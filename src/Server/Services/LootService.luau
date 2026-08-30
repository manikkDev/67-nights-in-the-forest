--[[
    @file    LootService.luau
    @author  manik
    @date    2025

    @summary
    Server-owned landmark chests, cave chests, and weighted loot.

    @description
    Chest prompts never accept a client-selected reward.  The server
    validates run membership and distance, rolls an allow-listed table,
    grants what fits in inventory, and marks the chest as opened.

    Landmark chests are one-open-per-run (global).  Cave chests are
    per-player — each member can open them once to get their own loot.
    Cave chests can grant Tools (e.g. Spear) in addition to resources.
]]

-- // VARIABLES // --

-- | Services | --
local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

-- | Modules | --
local Knit = require(ReplicatedStorage.Packages.Knit)
local ServerRole = require(ReplicatedStorage.Shared.ServerRole)

-- | Objects | --
local LootService = Knit.CreateService({
	Name = "LootService",
	Client = {
		ChestOpened = Knit.CreateSignal(),
	},
})

-- | Configuration | --
local OPEN_RANGE = 12
local OPEN_COOLDOWN = 0.5
local BASIC_CHEST_COUNT = 6
local GOLD_CHEST_COUNT = 2
local LANDMARK_NAMES = { "cabin", "Hunters Lodge", "Tower", "Treehouse", "Crashed Plane", "modern-house" }

-- Chest open sound (wooden chest open/close SFX from Creator Store).
local CHEST_OPEN_SOUND_ID = "rbxassetid://9120873624"

local LOOT_TABLES = {
	Basic = {
		guaranteed = { resource = "Scrap", min = 1, max = 3 },
		extras = {
			{ resource = "Coal", min = 1, max = 2, weight = 30 },
			{ resource = "Berries", min = 1, max = 2, weight = 25 },
			{ resource = "Mushrooms", min = 1, max = 2, weight = 20 },
			{ resource = "RawMeat", min = 1, max = 1, weight = 15 },
			{ resource = "Bandage", min = 1, max = 1, weight = 10 },
		},
	},
	Gold = {
		guaranteed = { resource = "Scrap", min = 4, max = 7 },
		extras = {
			{ resource = "Bandage", min = 1, max = 2, weight = 30 },
			{ resource = "Coal", min = 2, max = 4, weight = 30 },
			{ resource = "CookedMeat", min = 1, max = 2, weight = 25 },
			{ resource = "Scrap", min = 2, max = 4, weight = 15 },
		},
	},
	-- Cave chests: per-player, can grant Tools + guaranteed Bandage.
	CaveDino = {
		tool = "Spear",
		extras = {
			{ resource = "Bandage", min = 1, max = 1, weight = 100 },
		},
	},
}

-- Cave chest placement config: which cave gets which chest tier.
local CAVE_CHESTS = {
	{ caveId = "Dino", tier = "CaveDino", displayName = "Dino Cave Chest" },
}

-- | State Management | --
local runStateService: any = nil
local inventoryService: any = nil
local worldService: any = nil
local rescueService: any = nil
local combatService: any = nil
local openedChests: { [string]: boolean } = {}
local openedCaveChests: { [Player]: { [string]: boolean } } = {}
local cooldowns: { [Player]: number } = {}
local randomGenerator = Random.new()

-- // FUNCTIONS // --

-- | Private | --

