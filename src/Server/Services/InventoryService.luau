--[[
    @file    InventoryService.luau
    @author  manik
    @date    2025

    @summary
    Server-authoritative resource capacity, and the wearable carry-bag.

    @description
    Centralises every write to a player's `Resources` table so a single
    carry-capacity rule applies everywhere (chopping, foraging, cooking).
    Also equips the pre-placed `carry-bag` mesh as a welded backpack on
    every player's back, and grants it a larger capacity than going
    bag-less would allow — mirroring the reference game's "sack space"
    perk while staying a base-kit item rather than a paid upgrade.

    @exports
    - InventoryService:GetCapacity(player)               -> number
    - InventoryService:GetTotalCarried(player)            -> number
    - InventoryService:AddResource(player, name, amount)  -> number (actually added)
    - InventoryService:ConsumeResource(player, name, amount) -> boolean (success)
    - Knit Signal: ResourcesChanged(resources, capacity)  (server -> client)
    - Knit Remote: GetSnapshot -> { resources, capacity }
]]

-- // VARIABLES // --

-- | Services | --
local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")
local RunService = game:GetService("RunService")

-- | Modules | --
local Knit = require(ReplicatedStorage.Packages.Knit)
local ServerRole = require(ReplicatedStorage.Shared.ServerRole)
local Signal = require(ReplicatedStorage.Packages.Signal)
local Constants = require(ReplicatedStorage.Shared.Constants)
local RunConfig = require(ReplicatedStorage.Shared.RunConfig)
local JunkItemConfig = require(ReplicatedStorage.Shared.JunkItemConfig)

-- | Objects | --
local InventoryService = Knit.CreateService({
	Name = "InventoryService",
	Client = {
		ResourcesChanged = Knit.CreateSignal(),
		DragTargetMoved = Knit.CreateSignal(),
	},
})

-- Server-side signal so other services (e.g. CraftingService) can
-- react to resource changes without polling.  NOT a Knit remote.
InventoryService.ServerResourcesChanged = Signal.new()

-- | Configuration | --
local BASE_CAPACITY = 40
local BAG_CAPACITY_BONUS = 40
local ITEMS_PATH = ServerStorage.Assets[Constants.ITEMS_PATH]
local CARRY_BAG_NAME = "carry-bag"
local CARRY_BAG_TOOL_NAME = "Carry Bag"
local FLASHLIGHT_TOOL_NAME = "Flashlight"
local RESOURCE_NAMES = {
	"Wood",
	"WoodenSheet",
	"Scrap",
	"Coal",
	"Berries",
	"Mushrooms",
	"RawMeat",
	"CookedMeat",
	"OwlFeather",
	"CultistGem",
	"Bandage",
	"Bolt",
	"OldRadio",
	"SheetMetal",
	"Tyre",
	"BrokenFan",
	"BrokenMicrowave",
	"MetalChair",
}

local PICKUP_RANGE = 12
local DROP_SPACING = 2.2
local DROP_LIFETIME = 300

local DRAG_MAX_DISTANCE = 50

-- How close a dragged junk item must be released to the shredder to grind.
local GRIND_DROP_RANGE = 14

-- Map resources to the asset name in ITEMS_PATH.  Mushrooms use their own asset builder.
local DROP_ASSETS: { [string]: string? } = {
	Wood = "Log",
	WoodenSheet = nil :: string?,
	Coal = "Coal",
	Scrap = "Coal",
	Berries = "Carrot",
	RawMeat = "rabbit-meat",
	CookedMeat = "wolf-meat",
	OwlFeather = nil :: string?,
	CultistGem = "cultist gem",
	Bandage = "Bandage",
	Bolt = nil :: string?,
	OldRadio = nil :: string?,
	SheetMetal = nil :: string?,
	Tyre = nil :: string?,
	BrokenFan = nil :: string?,
	BrokenMicrowave = nil :: string?,
}
local MUSHROOM_ASSET_NAME = "Mushroom"

-- | State Management | --
local playerDataService: any = nil
local worldService: any = nil
local spawnService: any = nil
local bagTemplate: Tool? = nil
local flashlightTemplate: Tool? = nil
local mushroomSource: Model? = nil
local mushroomBaseOffset: number? = nil

local dragging: { [Player]: { model: Model, alignPos: AlignPosition, alignOri: AlignOrientation?, dragTarget: BasePart, dragTargetAttach: Attachment, itemAttach: Attachment, originalCanCollide: { [BasePart]: boolean }, originalAnchored: { [BasePart]: boolean } } } = {}
local draggedBy: { [Model]: Player } = {}

-- // FUNCTIONS // --

local function getPlayerData(player: Player): any
	if not playerDataService then
		return nil
	end
	return playerDataService:GetData(player)
end

--[[
    @summary  Returns true if the given model is already being dragged.
]]
local function isModelDragged(model: Model): boolean
	return draggedBy[model] ~= nil
end

local function updatePlayerData(player: Player, fn: (data: any) -> ())
	if not playerDataService then
		return
	end
	playerDataService:UpdateData(player, fn)
end

--[[
    @summary  Return the maximum total resource units a player can carry.
    @param    player  Player  -- the Roblox player
    @returns  number
]]
function InventoryService:GetCapacity(player: Player): number
	local data = getPlayerData(player)
	if not data then
		return BASE_CAPACITY
	end
	local capacity = BASE_CAPACITY
	if not data.Inventory or data.Inventory.HasBag ~= false then
		capacity += BAG_CAPACITY_BONUS
	end
	return capacity
end

--[[
    @summary  Sum every resource field into one carried total.
    @param    player  Player  -- the Roblox player
    @returns  number
]]
function InventoryService:IsModelDragged(model: Model): boolean
	return draggedBy[model] ~= nil
end

--[[
    @summary  Sum every resource field into one carried total.
    @param    player  Player  -- the Roblox player
    @returns  number
]]
function InventoryService:GetTotalCarried(player: Player): number
	local data = getPlayerData(player)
	if not data then
		return 0
	end
	local total = 0
	for _, name in ipairs(RESOURCE_NAMES) do
		total += data.Resources[name] or 0
	end
	return total
