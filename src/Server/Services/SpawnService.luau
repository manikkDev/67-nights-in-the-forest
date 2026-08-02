--[[
    @file    SpawnService.luau
    @author  manik
    @date    2025

    @summary
    Server-authoritative lobby-to-game teleportation.

    @description
    Provides a Knit Remote that the client can invoke (e.g. via a
    "Play" button) to request teleportation from the lobby to the
    base-map.  The server validates the request, calculates a random
    position around the Campfire, and teleports the character.

    @exports
    - Knit Remote: RequestSpawn  -> void  (client -> server)
    - SpawnService:SpawnPlayer(player)    (server only)
]]

-- // VARIABLES // --

-- | Services | --
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- | Modules | --
local Knit = require(ReplicatedStorage.Packages.Knit)

-- | Constants | --
local SPAWN_RADIUS = 12
local SPAWN_HEIGHT = 5

-- | Objects | --
local SpawnService = Knit.CreateService({
	Name = "SpawnService",
	Client = {
		RequestSpawn = Knit.CreateSignal(),
	},
})

-- | State | --
local worldService: any? = nil
local spawnedPlayers: { [Player]: boolean } = {}

-- // FUNCTIONS // --

--[[
    @summary  Teleport a player's character to a random point around the Campfire.
    @desc    Uses math.random so players do not stack on each other.
             Server-authoritative — the client cannot choose a position.
    @param   player  Player  -- the Roblox player
]]
function SpawnService:SpawnPlayer(player: Player)
	if spawnedPlayers[player] then
		return
	end

	local character = player.Character
	if not character then
		return
	end

	local primaryPart = character:FindFirstChild("HumanoidRootPart") or character.PrimaryPart
	if not primaryPart then
		return
	end

	local campfireCFrame = worldService:GetCampfireCFrame()
	if not campfireCFrame then
		warn("[SpawnService] Campfire CFrame not available")
		return
	end

	local angle = math.random() * math.pi * 2
	local offsetX = math.cos(angle) * SPAWN_RADIUS
	local offsetZ = math.sin(angle) * SPAWN_RADIUS

	local targetCFrame = campfireCFrame * CFrame.new(offsetX, SPAWN_HEIGHT, offsetZ)
	primaryPart.CFrame = targetCFrame

	spawnedPlayers[player] = true
end

--[[
    @summary  Client-facing remote requesting teleportation to the game map.
    @desc    The server validates that the player has not already spawned
             and that a character exists before teleporting.
    @param   player  Player  -- injected by Knit
]]
function SpawnService.Client:RequestSpawn(player: Player)
	self.Server:SpawnPlayer(player)
end

-- // INITIALIZATION // --

Knit.Start:Connect(function()
	worldService = Knit.GetService("WorldService")
end)
