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
    role is determined by PrivateServerId and PlaceId.
]]

local RunService = game:GetService("RunService")
local RunConfig = require(script.Parent.RunConfig)

local ServerRole = {}

--[[
    @summary  Returns true when the current server is the lobby place.
    @returns  boolean
]]
function ServerRole.IsLobby(): boolean
	-- In Studio with SkipLobby, the server acts as both lobby AND game.
	if RunService:IsStudio() and RunConfig.IsTestEnabled("SkipLobby") then
		return true
	end
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
		return true
	elseif attr == "Lobby" then
		return false
	end
	-- No attribute set — fall back to runtime detection.
	if RunService:IsStudio() then
		-- In Studio, SkipLobby mode means the lobby server also acts as the
		-- game server (since there's no real teleport to a separate place).
		return RunConfig.IsTestEnabled("ForceGameMode") or RunConfig.IsTestEnabled("SkipLobby")
	end
	-- A reserved game server has a non-empty PrivateServerId with no owner.
	-- Public servers (lobby) have an empty PrivateServerId.
	return game.PrivateServerId ~= "" and game.PrivateServerOwnerId == 0
end

return ServerRole
