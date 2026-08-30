--[[
    @file    AnimalAIService.luau
    @author  manik
    @date    2025

    @summary
    Server-authoritative spawn/despawn and patrol/chase/attack/flee AI
    for every non-unique NPC species (passive, predator, and solitary).

    @description
    Generic per-species state machine driven by `NpcConfig`.  Owns the
    day/night population cycle for Bunny/Wolf/AlphaWolf/Bear, and
    exposes SpawnNpc/DespawnAllOfSpecies so CultistRaidService can
    reuse the same chase/attack machinery for raid waves without a
    second implementation.  Every spawned NPC is registered with
    `CombatTargetRegistry` so CombatService can damage it generically.

    @exports
    - AnimalAIService:SpawnNpc(speciesKey, cframe) -> Model?
    - AnimalAIService:DespawnAllOfSpecies(speciesKey)
    - Knit Signal: NpcAttacked(position)  (server -> client, VFX hook)
]]

-- // VARIABLES // --

-- | Services | --
local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local PathfindingService = game:GetService("PathfindingService")
local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")

-- | Modules | --
local Knit = require(ReplicatedStorage.Packages.Knit)
local ServerRole = require(ReplicatedStorage.Shared.ServerRole)
local Signal = require(ReplicatedStorage.Packages.Signal)
local NpcConfig = require(ReplicatedStorage.Shared.NpcConfig)
local RunConfig = require(ReplicatedStorage.Shared.RunConfig)
local WorldProgressionConfig = require(ReplicatedStorage.Shared.WorldProgressionConfig)
local CombatTargetRegistry = require(script.Parent.Parent.CombatTargetRegistry)

-- | Objects | --
local AnimalAIService = Knit.CreateService({
	Name = "AnimalAIService",
	Client = {
		NpcAttacked = Knit.CreateSignal(),
		NpcDied = Knit.CreateSignal(),
		NpcHealthChanged = Knit.CreateSignal(),
	},
})

AnimalAIService.NpcDiedServer = Signal.new()

-- | Configuration | --
local NPC_SOURCE_PATH = ServerStorage:FindFirstChild("Assets") and ServerStorage.Assets:FindFirstChild("Assets Npcs") or nil
if not NPC_SOURCE_PATH then
	warn("[AnimalAIService] NPC_SOURCE_PATH not found: ServerStorage.Assets.Assets Npcs")
end
local DECISION_INTERVAL = 0.25
local MIN_SPAWN_DIST = 20
local MAX_SPAWN_DIST = 60
-- Bunnies spawn far from campfire, scattered across all levels
local BUNNY_MIN_SPAWN_DIST = 100
local BUNNY_MAX_SPAWN_DIST = 200
-- Bears spawn at level 3+ distance (far out)
local BEAR_MIN_SPAWN_DIST = 250
local BEAR_MAX_SPAWN_DIST = 400
local GAIT_AMPLITUDE = math.rad(35)
local GAIT_ARM_AMPLITUDE = math.rad(22)
local IDLE_LERP_SPEED = 6
local PATH_RECOMPUTE_INTERVAL = 1.5
local PATH_AGENT_RADIUS = 3.5
local PATH_AGENT_HEIGHT = 6
local LUNGE_DISTANCE = 2.5
local LUNGE_DURATION = 0.18
local DEATH_FADE_DELAY = 4
local HIT_FLASH_DURATION = 0.12
local WOLF_BASE_COUNT = 3
local WOLF_DAY_SCALING = 3
local ALPHA_START_DAY = 3
-- Wolves spawn at level 2+ distance
local WOLF_MIN_SPAWN_DIST = 150
local WOLF_MAX_SPAWN_DIST = 250
local PERSISTENT_TARGET_COUNTS = { Bunny = 8, Bear = 2, WolfModel = 3 }
local RESPAWN_CHECK_INTERVAL = 10

-- | State Management | --
local worldService: any = nil
local timeService: any = nil
local spawnService: any = nil
local inventoryService: any = nil
local playerDataService: any = nil
local playerLifeService: any = nil
local runStateService: any = nil
local worldProgressionService: any = nil
local activeNpcs: { [Model]: any } = {}
local speciesCounts: { [string]: number } = {}
local lastPhase: string = "Day"
local nightSpawnDone = false
local persistentSpawned = false
local respawnCheckTimer = 0
local treePivots: { CFrame } = {}
local groundBounds: { minX: number, maxX: number, minZ: number, maxZ: number }? = nil
local spawnPersistentPopulation: (() -> ())? = nil

-- // FUNCTIONS // --

-- | Private | --

