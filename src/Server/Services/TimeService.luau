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

    The clock stays paused until StartMatch() so lobby time does not
    consume Day 1.

    @exports
    - TimeService.DayStarted    (Knit Signal)
    - TimeService.NightStarted  (Knit Signal)
    - TimeService:GetCurrentPhase()  -> "Day" | "Night"
    - TimeService:GetClockTime()     -> number
    - TimeService:StartMatch()       -- begins the day/night clock
]]

-- // VARIABLES // --

-- | Services | --
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- | Modules | --
local Knit = require(ReplicatedStorage.Packages.Knit)
local ServerRole = require(ReplicatedStorage.Shared.ServerRole)
local RunConfig = require(ReplicatedStorage.Shared.RunConfig)

-- | Objects | --
local TimeService = Knit.CreateService({
	Name = "TimeService",
	Client = {
		DayStarted = Knit.CreateSignal(),
		NightStarted = Knit.CreateSignal(),
		DawnAdvanced = Knit.CreateSignal(),
		GetPhaseState = Knit.CreateProperty("Day"),
	},
})

-- | Configuration | --
local DAY_START_CLOCK = RunConfig.DayStartClock
local DAY_END_CLOCK = RunConfig.DayEndClock
local DAY_AMBIENT = Color3.fromRGB(128, 128, 128)
local NIGHT_AMBIENT = Color3.fromRGB(45, 48, 58)
local DAY_OUTDOOR_AMBIENT = Color3.fromRGB(128, 128, 128)
local NIGHT_OUTDOOR_AMBIENT = Color3.fromRGB(35, 38, 48)
local DAY_BRIGHTNESS = 1
local NIGHT_BRIGHTNESS = 0.6
local DAY_FOG_END = 100000
local NIGHT_FOG_END = 400
local TWEEN_DURATION = 8

-- | State Management | --
local currentPhase: "Day" | "Night" = "Day"
local phaseTimer = 0
local clockTime = DAY_START_CLOCK
local cycleIndex = 1
local displayedDay = 1
local isRunning = false
local heartbeatConnection: RBXScriptConnection? = nil
local multiplierProvider: (() -> number)? = nil
local dawnListeners: { (payload: { [string]: any }) -> () } = {}

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
    @summary  Return how many night cycles have actually been played.
    @desc     Scheduling (raids, entity unlocks, spawn scaling) must use
              this value, never the displayed progress value.
    @returns  number
]]
function TimeService:GetCycleIndex(): number
	return cycleIndex
end

--[[
    @summary  Return the survival progress value shown to players.
    @returns  number
]]
function TimeService:GetDisplayedDay(): number
	return displayedDay
end

--[[
    @summary  Return the scheduling cycle index.
    @returns  number
]]
function TimeService:GetDayNumber(): number
	return cycleIndex
end

function TimeService.Client:GetDayNumber(_player: Player): number
	return displayedDay
end

function TimeService.Client:GetProgress(_player: Player): { [string]: any }
	return {
		displayedDay = displayedDay,
		cycleIndex = cycleIndex,
		goalDay = RunConfig.GoalDay,
		phase = currentPhase,
	}
end

function TimeService:IsRunning(): boolean
	return isRunning
end

--[[
    @summary  Return the configured duration of the current phase.
    @returns  number
]]
function TimeService:GetPhaseDuration(): number
	return RunConfig.GetPhaseDuration(currentPhase)
end

--[[
    @summary  Return how many seconds have elapsed in the current phase.
    @returns  number
]]
function TimeService:GetPhaseElapsed(): number
	return phaseTimer
end

--[[
    @summary  Pause the clock without resetting run progress.
]]
function TimeService:Pause()
	isRunning = false
end

--[[
    @summary  Register the source of the current day multiplier.
    @param    provider  function  -- returns the current multiplier
]]
function TimeService:SetMultiplierProvider(provider: () -> number)
	multiplierProvider = provider
end

--[[
    @summary  Register a server listener for dawn progression.
    @param    listener  function  -- receives the dawn payload
]]
function TimeService:OnDawn(listener: (payload: { [string]: any }) -> ())
	table.insert(dawnListeners, listener)
end

--[[
    @summary  Return the currently active day multiplier.
    @returns  number
]]
local function getMultiplier(): number
	if not multiplierProvider then
		return RunConfig.BaseMultiplier
	end
	local ok, value = pcall(multiplierProvider)
	if not ok or typeof(value) ~= "number" then
		return RunConfig.BaseMultiplier
	end
	return math.clamp(math.floor(value), RunConfig.BaseMultiplier, RunConfig.MaxMultiplier)
end