--[[
    @summary  Select one weighted loot entry from a tier table.
    @param    entries  table
    @returns  table
]]
local function chooseWeighted(entries)
	local totalWeight = 0
	for _, entry in ipairs(entries) do
		totalWeight += entry.weight
	end
	local roll = randomGenerator:NextNumber(0, totalWeight)
	local cursor = 0
	for _, entry in ipairs(entries) do
		cursor += entry.weight
		if roll <= cursor then
			return entry
		end
	end
	return entries[#entries]
end

--[[
    @summary  Return a usable chest model from the stored source asset.
    @param    tier  string
    @returns  Model?
]]
local function cloneChest(tier: string): Model?
	local assets = ServerStorage:FindFirstChild("Assets")
	local mapsItems = assets and assets:FindFirstChild("Assets maps items")
	local assetName = if tier == "Gold" then "Gold-chest" else "basic-chest"
	local source = mapsItems and mapsItems:FindFirstChild(assetName)
	if not source then
		return nil
	end

	if source:IsA("Model") then
		return source:Clone()
	end
	if source:IsA("BasePart") then
		local model = Instance.new("Model")
		local part = source:Clone()
		part.Name = "ChestBody"
		part.Parent = model
		model.PrimaryPart = part
		return model
	end
	return nil
end

--[[
    @summary  Find distinct landmarks to anchor chest positions.
    @returns  { Model }
]]
local function collectLandmarks(): { Model }
	local baseMap = worldService and worldService:GetBaseMap()
	local landmarks = {}
	if not baseMap then
		return landmarks
	end
	for _, child in ipairs(baseMap:GetChildren()) do
		if child:IsA("Model") and table.find(LANDMARK_NAMES, child.Name) then
			table.insert(landmarks, child)
		end
	end
	return landmarks
end

--[[
    @summary  Resolve a grounded position near a landmark.
    @param    landmark  Model
    @param    index     number
    @returns  CFrame
]]
local function chestCFrame(landmark: Model, index: number): CFrame
	local pivot = landmark:GetPivot()
	local angle = index * 2.399963
	local candidate = pivot.Position + Vector3.new(math.cos(angle) * 10, 30, math.sin(angle) * 10)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { worldService:GetBaseMap() }
	local result = workspace:Raycast(candidate, Vector3.new(0, -80, 0), params)
	local position = if result then result.Position + Vector3.new(0, 2, 0) else pivot.Position + Vector3.new(0, 3, 0)
	return CFrame.new(position) * CFrame.Angles(0, angle, 0)
end

--[[
    @summary  Play a chest open sound at the chest position.
    @param    position  Vector3
]]
local function playChestSound(position: Vector3)
	local soundPart = Instance.new("Part")
	soundPart.Anchored = true
	soundPart.CanCollide = false
	soundPart.CanQuery = false
	soundPart.CanTouch = false
	soundPart.Transparency = 1
	soundPart.Size = Vector3.new(0.2, 0.2, 0.2)
	soundPart.Position = position
	soundPart.Parent = workspace

	local sound = Instance.new("Sound")
	sound.SoundId = CHEST_OPEN_SOUND_ID
	sound.Volume = 1
	sound.Parent = soundPart
	sound:Play()

	Debris:AddItem(soundPart, 3)
end

--[[
    @summary  Spawn a golden particle burst and light flash at a position.
    @param    position  Vector3
]]
local function spawnChestVFX(position: Vector3)
	local anchor = Instance.new("Part")
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.Position = position + Vector3.new(0, 1, 0)
	anchor.Parent = workspace

	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	emitter.Color = ColorSequence.new(Color3.fromRGB(255, 215, 120))
	emitter.Lifetime = NumberRange.new(0.4, 0.8)
	emitter.Speed = NumberRange.new(6, 12)
	emitter.SpreadAngle = Vector2.new(45, 45)
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1.5),
		NumberSequenceKeypoint.new(1, 0.1),
	})
	emitter.Rate = 0
	emitter.Parent = anchor
	emitter:Emit(30)

	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 215, 120)
	light.Brightness = 5
	light.Range = 15
	light.Parent = anchor

	TweenService:Create(light, TweenInfo.new(0.6, Enum.EasingStyle.Quad), { Brightness = 0 }):Play()

	Debris:AddItem(anchor, 2)
end

--[[
    @summary  Bounce-scale a chest model to simulate opening.
    @param    chest  Model
]]
local function animateChestOpen(chest: Model)
	local primary = chest.PrimaryPart or chest:FindFirstChildWhichIsA("BasePart", true)
	if not primary then
		return
	end
	local originalSize = primary.Size
	local capturedRunId = runStateService:GetRunId()
	TweenService:Create(primary, TweenInfo.new(0.2, Enum.EasingStyle.Bounce, Enum.EasingDirection.Out), {
		Size = originalSize * 1.15,
	}):Play()
	task.delay(0.2, function()
		if runStateService:IsCurrentRun(capturedRunId) and primary.Parent then
			TweenService:Create(primary, TweenInfo.new(0.15, Enum.EasingStyle.Quad), {
				Size = originalSize,
			}):Play()
		end
	end)
end