--[[
    @summary  Collect tree pivots and ground bounds for spawn scattering.
]]
local function collectSpawnArea()
	if not worldService or not worldService:IsForestReady() then
		task.defer(collectSpawnArea)
		return
	end

	local baseMap = worldService:GetBaseMap()
	if not baseMap then
		task.defer(collectSpawnArea)
		return
	end

	treePivots = {}
	groundBounds = worldService:GetGroundBounds()
	for _, descendant in ipairs(baseMap:GetDescendants()) do
		if descendant:IsA("Model") and (descendant.Name == "Tree" or descendant.Name == "bigtree" or descendant.Name == "GiantTree") then
			table.insert(treePivots, descendant:GetPivot())
		end
	end

end

--[[
    @summary  Pick a random ground position between MIN_SPAWN_DIST and
              MAX_SPAWN_DIST studs from the campfire.
    @returns  Vector3?
]]
local function pickSpawnPosition(minDist: number?, maxDist: number?): Vector3?
	if not worldService then
		return nil
	end
	local campfireCFrame = worldService:GetCampfireCFrame()
	if not campfireCFrame then
		return nil
	end
	local campfirePos = campfireCFrame.Position

	local distMin = minDist or MIN_SPAWN_DIST
	local requestedMax = maxDist or MAX_SPAWN_DIST
	local accessibleMax = if worldProgressionService then worldProgressionService:GetAccessRadius() - 20 else requestedMax
	local distMax = math.max(distMin, math.min(requestedMax, accessibleMax))

	for _ = 1, 12 do
		local angle = math.random() * math.pi * 2
		local dist = distMin + math.random() * (distMax - distMin)
		local candidate = campfirePos + Vector3.new(math.cos(angle) * dist, 0, math.sin(angle) * dist)
		if groundBounds then
			if
				candidate.X >= groundBounds.minX
				and candidate.X <= groundBounds.maxX
				and candidate.Z >= groundBounds.minZ
				and candidate.Z <= groundBounds.maxZ
			then
				return candidate
			end
		else
			return candidate
		end
	end

	if #treePivots > 0 then
		return treePivots[math.random(1, #treePivots)].Position
	end

	return campfirePos + Vector3.new(distMin, 0, 0)
end

--[[
    @summary  Raycast down from a candidate spawn position to find the
              ground CFrame, falling back to a fixed height if nothing
              is hit.
    @param    position  Vector3
    @returns  CFrame
]]
local function groundedCFrame(position: Vector3): CFrame
	local y = worldService and worldService:GetGroundY()
	return CFrame.new(position.X, (y or position.Y) + 3, position.Z)
end

--[[
    @summary  Collect every Motor6D whose second part is a leg or arm,
              tagged with which side it is on for gait phasing.
    @param    model  Model
    @returns  { { motor: Motor6D, originalC0: CFrame, isLeg: boolean, side: string } }
]]
local function collectGaitJoints(model: Model)
	local joints = {}
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("Motor6D") and descendant.Part1 then
			local partName = descendant.Part1.Name
			local lower = partName:lower()
			local isLeg = lower:find("leg") ~= nil
			local isArm = lower:find("arm") ~= nil
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
    @summary  Resolve the R15/R6 default Animate-script walk animation
              id for a rig style, so no custom animation asset is needed.
    @param    rigStyle  "R15" | "R6"
    @returns  string?
]]
local function defaultWalkAnimationId(rigStyle: string): string?
	if rigStyle == "R15" then
		return "rbxassetid://913402848"
	elseif rigStyle == "R6" then
		return "rbxassetid://180426354"
	end
	return nil
end

--[[
    @summary  Resolve the R15/R6 default Animate-script idle animation id.
    @param    rigStyle  "R15" | "R6"
    @returns  string?
]]
local function defaultIdleAnimationId(rigStyle: string): string?
	if rigStyle == "R15" then
		return "rbxassetid://507766388"
	elseif rigStyle == "R6" then
		return "rbxassetid://180435571"
	end
	return nil
end

--[[
    @summary  Load walk/idle/attack AnimationTracks for a record's rig
              style, tolerating a bad asset id without erroring.
    @param    record  table
]]
local function buildAnimationTracks(record)
	local humanoid = record.humanoid
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end
	record.tracks = {}

	local function loadTrack(id: string, looped: boolean, priority: Enum.AnimationPriority?): AnimationTrack?
		local anim = Instance.new("Animation")
		anim.AnimationId = id
		local ok, track = pcall(function()
			return animator:LoadAnimation(anim)
		end)
		if not ok or not track then
			return nil
		end
		track.Looped = looped
		track.Priority = priority or Enum.AnimationPriority.Idle
		return track
	end

	if record.config.RigStyle == "R15" or record.config.RigStyle == "R6" then
		local walkId = defaultWalkAnimationId(record.config.RigStyle)
		local idleId = defaultIdleAnimationId(record.config.RigStyle)
		if walkId then
			record.tracks.Walk = loadTrack(walkId, true)
		end
		if idleId then
			record.tracks.Idle = loadTrack(idleId, true)
		end
	end

	if record.config.BakedAttackAnimName then
		local animInstance = record.model:FindFirstChild(record.config.BakedAttackAnimName, true)
		if animInstance and animInstance:IsA("Animation") then
			record.tracks.Attack = loadTrack(animInstance.AnimationId, false, Enum.AnimationPriority.Action)
		end
	end

	if record.config.RigStyle == "Procedural" then
		record.gaitJoints = collectGaitJoints(record.model)
	end
