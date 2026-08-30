--[[
    @file    RunStateService.luau
    @author  manik
    @date    2025

    @summary
    Authoritative owner of one forest run: lifecycle phase, run token,
    membership, day multiplier, run statistics, and per-run cleanup.

    @description
    Every Phase 4 system asks this service whether a run is active and
    whether a captured token is still current before mutating state.
    Run-scoped profile tables are cleared when a run starts and again
    when it ends, so a finished camp never carries into the next run.

    @exports
    - RunStateService:GetRunId()                 -> string
    - RunStateService:GetPhase()                 -> RunPhase
    - RunStateService:IsActive()                 -> boolean
    - RunStateService:IsCurrentRun(runId)        -> boolean
    - RunStateService:IsMember(player)           -> boolean
    - RunStateService:StartRun(players)          -> string?
    - RunStateService:EndRun(reason, payload)
    - RunStateService:GetRuntimeFolder()         -> Folder
    - RunStateService:AddMultiplierSource(key, amount)
    - RunStateService:GetMultiplier()            -> number
    - RunStateService:IncrementStat(player, key, amount)
    - Knit Signal: RunPhaseChanged(phase, payload)
]]

-- // VARIABLES // --

-- | Services | --
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")

-- | Modules | --
local Knit = require(ReplicatedStorage.Packages.Knit)
local ServerRole = require(ReplicatedStorage.Shared.ServerRole)
local Signal = require(ReplicatedStorage.Packages.Signal)
local RunConfig = require(ReplicatedStorage.Shared.RunConfig)
local WorldPlacement = require(script.Parent.Parent.WorldPlacement)

-- | Objects | --
local RunStateService = Knit.CreateService({
	Name = "RunStateService",
	Client = {
		RunPhaseChanged = Knit.CreateSignal(),
		MultiplierChanged = Knit.CreateSignal(),
		RunEnded = Knit.CreateSignal(),
	},
})

export type RunPhase = "Lobby" | "Starting" | "Active" | "Ending" | "Ended"

RunStateService.PhaseChanged = Signal.new()
RunStateService.RunStarted = Signal.new()
RunStateService.RunEnding = Signal.new()
RunStateService.RunCleaned = Signal.new()

-- | Configuration | --
local RUNTIME_FOLDER_NAME = "Runtime"
local RUN_SCOPED_PROFILE_KEYS = { "Resources", "Inventory", "Base", "Rescue", "Stats", "Campfire" }

-- | State Management | --
local playerDataService: any = nil
local timeService: any = nil
local spawnService: any = nil
local campfireService: any = nil
local animalAIService: any = nil

local runId = ""
local phase: RunPhase = "Lobby"
local runStartedAt = 0
local partyId = ""
local hostUserId = 0
local initialPartySize = 0
local members: { [Player]: boolean } = {}
local memberRecords: { [number]: { userId: number, name: string, username: string } } = {}
local multiplierSources: { [string]: number } = {}
local runtimeFolder: Folder? = nil
local cleanupCallbacks: { () -> () } = {}

-- // FUNCTIONS // --

-- | Private | --

--[[
    @summary  Return a fresh copy of a run-scoped profile table.
    @param    key  string  -- top-level profile table name
    @returns  table
]]
local function freshRunTable(key: string): { [string]: any }
	if key == "Resources" then
		return {
			Wood = 0,
			Coal = 0,
			Berries = 0,
			Mushrooms = 0,
			RawMeat = 0,
			CookedMeat = 0,
			OwlFeather = 0,
			CultistGem = 0,
			Bandage = 0,
			Bolt = 0,
			OldRadio = 0,
			SheetMetal = 0,
			Tyre = 0,
			BrokenFan = 0,
			BrokenMicrowave = 0,
			MetalChair = 0,
		}
	elseif key == "Base" then
		return { BedCount = 0, DayMultiplier = 1, UnlockedStructures = {} }
	elseif key == "Rescue" then
		return { ChildrenRescued = {}, CavesUnlocked = {} }
	elseif key == "Stats" then
		return {
			TreesChopped = 0,
			WolvesKilled = 0,
			CultistsKilled = 0,
			StructuresBuilt = 0,
			ChildrenRescued = 0,
			Revives = 0,
			Downs = 0,
			TotalPlaytime = 0,
		}
	elseif key == "Campfire" then
		return { Level = 1, Progress = 0, Fuel = 0 }
	end
	return { HasBag = true, PickupOrder = {} }
end

