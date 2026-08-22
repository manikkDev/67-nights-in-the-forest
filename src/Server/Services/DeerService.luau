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
		StalkerActive = Knit.CreateSignal(),
	},
})

-- | Configuration | --
local NPC_SOURCE_PATH = ServerStorage.Assets["Assets Npcs"]
local DORMANT_HOLDING_POSITION = Vector3.new(0, 300, 0)
local DECISION_INTERVAL = 0.2
local CONTACT_RANGE = 14
local CONTACT_COOLDOWN = 2.5
local ATTACK_LOCKOUT = 1.6 -- time the Deer pauses to play attack animation
local PURSUIT_ACCEL_PER_SEC = 0.35
local PURSUIT_MAX_BONUS_SPEED = 14
local BASE_STUN_DURATION = 4
local STUN_DECAY_PER_USE = 0.6
local MIN_STUN_DURATION = 1
local STUN_RESISTANCE_RECOVERY_TIME = 45
local RETREAT_HOLD_TIME = 3
local GAIT_AMPLITUDE = math.rad(35)
local GAIT_ARM_AMPLITUDE = math.rad(22)
local IDLE_LERP_SPEED = 6

-- Ram Monster starts appearing from night 8 onwards, with a 30% chance
-- to replace the Deer on any given night (mirrors the 99 Nights wiki:
-- "there is a chance for the Ram to spawn each night; if it does,
-- the Deer will not spawn")
local RAM_START_DAY = 8
local RAM_SPAWN_CHANCE = 0.30

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
local deerSuppressed = false
local activeStalkerKey: string? = nil  -- which stalker is active tonight ("Deer" or "RamMonster")
local lastPhase: string? = nil

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
	@summary  Collect every Motor6D whose second part is a leg or arm,
			  tagged with which side it is on for gait phasing.
	@param    model  Model
	@returns  { { motor: Motor6D, originalC0: CFrame, isLeg: boolean, side: string } }
]]
local function collectGaitJoints(model)
	local joints = {}
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("Motor6D") and descendant.Part1 then
			local partName = descendant.Part1.Name
			local lower = partName:lower()
			local isLeg = lower:find("leg") ~= nil or lower:find("foot") ~= nil
			local isArm = lower:find("arm") ~= nil or lower:find("hand") ~= nil
			if isLeg or isArm then
				local side = if lower:find("left") or lower:find("%.l") then "Left" else "Right"
				table.insert(joints, {
					motor = descendant,
					originalC0 = descendant.C0,
					isLeg = isLeg,
					side = side,
				})
			end
		end
	end
	return joints
end

--[[
	@summary  Register KeyframeSequences via KeyframeSequenceProvider
	          and update the model's Animations folder with the local IDs.
	          This bypasses the need for published animation asset IDs.
	@param    model  Model
]]
local function registerKeyframeAnims(model: Model)
	local KSSP = game:GetService("KeyframeSequenceProvider")
	local kfFolder = model:FindFirstChild("KeyframeSequences")
	if not kfFolder then return end

	local animFolder = model:FindFirstChild("Animations")
	if not animFolder then
		animFolder = Instance.new("Folder")
		animFolder.Name = "Animations"
		animFolder.Parent = model
	end

	for _, kfs in ipairs(kfFolder:GetChildren()) do
		if kfs:IsA("KeyframeSequence") then
			-- RegisterKeyframeSequence returns a hash (not a numeric asset ID).
			-- It must be used as-is without the "rbxassetid://" prefix.
			local assetId = KSSP:RegisterKeyframeSequence(kfs)
			local animObj = animFolder:FindFirstChild(kfs.Name)
			if not animObj then
				animObj = Instance.new("Animation")
				animObj.Name = kfs.Name
				animObj.Parent = animFolder
			end
			animObj.AnimationId = assetId
		end
	end
end

--[[
	@summary  Drive procedural leg/arm swing via Motor6D offsets for
			  custom rigs with no working baked locomotion animation.
	@param    stalker   table
	@param    dt        number
	@param    isMoving  boolean
]]
local function applyProceduralGait(stalker, dt: number, isMoving: boolean)
	if not stalker.gaitJoints then
		return
	end

	if isMoving then
		local speedFactor = math.clamp(stalker.humanoid.WalkSpeed / 10, 0.6, 2.6)
		stalker.gaitPhase = (stalker.gaitPhase or 0) + dt * 8 * speedFactor
	end

	for _, joint in ipairs(stalker.gaitJoints) do
		local target: CFrame
		if isMoving then
			local phaseOffset = if joint.side == "Right" then math.pi else 0
			local amplitude = if joint.isLeg then GAIT_AMPLITUDE else GAIT_ARM_AMPLITUDE
			local swing = math.sin(stalker.gaitPhase + phaseOffset) * amplitude
			target = joint.originalC0 * CFrame.Angles(swing, 0, 0)
		else
			target = joint.originalC0
		end
		joint.motor.C0 = joint.motor.C0:Lerp(target, math.clamp(dt * IDLE_LERP_SPEED, 0, 1))
	end
