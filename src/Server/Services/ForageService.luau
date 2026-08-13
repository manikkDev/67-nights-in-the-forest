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
local BERRY_TARGET_COUNT = 35
local MUSHROOM_TARGET_COUNT = 25
local MIN_TREE_SCATTER_RADIUS = 4
local MAX_TREE_SCATTER_RADIUS = 45
local MAP_SCATTER_CHANCE = 0.4
local PICKUP_RANGE = 12
local RESPAWN_TIME = 60
local MIN_SUBMERGE = 0.65
local MAX_SUBMERGE = 1.15
local MIN_TILT = -8
local MAX_TILT = 8
local MUSHROOM_STEM_HALF_HEIGHT = 0.3
local MUSHROOM_SUBMERGE_MAX = 0.15
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
local groundPart: BasePart? = nil
local groundBounds: { minX: number, maxX: number, minZ: number, maxZ: number }? = nil
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
	stem.CFrame = CFrame.new()
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

	model.WorldPivot = CFrame.new()
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
		elseif descendant:IsA("BasePart") and descendant.Name == "Земля" then
			groundPart = descendant
			local halfSize = descendant.Size / 2
			groundBounds = {
				minX = descendant.Position.X - halfSize.X,
				maxX = descendant.Position.X + halfSize.X,
				minZ = descendant.Position.Z - halfSize.Z,
				maxZ = descendant.Position.Z + halfSize.Z,
			}
		end
	end

	print("[ForageService] Collected", #treePivots, "tree pivots for forage scatter")
end

--[[
    @summary  Return the Y coordinate of the base-map ground plane.
    @returns  number?
]]
local function getGroundTopY(): number?
	if not groundPart then
		return nil
	end
	return groundPart.Position.Y + groundPart.Size.Y / 2
end

--[[
    @summary  Pick a completely random position within the base-map ground
              bounds so forage can appear anywhere, not only near trees.
    @returns  Vector3?
]]
local function randomMapPosition(): Vector3?
	if not groundBounds then
		return nil
	end
	local y = getGroundTopY()
	if not y then
		return nil
	end
	local x = math.random() * (groundBounds.maxX - groundBounds.minX) + groundBounds.minX
	local z = math.random() * (groundBounds.maxZ - groundBounds.minZ) + groundBounds.minZ
	return Vector3.new(x, y, z)
end

--[[
    @summary  Pick a random ground position near a random tree or anywhere
              on the map, using the true ground height.
    @returns  Vector3?
]]
local function randomForagePosition(): Vector3?
	local y = getGroundTopY()
	if not y then
		return nil
	end

	if math.random() < MAP_SCATTER_CHANCE then
		return randomMapPosition()
	end

	if #treePivots == 0 then
		return nil
	end
	local pivot = treePivots[math.random(1, #treePivots)]
	local angle = math.random() * math.pi * 2
	local radius = MIN_TREE_SCATTER_RADIUS + math.random() * (MAX_TREE_SCATTER_RADIUS - MIN_TREE_SCATTER_RADIUS)
	local x = pivot.Position.X + math.cos(angle) * radius
	local z = pivot.Position.Z + math.sin(angle) * radius
	return Vector3.new(x, y, z)
end

--[[
    @summary  Compute a ground-partially-submerged CFrame for a forage
              pickup, with random yaw and a slight natural tilt.
    @param    position      Vector3  -- ground position
    @param    resourceName  string
    @param    size          Vector3? -- size of the berry mesh
    @returns  CFrame
]]
local function buildForageCFrame(position: Vector3, resourceName: string, size: Vector3?): CFrame
	local x, z = position.X, position.Z
	local yaw = math.random() * math.pi * 2

	local function makeCFrame(y: number, leanDegrees: number, roll: number?): CFrame
		local pitch = math.rad(leanDegrees)
		local rollRad = roll or 0

		-- long X axis leans from +Y (up) toward a random horizontal direction (yaw).
		local right = Vector3.new(
			math.sin(pitch) * math.sin(yaw),
			math.cos(pitch),
			math.sin(pitch) * math.cos(yaw)
		)

		-- choose an 'up' perpendicular to 'right' and the world Y plane.
		local up = Vector3.new(math.cos(yaw), 0, -math.sin(yaw))
		local back = right:Cross(up)

		-- roll around the long (right) axis.
		if rollRad ~= 0 then
			local cosR = math.cos(rollRad)
			local sinR = math.sin(rollRad)
			up = (up * cosR) + (back * sinR)
			back = right:Cross(up)
		end

		return CFrame.fromMatrix(Vector3.new(x, y, z), right, up)
	end

	if resourceName == "Berries" then
		local halfExtent = (size and size.Magnitude or 2.4) / 2
		local submerge = MIN_SUBMERGE + math.random() * (MAX_SUBMERGE - MIN_SUBMERGE)
		local y = position.Y + halfExtent - submerge
		local lean = math.random(35, 55)
		local roll = math.random() * math.pi * 2
		return makeCFrame(y, lean, roll)
	else
		local submerge = math.random() * MUSHROOM_SUBMERGE_MAX
		local y = position.Y + MUSHROOM_STEM_HALF_HEIGHT - submerge
		local lean = math.random(-10, 10)
		local roll = math.random() * math.pi * 2
		return makeCFrame(y, lean, roll)
	end
end

--[[
    @summary  Attach the ProximityPrompt that the global handler looks for.
    @param    model         Model
    @param    resourceName  string
]]
local function addForagePrompt(model: Model, resourceName: string)
	if not model.PrimaryPart then
		return
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "ForagePickupPrompt"
	prompt.ObjectText = resourceName == "Berries" and "Carrot" or "Mushroom"
	prompt.ActionText = "Forage"
	prompt.MaxActivationDistance = PICKUP_RANGE
	prompt.RequiresLineOfSight = false
	prompt.HoldDuration = 0
	prompt.Parent = model.PrimaryPart
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
	local cframe: CFrame
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
		cframe = buildForageCFrame(position, resourceName, clone.Size)
	else
		model = buildMushroomProp()
		cframe = buildForageCFrame(position, resourceName, nil)
	end

	model:PivotTo(cframe)
	model:SetAttribute("ForageResource", resourceName)
	addForagePrompt(model, resourceName)

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
	if inventoryService and inventoryService:IsModelDragged(model) then
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