end

--[[
    @summary  Switch between the Idle and Walk baked tracks for
              R15/R6-rigged NPCs based on current movement.
    @param    record    table
    @param    isMoving  boolean
]]
local function updateBakedLocomotion(record, isMoving: boolean)
	if not record.tracks then
		return
	end
	local walk = record.tracks.Walk
	local idle = record.tracks.Idle
	if isMoving then
		if walk and not walk.IsPlaying then
			walk:Play(0.2)
		end
		if idle and idle.IsPlaying then
			idle:Stop(0.2)
		end
	else
		if walk and walk.IsPlaying then
			walk:Stop(0.2)
		end
		if idle and not idle.IsPlaying then
			idle:Play(0.2)
		end
	end
end

--[[
    @summary  Drive procedural leg/arm swing via Motor6D offsets for
              custom rigs with no baked locomotion animation.
    @param    record    table
    @param    dt        number
    @param    isMoving  boolean
]]
local function applyProceduralGait(record, dt: number, isMoving: boolean)
	if not record.gaitJoints then
		return
	end

	if isMoving then
		local speedFactor = math.clamp(record.humanoid.WalkSpeed / 10, 0.6, 2.6)
		record.gaitPhase = (record.gaitPhase or 0) + dt * 8 * speedFactor
	end

	for _, joint in ipairs(record.gaitJoints) do
		local target: CFrame
		if isMoving then
			local phaseOffset = if joint.side == "Right" then math.pi else 0
			local amplitude = if joint.isLeg then GAIT_AMPLITUDE else GAIT_ARM_AMPLITUDE
			local swing = math.sin(record.gaitPhase + phaseOffset) * amplitude
			target = joint.originalC0 * CFrame.Angles(swing, 0, 0)
		else
			target = joint.originalC0
		end
		joint.motor.C0 = joint.motor.C0:Lerp(target, math.clamp(dt * IDLE_LERP_SPEED, 0, 1))
	end
end

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

local function scaledCount(baseCount: number): number
	return RunConfig.ScaleEnemyCount(baseCount, runStateService and runStateService:GetInitialPartySize() or 1)
end

--[[
    @summary  Roll loot from a species' loot table and grant it to the killer.
    @param    player  Player
    @param    loot    { NpcConfig.LootEntry }
]]
local function grantLoot(record, player: Player)
	if not inventoryService then
		return
	end
	for _, entry in ipairs(record.config.Loot or {}) do
		if math.random() <= entry.Chance then
			local amount = math.random(entry.Min, entry.Max)
			if entry.Resource == "RawMeat" or entry.Resource == "CultistGem" then
				-- Spawn as a physical world drop so the player can pick it up.
				for _ = 1, amount do
					local drop = inventoryService:BuildDropModel(entry.Resource)
					if drop then
						local pos = record.model:GetPivot().Position
						local offset = Vector3.new((math.random() - 0.5) * 5, 2, (math.random() - 0.5) * 5)
						drop:PivotTo(CFrame.new(pos + offset))
						drop.Parent = worldService and worldService:GetBaseMap() or record.model.Parent
						Debris:AddItem(drop, 300)
					end
				end
			else
				inventoryService:AddResource(player, entry.Resource, amount)
			end
		end
	end
end

--[[
    @summary  Play a short lunge-forward Tween on the NPC's root part to
              sell a melee attack without a baked swing animation.
    @param    record  table
]]
local function playLunge(record)
	local rootPart = record.rootPart
	if not rootPart then
		return
	end
	local originalCFrame = rootPart.CFrame
	local lungeCFrame = originalCFrame * CFrame.new(0, 0, -LUNGE_DISTANCE)
	local tweenOut = TweenService:Create(rootPart, TweenInfo.new(LUNGE_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		CFrame = lungeCFrame,
	})
	tweenOut.Completed:Once(function()
		TweenService:Create(rootPart, TweenInfo.new(LUNGE_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			CFrame = originalCFrame,
		}):Play()
	end)
	tweenOut:Play()
end

--[[
    @summary  Flash an NPC's parts red briefly to give hit feedback.
    @param    model  Model
]]
local function flashHit(model: Model)
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") then
			local highlight = Instance.new("Highlight")
			highlight.FillColor = Color3.fromRGB(255, 40, 40)
			highlight.FillTransparency = 0.4
			highlight.OutlineTransparency = 1
			highlight.Adornee = model
			highlight.Parent = model
			Debris:AddItem(highlight, HIT_FLASH_DURATION)
			break
		end
	end
