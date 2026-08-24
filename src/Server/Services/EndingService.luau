--[[
    @file    EndingService.luau
    @author  manik
    @date    2025

    @summary
    One-shot Day 67 victory or team-defeat transition, threat pause,
    result construction, idempotent lifetime records, and lobby return.
]]

-- // VARIABLES // --

-- | Services | --
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- | Modules | --
local Knit = require(ReplicatedStorage.Packages.Knit)
local RunConfig = require(ReplicatedStorage.Shared.RunConfig)

-- | Objects | --
local EndingService = Knit.CreateService({
	Name = "EndingService",
	Client = {
		EndingStarted = Knit.CreateSignal(),
		ResultsReady = Knit.CreateSignal(),
	},
})

-- | State Management | --
local runStateService: any = nil
local timeService: any = nil
local playerDataService: any = nil
local playerLifeService: any = nil
local rescueService: any = nil
local animalAIService: any = nil
local deerService: any = nil
local owlService: any = nil
local endingRunId = ""

-- // FUNCTIONS // --

--[[
    @summary  Return a player's finalized result and persistence payload.
    @param    player      Player
    @param    reason      string
    @param    endingData  table
    @returns  table
]]
local function buildPlayerResult(player: Player, reason: string, endingData): { [string]: any }
	local data = playerDataService:GetData(player)
	local stats = data and data.Stats or {}
	local displayedDay = timeService:GetDisplayedDay()
	local cycleIndex = timeService:GetCycleIndex()
	local victory = reason == "DAY_67"
	return {
		runId = endingRunId,
		reason = reason,
		victory = victory,
		displayedDay = displayedDay,
		goalDay = RunConfig.GoalDay,
		cycleIndex = cycleIndex,
		elapsedSeconds = endingData.elapsedSeconds or runStateService:GetElapsedSeconds(),
		multiplier = runStateService:GetMultiplier(),
		multiplierSources = runStateService:GetMultiplierSources(),
		childrenRescued = stats.ChildrenRescued or rescueService:GetRescuedCount(),
		structuresBuilt = stats.StructuresBuilt or 0,
		treesChopped = stats.TreesChopped or 0,
		wolvesKilled = stats.WolvesKilled or 0,
		cultistsKilled = stats.CultistsKilled or 0,
		revives = stats.Revives or 0,
		downs = stats.Downs or 0,
		deaths = if playerLifeService:GetLifeState(player) == "Eliminated" then 1 else 0,
	}
end

--[[
    @summary  Persist and deliver final results to every run member.
    @param    reason  string
    @param    data    table
]]
local function finalizeResults(reason: string, data)
	for _, player in ipairs(runStateService:GetMembers()) do
		local result = buildPlayerResult(player, reason, data)
		local saved, saveCode = playerDataService:ApplyRunRecords(player, endingRunId, result)
		result.recordSaved = saved
		result.recordSaveCode = saveCode
		EndingService.Client.ResultsReady:Fire(player, result)
	end
end

--[[
    @summary  Pause active threats and begin the shared result sequence.
    @param    reason  string
    @param    data    table
]]
local function onRunEnding(reason: string, data)
	local currentRunId = runStateService:GetRunId()
	if currentRunId == "" or endingRunId == currentRunId then
		return
	end
	endingRunId = currentRunId
	timeService:Pause()
	animalAIService:CleanupAll()
	deerService:ResetForRun()
	owlService:ResetForRun()

	local presentation = {
		reason = reason,
		victory = reason == "DAY_67",
		displayedDay = timeService:GetDisplayedDay(),
		cycleIndex = timeService:GetCycleIndex(),
		goalDay = RunConfig.GoalDay,
		elapsedSeconds = data.elapsedSeconds or runStateService:GetElapsedSeconds(),
	}
	for _, player in ipairs(runStateService:GetMembers()) do
		EndingService.Client.EndingStarted:Fire(player, presentation)
	end
	finalizeResults(reason, data)

	local capturedRunId = endingRunId
	task.delay(RunConfig.ResultsDisplaySeconds, function()
		if runStateService:GetRunId() == capturedRunId then
			runStateService:CleanupRun(reason)
			endingRunId = ""
		end
	end)
end

-- // INITIALIZATION // --

function EndingService:KnitStart()
	runStateService = Knit.GetService("RunStateService")
	timeService = Knit.GetService("TimeService")
	playerDataService = Knit.GetService("PlayerDataService")
	playerLifeService = Knit.GetService("PlayerLifeService")
	rescueService = Knit.GetService("RescueService")
	animalAIService = Knit.GetService("AnimalAIService")
	deerService = Knit.GetService("DeerService")
	owlService = Knit.GetService("OwlService")

	timeService:OnDawn(function(payload)
		if payload.reachedGoal == true then
			runStateService:BeginEnding("DAY_67", payload)
		end
	end)
	runStateService.RunEnding:Connect(onRunEnding)
end

return EndingService
