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
local BASE_CAPACITY = 40
local BAG_CAPACITY_BONUS = 40
local ITEMS_PATH = ServerStorage.Assets[Constants.ITEMS_PATH]
local CARRY_BAG_NAME = "carry-bag"
local RESOURCE_NAMES = { "Wood", "Stone", "Berries", "Mushrooms", "RawMeat", "CookedMeat" }

-- | State Management | --
local playerDataService: any? = nil

-- // FUNCTIONS // --

--[[
    @summary  Return the maximum total resource units a player can carry.
    @param    player  Player  -- the Roblox player
    @returns  number
]]
function InventoryService:GetCapacity(player: Player): number
	local data = playerDataService:GetData(player)
	if not data then
		return BASE_CAPACITY
	end
	local capacity = BASE_CAPACITY
	if data.Inventory and data.Inventory.HasBag then
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
	local data = playerDataService:GetData(player)
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
	local data = playerDataService:GetData(player)
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

	local data = playerDataService:GetData(player)
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

	playerDataService:UpdateData(player, function(playerData)
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

	local data = playerDataService:GetData(player)
	if not data or (data.Resources[name] or 0) < amount then
		return false
	end

	playerDataService:UpdateData(player, function(playerData)
		playerData.Resources[name] -= amount
	end)

	broadcastSnapshot(player)
	return true
end

--[[
    @summary  Weld a cloned carry-bag onto a character's back.
    @desc     Uses a manual Motor6D weld rather than the Accessory system
              so it works regardless of rig type or attachment naming.
    @param    character  Model  -- the player's character
]]
local function equipCarryBag(character: Model)
	if character:FindFirstChild("CarryBag") then
		return
	end

	local torso = character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso")
	if not torso or not torso:IsA("BasePart") then
		task.defer(function()
			if character.Parent then
				equipCarryBag(character)
			end
		end)
		return
	end

	local source = ITEMS_PATH:FindFirstChild(CARRY_BAG_NAME)
	if not source then
		warn("[InventoryService] carry-bag asset not found in Assets Items")
		return
	end

	local bag = source:Clone()
	bag.Name = "CarryBag"
	bag.Anchored = false
	bag.CanCollide = false
	bag.CanQuery = false
	bag.CanTouch = false
	bag.Massless = true
	bag.Parent = character

	local weld = Instance.new("Motor6D")
	weld.Name = "CarryBagWeld"
	weld.Part0 = torso
	weld.Part1 = bag
	weld.C0 = CFrame.new(0, 0.1, torso.Size.Z / 2 + bag.Size.Z / 2 - 0.3) * CFrame.Angles(0, math.rad(180), 0)
	weld.Parent = torso
end

--[[
    @summary  Equip the carry-bag on a player's current and future characters.
    @param    player  Player  -- the Roblox player
]]
local function watchForBag(player: Player)
	if player.Character then
		equipCarryBag(player.Character)
	end
	player.CharacterAdded:Connect(equipCarryBag)
end

-- // CLIENT REMOTES // --

--[[
    @summary  Client-facing remote returning a one-shot resources/capacity snapshot.
    @param    player  Player  -- injected by Knit
    @returns  { resources: table, capacity: number } | nil
]]
function InventoryService.Client:GetSnapshot(player: Player)
	local data = playerDataService:GetData(player)
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

	playerDataService.ProfileLoaded:Connect(function(player: Player)
		watchForBag(player)
		broadcastSnapshot(player)
	end)

	for _, player in ipairs(Players:GetPlayers()) do
		if playerDataService:GetData(player) then
			watchForBag(player)
		end
	end

	print("[InventoryService] Initialised — capacity & carry-bag active")
end

return InventoryService
