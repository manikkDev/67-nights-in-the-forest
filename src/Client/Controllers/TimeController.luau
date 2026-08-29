--[[
    @file    TimeController.luau
    @author  manik
    @date    2025

    @summary
    Client-side listener for day/night phase changes.

    @description
    Subscribes to the server's DayStarted and NightStarted signals
    and triggers local-side reactions (UI indicators, ambient audio).
    Concrete UI and audio assets will be wired in a later phase; for
    now the controller exposes local signal hooks for downstream use.

    @exports
    - TimeController.DayStarted   (Signal, local)
    - TimeController.NightStarted (Signal, local)
]]

-- // VARIABLES // --

-- | Services | --
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- | Modules | --
local Knit = require(ReplicatedStorage.Packages.Knit)
local ServerRole = require(ReplicatedStorage.Shared.ServerRole)
local Signal = require(ReplicatedStorage.Packages.Signal)

-- | Objects | --
local TimeController = Knit.CreateController({
	Name = "TimeController",
})

-- | State Management | --
local dayStarted = Signal.new()
local nightStarted = Signal.new()

-- // FUNCTIONS // --

--[[
    @summary  Return the local DayStarted signal.
    @returns  Signal
]]
function TimeController:GetDayStartedSignal()
	return dayStarted
end

--[[
    @summary  Return the local NightStarted signal.
    @returns  Signal
]]
function TimeController:GetNightStartedSignal()
	return nightStarted
end

--[[
    @summary  Handler invoked when the server signals day has started.
]]
local function onDayStarted()
	dayStarted:Fire()
end

--[[
    @summary  Handler invoked when the server signals night has started.
]]
local function onNightStarted()
	nightStarted:Fire()
end

-- // INITIALIZATION // --

function TimeController:KnitStart()
	if not ServerRole.IsGameServer() then return end
	local timeService = Knit.GetService("TimeService")
	timeService.DayStarted:Connect(onDayStarted)
	timeService.NightStarted:Connect(onNightStarted)
end

return TimeController