end

local DEFAULT_R6_WALK_ID = "rbxassetid://180426354"
local DEFAULT_R6_IDLE_ID = "rbxassetid://180435571"
local DEFAULT_R6_RUN_ID = "rbxassetid://180426354"

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

	-- Register KeyframeSequences FIRST so the Animations folder has valid local IDs
	registerKeyframeAnims(stalker.model)

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
						and animInstance.Name ~= "Attack"
					-- Set explicit priorities so Attack/Stunned override Walk/Run
					if animInstance.Name == "Attack" or animInstance.Name == "Jumpscare" then
						track.Priority = Enum.AnimationPriority.Action4
					elseif animInstance.Name:match("^Stunned") then
						track.Priority = Enum.AnimationPriority.Action4
					elseif animInstance.Name == "Walk" or animInstance.Name == "Run" then
						track.Priority = Enum.AnimationPriority.Action2
					elseif animInstance.Name == "Idle" then
						track.Priority = Enum.AnimationPriority.Idle
					end
					stalker.tracks[animInstance.Name] = track
				end
			end
		end
	end

	if not stalker.tracks.Walk then
		stalker.tracks.Walk = loadTrack(DEFAULT_R6_WALK_ID, true)
	end
	if not stalker.tracks.Run then
		stalker.tracks.Run = loadTrack(DEFAULT_R6_RUN_ID, true)
	end
	if not stalker.tracks.Idle then
		stalker.tracks.Idle = loadTrack(DEFAULT_R6_IDLE_ID, true)
	end
end

