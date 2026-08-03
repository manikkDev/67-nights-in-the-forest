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

-- | Constants | --
local ITEMS_PATH = ServerStorage.Assets["Assets Items"]
local CHOP_RANGE = 10
local CHOP_COOLDOWN = 0.5
local TREE_HEALTH = 3
local WOOD_DROP_MIN = 3
local WOOD_DROP_MAX = 5
local WOOD_SCATTER_RADIUS = 4
local TREE_RESPAWN_TIME = 45
local FELL_TWEEN_DURATION = 1.2
local PICKUP_RANGE = 8
local AXE_TOOL_NAME = "Axe"
local TREE_MODEL_NAMES = { "Tree", "bigtree" }

-- | Objects | --
local HarvestService = Knit.CreateService({
	Name = "HarvestService",
	Client = {
		TreeChopped = Knit.CreateSignal(),
	},
})

-- | State | --
local worldService: any? = nil
local playerDataService: any? = nil
local treeRegistry: { [Model]: { health: number, part: BasePart, pivot: CFrame, prompt: ProximityPrompt, felled: boolean } } = {}
local chopCooldowns: { [Player]: number } = {}
local axeTemplate: Tool? = nil

-- // FUNCTIONS // --

--[[
    @summary  Build a wearable Axe Tool from the raw mesh Model asset.
    @desc     The source asset has no Handle/Tool wrapper, so the two
              meshes are welded together under a synthetic Handle.
    @returns  Tool?
]]
local function buildAxeTool(): Tool?
	local source = ITEMS_PATH:FindFirstChild(AXE_TOOL_NAME)
	if not source then
		warn("[HarvestService] Axe model not found in Assets Items")
		return nil
	end

	local handle = source:FindFirstChild("meshpart")
	local head = source:FindFirstChild("Union")
	if not handle or not head then
		warn("[HarvestService] Axe model missing expected mesh parts")
		return nil
	end

	local tool = Instance.new("Tool")
	tool.Name = AXE_TOOL_NAME
	tool.RequiresHandle = true

	local handleClone = handle:Clone()
	handleClone.Name = "Handle"
	handleClone.Anchored = false
	handleClone.CanCollide = false
	handleClone.Parent = tool

	local headClone = head:Clone()
	headClone.Anchored = false
	headClone.CanCollide = false
	headClone.Parent = handleClone

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = handleClone
	weld.Part1 = headClone
	weld.Parent = handleClone

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
    @param    position  Vector3  -- ground position of the felled tree
    @param    baseMap   Model    -- the cloned base-map to parent logs into
]]
local function spawnWoodDrops(position: Vector3, baseMap: Model)
	local source = ITEMS_PATH:FindFirstChild("Log")
	if not source then
		warn("[HarvestService] Log model not found in Assets Items")
		return
	end

	local count = math.random(WOOD_DROP_MIN, WOOD_DROP_MAX)
	for _ = 1, count do
		local log = source:Clone()
		local angle = math.random() * math.pi * 2
		local radius = math.random() * WOOD_SCATTER_RADIUS
		local offset = Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
		log:PivotTo(CFrame.new(position + offset))

		for _, descendant in ipairs(log:GetDescendants()) do
			if descendant:IsA("BasePart") then
				descendant.Anchored = true
				descendant.CanCollide = true
			end
		end

		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "PickupPrompt"
		prompt.ActionText = "Pick Up"
		prompt.ObjectText = "Wood"
		prompt.MaxActivationDistance = PICKUP_RANGE
		prompt.HoldDuration = 0
		prompt.Parent = log.PrimaryPart

		log.Parent = baseMap
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
	registry.prompt.Enabled = false

	local startPivot = registry.pivot
	local yaw = math.random() * math.pi * 2
	local fallAngle = Instance.new("NumberValue")
	fallAngle.Value = 0

	local function applyFall(degrees: number)
		local rad = math.rad(degrees)
		treeModel:PivotTo(
			startPivot * CFrame.Angles(0, yaw, 0) * CFrame.Angles(rad, 0, 0) * CFrame.Angles(0, -yaw, 0)
		)
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
		spawnWoodDrops(startPivot.Position, baseMap)
		task.delay(TREE_RESPAWN_TIME, function()
			treeModel:PivotTo(startPivot)
			registry.felled = false
			registry.health = TREE_HEALTH
			registry.prompt.Enabled = true
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

	local part = treeModel:FindFirstChildWhichIsA("BasePart", true)
	if not part then
		return
	end

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "ChopPrompt"
	prompt.ActionText = "Chop"
	prompt.ObjectText = "Tree"
	prompt.MaxActivationDistance = CHOP_RANGE + 2
	prompt.HoldDuration = 0.15
	prompt.Parent = part

	treeRegistry[treeModel] = {
		health = TREE_HEALTH,
		part = part,
		pivot = treeModel:GetPivot(),
		prompt = prompt,
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

	if (rootPart.Position - registry.part.Position).Magnitude > CHOP_RANGE then
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
local function tryPickup(logModel: Model, player: Player)
	if not logModel.Parent then
		return
	end

	local character = player.Character
	if not character then
		return
	end

	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart or not rootPart:IsA("BasePart") then
		return
	end

	if (rootPart.Position - logModel:GetPivot().Position).Magnitude > PICKUP_RANGE then
		return
	end

	playerDataService:UpdateData(player, function(data)
		data.Resources.Wood += 1
	end)
	logModel:Destroy()
end

--[[
    @summary  Route a global ProximityPrompt trigger to the matching
              chop or pickup handler.
    @param    prompt  ProximityPrompt  -- the triggered prompt
    @param    player  Player           -- the triggering player
]]
local function onPromptTriggered(prompt: ProximityPrompt, player: Player)
	if prompt.Name == "ChopPrompt" then
		for treeModel, registry in pairs(treeRegistry) do
			if registry.prompt == prompt then
				tryChop(treeModel, registry, player)
				return
			end
		end
	elseif prompt.Name == "PickupPrompt" then
		local logModel = prompt.Parent and prompt.Parent.Parent
		if logModel and logModel:IsA("Model") then
			tryPickup(logModel, player)
		end
	end
end

-- // INITIALIZATION // --

function HarvestService:KnitStart()
	worldService = Knit.GetService("WorldService")
	playerDataService = Knit.GetService("PlayerDataService")

	axeTemplate = buildAxeTool()
	registerAllTrees()

	ProximityPromptService.PromptTriggered:Connect(onPromptTriggered)

	Players.PlayerAdded:Connect(giveAxe)
	for _, player in ipairs(Players:GetPlayers()) do
		giveAxe(player)
	end

	print("[HarvestService] Initialised — chop/pickup wired")
end

return HarvestService
