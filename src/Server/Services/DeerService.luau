--[[
    @file    DeerService.luau
    @author  manik
    @date    2025

    @summary
    Server-authoritative unkillable stalker AI for the Deer and Ram
    Monster, including the flashlight-stun mechanic.

    @description
    Both entities share one behavioral family per the reference game:
    dormant by day, hunt the nearest player outside the campfire's
    safe zone at night in a straight line, speed up the longer they
    pursue one target, retreat when that target reaches the safe zone,
    and deal heavy contact damage instead of dying to weapons.  A
    flashlight beam interrupts an active chase with a stun whose
    duration shrinks on each consecutive use against the same
    instance, recovering over time between uses.

    @exports
    - DeerService:ApplyFlashlightStun(model, player) -> boolean  (server only)
]]

-- // VARIABLES // --

-- | Services | --
local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")

-- | Modules | --
local Knit = require(ReplicatedStorage.Packages.Knit)
local NpcConfig = require(ReplicatedStorage.Shared.NpcConfig)
local CombatTargetRegistry = require(script.Parent.Parent.CombatTargetRegistry)

-- | Objects | --
local DeerService = Knit.CreateService({
	Name = "DeerService",
	Client = {
		StalkerStunned = Knit.CreateSignal(),
		StalkerContact = Knit.CreateSignal(),
	},
})

-- | Configuration | --
local NPC_SOURCE_PATH = ServerStorage.Assets["Assets Npcs"]
local DORMANT_HOLDING_POSITION = Vector3.new(0, -500, 0)
local DECISION_INTERVAL = 0.2
local CONTACT_RANGE = 5
local CONTACT_COOLDOWN = 1.2
local PURSUIT_ACCEL_PER_SEC = 0.35
local PURSUIT_MAX_BONUS_SPEED = 14
local BASE_STUN_DURATION = 4
local STUN_DECAY_PER_USE = 0.6
local MIN_STUN_DURATION = 1
local STUN_RESISTANCE_RECOVERY_TIME = 45
local RETREAT_HOLD_TIME = 3

local STALKER_DEFS = {
	Deer = {
		ModelName = "Deer",
		BaseSpeed = 14,
		AttackDamage = 55,
		UsesFlashlightStun = true,
	},
	RamMonster = {
		ModelName = "Ram Monster",
		BaseSpeed = NpcConfig.RamMonster.WalkSpeed,
		AttackDamage = NpcConfig.RamMonster.AttackDamage,
		UsesFlashlightStun = true,
	},
}

-- | State Management | --
local worldService: any = nil
local timeService: any = nil
local campfireService: any = nil
local spawnService: any = nil
local stalkers: { [string]: any } = {}

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

local DEFAULT_R15_WALK_ID = "rbxassetid://913402848"
local DEFAULT_R15_IDLE_ID = "rbxassetid://507766388"
local DEFAULT_R15_RUN_ID = "rbxassetid://913402848"