--[[
    @summary  Reset every run-scoped table on one player's profile.
    @param    player  Player
]]
local function resetPlayerRunData(player: Player)
	if not playerDataService then
		return
	end
	playerDataService:UpdateData(player, function(data)
		for _, key in ipairs(RUN_SCOPED_PROFILE_KEYS) do
			data[key] = freshRunTable(key)
		end
		data.Survival = data.Survival or {}
		data.Survival.Health = RunConfig.StartingHealth
		data.Survival.MaxHealth = RunConfig.StartingHealth
		data.Survival.Hunger = RunConfig.StartingHunger
		data.Survival.MaxHunger = RunConfig.StartingHunger
	end)
end

--[[
    @summary  Create or reuse the folder that holds all run instances.
    @returns  Folder
]]
local function ensureRuntimeFolder(): Folder
	if runtimeFolder and runtimeFolder.Parent then
		return runtimeFolder
	end
	local existing = workspace:FindFirstChild(RUNTIME_FOLDER_NAME)
	if existing and existing:IsA("Folder") then
		runtimeFolder = existing
		return existing
	end
	local folder = Instance.new("Folder")
	folder.Name = RUNTIME_FOLDER_NAME
	folder.Parent = workspace
	runtimeFolder = folder
	return folder
end

--[[
    @summary  Clear every child from the runtime folder.
    @desc     Called before a new run starts so there are no duplicates.
]]
local function clearRuntimeFolder()
	local folder = ensureRuntimeFolder()
	for _, child in ipairs(folder:GetChildren()) do
		child:Destroy()
	end
end

--[[
    @summary  Broadcast the current lifecycle phase to every member.
    @param    payload  table?  -- optional extra state for clients
]]
local function buildMemberSnapshot(): { { userId: number, name: string, username: string } }
	local result = {}
	for _, record in pairs(memberRecords) do
		table.insert(result, table.clone(record))
	end
	table.sort(result, function(a, b)
		return a.userId < b.userId
	end)
	return result
end

local function broadcastPhase(payload: { [string]: any }?)
	local data = table.clone(payload or {})
	data.phase = phase
	data.runId = runId
	data.partyId = partyId
	data.hostUserId = hostUserId
	data.initialPartySize = initialPartySize
	data.members = buildMemberSnapshot()
	for player in pairs(members) do
		if player.Parent == Players then
			RunStateService.Client.RunPhaseChanged:Fire(player, data)
		end
	end
	RunStateService.PhaseChanged:Fire(phase, data)
end

-- | Public | --

--[[
    @summary  Return the identifier of the current run.
    @returns  string
]]
function RunStateService:GetRunId(): string
	return runId
end

function RunStateService:GetPartyId(): string
	return partyId
end

function RunStateService:GetHostUserId(): number
	return hostUserId
end

function RunStateService:GetInitialPartySize(): number
	return initialPartySize
end

--[[
    @summary  Return the current lifecycle phase.
    @returns  RunPhase
]]
function RunStateService:GetPhase(): RunPhase
	return phase
end

--[[
    @summary  Return whether gameplay actions are currently permitted.
    @returns  boolean
]]
function RunStateService:IsActive(): boolean
	return phase == "Active"
end

--[[
    @summary  Return whether a captured token still matches the live run.
    @param    token  string?
    @returns  boolean
]]
function RunStateService:IsCurrentRun(token: string?): boolean
	return token ~= nil and token == runId and runId ~= ""
end

--[[
    @summary  Return whether a player belongs to the current run.
    @param    player  Player
    @returns  boolean
]]
function RunStateService:IsMember(player: Player): boolean
	return members[player] == true
end

--[[
    @summary  Return every player still participating in the run.
    @returns  { Player }
]]
function RunStateService:GetMembers(): { Player }
	local list = {}
	for player in pairs(members) do
		if player.Parent then
			table.insert(list, player)
		end
	end
	return list
end

--[[
    @summary  Return the folder that owns all run-created instances.
    @returns  Folder
]]
function RunStateService:GetRuntimeFolder(): Folder
	return ensureRuntimeFolder()
end

--[[
    @summary  Register work that must run when the current run is cleaned.
    @param    callback  function
]]
function RunStateService:AddCleanupTask(callback: () -> ())
	table.insert(cleanupCallbacks, callback)
end

--[[
    @summary  Return the number of seconds the run has been going.
    @returns  number
]]
function RunStateService:GetElapsedSeconds(): number
	if runStartedAt <= 0 then
		return 0
	end
	return os.clock() - runStartedAt
end

