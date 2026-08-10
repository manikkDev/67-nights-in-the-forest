--[[
    @file    ForageService.luau
    @author  manik
    @date    2025

    @summary
    Server-authoritative Berries/Mushrooms foraging and eating.

    @description
    Scatters pickup-able Berries (reusing the existing `Carrot` mesh as
    the closest available forage-food art) and Mushrooms (a small
    procedurally-built cap+stem prop, since no mushroom mesh exists in
    the asset library yet) near trees across the base-map.  Players pick
    them up via ProximityPrompt into their inventory, then eat them from
    the Inventory UI to restore Hunger.  Respawns on a timer, mirroring
    HarvestService's tree/log pattern.

    @exports
    - Knit Remote: RequestEat(resourceName)  -> boolean  (client -> server)
]]

-- // VARIABLES // --

-- | Services | --
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ProximityPromptService = game:GetService("ProximityPromptService")

-- | Modules | --
local Knit = require(ReplicatedStorage.Packages.Knit)
local Constants = require(ReplicatedStorage.Shared.Constants)

-- | Objects | --
local ForageService = Knit.CreateService({
	Name = "ForageService",
	Client = {},
})

-- | Configuration | --
local ITEMS_PATH = ServerStorage.Assets[Constants.ITEMS_PATH]
local TREE_MODEL_NAMES = { "Tree", "bigtree" }
local BERRY_TARGET_COUNT = 15
local MUSHROOM_TARGET_COUNT = 15
local SCATTER_RADIUS = 10
local MIN_SCATTER_RADIUS = 3
local PICKUP_RANGE = 12
local RESPAWN_TIME = 60
local BERRY_HUNGER_RESTORE = 12
local MUSHROOM_HUNGER_RESTORE = 10
local RAW_MEAT_HUNGER_RESTORE = 15
local COOKED_MEAT_HUNGER_RESTORE = 30
local EAT_HUNGER_RESTORE = {
	Berries = BERRY_HUNGER_RESTORE,
	Mushrooms = MUSHROOM_HUNGER_RESTORE,
	RawMeat = RAW_MEAT_HUNGER_RESTORE,
	CookedMeat = COOKED_MEAT_HUNGER_RESTORE,
}

-- | State Management | --
local worldService: any? = nil
local inventoryService: any? = nil
local hungerService: any? = nil
local treePivots: { CFrame } = {}
local activePickups = 0

-- // FUNCTIONS // --

--[[
    @summary  Build a small procedural mushroom prop (stem + cap) since
              no mushroom mesh exists in the asset library.
    @returns  Model
]]
local function buildMushroomProp(): Model
	local model = Instance.new("Model")
	model.Name = "MushroomPickup"

	local stem = Instance.new("Part")
	stem.Name = "Stem"
	stem.Shape = Enum.PartType.Cylinder
	stem.Size = Vector3.new(0.6, 0.35, 0.35)
	stem.Color = Color3.fromRGB(235, 225, 200)
	stem.Material = Enum.Material.SmoothPlastic
	stem.CanCollide = false
	stem.Anchored = true
	stem.CFrame = CFrame.Angles(0, 0, math.rad(90))
	stem.Parent = model

	local cap = Instance.new("Part")
	cap.Name = "Cap"
	cap.Shape = Enum.PartType.Ball
	cap.Size = Vector3.new(0.7, 0.45, 0.7)
	cap.Color = Color3.fromRGB(170, 60, 55)
	cap.Material = Enum.Material.SmoothPlastic
	cap.CanCollide = false
	cap.Anchored = true
	cap.CFrame = CFrame.new(0, 0.3, 0)
	cap.Parent = model

	model.PrimaryPart = stem
	return model
end

