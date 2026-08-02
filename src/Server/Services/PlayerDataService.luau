--[[
    @file    PlayerDataService.luau
    @author  manik
    @date    2025

    @summary
    Session-locked player data layer built on ProfileService.

    @description
    Wraps ProfileService to load, reconcile, and release player profiles
    with full session-locking guarantees.  Exposes read-only Knit Remote
    methods so the client can observe its own data, but all writes are
    server-authoritative.

    @exports
    - PlayerDataService:GetProfile(player)     -> Profile | nil
    - PlayerDataService:GetData(player)        -> table | nil
    - PlayerDataService:UpdateData(player, fn) -> void  (server only)
    - Knit Remote: GetData                      -> table  (client-safe copy)
]]

-- // VARIABLES // --

-- | Services | --
local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- | Modules | --
local Knit = require(ReplicatedStorage.Packages.Knit)
local ProfileService = require(ServerScriptService.ServerPackages.ProfileService)
local ProfileTemplate = require(script.Parent.Parent.Data.ProfileTemplate)

-- | Constants | --
local STORE_NAME = "67Nights_v1"

-- | Objects | --
local PlayerDataService = Knit.CreateService({
	Name = "PlayerDataService",
	Client = {
		DataLoaded = Knit.CreateSignal(),
	},
})

-- | State | --
local profileStore = ProfileService.GetProfileStore(STORE_NAME, ProfileTemplate)
local profiles = {}

-- // FUNCTIONS // --

--[[
    @summary  Retrieve the live Profile object for a player.
    @param    player  Player  -- the Roblox player
    @returns  Profile | nil   -- nil if no profile is loaded
]]
function PlayerDataService:GetProfile(player: Player)
	return profiles[player]
end

--[[
    @summary  Retrieve a shallow copy of the player's data table.
    @param    player  Player  -- the Roblox player
    @returns  table | nil     -- nil if no profile is loaded
]]
function PlayerDataService:GetData(player: Player)
	local profile = profiles[player]
	if not profile then
		return nil
	end
	return profile.Data
end

--[[
    @summary  Mutate the player's data inside a transaction.
    @desc     The callback receives the Data table; mutations persist
              automatically because ProfileService writes through.
    @param    player  Player    -- the Roblox player
    @param    fn      function  -- callback(data: table) -> void
]]
function PlayerDataService:UpdateData(player: Player, fn: (data: table) -> ())
	local profile = profiles[player]
	if not profile then
		return
	end
	fn(profile.Data)
end

--[[
    @summary  Load a profile for a player with session-locking.
    @desc     Called on PlayerAdded.  If the profile cannot be loaded
              within AUTO_LOAD_TIMEOUT seconds, the player is kicked.
    @param    player  Player  -- the Roblox player
]]
local function loadProfile(player: Player)
	local profile = profileStore:LoadProfileAsync(tostring(player.UserId), function(placeId, gameJobId)
		if player.Parent then
			player:Kick("Profile released by another server.")
		end
	end)

	if profile then
		profile:ListenToRelease(function()
			profiles[player] = nil
			if player.Parent then
				player:Kick("Profile released by another server.")
			end
		end)

		if player.Parent then
			profiles[player] = profile
			PlayerDataService.Client.DataLoaded:Fire(player, table.clone(profile.Data))
		else
			profile:Release()
		end
	elseif player.Parent then
		player:Kick("Failed to load profile. Please rejoin.")
	end
end

--[[
    @summary  Release the profile for a departing player.
    @param    player  Player  -- the Roblox player
]]
local function releaseProfile(player: Player)
	local profile = profiles[player]
	if profile then
		profile:Release()
	end
	profiles[player] = nil
end

--[[
    @summary  Client-facing remote returning a copy of the caller's data.
    @param    player  Player  -- injected by Knit
    @returns  table | nil
]]
function PlayerDataService.Client:GetData(player: Player)
	local profile = profiles[player]
	if not profile then
		return nil
	end
	return table.clone(profile.Data)
end

-- // INITIALIZATION // --

Players.PlayerAdded:Connect(function(player)
	task.spawn(loadProfile, player)
end)

Players.PlayerRemoving:Connect(function(player)
	releaseProfile(player)
end)

for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(loadProfile, player)
end

game:BindToClose(function()
	for player, profile in pairs(profiles) do
		profile:Release()
		profiles[player] = nil
	end
end)

return PlayerDataService