end

--[[
    @summary  Remove a record from all tracking tables and destroy its model.
    @param    record  table
]]
local function cleanupRecord(record)
	activeNpcs[record.model] = nil
	speciesCounts[record.key] = math.max((speciesCounts[record.key] or 1) - 1, 0)
	CombatTargetRegistry.Unregister(record.model)
	if record.model.Parent then
		record.model:Destroy()
	end
end

--[[
    @summary  Kill an NPC: grant loot, bump stats, ragdoll, then remove
              it after a short delay so the death reads clearly.
    @param    record    table
    @param    attacker  Player?
]]
local function killNpc(record, attacker: Player?)
	if record.isDead then
		return
	end
	record.isDead = true

	if attacker then
		grantLoot(record, attacker)
		if record.config.StatsKey and playerDataService then
			playerDataService:UpdateData(attacker, function(data)
				data.Stats[record.config.StatsKey] = (data.Stats[record.config.StatsKey] or 0) + 1
			end)
		end
	end

	broadcastToAll(AnimalAIService.Client.NpcDied, record.model, record.model:GetPivot().Position, record.key)
	AnimalAIService.NpcDiedServer:Fire(record.model, record.key, attacker)

	if record.humanoid then
		record.humanoid.WalkSpeed = 0
		pcall(function()
			record.humanoid:SetStateEnabled(Enum.HumanoidStateType.Physics, true)
		end)
		record.humanoid.Health = 0
	end

	CombatTargetRegistry.Unregister(record.model)
	Debris:AddItem(record.model, DEATH_FADE_DELAY)
	task.delay(DEATH_FADE_DELAY, function()
		activeNpcs[record.model] = nil
		speciesCounts[record.key] = math.max((speciesCounts[record.key] or 1) - 1, 0)
	end)
end

--[[
    @summary  Apply combat damage to a spawned NPC, killing it if its
              health reaches zero.
    @param    record    table
    @param    amount    number
    @param    attacker  Player?
    @returns  boolean, boolean  -- killed, immune
]]
local function applyDamageToRecord(record, amount: number, attacker: Player?): (boolean, boolean)
	if record.isDead then
		return false, false
	end
	if record.config.MaxHealth <= 0 then
		flashHit(record.model)
		return false, true
	end
	record.health -= amount
	record.humanoid.Health = math.max(record.health, 0)
	flashHit(record.model)

	local maxHealth = record.maxHealth or record.config.MaxHealth
	local healthRatio = math.clamp(record.health / math.max(maxHealth, 1), 0, 1)
	local position = record.rootPart.Position
	broadcastToAll(AnimalAIService.Client.NpcHealthChanged, record.model, healthRatio, amount, position, record.key)

	if record.health <= 0 then
		killNpc(record, attacker)
		return true, false
	end
	return false, false
end

--[[
    @summary  Return the nearest in-game player within range of a position.
    @param    position  Vector3
    @param    range     number
    @returns  Player?, number?  -- player and distance
]]
local function findNearestPlayer(position: Vector3, range: number): (Player?, number?)
	local nearest: Player? = nil
	local nearestDist: number? = nil
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
		local dist = (rootPart.Position - position).Magnitude
		if dist <= range and (not nearestDist or dist < nearestDist) then
			nearest = player
			nearestDist = dist
		end
	end
	return nearest, nearestDist
end

--[[
    @summary  Attempt to compute a PathfindingService route to a
              destination, falling back to a direct heading on failure.
    @param    record       table
    @param    destination  Vector3
]]
local function recomputePath(record, destination: Vector3)
	record.lastPathRecompute = os.clock()
	record.waypoints = nil
	record.waypointIndex = 1

	local path = PathfindingService:CreatePath({
		AgentRadius = PATH_AGENT_RADIUS,
		AgentHeight = PATH_AGENT_HEIGHT,
		AgentCanJump = false,
	})

	local ok = pcall(function()
		path:ComputeAsync(record.rootPart.Position, destination)
	end)

	if ok and path.Status == Enum.PathStatus.Success then
		record.waypoints = path:GetWaypoints()
	end
end

--[[
    @summary  Move an NPC toward a destination, following a computed
              path when available and re-planning periodically.
    @param    record       table
    @param    destination  Vector3
]]
local function moveTowards(record, destination: Vector3)
	local now = os.clock()
	if not record.waypoints or (now - (record.lastPathRecompute or 0)) >= PATH_RECOMPUTE_INTERVAL then
		recomputePath(record, destination)
	end

	if record.waypoints and record.waypoints[record.waypointIndex] then
		local waypoint = record.waypoints[record.waypointIndex]
		if (record.rootPart.Position - waypoint.Position).Magnitude < 4 then
			record.waypointIndex += 1
		end
		local target = record.waypoints[record.waypointIndex]
		record.humanoid:MoveTo(if target then target.Position else destination)
	else
		record.humanoid:MoveTo(destination)
	end
