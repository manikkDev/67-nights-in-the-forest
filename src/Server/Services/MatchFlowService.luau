--[[
    @file    MatchFlowService.luau
    @author  manik
    @date    2025

    @summary
    Server-authoritative isolated teleporter queues and match intro flow.

    @description
    Teleporter1/2/3 are independent queues. Each queue owns its capacity,
    roster, host migration, countdown, and party identity. Published parties
    route to reserved servers; Studio starts the same party locally.
]]

-- // VARIABLES // --

-- | Services | --
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

-- | Modules | --
local Knit = require(ReplicatedStorage.Packages.Knit)
local Constants = require(ReplicatedStorage.Shared.Constants)

-- | Objects | --
local MatchFlowService = Knit.CreateService({
	Name = "MatchFlowService",
	Client = {
		RequestStart = Knit.CreateSignal(),
		RequestLeave = Knit.CreateSignal(),
		RequestSetCapacity = Knit.CreateSignal(),
		FlowStateChanged = Knit.CreateSignal(),
		Countdown = Knit.CreateSignal(),
		RosterChanged = Knit.CreateSignal(),
		SessionChanged = Knit.CreateSignal(),
	},
})

export type FlowState = "Lobby" | "Waiting" | "Countdown" | "Story" | "Day1" | "InGame"

type Session = {
	queueId: string,
	partyId: string,
	state: FlowState,
	host: Player,
	players: { [Player]: boolean },
	memberOrder: { Player },
	capacity: number,
	endsAt: number,
	duration: number,
	timerThread: thread?,
	routing: boolean,
}

-- | Configuration | --
local COUNTDOWN_SECONDS = Constants.MATCH_COUNTDOWN_SECONDS or 5
local STORY_FADE_SECONDS = Constants.MATCH_STORY_FADE_SECONDS or 1.2
local STORY_HOLD_SECONDS = Constants.MATCH_STORY_HOLD_SECONDS or 5
local DAY1_HOLD_SECONDS = Constants.MATCH_DAY1_HOLD_SECONDS or 2
local MIN_PARTY = Constants.PARTY_MIN_PLAYERS or 1
local MAX_PARTY = Constants.PARTY_MAX_PLAYERS or 5
local REQUEST_COOLDOWN = Constants.PARTY_REQUEST_COOLDOWN or 0.35

-- | State Management | --
local spawnService: any = nil
local timeService: any = nil
local runStateService: any = nil
local sessionRoutingService: any = nil
local sessionsByPlayer: { [Player]: Session } = {}
local sessionsByQueue: { [string]: Session } = {}
local lastRequestAt: { [Player]: number } = {}

-- // FUNCTIONS // --

-- | Session Snapshots | --
local function isQueueId(queueId: any): boolean
	if typeof(queueId) ~= "string" then
		return false
	end
	for _, allowed in ipairs(Constants.PARTY_QUEUE_IDS or {}) do
		if queueId == allowed then
			return true
		end
	end
	return false
end

local function getServerNow(): number
	return workspace:GetServerTimeNow()
end

local function rosterFor(session: Session): { { userId: number, name: string, username: string, isHost: boolean } }
	local roster = {}
	for _, player in ipairs(session.memberOrder) do
		if session.players[player] and player.Parent == Players then
			table.insert(roster, {
				userId = player.UserId,
				name = player.DisplayName,
				username = player.Name,
				isHost = player == session.host,
			})
		end
	end
	return roster
end

local function snapshotFor(session: Session, viewer: Player): { [string]: any }
	return {
		state = session.state,
		queueId = session.queueId,
		partyId = session.partyId,
		hostUserId = session.host.UserId,
		isHost = session.host == viewer,
		capacity = session.capacity,
		roster = rosterFor(session),
		endsAt = session.endsAt,
		duration = session.duration,
	}
end

local function fireToSession(session: Session, signal, ...)
	for player in pairs(session.players) do
		if player.Parent == Players then
			signal:Fire(player, ...)
		end
	end
end

local function broadcastSession(session: Session)
	local roster = rosterFor(session)
	for player in pairs(session.players) do
		if player.Parent == Players then
			MatchFlowService.Client.RosterChanged:Fire(player, roster)
			MatchFlowService.Client.SessionChanged:Fire(player, snapshotFor(session, player))
		end
	end
end

local function rateLimited(player: Player): boolean
	local now = os.clock()
	local previous = lastRequestAt[player] or 0
	if now - previous < REQUEST_COOLDOWN then
		return true
	end
	lastRequestAt[player] = now
	return false
end

-- | Queue Lifecycle | --
local function cancelTimer(session: Session)
	if session.timerThread then
		pcall(task.cancel, session.timerThread)
		session.timerThread = nil
	end
end