end

--[[
    @summary  Return whether a resource identifier is supported.
    @param    name  string
    @returns  boolean
]]
function InventoryService:IsResource(name: string): boolean
	return table.find(RESOURCE_NAMES, name) ~= nil
end

--[[
    @summary  Return the player's current count of a single resource.
    @param    player  Player
    @param    name    string  -- one of RESOURCE_NAMES
    @returns  number
]]
function InventoryService:GetResourceCount(player: Player, name: string): number
	local data = getPlayerData(player)
	if not data then
		return 0
	end
	return data.Resources[name] or 0
end

--[[
    @summary  Fire the client-facing resources snapshot for one player.
    @param    player  Player  -- the Roblox player
]]
local function broadcastSnapshot(player: Player)
	local data = getPlayerData(player)
	if not data then
		return
	end
	local resourcesClone = table.clone(data.Resources)
	InventoryService.Client.ResourcesChanged:Fire(player, resourcesClone, InventoryService:GetCapacity(player))
	InventoryService.ServerResourcesChanged:Fire(player, resourcesClone)
end

--[[
    @summary  Push the current resource state to one player.
    @param    player  Player
]]
function InventoryService:Refresh(player: Player)
	broadcastSnapshot(player)
end

--[[
    @summary  Add units of a resource, clamped by remaining capacity.
    @param    player  Player  -- the Roblox player
    @param    name    string  -- one of RESOURCE_NAMES
    @param    amount  number  -- units requested (must be positive)
    @returns  number          -- units actually added (may be less than amount)
]]
function InventoryService:AddResource(player: Player, name: string, amount: number): number
	if amount <= 0 or not table.find(RESOURCE_NAMES, name) then
		return 0
	end

	local data = getPlayerData(player)
	if not data then
		return 0
	end

	local capacity = self:GetCapacity(player)
	local carried = self:GetTotalCarried(player)
	local room = math.max(0, capacity - carried)
	local actualAmount = math.min(amount, room)
	if actualAmount <= 0 then
		return 0
	end

	updatePlayerData(player, function(playerData)
		playerData.Resources[name] = (playerData.Resources[name] or 0) + actualAmount

		if typeof(playerData.Inventory) ~= "table" then
			playerData.Inventory = {}
		end
		if typeof(playerData.Inventory.PickupOrder) ~= "table" then
			playerData.Inventory.PickupOrder = {}
		end
		local order = playerData.Inventory.PickupOrder
		for _ = 1, actualAmount do
			table.insert(order, name)
		end
	end)

	broadcastSnapshot(player)
	return actualAmount
end

--[[
    @summary  Consume units of a resource if the player has enough.
    @param    player  Player  -- the Roblox player
    @param    name    string  -- one of RESOURCE_NAMES
    @param    amount  number  -- units to consume
    @returns  boolean         -- true if the full amount was consumed
]]
function InventoryService:ConsumeResource(player: Player, name: string, amount: number): boolean
	if amount <= 0 or not table.find(RESOURCE_NAMES, name) then
		return false
	end
	if RunConfig.IsTestEnabled("GrantResources") then
		return true
	end

	local data = getPlayerData(player)
	if not data or (data.Resources[name] or 0) < amount then
		return false
	end

	updatePlayerData(player, function(playerData)
		playerData.Resources[name] = (playerData.Resources[name] or 0) - amount

		if typeof(playerData.Inventory) == "table" and typeof(playerData.Inventory.PickupOrder) == "table" then
			local order = playerData.Inventory.PickupOrder
			for _ = 1, amount do
				for i = #order, 1, -1 do
					if order[i] == name then
						table.remove(order, i)
						break
					end
				end
			end
		end
	end)

	broadcastSnapshot(player)
	return true
end

--[[
    @summary  Consume one junk item and grant its Scrap yield.
    @desc     Called by GrinderService when a player grinds a junk item.
              Does NOT check proximity to the grinder — that is the
              caller's responsibility.
    @param    player   Player
    @param    junkId   string  -- key into JunkItemConfig
    @returns  number           -- scrap actually granted (0 on failure)
]]
function InventoryService:GrindJunk(player: Player, junkId: string): number
	local config = JunkItemConfig[junkId]
	if not config then
		return 0
	end
	local consumed = self:ConsumeResource(player, junkId, 1)
	if not consumed then
		return 0
	end
	local added = self:AddResource(player, "Scrap", config.ScrapYield)
	return added
end

-- // PICKUP / DROP // --

--[[
    @summary  Compute how far the Mushroom asset's stem is above its base.
    @param    source  Model  -- the Mushroom template in Assets Items
    @returns  number
]]
local function computeMushroomBaseOffset(source: Model): number
	local pivot = source:GetPivot()
	local cf, size = source:GetBoundingBox()
	local up = pivot.UpVector
	local base = cf.Position - cf.UpVector * (size.Y / 2)

	-- BuildMushroomModel sets the stem as the model's PrimaryPart, so PivotTo
	-- will place the stem at the returned CFrame. Find the stem (tallest thin
	-- part) and measure from it to the base so spawned mushrooms rest on the
	-- ground instead of floating above it.
	local bestStem: BasePart? = nil
	local bestScore = 0
	for _, desc in ipairs(source:GetDescendants()) do
		if desc:IsA("BasePart") then
			local score = desc.Size.Y * (1 / (desc.Size.X * desc.Size.Z + 0.001))
			if score > bestScore then
				bestScore = score
				bestStem = desc
			end
		end
	end
	if bestStem then
		return (bestStem.Position - base):Dot(up)
	end

	return (pivot.Position - base):Dot(up)
end

--[[
    @summary  Load and cache the Mushroom asset from Assets Items.
    @returns  Model
]]
local function getMushroomSource(): Model?
	if not mushroomSource then
		mushroomSource = ITEMS_PATH:FindFirstChild(MUSHROOM_ASSET_NAME)
		if mushroomSource then
			mushroomBaseOffset = computeMushroomBaseOffset(mushroomSource)
		end
	end
	return mushroomSource
end

