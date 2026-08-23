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
local Signal = require(ReplicatedStorage.Packages.Signal)
local ProfileService = require(ServerScriptService.ServerPackages.ProfileService)
local ProfileTemplate = require(script.Parent.Parent.Data.ProfileTemplate)
local Constants = require(ReplicatedStorage.Shared.Constants)
local RunConfig = require(ReplicatedStorage.Shared.RunConfig)

-- | Objects | --
local PlayerDataService = Knit.CreateService({
	Name = "PlayerDataService",
	Client = {},
})

PlayerDataService.ProfileLoaded = Signal.new()

-- | State Management | --
local profileStore = ProfileService.GetProfileStore(Constants.STORE_NAME, ProfileTemplate)
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
    @summary  Retrieve the live data table for a loaded player profile.
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
function PlayerDataService:UpdateData(player: Player, fn: (data: { [string]: any }) -> ())
	local profile = profiles[player]
	if not profile then
		return
	end
	fn(profile.Data)
end

--[[
    @summary  Apply one completed run to lifetime records exactly once.
    @param    player   Player
    @param    runId    string
    @param    result   table  -- validated final run values
    @returns  boolean, string
]]
function PlayerDataService:ApplyRunRecords(player: Player, runId: string, result: { [string]: any }): (boolean, string)
	if runId == "" or typeof(result) ~= "table" then
		return false, "INVALID_RESULT"
	end

	local profile = profiles[player]
	if not profile then
		return false, "PROFILE_NOT_LOADED"
	end

	local data = profile.Data
	data.Internal = data.Internal or { LastAppliedRunId = "" }
	if data.Internal.LastAppliedRunId == runId then
		return true, "ALREADY_APPLIED"
	end

	data.Records = data.Records or {}
	local records = data.Records
	local displayedDay = math.max(0, math.floor(tonumber(result.displayedDay) or 0))
	local elapsedSeconds = math.max(0, tonumber(result.elapsedSeconds) or 0)

	records.HighestDay = math.max(records.HighestDay or 0, displayedDay)
	if result.victory == true then
		records.Wins = (records.Wins or 0) + 1
		if elapsedSeconds > 0 and ((records.FastestDay67Seconds or 0) <= 0 or elapsedSeconds < records.FastestDay67Seconds) then
			records.FastestDay67Seconds = elapsedSeconds
		end
	end

	local additiveKeys = {
		childrenRescued = "ChildrenRescued",
		treesChopped = "TreesChopped",
		wolvesKilled = "WolvesKilled",
		cultistsKilled = "CultistsKilled",
		revives = "Revives",
		deaths = "Deaths",
	}
	for resultKey, recordKey in pairs(additiveKeys) do
		local amount = math.max(0, math.floor(tonumber(result[resultKey]) or 0))
		records[recordKey] = (records[recordKey] or 0) + amount
	end
	records.TotalPlaytime = (records.TotalPlaytime or 0) + elapsedSeconds

	data.Internal.LastAppliedRunId = runId
	return true, "APPLIED"
end

--[[
    @summary  Bring a legacy profile up to the current schema version.
    @desc     Older saves stored run progress and inflated test health.
              Those tables are discarded so a returning player cannot
              start a fresh run with a finished camp or 300 health.
    @param    data  table  -- the reconciled profile data
]]
local function migrateProfile(data: { [string]: any })
	if (data.DataVersion or 1) >= 2 then
		return
	end

	local legacyStats = data.Stats or {}
	data.Records = data.Records or {}
	data.Records.TreesChopped = (data.Records.TreesChopped or 0) + (legacyStats.TreesChopped or 0)
	data.Records.WolvesKilled = (data.Records.WolvesKilled or 0) + (legacyStats.WolvesKilled or 0)
	data.Records.TotalPlaytime = (data.Records.TotalPlaytime or 0) + (legacyStats.TotalPlaytime or 0)

	local legacySurvival = data.Survival or {}
	data.Records.HighestDay = math.max(data.Records.HighestDay or 0, legacySurvival.HighestNightSurvived or 0)
	data.Records.Deaths = (data.Records.Deaths or 0) + (legacySurvival.DeathCount or 0)

	data.Survival = {
		Health = RunConfig.StartingHealth,
		MaxHealth = RunConfig.StartingHealth,
		Hunger = RunConfig.StartingHunger,
		MaxHunger = RunConfig.StartingHunger,
		DeathCount = 0,
		HighestNightSurvived = 0,
	}

	data.Resources = nil
	data.Base = nil
	data.Rescue = nil
	data.Stats = nil
	data.Campfire = nil
	data.Inventory = nil

	data.DataVersion = 2
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
		migrateProfile(profile.Data)
		profile:Reconcile()
		-- Reset vital stats to max on each join so players don't spawn starving
		profile.Data.Survival.MaxHealth = RunConfig.StartingHealth
		profile.Data.Survival.MaxHunger = RunConfig.StartingHunger
		profile.Data.Survival.Hunger = profile.Data.Survival.MaxHunger
		profile.Data.Survival.Health = profile.Data.Survival.MaxHealth
		profile:ListenToRelease(function()
			profiles[player] = nil
			if player.Parent then
				player:Kick("Profile released by another server.")
			end
		end)

		if player.Parent then
			profiles[player] = profile
			PlayerDataService.ProfileLoaded:Fire(player)
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