--[[
    @summary  Set how many multiplier points one named source contributes.
    @param    key     string  -- unique source identifier
    @param    amount  number  -- points contributed by that source
]]
function RunStateService:AddMultiplierSource(key: string, amount: number)
	if typeof(key) ~= "string" or typeof(amount) ~= "number" then
		return
	end
	multiplierSources[key] = math.max(0, math.floor(amount))

	local multiplier = self:GetMultiplier()
	for player in pairs(members) do
		if player.Parent == Players then
			RunStateService.Client.MultiplierChanged:Fire(player, {
				multiplier = multiplier,
				sources = table.clone(multiplierSources),
			})
		end
	end
end

--[[
    @summary  Return the active day multiplier from all live sources.
    @returns  number
]]
function RunStateService:GetMultiplier(): number
	local total = RunConfig.BaseMultiplier
	for _, amount in pairs(multiplierSources) do
		total += amount
	end
	return math.clamp(total, RunConfig.BaseMultiplier, RunConfig.MaxMultiplier)
end

--[[
    @summary  Return a copy of the current multiplier contributions.
    @returns  table
]]
function RunStateService:GetMultiplierSources(): { [string]: number }
	return table.clone(multiplierSources)
end

--[[
    @summary  Increase one run statistic for a player.
    @param    player  Player
    @param    key     string
    @param    amount  number?
]]
function RunStateService:IncrementStat(player: Player, key: string, amount: number?)
	if not playerDataService or not player.Parent then
		return
	end
	local delta = amount or 1
	playerDataService:UpdateData(player, function(data)
		data.Stats = data.Stats or freshRunTable("Stats")
		data.Stats[key] = (data.Stats[key] or 0) + delta
	end)
end

--[[
    @summary  Add a player to the live run without restarting it.
    @param    player  Player
]]
function RunStateService:AddMember(player: Player): boolean
	if phase == "Lobby" or phase == "Ended" or not player or player.Parent ~= Players then
		return false
	end
	if not memberRecords[player.UserId] then
		return false
	end
	members[player] = true
	return true
end

--[[
    @summary  Remove a player from the live run without ending it for others.
    @desc    Used by EndingService when a player individually returns to the
             lobby. The member record is preserved so the run still knows who
             was originally part of the party, but the player no longer
             receives run-scoped broadcasts or counts as a participant.
    @param   player  Player
]]
function RunStateService:RemoveMember(player: Player)
	members[player] = nil
end

