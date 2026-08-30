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
local PathfindingService = game:GetService("PathfindingService")
local Workspace = game:GetService("Workspace")
local _Debris = game:GetService("Debris")

-- | Modules | --
local Knit = require(ReplicatedStorage.Packages.Knit)
local ServerRole = require(ReplicatedStorage.Shared.ServerRole)
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
local NPC_SOURCE_PATH = ServerStorage:FindFirstChild("Assets") and ServerStorage.Assets:FindFirstChild("Assets Npcs") or nil
if not NPC_SOURCE_PATH then
	warn("[DeerService] NPC_SOURCE_PATH not found: ServerStorage.Assets.Assets Npcs")
end
local DORMANT_HOLDING_POSITION = Vector3.new(0, 300, 0)
local DECISION_INTERVAL = 0.2
local CONTACT_RANGE = 14
local CONTACT_COOLDOWN = 2.5
local ATTACK_LOCKOUT = 1.6 -- time the Deer pauses to play attack animation
local PURSUIT_ACCEL_PER_SEC = 0.35
local PURSUIT_MAX_BONUS_SPEED = 14
local BASE_STUN_DURATION = 3
local STUN_DECAY_PER_USE = 0.5
local MIN_STUN_DURATION = 1
local STUN_RESISTANCE_RECOVERY_TIME = 30
local MAX_CONTINUOUS_STUN = 5 -- max total seconds the deer can stay stunned from continuous beam refresh
local STUN_COOLDOWN = 3 -- seconds after a stun expires before the deer can be re-stunned
local RETREAT_HOLD_TIME = 3
-- Pathfinding configuration
local PATH_RECOMPUTE_INTERVAL = 0.4 -- recompute path every 0.4s for responsive chasing
local PATH_AGENT_RADIUS = 3
local PATH_AGENT_HEIGHT = 6
local WAYPOINT_REACHED_DIST = 4 -- distance to consider a waypoint reached
local STUCK_CHECK_INTERVAL = 0.3 -- check if stuck every 0.3s
local STUCK_DIST_THRESHOLD = 1.5 -- if moved less than 1.5 studs in 0.3s, consider stuck
local STUCK_MAX_COUNT = 2 -- force recompute after this many stuck checks
local LOS_CHECK_INTERVAL = 0.3 -- check line-of-sight every 0.3s
local LOS_RAY_OFFSET = 2 -- raycast from 2 studs above root part
local DIRECT_CHASE_DIST = 60 -- if player within this dist and visible, run straight at them
local OBSTACLE_AVOID_DIST = 12 -- how far to steer around an obstacle when stuck
local PATH_COMPUTING_TIMEOUT = 1.5 -- max time to wait for a path computation before giving up
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
local runStateService: any = nil
local campfireService: any = nil
local spawnService: any = nil
local playerLifeService: any = nil
local worldProgressionService: any = nil
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
	if not runStateService or not runStateService:IsActive() then
		return
	end
	for _, player in ipairs(runStateService:GetMembers()) do
		signal:Fire(player, ...)
	end
end

