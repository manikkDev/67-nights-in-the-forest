--[[
    @file    CultistRaidService.luau
    @author  manik
    @date    2025

    @summary
    Recurring timed Cultist raids on the campfire, with a warning,
    a fuel-decay penalty for unresolved raids, and a clear-out reward.

    @description
    Every RAID_INTERVAL_DAYS nights a wave of Cultist/Cultist2 spawns
    around the camp perimeter and marches on the campfire, reusing
    AnimalAIService's generic chase/attack state machine so raiders
    behave exactly like any other hostile NPC.  A warning fires at the
    start of the preceding day.  If any raider survives to dawn, the
    campfire's fuel drains faster in proportion to the number left.

    @exports
    - Knit Signal: RaidWarning(dayNumber, phase)  -- phase: "dayBefore" | "preNight"
    - Knit Signal: RaidStarted(dayNumber, cultistCount)
    - Knit Signal: RaidCleared(dayNumber)
    - Knit Signal: RaidFailed(dayNumber, survivors)
    - Knit Signal: RaidStatusUpdate(remaining, total, healthRatio)
]]

-- // VARIABLES // --

-- | Services | --
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- | Modules | --
local Knit = require(ReplicatedStorage.Packages.Knit)

-- | Objects | --
local CultistRaidService = Knit.CreateService({
	Name = "CultistRaidService",
	Client = {
		RaidWarning = Knit.CreateSignal(),
		RaidStarted = Knit.CreateSignal(),
		RaidCleared = Knit.CreateSignal(),
		RaidFailed = Knit.CreateSignal(),
		RaidStatusUpdate = Knit.CreateSignal(),
	},
})

-- | Configuration | --
local RAID_INTERVAL_DAYS = 1 -- TEMP: raid every night for testing, revert to 4 when done
local BASE_RAID_SIZE = 3
local RAID_SIZE_GROWTH_PER_INTERVAL = 1
local MAX_RAID_SIZE = 8
local SPAWN_RADIUS = 55
local RAID_PENALTY_PER_SURVIVOR = 0.6
local RAID_CLEANUP_DELAY = 30
local CULTIST_MODEL_KEYS = { "Cultist", "Cultist2" }

-- | State Management | --
local timeService: any = nil
local worldService: any = nil
local animalAIService: any = nil
local campfireService: any = nil
local deerService: any = nil
local lastPhase: string = "Day"
local raidActive = false
local raidCultists: { Model } = {}
local raidDayNumber = 0
local cleanupScheduled = false
local raidTotalCount = 0
local raidTotalMaxHealth = 0
local lastStatusUpdate = 0
local preNightWarningFired = false

-- // FUNCTIONS // --

--[[
    @summary  Fire a Knit signal to every currently-connected player.
    @param    signal  KnitSignal
]]
local function broadcastToAll(signal, ...)
	for _, player in ipairs(Players:GetPlayers()) do
		signal:Fire(player, ...)
	end
end

--[[
    @summary  Return true if a raid should occur on the given day number.
    @param    dayNumber  number
    @returns  boolean
]]
local function isRaidDay(dayNumber: number): boolean
	return dayNumber > 0 and dayNumber % RAID_INTERVAL_DAYS == 0
end

--[[
    @summary  Compute how many cultists spawn for a given day number.
    @param    dayNumber  number
    @returns  number
]]
local function computeRaidSize(dayNumber: number): number
	local intervals = math.floor(dayNumber / RAID_INTERVAL_DAYS)
	return math.clamp(BASE_RAID_SIZE + (intervals - 1) * RAID_SIZE_GROWTH_PER_INTERVAL, BASE_RAID_SIZE, MAX_RAID_SIZE)
end

