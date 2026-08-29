--[[
    @file    EndingService.luau
    @author  manik
    @date    2025

    @summary
    One-shot Day 67 victory or team-defeat transition, threat pause,
    result construction, idempotent lifetime records, individual lobby
    return, and unanimous vote-to-replay for team defeat.

    @description
    The ending sequence is server-authoritative. Each run member may
    individually return to the lobby without forcing the rest of the
    team out. On team defeat, members may vote to replay; the run only
    restarts when every still-connected member votes yes within the
    configured window. The host may also cancel a pending vote. All
    client requests are rate-limited and validated against the live
    run token so stale or duplicate requests are rejected.
]]

-- // VARIABLES // --

-- | Services | --
local Players = game:GetService("Players")
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
		ReplayVoteChanged = Knit.CreateSignal(),
		ReplayVoteResolved = Knit.CreateSignal(),
		IndividualReturnAck = Knit.CreateSignal(),
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
local spawnService: any = nil
local matchFlowService: any = nil

local endingRunId = ""
local endingReason = ""
local isVictory = false
local autoCleanupTask: thread? = nil

-- Replay vote state (team defeat only)
local replayVotes: { [Player]: boolean } = {}
local replayVoteDeadline = 0
local replayVoteTask: thread? = nil
local replayVoteActive = false

-- Per-player request cooldowns
local returnCooldowns: { [Player]: number } = {}
local voteCooldowns: { [Player]: number } = {}

-- // FUNCTIONS // --

-- | Helpers | --

local function remainingMembers(): { Player }
	local list = {}
	for _, player in ipairs(runStateService:GetMembers()) do
		if player.Parent == Players then
			table.insert(list, player)
		end
	end
	return list
end

local function broadcastToMembers(signal, ...)
	for _, player in ipairs(remainingMembers()) do
		signal:Fire(player, ...)
	end
end

local function buildVoteSnapshot(): { [string]: any }
	local yes = {}
	local pending = {}
	for _, player in ipairs(remainingMembers()) do
		if replayVotes[player] == true then
			table.insert(yes, player.UserId)
		else
			table.insert(pending, player.UserId)
		end
	end
	table.sort(yes)
	table.sort(pending)
	return {
		active = replayVoteActive,
		deadline = replayVoteDeadline,
		yesUserIds = yes,
		pendingUserIds = pending,
		hostUserId = runStateService:GetHostUserId(),
	}
end

local function fireVoteChanged()
	local snapshot = buildVoteSnapshot()
	broadcastToMembers(EndingService.Client.ReplayVoteChanged, snapshot)
end

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
		canReplay = not victory,
	}
end

--[[
    @summary  Persist and deliver final results to every run member.
    @param    reason  string
    @param    data    table
]]
local function finalizeResults(reason: string, data)
	for _, player in ipairs(remainingMembers()) do
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
	endingReason = reason
	isVictory = reason == "DAY_67"
	timeService:Pause()
	animalAIService:CleanupAll()
	deerService:ResetForRun()
	owlService:ResetForRun()

	local presentation = {
		reason = reason,
		victory = isVictory,
		displayedDay = timeService:GetDisplayedDay(),
		cycleIndex = timeService:GetCycleIndex(),
		goalDay = RunConfig.GoalDay,
		elapsedSeconds = data.elapsedSeconds or runStateService:GetElapsedSeconds(),
		canReplay = not isVictory,
	}
	broadcastToMembers(EndingService.Client.EndingStarted, presentation)
	finalizeResults(reason, data)

	-- Start replay vote window for team defeat only.
	if not isVictory then
		replayVoteActive = true
		replayVotes = {}
		replayVoteDeadline = workspace:GetServerTimeNow() + RunConfig.ReplayVoteSeconds
		fireVoteChanged()
		if replayVoteTask then
			task.cancel(replayVoteTask)
		end
		replayVoteTask = task.delay(RunConfig.ReplayVoteSeconds, function()
			if endingRunId == currentRunId and replayVoteActive then
				replayVoteActive = false
				broadcastToMembers(EndingService.Client.ReplayVoteResolved, { outcome = "timeout" })
			end
		end)
	end

	-- Auto-cleanup after the results display window. The window is extended
	-- by the replay vote duration on team defeat so players have time to vote.
	local cleanupDelay = RunConfig.ResultsDisplaySeconds
	if not isVictory then
		cleanupDelay = math.max(cleanupDelay, RunConfig.ReplayVoteSeconds + 2)
	end
	if autoCleanupTask then
		task.cancel(autoCleanupTask)
	end
	autoCleanupTask = task.delay(cleanupDelay, function()
		if runStateService:GetRunId() == currentRunId and endingRunId == currentRunId then
			runStateService:CleanupRun(reason)
			endingRunId = ""
			endingReason = ""
			replayVoteActive = false
			replayVotes = {}
			replayVoteDeadline = 0
		end
	end)
end

--[[
    @summary  Reset all ending state when the run is cleaned.
]]
local function onRunCleaned()
	endingRunId = ""
	endingReason = ""
	replayVoteActive = false
	replayVotes = {}
	replayVoteDeadline = 0
	if replayVoteTask then
		task.cancel(replayVoteTask)
		replayVoteTask = nil
	end
	if autoCleanupTask then
		task.cancel(autoCleanupTask)
		autoCleanupTask = nil
	end
