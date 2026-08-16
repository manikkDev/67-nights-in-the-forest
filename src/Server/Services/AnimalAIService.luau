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
local NpcConfig = require(ReplicatedStorage.Shared.NpcConfig)
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

-- | Configuration | --
local NPC_SOURCE_PATH = ServerStorage.Assets["Assets Npcs"]
local DECISION_INTERVAL = 0.25
local MIN_SPAWN_DIST = 25
local MAX_SPAWN_DIST = 90
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
local PERSISTENT_TARGET_COUNTS = { Bunny = 4, Bear = 1 }
local RESPAWN_CHECK_INTERVAL = 10

-- | State Management | --
local worldService: any = nil
local timeService: any = nil
local spawnService: any = nil
local inventoryService: any = nil
local playerDataService: any = nil
local activeNpcs: { [Model]: any } = {}
local speciesCounts: { [string]: number } = {}
local lastPhase: string = "Day"
local nightSpawnDone = false
local persistentSpawned = false
local respawnCheckTimer = 0
local treePivots: { CFrame } = {}
local groundBounds: { minX: number, maxX: number, minZ: number, maxZ: number }? = nil

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
	for _, descendant in ipairs(baseMap:GetDescendants()) do
		if descendant:IsA("Model") and (descendant.Name == "Tree" or descendant.Name == "bigtree") then
			table.insert(treePivots, descendant:GetPivot())
		elseif descendant:IsA("BasePart") and descendant.Name == "Земля" then
			local halfSize = descendant.Size / 2
			groundBounds = {
				minX = descendant.Position.X - halfSize.X,
				maxX = descendant.Position.X + halfSize.X,
				minZ = descendant.Position.Z - halfSize.Z,
				maxZ = descendant.Position.Z + halfSize.Z,
			}
		end
	end

	print("[AnimalAIService] Collected", #treePivots, "tree pivots for spawn scatter")
end

--[[
    @summary  Pick a random ground position between MIN_SPAWN_DIST and
              MAX_SPAWN_DIST studs from the campfire.
    @returns  Vector3?
]]
local function pickSpawnPosition(): Vector3?
	if not worldService then
		return nil
	end
	local campfireCFrame = worldService:GetCampfireCFrame()
	if not campfireCFrame then
		return nil
	end
	local campfirePos = campfireCFrame.Position

	for _ = 1, 12 do
		local angle = math.random() * math.pi * 2
		local dist = MIN_SPAWN_DIST + math.random() * (MAX_SPAWN_DIST - MIN_SPAWN_DIST)
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

	return campfirePos + Vector3.new(MIN_SPAWN_DIST, 0, 0)
end

--[[
    @summary  Raycast down from a candidate spawn position to find the
              ground CFrame, falling back to a fixed height if nothing
              is hit.
    @param    position  Vector3
    @returns  CFrame
]]
local function groundedCFrame(position: Vector3): CFrame
	local origin = position + Vector3.new(0, 200, 0)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local result = workspace:Raycast(origin, Vector3.new(0, -400, 0), params)
	if result then
		return CFrame.new(result.Position + Vector3.new(0, 3, 0))
	end
	return CFrame.new(position + Vector3.new(0, 5, 0))
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
	for _, player in ipairs(Players:GetPlayers()) do
		signal:Fire(player, ...)
	end
end

--[[
    @summary  Roll loot from a species' loot table and grant it to the killer.
    @param    player  Player
    @param    loot    { NpcConfig.LootEntry }
]]
local function grantLoot(player: Player, loot: { any })
	if not inventoryService then
		return
	end
	for _, entry in ipairs(loot) do
		if math.random() <= entry.Chance then
			local amount = math.random(entry.Min, entry.Max)
			inventoryService:AddResource(player, entry.Resource, amount)
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
		grantLoot(attacker, record.config.Loot)
		if record.config.StatsKey and playerDataService then
			playerDataService:UpdateData(attacker, function(data)
				data.Stats[record.config.StatsKey] = (data.Stats[record.config.StatsKey] or 0) + 1
			end)
		end
	end

	broadcastToAll(AnimalAIService.Client.NpcDied, record.model, record.model:GetPivot().Position, record.key)

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
	flashHit(record.model)

	local maxHealth = record.config.MaxHealth
	local healthRatio = math.clamp(record.health / maxHealth, 0, 1)
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
	for _, player in ipairs(Players:GetPlayers()) do
		if spawnService and not spawnService:IsPlayerSpawned(player) then
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
				record.fleeStartleUntil = os.clock() + 0.4
				record.fleeZigzagPhase = 0
			end
		elseif record.target and record.state == "Flee" then
			local character = (record.target :: Player).Character
			local rootPart = character and character:FindFirstChild("HumanoidRootPart")
			if not rootPart or (record.rootPart.Position - rootPart.Position).Magnitude > config.LoseAggroRange then
				record.state = "Idle"
				record.target = nil
			end
		else
			record.state = "Idle"
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
		record.humanoid.WalkSpeed = config.WalkSpeed
		if not record.patrolTarget or (record.rootPart.Position - record.patrolTarget).Magnitude < 4 then
			local offset = Vector3.new((math.random() - 0.5) * 30, 0, (math.random() - 0.5) * 30)
			record.patrolTarget = record.spawnPosition + offset
		end
		record.humanoid:MoveTo(record.patrolTarget)
		isMoving = true
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
			record.humanoid.WalkSpeed = config.RunSpeed * (config.FleeSpeedMultiplier or 1.25)
			local character = record.target and (record.target :: Player).Character
			local rootPart = character and character:FindFirstChild("HumanoidRootPart")
			if rootPart then
				local away = (record.rootPart.Position - rootPart.Position)
				if away.Magnitude > 0.1 then
					local awayUnit = away.Unit
					local perp = Vector3.new(-awayUnit.Z, 0, awayUnit.X)
					record.fleeZigzagPhase = (record.fleeZigzagPhase or 0) + dt * 4
					local zigzag = math.sin(record.fleeZigzagPhase) * 0.6
					local fleeDir = (awayUnit + perp * zigzag).Unit
					local fleeTarget = record.rootPart.Position + fleeDir * 25
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
			local character = record.target and (record.target :: Player).Character
			local targetHumanoid = character and character:FindFirstChildOfClass("Humanoid")
			if targetHumanoid then
				playLunge(record)
				if record.tracks and record.tracks.Attack then
					record.tracks.Attack:Play()
				end
				targetHumanoid:TakeDamage(config.AttackDamage)
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
function AnimalAIService:SpawnNpc(speciesKey: string, cframe: CFrame): Model?
	local config = NpcConfig[speciesKey]
	if not config then
		warn("[AnimalAIService] Unknown species key", speciesKey)
		return nil
	end

	local template = NPC_SOURCE_PATH:FindFirstChild(config.ModelName)
	if not template or not template:IsA("Model") then
		warn("[AnimalAIService] Missing NPC template", config.ModelName)
		return nil
	end

	local model = template:Clone()
	model:PivotTo(cframe)
	model.Parent = workspace

	local humanoid = model:FindFirstChildOfClass("Humanoid") or model:FindFirstChild("NPC")
	local rootPart = model:FindFirstChild("HumanoidRootPart") or model:FindFirstChild("HRP")
	if not humanoid or not humanoid:IsA("Humanoid") or not rootPart then
		warn("[AnimalAIService] Template", config.ModelName, "missing Humanoid/root part")
		model:Destroy()
		return nil
	end

	humanoid.MaxHealth = math.max(config.MaxHealth, 1)
	humanoid.Health = humanoid.MaxHealth
	humanoid.WalkSpeed = config.WalkSpeed

	local record = {
		model = model,
		humanoid = humanoid,
		rootPart = rootPart,
		config = config,
		key = speciesKey,
		state = "Patrol",
		target = nil,
		health = config.MaxHealth,
		spawnPosition = cframe.Position,
		gaitPhase = 0,
		isDead = false,
	}

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
		if record.key == speciesKey then
			cleanupRecord(record)
		end
	end
end

--[[
    @summary  Spawn a wolf pack (regular or alpha-led) around a random
              point at spawn distance from the campfire.
    @param    dayNumber  number
]]
local function spawnWolfPack(dayNumber: number)
	local center = pickSpawnPosition()
	if not center then
		return
	end

	local packSize = math.clamp(WOLF_BASE_COUNT + math.floor(dayNumber / WOLF_DAY_SCALING), WOLF_BASE_COUNT, 8)
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
local function spawnPersistentPopulation()
	if persistentSpawned then
		return
	end
	persistentSpawned = true

	for _ = 1, 4 do
		local position = pickSpawnPosition()
		if position then
			AnimalAIService:SpawnNpc("Bunny", groundedCFrame(position))
		end
	end

	local bearPosition = pickSpawnPosition()
	if bearPosition then
		AnimalAIService:SpawnNpc("Bear", groundedCFrame(bearPosition))
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

	for speciesKey, targetCount in pairs(PERSISTENT_TARGET_COUNTS) do
		local current = speciesCounts[speciesKey] or 0
		if current < targetCount then
			local position = pickSpawnPosition()
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
				AnimalAIService:DespawnAllOfSpecies("WolfModel")
				AnimalAIService:DespawnAllOfSpecies("AlphaWolfModel")
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
	worldService = Knit.GetService("WorldService")
	timeService = Knit.GetService("TimeService")
	spawnService = Knit.GetService("SpawnService")
	inventoryService = Knit.GetService("InventoryService")
	playerDataService = Knit.GetService("PlayerDataService")

	collectSpawnArea()
	task.delay(3, spawnPersistentPopulation)

	RunService.Heartbeat:Connect(onHeartbeat)

	print("[AnimalAIService] Initialised — animal AI active")
end

return AnimalAIService
