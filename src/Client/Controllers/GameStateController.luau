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
	print("[GameStateController] Game started — intro complete")
end

-- // INITIALIZATION // --

function GameStateController:KnitInit()
	gameStartedSignal = Signal.new()
	GameStateController.GameStarted = gameStartedSignal
end

function GameStateController:KnitStart()
	local matchFlow = Knit.GetService("MatchFlowService")

	matchFlow.FlowStateChanged:Connect(function(state: string)
		if state == "Lobby" or state == "Waiting" or state == "Countdown" or state == "Story" or state == "Day1" then
			flowState = state
		elseif state == "InGame" then
			flowState = "Day1"
			-- Safety net: if IntroController is not present or already destroyed,
			-- mark intro complete so tools/HUD are unlocked.
			if not isInGame then
				task.wait(3)
				if not isInGame then
					GameStateController:MarkIntroComplete()
				end
			end
		end
	end)

	print("[GameStateController] Initialised")
end

return GameStateController