--[[
    @summary  Spawn a wave of cultists in a ring around the campfire.
    @param    count  number
]]
local function spawnRaidWave(count: number)
	if not worldService or not animalAIService then
		return
	end
	local campfireCFrame = worldService:GetCampfireCFrame()
	if not campfireCFrame then
		return
	end

	raidCultists = {}
	for i = 1, count do
		local angle = (i / count) * math.pi * 2
		local position = campfireCFrame.Position + Vector3.new(math.cos(angle) * SPAWN_RADIUS, 0, math.sin(angle) * SPAWN_RADIUS)
		local origin = position + Vector3.new(0, 200, 0)
		local result = workspace:Raycast(origin, Vector3.new(0, -400, 0))
		local groundedPosition = if result then result.Position + Vector3.new(0, 3, 0) else position + Vector3.new(0, 5, 0)

		local speciesKey = CULTIST_MODEL_KEYS[((i - 1) % #CULTIST_MODEL_KEYS) + 1]
		local model = animalAIService:SpawnNpc(speciesKey, CFrame.new(groundedPosition), { isRaidCultist = true })
		if model then
			table.insert(raidCultists, model)
		end
	end
end

--[[
    @summary  Count how many of this raid's cultists are still alive.
    @returns  number
]]
local function countSurvivors(): number
	local count = 0
	for _, model in ipairs(raidCultists) do
		if not model.Parent then
			continue
		end
		local humanoid = model:FindFirstChildOfClass("Humanoid")
		if humanoid and humanoid.Health > 0 then
			count += 1
		end
	end
	return count
end

--[[
    @summary  Compute the total remaining health of all living raid cultists.
    @returns  number, number  (current health, max health)
]]
local function computeTotalHealth(): (number, number)
	local current = 0
	local maximum = 0
	for _, model in ipairs(raidCultists) do
		if not model.Parent then
			continue
		end
		local humanoid = model:FindFirstChildOfClass("Humanoid")
		if humanoid and humanoid.Health > 0 then
			current += humanoid.Health
			maximum += humanoid.MaxHealth
		end
	end
	return current, maximum
end

--[[
    @summary  Begin a raid: fire the started signal (triggers cutscene on
              clients), then spawn the wave after the cutscene fades.
    @param    dayNumber  number
]]
local function startRaid(dayNumber: number)
	raidDayNumber = dayNumber
	cleanupScheduled = false
	preNightWarningFired = false
	local count = computeRaidSize(dayNumber)

	-- Suppress the Deer stalker during cultist raids so only cultists
	-- are present as hostile NPCs.
	if deerService then
		deerService:SuppressDeer(true)
	end

	-- Fire RaidStarted immediately so clients play the cinematic cutscene.
	-- Cultists spawn after the cutscene finishes (~5 seconds).
	broadcastToAll(CultistRaidService.Client.RaidStarted, dayNumber, count)

	task.delay(5, function()
		if not timeService or not timeService:IsRunning() then
			return
		end
		-- Abort if the run ended during the delay.
		if timeService:GetCurrentPhase() ~= "Night" then
			return
		end
		raidActive = true
		spawnRaidWave(count)
		raidTotalCount = #raidCultists
		local _, maxHp = computeTotalHealth()
		raidTotalMaxHealth = maxHp
	end)
end

--[[
    @summary  Destroy any cultists still alive once the cleanup grace
              period after dawn has elapsed.
]]
local function cleanupRemainingRaiders()
	local survivors = countSurvivors()
	for _, model in ipairs(raidCultists) do
		if model.Parent then
			model:Destroy()
		end
	end
	raidCultists = {}
	raidActive = false
	-- Re-enable the Deer stalker now that the raid is over.
	if deerService then
		deerService:SuppressDeer(false)
	end
	-- If cultists survived to dawn, fire the failed signal.
	if survivors > 0 then
		broadcastToAll(CultistRaidService.Client.RaidFailed, raidDayNumber, survivors)
	end
end

--[[
    @summary  Heartbeat-driven raid lifecycle: detect day/night
              transitions, apply the dawn fuel penalty, and clear the
              raid once every cultist is dead.
    @param    dt  number
]]
local function onHeartbeat(dt: number)
	if not timeService or not timeService:IsRunning() then
		return
	end

	local phase = timeService:GetCurrentPhase()
	local dayNumber = timeService:GetDayNumber()

	if phase ~= lastPhase then
		lastPhase = phase
		if phase == "Day" and isRaidDay(dayNumber) then
			preNightWarningFired = false
			broadcastToAll(CultistRaidService.Client.RaidWarning, dayNumber, "dayBefore")
		elseif phase == "Night" and isRaidDay(dayNumber) and not raidActive then
			startRaid(dayNumber)
		elseif phase == "Day" and raidActive then
			if not cleanupScheduled then
				cleanupScheduled = true
				task.delay(RAID_CLEANUP_DELAY, function()
					if raidActive then
						cleanupRemainingRaiders()
					end
				end)
			end
		end
	end

	-- Fire pre-night warning a few seconds before night starts.
	if phase == "Day" and isRaidDay(dayNumber) and not preNightWarningFired then
		local dayDuration = timeService:GetPhaseDuration()
		local elapsed = timeService:GetPhaseElapsed()
		if elapsed >= (dayDuration - 5) then
			preNightWarningFired = true
			broadcastToAll(CultistRaidService.Client.RaidWarning, dayNumber, "preNight")
		end
	end

	if not raidActive then
		return
	end

	local survivors = countSurvivors()
	if survivors == 0 then
		raidActive = false
		-- Re-enable the Deer stalker now that the raid is cleared.
		if deerService then
			deerService:SuppressDeer(false)
		end
		broadcastToAll(CultistRaidService.Client.RaidCleared, raidDayNumber)
		return
	end

	-- Periodically broadcast raid status for the tracker HUD.
	local now = os.clock()
	if now - lastStatusUpdate >= 0.5 then
		lastStatusUpdate = now
		local currentHp, maxHp = computeTotalHealth()
		local ratio = if raidTotalMaxHealth > 0 then currentHp / raidTotalMaxHealth else 0
		broadcastToAll(CultistRaidService.Client.RaidStatusUpdate, survivors, raidTotalCount, ratio)
	end

	if phase == "Day" and campfireService then
		campfireService:ApplyExternalDrain(RAID_PENALTY_PER_SURVIVOR * survivors * dt)
	end
end

-- // INITIALIZATION // --

function CultistRaidService:KnitStart()
	timeService = Knit.GetService("TimeService")
	worldService = Knit.GetService("WorldService")
	animalAIService = Knit.GetService("AnimalAIService")
	campfireService = Knit.GetService("CampfireService")
	deerService = Knit.GetService("DeerService")

	RunService.Heartbeat:Connect(onHeartbeat)

end

return CultistRaidService
