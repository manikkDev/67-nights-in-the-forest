--[[
    @file    ServerRole.luau
    @author  manik
    @date    2025

    @summary
    Detects whether the current server is the lobby place or the game place.

    @description
    Professional two-place architecture: the experience has a Lobby place
    (start place) and a Game place (sub-place).  Each party gets a reserved
    server of the Game place.  This module lets every service and controller
    cheaply determine which role the current server plays so game-only logic
    can be skipped on the lobby and vice-versa.

    In Studio, the role is determined by the StudioTest.ForceGameMode flag
    so you can test either place without publishing.  In production, the
    role is determined by PlaceId and the DataModel attribute.
]]

local RunService = game:GetService("RunService")
local RunConfig = require(script.Parent.RunConfig)
local Constants = require(script.Parent.Constants)

local ServerRole = {}

local isServer = RunService:IsServer()

-- One-shot diagnostic log so we can see exactly how role detection resolved.
local detectionLogged = false
local function logDetection(source: string, result: boolean)
	if detectionLogged then
		return
	end
	detectionLogged = true
	-- Only access PrivateServerId/Owner on the server — these properties
	-- warn on the client.
	local psId = "n/a"
	local psOwner = "n/a"
	if isServer then
		psId = game.PrivateServerId ~= "" and "non-empty" or "empty"
		psOwner = tostring(game.PrivateServerOwnerId)
	end
	print(("[ServerRole] %s -> IsGameServer=%s | PlaceId=%d GAME_PLACE_ID=%d LOBBY_PLACE_ID=%d | attr=%s | PrivateServerId=%s OwnerId=%s | IsStudio=%s | IsServer=%s")
		:format(
			source,
			tostring(result),
			game.PlaceId or -1,
			Constants.GAME_PLACE_ID,
			Constants.LOBBY_PLACE_ID,
			tostring(game:GetAttribute("ServerRole")),
			psId,
			psOwner,
			tostring(RunService:IsStudio()),
			tostring(isServer)
		))
end

--[[
    @summary  Returns true when the current server is the lobby place.
    @returns  boolean
]]
function ServerRole.IsLobby(): boolean
	return not ServerRole.IsGameServer()
end

--[[
    @summary  Returns true when the current server is a game-place server
              (either a reserved match server or a Studio simulation of one).
    @returns  boolean
]]
function ServerRole.IsGameServer(): boolean
	-- Rojo-built places can set a DataModel attribute "ServerRole" = "Game"
	-- to mark the game place project file.
	local attr = game:GetAttribute("ServerRole")
	if attr == "Game" then
		logDetection("attr=Game", true)
		return true
	elseif attr == "Lobby" then
		logDetection("attr=Lobby", false)
		return false
	end

	-- PlaceId check: the most reliable detection in production.
	-- In Studio the PlaceId is the lobby place, so skip this check there.
	if not RunService:IsStudio() then
		if game.PlaceId == Constants.GAME_PLACE_ID then
			logDetection("PlaceId==GAME_PLACE_ID", true)
			return true
		end
		if game.PlaceId == Constants.LOBBY_PLACE_ID then
			logDetection("PlaceId==LOBBY_PLACE_ID", false)
			return false
		end
	end

	-- No attribute or PlaceId match — fall back to runtime detection.
	if RunService:IsStudio() then
		-- In Studio, SkipLobby mode means the lobby server also acts as the
		-- game server (since there's no real teleport to a separate place).
		local result = RunConfig.IsTestEnabled("ForceGameMode") or RunConfig.IsTestEnabled("SkipLobby")
		logDetection("Studio flags", result)
		return result
	end
	-- A reserved game server has a non-empty PrivateServerId with no owner.
	-- Public servers (lobby) have an empty PrivateServerId.
	-- This check only runs on the server (client doesn't have these props).
	if isServer then
		local result = game.PrivateServerId ~= "" and game.PrivateServerOwnerId == 0
		logDetection("PrivateServerId fallback", result)
		return result
	end
	-- On the client with no attribute/PlaceId match, assume not game server.
	logDetection("client fallback", false)
	return false
end

return ServerRole