end

--[[
    @summary  Decide the next state (Idle/Patrol/Chase/Attack/Flee) for
              an NPC based on its tier, config, and nearby players.
    @param    record  table
]]
local function updateState(record)
	local config = record.config

	-- Raid cultists always chase the nearest player regardless of distance.
	if record.isRaidCultist then
		local position = record.rootPart.Position
		-- Use a very large range so we always find the nearest player.
		local nearestPlayer, distance = findNearestPlayer(position, 99999)
		if nearestPlayer and distance then
			-- Validate current target is still alive.
			if record.target then
				local character = (record.target :: Player).Character
				local rootPart = character and character:FindFirstChild("HumanoidRootPart")
				if not rootPart or not spawnService or not spawnService:IsPlayerSpawned(record.target) or
					(playerLifeService and not playerLifeService:IsAlive(record.target)) then
					record.target = nearestPlayer
				end
			else
				record.target = nearestPlayer
			end
			record.state = if distance <= config.AttackRange then "Attack" else "Chase"
		else
			-- No players found at all; patrol toward campfire area.
			record.state = "Patrol"
		end
		return
	end

	if config.AggroRange <= 0 then
		record.state = "Idle"
		record.target = nil
		return
	end

	local position = record.rootPart.Position
	local nearestPlayer, distance = findNearestPlayer(position, config.AggroRange)

	if config.Tier == "Passive" then
		if nearestPlayer and distance then
			if record.state ~= "Flee" then
				record.state = "Flee"
				record.target = nearestPlayer
				record.fleeStartleUntil = os.clock() + 0.2
				record.fleeZigzagPhase = 0
			end
		elseif record.target and record.state == "Flee" then
			local character = (record.target :: Player).Character
			local rootPart = character and character:FindFirstChild("HumanoidRootPart")
			if not rootPart or (record.rootPart.Position - rootPart.Position).Magnitude > config.LoseAggroRange then
				record.state = "Patrol"
				record.target = nil
			end
		else
			record.state = "Patrol"
		end
		return
	end

	-- Predator / Solitary
	if config.Tier == "Solitary" and config.TerritoryRadius then
		local distFromSpawn = (position - record.spawnPosition).Magnitude
		if record.state == "Chase" and distFromSpawn > config.TerritoryRadius then
			record.state = "Patrol"
			record.target = nil
			return
		end
	end

	if record.target then
		local character = (record.target :: Player).Character
		local rootPart = character and character:FindFirstChild("HumanoidRootPart")
		if not rootPart or not spawnService or not spawnService:IsPlayerSpawned(record.target) then
			record.state = "Patrol"
			record.target = nil
			return
		end
		local dist = (position - rootPart.Position).Magnitude
		if dist > config.LoseAggroRange then
			record.state = "Patrol"
			record.target = nil
			return
		end
		record.state = if dist <= config.AttackRange then "Attack" else "Chase"
		return
	end

	if nearestPlayer then
		if config.Tier == "Solitary" and config.TerritoryRadius then
			if (record.spawnPosition - position).Magnitude > config.TerritoryRadius then
				return
			end
		end
		record.target = nearestPlayer
		record.state = "Chase"
	else
		record.state = "Patrol"
	end
end