--[[
    @summary  Grant a rolled chest reward to a player.
    @param    player  Player
    @param    tier    string
    @returns  table
]]
local function grantLoot(player: Player, tier: string): { [string]: number }
	local lootTable = LOOT_TABLES[tier]
	local granted = {}

	-- Tool grant (e.g. Spear from cave chests).
	if lootTable.tool and combatService then
		local template = combatService:GetSpearTemplate()
		if template and lootTable.tool == "Spear" then
			local backpack = player:FindFirstChild("Backpack")
			if backpack and not backpack:FindFirstChild("Spear") then
				template:Clone().Parent = backpack
				granted["Spear"] = 1
			end
		end
	end

	-- Guaranteed resource (landmark chests only).
	if lootTable.guaranteed then
		local guaranteed = lootTable.guaranteed
		local guaranteedAmount = randomGenerator:NextInteger(guaranteed.min, guaranteed.max)
		local added = inventoryService:AddResource(player, guaranteed.resource, guaranteedAmount)
		if added > 0 then
			granted[guaranteed.resource] = added
		end
	end

	-- Weighted extra.
	if lootTable.extras then
		local extra = chooseWeighted(lootTable.extras)
		local extraAmount = randomGenerator:NextInteger(extra.min, extra.max)
		local extraAdded = inventoryService:AddResource(player, extra.resource, extraAmount)
		if extraAdded > 0 then
			granted[extra.resource] = (granted[extra.resource] or 0) + extraAdded
		end
	end
	return granted
end

--[[
    @summary  Validate and open one live chest for a player.
    @param    player  Player
    @param    chest   Model
]]
local function openChest(player: Player, chest: Model)
	local chestId = chest:GetAttribute("ChestId")
	local tier = chest:GetAttribute("LootTier")
	local capturedRunId = chest:GetAttribute("RunId")
	local isCaveChest = chest:GetAttribute("IsCaveChest") == true
	if typeof(chestId) ~= "string" or not LOOT_TABLES[tier] then
		return
	end
	if not runStateService:IsCurrentRun(capturedRunId) then
		return
	end
	if not runStateService:IsActive() or not runStateService:IsMember(player) then
		return
	end

	-- Per-player open check for cave chests; global for landmark chests.
	if isCaveChest then
		openedCaveChests[player] = openedCaveChests[player] or {}
		if openedCaveChests[player][chestId] then
			return
		end
	else
		if openedChests[chestId] then
			return
		end
	end

	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not rootPart or not rootPart:IsA("BasePart") or not humanoid or humanoid.Health <= 0 then
		return
	end
	if (rootPart.Position - chest:GetPivot().Position).Magnitude > OPEN_RANGE then
		return
	end

	local now = os.clock()
	if cooldowns[player] and now - cooldowns[player] < OPEN_COOLDOWN then
		return
	end
	cooldowns[player] = now

	-- Mark as opened.
	if isCaveChest then
		openedCaveChests[player][chestId] = true
	else
		openedChests[chestId] = true
		chest:SetAttribute("Opened", true)
		local prompt = chest:FindFirstChildWhichIsA("ProximityPrompt", true)
		if prompt then
			prompt.Enabled = false
		end
		for _, descendant in ipairs(chest:GetDescendants()) do
			if descendant:IsA("BasePart") then
				descendant.Color = descendant.Color:Lerp(Color3.fromRGB(65, 65, 65), 0.35)
			end
		end
	end

	local granted = grantLoot(player, tier)
	local chestPosition = chest:GetPivot().Position

	-- VFX + sound + animation.
	animateChestOpen(chest)
	spawnChestVFX(chestPosition)
	playChestSound(chestPosition)

	-- Fire only to the opener.
	LootService.Client.ChestOpened:Fire(player, chestPosition, tier, granted, player.UserId)
end

