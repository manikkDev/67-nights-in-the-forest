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
	GrantResources = true, -- TEMP: grant all resources for testing, revert to false when done
	InfiniteWood = false,
	FastClock = true, -- TEMP: 15s day/night for testing, revert to false when done
	ForceNight = false,
	VerboseFlashlight = true,
	VerboseStalkers = false,
}

local Config = {
	GoalDay = 67,

	DayDuration = 300, -- TEMP: 300s for testing, revert to 180 when done
	NightDuration = 90,
	DayStartClock = 6,
	DayEndClock = 18,

	StartingHealth = 1000, -- TEMP: 1000 HP for testing, revert to 100 when done
	StartingHunger = 100,

	BaseMultiplier = 1,
	MaxMultiplier = 9,

	RaidCycleInterval = 4,

	DownedDuration = 45,
	ReviveHoldDuration = 5,
	ReviveHealth = 35,
	ReviveRange = 12,
	ReviveGracePeriod = 3,

	PlacementGrid = 2,
	PlacementRotationDegrees = 15,
	PlacementMaxRange = 35,
	PlacementMaxSlope = 25,

	CampBuildRadius = 110,
	MaxStructures = 48,

	ResultsDisplaySeconds = 12,

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
		return if phase == "Day" then Config.DayDuration else Config.NightDuration
	end
	return if phase == "Day" then Config.DayDuration else Config.NightDuration
end

return Config