--[[
    @summary  Find the stem-like part in the mushroom model (tallest part with
              a small cross-section) so it can be used as the PrimaryPart.
    @param    model  Model
    @returns  BasePart?
]]
local function findMushroomStem(model: Model): BasePart?
	local best: BasePart? = nil
	local bestScore: number = 0
	for _, desc in ipairs(model:GetDescendants()) do
		if desc:IsA("BasePart") then
			local score = desc.Size.Y * (1 / (desc.Size.X * desc.Size.Z + 0.001))
			if score > bestScore then
				bestScore = score
				best = desc
			end
		end
	end
	return best
end

--[[
    @summary  Build a fresh Mushroom pickup from the stored asset.
    @returns  Model
]]
local function buildMushroomProp(): Model
	local source = getMushroomSource()
	if not source then
		warn("[InventoryService] Mushroom asset not found in Assets Items")
		local fallback = Instance.new("Model")
		fallback.Name = "MushroomPickup"
		local p = Instance.new("Part")
		p.Name = "Main"
		p.Size = Vector3.new(1, 1, 1)
		p.Color = Color3.fromRGB(180, 180, 180)
		p.Material = Enum.Material.SmoothPlastic
		p.Parent = fallback
		fallback.PrimaryPart = p
		return fallback
	end

	local model = source:Clone()
	model.Name = "MushroomPickup"

	local stem = findMushroomStem(model)
	if stem then
		model.PrimaryPart = stem
		for _, desc in ipairs(model:GetDescendants()) do
			if desc:IsA("BasePart") and desc ~= stem then
				local weld = Instance.new("WeldConstraint")
				weld.Part0 = stem
				weld.Part1 = desc
				weld.Parent = stem
			end
		end
	end

	return model
end

--[[
    @summary  Return the base offset of the Mushroom asset, measured from the
              bottom of its bounding box to its stem along the up axis.
    @returns  number
]]
function InventoryService:GetMushroomBaseOffset(): number
	getMushroomSource()
	return mushroomBaseOffset or 1.93
end

--[[
    @summary  Public wrapper to build a Mushroom pickup from the asset.
    @returns  Model
]]
function InventoryService:BuildMushroomModel(): Model
	return buildMushroomProp()
end

--[[
    @summary  Map a JunkItemConfig id to possible 3D model names.
    @desc     The model names in the folder differ from the code ids,
              so this table lists every name variant to try.
]]
local JUNK_ASSET_NAMES: { [string]: { string } } = {
	Bolt = { "Bolt", "Bolts" },
	SheetMetal = { "Sheet Metal Plate", "SheetMetal", "Sheet Metal", "SheetMetalPlate" },
	OldRadio = { "Classic Radio", "OldRadio", "Old Radio", "Radio" },
	BrokenFan = { "Desk Fan", "BrokenFan", "Broken Fan", "Fan", "DeskFan" },
	BrokenMicrowave = { "Microwave", "BrokenMicrowave", "Broken Microwave" },
	MetalChair = { "Metal Chair", "MetalChair", "Chair" },
	Tyre = { "Tyre", "Tire", "TyreModel" },
}

-- Cache the junk folder so we only search once
local junkFolderCache: Instance? = nil

--[[
    @summary  Find the junk assets folder anywhere under ServerStorage.
    @desc     Searches recursively for a folder named "Bolts items",
              "Bolts Items", "bolts items", or similar.
    @returns  Instance?
]]
local function findJunkFolder(): Instance?
	if junkFolderCache then
		return junkFolderCache
	end

	local assets = ServerStorage:FindFirstChild("Assets")
	if not assets then
		return nil
	end

	-- Search all descendants for a folder matching "bolts items" (case-insensitive)
	for _, desc in ipairs(assets:GetDescendants()) do
		if desc:IsA("Folder") or desc:IsA("Model") then
			local name = desc.Name:lower()
			if name == "bolts items" or name == "bolts" or name == "boltsitems" then
				junkFolderCache = desc
				return desc
			end
		end
	end

	-- If no dedicated folder, try the Assets Items folder directly
	local itemsPath = assets:FindFirstChild(Constants.ITEMS_PATH)
	if itemsPath then
		junkFolderCache = itemsPath
		return itemsPath
	end

	return nil
end

--[[
    @summary  Find a junk model by trying multiple name variants.
    @desc     Case-insensitive search through the junk folder.
    @param    folder  Instance  -- the folder to search
    @param    names   {string}  -- ordered list of names to try
    @returns  Model?
]]
local function findJunkModel(folder: Instance, names: { string }): Instance?
	-- Build a case-insensitive lookup of all children
	local byLowerName: { [string]: Instance } = {}
	for _, child in ipairs(folder:GetChildren()) do
		byLowerName[child.Name:lower()] = child
	end

	for _, name in ipairs(names) do
		local found = byLowerName[name:lower()]
		if found and (found:IsA("Model") or found:IsA("BasePart")) then
			return found
		end
	end

	-- Also search descendants (in case models are nested)
	for _, name in ipairs(names) do
		local lower = name:lower()
		for _, desc in ipairs(folder:GetDescendants()) do
			if (desc:IsA("Model") or desc:IsA("BasePart")) and desc.Name:lower() == lower then
				return desc
			end
		end
	end

	return nil
end

