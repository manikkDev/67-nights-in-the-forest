--[[
    @file    HarvestService.luau
    @author  manik
    @date    2025

    @summary
    Server-authoritative tree chopping, felling, and wood pickup.

    @description
    Scans the cloned base-map for pre-placed Tree/bigtree models and
    wires a ProximityPrompt onto each.  Validates chop requests against
    range, cooldown, and an equipped Axe tool before decrementing a
    per-tree health counter.  A depleted tree tweens over mathematically
    (no physics), drops Log pickups, and respawns after a delay.  Also
    issues every player an Axe tool built from the ServerStorage mesh
    asset, since the source asset has no Handle/Tool wrapper.

    @exports
    - Knit Signal: TreeChopped(position: Vector3)  (server -> client, VFX hook)
    - Knit Remote: RequestChop(player)              (client -> server, click-to-chop)
]]

-- // VARIABLES // --

-- | Services | --
local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ProximityPromptService = game:GetService("ProximityPromptService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

-- | Modules | --
local Knit = require(ReplicatedStorage.Packages.Knit)
local Constants = require(ReplicatedStorage.Shared.Constants)

-- | Objects | --
local HarvestService = Knit.CreateService({
	Name = "HarvestService",
	Client = {
		TreeChopped = Knit.CreateSignal(),
	},
})

-- | Configuration | --
local TREE_HEALTH = 6
local CHOP_COOLDOWN = 0.5
local CHOP_RANGE = 12
local FELL_TWEEN_DURATION = 1.2
local FELL_LIE_DURATION = 3
local FELL_FADE_DURATION = 2
local TREE_RESPAWN_TIME = 45
local WOOD_SCATTER_RADIUS = 4
local SMALL_WOOD_DROP_MIN = 3
local SMALL_WOOD_DROP_MAX = 5
local BIG_WOOD_DROP_MIN = 5
local BIG_WOOD_DROP_MAX = 8
local PICKUP_RANGE = 12
local LOG_LIFETIME = 300
local ITEMS_PATH = ServerStorage.Assets[Constants.ITEMS_PATH]
local TREE_MODEL_NAMES = { "Tree", "bigtree" }
local AXE_TOOL_NAME = "Axe"

-- | State Management | --
local worldService: any = nil
local inventoryService: any = nil
local spawnService: any = nil
local axeTemplate: Tool? = nil
local treeRegistry: { [Model]: { health: number, part: { Position: Vector3 }, pivot: CFrame, felled: boolean } } = {}
local chopCooldowns: { [Player]: number } = {}

-- // FUNCTIONS // --

--[[
    @summary  Build a wearable Axe Tool by cloning the pre-configured
              axe MeshPart from the R6 Axe Animations asset.
    @desc     The source MeshPart already has the correct MeshId,
              TextureID, Size, and Material.  We clone it as the
              Tool's Handle and set the grip so the hand holds the
              lower portion of the shaft.
    @returns  Tool?
]]
local function buildAxeTool(): Tool?
	local animModel = ITEMS_PATH:FindFirstChild("AxeAnimations")
	if not animModel then
		warn("[HarvestService] AxeAnimations model not found in Assets Items")
		return nil
	end

	local r6Folder = animModel:FindFirstChild("R6 Axe Animations")
	if not r6Folder then
		warn("[HarvestService] R6 Axe Animations folder not found")
		return nil
	end

	local sourceAxe = r6Folder:FindFirstChild("Axe")
	if not sourceAxe or not sourceAxe:IsA("MeshPart") then
		warn("[HarvestService] Axe MeshPart not found in R6 Axe Animations")
		return nil
	end

	local tool = Instance.new("Tool")
	tool.Name = AXE_TOOL_NAME
	tool.RequiresHandle = true

	-- The axe mesh has a built-in rotation of ~91° on Z and ~25° on Y,
	-- which means the mesh's long axis (Y, 4 studs) is actually pointing
	-- along the world X axis after the part's rotation is applied.
	-- For a natural R15 grip, we need the hand to hold the bottom of the
	-- shaft with the blade pointing up and slightly forward.
	-- GripPos: hand sits 1.5 studs along the mesh's local Y (shaft bottom)
	-- GripUp: mesh local Y maps to tool Up (blade points up)
	-- GripForward: mesh local -Z maps to tool Forward (blade faces forward)
	-- GripRight: mesh local X maps to tool Right
	tool.GripPos = Vector3.new(0, -1.5, 0)
	tool.GripUp = Vector3.new(0, 1, 0)
	tool.GripForward = Vector3.new(1, 0, 0)
	tool.GripRight = Vector3.new(0, 0, 1)

	local handle = sourceAxe:Clone()
	handle.Name = "Handle"
	handle.CanCollide = false
	handle.Anchored = false
	handle.Transparency = 0
	-- Remove any children from the source (Animation instances, Motor6Ds)
	for _, child in ipairs(handle:GetChildren()) do
		child:Destroy()
	end
	handle.Parent = tool

	return tool
end

--[[
    @summary  Grant the Axe tool to a player's Backpack and StarterGear
              so it persists across respawns.
    @param    player  Player  -- the Roblox player
]]
local function giveAxe(player: Player)
	if not axeTemplate then
		return
	end
	if spawnService and not spawnService:IsPlayerSpawned(player) then
		return
	end

	local backpack = player:WaitForChild("Backpack")
	if not backpack:FindFirstChild(AXE_TOOL_NAME) then
		local clone = axeTemplate:Clone()
		clone.Parent = backpack
	end

	local starterGear = player:WaitForChild("StarterGear")
	if not starterGear:FindFirstChild(AXE_TOOL_NAME) then
		local clone = axeTemplate:Clone()
		clone.Parent = starterGear
	end
end

--[[
    @summary  Spawn a short-lived wood-chip particle burst at a position.
    @param    position  Vector3  -- world position of the chop impact
]]
local function spawnChopVFX(position: Vector3)
	local anchor = Instance.new("Part")
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.Position = position
	anchor.Parent = workspace

	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = "rbxasset://textures/particles/smoke_main.dds"
	emitter.Color = ColorSequence.new(Color3.fromRGB(120, 80, 45))
	emitter.Lifetime = NumberRange.new(0.4, 0.8)
	emitter.Speed = NumberRange.new(6, 12)
	emitter.SpreadAngle = Vector2.new(45, 45)
	emitter.Size = NumberSequence.new(0.3, 0.05)
	emitter.Rate = 0
	emitter.Parent = anchor

	emitter:Emit(14)
	Debris:AddItem(anchor, 2)
end

--[[
    @summary  Scatter Log pickups around a felled tree's base and wire
              a pickup ProximityPrompt on each.
    @param    position    Vector3  -- ground position of the felled tree
    @param    baseMap     Model    -- the cloned base-map to parent logs into
    @param    isBigTree   boolean  -- true for bigtree models
]]
local function spawnWoodDrops(position: Vector3, baseMap: Model, isBigTree: boolean)
	local source = ITEMS_PATH:FindFirstChild("Log")
	if not source then
		warn("[HarvestService] Log model not found in Assets Items")
		return
	end

	local dropMin = if isBigTree then BIG_WOOD_DROP_MIN else SMALL_WOOD_DROP_MIN
	local dropMax = if isBigTree then BIG_WOOD_DROP_MAX else SMALL_WOOD_DROP_MAX
	local count = math.random(dropMin, dropMax)
	for _ = 1, count do
		local log = source:Clone()
		local angle = math.random() * math.pi * 2
		local radius = math.random() * WOOD_SCATTER_RADIUS
		local offset = Vector3.new(math.cos(angle) * radius, 2, math.sin(angle) * radius)
		log:PivotTo(CFrame.new(position + offset) * CFrame.Angles(0, math.random() * math.pi * 2, 0))

		for _, descendant in ipairs(log:GetDescendants()) do
			if descendant:IsA("BasePart") then
				descendant.Anchored = false
				descendant.CanCollide = true
			end
		end

		-- Apply a random impulse so logs scatter naturally
		if log.PrimaryPart then
			local impulseDir = Vector3.new(math.random() - 0.5, 0.3, math.random() - 0.5).Unit
			log.PrimaryPart:ApplyImpulse(impulseDir * log.PrimaryPart.AssemblyMass * 8)
		end

		log:SetAttribute("PickupResource", "Wood")

		log.Parent = baseMap
		Debris:AddItem(log, LOG_LIFETIME)
	end
end

--[[
    @summary  Tween a felled tree over mathematically, then drop wood
              and schedule its respawn.
    @param    treeModel  Model   -- the tree to fell
    @param    baseMap    Model   -- the cloned base-map, for wood drops
]]
local function fellTree(treeModel: Model, baseMap: Model)
	local registry = treeRegistry[treeModel]
	if not registry or registry.felled then
		return
	end
	registry.felled = true

	local startPivot = registry.pivot

	-- Find the lowest point of the tree so we can rotate around its base,
	-- not its geometric center (which causes floating).
	local lowestY = math.huge
	for _, desc in ipairs(treeModel:GetDescendants()) do
		if desc:IsA("BasePart") then
			local partBottom = desc.Position.Y - desc.Size.Y / 2
			if partBottom < lowestY then
				lowestY = partBottom
			end
		end
	end
	if lowestY == math.huge then
		lowestY = startPivot.Position.Y
	end

	-- Base rotation point at ground level directly below the tree pivot
	local basePos = Vector3.new(startPivot.Position.X, lowestY, startPivot.Position.Z)
	local baseCFrame = CFrame.new(basePos)

	local yaw = math.random() * math.pi * 2
	local fallAngle = Instance.new("NumberValue")
	fallAngle.Value = 0

	local function applyFall(degrees: number)
		local rad = math.rad(degrees)
		local rotation = CFrame.Angles(0, yaw, 0) * CFrame.Angles(rad, 0, 0) * CFrame.Angles(0, -yaw, 0)
		-- Rotate the tree's original pivot around the base point:
		-- translate to base, apply rotation, translate back
		treeModel:PivotTo(baseCFrame * rotation * baseCFrame:Inverse() * startPivot)
	end

	fallAngle:GetPropertyChangedSignal("Value"):Connect(function()
		applyFall(fallAngle.Value)
	end)

	local tween = TweenService:Create(
		fallAngle,
		TweenInfo.new(FELL_TWEEN_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ Value = 88 }
	)

	tween.Completed:Connect(function()
		fallAngle:Destroy()
		spawnWoodDrops(startPivot.Position, baseMap, treeModel.Name == "bigtree")

		-- Lie on the ground for a moment, then fade out smoothly
		task.delay(FELL_LIE_DURATION, function()
			-- Collect all parts and their original transparency for fade-out
			local parts = {}
			for _, desc in ipairs(treeModel:GetDescendants()) do
				if desc:IsA("BasePart") then
					table.insert(parts, { part = desc, originalTransparency = desc.Transparency })
				end
			end

			local fadeValue = Instance.new("NumberValue")
			fadeValue.Value = 0
			fadeValue:GetPropertyChangedSignal("Value"):Connect(function()
				for _, entry in ipairs(parts) do
					entry.part.Transparency = entry.originalTransparency + fadeValue.Value * (1 - entry.originalTransparency)
				end
			end)

			local actualFadeTween = TweenService:Create(
				fadeValue,
				TweenInfo.new(FELL_FADE_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{ Value = 1 }
			)

			actualFadeTween.Completed:Connect(function()
				fadeValue:Destroy()
				-- Unparent the tree to hide it during respawn timer
				treeModel.Parent = nil
				-- Restore transparency so the tree is visible when respawned
				for _, entry in ipairs(parts) do
					if entry.part then
						entry.part.Transparency = entry.originalTransparency
					end
				end
				task.delay(TREE_RESPAWN_TIME, function()
					if not treeModel or not treeModel:GetChildren()[1] then return end
					if not baseMap or not baseMap.Parent then return end
					treeModel:PivotTo(startPivot)
					treeModel.Parent = baseMap
					registry.felled = false
					registry.health = TREE_HEALTH
				end)
			end)

			actualFadeTween:Play()
		end)
	end)

	tween:Play()
end

--[[
    @summary  Wire a ProximityPrompt onto a single tree model and
              register it for chop tracking.
    @param    treeModel  Model  -- a Tree/bigtree descendant of base-map
]]
local function registerTree(treeModel: Model)
	if treeRegistry[treeModel] then
		return
	end

	-- Use the tree's pivot position (base of trunk at ground level)
	-- for range checks. This is more reliable than finding the lowest
	-- part, which can be a tiny root far from the trunk center.
	local pivot = treeModel:GetPivot()

	treeRegistry[treeModel] = {
		health = TREE_HEALTH,
		part = { Position = pivot.Position },
		pivot = pivot,
		felled = false,
	}
end

--[[
    @summary  Scan the base-map for Tree/bigtree descendants and
              register each one for chopping.  Retries until the
              base-map has finished loading.
]]
local function registerAllTrees()
	if not worldService then
		task.defer(registerAllTrees)
		return
	end
	local baseMap = worldService:GetBaseMap()
	if not baseMap then
		task.defer(registerAllTrees)
		return
	end
	if not worldService:IsForestReady() then
		task.defer(registerAllTrees)
		return
	end

	local registeredCount = 0
	for _, descendant in ipairs(baseMap:GetDescendants()) do
		if descendant:IsA("Model") and table.find(TREE_MODEL_NAMES, descendant.Name) then
			registerTree(descendant)
			registeredCount += 1
		end
	end

	print("[HarvestService] Registered", registeredCount, "trees")
end

--[[
    @summary  Validate and process a chop attempt against one tree.
    @param    treeModel  Model   -- the tree being chopped
    @param    registry   table   -- the tree's tracked state
    @param    player     Player  -- the chopping player
]]
local function tryChop(treeModel: Model, registry, player: Player)
	if registry.felled then
		return
	end

	local character = player.Character
	if not character then
		return
	end

	local axe = character:FindFirstChild(AXE_TOOL_NAME)
	if not axe or not axe:IsA("Tool") then
		return
	end

	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart or not rootPart:IsA("BasePart") then
		return
	end

	local dist = (rootPart.Position - registry.part.Position).Magnitude
	if dist > CHOP_RANGE then
		return
	end

	local now = os.clock()
	if chopCooldowns[player] and (now - chopCooldowns[player]) < CHOP_COOLDOWN then
		return
	end
	chopCooldowns[player] = now

	registry.health -= 1
	spawnChopVFX(registry.part.Position)
	HarvestService.Client.TreeChopped:Fire(player, registry.part.Position)

	if registry.health <= 0 then
		if not worldService then
			return
		end
		local baseMap = worldService:GetBaseMap()
		if baseMap then
			fellTree(treeModel, baseMap)
		end
	end
end

--[[
    @summary  Validate and process a wood pickup attempt.
    @param    logModel  Model   -- the dropped Log instance
    @param    player    Player  -- the picking player
]]
local function tryPickup(logModel: Model, player: Player): boolean
	if not logModel.Parent then
		return false
	end
	if inventoryService and inventoryService:IsModelDragged(logModel) then
		return false
	end

	local character = player.Character
	if not character then
		return false
	end

	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart or not rootPart:IsA("BasePart") then
		return false
	end

	if (rootPart.Position - logModel:GetPivot().Position).Magnitude > PICKUP_RANGE then
		return false
	end

	if not inventoryService then
		return false
	end
	local added = inventoryService:AddResource(player, "Wood", 1)
	if added <= 0 then
		return false
	end
	logModel:Destroy()
	return true
end

--[[
    @summary  Route a global ProximityPrompt trigger to the matching
              chop or pickup handler.
    @param    prompt  ProximityPrompt  -- the triggered prompt
    @param    player  Player           -- the triggering player
]]
local function onPromptTriggered(prompt: ProximityPrompt, player: Player)
	if prompt.Name == "PickupPrompt" then
		local logModel = prompt.Parent and prompt.Parent.Parent
		if logModel and logModel:IsA("Model") then
			tryPickup(logModel, player)
		end
	end
end

--[[
    @summary  Find the nearest registered tree within CHOP_RANGE of
              the player's character root part.
    @param    player  Player  -- the chopping player
    @returns  Model, table  -- the tree model and its registry entry, or nil
]]
local function findNearestTree(player: Player)
	local character = player.Character
	if not character then
		return nil, nil
	end

	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart or not rootPart:IsA("BasePart") then
		return nil, nil
	end

	local nearestModel: Model? = nil
	local nearestRegistry = nil
	local nearestDist = math.huge

	for treeModel, registry in pairs(treeRegistry) do
		if not registry.felled then
			local dist = (rootPart.Position - registry.part.Position).Magnitude
			if dist < nearestDist and dist <= CHOP_RANGE then
				nearestDist = dist
				nearestModel = treeModel
				nearestRegistry = registry
			end
		end
	end

	return nearestModel, nearestRegistry
end

--[[
    @summary  Publish a short, simple R15 tool-slash Animation to
              ReplicatedStorage so the client can play the axe swing.
    @desc     The default R15 tool-slash (asset 522635514) is a quick,
              minimal overhead strike that works for an axe/pickaxe
              without the exaggerated motion of a sword combo.
]]
local function publishAxeAnimation()
	local old = ReplicatedStorage:FindFirstChild("AxeStrikeKeyframeSequence")
	if old then
		old:Destroy()
	end

	local anim = Instance.new("Animation")
	anim.Name = "AxeStrikeAnimation"
	anim.AnimationId = "rbxassetid://522635514"
	anim.Parent = ReplicatedStorage

	print("[HarvestService] Axe strike animation published to ReplicatedStorage")
end

-- // INITIALIZATION // --

function HarvestService:KnitStart()
	worldService = Knit.GetService("WorldService")
	inventoryService = Knit.GetService("InventoryService")
	spawnService = Knit.GetService("SpawnService")

	axeTemplate = buildAxeTool()
	publishAxeAnimation()
	registerAllTrees()

	ProximityPromptService.PromptTriggered:Connect(onPromptTriggered)

	local spawnServicePublic = spawnService
	local function tryGiveAxe(player: Player)
		if spawnServicePublic and spawnServicePublic:IsPlayerSpawned(player) then
			giveAxe(player)
		end
	end

	Players.PlayerAdded:Connect(tryGiveAxe)
	for _, player in ipairs(Players:GetPlayers()) do
		tryGiveAxe(player)
	end

	-- Give the axe immediately when a player teleports to the game map.
	if spawnService then
		spawnService.PlayerSpawned:Connect(function(player: Player)
			giveAxe(player)
		end)
	end

	print("[HarvestService] Initialised — chop/pickup wired")
end

Players.PlayerRemoving:Connect(function(player)
	chopCooldowns[player] = nil
end)

function HarvestService.Client:RequestPickup(player: Player, model: Model): boolean
	local resourceName = model and model:IsA("Model") and (model:GetAttribute("Resource") or model:GetAttribute("PickupResource") or model:GetAttribute("ForageResource"))
	if not model or not model:IsA("Model") or not model.Parent then
		return false
	end
	if resourceName ~= "Wood" then
		return false
	end
	if not worldService or not inventoryService then
		return false
	end
	local baseMap = worldService:GetBaseMap()
	if not baseMap or not model:IsDescendantOf(baseMap) then
		return false
	end
	local ok = tryPickup(model, player)
	return ok
end

-- // CLIENT REMOTES // --

--[[
    @summary  Client-to-server remote for click-to-chop.
    @desc     Finds the nearest tree within range and processes the chop.
    @param    player  Player  -- the requesting player (injected by Knit)
]]
function HarvestService.Client:RequestChop(player: Player)
	local treeModel, registry = findNearestTree(player)
	if treeModel and registry then
		tryChop(treeModel, registry, player)
	end
end

return HarvestService
