--[[
    @file    LeaderboardService.luau
    @author  manik
    @date    2025

    @summary
    Maintains the lobby's global leaderboards (top survivors + donors).

    @description
    Two OrderedDataStores hold the cross-server rankings:
    `67Nights_LB_HighestDay` (best night count per player, fed by
    PlayerDataService.HighestDayUpdated after each run) and
    `67Nights_LB_Donated` (lifetime Robux tipped at the donation stand,
    fed by DonationService receipts).  On the lobby place a refresh loop
    rewrites the SurfaceGui rows on the two board models so every client
    sees the live top 15 without any client-side work.  OrderedDataStore
    is unavailable in Studio without API access, so every call is pcalled
    and the boards fall back to a "data unavailable" status line.

    @exports
    - LeaderboardService:RecordHighestDay(player, day)   -> void
    - LeaderboardService:RecordDonation(player, amount)  -> void
]]

-- // VARIABLES // --

-- | Services | --
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- | Modules | --
local Knit = require(ReplicatedStorage.Packages.Knit)

-- | Objects | --
local LeaderboardService = Knit.CreateService({
	Name = "LeaderboardService",
	Client = {},
})

local playerDataService

-- | State Management | --
local MAX_ROWS = 10
local REFRESH_SECONDS = 90
local POLL_SECONDS = 10
local daysStore
local donationsStore
local nameCache = {}
local thumbCache = {}
local boards = {}
local refreshDirty = true
local storeWarned = false
local seedsApplied = false

-- Owner seed rows, applied once per lobby server (max-merge, real data
-- in the OrderedDataStores so boards never look empty).
local SEEDS = {
	days = { RealSwertz = 67 },
	donations = { RealSwertz = 10 },
}

-- // FUNCTIONS // --

--[[
    @summary  Lazily grab the ordered stores; nil-safe for Studio.
    @returns  boolean  -- true when both stores resolved
]]
local function storesReady(): boolean
	if daysStore and donationsStore then
		return true
	end
	local ok = pcall(function()
		daysStore = DataStoreService:GetOrderedDataStore("67Nights_LB_HighestDay")
		donationsStore = DataStoreService:GetOrderedDataStore("67Nights_LB_Donated")
	end)
	if not ok then
		daysStore, donationsStore = nil, nil
	end
	return daysStore ~= nil
end

local function warnStoreOnce(context: string, err: any)
	if storeWarned then
		return
	end
	storeWarned = true
	warn(("[LeaderboardService] OrderedDataStore unavailable (%s): %s"):format(context, tostring(err)))
end

--[[
    @summary  Write a player's best day (max) to the days store.
    @param    player  Player
    @param    day     number  -- highest night the player has reached
]]
function LeaderboardService:RecordHighestDay(player: Player, day: number)
	if not storesReady() or day <= 0 then
		return
	end
	local key = tostring(player.UserId)
	local ok, err = pcall(function()
		daysStore:UpdateAsync(key, function(old)
			return math.max(old or 0, math.floor(day))
		end)
	end)
	if ok then
		refreshDirty = true
	else
		warnStoreOnce("RecordHighestDay", err)
	end
end

--[[
    @summary  Increment a player's lifetime donation total.
    @param    player  Player
    @param    amount  number  -- Robux donated this purchase
]]
function LeaderboardService:RecordDonation(player: Player, amount: number)
	if not storesReady() or amount <= 0 then
		return
	end
	local key = tostring(player.UserId)
	local ok, err = pcall(function()
		donationsStore:UpdateAsync(key, function(old)
			return (old or 0) + math.floor(amount)
		end)
	end)
	if ok then
		refreshDirty = true
	else
		warnStoreOnce("RecordDonation", err)
	end
end

--[[
    @summary  Fetch the top entries for a store, or nil on failure.
    @param    store  OrderedDataStore
    @returns  table | nil  -- array of {key=string, value=number}
]]
local function getTop(store): { { key: string, value: number } }?
	local ok, result = pcall(function()
		return store:GetSortedAsync(false, MAX_ROWS):GetCurrentPage()
	end)
	if not ok then
		warnStoreOnce("GetSortedAsync", result)
		return nil
	end
	return result
end

--[[
    @summary  Resolve a display name for a user id, cached forever.
    @param    userId  number
    @returns  string
]]
local function displayName(userId: number): string
	if nameCache[userId] then
		return nameCache[userId]
	end
	local ok, name = pcall(Players.GetNameFromUserIdAsync, Players, userId)
	nameCache[userId] = (ok and name) or ("User " .. userId)
	return nameCache[userId]
end