--[[
    @summary  Stop every currently-playing track on a stalker.
    @param    stalker  table
]]
local function stopAllTracks(stalker)
	for _, track in pairs(stalker.tracks) do
		if track.IsPlaying then
			track:Stop(0)
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
	if not track then
		warn("[DeerService] No track found for", name, "on", stalker.key)
		return
	end
	-- Don't restart if already playing (avoids stutter on looping tracks
	-- that are called every Heartbeat like Walk/Run/Idle)
	if track.IsPlaying then return end
	stopAllTracks(stalker)
	track:Play(0.15)
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
	if stalker.rootPart then
		stalker.rootPart.Anchored = true
	end
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
	-- Prefer HRP (the actual PrimaryPart) over HumanoidRootPart, since
	-- HumanoidRootPart may be a non-colliding anchored dummy in custom rigs
	local rootPart = model:FindFirstChild("HRP") or model:FindFirstChild("HumanoidRootPart")
	if not humanoid or not rootPart then
		warn("[DeerService] Template", def.ModelName, "missing Humanoid/root part")
		model:Destroy()
		return
	end

	-- Anchor the root part to keep the model suspended at the dormant position.
	-- It will be un-anchored when the stalker activates at night.
	rootPart.Anchored = true
	-- Un-anchor everything else (including HumanoidRootPart, which is welded
	-- to HRP — if it stays anchored the weld prevents the whole model from moving).
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") and part ~= rootPart then
			part.Anchored = false
		end
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
		attackUntil = 0,
		consecutiveStuns = 0,
		lastStunTime = 0,
		stunUntil = 0,
		retreatUntil = 0,
		nextDecisionTime = 0,
		pursuitStartTime = nil,
	}

	buildAnimationTracks(stalker)

	-- Note: Procedural gait is disabled for the Deer because we now have
	-- proper KeyframeSequence-based animations registered via
	-- KeyframeSequenceProvider that handle all joint movement.
	-- Using both would conflict as they both set Motor6D.Transform.

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

	local currentPhase = timeService and timeService:GetCurrentPhase() or "Day"

	-- Phase transition: decide which stalker is active tonight
	if currentPhase ~= lastPhase then
		lastPhase = currentPhase
		if currentPhase == "Night" then
			local dayNumber = timeService:GetDayNumber()
			-- Roll for Ram Monster replacing the Deer (from RAM_START_DAY onwards)
			if dayNumber >= RAM_START_DAY and math.random() <= RAM_SPAWN_CHANCE then
				activeStalkerKey = "RamMonster"
				print("[DeerService] The Ram Monster is active tonight (night", dayNumber, ")")
			else
				activeStalkerKey = "Deer"
				print("[DeerService] The Deer is active tonight (night", dayNumber, ")")
			end
			broadcastToAll(DeerService.Client.StalkerActive, activeStalkerKey)
		elseif currentPhase == "Day" then
			activeStalkerKey = nil
		end
	end

	if currentPhase ~= "Night" then
		if stalker.state ~= "Dormant" then
			enterDormant(stalker)
		end
		return
	end

	-- Only the active stalker for tonight is allowed to hunt
	if stalker.key ~= activeStalkerKey then
		if stalker.state ~= "Dormant" then
			enterDormant(stalker)
		end
		return
	end

	-- Deer is suppressed when the Owl is active tonight
	if deerSuppressed and stalker.key == "Deer" then
		if stalker.state ~= "Dormant" then
			enterDormant(stalker)
		end
		return
	end

	if stalker.state == "Dormant" then
		stalker.state = "Patrol"
		local campfirePosition = (worldService and worldService:GetCampfireCFrame() or CFrame.new()).Position
		local angle = math.random() * math.pi * 2
		local entryOffset = Vector3.new(math.cos(angle) * 90, 0, math.sin(angle) * 90)
		-- Raycast down to find ground level so the Deer doesn't spawn underground
		local spawnPos = campfirePosition + entryOffset
		local rayOrigin = spawnPos + Vector3.new(0, 200, 0)
		local rayParams = RaycastParams.new()
		local rayResult = workspace:Raycast(rayOrigin, Vector3.new(0, -400, 0), rayParams)
		if rayResult then
			spawnPos = rayResult.Position + Vector3.new(0, 5, 0)
		else
			spawnPos = spawnPos + Vector3.new(0, 10, 0)
		end
		stalker.model:PivotTo(CFrame.new(spawnPos))
		-- Un-anchor the root part so the Deer can walk
		if stalker.rootPart then
			stalker.rootPart.Anchored = false
		end
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
		local campfirePos = (worldService and worldService:GetCampfireCFrame() or CFrame.new()).Position
		local awayDir = stalker.rootPart.Position - campfirePos
		if awayDir.Magnitude < 1 then
			awayDir = Vector3.new(1, 0, 0)
		end
		awayDir = Vector3.new(awayDir.X, 0, awayDir.Z).Unit
		stalker.humanoid:MoveTo(stalker.rootPart.Position + awayDir * 40)
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

		local now = os.clock()

		-- Attack lockout: pause movement and let the Attack animation play
		if now < stalker.attackUntil then
			stalker.humanoid.WalkSpeed = 0
			return
		end

		local speed = computePursuitSpeed(stalker)
		stalker.humanoid.WalkSpeed = speed
		playTrack(stalker, if speed > stalker.def.BaseSpeed * 1.4 then "Run" else "Walk")
		stalker.humanoid:MoveTo(rootPart.Position)

		local dist = (stalker.rootPart.Position - rootPart.Position).Magnitude
		if dist <= CONTACT_RANGE and (now - stalker.lastContactTime) >= CONTACT_COOLDOWN then
			stalker.lastContactTime = now
			stalker.attackUntil = now + ATTACK_LOCKOUT
			local targetHumanoid = character:FindFirstChildOfClass("Humanoid")
			if targetHumanoid then
				targetHumanoid:TakeDamage(stalker.def.AttackDamage)
				-- Stop only Walk/Run (not all tracks) to avoid nuking Attack
				if stalker.tracks.Walk and stalker.tracks.Walk.IsPlaying then
					stalker.tracks.Walk:Stop(0.1)
				end
				if stalker.tracks.Run and stalker.tracks.Run.IsPlaying then
					stalker.tracks.Run:Stop(0.1)
				end
				local attackTrack = stalker.tracks.Attack
				if attackTrack then
					attackTrack:Play(0.1)
				end
				broadcastToAll(DeerService.Client.StalkerContact, stalker.rootPart.Position, stalker.key)
			end
		end
	end
end

--[[
    @summary  Suppress or unsuppress the Deer (called by OwlService).
              When suppressed, the Deer stays dormant even at night.
    @param    suppressed  boolean
]]
function DeerService:SuppressDeer(suppressed: boolean)
	deerSuppressed = suppressed
	if suppressed then
		local deer = stalkers["Deer"]
		if deer and deer.state ~= "Dormant" then
			enterDormant(deer)
		end
	end
end

--[[
    @summary  Return whether the Deer stalker is currently active (not dormant).
    @returns  boolean
]]
function DeerService:IsDeerActive(): boolean
	local deer = stalkers["Deer"]
	return deer ~= nil and deer.state ~= "Dormant"
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
local function onHeartbeat(dt: number)
	local now = os.clock()
	for _, stalker in pairs(stalkers) do
		if now >= stalker.nextDecisionTime then
			stalker.nextDecisionTime = now + DECISION_INTERVAL
			updateStalkerState(stalker)
		end
		runStalkerBehavior(stalker)

		-- Apply procedural gait for custom-rig stalkers (Deer)
		if stalker.gaitJoints then
			local vel = stalker.rootPart.AssemblyLinearVelocity
			local isMoving = Vector3.new(vel.X, 0, vel.Z).Magnitude > 1
			applyProceduralGait(stalker, dt, isMoving and stalker.state ~= "Stunned")
		end
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