--[[
    @summary  Spawn all configured landmark chests for a new run.
]]
local function spawnChests()
	openedChests = {}
	cooldowns = {}
	openedCaveChests = {}
	local landmarks = collectLandmarks()
	if #landmarks == 0 then
		warn("[LootService] No landmarks found for chest placement")
	else
		local folder = Instance.new("Folder")
		folder.Name = "Chests"
		folder.Parent = runStateService:GetRuntimeFolder()
		local total = BASIC_CHEST_COUNT + GOLD_CHEST_COUNT
		for index = 1, total do
			local tier = if index > BASIC_CHEST_COUNT then "Gold" else "Basic"
			local chest = cloneChest(tier)
			if not chest then
				continue
			end
			chest.Name = tier .. "Chest"
			chest:SetAttribute("ChestId", HttpService:GenerateGUID(false))
			chest:SetAttribute("LootTier", tier)
			chest:SetAttribute("RunId", runStateService:GetRunId())
			chest:SetAttribute("Opened", false)
			chest:SetAttribute("IsCaveChest", false)
			for _, descendant in ipairs(chest:GetDescendants()) do
				if descendant:IsA("BasePart") then
					descendant.Anchored = true
				end
			end
			chest.Parent = folder
			local landmark = landmarks[((index - 1) % #landmarks) + 1]
			chest:PivotTo(chestCFrame(landmark, index))

			local anchor = chest.PrimaryPart or chest:FindFirstChildWhichIsA("BasePart", true)
			if anchor then
				local prompt = Instance.new("ProximityPrompt")
				prompt.Name = "OpenChest"
				prompt.ActionText = "Open"
				prompt.ObjectText = tier .. " Chest"
				prompt.MaxActivationDistance = OPEN_RANGE
				prompt.HoldDuration = 0.7
				prompt.RequiresLineOfSight = true
				prompt.Parent = anchor
				prompt.Triggered:Connect(function(player)
					openChest(player, chest)
				end)
			end
		end
	end
end

--[[
    @summary  Spawn cave chests inside designated caves for a new run.
]]
local function spawnCaveChests()
	if not rescueService then
		return
	end
	local folder = workspace:FindFirstChild("CaveChests")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "CaveChests"
		folder.Parent = runStateService:GetRuntimeFolder()
	end

	for _, config in ipairs(CAVE_CHESTS) do
		local center = rescueService:GetCaveCenter(config.caveId)
		if not center then
			warn("[LootService] No cave center found for", config.caveId)
			continue
		end

		local chest = cloneChest("Basic")
		if not chest then
			continue
		end
		chest.Name = config.caveId .. "CaveChest"
		chest:SetAttribute("ChestId", HttpService:GenerateGUID(false))
		chest:SetAttribute("LootTier", config.tier)
		chest:SetAttribute("RunId", runStateService:GetRunId())
		chest:SetAttribute("Opened", false)
		chest:SetAttribute("IsCaveChest", true)

		for _, descendant in ipairs(chest:GetDescendants()) do
			if descendant:IsA("BasePart") then
				descendant.Anchored = true
				descendant.CanCollide = true
			end
		end

		-- Place inside the cave: right side, toward the back, on the floor.
		-- Cave floor top is at center.Y + 0.5 (1-stud-thick floor at center.Y).
		-- basic-chest native size is ~3.36 x 2.60 x 1.77, half-height ~1.3.
		local chestHeight = 2.6
		local floorTop = center.Y + 1.0
		local position = Vector3.new(center.X + 10, floorTop + chestHeight * 0.5, center.Z - 3)
		chest:PivotTo(CFrame.new(position) * CFrame.Angles(0, math.rad(-90), 0))
		chest.Parent = folder

		local anchor = chest.PrimaryPart or chest:FindFirstChildWhichIsA("BasePart", true)
		if anchor then
			local prompt = Instance.new("ProximityPrompt")
			prompt.Name = "OpenChest"
			prompt.ActionText = "Open"
			prompt.ObjectText = config.displayName
			prompt.MaxActivationDistance = OPEN_RANGE
			prompt.HoldDuration = 0.7
			prompt.RequiresLineOfSight = false
			prompt.Parent = anchor
			prompt.Triggered:Connect(function(player)
				openChest(player, chest)
			end)
		end
	end
end

-- // INITIALIZATION // --

function LootService:KnitStart()
	if not ServerRole.IsGameServer() then return end
	runStateService = Knit.GetService("RunStateService")
	inventoryService = Knit.GetService("InventoryService")
	worldService = Knit.GetService("WorldService")
	rescueService = Knit.GetService("RescueService")
	combatService = Knit.GetService("CombatService")

	runStateService.RunStarted:Connect(function(runId)
		spawnChests()
		-- Defer cave chest spawning so RescueService.buildCaves() runs first
		-- (it also defers on RunStarted via task.defer).
		task.defer(function()
			task.wait(0.1)
			if runStateService:IsCurrentRun(runId) then
				spawnCaveChests()
			end
		end)
	end)
	Players.PlayerRemoving:Connect(function(player)
		cooldowns[player] = nil
		openedCaveChests[player] = nil
	end)
end

return LootService
