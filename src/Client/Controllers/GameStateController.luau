--[[
    @file    GameStateController.luau
    @author  manik
    @date    2025

    @summary
    Tracks whether the local player has entered the actual game map.

    @description
    Listens to SpawnService.PlayerSpawned and exposes a signal / query
    that other client controllers can use to hold back game UI/effects
    until the player teleports from the lobby to the base-map.

    @exports
    - GameStateController.GameStarted  -> Signal
    - GameStateController:IsInGame()   -> boolean
]]

-- // VARIABLES // --

-- | Services | --
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- | Modules | --
local Knit = require(ReplicatedStorage.Packages.Knit)
local Signal = require(ReplicatedStorage.Packages.Signal)

-- | Objects | --
local GameStateController = Knit.CreateController({
	Name = "GameStateController",
})

-- | State Management | --
local isInGame = false
local gameStartedSignal: any? = nil

-- // FUNCTIONS // --

--[[
    @summary  Returns true once the player has teleported to the game map.
    @returns  boolean
]]
function GameStateController:IsInGame(): boolean
	return isInGame
end

-- // INITIALIZATION // --

function GameStateController:KnitInit()
	gameStartedSignal = Signal.new()
	GameStateController.GameStarted = gameStartedSignal
end

function GameStateController:KnitStart()
	local spawnService = Knit.GetService("SpawnService")

	spawnService.PlayerSpawned:Connect(function()
		if isInGame then
			return
		end
		isInGame = true
		if gameStartedSignal then
			gameStartedSignal:Fire()
		end
		print("[GameStateController] Game started — player teleported to map")
	end)

	print("[GameStateController] Initialised")
end

return GameStateController
