--[[
    @file    MatchFlowService.luau
    @author  manik
    @date    2025

    @summary
    Server-authoritative lobby waiting room and match start.

    @description
    Teleporter pads open the Create Party UI. The host clicks Create,
    a 5-second countdown runs, the screen fades to the story text,
    then players are teleported while the screen is still dark. The
    Day 1 card appears on black, then the base map is slowly revealed.

    @exports
    - MatchFlowService:EnterWaiting(player)
    - MatchFlowService:GetState(player)
    - Client.RequestStart
    - Client.FlowStateChanged
    - Client.Countdown
    - Client.RosterChanged
]]

-- // VARIABLES // --

-- | Services | --
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- | Modules | --
local Knit = require(ReplicatedStorage.Packages.Knit)
local Constants = require(ReplicatedStorage.Shared.Constants)

-- | Objects | --
local MatchFlowService = Knit.CreateService({
	Name = "MatchFlowService",
	Client = {
		RequestStart = Knit.CreateSignal(),
		FlowStateChanged = Knit.CreateSignal(),
		Countdown = Knit.CreateSignal(),
		RosterChanged = Knit.CreateSignal(),
	},
})

export type FlowState = "Lobby" | "Waiting" | "Countdown" | "Story" | "Day1" | "InGame"

type Session = {
	state: FlowState,
	host: Player,
	players: { [Player]: boolean },
	endsAt: number,
	duration: number,
	timerThread: thread?,
}

-- | Configuration | --
local COUNTDOWN_SECONDS = Constants.MATCH_COUNTDOWN_SECONDS or 5
local STORY_FADE_SECONDS = Constants.MATCH_STORY_FADE_SECONDS or 1.2
local STORY_HOLD_SECONDS = Constants.MATCH_STORY_HOLD_SECONDS or 5
local DAY1_HOLD_SECONDS = Constants.MATCH_DAY1_HOLD_SECONDS or 2

-- | State Management | --
local spawnService: any = nil
local timeService: any = nil
local runStateService: any = nil
local sessions: { [Player]: Session } = {}

-- // FUNCTIONS // --

local function getServerNow(): number
	return workspace:GetServerTimeNow()
end

local function buildRoster(session: Session): { { userId: number, name: string, isHost: boolean } }
	local roster = {}
	for player in pairs(session.players) do
		if player.Parent then
			table.insert(roster, {
				userId = player.UserId,
				name = player.DisplayName,
				isHost = player == session.host,
			})
		end
	end
	table.sort(roster, function(a, b)
		if a.isHost ~= b.isHost then
			return a.isHost
		end
		return a.name < b.name
	end)
	return roster
end

local function fireToSession(session: Session, signal, ...)
	for player in pairs(session.players) do
		if player.Parent then
			signal:Fire(player, ...)
		end
	end
end

local function cancelTimer(session: Session)
	if session.timerThread then
		pcall(task.cancel, session.timerThread)
		session.timerThread = nil
	end
end

local function destroySession(owner: Player)
	local session = sessions[owner]
	if not session then
		return
	end
	cancelTimer(session)
	for player, mappedSession in pairs(sessions) do
		if mappedSession == session then
			sessions[player] = nil
		end
	end
end

local function getSessionFor(player: Player): Session?
	return sessions[player]
end

--[[
    @summary  Merge other waiting players into the host's pending run.
    @param    hostSession  Session
]]
local function mergeWaitingSessions(hostSession: Session)
	local candidates = {}
	local seen = {}
	for _, candidate in pairs(sessions) do
		if candidate ~= hostSession and candidate.state == "Waiting" and not seen[candidate] then
			seen[candidate] = true
			table.insert(candidates, candidate)
		end
	end

	local memberCount = 0
	for _ in pairs(hostSession.players) do
		memberCount += 1
	end
	for _, candidate in ipairs(candidates) do
		for player in pairs(candidate.players) do
			if memberCount >= Constants.MAX_PLAYERS then
				return
			end
			if player.Parent and not hostSession.players[player] then
				hostSession.players[player] = true
				sessions[player] = hostSession
				memberCount += 1
			end
		end
		cancelTimer(candidate)
	end
end

--[[
    @summary  Remove one player while preserving a viable shared session.
    @param    player  Player
]]
local function removePlayerFromSession(player: Player)
	local session = sessions[player]
	if not session then
		return
	end
	sessions[player] = nil
	session.players[player] = nil
	if not next(session.players) then
		cancelTimer(session)
		return
	end
	if session.host == player then
		session.host = next(session.players) :: Player
	end
	fireToSession(session, MatchFlowService.Client.RosterChanged, buildRoster(session))
end

function MatchFlowService:GetState(player: Player): FlowState
	local session = getSessionFor(player)
	if not session then
		return "Lobby"
	end
	return session.state
end