--[[
    @summary  Build a junk item model by cloning the 3D asset.
    @desc     Searches ServerStorage for the junk folder and model.
              Falls back to a simple primitive if the asset is missing.
    @param    itemId  string  -- key into JunkItemConfig
    @returns  Model
]]
local function buildJunkModel(itemId: string): Model
	local folder = findJunkFolder()
	local nameVariants = JUNK_ASSET_NAMES[itemId]
	local source = folder and nameVariants and findJunkModel(folder, nameVariants)

	if source then
		if source:IsA("Model") then
			local clone = source:Clone()
			clone.Name = itemId .. "Pickup"
			-- Disable all scripts inside the cloned asset (e.g. RadioScript)
			for _, desc in ipairs(clone:GetDescendants()) do
				if desc:IsA("Script") or desc:IsA("LocalScript") or desc:IsA("ModuleScript") then
					desc.Disabled = true
				end
			end
			if not clone.PrimaryPart then
				local first = clone:FindFirstChildWhichIsA("BasePart", true)
				if first then
					clone.PrimaryPart = first
				end
			end
			return clone
		elseif source:IsA("BasePart") then
			-- Asset is a single part (e.g. MeshPart), wrap it in a Model
			local model = Instance.new("Model")
			model.Name = itemId .. "Pickup"
			local clone = source:Clone()
			clone.Name = "Main"
			clone.Parent = model
			model.PrimaryPart = clone
			return model
		end
	end

	-- Fallback: simple colored part if the 3D asset is missing
	local config = JunkItemConfig[itemId]
	local fallback = Instance.new("Model")
	fallback.Name = itemId .. "Pickup"
	local p = Instance.new("Part")
	p.Name = "Main"
	p.Size = Vector3.new(1, 1, 1)
	p.Color = config and config.Color or Color3.fromRGB(150, 150, 150)
	p.Material = config and config.Material or Enum.Material.Metal
	p.Parent = fallback
	fallback.PrimaryPart = p
	return fallback
end

--[[
    @summary  Make a fresh clone of a resource asset (or build one) and tag
              it with the attributes CarryController/HarvestService/ForageService
              will look for.
    @param    resourceName  string  -- one of RESOURCE_NAMES
    @returns  Model
]]
local function buildDropModel(resourceName: string): Model
	local model: Model

	if resourceName == "Mushrooms" then
		model = buildMushroomProp()
	elseif JunkItemConfig[resourceName] then
		model = buildJunkModel(resourceName)
	else
		local assetName = DROP_ASSETS[resourceName]
		local source = assetName and ITEMS_PATH:FindFirstChild(assetName)
		if source and source:IsA("Model") then
			model = source:Clone()
			if not model.PrimaryPart then
				local first = model:FindFirstChildWhichIsA("BasePart", true)
				if first then
					model.PrimaryPart = first
				end
			end
		elseif source and source:IsA("BasePart") then
			model = Instance.new("Model")
			model.Name = source.Name .. "Pickup"
			local clone = source:Clone()
			clone.Anchored = false
			clone.CanCollide = true
			clone.Parent = model
			model.PrimaryPart = clone
		else
			model = Instance.new("Model")
			model.Name = resourceName .. "Pickup"
			local fallback = Instance.new("Part")
			fallback.Name = "Main"
			if resourceName == "OwlFeather" then
				fallback.Size = Vector3.new(0.5, 0.3, 2)
				fallback.Color = Color3.fromRGB(230, 220, 200)
				fallback.Material = Enum.Material.Neon
			else
				fallback.Size = Vector3.new(1, 1, 1)
				fallback.Color = Color3.fromRGB(180, 180, 180)
				fallback.Material = Enum.Material.SmoothPlastic
			end
			fallback.Parent = model
			model.PrimaryPart = fallback
		end
	end

	-- Prepare model: ensure PrimaryPart, weld parts together, and make
	-- every part queryable for mouse raycasts.
	local primary = model.PrimaryPart
	if not primary then
		local first = model:FindFirstChildWhichIsA("BasePart", true)
		if first then
			model.PrimaryPart = first
			primary = first
		end
	end

	local _isJunk = JunkItemConfig[resourceName] ~= nil

	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			-- Weld every part to the PrimaryPart so the model doesn't scatter.
			-- Use pcall for GetConstraints since some nested parts may error.
			if primary and descendant ~= primary then
				local alreadyWelded = false
				pcall(function()
					for _, constraint in ipairs(descendant:GetConstraints()) do
						if constraint:IsA("WeldConstraint") then
							alreadyWelded = true
							break
						end
					end
				end)
				if not alreadyWelded then
					local weld = Instance.new("WeldConstraint")
					weld.Name = "JunkWeld"
					weld.Part0 = primary
					weld.Part1 = descendant
					weld.Parent = descendant
				end
			end
			-- All dropped items use physics so they fall to the ground.
			descendant.Anchored = false
			descendant.CanCollide = true
			descendant.CanQuery = true
			descendant.CanTouch = true
		end
	end

	-- Generic identifier used by CarryController.
	model:SetAttribute("Resource", resourceName)

	-- Legacy identifiers so existing services can still handle their own items.
	if resourceName == "Wood" then
		model:SetAttribute("PickupResource", "Wood")
	elseif resourceName == "Berries" or resourceName == "Mushrooms" then
		model:SetAttribute("ForageResource", resourceName)
	end

	return model
end

--[[
    @summary  Public wrapper for buildDropModel so other services can spawn
              world items without duplicating drop logic.
    @param    resourceName  string
    @returns  Model
]]
function InventoryService:BuildDropModel(resourceName: string): Model
	return buildDropModel(resourceName)
end

--[[
    @summary  Return the distance from the model's pivot to the lowest
              BasePart in the model.  Used by FacilityService to place
              junk items so they sit ON the ground instead of in it.
    @param    model  Model
    @returns  number  -- how far below the pivot the lowest part is
]]
function InventoryService:GetModelBottomOffset(model: Model): number
	local pivotY = model:GetPivot().Position.Y
	local lowestY = math.huge
	for _, desc in ipairs(model:GetDescendants()) do
		if desc:IsA("BasePart") then
			if desc.Position.Y < lowestY then
				lowestY = desc.Position.Y
			end
		end
	end
	if lowestY == math.huge then
		return 0
	end
	return pivotY - lowestY  -- positive if lowest part is below pivot
end

--[[
    @summary  Build a drop CFrame for a resource, with mushrooms standing
              upright and everything else lying flat.
    @param    position      Vector3
    @param    resourceName  string
    @returns  CFrame
]]
local function buildDropCFrame(position: Vector3, resourceName: string): CFrame
	local yaw = math.random() * math.pi * 2
	if resourceName == "Mushrooms" then
		local offset = InventoryService:GetMushroomBaseOffset()
		return CFrame.new(position) * CFrame.Angles(0, yaw, 0) * CFrame.new(0, offset, 0)
	end
	return CFrame.new(position) * CFrame.Angles(0, yaw, 0)
end