--[[
	@summary  Collect every Motor6D whose second part is a leg or arm,
			  tagged with which side it is on for gait phasing.
	@param    model  Model
	@returns  { { motor: Motor6D, originalC0: CFrame, isLeg: boolean, side: string } }
]]
local function _collectGaitJoints(model)
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
	-- RegisterKeyframeSequence ONLY works in Studio. In a published game it
	-- throws "RegisterKeyframeSequence can only be called in Studio", which
	-- crashes the entire DeerService. We wrap it in a pcall and silently fall
	-- back to the default R6 walk/idle/run animation IDs (defined below in
	-- buildAnimationTracks) when running in production.
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
			-- Try to register the KeyframeSequence. In production this will
			-- fail and we fall back to default animation IDs.
			local ok, assetId = pcall(function()
				return KSSP:RegisterKeyframeSequence(kfs)
			end)
			if ok and typeof(assetId) == "string" and assetId ~= "" then
				local animObj = animFolder:FindFirstChild(kfs.Name)
				if not animObj then
					animObj = Instance.new("Animation")
					animObj.Name = kfs.Name
					animObj.Parent = animFolder
				end
				animObj.AnimationId = assetId
			else
				warn("[DeerService] RegisterKeyframeSequence failed for", kfs.Name, "— using default animations instead")
			end
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
					if animInstance.Name == "Attack" or animInstance.Name == "Jumpscare" or animInstance.Name == "Scared" then
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
	-- Only stop locomotion tracks to avoid nuking Attack/Stunned animations
	local locomotionTracks = { Walk = true, Run = true, Idle = true }
	for trackName, t in pairs(stalker.tracks) do
		if t ~= track and t.IsPlaying and locomotionTracks[trackName] then
			t:Stop(0.15)
		end
	end
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
	-- Reset pathfinding state
	stalker.waypoints = nil
	stalker.waypointIndex = 1
	stalker.lastPathRecompute = 0
	stalker.lastStuckPosition = nil
	stalker.stuckCounter = 0
	stalker.pathComputing = false
	stalker.lastLOSCheck = 0
	stalker.hasLineOfSight = false
	stalker.avoidanceDir = nil
	stalker.avoidanceUntil = 0
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

	-- Set PrimaryPart so external services (FlashlightService) can locate
	-- the stalker's position via model.PrimaryPart
	model.PrimaryPart = rootPart

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
		stunEndPlayed = false,
		stunStartTime = 0, -- when the current continuous stun began
		stunImmune = false, -- true when deer has been stunned too long and needs to recover
		postStunLockout = 0, -- time until which the deer pauses after stun ends
		stunCooldownUntil = 0, -- time until which the deer can't be re-stunned after a stun ends
		retreatUntil = 0,
		nextDecisionTime = 0,
		pursuitStartTime = nil,
		-- Pathfinding state
		waypoints = nil,
		waypointIndex = 1,
		lastPathRecompute = 0,
		lastStuckCheck = 0,
		lastStuckPosition = nil,
		stuckCounter = 0,
		pathComputing = false, -- true while a path computation is in progress
		lastLOSCheck = 0,
		hasLineOfSight = false, -- true if the deer can see the target directly
		avoidanceDir = nil, -- temporary steering direction when avoiding obstacles
		avoidanceUntil = 0, -- time until which to follow the avoidance direction
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
	for _, player in ipairs(runStateService:GetMembers()) do
		if not runStateService:IsActive() or not runStateService:IsMember(player) then
			continue
		end
		if spawnService and not spawnService:IsPlayerSpawned(player) then
			continue
		end
		if playerLifeService and not playerLifeService:IsAlive(player) then
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
			-- Play StunnedEnd transition animation
			if not stalker.stunEndPlayed then
				stalker.stunEndPlayed = true
				stopAllTracks(stalker)
				local endTrack = stalker.tracks["StunnedEnd"]
				if endTrack then
					endTrack:Play(0.1)
				end
				-- Set the lockout ONCE when stun first expires
				stalker.postStunLockout = now + 0.3
			end
			-- Transition after the lockout
			if stalker.postStunLockout > 0 and now >= stalker.postStunLockout then
				-- Stop all stun animations before transitioning
				stopAllTracks(stalker)
				-- Un-anchor the root part
				if stalker.rootPart.Anchored then
					stalker.rootPart.Anchored = false
				end
				stalker.state = if stalker.target then "Pursuing" else "Patrol"
				stalker.postStunLockout = 0
				-- Set cooldown so the deer can't be immediately re-stunned
				stalker.stunCooldownUntil = now + STUN_COOLDOWN
				-- Clear stun immunity flag after recovery
				if stalker.stunImmune and now - stalker.stunUntil >= STUN_RESISTANCE_RECOVERY_TIME * 0.5 then
					stalker.stunImmune = false
					stalker.consecutiveStuns = 0
				end
			end
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
			else
				activeStalkerKey = "Deer"
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
		-- Spawn far from campfire but within the current accessible map area
		-- Use 60-90% of the access radius so it's far but not outside the boundary
		local accessRadius = if worldProgressionService then worldProgressionService:GetAccessRadius() else 350
		local minSpawn = math.max(80, accessRadius * 0.6)
		local maxSpawn = math.max(minSpawn + 50, accessRadius * 0.9)
		local spawnDistance = minSpawn + math.random() * (maxSpawn - minSpawn)
		local entryOffset = Vector3.new(math.cos(angle) * spawnDistance, 0, math.sin(angle) * spawnDistance)
		local spawnPos = campfirePosition + entryOffset
		local groundY = worldService and worldService:GetGroundY()
		spawnPos = Vector3.new(spawnPos.X, (groundY or spawnPos.Y) + 5, spawnPos.Z)
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
    @summary  Check if the deer has a direct line of sight to the target.
              Uses raycasting to detect obstacles between the deer and target.
    @param    stalker   table
    @param    targetPos Vector3
    @returns  boolean
]]
local function checkLineOfSight(stalker, targetPos: Vector3): boolean
	local rootPos = stalker.rootPart.Position
	local startPos = rootPos + Vector3.new(0, LOS_RAY_OFFSET, 0)
	local endPos = targetPos + Vector3.new(0, LOS_RAY_OFFSET, 0)
	local direction = endPos - startPos
	local distance = direction.Magnitude
	if distance < 0.1 then
		return true
	end

	-- Raycast params: ignore the deer's own model
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = { stalker.model }

	local result = Workspace:Raycast(startPos, direction, rayParams)
	if not result then
		return true -- no obstacle, clear line of sight
	end

	-- If the hit obstacle is closer than the target, no line of sight
	local hitDist = (result.Position - startPos).Magnitude
	return hitDist >= distance - 2