--[[
    @summary  Resolve a head-shot thumbnail for a user id, cached.
    @param    userId  number
    @returns  string  -- rbxthumb content id, or "" on failure
]]
local function headshot(userId: number): string
	if thumbCache[userId] then
		return thumbCache[userId]
	end
	local ok, thumb = pcall(
		Players.GetUserThumbnailAsync,
		Players,
		userId,
		Enum.ThumbnailType.HeadShot,
		Enum.ThumbnailSize.Size48x48
	)
	thumbCache[userId] = (ok and thumb) or ""
	return thumbCache[userId]
end

--[[
    @summary  Write the owner seed rows into both stores once, max-merged
              so later real activity always wins or accumulates.
]]
local function applySeeds()
	if seedsApplied or not storesReady() then
		return
	end
	seedsApplied = true
	task.spawn(function()
		for username, day in pairs(SEEDS.days) do
			local ok, userId = pcall(Players.GetUserIdFromNameAsync, Players, username)
			if ok and userId then
				pcall(function()
					daysStore:UpdateAsync(tostring(userId), function(old)
						return math.max(old or 0, day)
					end)
				end)
			end
		end
		for username, amount in pairs(SEEDS.donations) do
			local ok, userId = pcall(Players.GetUserIdFromNameAsync, Players, username)
			if ok and userId then
				pcall(function()
					donationsStore:UpdateAsync(tostring(userId), function(old)
						return math.max(old or 0, amount)
					end)
				end)
			end
		end
		refreshDirty = true
	end)
end

local function commas(n: number): string
	local s = tostring(math.floor(n))
	return (s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", ""))
end

--[[
    @summary  Rewrite one board's SurfaceGui rows from fetched entries.
    @param    board    Model   -- lobby board model with Sign.BoardGui
    @param    entries  table   -- getTop() result, or nil on failure
    @param    format   (number)->string  -- value column formatter
]]
local function fillBoard(board: Instance, entries, format)
	local gui = board.Sign:FindFirstChild("BoardGui")
	if not gui then
		return
	end
	local rows = gui:FindFirstChild("Rows")
	local status = gui:FindFirstChild("Status")
	if status then
		status.Visible = entries == nil
		status.Text = "leaderboard data unavailable"
	end
	for i = 1, MAX_ROWS do
		local row = rows and rows:FindFirstChild("Rank" .. i)
		if not row then
			break
		end
		local entry = entries and entries[i]
		if entry then
			local userId = tonumber(entry.key) or 0
			row.Rank.Text = "#" .. i
			row.PlayerName.Text = displayName(userId)
			if row:FindFirstChild("Avatar") then
				row.Avatar.Image = headshot(userId)
			end
			row.Value.Text = format(entry.value)
			row.Visible = true
		else
			row.Visible = false
		end
	end
end

--[[
    @summary  Pull both stores and repaint both lobby boards.
]]
local function refreshBoards()
	if not boards.survivors or not boards.donors then
		return
	end
	if not storesReady() then
		fillBoard(boards.survivors, nil, nil)
		fillBoard(boards.donors, nil, nil)
		return
	end
	applySeeds()
	local days = getTop(daysStore)
	local donations = getTop(donationsStore)
	fillBoard(boards.survivors, days, function(v)
		return tostring(math.floor(v))
	end)
	fillBoard(boards.donors, donations, function(v)
		return "R$ " .. commas(v)
	end)
	refreshDirty = false
end

--[[
    @summary  Locate the two board models under lobby-map.
    @returns  boolean
]]
local function findBoards(): boolean
	local lobbyMap = workspace:FindFirstChild("lobby-map")
	if not lobbyMap then
		return false
	end
	boards.survivors = boards.survivors or lobbyMap:FindFirstChild("SurvivorBoard")
	boards.donors = boards.donors or lobbyMap:FindFirstChild("DonorBoard")
	return boards.survivors ~= nil and boards.donors ~= nil
end

-- // INITIALIZATION // --

--[[
    @summary  Knit lifecycle start — hooks the run-record signal and runs
              the lobby refresh loop (inert on real game servers).
]]
function LeaderboardService:KnitStart()
	playerDataService = Knit.GetService("PlayerDataService")
	playerDataService.HighestDayUpdated:Connect(function(player, day)
		LeaderboardService:RecordHighestDay(player, day)
	end)

	-- The boards only exist where lobby-map does; findBoards() polls until
	-- they appear, so this loop is inert on any place without them.
	task.spawn(function()
		-- Boards may stream in after service start; poll until found.
		while not findBoards() do
			task.wait(POLL_SECONDS)
		end
		refreshBoards()
		local lastRefresh = os.clock()
		while true do
			task.wait(POLL_SECONDS)
			if refreshDirty or os.clock() - lastRefresh >= REFRESH_SECONDS then
				refreshBoards()
				lastRefresh = os.clock()
			end
		end
	end)
end

return LeaderboardService
