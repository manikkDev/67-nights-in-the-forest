--[[
    @file    ForageService.luau
    @author  manik
    @date    2025

    @summary
    Server-authoritative Berries/Mushrooms foraging and eating.

    @description
    Scatters pickup-able Berries (reusing the existing `Carrot` mesh as
    the closest available forage-food art) and Mushrooms (using the
    `Mushroom` model from Assets Items) near trees across the base-map.
    Players pick them up via the CarryController hover/pickup system (F key) into their inventory, then
    eat them from the Inventory UI to restore Hunger.  Respawns on a
    timer, mirroring HarvestService's tree/log pattern.

    @exports
    - Knit Remote: RequestEat(resourceName)  -> boolean  (client -> server)
]]

-- // VARIABLES // --

-- | Services | --
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- | Modules | --
local Knit = require(ReplicatedStorage.Packages.Knit)
local ServerRole = require(ReplicatedStorage.Shared.ServerRole)
local Constants = require(ReplicatedStorage.Shared.Constants)
local WorldProgressionConfig = require(ReplicatedStorage.Shared.WorldProgressionConfig)

-- | Objects | --
local ForageService = Knit.CreateService({
	Name = "ForageService",
	Client = {},
})

-- | Configuration | --
local ITEMS_PATH = ServerStorage:FindFirstChild("Assets") and ServerStorage.Assets:FindFirstChild(Constants.ITEMS_PATH) or nil
if not ITEMS_PATH then
	warn("[ForageService] ITEMS_PATH not found: ServerStorage.Assets." .. tostring(Constants.ITEMS_PATH))
end
local TREE_MODEL_NAMES = { "Tree", "bigtree", "GiantTree" }
local BERRY_TARGET_COUNT = 35
local MUSHROOM_TARGET_COUNT = 25
local MIN_TREE_SCATTER_RADIUS = 4
local MAX_TREE_SCATTER_RADIUS = 45
local MAP_SCATTER_CHANCE = 0.4
local PICKUP_RANGE = 12
local RESPAWN_TIME = 60
local MIN_SUBMERGE = 0.65
local MAX_SUBMERGE = 1.15
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
local worldService: any = nil
local inventoryService: any = nil
local hungerService: any = nil
local treePivots: { CFrame } = {}
local groundPart: BasePart? = nil
local groundBounds: { minX: number, maxX: number, minZ: number, maxZ: number }? = nil
local activePickups = 0

-- // FUNCTIONS // --