--[[
    @summary  Validate and process a generic resource pickup.
    @param    model   Model   -- the world item to pick up
    @param    player  Player  -- the picking player
    @returns  boolean
]]
local function tryPickup(model: Model, player: Player): boolean
	if not model.Parent then
		return false
	end
	if isModelDragged(model) then
		return false
	end

	local resourceName = model:GetAttribute("Resource")
		or model:GetAttribute("PickupResource")
		or model:GetAttribute("ForageResource")
	if not resourceName or typeof(resourceName) ~= "string" then
		return false
	end
	if not table.find(RESOURCE_NAMES, resourceName) then
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

	if not worldService then
		return false
	end
	local baseMap = worldService:GetBaseMap()
	if not baseMap or not model:IsDescendantOf(baseMap) then
		return false
	end

	local added = InventoryService:AddResource(player, resourceName, 1)
	if added <= 0 then
		return false
	end

	model:Destroy()
	return true
end

--[[
    @summary  Drop every carried resource at the player's feet.
    @param    player  Player  -- the dropping player
    @returns  boolean
]]
local function tryDropAll(player: Player): boolean
	local data = getPlayerData(player)
	if not data then
		return false
	end

	if not worldService then
		return false
	end
	local baseMap = worldService:GetBaseMap()
	if not baseMap then
		return false
	end

	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	if not rootPart or not rootPart:IsA("BasePart") then
		return false
	end

	local origin = rootPart.Position
	local droppedAny = false

	for _, resourceName in ipairs(RESOURCE_NAMES) do
		local count = data.Resources[resourceName] or 0
		if count > 0 then
			droppedAny = true
			for i = 1, count do
				local golden = i * 2.3999632297
				local radius = math.sqrt(i) * DROP_SPACING
				local offset = Vector3.new(math.cos(golden) * radius, 0, math.sin(golden) * radius)
				local position = Vector3.new(origin.X + offset.X, origin.Y, origin.Z + offset.Z)

				local model = buildDropModel(resourceName); model:SetAttribute("DroppedBy", player.UserId)
				model:PivotTo(buildDropCFrame(position, resourceName))
				model.Parent = baseMap
				Debris:AddItem(model, DROP_LIFETIME)
			end

			updatePlayerData(player, function(playerData)
				playerData.Resources[resourceName] = 0
			end)
		end
	end

	if droppedAny then
		updatePlayerData(player, function(playerData)
			if typeof(playerData.Inventory) == "table" then
				playerData.Inventory.PickupOrder = {}
			end
		end)
		broadcastSnapshot(player)
	end
	return true
end

--[[
    @summary  Drop one item (the oldest from PickupOrder) at the player's feet.
    @param    player  Player  -- the dropping player
    @returns  boolean
]]
local function tryDropOne(player: Player): boolean
	local data = getPlayerData(player)
	if not data then
		return false
	end
	if not worldService then
		return false
	end
	local baseMap = worldService:GetBaseMap()
	if not baseMap then
		return false
	end

	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	if not rootPart or not rootPart:IsA("BasePart") then
		return false
	end

	local order = data.Inventory and data.Inventory.PickupOrder
	if not order then
		-- Backfill for profiles created before PickupOrder was added.
		order = {}
		for _, resourceName in ipairs(RESOURCE_NAMES) do
			for _ = 1, (data.Resources[resourceName] or 0) do
				table.insert(order, resourceName)
			end
		end
		updatePlayerData(player, function(playerData)
			if typeof(playerData.Inventory) ~= "table" then
				playerData.Inventory = {}
			end
			playerData.Inventory.PickupOrder = order
		end)
	end
	if #order == 0 then
		return false
	end

	local resourceName = order[1]
	local count = data.Resources[resourceName] or 0
	if count <= 0 then
		-- Stale entry; clean it up and try the next one.
		updatePlayerData(player, function(playerData)
			table.remove(playerData.Inventory.PickupOrder, 1)
		end)
		return tryDropOne(player)
	end

	local offset = rootPart.CFrame.LookVector * DROP_SPACING
	local position = Vector3.new(rootPart.Position.X + offset.X, rootPart.Position.Y, rootPart.Position.Z + offset.Z)

	local model = buildDropModel(resourceName); model:SetAttribute("DroppedBy", player.UserId)
	model:PivotTo(buildDropCFrame(position, resourceName))
	model.Parent = baseMap
	Debris:AddItem(model, DROP_LIFETIME)

	updatePlayerData(player, function(playerData)
		playerData.Resources[resourceName] -= 1
		table.remove(playerData.Inventory.PickupOrder, 1)
	end)

	broadcastSnapshot(player)
	return true
end

--[[
    @summary  Remove a player's drag constraints and restore the item.
    @param    player  Player
]]
local function stopDrag(player: Player)
	local entry = dragging[player]
	if not entry then
		return
	end

	if entry.alignPos then
		entry.alignPos:Destroy()
	end
	if entry.alignOri then
		entry.alignOri:Destroy()
	end
	if entry.dragTargetAttach then
		entry.dragTargetAttach:Destroy()
	end
	if entry.itemAttach then
		entry.itemAttach:Destroy()
	end
	if entry.dragTarget then
		entry.dragTarget:Destroy()
	end

	local model = entry.model
	if model and model.Parent then
		local resourceName = model:GetAttribute("Resource")
		local isJunk = resourceName and JunkItemConfig[resourceName] ~= nil
		local isWood = resourceName == "Wood"

		-- Check if the item was dropped near the shredder.
		-- If it's a junk item or wood near the shredder, auto-grind it.
		local grinderService = (isJunk or isWood) and Knit.GetService("GrinderService") or nil
		local grinderPos = grinderService and grinderService:GetGrinderPosition()
		local config = isJunk and JunkItemConfig[resourceName] or nil
		if grinderPos and (config or isWood) then
			local dist = (model:GetPivot().Position - grinderPos).Magnitude
			if dist <= GRIND_DROP_RANGE then
				-- Grant the output FIRST.  If the player is at carry
				-- capacity AddResource returns 0, and destroying the
				-- model anyway would silently delete their item for
				-- nothing — so in that case we let it fall instead.
				local outputResource = if isWood then "WoodenSheet" else "Scrap"
				local outputAmount = if isWood then 1 else config.ScrapYield
				local added = InventoryService:AddResource(player, outputResource, outputAmount)
				if added > 0 then
					model:Destroy()
					dragging[player] = nil
					draggedBy[model] = nil
					grinderService:StartGrindAnimation()
					grinderService:StopGrindAnimation()
					grinderService.Client.GrinderProcessed:Fire(player, {
						position = grinderPos,
						scrapAmount = added,
						junkId = if isWood then "WoodenSheet" else resourceName,
					})
					local craftingService = Knit.GetService("CraftingService")
					craftingService:AddShreddedTotal(outputResource, added)
					return
				end
				warn(("[InventoryService] %s could not grind %s: inventory full"):format(player.Name, resourceName))
			end
		end

		for _, desc in ipairs(model:GetDescendants()) do
			if desc:IsA("BasePart") then
				if entry.originalCanCollide[desc] ~= nil then
					desc.CanCollide = entry.originalCanCollide[desc]
				end
				if isJunk then
					-- Junk items: unanchor after drag so they fall to the ground
					desc.Anchored = false
				elseif entry.originalAnchored[desc] ~= nil then
					desc.Anchored = entry.originalAnchored[desc]
				end
			end
		end

		local primaryPart = model.PrimaryPart
		if primaryPart and primaryPart.Parent then
			pcall(function()
				primaryPart:SetNetworkOwner(nil)
			end)
		end
	end

	dragging[player] = nil
	if model then
		draggedBy[model] = nil
	end