end

--[[
    @summary  Return one player to the lobby without ending the run for others.
    @desc    The player is removed from the run member set and teleported to
             the lobby. The run continues for any remaining members. If the
             departing player was the last connected member, the run cleans up.
    @param   player  Player
]]
local function returnPlayerToLobby(player: Player)
	if not runStateService:IsMember(player) then
		return
	end
	-- Remove from member set so subsequent broadcasts skip them.
	runStateService:RemoveMember(player)
	replayVotes[player] = nil
	returnCooldowns[player] = nil
	voteCooldowns[player] = nil
	spawnService:ReturnToLobby(player)
	EndingService.Client.IndividualReturnAck:Fire(player, { success = true })
	-- If nobody remains, clean up the run.
	if #remainingMembers() == 0 then
		if autoCleanupTask then
			task.cancel(autoCleanupTask)
			autoCleanupTask = nil
		end
		if replayVoteTask then
			task.cancel(replayVoteTask)
			replayVoteTask = nil
		end
		runStateService:CleanupRun(endingReason ~= "" and endingReason or "EARLY_RETURN")
		endingRunId = ""
		endingReason = ""
		replayVoteActive = false
		replayVotes = {}
	else
		fireVoteChanged()
	end
end

--[[
    @summary  Check whether every remaining member has voted yes and replay.
]]
local function evaluateReplayVote()
	if not replayVoteActive then
		return
	end
	local members = remainingMembers()
	if #members == 0 then
		return
	end
	for _, player in ipairs(members) do
		if replayVotes[player] ~= true then
			return
		end
	end
	-- Unanimous. Cancel pending tasks and restart the run.
	replayVoteActive = false
	if replayVoteTask then
		task.cancel(replayVoteTask)
		replayVoteTask = nil
	end
	if autoCleanupTask then
		task.cancel(autoCleanupTask)
		autoCleanupTask = nil
	end
	broadcastToMembers(EndingService.Client.ReplayVoteResolved, { outcome = "replay" })
	local capturedPartyId = runStateService:GetPartyId()
	local capturedHostId = runStateService:GetHostUserId()
	local capturedInitialSize = runStateService:GetInitialPartySize()
	local participants = {}
	for _, player in ipairs(members) do
		table.insert(participants, player)
	end
	-- Clean up the old run first, then start a fresh one with the same party.
	runStateService:CleanupRun("REPLAY")
	endingRunId = ""
	endingReason = ""
	replayVotes = {}
	if matchFlowService and capturedPartyId ~= "" then
		matchFlowService:StartRunForReplay(participants, {
			partyId = capturedPartyId,
			hostUserId = capturedHostId,
			initialPartySize = capturedInitialSize,
		})
	else
		runStateService:StartRun(participants, {
			partyId = capturedPartyId,
			hostUserId = capturedHostId,
			initialPartySize = capturedInitialSize,
		})
	end
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
	spawnService = Knit.GetService("SpawnService")
	matchFlowService = Knit.GetService("MatchFlowService")

	timeService:OnDawn(function(payload)
		if payload.reachedGoal == true then
			runStateService:BeginEnding("DAY_67", payload)
		end
	end)
	runStateService.RunEnding:Connect(onRunEnding)
	runStateService.RunCleaned:Connect(onRunCleaned)

	-- Individual lobby return. Only the calling player is returned; the
	-- run continues for any remaining members.
	EndingService.Client.RequestEarlyReturn:Connect(function(player)
		if endingRunId == "" or not runStateService:IsMember(player) then
			return
		end
		local now = os.clock()
		if returnCooldowns[player] and now - returnCooldowns[player] < RunConfig.EarlyReturnCooldown then
			return
		end
		returnCooldowns[player] = now
		returnPlayerToLobby(player)
	end)

	-- Vote to replay (team defeat only).
	EndingService.Client.RequestReplayVote:Connect(function(player)
		if endingRunId == "" or not replayVoteActive or not runStateService:IsMember(player) then
			return
		end
		local now = os.clock()
		if voteCooldowns[player] and now - voteCooldowns[player] < RunConfig.ReplayRequestCooldown then
			return
		end
		voteCooldowns[player] = now
		replayVotes[player] = true
		fireVoteChanged()
		evaluateReplayVote()
	end)

	-- Cancel a replay vote (host only).
	EndingService.Client.RequestReplayCancel:Connect(function(player)
		if endingRunId == "" or not replayVoteActive or not runStateService:IsMember(player) then
			return
		end
		if player.UserId ~= runStateService:GetHostUserId() then
			return
		end
		replayVoteActive = false
		replayVotes = {}
		replayVoteDeadline = 0
		if replayVoteTask then
			task.cancel(replayVoteTask)
			replayVoteTask = nil
		end
		broadcastToMembers(EndingService.Client.ReplayVoteResolved, { outcome = "cancelled" })
	end)

	Players.PlayerRemoving:Connect(function(player)
		replayVotes[player] = nil
		returnCooldowns[player] = nil
		voteCooldowns[player] = nil
		if replayVoteActive then
			task.defer(function()
				if replayVoteActive and endingRunId ~= "" then
					fireVoteChanged()
					evaluateReplayVote()
				end
			end)
		end
	end)
end

return EndingService
