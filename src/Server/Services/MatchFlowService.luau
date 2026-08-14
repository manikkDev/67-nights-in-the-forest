--[[
    @file    MatchFlowService.luau
    @author  manik
    @date    2025

    @summary
    Server-authoritative lobby waiting room and match start.

    @description
    Teleporter pads enter Waiting instead of teleporting immediately.
    A host can START or wait for the countdown. Starting fades, then
    SpawnService teleports and TimeService begins Day 1.

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

export type FlowState = "Lobby" | "Waiting" | "Starting" | "InGame"

type Session = {
	state: FlowState,
	host: Player,
	players: { [Player]: boolean },
	endsAt: number,
	duration: number,
	timerThread: thread?,
}

-- | Configuration | --
local WAIT_SECONDS = Constants.MATCH_WAIT_SECONDS or 3599
local START_FADE_SECONDS = Constants.MATCH_START_FADE_SECONDS or 0.6

-- | State Management | --
local spawnService: any? = nil
local timeService: any? = nil
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
	sessions[owner] = nil
end

local function getSessionFor(player: Player): Session?
	return sessions[player]
end

function MatchFlowService:GetState(player: Player): FlowState
	local session = getSessionFor(player)
	if not session then
		return "Lobby"
	end
	return session.state
end

local function beginMatch(session: Session)
	if session.state ~= "Waiting" then
		return
	end

	cancelTimer(session)
	session.state = "Starting"
	fireToSession(session, MatchFlowService.Client.FlowStateChanged, "Starting")

	task.delay(START_FADE_SECONDS, function()
		if session.state ~= "Starting" then
			return
		end

		for player in pairs(session.players) do
			if player.Parent and spawnService then
				spawnService:SpawnPlayer(player)
			end
		end

		if timeService then
			timeService:StartMatch()
		end

		session.state = "InGame"
		fireToSession(session, MatchFlowService.Client.FlowStateChanged, "InGame")
		print("[MatchFlowService] Match started")
	end)
end

local function scheduleTimer(session: Session)
	cancelTimer(session)
	local remaining = math.max(0, session.endsAt - getServerNow())
	session.timerThread = task.delay(remaining, function()
		session.timerThread = nil
		beginMatch(session)
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

	local now = getServerNow()
	local session: Session = {
		state = "Waiting",
		host = player,
		players = { [player] = true },
		endsAt = now + WAIT_SECONDS,
		duration = WAIT_SECONDS,
		timerThread = nil,
	}
	sessions[player] = session
	scheduleTimer(session)

	MatchFlowService.Client.FlowStateChanged:Fire(player, "Waiting")
	MatchFlowService.Client.Countdown:Fire(player, {
		endsAt = session.endsAt,
		duration = session.duration,
	})
	MatchFlowService.Client.RosterChanged:Fire(player, buildRoster(session))
	print("[MatchFlowService] Waiting started for", player.Name)
end

function MatchFlowService:RequestStart(player: Player)
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
	beginMatch(session)
end

-- // INITIALIZATION // --

function MatchFlowService:KnitStart()
	spawnService = Knit.GetService("SpawnService")
	timeService = Knit.GetService("TimeService")

	MatchFlowService.Client.RequestStart:Connect(function(player: Player)
		MatchFlowService:RequestStart(player)
	end)
end

Players.PlayerRemoving:Connect(function(player)
	destroySession(player)
end)

return MatchFlowService