--[[
    @summary  Execute movement/attack behavior for the record's current state.
    @param    record  table
    @param    dt      number
]]
local function runStateBehavior(record, dt: number)
	local config = record.config
	local isMoving = false

	if record.state == "Idle" then
		record.humanoid.WalkSpeed = 0
	elseif record.state == "Patrol" then
		if record.patrolPauseUntil and os.clock() < record.patrolPauseUntil then
			record.humanoid.WalkSpeed = 0
		else
			record.patrolPauseUntil = nil
			record.humanoid.WalkSpeed = config.WalkSpeed
			if not record.patrolTarget or (record.rootPart.Position - record.patrolTarget).Magnitude < 4 then
				if config.Tier == "Passive" then
					record.patrolPauseUntil = os.clock() + math.random(2, 4)
				end
				local offset = Vector3.new((math.random() - 0.5) * 30, 0, (math.random() - 0.5) * 30)
				record.patrolTarget = record.spawnPosition + offset
			end
			record.humanoid:MoveTo(record.patrolTarget)
			isMoving = true
		end
	elseif record.state == "Chase" then
		record.humanoid.WalkSpeed = config.RunSpeed
		local character = (record.target :: Player).Character
		local rootPart = character and character:FindFirstChild("HumanoidRootPart")
		if rootPart then
			moveTowards(record, rootPart.Position)
			isMoving = true
		end
	elseif record.state == "Flee" then
		local now = os.clock()
		if record.fleeStartleUntil and now < record.fleeStartleUntil then
			record.humanoid.WalkSpeed = 0
			isMoving = false
		else
			record.fleeStartleUntil = nil
			record.humanoid.WalkSpeed = config.RunSpeed * (config.FleeSpeedMultiplier or 1.0)
			local character = record.target and (record.target :: Player).Character
			local rootPart = character and character:FindFirstChild("HumanoidRootPart")
			if rootPart then
				local away = (record.rootPart.Position - rootPart.Position)
				if away.Magnitude > 0.1 then
					local awayUnit = away.Unit
					local perp = Vector3.new(-awayUnit.Z, 0, awayUnit.X)
					record.fleeZigzagPhase = (record.fleeZigzagPhase or 0) + dt * 3
					local zigzag = math.sin(record.fleeZigzagPhase) * 0.35
					local fleeDir = (awayUnit + perp * zigzag).Unit
					local fleeTarget = record.rootPart.Position + fleeDir * 15
					record.humanoid:MoveTo(fleeTarget)
					isMoving = true
				end
			end
		end
	elseif record.state == "Attack" then
		record.humanoid.WalkSpeed = 0
		local now = os.clock()
		if not record.lastAttackTime or (now - record.lastAttackTime) >= config.AttackCooldown then
			record.lastAttackTime = now
			local targetPlayer = record.target :: Player?
			if targetPlayer and playerLifeService and playerLifeService:IsAlive(targetPlayer) then
				playLunge(record)
				if record.tracks and record.tracks.Attack then
					record.tracks.Attack:Play()
				end
				playerLifeService:ApplyDamage(targetPlayer, config.AttackDamage, record.key)
				broadcastToAll(AnimalAIService.Client.NpcAttacked, record.rootPart.Position)
			end
		end
	end

	if config.RigStyle == "R15" or config.RigStyle == "R6" then
		updateBakedLocomotion(record, isMoving)
	elseif config.RigStyle == "Procedural" then
		applyProceduralGait(record, dt, isMoving)
	end
end

--[[
    @summary  Per-heartbeat driver for one NPC record.
    @param    record  table
    @param    dt      number
]]
local function tickRecord(record, dt: number)
	if record.isDead then
		return
	end
	if not record.model.Parent or not record.humanoid or record.humanoid.Health <= 0 then
		cleanupRecord(record)
		return
	end

	local now = os.clock()
	if now >= (record.nextDecisionTime or 0) then
		record.nextDecisionTime = now + DECISION_INTERVAL
		updateState(record)
	end

	runStateBehavior(record, dt)
end

--[[
    @summary  Clone an NPC template, place it, and register it for the
              generic AI tick and combat targeting.
    @param    speciesKey  string          -- key into NpcConfig
    @param    cframe      CFrame          -- spawn CFrame
    @returns  Model?
]]
function AnimalAIService:SpawnNpc(speciesKey: string, cframe: CFrame, options: { isRaidCultist: boolean? }?): Model?
	local config = NpcConfig[speciesKey]
	if not config then
		warn("[AnimalAIService] Unknown species key", speciesKey)
		return nil
	end

	local template = NPC_SOURCE_PATH and NPC_SOURCE_PATH:FindFirstChild(config.ModelName)
	if not template or not template:IsA("Model") then
		warn("[AnimalAIService] Missing NPC template", config.ModelName)
		return nil
	end

	local model = template:Clone()
	model:PivotTo(cframe)

	local humanoid = model:FindFirstChildOfClass("Humanoid") or model:FindFirstChild("NPC")
	local rootPart = model:FindFirstChild("HumanoidRootPart") or model:FindFirstChild("HRP")
	if not humanoid or not humanoid:IsA("Humanoid") or not rootPart then
		warn("[AnimalAIService] Template", config.ModelName, "missing Humanoid/root part")
		model:Destroy()
		return nil
	end

	local scaledHealth = if config.MaxHealth > 0
		then RunConfig.ScaleEnemyHealth(config.MaxHealth, runStateService and runStateService:GetInitialPartySize() or 1)
		else 0
	humanoid.MaxHealth = math.max(scaledHealth, 1)
	humanoid.Health = humanoid.MaxHealth
	humanoid.WalkSpeed = config.WalkSpeed

	local isRaidCultist = options and options.isRaidCultist or false

	local record = {
		model = model,
		humanoid = humanoid,
		rootPart = rootPart,
		config = config,
		key = speciesKey,
		state = "Patrol",
		target = nil,
		health = scaledHealth,
		maxHealth = scaledHealth,
		spawnPosition = cframe.Position,
		gaitPhase = 0,
		isDead = false,
		isRaidCultist = isRaidCultist,
	}

	local doomed: { Instance } = {}
	for _, desc in ipairs(model:GetDescendants()) do
		if desc:IsA("BaseScript") or desc:IsA("ModuleScript")
			or desc:IsA("PackageLink") or desc:IsA("TextureConfiguration")
		then
			table.insert(doomed, desc)
		end
	end
	for _, inst in ipairs(doomed) do
		inst:Destroy()
	end
	model.Parent = workspace

	buildAnimationTracks(record)
	activeNpcs[model] = record
	speciesCounts[speciesKey] = (speciesCounts[speciesKey] or 0) + 1

	CombatTargetRegistry.Register(model, {
		ApplyDamage = function(amount: number, attacker: Player?)
			return applyDamageToRecord(record, amount, attacker)
		end,
		IsImmune = config.MaxHealth <= 0,
	})

	return model
