--[[
    @file    LootService.luau
    @author  manik
    @date    2025

    @summary
    Server-owned one-open-per-run landmark chests and weighted loot.

    @description
    Chest prompts never accept a client-selected reward.  The server
    validates run membership and distance, rolls an allow-listed table,
    grants what fits in inventory, and permanently opens that chest for
    the current run.
]]

-- // VARIABLES // --

-- | Services | --
local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

-- | Modules | --
local Knit = require(ReplicatedStorage.Packages.Knit)

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
}

-- | State Management | --
local runStateService: any = nil
local inventoryService: any = nil
local worldService: any = nil
local openedChests: { [string]: boolean } = {}
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
	local mapsItems = ServerStorage.Assets:FindFirstChild("Assets maps items")
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
    @summary  Grant a rolled chest reward to a player.
    @param    player  Player
    @param    tier    string
    @returns  table
]]
local function grantLoot(player: Player, tier: string): { [string]: number }
	local lootTable = LOOT_TABLES[tier]
	local granted = {}
	local guaranteed = lootTable.guaranteed
	local guaranteedAmount = randomGenerator:NextInteger(guaranteed.min, guaranteed.max)
	local added = inventoryService:AddResource(player, guaranteed.resource, guaranteedAmount)
	if added > 0 then
		granted[guaranteed.resource] = added
	end

	local extra = chooseWeighted(lootTable.extras)
	local extraAmount = randomGenerator:NextInteger(extra.min, extra.max)
	local extraAdded = inventoryService:AddResource(player, extra.resource, extraAmount)
	if extraAdded > 0 then
		granted[extra.resource] = (granted[extra.resource] or 0) + extraAdded
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
	if typeof(chestId) ~= "string" or (tier ~= "Basic" and tier ~= "Gold") then
		return
	end
	if openedChests[chestId] or not runStateService:IsCurrentRun(capturedRunId) then
		return
	end
	if not runStateService:IsActive() or not runStateService:IsMember(player) then
		return
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
	openedChests[chestId] = true

	local granted = grantLoot(player, tier)
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
	for _, member in ipairs(runStateService:GetMembers()) do
		LootService.Client.ChestOpened:Fire(member, chest:GetPivot().Position, tier, granted, player.UserId)
	end
end

--[[
    @summary  Spawn all configured chests for a new run.
]]
local function spawnChests()
	openedChests = {}
	cooldowns = {}
	local landmarks = collectLandmarks()
	if #landmarks == 0 then
		warn("[LootService] No landmarks found for chest placement")
		return
	end

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

-- // INITIALIZATION // --

function LootService:KnitStart()
	runStateService = Knit.GetService("RunStateService")
	inventoryService = Knit.GetService("InventoryService")
	worldService = Knit.GetService("WorldService")

	runStateService.RunStarted:Connect(spawnChests)
	Players.PlayerRemoving:Connect(function(player)
		cooldowns[player] = nil
	end)
end

return LootService
