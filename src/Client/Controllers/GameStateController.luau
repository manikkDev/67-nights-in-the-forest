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
    @summary  Unlock gameplay after the Day 1 card fades out.
]]
function GameStateController:MarkIntroComplete()
	if isInGame then
		return
	end
	flowState = "InGame"
	isInGame = true
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

	-- On the game place (not lobby), there is no intro screen.
	-- Auto-mark as in-game after a short delay to unlock all gameplay
	-- (hover, drag, F-key, axe chopping, combat, flashlight, etc.).
	-- This is a safety net in case the server's FlowStateChanged signal
	-- is missed or delayed during the teleport transition.
	if not ServerRole.IsLobby() then
		print("[GameStateController] Game place detected — auto-completing intro in 2s")
		task.delay(2, function()
			if not isInGame then
				print("[GameStateController] Auto-completing intro (game place safety net)")
				GameStateController:MarkIntroComplete()
			end
		end)
	end

	matchFlow.FlowStateChanged:Connect(function(state: string)
		if state == "Lobby" or state == "Waiting" or state == "Countdown" or state == "Story" or state == "Day1" then
			flowState = state
			if state == "Lobby" then
				isInGame = false
			end
		elseif state == "InGame" then
			flowState = "Day1"
			-- Safety net: only unlock if this same run is still awaiting its intro.
			if not isInGame then
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