--[[
    @summary  Tween Lighting properties to day values.
]]
local function transitionToDay()
	local tweenInfo = TweenInfo.new(TWEEN_DURATION, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
	TweenService:Create(Lighting, tweenInfo, {
		Ambient = DAY_AMBIENT,
		OutdoorAmbient = DAY_OUTDOOR_AMBIENT,
		Brightness = DAY_BRIGHTNESS,
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
		OutdoorAmbient = NIGHT_OUTDOOR_AMBIENT,
		Brightness = NIGHT_BRIGHTNESS,
		FogEnd = NIGHT_FOG_END,
	}):Play()
end

--[[
    @summary  Broadcast a signal to all clients.
    @desc    Knit signals do not have FireAll, so we iterate players.
    @param   signal  KnitSignal
]]
local function broadcastSignal(signal, ...)
	for _, player in ipairs(game:GetService("Players"):GetPlayers()) do
		signal:Fire(player, ...)
	end
end

--[[
    @summary  Switch to the day phase and apply survival progression.
]]
local function startDay()
	currentPhase = "Day"
	phaseTimer = 0
	cycleIndex += 1

	local multiplier = getMultiplier()
	local previousDay = displayedDay
	displayedDay = math.min(RunConfig.GoalDay, displayedDay + multiplier)

	transitionToDay()
	TimeService.Client.GetPhaseState:Set("Day")

	local payload = {
		previousDay = previousDay,
		displayedDay = displayedDay,
		cycleIndex = cycleIndex,
		multiplier = multiplier,
		goalDay = RunConfig.GoalDay,
		reachedGoal = displayedDay >= RunConfig.GoalDay,
	}

	broadcastSignal(TimeService.Client.DayStarted, cycleIndex)
	broadcastSignal(TimeService.Client.DawnAdvanced, payload)

	for _, listener in ipairs(dawnListeners) do
		task.spawn(listener, payload)
	end
end

--[[
    @summary  Switch to the night phase.
]]
local function startNight()
	currentPhase = "Night"
	phaseTimer = 0
	transitionToNight()
	TimeService.Client.GetPhaseState:Set("Night")
	broadcastSignal(TimeService.Client.NightStarted, cycleIndex)
end

--[[
    @summary  Heartbeat-driven time advancement.
    @param   dt  number  -- delta time in seconds
]]
local function onHeartbeat(dt: number)
	if not isRunning then
		return
	end

	phaseTimer += dt

	local duration = RunConfig.GetPhaseDuration(currentPhase)
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

local function applyDayLightingImmediate()
	Lighting.ClockTime = DAY_START_CLOCK
	Lighting.Ambient = DAY_AMBIENT
	Lighting.OutdoorAmbient = DAY_OUTDOOR_AMBIENT
	Lighting.Brightness = DAY_BRIGHTNESS
	Lighting.FogEnd = DAY_FOG_END
end

--[[
    @summary  Begin the day/night clock at the start of a run.
    @desc    Idempotent while already running.
]]
function TimeService:StartMatch()
	if isRunning then
		return
	end

	isRunning = true
	currentPhase = "Day"
	phaseTimer = 0
	clockTime = DAY_START_CLOCK
	cycleIndex = 1
	displayedDay = 1
	applyDayLightingImmediate()
	TimeService.Client.GetPhaseState:Set("Day")
	broadcastSignal(TimeService.Client.DayStarted, cycleIndex)
	broadcastSignal(TimeService.Client.DawnAdvanced, {
		previousDay = 1,
		displayedDay = 1,
		cycleIndex = 1,
		multiplier = getMultiplier(),
		goalDay = RunConfig.GoalDay,
		reachedGoal = false,
	})

	if not heartbeatConnection then
		heartbeatConnection = RunService.Heartbeat:Connect(onHeartbeat)
	end
end

--[[
    @summary  Stop the clock and restore the pre-run lighting baseline.
]]
function TimeService:ResetMatch()
	isRunning = false
	currentPhase = "Day"
	phaseTimer = 0
	clockTime = DAY_START_CLOCK
	cycleIndex = 1
	displayedDay = 1
	applyDayLightingImmediate()
	TimeService.Client.GetPhaseState:Set("Day")
	if heartbeatConnection then
		heartbeatConnection:Disconnect()
		heartbeatConnection = nil
	end
end

-- // INITIALIZATION // --

function TimeService:KnitStart()
	if not ServerRole.IsGameServer() then
		return
	end
	Lighting.ClockTime = DAY_START_CLOCK
	Lighting.Ambient = DAY_AMBIENT
	Lighting.OutdoorAmbient = DAY_OUTDOOR_AMBIENT
	Lighting.Brightness = DAY_BRIGHTNESS
	Lighting.FogEnd = DAY_FOG_END
end

return TimeService