local function setState(session: Session, state: FlowState)
	session.state = state
	fireToSession(session, MatchFlowService.Client.FlowStateChanged, state)
	broadcastSession(session)
end

local function selectNextHost(session: Session): Player?
	for _, candidate in ipairs(session.memberOrder) do
		if session.players[candidate] and candidate.Parent == Players then
			return candidate
		end
	end
	return nil
end

local function removePlayerFromSession(player: Player, returnToLobby: boolean?)
	local session = sessionsByPlayer[player]
	if not session then
		return
	end
	sessionsByPlayer[player] = nil
	session.players[player] = nil
	if session.state == "Countdown" then
		cancelTimer(session)
		session.endsAt = 0
		session.duration = 0
		session.state = "Waiting"
	end
	if not next(session.players) then
		cancelTimer(session)
		sessionsByQueue[session.queueId] = nil
	else
		if session.host == player then
			session.host = selectNextHost(session) :: Player
		end
		if session.state == "Waiting" then
			fireToSession(session, MatchFlowService.Client.FlowStateChanged, "Waiting")
		end
		broadcastSession(session)
	end
	if player.Parent == Players then
		MatchFlowService.Client.FlowStateChanged:Fire(player, "Lobby")
		MatchFlowService.Client.SessionChanged:Fire(player, { state = "Lobby" })
		if returnToLobby and spawnService then
			spawnService:ReturnToLobby(player)
		end
	end
end

local function participantsFor(session: Session): { Player }
	local participants = {}
	for _, player in ipairs(session.memberOrder) do
		if session.players[player] and player.Parent == Players then
			table.insert(participants, player)
		end
	end
	return participants
end

-- | Run Start | --
local function startRun(participants: { Player }, metadata: { [string]: any }, session: Session?): boolean
	local startedRunId = runStateService and runStateService:StartRun(participants, metadata) or nil
	if not startedRunId then
		if session then
			session.routing = false
			setState(session, "Waiting")
		end
		return false
	end

	if session then
		for _, player in ipairs(participants) do
			sessionsByPlayer[player] = session
		end
	end
	if spawnService then
		spawnService:SpawnParty(participants)
	end
	if timeService then
		timeService:StartMatch()
	end

	if session then
		setState(session, "Day1")
	else
		for _, player in ipairs(participants) do
			MatchFlowService.Client.FlowStateChanged:Fire(player, "Day1")
		end
	end
	task.delay(DAY1_HOLD_SECONDS, function()
		if not runStateService or not runStateService:IsCurrentRun(startedRunId) then
			return
		end
		if session then
			setState(session, "InGame")
		else
			for _, player in ipairs(participants) do
				if player.Parent == Players and runStateService:IsMember(player) then
					MatchFlowService.Client.FlowStateChanged:Fire(player, "InGame")
				end
			end
		end
	end)
	return true
end

local function beginStory(session: Session)
	if session.state ~= "Countdown" then
		return
	end
	cancelTimer(session)
	setState(session, "Story")
	task.delay(STORY_FADE_SECONDS + STORY_HOLD_SECONDS, function()
		if session.state ~= "Story" or session.routing then
			return
		end
		local participants = participantsFor(session)
		if #participants == 0 then
			return
		end
		session.routing = true
		local accepted = sessionRoutingService
			and sessionRoutingService:RouteParty(session.partyId, session.host.UserId, participants)
		if not accepted then
			session.routing = false
			setState(session, "Waiting")
		end
	end)
end

local function scheduleTimer(session: Session)
	cancelTimer(session)
	session.timerThread = task.delay(math.max(0, session.endsAt - getServerNow()), function()
		session.timerThread = nil
		beginStory(session)
	end)
end

function MatchFlowService:EnterWaiting(player: Player, queueId: string)
	if not player or player.Parent ~= Players or not isQueueId(queueId) then
		return
	end
	local existing = sessionsByPlayer[player]
	if existing then
		MatchFlowService.Client.FlowStateChanged:Fire(player, existing.state)
		MatchFlowService.Client.SessionChanged:Fire(player, snapshotFor(existing, player))
		MatchFlowService.Client.RosterChanged:Fire(player, rosterFor(existing))
		return
	end
	if spawnService and spawnService:IsPlayerSpawned(player) then
		return
	end

	local session = sessionsByQueue[queueId]
	if session then
		if session.state ~= "Waiting" or #rosterFor(session) >= session.capacity then
			return
		end
		session.players[player] = true
		table.insert(session.memberOrder, player)
		sessionsByPlayer[player] = session
	else
		session = {
			queueId = queueId,
			partyId = HttpService:GenerateGUID(false),
			state = "Waiting",
			host = player,
			players = { [player] = true },
			memberOrder = { player },
			capacity = MIN_PARTY,
			endsAt = 0,
			duration = 0,
			timerThread = nil,
			routing = false,
		}
		sessionsByQueue[queueId] = session
		sessionsByPlayer[player] = session
	end
	MatchFlowService.Client.FlowStateChanged:Fire(player, "Waiting")
	broadcastSession(session)