--[[
    @summary  Begin a new run for the given players.
    @param    participants  { Player }
    @returns  string?  -- the new run identifier, or nil when refused
]]
function RunStateService:StartRun(participants: { Player }, metadata: { [string]: any }?): string?
	if phase == "Active" or phase == "Starting" or phase == "Ending" then
		warn("[RunStateService] StartRun rejected — phase is", phase)
		return nil
	end
	if #participants == 0 then
		warn("[RunStateService] StartRun rejected — 0 participants")
		return nil
	end
	if #participants > 5 then
		warn("[RunStateService] StartRun rejected — too many participants:", #participants)
		return nil
	end
	if not playerDataService then
		warn("[RunStateService] StartRun rejected — playerDataService is nil")
		return nil
	end
	local seenUserIds = {}
	for _, player in ipairs(participants) do
		if not player.Parent then
			warn("[RunStateService] StartRun rejected — player has no Parent:", player.Name)
			return nil
		end
		if not playerDataService:GetData(player) then
			warn("[RunStateService] StartRun rejected — no profile data for:", player.Name)
			return nil
		end
		if seenUserIds[player.UserId] then
			warn("[RunStateService] StartRun rejected — duplicate userId:", player.UserId)
			return nil
		end
		seenUserIds[player.UserId] = true
	end

	local requestedPartyId = metadata and metadata.partyId
	local requestedHostId = metadata and metadata.hostUserId
	local requestedInitialSize = metadata and metadata.initialPartySize
	if requestedPartyId ~= nil and (typeof(requestedPartyId) ~= "string" or #requestedPartyId < 8) then
		warn("[RunStateService] StartRun rejected — invalid partyId in metadata")
		return nil
	end
	if requestedHostId ~= nil and typeof(requestedHostId) ~= "number" then
		warn("[RunStateService] StartRun rejected — invalid hostUserId in metadata")
		return nil
	end
	if requestedInitialSize ~= nil and (typeof(requestedInitialSize) ~= "number" or requestedInitialSize < #participants or requestedInitialSize > 5) then
		warn("[RunStateService] StartRun rejected — invalid initialPartySize:", requestedInitialSize, "participants:", #participants)
		return nil
	end

	runId = HttpService:GenerateGUID(false)
	partyId = requestedPartyId or runId
	hostUserId = if requestedHostId and seenUserIds[requestedHostId] then requestedHostId else participants[1].UserId
	initialPartySize = requestedInitialSize or #participants
	WorldPlacement.Reset()
	phase = "Starting"
	runStartedAt = os.clock()
	members = {}
	memberRecords = {}
	multiplierSources = {}
	cleanupCallbacks = {}

	for _, player in ipairs(participants) do
		if player.Parent then
			members[player] = true
			memberRecords[player.UserId] = {
				userId = player.UserId,
				name = player.DisplayName,
				username = player.Name,
			}
			resetPlayerRunData(player)
		end
	end

	ensureRuntimeFolder()
	clearRuntimeFolder()
	if campfireService then
		campfireService:ResetForRun()
	end
	if animalAIService then
		animalAIService:ResetForRun()
	end
	broadcastPhase({ startedAt = runStartedAt })
	RunStateService.RunStarted:Fire(runId)

	phase = "Active"
	broadcastPhase({ startedAt = runStartedAt })

	print("[RunStateService] StartRun succeeded — runId:", runId, "partyId:", partyId, "members:", #participants)
	return runId
end

--[[
    @summary  Move the run into its ending sequence exactly once.
    @param    reason   string
    @param    payload  table?
    @returns  boolean  -- true when this call performed the transition
]]
function RunStateService:BeginEnding(reason: string, payload: { [string]: any }?): boolean
	if phase ~= "Active" then
		return false
	end

	phase = "Ending"

	local data = payload or {}
	data.reason = reason
	data.elapsedSeconds = self:GetElapsedSeconds()
	data.multiplier = self:GetMultiplier()

	broadcastPhase(data)
	RunStateService.RunEnding:Fire(reason, data)

	return true
end

--[[
    @summary  Destroy run-owned state and return the server to the lobby.
    @param    reason  string
]]
function RunStateService:CleanupRun(reason: string)
	if phase == "Lobby" then
		return
	end

	phase = "Ended"

	for _, callback in ipairs(cleanupCallbacks) do
		local ok, err = pcall(callback)
		if not ok then
			warn("[RunStateService] Cleanup task failed:", err)
		end
	end
	cleanupCallbacks = {}

	if RunService:IsStudio() then
		-- Keep the Runtime folder visible in Studio edit mode so the
		-- developer can inspect and reposition run-created objects. The
		-- folder is cleared on the next StartRun.
		if runtimeFolder then
			runtimeFolder = nil
		end
	else
		if runtimeFolder then
			runtimeFolder:Destroy()
			runtimeFolder = nil
		end
	end

	if timeService then
		timeService:ResetMatch()
	end

	local currentMembers = {}
	for player in pairs(members) do
		table.insert(currentMembers, player)
	end
	for _, player in ipairs(currentMembers) do
		if player.Parent then
			resetPlayerRunData(player)
			if spawnService then
				spawnService:ResetPlayer(player)
			end
		end
	end

	phase = "Lobby"
	broadcastPhase({ reason = reason })

	members = {}
	memberRecords = {}
	multiplierSources = {}
	runStartedAt = 0
	runId = ""
	partyId = ""
	hostUserId = 0
	initialPartySize = 0
	RunStateService.RunCleaned:Fire(reason)
end

--[[
    @summary  Client-facing snapshot of the run for HUD binding.
    @param    player  Player  -- injected by Knit
    @returns  table
]]
function RunStateService.Client:GetSnapshot(player: Player): { [string]: any }
	if members[player] ~= true then
		return {
			phase = "Lobby",
			isMember = false,
			goalDay = RunConfig.GoalDay,
		}
	end
	return {
		runId = runId,
		partyId = partyId,
		hostUserId = hostUserId,
		initialPartySize = initialPartySize,
		members = buildMemberSnapshot(),
		phase = phase,
		isMember = true,
		multiplier = RunStateService:GetMultiplier(),
		sources = table.clone(multiplierSources),
		goalDay = RunConfig.GoalDay,
		elapsedSeconds = RunStateService:GetElapsedSeconds(),
	}
end

-- // INITIALIZATION // --

function RunStateService:KnitStart()
	-- playerDataService is needed on both lobby and game for StartRun validation.
	playerDataService = Knit.GetService("PlayerDataService")

	-- Game-only wiring: time service, spawn, campfire, AI, etc.
	if not ServerRole.IsGameServer() then return end
	timeService = Knit.GetService("TimeService")
	spawnService = Knit.GetService("SpawnService")
	campfireService = Knit.GetService("CampfireService")
	animalAIService = Knit.GetService("AnimalAIService")

	if timeService then
		timeService:SetMultiplierProvider(function()
			return RunStateService:GetMultiplier()
		end)
	end

	Players.PlayerRemoving:Connect(function(player)
		members[player] = nil
	end)
end

return RunStateService
