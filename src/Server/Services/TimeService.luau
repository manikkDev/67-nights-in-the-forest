--[[
    @file    TimeService.luau
    @author  manik
    @date    2025

    @summary
    Server-authoritative day/night cycle controller.

    @description
    Advances in-game time via a Heartbeat loop, fires Knit Signals
    when day or night begins, and drives Lighting transitions with
    TweenService for smooth visual changes.

    @exports
    - TimeService.DayStarted    (Knit Signal)
    - TimeService.NightStarted  (Knit Signal)
    - TimeService:GetCurrentPhase()  -> "Day" | "Night"
    - TimeService:GetClockTime()     -> number
]]

-- // VARIABLES // --

-- | Services | --
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- | Modules | --
local Knit = require(ReplicatedStorage.Packages.Knit)

-- | Constants | --
local DAY_DURATION = 120
local NIGHT_DURATION = 120
local DAY_START_CLOCK = 6
local DAY_END_CLOCK = 18
local DAY_AMBIENT = Color3.fromRGB(128, 128, 128)
local NIGHT_AMBIENT = Color3.fromRGB(20, 22, 32)
local DAY_FOG_END = 100000
local NIGHT_FOG_END = 80
local TWEEN_DURATION = 8

-- | Objects | --
local TimeService = Knit.CreateService({
	Name = "TimeService",
	Client = {
		DayStarted = Knit.CreateSignal(),
		NightStarted = Knit.CreateSignal(),
		GetPhaseState = Knit.CreateProperty("Day"),
	},
})

-- | State | --
local currentPhase: "Day" | "Night" = "Day"
local phaseTimer = 0
local clockTime = DAY_START_CLOCK
local dayNumber = 1

-- // FUNCTIONS // --

--[[
    @summary  Return the current phase string.
    @returns  "Day" | "Night"
]]
function TimeService:GetCurrentPhase(): string
	return currentPhase
end

--[[
    @summary  Return the current in-game clock time (0–24).
    @returns  number
]]
function TimeService:GetClockTime(): number
	return clockTime
end

--[[
    @summary  Return the current day number (starts at 1).
    @returns  number
]]
function TimeService:GetDayNumber(): number
	return dayNumber
end

--[[
    @summary  Tween Lighting properties to day values.
]]
local function transitionToDay()
	local tweenInfo = TweenInfo.new(TWEEN_DURATION, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
	TweenService:Create(Lighting, tweenInfo, {
		Ambient = DAY_AMBIENT,
		FogEnd = DAY_FOG_END,
	}):Play()
end

--[[
    @summary  Tween Lighting properties to night values.
]]
local function transitionToNight()
	local tweenInfo = TweenInfo.new(TWEEN_DURATION, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
	TweenService:Create(Lighting, tweenInfo, {
		Ambient = NIGHT_AMBIENT,
		FogEnd = NIGHT_FOG_END,
	}):Play()
end

--[[
    @summary  Broadcast a signal to all clients.
    @desc    Knit signals do not have FireAll, so we iterate players.
    @param   signal  KnitSignal
]]
local function broadcastSignal(signal)
	for _, player in ipairs(game:GetService("Players"):GetPlayers()) do
		signal:Fire(player)
	end
end

--[[
    @summary  Switch to the day phase.
]]
local function startDay()
	currentPhase = "Day"
	phaseTimer = 0
	dayNumber += 1
	transitionToDay()
	TimeService.Client.GetPhaseState:Set("Day")
	broadcastSignal(TimeService.Client.DayStarted)
	print("[TimeService] Day", dayNumber, "started")
end

--[[
    @summary  Switch to the night phase.
]]
local function startNight()
	currentPhase = "Night"
	phaseTimer = 0
	transitionToNight()
	TimeService.Client.GetPhaseState:Set("Night")
	broadcastSignal(TimeService.Client.NightStarted)
	print("[TimeService] Night", dayNumber, "started")
end

--[[
    @summary  Heartbeat-driven time advancement.
    @param   dt  number  -- delta time in seconds
]]
local function onHeartbeat(dt: number)
	phaseTimer += dt

	local duration = if currentPhase == "Day" then DAY_DURATION else NIGHT_DURATION
	local progress = phaseTimer / duration
	clockTime = if currentPhase == "Day"
		then DAY_START_CLOCK + (DAY_END_CLOCK - DAY_START_CLOCK) * progress
		else (DAY_END_CLOCK + (DAY_END_CLOCK - DAY_START_CLOCK) * progress) % 24

	Lighting.ClockTime = clockTime

	if phaseTimer >= duration then
		if currentPhase == "Day" then
			startNight()
		else
			startDay()
		end
	end
end

-- // INITIALIZATION // --

Lighting.ClockTime = DAY_START_CLOCK
Lighting.Ambient = DAY_AMBIENT
Lighting.FogEnd = DAY_FOG_END

RunService.Heartbeat:Connect(onHeartbeat)

print("[TimeService] Initialised — starting in Day phase")

return TimeService
