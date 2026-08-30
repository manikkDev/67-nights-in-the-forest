--[[
    @file    GameStateController.luau
    @author  manik
    @date    2025

    @summary
    Tracks whether the local player has entered the actual game.

    @description
    Follows MatchFlowService states. GameStarted fires only after the
    Day 1 intro card finishes, so HUD/tools stay gated through waiting
    and the teleport fade.

    On the game place (not lobby), there is no intro screen, so the
    controller auto-marks as in-game immediately and never resets.

    @exports
    - GameStateController.GameStarted  -> Signal
    - GameStateController:IsInGame()   -> boolean
    - GameStateController:GetState()   -> string
    - GameStateController:MarkIntroComplete()
]]

-- // VARIABLES // --

-- | Services | --
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- | Modules | --
local Knit = require(ReplicatedStorage.Packages.Knit)
local Signal = require(ReplicatedStorage.Packages.Signal)
local ServerRole = require(ReplicatedStorage.Shared.ServerRole)

-- | Objects | --
local GameStateController = Knit.CreateController({
	Name = "GameStateController",
})

export type FlowState = "Lobby" | "Waiting" | "Countdown" | "Story" | "Day1" | "InGame"

-- | State Management | --
local flowState: FlowState = "Lobby"
local isInGame = false
local gameStartedSignal: any = nil
-- On the game place, the player is always in the game. This flag prevents
-- any FlowStateChanged = "Lobby" signal from resetting isInGame to false.
local isGamePlace = false

-- // FUNCTIONS // --

--[[
    @summary  Returns true once the player has teleported to the game map.
    @returns  boolean
]]
function GameStateController:IsInGame(): boolean
	return isInGame
end

function GameStateController:GetState(): FlowState
	return flowState
end

--[[
    @summary  Unlock gameplay after the Day 1 intro fades out (lobby place),
              or immediately on the game place.
]]
function GameStateController:MarkIntroComplete()
	if isInGame then
		return
	end
	flowState = "InGame"
	isInGame = true
	print("[GameStateController] MarkIntroComplete — isInGame now true")
	if gameStartedSignal then
		gameStartedSignal:Fire()
	end
end

-- // INITIALIZATION // --

function GameStateController:KnitInit()
	gameStartedSignal = Signal.new()
	GameStateController.GameStarted = gameStartedSignal
end

function GameStateController:KnitStart()
	local matchFlow = Knit.GetService("MatchFlowService")

	-- Detect whether we're on the game place (not lobby).
	-- On the game place, there is no intro screen and no lobby state.
	-- The player is always in the game, so we mark as in-game immediately.
	isGamePlace = ServerRole.IsGameServer() and not ServerRole.IsLobby()
	print(("[GameStateController] KnitStart — isGamePlace=%s IsGameServer=%s IsLobby=%s")
		:format(tostring(isGamePlace), tostring(ServerRole.IsGameServer()), tostring(ServerRole.IsLobby())))

	if isGamePlace then
		print("[GameStateController] Game place detected — marking in-game immediately")
		GameStateController:MarkIntroComplete()
	else
		-- Lobby place: wait for the intro card to finish.
		-- The IntroController calls MarkIntroComplete() after the Day 1 card fades.
		-- Also listen for the server's FlowStateChanged as a safety net.
	end

	matchFlow.FlowStateChanged:Connect(function(state: string)
		if state == "Lobby" or state == "Waiting" or state == "Countdown" or state == "Story" or state == "Day1" then
			flowState = state
			-- Only reset isInGame on the LOBBY place. On the game place,
			-- the player is always in the game and should never go back to lobby.
			if state == "Lobby" and not isGamePlace then
				isInGame = false
			end
		elseif state == "InGame" then
			flowState = "Day1"
			-- Safety net on the lobby place: unlock if the intro hasn't fired yet.
			if not isInGame and not isGamePlace then
				task.delay(3, function()
					if not isInGame and flowState == "Day1" then
						GameStateController:MarkIntroComplete()
					end
				end)
			end
		end
	end)

end

return GameStateController