--[[
    @summary  Build a Mushroom forage pickup using the stored Mushroom asset.
    @returns  Model
]]
local function buildMushroomProp(): Model
	if not inventoryService then
		local fallback = Instance.new("Model")
		fallback.Name = "MushroomPickup"
		return fallback
	end
	local model = inventoryService:BuildMushroomModel()
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = true
		end
	end
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

	-- Remove edit-mode preview forage items before spawning real ones.
	local preview = baseMap:FindFirstChild("ForagePreview")
	if preview then
		preview:Destroy()
	end

	treePivots = {}
	groundPart = worldService:GetGroundPart()
	groundBounds = worldService:GetGroundBounds()
	for _, descendant in ipairs(baseMap:GetDescendants()) do
		if descendant:IsA("Model") and table.find(TREE_MODEL_NAMES, descendant.Name) then
			table.insert(treePivots, descendant:GetPivot())
		end
	end

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
local function randomForagePosition(unlockLevel: number): Vector3?
	local y = getGroundTopY()
	local campfireCFrame = worldService and worldService:GetCampfireCFrame()
	if not y or not campfireCFrame then
		return nil
	end
	local center = campfireCFrame.Position
	local minRadius = if unlockLevel > 1 then WorldProgressionConfig.GetAccessRadius(unlockLevel - 1) + 15 else 35
	local maxRadius = WorldProgressionConfig.GetAccessRadius(unlockLevel) - 20
	for _ = 1, 40 do
		local position: Vector3
		if #treePivots > 0 and math.random() >= MAP_SCATTER_CHANCE then
			local pivot = treePivots[math.random(1, #treePivots)]
			local angle = math.random() * math.pi * 2
			local scatter = MIN_TREE_SCATTER_RADIUS + math.random() * (MAX_TREE_SCATTER_RADIUS - MIN_TREE_SCATTER_RADIUS)
			position = Vector3.new(pivot.Position.X + math.cos(angle) * scatter, y, pivot.Position.Z + math.sin(angle) * scatter)
		else
			local angle = math.random() * math.pi * 2
			local radius = math.sqrt(math.random() * (maxRadius * maxRadius - minRadius * minRadius) + minRadius * minRadius)
			position = Vector3.new(center.X + math.cos(angle) * radius, y, center.Z + math.sin(angle) * radius)
		end
		local distance = (Vector3.new(position.X, 0, position.Z) - Vector3.new(center.X, 0, center.Z)).Magnitude
		if distance >= minRadius and distance <= maxRadius then
			return position
		end
	end
	return nil
end

--[[
    @summary  Compute a ground-partially-submerged CFrame for a forage
              pickup, with random yaw.  Mushrooms stay upright to preserve
              the asset's authored axis and angle.
    @param    position      Vector3  -- ground position
    @param    resourceName  string
    @param    size          Vector3? -- size of the berry mesh
    @returns  CFrame
]]
local function buildForageCFrame(position: Vector3, resourceName: string, size: Vector3?): CFrame
	local x, z = position.X, position.Z
	local yaw = math.random() * math.pi * 2

	local function makeBerryCFrame(y: number, leanDegrees: number, roll: number?): CFrame
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
		local halfExtent = (size and math.sqrt(size.X * size.X + size.Y * size.Y) or 2.4) / 2
		local submerge = MIN_SUBMERGE + math.random() * (MAX_SUBMERGE - MIN_SUBMERGE)
		local lean = math.random(35, 55)
		local rightY = math.cos(math.rad(lean))
		local y = position.Y + halfExtent * rightY - submerge
		local roll = math.random() * math.pi * 2
		return makeBerryCFrame(y, lean, roll) * CFrame.Angles(0, 0, math.rad(-45))
	else
		local submerge = math.random() * MUSHROOM_SUBMERGE_MAX
		local y = position.Y - submerge
		local offset = inventoryService and inventoryService:GetMushroomBaseOffset() or 1.93
		return CFrame.new(x, y, z) * CFrame.Angles(0, yaw, 0) * CFrame.new(0, offset, 0)
	end
end

--[[
    @summary  Spawn one forage pickup of the given resource type and
              schedule its respawn after it's collected.
    @param    resourceName  string  -- "Berries" or "Mushrooms"
]]
local function spawnForagePickup(resourceName: string, unlockLevel: number?)
	local level = unlockLevel or math.random(1, #WorldProgressionConfig.AccessRadiusByLevel)
	local position = randomForagePosition(level)
	if not worldService then
		task.delay(2, spawnForagePickup, resourceName, level)
		return
	end
	local baseMap = worldService:GetBaseMap()
	if not position or not baseMap then
		task.delay(2, spawnForagePickup, resourceName, level)
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
		clone.CanCollide = true
		clone.Parent = model
		model.PrimaryPart = clone
		cframe = buildForageCFrame(position, resourceName, clone.Size)
	else
		model = buildMushroomProp()
		cframe = buildForageCFrame(position, resourceName, nil)
	end

	model:PivotTo(cframe)
	model:SetAttribute("ForageResource", resourceName)
	model:SetAttribute("UnlockLevel", level)

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

	local isLiveForage = not model:GetAttribute("Resource")
	local unlockLevel = model:GetAttribute("UnlockLevel")
	model:Destroy()
	if isLiveForage then
		activePickups -= 1
		task.delay(RESPAWN_TIME, spawnForagePickup, resourceName, if typeof(unlockLevel) == "number" then unlockLevel else 1)
	end
	return true
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

	local levelCount = #WorldProgressionConfig.AccessRadiusByLevel
	for index = 1, BERRY_TARGET_COUNT do
		local unlockLevel = if index <= math.ceil(BERRY_TARGET_COUNT * 0.4) then 1 else ((index - 1) % levelCount) + 1
		spawnForagePickup("Berries", unlockLevel)
	end
	for index = 1, MUSHROOM_TARGET_COUNT do
		local unlockLevel = if index <= math.ceil(MUSHROOM_TARGET_COUNT * 0.4) then 1 else ((index - 1) % levelCount) + 1
		spawnForagePickup("Mushrooms", unlockLevel)
	end

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
	if not ServerRole.IsGameServer() then return end
	worldService = Knit.GetService("WorldService")
	inventoryService = Knit.GetService("InventoryService")
	hungerService = Knit.GetService("HungerService")

	collectTreePivots()
	task.delay(1, spawnInitialForage)

end

return ForageService
