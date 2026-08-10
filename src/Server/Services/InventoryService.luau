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

local PICKUP_RANGE = 12
local DROP_SPACING = 2.2
local DROP_LIFETIME = 300

local DRAG_ATTACHMENT_OFFSET = Vector3.new(0, 1, -3)
local DRAG_MAX_DISTANCE = 50

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

local dragging: { [Player]: { model: Model, alignPos: AlignPosition, alignOri: AlignOrientation, playerAttach: Attachment, itemAttach: Attachment, originalCanCollide: { [BasePart]: boolean } } } = {}
local draggedBy: { [Model]: Player } = {}

-- // FUNCTIONS // --

local function getPlayerData(player: Player): any?
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

	local data = getPlayerData(player)
	if not data or (data.Resources[name] or 0) < amount then
		return false
	end

	updatePlayerData(player, function(playerData)
		playerData.Resources[name] -= amount

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

	local model = buildDropModel(resourceName)
	model:PivotTo(CFrame.new(position) * CFrame.Angles(0, math.random() * math.pi * 2, 0))
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
	if entry.playerAttach then
		entry.playerAttach:Destroy()
	end
	if entry.itemAttach then
		entry.itemAttach:Destroy()
	end

	local model = entry.model
	if model and model.Parent then
		for _, desc in ipairs(model:GetDescendants()) do
			if desc:IsA("BasePart") then
				if entry.originalCanCollide[desc] ~= nil then
					desc.CanCollide = entry.originalCanCollide[desc]
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

	-- Only allow dragging dropped items and felled logs, not live forage spawns.
	if model:GetAttribute("ForageResource") and not model:GetAttribute("Resource") and not model:GetAttribute("PickupResource") then
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
	for _, desc in ipairs(model:GetDescendants()) do
		if desc:IsA("BasePart") then
			originalCanCollide[desc] = desc.CanCollide
			desc.Anchored = false
			desc.CanCollide = false
		end
	end

	pcall(function()
		primaryPart:SetNetworkOwner(player)
	end)

	local playerAttach = Instance.new("Attachment")
	playerAttach.Name = "DragPlayerAttachment"
	playerAttach.Position = DRAG_ATTACHMENT_OFFSET
	playerAttach.Parent = hrp

	local itemAttach = Instance.new("Attachment")
	itemAttach.Name = "DragItemAttachment"
	itemAttach.Position = Vector3.zero
	itemAttach.Parent = primaryPart

	local alignPos = Instance.new("AlignPosition")
	alignPos.Name = "DragAlignPosition"
	alignPos.Attachment0 = itemAttach
	alignPos.Attachment1 = playerAttach
	alignPos.RigidityEnabled = false
	alignPos.Responsiveness = 25
	alignPos.MaxForce = 1e5
	alignPos.ApplyAtCenterOfMass = true
	alignPos.Parent = primaryPart

	local alignOri = Instance.new("AlignOrientation")
	alignOri.Name = "DragAlignOrientation"
	alignOri.Attachment0 = itemAttach
	alignOri.Attachment1 = playerAttach
	alignOri.RigidityEnabled = false
	alignOri.Responsiveness = 20
	alignOri.MaxTorque = 1e5
	alignOri.Parent = primaryPart

	dragging[player] = {
		model = model,
		alignPos = alignPos,
		alignOri = alignOri,
		playerAttach = playerAttach,
		itemAttach = itemAttach,
		originalCanCollide = originalCanCollide,
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

	print("[InventoryService] Initialised — capacity & carry-bag tool active")
end

return InventoryService