end

--[[
    @summary  Validate and start dragging a world item for a player.
    @param    player  Player
    @param    model   Model
    @returns  boolean
]]
local function tryStartDrag(player: Player, model: Model): boolean
	if not model or not model:IsA("Model") or not model.Parent then
		return false
	end

	local resourceName = model:GetAttribute("Resource")
		or model:GetAttribute("PickupResource")
		or model:GetAttribute("ForageResource")
	if not resourceName or typeof(resourceName) ~= "string" then
		return false
	end
	if not table.find(RESOURCE_NAMES, resourceName) then
		return false
	end

	if not worldService then
		return false
	end
	local baseMap = worldService:GetBaseMap()
	if not baseMap or not model:IsDescendantOf(baseMap) then
		return false
	end
	if dragging[player] then
		return false
	end
	if draggedBy[model] then
		return false
	end

	local character = player.Character
	if not character then
		return false
	end
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp or not hrp:IsA("BasePart") then
		return false
	end
	local primaryPart = model.PrimaryPart
	if not primaryPart then
		return false
	end
	if (hrp.Position - model:GetPivot().Position).Magnitude > PICKUP_RANGE then
		return false
	end

	local originalCanCollide: { [BasePart]: boolean } = {}
	local originalAnchored: { [BasePart]: boolean } = {}
	for _, desc in ipairs(model:GetDescendants()) do
		if desc:IsA("BasePart") then
			originalCanCollide[desc] = desc.CanCollide
			originalAnchored[desc] = desc.Anchored
			desc.Anchored = false
			-- Keep original CanCollide so the item slides against the map like the real game.
		end
	end

	pcall(function()
		primaryPart:SetNetworkOwner(player)
	end)

	local dragTarget = Instance.new("Part")
	dragTarget.Name = "DragTarget_" .. tostring(player.UserId)
	dragTarget.Size = Vector3.new(1, 1, 1)
	dragTarget.Transparency = 1
	dragTarget.CanCollide = false
	dragTarget.Anchored = true
	dragTarget.CFrame = primaryPart.CFrame
	dragTarget.Parent = workspace

	local dragTargetAttach = Instance.new("Attachment")
	dragTargetAttach.Name = "DragTargetAttachment"
	dragTargetAttach.Position = Vector3.zero
	dragTargetAttach.Parent = dragTarget

	local itemAttach = Instance.new("Attachment")
	itemAttach.Name = "DragItemAttachment"
	itemAttach.Position = Vector3.zero
	itemAttach.Parent = primaryPart

	local alignPos = Instance.new("AlignPosition")
	alignPos.Name = "DragAlignPosition"
	alignPos.Attachment0 = itemAttach
	alignPos.Attachment1 = dragTargetAttach
	alignPos.RigidityEnabled = false
	alignPos.Responsiveness = 80
	alignPos.MaxForce = 2.5e5
	alignPos.ApplyAtCenterOfMass = true
	alignPos.Parent = primaryPart

	local alignOri = Instance.new("AlignOrientation")
	alignOri.Name = "DragAlignOrientation"
	alignOri.Attachment0 = itemAttach
	alignOri.Attachment1 = dragTargetAttach
	alignOri.RigidityEnabled = false
	alignOri.Responsiveness = 50
	alignOri.MaxTorque = 1e5
	alignOri.Parent = primaryPart

	dragging[player] = {
		model = model,
		alignPos = alignPos,
		alignOri = alignOri,
		dragTarget = dragTarget,
		dragTargetAttach = dragTargetAttach,
		itemAttach = itemAttach,
		originalCanCollide = originalCanCollide,
		originalAnchored = originalAnchored,
	}
	draggedBy[model] = player
	return true
end

--[[
    @summary  Drop any drag whose model, player, or distance has become invalid.
]]
local function cleanupDrags()
	local toStop: { Player } = {}
	for player, entry in pairs(dragging) do
		local character = player.Character
		local hrp = character and character:FindFirstChild("HumanoidRootPart")
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")

		local model = entry.model
		if not model or not model.Parent then
			table.insert(toStop, player)
			continue
		end

		if not hrp or not hrp:IsA("BasePart") or humanoid and humanoid.Health <= 0 then
			table.insert(toStop, player)
			continue
		end

		local primaryPart = model.PrimaryPart
		if not primaryPart or not primaryPart:IsA("BasePart") or not primaryPart.Parent then
			table.insert(toStop, player)
			continue
		end

		if (hrp.Position - primaryPart.Position).Magnitude > DRAG_MAX_DISTANCE then
			table.insert(toStop, player)
			continue
		end

		local dragTarget = entry.dragTarget
		if not dragTarget or not dragTarget.Parent then
			table.insert(toStop, player)
			continue
		end

		if (hrp.Position - dragTarget.Position).Magnitude > DRAG_MAX_DISTANCE then
			table.insert(toStop, player)
			continue
		end

		if (dragTarget.Position - primaryPart.Position).Magnitude > 30 then
			table.insert(toStop, player)
			continue
		end

		if not worldService then
			continue
		end
		local baseMap = worldService:GetBaseMap()
		if not baseMap or not model:IsDescendantOf(baseMap) then
			table.insert(toStop, player)
			continue
		end
	end

	for _, player in ipairs(toStop) do
		stopDrag(player)
	end