end

function MatchFlowService:GetState(player: Player): FlowState
	local session = sessionsByPlayer[player]
	return if session then session.state else "Lobby"
end

function MatchFlowService.Client:GetSnapshot(player: Player): { [string]: any }
	local session = sessionsByPlayer[player]
	return if session then snapshotFor(session, player) else { state = "Lobby" }
end

-- // INITIALIZATION // --

function MatchFlowService:KnitInit()
	-- Preserve compatibility with this project's Knit build when signal markers
	-- have not yet been converted during service construction.
	local comm = self.KnitComm
	if typeof(self.Client.RequestStart) ~= "table" then
		self.Client.RequestStart = comm:CreateSignal("RequestStart", false)
		self.Client.RequestLeave = comm:CreateSignal("RequestLeave", false)
		self.Client.RequestSetCapacity = comm:CreateSignal("RequestSetCapacity", false)
		self.Client.FlowStateChanged = comm:CreateSignal("FlowStateChanged", false)
		self.Client.Countdown = comm:CreateSignal("Countdown", false)
		self.Client.RosterChanged = comm:CreateSignal("RosterChanged", false)
		self.Client.SessionChanged = comm:CreateSignal("SessionChanged", false)
	end
end

function MatchFlowService:KnitStart()
	spawnService = Knit.GetService("SpawnService")
	timeService = Knit.GetService("TimeService")
	runStateService = Knit.GetService("RunStateService")
	sessionRoutingService = Knit.GetService("SessionRoutingService")

	self.Client.RequestSetCapacity:Connect(function(player: Player, requested: any)
		if rateLimited(player) or typeof(requested) ~= "number" then
			return
		end
		local session = sessionsByPlayer[player]
		local capacity = math.floor(requested)
		if not session or session.host ~= player or session.state ~= "Waiting"
			or capacity < MIN_PARTY or capacity > MAX_PARTY or capacity < #rosterFor(session)
		then
			return
		end
		session.capacity = capacity
		broadcastSession(session)
	end)

	self.Client.RequestLeave:Connect(function(player: Player)
		if not rateLimited(player) then
			removePlayerFromSession(player, true)
		end
	end)

	self.Client.RequestStart:Connect(function(player: Player)
		if rateLimited(player) then
			return
		end
		local session = sessionsByPlayer[player]
		if not session or session.host ~= player or session.state ~= "Waiting" or session.routing then
			return
		end
		local count = #rosterFor(session)
		if count < MIN_PARTY or count > session.capacity then
			return
		end
		session.state = "Countdown"
		session.endsAt = getServerNow() + COUNTDOWN_SECONDS
		session.duration = COUNTDOWN_SECONDS
		scheduleTimer(session)
		fireToSession(session, MatchFlowService.Client.FlowStateChanged, "Countdown")
		fireToSession(session, MatchFlowService.Client.Countdown, {
			endsAt = session.endsAt,
			duration = session.duration,
		})
		broadcastSession(session)
	end)

	sessionRoutingService.LocalPartyReady:Connect(function(participants, metadata)
		local session = sessionsByQueue[metadata.queueId or ""]
		if not session then
			for _, candidate in pairs(sessionsByQueue) do
				if candidate.partyId == metadata.partyId then
					session = candidate
					break
				end
			end
		end
		startRun(participants, metadata, session)
	end)

	sessionRoutingService.DestinationReady:Connect(function(participants, metadata)
		startRun(participants, metadata, nil)
	end)

	sessionRoutingService.PartyTeleportFailed:Connect(function(partyId)
		for _, session in pairs(sessionsByQueue) do
			if session.partyId == partyId and session.state == "Story" then
				session.routing = false
				setState(session, "Waiting")
				break
			end
		end
	end)

	runStateService.RunCleaned:Connect(function()
		local unique = {}
		for _, session in pairs(sessionsByQueue) do
			if not unique[session] then
				unique[session] = true
				cancelTimer(session)
			end
		end
		sessionsByPlayer = {}
		sessionsByQueue = {}
		for _, player in ipairs(Players:GetPlayers()) do
			MatchFlowService.Client.FlowStateChanged:Fire(player, "Lobby")
			MatchFlowService.Client.SessionChanged:Fire(player, { state = "Lobby" })
		end
	end)
end

Players.PlayerRemoving:Connect(function(player)
	lastRequestAt[player] = nil
	removePlayerFromSession(player, false)
end)

return MatchFlowService
