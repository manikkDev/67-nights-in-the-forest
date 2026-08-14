--[[
    @file    HungerService.luau
    @author  manik
    @date    2025

    @summary
    Server-authoritative hunger decay and starvation damage.

    @description
    Drains each active player's Hunger stat over time, applying an
    accelerated drain while the player is moving faster than the
    sprint threshold.  When Hunger reaches zero, the player's Humanoid
    takes continuous starvation damage until they die or eat.
    Broadcasts throttled hunger updates to the owning client so the
    HUD can stay in sync.

    @exports
    - Knit Signal: HungerChanged(hunger: number, maxHunger: number)  (server -> client)
    - HungerService:RestoreHunger(player, amount)  -> void  (server only)
]]

-- // VARIABLES // --

-- | Services | --
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- | Modules | --
local Knit = require(ReplicatedStorage.Packages.Knit)

-- | Objects | --
local HungerService = Knit.CreateService({
	Name = "HungerService",
	Client = {
		HungerChanged = Knit.CreateSignal(),
	},
})

-- | Configuration | --
local HUNGER_DRAIN_PER_SEC = 100 / 600
local SPRINT_DRAIN_MULTIPLIER = 2
local SPRINT_SPEED_THRESHOLD = 20
local STARVE_DAMAGE_PER_SEC = 2
local BROADCAST_INTERVAL = 1

-- | State Management | --
local playerDataService: any? = nil
local spawnService: any? = nil
local broadcastTimer = 0

-- // FUNCTIONS // --

--[[
    @summary  Return true if the player's character is moving faster
              than the sprint threshold.
    @param    player  Player  -- the Roblox player
    @returns  boolean
]]
local function isSprinting(player: Player): boolean
	local character = player.Character
	if not character then
		return false
	end
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart or not rootPart:IsA("BasePart") then
		return false
	end
	return rootPart.AssemblyLinearVelocity.Magnitude > SPRINT_SPEED_THRESHOLD
end

--[[
    @summary  Drain one player's Hunger and apply starvation damage.
    @param    player  Player  -- the Roblox player
    @param    dt      number  -- delta time in seconds
]]
local function tickPlayer(player: Player, dt: number)
	if not playerDataService then
		return
	end
	if spawnService and not spawnService:IsPlayerSpawned(player) then
		return
	end
	local data = playerDataService:GetData(player)
	if not data then
		return
	end

	local drain = HUNGER_DRAIN_PER_SEC * dt
	if isSprinting(player) then
		drain *= SPRINT_DRAIN_MULTIPLIER
	end

	local newHunger = math.clamp(data.Survival.Hunger - drain, 0, data.Survival.MaxHunger)
	playerDataService:UpdateData(player, function(playerData)
		playerData.Survival.Hunger = newHunger
	end)

	if newHunger <= 0 then
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid:TakeDamage(STARVE_DAMAGE_PER_SEC * dt)
		end
	end
end

--[[
    @summary  Restore hunger for a player (e.g. after eating) and push
              an immediate update to their client.
    @param    player  Player  -- the Roblox player
    @param    amount  number  -- hunger units to restore (positive)
]]
function HungerService:RestoreHunger(player: Player, amount: number)
	if amount <= 0 then
		return
	end

	if not playerDataService then
		return
	end
	local data = playerDataService:GetData(player)
	if not data then
		return
	end

	local newHunger = math.clamp(data.Survival.Hunger + amount, 0, data.Survival.MaxHunger)
	playerDataService:UpdateData(player, function(playerData)
		playerData.Survival.Hunger = newHunger
	end)

	HungerService.Client.HungerChanged:Fire(player, newHunger, data.Survival.MaxHunger)
end

--[[
    @summary  Heartbeat-driven tick and throttled broadcast for all
              active players.
    @param    dt  number  -- delta time in seconds
]]
local function onHeartbeat(dt: number)
	for _, player in ipairs(Players:GetPlayers()) do
		tickPlayer(player, dt)
	end

	broadcastTimer += dt
	if broadcastTimer < BROADCAST_INTERVAL then
		return
	end
	broadcastTimer = 0

	if not playerDataService then
		return
	end
	for _, player in ipairs(Players:GetPlayers()) do
		if spawnService and not spawnService:IsPlayerSpawned(player) then
			continue
		end
		local data = playerDataService:GetData(player)
		if data then
			HungerService.Client.HungerChanged:Fire(player, data.Survival.Hunger, data.Survival.MaxHunger)
		end
	end
end

-- // INITIALIZATION // --

function HungerService:KnitStart()
	playerDataService = Knit.GetService("PlayerDataService")
	spawnService = Knit.GetService("SpawnService")
	RunService.Heartbeat:Connect(onHeartbeat)

	local function fireInitialHunger(player: Player)
		if not player.Parent then return end
		if not playerDataService then return end
		local data = playerDataService:GetData(player)
		if data then
			HungerService.Client.HungerChanged:Fire(player, data.Survival.Hunger, data.Survival.MaxHunger)
		end
	end

	playerDataService.ProfileLoaded:Connect(fireInitialHunger)

	for _, player in ipairs(Players:GetPlayers()) do
		fireInitialHunger(player)
	end

	print("[HungerService] Initialised — hunger drain active")
end

return HungerService
