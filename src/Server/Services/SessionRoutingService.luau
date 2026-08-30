--[[
    @file    SessionRoutingService.luau
    @author  manik
    @date    2025

    @summary
    Securely routes lobby parties into isolated reserved run servers.

    @description
    Public servers reserve this same place and attach server-authored party
    metadata. Reserved destinations validate every arrival and wait for both
    the expected party and their profiles. Studio uses the same interface but
    returns the local party instead of calling TeleportService.
]]

-- // VARIABLES // --

-- | Services | --
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService = game:GetService("TeleportService")
local MemoryStoreService = game:GetService("MemoryStoreService")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")

-- | Modules | --
local Knit = require(ReplicatedStorage.Packages.Knit)
local Signal = require(ReplicatedStorage.Packages.Signal)
local Constants = require(ReplicatedStorage.Shared.Constants)

-- | Objects | --
local SessionRoutingService = Knit.CreateService({
	Name = "SessionRoutingService",
	Client = {},
})

SessionRoutingService.LocalPartyReady = Signal.new()
SessionRoutingService.DestinationReady = Signal.new()
SessionRoutingService.PartyTeleportFailed = Signal.new()

-- | Configuration | --
local DATA_VERSION = Constants.PARTY_TELEPORT_DATA_VERSION or 1
local MAX_DATA_AGE = Constants.PARTY_TELEPORT_DATA_MAX_AGE or 120
local DESTINATION_WAIT = Constants.PARTY_DESTINATION_WAIT_SECONDS or 30
local TICKET_TTL = Constants.PARTY_RECONNECT_TICKET_SECONDS or 120
local MIN_PARTY = Constants.PARTY_MIN_PLAYERS or 1
local MAX_PARTY = Constants.PARTY_MAX_PLAYERS or 5
local TICKET_MAP = MemoryStoreService:GetHashMap("ForestRunReconnectTicketsV1")

-- | State Management | --
local playerDataService: any = nil
local destinationStarted = false
local destinationMetadata: { [string]: any }? = nil
local destinationPlayers: { [number]: Player } = {}
local pendingTeleports: { [Player]: string } = {}

-- // FUNCTIONS // --

-- | Validation | --
local function copyUserIds(players: { Player }): { number }
	local ids = {}
	for _, player in ipairs(players) do
		table.insert(ids, player.UserId)
	end
	table.sort(ids)
	return ids
end

local function validMetadata(data: any): boolean
	if typeof(data) ~= "table"
		or data.version ~= DATA_VERSION
		or typeof(data.partyId) ~= "string"
		or #data.partyId < 8
		or typeof(data.hostUserId) ~= "number"
		or typeof(data.initialPartySize) ~= "number"
		or typeof(data.expectedUserIds) ~= "table"
		or typeof(data.issuedAt) ~= "number"
	then
		return false
	end
	if data.initialPartySize < MIN_PARTY or data.initialPartySize > MAX_PARTY then
		return false
	end
	if #data.expectedUserIds ~= data.initialPartySize or math.abs(os.time() - data.issuedAt) > MAX_DATA_AGE then
		return false
	end
	local seen = {}
	local hostFound = false
	for _, userId in ipairs(data.expectedUserIds) do
		if typeof(userId) ~= "number" or userId <= 0 or seen[userId] then
			return false
		end
		seen[userId] = true
		hostFound = hostFound or userId == data.hostUserId
	end
	return hostFound
end

local function metadataMatches(a: { [string]: any }, b: { [string]: any }): boolean
	if a.partyId ~= b.partyId or a.hostUserId ~= b.hostUserId or #a.expectedUserIds ~= #b.expectedUserIds then
		return false
	end
	local expected = {}
	for _, userId in ipairs(a.expectedUserIds) do
		expected[userId] = true
	end
	for _, userId in ipairs(b.expectedUserIds) do
		if not expected[userId] then
			return false
		end
	end
	return true
end

local function isExpected(data: { [string]: any }, userId: number): boolean
	for _, expectedId in ipairs(data.expectedUserIds) do
		if expectedId == userId then
			return true
		end
	end
	return false
end

-- | Reconnect Tickets | --
function SessionRoutingService:WriteReconnectTicket(partyId: string, userId: number, accessCode: string): boolean
	local ok = pcall(function()
		TICKET_MAP:SetAsync(('%s:%d'):format(partyId, userId), {
			partyId = partyId,
			userId = userId,
			accessCode = accessCode,
			expiresAt = os.time() + TICKET_TTL,
		}, TICKET_TTL)
	end)
	return ok
end

function SessionRoutingService:GetReconnectTicket(partyId: string, userId: number): { [string]: any }?
	local ok, ticket = pcall(function()
		return TICKET_MAP:GetAsync(('%s:%d'):format(partyId, userId))
	end)
	if not ok or typeof(ticket) ~= "table" or ticket.userId ~= userId or ticket.partyId ~= partyId then
		return nil
	end
	if typeof(ticket.expiresAt) ~= "number" or ticket.expiresAt < os.time() then
		return nil
	end
	return ticket
end

function SessionRoutingService:ConsumeReconnectTicket(partyId: string, userId: number)
	pcall(function()
		TICKET_MAP:RemoveAsync(('%s:%d'):format(partyId, userId))
	end)
end

-- | Routing | --
function SessionRoutingService:IsReservedRunServer(): boolean
	return not RunService:IsStudio() and game.PrivateServerId ~= "" and game.PrivateServerOwnerId == 0
end