end

-- // CLIENT REMOTES // --

--[[
    @summary  Client-to-server remote for picking up a generic resource drop.
    @param    player  Player  -- injected by Knit
    @param    model   Model   -- the resource model in the world
    @returns  boolean
]]
function InventoryService.Client:RequestPickup(player: Player, model: Model): boolean
	if not model or not model:IsA("Model") or not model.Parent then
		return false
	end
	return tryPickup(model, player)
end

--[[
    @summary  Client-to-server remote to drop the entire inventory.
    @param    player  Player  -- injected by Knit
    @returns  boolean
]]
function InventoryService.Client:RequestDropAll(player: Player): boolean
	return tryDropAll(player)
end

--[[
    @summary  Client-to-server remote to drop the oldest single item.
    @param    player  Player  -- injected by Knit
    @returns  boolean
]]
function InventoryService.Client:RequestDropOne(player: Player): boolean
	return tryDropOne(player)
end

--[[
    @summary  Client-to-server remote to drop a specific amount of a resource.
    @param    player        Player  -- injected by Knit
    @param    resourceName  string  -- one of RESOURCE_NAMES
    @param    amount        number  -- units to drop (default 1)
    @returns  boolean
]]
function InventoryService.Client:RequestDrop(player: Player, resourceName: string, amount: number?): boolean
	if not resourceName or typeof(resourceName) ~= "string" then
		return false
	end
	if not table.find(RESOURCE_NAMES, resourceName) then
		return false
	end

	local dropAmount = math.max(1, math.floor(amount or 1))
	local data = getPlayerData(player)
	if not data then
		return false
	end
	if (data.Resources[resourceName] or 0) < dropAmount then
		return false
	end
	if not worldService then
		return false
	end
	local baseMap = worldService:GetBaseMap()
	if not baseMap then
		return false
	end

	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	if not rootPart or not rootPart:IsA("BasePart") then
		return false
	end

	local origin = rootPart.Position
	local dropped = 0
	for i = 1, dropAmount do
		local golden = i * 2.3999632297
		local radius = math.sqrt(i) * DROP_SPACING
		local offset = Vector3.new(math.cos(golden) * radius, 0, math.sin(golden) * radius)
		local position = Vector3.new(origin.X + offset.X, origin.Y, origin.Z + offset.Z)

		local model = buildDropModel(resourceName); model:SetAttribute("DroppedBy", player.UserId)
		model:PivotTo(buildDropCFrame(position, resourceName))
		model.Parent = baseMap
		Debris:AddItem(model, DROP_LIFETIME)
		dropped += 1
	end

	if dropped > 0 then
		if not RunConfig.IsTestEnabled("GrantResources") then
			updatePlayerData(player, function(playerData)
				playerData.Resources[resourceName] -= dropped
				if typeof(playerData.Inventory) == "table" and typeof(playerData.Inventory.PickupOrder) == "table" then
					local order = playerData.Inventory.PickupOrder
					for _ = 1, dropped do
						for i = #order, 1, -1 do
							if order[i] == resourceName then
								table.remove(order, i)
								break
							end
						end
					end
				end
			end)
		end
		broadcastSnapshot(player)
	end
	return dropped > 0
end

--[[
    @summary  Client-to-server remote to start dragging a world item.
    @param    player  Player  -- injected by Knit
    @param    model   Model   -- the item to drag
    @returns  boolean
]]
function InventoryService.Client:RequestDragStart(player: Player, model: Model): boolean
	return tryStartDrag(player, model)
end

--[[
    @summary  Client-to-server remote to stop dragging and release the item.
    @param    player  Player  -- injected by Knit
    @returns  boolean
]]
function InventoryService.Client:RequestDragStop(player: Player): boolean
	if not dragging[player] then
		return false
	end
	stopDrag(player)
	return true
end

--[[
    @summary  Build an equippable Carry Bag Tool from the pre-placed mesh.
    @desc     Clones the carry-bag Part as the Tool's Handle so the player
              can equip and unequip it like the Axe.
    @returns  Tool?
]]
local function buildCarryBagTool(): Tool?
	local source = ITEMS_PATH:FindFirstChild(CARRY_BAG_NAME)
	if not source or not source:IsA("BasePart") then
		warn("[InventoryService] carry-bag asset not found in Assets Items")
		return nil
	end

	local tool = Instance.new("Tool")
	tool.Name = CARRY_BAG_TOOL_NAME
	tool.RequiresHandle = true
	tool.CanBeDropped = false

	-- Hold the bag by its opening (top) so the body hangs downward from the hand.
	-- GripPos is in the Handle's local space: +Y is the top/opening of the mesh,
	-- so we place the grip point at +halfHeight to put the hand at the opening.
	local mesh = source:FindFirstChildWhichIsA("SpecialMesh")
	local halfHeight = source.Size.Y / 2
	if mesh and mesh:IsA("SpecialMesh") then
		halfHeight *= mesh.Scale.Y
	end
	tool.GripPos = Vector3.new(0, halfHeight, 0)
	tool.GripUp = Vector3.new(0, 1, 0)
	tool.GripForward = Vector3.new(0, 0, 1)
	tool.GripRight = Vector3.new(1, 0, 0)

	local handle = source:Clone()
	handle.Name = "Handle"
	handle.Anchored = false
	handle.CanCollide = false
	handle.CanQuery = false
	handle.CanTouch = false
	handle.Massless = true
	-- Strip the source's in-world Y-180 rotation so the Tool grip controls it fully.
	handle.CFrame = CFrame.new(handle.CFrame.Position)
	for _, child in ipairs(handle:GetChildren()) do
		if child:IsA("JointInstance") or child:IsA("Motor6D") then
			child:Destroy()
		end
	end
	handle.Parent = tool

	return tool
