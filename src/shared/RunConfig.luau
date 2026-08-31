--[[
    @file    RunConfig.luau
    @author  manik
    @date    2025

    @summary
    Central tuning and lifecycle configuration for a single forest run.

    @description
    Pure data module shared by server and client.  Replaces the scattered
    per-service test booleans from earlier phases: production values live
    at the top level and every debug override lives under StudioTest,
    which only applies while running inside Studio.
]]

local RunService = game:GetService("RunService")

local StudioTest = {
	Enabled = true,
	SkipLobby = true, -- TEMP: skip lobby for testing, revert to false when done
	ForceGameMode = false,
	GrantResources = true, -- TEMP: grant all resources for testing, revert to false when done
	InfiniteWood = false,
	FastClock = true, -- TEMP: 15s day/night for testing, revert to false when done
	ForceNight = false,
	VerboseFlashlight = true,
	VerboseStalkers = false,
	DayDuration = 30, -- TEMP: short day for testing, revert to 15 when done
	NightDuration = 60, -- TEMP: 60s night for testing, revert to 15 when done
}

local Config = {
	GoalDay = 67,

	DayDuration = 5, -- TEMP: revert to 180 when done
	NightDuration = 90,
	DayStartClock = 6,
	DayEndClock = 18,

	StartingHealth = 100,
	StartingHunger = 100,
	ConsumableHeal = {
		Berries = 5,
		Mushrooms = 6,
		RawMeat = 3,
		CookedMeat = 15,
	},

	BaseMultiplier = 1,
	MaxMultiplier = 9,

	RaidCycleInterval = 4,

	-- Difficulty is fixed from RunState's initial party size for the entire run.
	-- Counts and health rise conservatively; enemy damage is intentionally unchanged.
	Difficulty = {
		MaxPartySize = 5,
		HealthPerAdditionalPlayer = 0.12,
		CountPerAdditionalPlayer = 0.15,
	},

	DownedDuration = 45,
	ReviveHoldDuration = 5,
	ReviveHealth = 35,
	ReviveRange = 12,
	ReviveGracePeriod = 3,
	BodyDragStartRange = 12,
	BodyDragMaxDistance = 28,
	BodyDragUpdateInterval = 0.04,
	BodyDragResponsiveness = 35,

	PlacementGrid = 2,
	PlacementRotationDegrees = 15,
	PlacementMaxRange = 35,
	PlacementMaxSlope = 25,

	CampBuildRadius = 110,
	MaxStructures = 48,

	ResultsDisplaySeconds = 12,
	ReplayVoteSeconds = 30,
	ReplayRequestCooldown = 1.5,
	EarlyReturnCooldown = 1.5,

	StudioTest = StudioTest,
}

--[[
    @summary  Return whether a named Studio-only debug override is active.
    @param    flagName  string  -- key inside the StudioTest table
    @returns  boolean
]]
function Config.IsTestEnabled(flagName: string): boolean
	if not RunService:IsStudio() then
		return false
	end
	if not StudioTest.Enabled then
		return false
	end
	return StudioTest[flagName] == true
end

--[[
    @summary  Return the configured duration of a day or night phase.
    @param    phase  string  -- "Day" or "Night"
    @returns  number
]]
function Config.GetPhaseDuration(phase: string): number
	if Config.IsTestEnabled("FastClock") then
		return if phase == "Day" then StudioTest.DayDuration else StudioTest.NightDuration
	end
	return if phase == "Day" then Config.DayDuration else Config.NightDuration
end

local function normalizedPartySize(initialPartySize: number?): number
	local size = if typeof(initialPartySize) == "number" then math.floor(initialPartySize) else 1
	return math.clamp(size, 1, Config.Difficulty.MaxPartySize)
end

function Config.GetEnemyHealthMultiplier(initialPartySize: number?): number
	return 1 + (normalizedPartySize(initialPartySize) - 1) * Config.Difficulty.HealthPerAdditionalPlayer
end

function Config.GetEnemyCountMultiplier(initialPartySize: number?): number
	return 1 + (normalizedPartySize(initialPartySize) - 1) * Config.Difficulty.CountPerAdditionalPlayer
end

function Config.ScaleEnemyHealth(baseHealth: number, initialPartySize: number?): number
	if baseHealth <= 0 then
		return baseHealth
	end
	return math.max(baseHealth, math.round(baseHealth * Config.GetEnemyHealthMultiplier(initialPartySize)))
end

function Config.ScaleEnemyCount(baseCount: number, initialPartySize: number?): number
	if baseCount <= 0 then
		return 0
	end
	return math.max(baseCount, math.round(baseCount * Config.GetEnemyCountMultiplier(initialPartySize)))
end

return Config