--[[
    @summary  Load a stalker's baked Animations folder into AnimationTracks,
              falling back to the default R15 walk/idle/run set for a
              stalker with no baked Animations folder (Ram Monster shares
              the Deer's stalker logic but ships no baked animations).
    @param    stalker  table
]]
local function buildAnimationTracks(stalker)
	stalker.tracks = {}
	local humanoid = stalker.humanoid
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end

	local function loadTrack(id: string, looped: boolean): AnimationTrack?
		local anim = Instance.new("Animation")
		anim.AnimationId = id
		local ok, track = pcall(function()
			return animator:LoadAnimation(anim)
		end)
		if not ok or not track then
			return nil
		end
		track.Looped = looped
		return track
	end

	local animFolder = stalker.model:FindFirstChild("Animations")
	if animFolder then
		for _, animInstance in ipairs(animFolder:GetChildren()) do
			if animInstance:IsA("Animation") then
				local ok, track = pcall(function()
					return animator:LoadAnimation(animInstance)
				end)
				if ok and track then
					track.Looped = animInstance.Name ~= "Jumpscare"
						and animInstance.Name ~= "StunnedStart"
						and animInstance.Name ~= "StunnedEnd"
					stalker.tracks[animInstance.Name] = track
				end
			end
		end
	end

	if not stalker.tracks.Walk then
		stalker.tracks.Walk = loadTrack(DEFAULT_R15_WALK_ID, true)
	end
	if not stalker.tracks.Run then
		stalker.tracks.Run = loadTrack(DEFAULT_R15_RUN_ID, true)
	end
	if not stalker.tracks.Idle then
		stalker.tracks.Idle = loadTrack(DEFAULT_R15_IDLE_ID, true)
	end
end

--[[
    @summary  Stop every currently-playing track on a stalker.
    @param    stalker  table
]]
local function stopAllTracks(stalker)
	for _, track in pairs(stalker.tracks) do
		if track.IsPlaying then
			track:Stop(0.15)
		end
	end
end

--[[
    @summary  Play a named track if it exists, without interrupting
              itself if already playing.
    @param    stalker  table
    @param    name     string
]]
local function playTrack(stalker, name: string)
	local track = stalker.tracks[name]
	if track and not track.IsPlaying then
		stopAllTracks(stalker)
		track:Play(0.15)
	end
end

--[[
    @summary  Move a stalker to the hidden holding position and disable
              collision/visibility while dormant.
    @param    stalker  table
]]
local function enterDormant(stalker)
	stalker.state = "Dormant"
	stalker.target = nil
	stalker.pursuitStartTime = nil
	stalker.model:PivotTo(CFrame.new(DORMANT_HOLDING_POSITION))
	stalker.humanoid.WalkSpeed = 0
	stopAllTracks(stalker)
end

--[[
    @summary  Spawn a stalker's model into the world at a hidden holding
              position, ready to be activated at night.
    @param    key  string  -- key into STALKER_DEFS
]]
local function spawnStalker(key: string)
	local def = STALKER_DEFS[key]
	local template = NPC_SOURCE_PATH:FindFirstChild(def.ModelName)
	if not template or not template:IsA("Model") then
		warn("[DeerService] Missing template for", key)
		return
	end

	local model = template:Clone()
	model.Parent = workspace
	model:PivotTo(CFrame.new(DORMANT_HOLDING_POSITION))

	local humanoid = model:FindFirstChildOfClass("Humanoid") or model:FindFirstChild("NPC")
	local rootPart = model:FindFirstChild("HumanoidRootPart") or model:FindFirstChild("HRP")
	if not humanoid or not rootPart then
		warn("[DeerService] Template", def.ModelName, "missing Humanoid/root part")
		model:Destroy()
		return
	end

	local stalker = {
		key = key,
		def = def,
		model = model,
		humanoid = humanoid,
		rootPart = rootPart,
		state = "Dormant",
		target = nil,
		lastContactTime = 0,
		consecutiveStuns = 0,
		lastStunTime = 0,
		stunUntil = 0,
		retreatUntil = 0,
		nextDecisionTime = 0,
		pursuitStartTime = nil,
	}

	buildAnimationTracks(stalker)
	stalkers[key] = stalker

	CombatTargetRegistry.Register(model, {
		ApplyDamage = function()
			return false, true
		end,
		IsImmune = true,
	})
end

--[[
    @summary  Pick the nearest in-game player who is currently outside
              the campfire's safe zone.
    @param    fromPosition  Vector3  -- the stalker's current position
    @returns  Player?, Vector3?
]]
local function findHuntableTarget(fromPosition: Vector3): (Player?, Vector3?)
	local nearest: Player? = nil
	local nearestPos: Vector3? = nil
	local nearestDist = math.huge
	for _, player in ipairs(Players:GetPlayers()) do
		if spawnService and not spawnService:IsPlayerSpawned(player) then
			continue
		end
		local character = player.Character
		local rootPart = character and character:FindFirstChild("HumanoidRootPart")
		if not rootPart or not rootPart:IsA("BasePart") then
			continue
		end
		if campfireService and campfireService:IsInSafeZone(rootPart.Position) then
			continue
		end
		local dist = (rootPart.Position - fromPosition).Magnitude
		if dist < nearestDist then
			nearestDist = dist
			nearest = player
			nearestPos = rootPart.Position
		end
	end
	return nearest, nearestPos
end

--[[
    @summary  Compute a stalker's current speed based on how long it
              has been pursuing its current target.
    @param    stalker  table
    @returns  number
]]
local function computePursuitSpeed(stalker): number
	if not stalker.pursuitStartTime then
		return stalker.def.BaseSpeed
	end
	local elapsed = os.clock() - stalker.pursuitStartTime
	local bonus = math.min(elapsed * PURSUIT_ACCEL_PER_SEC, PURSUIT_MAX_BONUS_SPEED)
	return stalker.def.BaseSpeed + bonus
end

--[[
    @summary  Decide whether a dormant/patrolling stalker should begin
              or continue a pursuit, or retreat.
    @param    stalker  table
]]
local function updateStalkerState(stalker)
	local now = os.clock()

	if stalker.state == "Stunned" then
		if now >= stalker.stunUntil then
			stalker.state = if stalker.target then "Pursuing" else "Patrol"
		end
		return
	end

	if stalker.state == "Retreating" then
		if now >= stalker.retreatUntil then
			stalker.state = "Patrol"
			stalker.target = nil
		end
		return
	end

	if not timeService or timeService:GetCurrentPhase() ~= "Night" then
		if stalker.state ~= "Dormant" then
			enterDormant(stalker)
		end
		return
	end

	if stalker.state == "Dormant" then
		stalker.state = "Patrol"
		local campfirePosition = (worldService and worldService:GetCampfireCFrame() or CFrame.new()).Position
		local angle = math.random() * math.pi * 2
		local entryOffset = Vector3.new(math.cos(angle) * 70, 0, math.sin(angle) * 70)
		stalker.model:PivotTo(CFrame.new(campfirePosition + entryOffset))
	end

	if stalker.target then
		local character = (stalker.target :: Player).Character
		local rootPart = character and character:FindFirstChild("HumanoidRootPart")
		if not rootPart or (campfireService and campfireService:IsInSafeZone(rootPart.Position)) then
			stalker.state = "Retreating"
			stalker.retreatUntil = now + RETREAT_HOLD_TIME
			stalker.target = nil
			stalker.pursuitStartTime = nil
			return
		end
		stalker.state = "Pursuing"
		return
	end

	local target, _ = findHuntableTarget(stalker.rootPart.Position)
	if target then
		stalker.target = target
		stalker.pursuitStartTime = now
		stalker.state = "Pursuing"
	else
		stalker.state = "Patrol"
	end
end

--[[
    @summary  Execute movement/contact-damage behavior for a stalker's
              current state.
    @param    stalker  table
]]
local function runStalkerBehavior(stalker)
	if stalker.state == "Dormant" or stalker.state == "Stunned" then
		stalker.humanoid.WalkSpeed = 0
		if stalker.state == "Stunned" then
			playTrack(stalker, "StunnedLoop")
		end
		return
	end

	if stalker.state == "Retreating" then
		stalker.humanoid.WalkSpeed = stalker.def.BaseSpeed
		playTrack(stalker, "Run")
		local away = stalker.rootPart.CFrame.LookVector
		stalker.humanoid:MoveTo(stalker.rootPart.Position + away * -20)
		return
	end

	if stalker.state == "Patrol" then
		stalker.humanoid.WalkSpeed = stalker.def.BaseSpeed * 0.4
		playTrack(stalker, "Idle")
		return
	end

	if stalker.state == "Pursuing" and stalker.target then
		local character = (stalker.target :: Player).Character
		local rootPart = character and character:FindFirstChild("HumanoidRootPart")
		if not rootPart then
			return
		end

		local speed = computePursuitSpeed(stalker)
		stalker.humanoid.WalkSpeed = speed
		playTrack(stalker, if speed > stalker.def.BaseSpeed * 1.4 then "Run" else "Walk")
		stalker.humanoid:MoveTo(rootPart.Position)

		local dist = (stalker.rootPart.Position - rootPart.Position).Magnitude
		local now = os.clock()
		if dist <= CONTACT_RANGE and (now - stalker.lastContactTime) >= CONTACT_COOLDOWN then
			stalker.lastContactTime = now
			local targetHumanoid = character:FindFirstChildOfClass("Humanoid")
			if targetHumanoid then
				targetHumanoid:TakeDamage(stalker.def.AttackDamage)
				broadcastToAll(DeerService.Client.StalkerContact, stalker.rootPart.Position, stalker.key)
			end
		end
	end
end

--[[
    @summary  Interrupt a stalker's pursuit with a flashlight stun,
              shortening the duration for each consecutive use.
    @param    model   Model    -- the Deer/Ram Monster model
    @param    player  Player   -- the player holding the flashlight
    @returns  boolean          -- true if the stun was applied
]]
function DeerService:ApplyFlashlightStun(model: Model, player: Player): boolean
	for _, stalker in pairs(stalkers) do
		if stalker.model == model then
			if not stalker.def.UsesFlashlightStun or stalker.state ~= "Pursuing" then
				return false
			end

			local now = os.clock()
			if (now - stalker.lastStunTime) >= STUN_RESISTANCE_RECOVERY_TIME then
				stalker.consecutiveStuns = 0
			end
			stalker.consecutiveStuns += 1
			stalker.lastStunTime = now

			local duration = math.max(
				BASE_STUN_DURATION - (stalker.consecutiveStuns - 1) * STUN_DECAY_PER_USE,
				MIN_STUN_DURATION
			)

			stalker.state = "Stunned"
			stalker.stunUntil = now + duration
			stalker.humanoid.WalkSpeed = 0
			stopAllTracks(stalker)
			playTrack(stalker, "StunnedStart")
			task.delay(0.3, function()
				if stalker.state == "Stunned" then
					playTrack(stalker, "StunnedLoop")
				end
			end)
			task.delay(duration, function()
				if stalker.state == "Stunned" then
					playTrack(stalker, "StunnedEnd")
				end
			end)

			broadcastToAll(DeerService.Client.StalkerStunned, stalker.rootPart.Position, stalker.key, duration)
			return true
		end
	end
	return false
end

--[[
    @summary  Heartbeat-driven tick for every registered stalker.
]]
local function onHeartbeat()
	local now = os.clock()
	for _, stalker in pairs(stalkers) do
		if now >= stalker.nextDecisionTime then
			stalker.nextDecisionTime = now + DECISION_INTERVAL
			updateStalkerState(stalker)
		end
		runStalkerBehavior(stalker)
	end
end

-- // INITIALIZATION // --

function DeerService:KnitStart()
	worldService = Knit.GetService("WorldService")
	timeService = Knit.GetService("TimeService")
	campfireService = Knit.GetService("CampfireService")
	spawnService = Knit.GetService("SpawnService")

	task.delay(3, function()
		spawnStalker("Deer")
		spawnStalker("RamMonster")
	end)

	RunService.Heartbeat:Connect(onHeartbeat)

	print("[DeerService] Initialised — Deer/Ram Monster stalker AI active")
end

return DeerService