end

--[[
    @summary  Compute a pathfinding route to a destination asynchronously.
              Uses task.spawn so it doesn't block the Heartbeat thread.
    @param    stalker      table
    @param    destination  Vector3
]]
local function recomputePath(stalker, destination: Vector3)
	if stalker.pathComputing then
		return -- already computing a path
	end
	stalker.pathComputing = true
	stalker.lastPathRecompute = os.clock()

	local startPos = stalker.rootPart.Position
	local targetPos = destination

	task.spawn(function()
		local path = PathfindingService:CreatePath({
			AgentRadius = PATH_AGENT_RADIUS,
			AgentHeight = PATH_AGENT_HEIGHT,
			AgentCanJump = false,
		})

		local ok = pcall(function()
			path:ComputeAsync(startPos, targetPos)
		end)

		stalker.pathComputing = false

		if ok and path.Status == Enum.PathStatus.Success then
			local waypoints = path:GetWaypoints()
			-- Only update if we're still chasing the same general area
			-- (the target may have moved, but the path is still useful)
			stalker.waypoints = waypoints
			stalker.waypointIndex = 1
			stalker.stuckCounter = 0
		else
			-- Pathfinding failed — clear waypoints so we fall back to obstacle avoidance
			stalker.waypoints = nil
			stalker.waypointIndex = 1
		end
	end)
end

--[[
    @summary  Detect if the deer is stuck (not moving despite trying to).
    @param    stalker  table
    @param    rootPos  Vector3
    @returns  boolean  -- true if stuck
]]
local function detectStuck(stalker, rootPos: Vector3): boolean
	local now = os.clock()
	if not stalker.lastStuckPosition then
		stalker.lastStuckCheck = now
		stalker.lastStuckPosition = rootPos
		return false
	end

	if now - stalker.lastStuckCheck < STUCK_CHECK_INTERVAL then
		return false
	end

	local movedDist = (Vector3.new(rootPos.X, 0, rootPos.Z) - Vector3.new(stalker.lastStuckPosition.X, 0, stalker.lastStuckPosition.Z)).Magnitude
	stalker.lastStuckCheck = now
	stalker.lastStuckPosition = rootPos

	if movedDist < STUCK_DIST_THRESHOLD then
		stalker.stuckCounter += 1
		if stalker.stuckCounter >= STUCK_MAX_COUNT then
			return true
		end
	else
		stalker.stuckCounter = 0
	end
	return false
end