--[[
    @summary  Scan the base-map for tree pivots so forage points can be
              scattered near them.  Retries until the forest is ready.
]]
local function collectTreePivots()
	if not worldService or not worldService:IsForestReady() then
		task.defer(collectTreePivots)
		return
	end

	local baseMap = worldService:GetBaseMap()
	if not baseMap then
		task.defer(collectTreePivots)
		return
	end

	treePivots = {}
	for _, descendant in ipairs(baseMap:GetDescendants()) do
		if descendant:IsA("Model") and table.find(TREE_MODEL_NAMES, descendant.Name) then
			table.insert(treePivots, descendant:GetPivot())
		end
	end

	print("[ForageService] Collected", #treePivots, "tree pivots for forage scatter")
end

--[[
    @summary  Pick a random ground position near a random tree.
    @returns  Vector3?
]]
local function randomForagePosition(): Vector3?
	if #treePivots == 0 then
		return nil
	end
	local pivot = treePivots[math.random(1, #treePivots)]
	local angle = math.random() * math.pi * 2
	local radius = MIN_SCATTER_RADIUS + math.random() * (SCATTER_RADIUS - MIN_SCATTER_RADIUS)
	local offset = Vector3.new(math.cos(angle) * radius, 0.5, math.sin(angle) * radius)
	return pivot.Position + offset
end

--[[
    @summary  Spawn one forage pickup of the given resource type, wire
              its pickup prompt, and schedule its respawn after it's
              collected.
    @param    resourceName  string  -- "Berries" or "Mushrooms"
]]
local function spawnForagePickup(resourceName: string)
	local position = randomForagePosition()
	if not worldService then
		task.delay(2, spawnForagePickup, resourceName)
		return
	end
	local baseMap = worldService:GetBaseMap()
	if not position or not baseMap then
		task.delay(2, spawnForagePickup, resourceName)
		return
	end

	local model: Model
	if resourceName == "Berries" then
		local source = ITEMS_PATH:FindFirstChild("Carrot")
		if not source then
			warn("[ForageService] Carrot mesh not found in Assets Items")
			return
		end
		model = Instance.new("Model")
		model.Name = "BerriesPickup"
		local clone = source:Clone()
		clone.Name = "BerriesMesh"
		clone.Anchored = true
		clone.CanCollide = false
		clone.Parent = model
		model.PrimaryPart = clone
	else
		model = buildMushroomProp()
	end

	model:PivotTo(CFrame.new(position))
	model:SetAttribute("ForageResource", resourceName)

	model.Parent = baseMap
	activePickups += 1
end

--[[
    @summary  Validate and process a forage pickup attempt.
    @param    model   Model   -- the forage pickup model
    @param    player  Player  -- the picking player
]]
local function tryForagePickup(model: Model, player: Player): boolean
	if not model.Parent then
		return false
	end

	local resourceName = model:GetAttribute("ForageResource")
	if not resourceName then
		return false
	end

	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	if not rootPart or not rootPart:IsA("BasePart") then
		return false
	end

	if (rootPart.Position - model:GetPivot().Position).Magnitude > PICKUP_RANGE then
		return false
	end

	if not inventoryService then
		return false
	end
	local added = inventoryService:AddResource(player, resourceName, 1)
	if added <= 0 then
		return false
	end

	model:Destroy()
	activePickups -= 1
	task.delay(RESPAWN_TIME, spawnForagePickup, resourceName)
	return true
end

--[[
    @summary  Route a global ProximityPrompt trigger to the forage
              pickup handler if it matches our prompt name.
    @param    prompt  ProximityPrompt  -- the triggered prompt
    @param    player  Player           -- the triggering player
]]
local function onPromptTriggered(prompt: ProximityPrompt, player: Player)
	if prompt.Name ~= "ForagePickupPrompt" then
		return
	end
	local model = prompt.Parent and prompt.Parent.Parent
	if model and model:IsA("Model") then
		tryForagePickup(model, player)
	end
end

--[[
    @summary  Spawn the initial population of Berries and Mushrooms
              once tree pivots are known.
]]
local function spawnInitialForage()
	if #treePivots == 0 then
		task.delay(2, spawnInitialForage)
		return
	end

	for _ = 1, BERRY_TARGET_COUNT do
		spawnForagePickup("Berries")
	end
	for _ = 1, MUSHROOM_TARGET_COUNT do
		spawnForagePickup("Mushrooms")
	end

	print("[ForageService] Spawned initial forage:", activePickups, "pickups")
end

-- // CLIENT REMOTES // --

--[[
    @summary  Client-to-server remote for eating a carried food resource.
    @desc     Consumes 1 unit of the resource and restores Hunger by a
              fixed amount per resource type.
    @param    player        Player  -- injected by Knit
    @param    resourceName  string  -- one of EAT_HUNGER_RESTORE's keys
    @returns  boolean               -- true if eaten successfully
]]
function ForageService.Client:RequestPickup(player: Player, model: Model): boolean
	if not model or not model:IsA("Model") or not model.Parent then
		return false
	end
	local resourceName = model:GetAttribute("ForageResource")
	if not resourceName or typeof(resourceName) ~= "string" then
		return false
	end
	if not worldService or not inventoryService then
		return false
	end
	local baseMap = worldService:GetBaseMap()
	if not baseMap or not model:IsDescendantOf(baseMap) then
		return false
	end
	return tryForagePickup(model, player)
end

--[[
    @summary  Client-to-server remote for eating a carried food resource.
    @desc     Consumes 1 unit of the resource and restores Hunger by a
              fixed amount per resource type.
    @param    player        Player  -- injected by Knit
    @param    resourceName  string  -- one of EAT_HUNGER_RESTORE's keys
    @returns  boolean               -- true if eaten successfully
]]
function ForageService.Client:RequestEat(player: Player, resourceName: string): boolean
	local restoreAmount = EAT_HUNGER_RESTORE[resourceName]
	if not restoreAmount then
		return false
	end

	if not inventoryService then
		return false
	end
	local consumed = inventoryService:ConsumeResource(player, resourceName, 1)
	if not consumed then
		return false
	end

	if hungerService then
		hungerService:RestoreHunger(player, restoreAmount)
	end
	return true
end

-- // INITIALIZATION // --

function ForageService:KnitStart()
	worldService = Knit.GetService("WorldService")
	inventoryService = Knit.GetService("InventoryService")
	hungerService = Knit.GetService("HungerService")

	collectTreePivots()
	task.delay(1, spawnInitialForage)

	ProximityPromptService.PromptTriggered:Connect(onPromptTriggered)

	print("[ForageService] Initialised — forage/eat active")
end

return ForageService