end

--[[
    @summary  Destroy every currently-spawned NPC of a given species.
    @param    speciesKey  string
]]
function AnimalAIService:DespawnAllOfSpecies(speciesKey: string)
	for model, record in pairs(activeNpcs) do
		if record.key == speciesKey and model:GetAttribute("GuardCaveId") == nil then
			cleanupRecord(record)
		end
	end
end

--[[
    @summary  Destroy every generic NPC without scheduling replacements.
]]
function AnimalAIService:CleanupAll()
	for _, record in pairs(activeNpcs) do
		cleanupRecord(record)
	end
	activeNpcs = {}
	speciesCounts = {}
	persistentSpawned = false
	respawnCheckTimer = 0
end

--[[
    @summary  Destroy all generic NPCs and start a fresh run population.
]]
function AnimalAIService:ResetForRun()
	self:CleanupAll()
	lastPhase = "Day"
	nightSpawnDone = false

	local capturedRunId = runStateService and runStateService:GetRunId()
	task.delay(1, function()
		if runStateService and runStateService:IsCurrentRun(capturedRunId) and spawnPersistentPopulation then
			spawnPersistentPopulation()
		end
	end)
end

--[[
    @summary  Spawn a wolf pack (regular or alpha-led) around a random
              point at spawn distance from the campfire.
    @param    dayNumber  number
]]
local function spawnWolfPack(dayNumber: number)
	local center = pickSpawnPosition(WOLF_MIN_SPAWN_DIST, WOLF_MAX_SPAWN_DIST)
	if not center then
		return
	end

	local packSize = scaledCount(math.clamp(WOLF_BASE_COUNT + math.floor(dayNumber / WOLF_DAY_SCALING), WOLF_BASE_COUNT, 8))
	for i = 1, packSize do
		local offset = Vector3.new((math.random() - 0.5) * 12, 0, (math.random() - 0.5) * 12)
		local cframe = groundedCFrame(center + offset)
		AnimalAIService:SpawnNpc("WolfModel", cframe)
	end

	if dayNumber >= ALPHA_START_DAY then
		local alphaCount = if dayNumber >= ALPHA_START_DAY * 2 then 2 else 1
		for i = 1, alphaCount do
			local offset = Vector3.new((math.random() - 0.5) * 12, 0, (math.random() - 0.5) * 12)
			local cframe = groundedCFrame(center + offset)
			AnimalAIService:SpawnNpc("AlphaWolfModel", cframe)
		end
	end
end

--[[
    @summary  Spawn the always-present Bunny/Bear population once,
              at server start (they persist across the whole run).
]]
spawnPersistentPopulation = function()
	if persistentSpawned then
		return
	end
	persistentSpawned = true

	-- Determine current campfire level from access radius
	local currentLevel = 1
	if worldProgressionService then
		currentLevel = WorldProgressionConfig.GetUnlockLevelForDistance(worldProgressionService:GetAccessRadius())
	end

	-- Bunnies: spawn at all levels, far from campfire, scattered
	for _ = 1, scaledCount(PERSISTENT_TARGET_COUNTS.Bunny) do
		local position = pickSpawnPosition(BUNNY_MIN_SPAWN_DIST, BUNNY_MAX_SPAWN_DIST)
		if position then
			AnimalAIService:SpawnNpc("Bunny", groundedCFrame(position))
		end
	end

	-- Wolves: only spawn at level 2+
	if currentLevel >= 2 then
		for _ = 1, scaledCount(PERSISTENT_TARGET_COUNTS.WolfModel) do
			local wolfPosition = pickSpawnPosition(WOLF_MIN_SPAWN_DIST, WOLF_MAX_SPAWN_DIST)
			if wolfPosition then
				AnimalAIService:SpawnNpc("WolfModel", groundedCFrame(wolfPosition))
			end
		end
	end

	-- Bears: only spawn at level 3+
	if currentLevel >= 3 then
		for _ = 1, scaledCount(PERSISTENT_TARGET_COUNTS.Bear) do
			local bearPosition = pickSpawnPosition(BEAR_MIN_SPAWN_DIST, BEAR_MAX_SPAWN_DIST)
			if bearPosition then
				AnimalAIService:SpawnNpc("Bear", groundedCFrame(bearPosition))
			end
		end
	end
