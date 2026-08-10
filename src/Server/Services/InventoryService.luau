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

-- | Modules | --
local Knit = require(ReplicatedStorage.Packages.Knit)
local Constants = require(ReplicatedStorage.Shared.Constants)

-- | Objects | --
local InventoryService = Knit.CreateService({
	Name = "InventoryService",
	Client = {
		ResourcesChanged = Knit.CreateSignal(),
	},
})

-- | Configuration | --
local BASE_CAPACITY = 5
local BAG_CAPACITY_BONUS = 0
local ITEMS_PATH = ServerStorage.Assets[Constants.ITEMS_PATH]
local CARRY_BAG_NAME = "carry-bag"
local CARRY_BAG_TOOL_NAME = "Carry Bag"
local RESOURCE_NAMES = { "Wood", "Stone", "Berries", "Mushrooms", "RawMeat", "CookedMeat" }

local PICKUP_RANGE = 6
local DROP_SPACING = 2.2
local DROP_LIFETIME = 300

-- Map resources to the asset name in ITEMS_PATH.  Mushrooms are built procedurally.
local DROP_ASSETS: { [string]: string? } = {
	Wood = "Log",
	Stone = "Coal",
	Berries = "Carrot",
	RawMeat = "rabbit-meat",
	CookedMeat = "wolf-meat",
}

-- | State Management | --
local playerDataService: any? = nil
local worldService: any? = nil
local bagTemplate: Tool? = nil

-- // FUNCTIONS // --

local function getPlayerData(player: Player): any?
	if not playerDataService then
		return nil
	end
	return playerDataService:GetData(player)
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
    @summary  Fire the client-facing resources snapshot for one player.
    @param    player  Player  -- the Roblox player
]]
local function broadcastSnapshot(player: Player)
	local data = getPlayerData(player)
	if not data then
		return
	end
	InventoryService.Client.ResourcesChanged:Fire(player, table.clone(data.Resources), InventoryService:GetCapacity(player))
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
		playerData.Resources[name] += actualAmount
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

	local data = getPlayerData(player)
	if not data or (data.Resources[name] or 0) < amount then
		return false
	end

	updatePlayerData(player, function(playerData)
		playerData.Resources[name] -= amount
	end)

	broadcastSnapshot(player)
	return true
end

-- // PICKUP / DROP // --

--[[
    @summary  Build a small procedural mushroom for dropping.
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
	stem.CFrame = CFrame.Angles(0, 0, math.rad(90))
	stem.Parent = model

	local cap = Instance.new("Part")
	cap.Name = "Cap"
	cap.Shape = Enum.PartType.Ball
	cap.Size = Vector3.new(0.7, 0.45, 0.7)
	cap.Color = Color3.fromRGB(170, 60, 55)
	cap.Material = Enum.Material.SmoothPlastic
	cap.CFrame = CFrame.new(0, 0.3, 0)
	cap.Parent = model

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = stem
	weld.Part1 = cap
	weld.Parent = stem

	model.PrimaryPart = stem
	return model
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
			fallback.Size = Vector3.new(1, 1, 1)
			fallback.Color = Color3.fromRGB(180, 180, 180)
			fallback.Material = Enum.Material.SmoothPlastic
			fallback.Parent = model
			model.PrimaryPart = fallback
		end
	end

	-- Prepare physics: let them fall and rest on the ground.
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Anchored = false
			descendant.CanCollide = true
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
    @summary  Validate and process a generic resource pickup.
    @param    model   Model   -- the world item to pick up
    @param    player  Player  -- the picking player
    @returns  boolean
]]
local function tryPickup(model: Model, player: Player): boolean
	if not model.Parent then
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

				local model = buildDropModel(resourceName)
				model:PivotTo(CFrame.new(position) * CFrame.Angles(0, math.random() * math.pi * 2, 0))
				model.Parent = baseMap
				Debris:AddItem(model, DROP_LIFETIME)
			end

			updatePlayerData(player, function(playerData)
				playerData.Resources[resourceName] = 0
			end)
		end
	end

	if droppedAny then
		broadcastSnapshot(player)
	end
	return true
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
local function giveCarryBag(player: Player)
	if not bagTemplate then
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
	playerDataService = Knit.GetService("PlayerDataService")
	worldService = Knit.GetService("WorldService")

	bagTemplate = buildCarryBagTool()

	playerDataService.ProfileLoaded:Connect(function(player: Player)
		giveCarryBag(player)
		broadcastSnapshot(player)
	end)

	for _, player in ipairs(Players:GetPlayers()) do
		if getPlayerData(player) then
			giveCarryBag(player)
		end
	end

	print("[InventoryService] Initialised — capacity & carry-bag tool active")
end

return InventoryService