--[[
    @summary  Pick a perpendicular avoidance direction when the deer is stuck.
              Raycasts to find an open direction to steer around the obstacle.
    @param    stalker      table
    @param    destination  Vector3
]]
local function startAvoidance(stalker, destination: Vector3)
	local now = os.clock()
	local rootPos = stalker.rootPart.Position
	local toTarget = (destination - rootPos)
	toTarget = Vector3.new(toTarget.X, 0, toTarget.Z)
	if toTarget.Magnitude < 0.1 then
		return
	end
	toTarget = toTarget.Unit

	-- Try perpendicular directions (left and right of the direct path)
	local leftDir = Vector3.new(-toTarget.Z, 0, toTarget.X)
	local rightDir = Vector3.new(toTarget.Z, 0, -toTarget.X)

	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = { stalker.model }

	-- Check which side has more open space
	local leftResult = Workspace:Raycast(rootPos + Vector3.new(0, 1, 0), leftDir * OBSTACLE_AVOID_DIST, rayParams)
	local rightResult = Workspace:Raycast(rootPos + Vector3.new(0, 1, 0), rightDir * OBSTACLE_AVOID_DIST, rayParams)

	local leftClear = not leftResult
	local rightClear = not rightResult

	if leftClear and rightClear then
		-- Both clear — pick one randomly to avoid getting stuck in a loop
		stalker.avoidanceDir = if math.random() > 0.5 then leftDir else rightDir
	elseif leftClear then
		stalker.avoidanceDir = leftDir
	elseif rightClear then
		stalker.avoidanceDir = rightDir
	else
		-- Both blocked — try the direction with more space (longer raycast hit)
		local leftDist = if leftResult then (leftResult.Position - rootPos).Magnitude else 0
		local rightDist = if rightResult then (rightResult.Position - rootPos).Magnitude else 0
		stalker.avoidanceDir = if leftDist > rightDist then leftDir else rightDir
	end

	stalker.avoidanceUntil = now + 1.0 -- avoid for 1 second
	stalker.stuckCounter = 0
	stalker.waypoints = nil -- clear stale path
	stalker.lastPathRecompute = 0 -- force path recompute after avoidance
end

--[[
    @summary  Move the stalker toward a destination using an advanced
              navigation system:
              1. Check line-of-sight — if clear, run straight at target
              2. If blocked, use pathfinding to navigate around obstacles
              3. If stuck, use obstacle avoidance steering
              4. Fall back to direct movement if all else fails
    @param    stalker      table
    @param    destination  Vector3
]]
local function moveTowards(stalker, destination: Vector3)
	local now = os.clock()
	local rootPos = stalker.rootPart.Position
	local flatRootPos = Vector3.new(rootPos.X, 0, rootPos.Z)
	local flatDest = Vector3.new(destination.X, 0, destination.Z)
	local distToTarget = (flatRootPos - flatDest).Magnitude

	-- Check line of sight periodically
	if now - stalker.lastLOSCheck >= LOS_CHECK_INTERVAL then
		stalker.lastLOSCheck = now
		stalker.hasLineOfSight = checkLineOfSight(stalker, destination)
	end

	-- If we have line of sight and the target is close enough, run straight at it
	if stalker.hasLineOfSight and distToTarget < DIRECT_CHASE_DIST then
		stalker.waypoints = nil -- no need for pathfinding
		stalker.avoidanceDir = nil
		stalker.humanoid:MoveTo(destination)
		return
	end

	-- If currently in avoidance mode, steer around the obstacle
	if stalker.avoidanceDir and now < stalker.avoidanceUntil then
		local avoidPos = rootPos + stalker.avoidanceDir * 20
		stalker.humanoid:MoveTo(avoidPos)
		return
	end
	stalker.avoidanceDir = nil

	-- Stuck detection
	if detectStuck(stalker, rootPos) then
		-- Force a path recompute and start avoidance
		startAvoidance(stalker, destination)
		return
	end

	-- Recompute path periodically or if no path exists
	if not stalker.waypoints and not stalker.pathComputing and (now - stalker.lastPathRecompute) >= PATH_RECOMPUTE_INTERVAL then
		recomputePath(stalker, destination)
	end

	-- Follow waypoints if available
	if stalker.waypoints and stalker.waypoints[stalker.waypointIndex] then
		local waypoint = stalker.waypoints[stalker.waypointIndex]
		local flatDist = (flatRootPos - Vector3.new(waypoint.Position.X, 0, waypoint.Position.Z)).Magnitude
		if flatDist < WAYPOINT_REACHED_DIST then
			stalker.waypointIndex += 1
		end
		local nextWaypoint = stalker.waypoints[stalker.waypointIndex]
		if nextWaypoint then
			-- Move to the waypoint position but keep Y at the deer's current level
			-- to prevent the deer from trying to move to elevated waypoint positions
			local movePos = Vector3.new(nextWaypoint.Position.X, rootPos.Y, nextWaypoint.Position.Z)
			stalker.humanoid:MoveTo(movePos)
		else
			-- Ran out of waypoints — head directly to destination
			stalker.humanoid:MoveTo(destination)
			stalker.waypoints = nil
		end
	else
		-- No path available and not computing — use direct movement
		-- but check if there's an obstacle directly ahead
		if not stalker.pathComputing then
			local toTarget = (flatDest - flatRootPos)
			if toTarget.Magnitude > 0.1 then
				toTarget = toTarget.Unit
				local rayParams = RaycastParams.new()
				rayParams.FilterType = Enum.RaycastFilterType.Exclude
				rayParams.FilterDescendantsInstances = { stalker.model }
				local result = Workspace:Raycast(rootPos + Vector3.new(0, 1, 0), toTarget * 8, rayParams)
				if result then
					-- Obstacle ahead — start avoidance
					startAvoidance(stalker, destination)
					return
				end
			end
			stalker.humanoid:MoveTo(destination)
		end
	end