end

--[[
    @summary  Grant the Carry Bag tool to a player's Backpack and StarterGear
              so it persists across respawns.
    @param    player  Player  -- the Roblox player
]]
local function giveFlashlight(player: Player)
	if not flashlightTemplate then
		return
	end
	-- On the game place, always give the flashlight. On the lobby, require spawn first.
	if ServerRole.IsLobby() and spawnService and not spawnService:IsPlayerSpawned(player) then
		return
	end

	local backpack = player:WaitForChild("Backpack")
	if not backpack:FindFirstChild(FLASHLIGHT_TOOL_NAME) then
		flashlightTemplate:Clone().Parent = backpack
	end

	local starterGear = player:WaitForChild("StarterGear")
	if not starterGear:FindFirstChild(FLASHLIGHT_TOOL_NAME) then
		flashlightTemplate:Clone().Parent = starterGear
	end
end

local function giveCarryBag(player: Player)
	if not bagTemplate then
		return
	end
	-- On the game place, always give the bag. On the lobby, require spawn first.
	if ServerRole.IsLobby() and spawnService and not spawnService:IsPlayerSpawned(player) then
		return
	end

	local data = getPlayerData(player)
	if data and data.Inventory and data.Inventory.HasBag == false then
		return
	end

	local backpack = player:WaitForChild("Backpack")
	if not backpack:FindFirstChild(CARRY_BAG_TOOL_NAME) then
		local clone = bagTemplate:Clone()
		clone.Parent = backpack
	end

	local starterGear = player:WaitForChild("StarterGear")
	if not starterGear:FindFirstChild(CARRY_BAG_TOOL_NAME) then
		local clone = bagTemplate:Clone()
		clone.Parent = starterGear
	end
end

-- // CLIENT REMOTES // --

--[[
    @summary  Client-facing remote returning a one-shot resources/capacity snapshot.
    @param    player  Player  -- injected by Knit
    @returns  { resources: table, capacity: number } | nil
]]
function InventoryService.Client:GetSnapshot(player: Player)
	local data = getPlayerData(player)
	if not data then
		local empty = {}
		for _, name in ipairs(RESOURCE_NAMES) do
			empty[name] = 0
		end
		return { resources = empty, capacity = BASE_CAPACITY }
	end
	return {
		resources = table.clone(data.Resources),
		capacity = InventoryService:GetCapacity(player),
	}
end

-- // INITIALIZATION // --

function InventoryService:KnitStart()
	if not ServerRole.IsGameServer() then return end
	playerDataService = Knit.GetService("PlayerDataService")
	worldService = Knit.GetService("WorldService")
	spawnService = Knit.GetService("SpawnService")

	-- Diagnostic: log junk folder discovery
	local junkFolder = findJunkFolder()
	if junkFolder then
		local names = {}
		for _, child in ipairs(junkFolder:GetChildren()) do
			table.insert(names, child.Name .. "(" .. child.ClassName .. ")")
		end
		print(("[InventoryService] Junk folder found: '%s' with children: %s"):format(
			junkFolder:GetFullName(),
			table.concat(names, ", ")
		))
	else
		warn("[InventoryService] No junk folder found under ServerStorage.Assets")
	end

	bagTemplate = buildCarryBagTool()
	flashlightTemplate = ITEMS_PATH:FindFirstChild(FLASHLIGHT_TOOL_NAME)
	if flashlightTemplate and not flashlightTemplate:IsA("Tool") then
		warn("[InventoryService] Flashlight asset is not a Tool, got:", flashlightTemplate.ClassName)
		flashlightTemplate = nil
	end

	playerDataService.ProfileLoaded:Connect(function(player: Player)
		giveCarryBag(player)
		giveFlashlight(player)
		broadcastSnapshot(player)
	end)

	-- Give bag and flashlight when player teleports to the game map.
	if spawnService then
		spawnService.PlayerSpawned:Connect(function(player: Player)
			giveCarryBag(player)
			giveFlashlight(player)
			if RunConfig.IsTestEnabled("GrantResources") then
				updatePlayerData(player, function(playerData)
					for _, resourceName in ipairs(RESOURCE_NAMES) do
						playerData.Resources[resourceName] = 9999
					end
					playerData.Inventory.PickupOrder = table.clone(RESOURCE_NAMES)
				end)
			end
			broadcastSnapshot(player)
		end)
	end

	for _, player in ipairs(Players:GetPlayers()) do
		if getPlayerData(player) then
			giveCarryBag(player)
			giveFlashlight(player)
		end
	end

	InventoryService.Client.DragTargetMoved:Connect(function(player: Player, pos: any)
		if typeof(pos) ~= "Vector3" then
			return
		end
		local position = pos :: Vector3
		local entry = dragging[player]
		if not entry then
			return
		end
		local dragTarget = entry.dragTarget
		if not dragTarget or not dragTarget.Parent then
			return
		end
		local character = player.Character
		local hrp = character and character:FindFirstChild("HumanoidRootPart")
		if not hrp or not hrp:IsA("BasePart") then
			return
		end
		if (hrp.Position - position).Magnitude > DRAG_MAX_DISTANCE then
			return
		end
		dragTarget.CFrame = CFrame.new(position) * dragTarget.CFrame.Rotation
	end)

	Players.PlayerRemoving:Connect(stopDrag)
	local function onCharacterRemoving(player: Player)
		stopDrag(player)
	end
	Players.PlayerAdded:Connect(function(player: Player)
		player.CharacterRemoving:Connect(function()
			onCharacterRemoving(player)
		end)
	end)
	for _, player in ipairs(Players:GetPlayers()) do
		player.CharacterRemoving:Connect(function()
			onCharacterRemoving(player)
		end)
	end

	RunService.Heartbeat:Connect(cleanupDrags)
end

return InventoryService