local function beginStory(session: Session)
	if session.state ~= "Countdown" then
		return
	end
	cancelTimer(session)
	session.state = "Story"
	fireToSession(session, MatchFlowService.Client.FlowStateChanged, "Story")

	-- Fade to black + story hold, then teleport while still dark.
	task.delay(STORY_FADE_SECONDS + STORY_HOLD_SECONDS, function()
		if (session.state :: FlowState) ~= "Story" then
			return
		end

		local participants = {}
		for player in pairs(session.players) do
			if player.Parent then
				table.insert(participants, player)
			end
		end

		local startedRunId = runStateService and runStateService:StartRun(participants) or nil
		if not startedRunId then
			session.state = "Waiting"
			fireToSession(session, MatchFlowService.Client.FlowStateChanged, "Waiting")
			fireToSession(session, MatchFlowService.Client.RosterChanged, buildRoster(session))
			return
		end

		for _, player in ipairs(participants) do
			if spawnService then
				spawnService:SpawnPlayer(player)
			end
		end

		if timeService then
			timeService:StartMatch()
		end

		session.state = "Day1"
		fireToSession(session, MatchFlowService.Client.FlowStateChanged, "Day1")

		-- Hold Day 1 on black, then reveal world and begin gameplay.
		task.delay(DAY1_HOLD_SECONDS, function()
			if (session.state :: FlowState) ~= "Day1" then
				return
			end
			session.state = "InGame"
			fireToSession(session, MatchFlowService.Client.FlowStateChanged, "InGame")
		end)
	end)
end

local function scheduleTimer(session: Session)
	cancelTimer(session)
	local remaining = math.max(0, session.endsAt - getServerNow())
	session.timerThread = task.delay(remaining, function()
		session.timerThread = nil
		beginStory(session)
	end)
end

--[[
    @summary  Put a player into the waiting room without teleporting.
    @desc    Idempotent. Solo-first: each player owns their own session.
]]
function MatchFlowService:EnterWaiting(player: Player)
	if not player or not player.Parent then
		return
	end

	local existing = getSessionFor(player)
	if existing then
		if existing.state == "Waiting" then
			MatchFlowService.Client.FlowStateChanged:Fire(player, "Waiting")
			MatchFlowService.Client.RosterChanged:Fire(player, buildRoster(existing))
		elseif existing.state == "Countdown" then
			MatchFlowService.Client.FlowStateChanged:Fire(player, "Countdown")
			MatchFlowService.Client.Countdown:Fire(player, {
				endsAt = existing.endsAt,
				duration = existing.duration,
			})
			MatchFlowService.Client.RosterChanged:Fire(player, buildRoster(existing))
		end
		return
	end

	if spawnService and spawnService:IsPlayerSpawned(player) then
		return
	end

	local session: Session = {
		state = "Waiting",
		host = player,
		players = { [player] = true },
		endsAt = 0,
		duration = 0,
		timerThread = nil,
	}
	sessions[player] = session

	MatchFlowService.Client.FlowStateChanged:Fire(player, "Waiting")
	MatchFlowService.Client.RosterChanged:Fire(player, buildRoster(session))
end

-- // INITIALIZATION // --

function MatchFlowService:KnitInit()
	-- Defensive: if Knit.Start didn't convert the SIGNAL_MARKERs, create the RemoteSignals ourselves.
	local comm = self.KnitComm
	if typeof(self.Client.RequestStart) ~= "table" then
		self.Client.RequestStart = comm:CreateSignal("RequestStart", false)
		self.Client.FlowStateChanged = comm:CreateSignal("FlowStateChanged", false)
		self.Client.Countdown = comm:CreateSignal("Countdown", false)
		self.Client.RosterChanged = comm:CreateSignal("RosterChanged", false)
	end
end

function MatchFlowService:KnitStart()
	spawnService = Knit.GetService("SpawnService")
	timeService = Knit.GetService("TimeService")
	runStateService = Knit.GetService("RunStateService")

	runStateService.RunCleaned:Connect(function()
		local uniqueSessions = {}
		for _, session in pairs(sessions) do
			if not uniqueSessions[session] then
				uniqueSessions[session] = true
				cancelTimer(session)
			end
		end
		sessions = {}
		for _, player in ipairs(Players:GetPlayers()) do
			MatchFlowService.Client.FlowStateChanged:Fire(player, "Lobby")
		end
	end)

	self.Client.RequestStart:Connect(function(player: Player)
		local session = getSessionFor(player)
		if not session then
			return
		end
		if session.host ~= player then
			return
		end
		if session.state ~= "Waiting" then
			return
		end

		mergeWaitingSessions(session)
		cancelTimer(session)
		local now = getServerNow()
		session.state = "Countdown"
		session.endsAt = now + COUNTDOWN_SECONDS
		session.duration = COUNTDOWN_SECONDS
		scheduleTimer(session)

		fireToSession(session, MatchFlowService.Client.FlowStateChanged, "Countdown")
		fireToSession(session, MatchFlowService.Client.Countdown, {
			endsAt = session.endsAt,
			duration = session.duration,
		})
		fireToSession(session, MatchFlowService.Client.RosterChanged, buildRoster(session))
	end)
end

Players.PlayerRemoving:Connect(removePlayerFromSession)

return MatchFlowService