end

--[[
    @summary  Execute movement/contact-damage behavior for a stalker's
              current state.
    @param    stalker  table
]]
local function runStalkerBehavior(stalker)
	-- If the deer is in post-stun lockout, keep it frozen.
	-- Do NOT clear postStunLockout here — updateStalkerState owns the transition.
	if stalker.postStunLockout > 0 then
		if os.clock() < stalker.postStunLockout then
			stalker.humanoid.WalkSpeed = 0
			stalker.humanoid:MoveTo(stalker.rootPart.Position)
			if not stalker.rootPart.Anchored then
				stalker.rootPart.Anchored = true
			end
			return
		end
		-- Lockout expired but state hasn't transitioned yet — keep frozen
		-- until updateStalkerState changes the state
		stalker.humanoid.WalkSpeed = 0
		stalker.humanoid:MoveTo(stalker.rootPart.Position)
		return
	end

	if stalker.state == "Dormant" or stalker.state == "Stunned" then
		stalker.humanoid.WalkSpeed = 0
		if stalker.state == "Stunned" then
			-- Explicitly cancel any pending MoveTo from the previous Pursuing frame
			stalker.humanoid:MoveTo(stalker.rootPart.Position)
			-- Anchor the root part to prevent physics from dragging the deer
			-- while it's stunned (players walking into it can push it around)
			if not stalker.rootPart.Anchored then
				stalker.rootPart.Anchored = true
			end
			local startTrack = stalker.tracks["StunnedStart"]
			local loopTrack = stalker.tracks["StunnedLoop"]
			-- Stop Attack track if it's still playing from a recent contact
			local attackTrack = stalker.tracks["Attack"]
			if attackTrack and attackTrack.IsPlaying then
				attackTrack:Stop(0)
			end
			if startTrack and startTrack.IsPlaying then
				-- Let StunnedStart finish, then switch to StunnedLoop in next tick
			elseif loopTrack and not loopTrack.IsPlaying then
				if startTrack then startTrack:Stop(0) end
				loopTrack:Play(0.1)
			end
		end
		return
	end

	-- Un-anchor the root part if it was anchored during stun
	if stalker.rootPart.Anchored then
		stalker.rootPart.Anchored = false
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
		-- Use pathfinding for retreat too so the deer doesn't get stuck fleeing
		moveTowards(stalker, stalker.rootPart.Position + awayDir * 60)
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
		-- Use pathfinding to navigate around obstacles instead of direct MoveTo
		moveTowards(stalker, rootPart.Position)

		local dist = (stalker.rootPart.Position - rootPart.Position).Magnitude
		if dist <= CONTACT_RANGE and (now - stalker.lastContactTime) >= CONTACT_COOLDOWN then
			stalker.lastContactTime = now
			stalker.attackUntil = now + ATTACK_LOCKOUT
			local targetPlayer = stalker.target :: Player?
			if targetPlayer and playerLifeService and playerLifeService:IsAlive(targetPlayer) then
				playerLifeService:ApplyDamage(targetPlayer, stalker.def.AttackDamage, stalker.key)
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
    @summary  Return every stalker to its hidden dormant state.
]]
function DeerService:ResetForRun()
	deerSuppressed = false
	activeStalkerKey = nil
	lastPhase = nil
	for _, stalker in pairs(stalkers) do
		enterDormant(stalker)
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
			if not stalker.def.UsesFlashlightStun then
				return false
			end
			if stalker.state == "Dormant" then
				return false
			end

			local now = os.clock()

			-- If the deer is in stun cooldown (recently recovered from a stun),
			-- don't allow re-stunning until the cooldown passes
			if now < stalker.stunCooldownUntil then
				return false
			end

			-- If the deer is stun-immune (was stunned too long), don't re-stun
			-- until the immunity period passes
			if stalker.stunImmune then
				if now - stalker.stunUntil >= STUN_RESISTANCE_RECOVERY_TIME * 0.5 then
					-- Immunity expired, allow stunning again
					stalker.stunImmune = false
					stalker.consecutiveStuns = 0
				else
					return false
				end
			end

			-- If already stunned, refresh the stun timer BUT only if the stun
			-- hasn't already expired. Once the stun timer has expired, let the
			-- deer recover — don't refresh even if the beam is still on.
			if stalker.state == "Stunned" then
				-- If stun has already expired, don't refresh — let recovery happen
				if now >= stalker.stunUntil then
					return false
				end
				local continuousStunTime = now - stalker.stunStartTime
				if continuousStunTime >= MAX_CONTINUOUS_STUN then
					-- Deer has been stunned too long — break free and become immune
					stalker.stunImmune = true
					stalker.stunUntil = now -- expire immediately
					stalker.stunEndPlayed = false
					return false
				end
				-- Refresh stun but don't extend beyond the max continuous cap
				local refreshDuration = math.max(
					BASE_STUN_DURATION - (stalker.consecutiveStuns - 1) * STUN_DECAY_PER_USE,
					MIN_STUN_DURATION
				)
				local maxRemaining = MAX_CONTINUOUS_STUN - continuousStunTime
				stalker.stunUntil = now + math.min(refreshDuration, maxRemaining)
				stalker.stunEndPlayed = false
				-- Ensure StunnedLoop is playing
				local loopTrack = stalker.tracks["StunnedLoop"]
				if loopTrack and not loopTrack.IsPlaying then
					local startTrack = stalker.tracks["StunnedStart"]
					if startTrack and startTrack.IsPlaying then
						-- Let StunnedStart finish naturally
					else
						loopTrack:Play(0.1)
					end
				end
				return true
			end

			-- New stun application
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
			stalker.stunStartTime = now
			stalker.humanoid.WalkSpeed = 0
			stalker.stunEndPlayed = false
			-- Reset pathfinding state so stale waypoints don't interfere after recovery
			stalker.waypoints = nil
			stalker.waypointIndex = 1
			stalker.lastPathRecompute = 0
			stalker.lastStuckPosition = nil
			stalker.stuckCounter = 0
			stalker.pathComputing = false
			stalker.avoidanceDir = nil
			stalker.avoidanceUntil = 0
			-- Stop all tracks immediately so Attack/Run don't override StunnedStart
			stopAllTracks(stalker)
			-- Play StunnedStart directly
			local startTrack = stalker.tracks["StunnedStart"]
			if startTrack then
				startTrack:Play(0.1)
			else
				local loopTrack = stalker.tracks["StunnedLoop"]
				if loopTrack then
					loopTrack:Play(0.1)
				else
					warn("[DeerService] No stunned animations found for", stalker.key)
				end
			end

			print(string.format("[DeerService] STUNNED %s for %.1fs by %s (consecutive: %d)",
				stalker.key, duration, player.Name, stalker.consecutiveStuns))

			broadcastToAll(DeerService.Client.StalkerStunned, stalker.rootPart.Position, stalker.key, duration, player.UserId)
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
	if not ServerRole.IsGameServer() then return end
	worldService = Knit.GetService("WorldService")
	timeService = Knit.GetService("TimeService")
	runStateService = Knit.GetService("RunStateService")
	campfireService = Knit.GetService("CampfireService")
	spawnService = Knit.GetService("SpawnService")
	playerLifeService = Knit.GetService("PlayerLifeService")
	worldProgressionService = Knit.GetService("WorldProgressionService")

	task.delay(3, function()
		spawnStalker("Deer")
		spawnStalker("RamMonster")
	end)

	RunService.Heartbeat:Connect(onHeartbeat)
end

return DeerService