end

--[[
    @summary  Respawn a fallen persistent-population NPC once its
              species count drops below the target headcount.
    @param    dt  number
]]
local function checkPersistentRespawn(dt: number)
	respawnCheckTimer += dt
	if respawnCheckTimer < RESPAWN_CHECK_INTERVAL then
		return
	end
	respawnCheckTimer = 0

	-- Determine current campfire level
	local currentLevel = 1
	if worldProgressionService then
		currentLevel = WorldProgressionConfig.GetUnlockLevelForDistance(worldProgressionService:GetAccessRadius())
	end

	for speciesKey, targetCount in pairs(PERSISTENT_TARGET_COUNTS) do
		-- Skip wolves if level < 2, skip bears if level < 3
		if speciesKey == "WolfModel" and currentLevel < 2 then
			continue
		end
		if speciesKey == "Bear" and currentLevel < 3 then
			continue
		end
		local current = speciesCounts[speciesKey] or 0
		if current < scaledCount(targetCount) then
			local position
			if speciesKey == "Bear" then
				position = pickSpawnPosition(BEAR_MIN_SPAWN_DIST, BEAR_MAX_SPAWN_DIST)
			elseif speciesKey == "WolfModel" then
				position = pickSpawnPosition(WOLF_MIN_SPAWN_DIST, WOLF_MAX_SPAWN_DIST)
			elseif speciesKey == "Bunny" then
				position = pickSpawnPosition(BUNNY_MIN_SPAWN_DIST, BUNNY_MAX_SPAWN_DIST)
			else
				position = pickSpawnPosition()
			end
			if position then
				AnimalAIService:SpawnNpc(speciesKey, groundedCFrame(position))
			end
		end
	end
end

--[[
    @summary  Watch for day/night transitions and spawn/despawn the
              night predator population accordingly.
]]
local function onHeartbeat(dt: number)
	if timeService and timeService:IsRunning() then
		local phase = timeService:GetCurrentPhase()
		if phase ~= lastPhase then
			lastPhase = phase
			if phase == "Night" and not nightSpawnDone then
				nightSpawnDone = true
				spawnWolfPack(timeService:GetDayNumber())
			elseif phase == "Day" then
				nightSpawnDone = false
			end
		end
	end

	if persistentSpawned then
		checkPersistentRespawn(dt)
	end

	for _, record in pairs(activeNpcs) do
		tickRecord(record, dt)
	end
end

-- // INITIALIZATION // --

function AnimalAIService:KnitStart()
	if not ServerRole.IsGameServer() then return end
	worldService = Knit.GetService("WorldService")
	timeService = Knit.GetService("TimeService")
	spawnService = Knit.GetService("SpawnService")
	inventoryService = Knit.GetService("InventoryService")
	playerDataService = Knit.GetService("PlayerDataService")
	playerLifeService = Knit.GetService("PlayerLifeService")
	runStateService = Knit.GetService("RunStateService")
	worldProgressionService = Knit.GetService("WorldProgressionService")
	local campfireService = Knit.GetService("CampfireService")

	collectSpawnArea()
	runStateService.RunCleaned:Connect(function()
		AnimalAIService:CleanupAll()
	end)

	-- When campfire levels up, spawn newly-unlocked animals
	if campfireService and campfireService.LevelChangedServer then
		campfireService.LevelChangedServer:Connect(function(level: number)
			if not persistentSpawned then
				return
			end
			-- Level 2: spawn wolves
			if level >= 2 then
				local currentWolves = speciesCounts["WolfModel"] or 0
				local needed = PERSISTENT_TARGET_COUNTS.WolfModel - currentWolves
				for _ = 1, math.max(0, needed) do
					local pos = pickSpawnPosition(WOLF_MIN_SPAWN_DIST, WOLF_MAX_SPAWN_DIST)
					if pos then
						AnimalAIService:SpawnNpc("WolfModel", groundedCFrame(pos))
					end
				end
			end
			-- Level 3: spawn bears
			if level >= 3 then
				local currentBears = speciesCounts["Bear"] or 0
				local needed = PERSISTENT_TARGET_COUNTS.Bear - currentBears
				for _ = 1, math.max(0, needed) do
					local pos = pickSpawnPosition(BEAR_MIN_SPAWN_DIST, BEAR_MAX_SPAWN_DIST)
					if pos then
						AnimalAIService:SpawnNpc("Bear", groundedCFrame(pos))
					end
				end
			end
		end)
	end

	RunService.Heartbeat:Connect(onHeartbeat)

end

return AnimalAIService
