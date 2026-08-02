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
    now the controller logs phase transitions and exposes hooks.

    @exports
    - TimeController.DayStarted   (Signal, local)
    - TimeController.NightStarted (Signal, local)
]]

-- // VARIABLES // --

-- | Services | --
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")

-- | Modules | --
local Knit = require(ReplicatedStorage.Packages.Knit)
local Signal = require(ReplicatedStorage.Packages.Signal)

-- | Objects | --
local TimeController = Knit.CreateController({
	Name = "TimeController",
})

-- | State | --
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
	print("[TimeController] Day started — UI/audio hooks go here")
	dayStarted:Fire()
end

--[[
    @summary  Handler invoked when the server signals night has started.
]]
local function onNightStarted()
	print("[TimeController] Night started — UI/audio hooks go here")
	nightStarted:Fire()
end

-- // INITIALIZATION // --

Knit.Start:Connect(function()
	local timeService = Knit.GetService("TimeService")
	timeService.DayStarted:Connect(onDayStarted)
	timeService.NightStarted:Connect(onNightStarted)
end)