function SessionRoutingService:RouteParty(partyId: string, hostUserId: number, players: { Player }): boolean
	if typeof(partyId) ~= "string" or #players < MIN_PARTY or #players > MAX_PARTY then
		return false
	end
	local livePlayers = {}
	for _, player in ipairs(players) do
		if player.Parent == Players then
			table.insert(livePlayers, player)
		end
	end
	if #livePlayers ~= #players then
		return false
	end
	local metadata = {
		version = DATA_VERSION,
		partyId = partyId,
		hostUserId = hostUserId,
		initialPartySize = #livePlayers,
		expectedUserIds = copyUserIds(livePlayers),
		issuedAt = os.time(),
		sourceJobId = game.JobId,
		nonce = HttpService:GenerateGUID(false),
	}
	if not validMetadata(metadata) then
		return false
	end

	if RunService:IsStudio() then
		task.spawn(function()
			local deadline = os.clock() + DESTINATION_WAIT
			while os.clock() < deadline do
				local ready = playerDataService ~= nil
				for _, player in ipairs(livePlayers) do
					if player.Parent ~= Players or not ready or not playerDataService:GetData(player) then
						ready = false
						break
					end
				end
				if ready then
					SessionRoutingService.LocalPartyReady:Fire(livePlayers, metadata)
					return
				end
				task.wait(0.25)
			end
			SessionRoutingService.PartyTeleportFailed:Fire(partyId, livePlayers, "Profiles were not ready")
		end)
		return true
	end
	if self:IsReservedRunServer() then
		return false
	end

	local reserveOk, accessCode = pcall(function()
		return TeleportService:ReserveServerAsync(game.PlaceId)
	end)
	if not reserveOk or typeof(accessCode) ~= "string" then
		warn("[SessionRoutingService] Could not reserve run server:", accessCode)
		return false
	end

	for _, player in ipairs(livePlayers) do
		pendingTeleports[player] = partyId
		self:WriteReconnectTicket(partyId, player.UserId, accessCode)
	end
	local options = Instance.new("TeleportOptions")
	options.ReservedServerAccessCode = accessCode
	options:SetTeleportData(metadata)
	local teleportOk, teleportError = pcall(function()
		TeleportService:TeleportAsync(game.PlaceId, livePlayers, options)
	end)
	if not teleportOk then
		for _, player in ipairs(livePlayers) do
			pendingTeleports[player] = nil
		end
		warn("[SessionRoutingService] Party teleport failed:", teleportError)
		SessionRoutingService.PartyTeleportFailed:Fire(partyId, livePlayers, tostring(teleportError))
		return false
	end
	return true
end

-- | Destination Assembly | --
local function rejectArrival(player: Player, reason: string)
	warn(("[SessionRoutingService] Rejected %s: %s"):format(player.Name, reason))
	player:Kick("This reserved run invitation is invalid or expired.")
end

local function registerDestinationPlayer(player: Player)
	if destinationStarted then
		rejectArrival(player, "run already started")
		return
	end
	local joinData = player:GetJoinData()
	local metadata = joinData and joinData.TeleportData
	if not validMetadata(metadata) or not isExpected(metadata, player.UserId) then
		rejectArrival(player, "invalid party metadata")
		return
	end
	if destinationMetadata and not metadataMatches(destinationMetadata, metadata) then
		rejectArrival(player, "party metadata mismatch")
		return
	end
	destinationMetadata = destinationMetadata or metadata
	destinationPlayers[player.UserId] = player
	SessionRoutingService:ConsumeReconnectTicket(metadata.partyId, player.UserId)
end

local function assembleDestination()
	local deadline = os.clock() + DESTINATION_WAIT
	while not destinationStarted and os.clock() < deadline do
		local metadata = destinationMetadata
		if metadata then
			local allReady = true
			for _, userId in ipairs(metadata.expectedUserIds) do
				local player = destinationPlayers[userId]
				if not player or player.Parent ~= Players or not playerDataService or not playerDataService:GetData(player) then
					allReady = false
					break
				end
			end
			if allReady then
				break
			end
		end
		task.wait(0.25)
	end
	if destinationStarted or not destinationMetadata then
		return
	end
	local participants = {}
	for _, userId in ipairs(destinationMetadata.expectedUserIds) do
		local player = destinationPlayers[userId]
		if player and player.Parent == Players and playerDataService and playerDataService:GetData(player) then
			table.insert(participants, player)
		end
	end
	if #participants == 0 then
		return
	end
	destinationStarted = true
	SessionRoutingService.DestinationReady:Fire(participants, destinationMetadata)
end

-- // INITIALIZATION // --

function SessionRoutingService:KnitStart()
	playerDataService = Knit.GetService("PlayerDataService")

	TeleportService.TeleportInitFailed:Connect(function(player, result, message)
		local partyId = pendingTeleports[player]
		if not partyId then
			return
		end
		pendingTeleports[player] = nil
		SessionRoutingService.PartyTeleportFailed:Fire(partyId, { player }, ("%s: %s"):format(result.Name, message))
	end)

	if self:IsReservedRunServer() then
		Players.PlayerAdded:Connect(registerDestinationPlayer)
		for _, player in ipairs(Players:GetPlayers()) do
			registerDestinationPlayer(player)
		end
		task.spawn(assembleDestination)
	end
end

Players.PlayerRemoving:Connect(function(player)
	pendingTeleports[player] = nil
	destinationPlayers[player.UserId] = nil
end)

return SessionRoutingService
