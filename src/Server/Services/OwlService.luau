--[[
    @file    OwlService.luau
    @author  manik
    @date    2025

    @summary
    Server-authoritative Owl NPC — a neutral, unkillable night stalker
    with a movement-detection minigame, wolf-summoning, and feather drops.

    @description
    The Owl is a unique entity (not part of the generic AnimalAI
    population).  It spawns on randomized nights starting from Day 10,
    lands near a player, and observes.  An on-screen eye icon fills red
    when nearby players move; if it fills completely the Owl screams and
    chases like the Deer (faster, flashlight-stunnable, campfire
    retreat).  If players stand still, the Owl loses interest and flies
    away, dropping a feather.  At dawn it flies away without a feather.
    While the Owl is active, the Deer is suppressed.  The Owl can
    summon wolves to scare players into moving.

    States: Dormant → FlyingIn → Perched → Chasing → Stunned → Retreating → FlyingAway

    @exports
    - OwlService:ApplyFlashlightStun(model, player) -> boolean
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
local CombatTargetRegistry = require(script.Parent.Parent.CombatTargetRegistry)

-- | Objects | --
local OwlService = Knit.CreateService({
	Name = "OwlService",
	Client = {
		OwlActive = Knit.CreateSignal(),
		OwlDetection = Knit.CreateSignal(),
		OwlScream = Knit.CreateSignal(),
		OwlContact = Knit.CreateSignal(),
		OwlStunned = Knit.CreateSignal(),
		OwlRetreated = Knit.CreateSignal(),
	},
})

-- | Configuration | --
local NPC_SOURCE_PATH = ServerStorage.Assets["Assets Npcs"]
local OWL_MODEL_NAME = "Owl"
local DORMANT_HOLDING_POSITION = Vector3.new(0, -500, 0)
local DECISION_INTERVAL = 0.15
local CONTACT_RANGE = 5
local CONTACT_COOLDOWN = 1.0
local PURSUIT_ACCEL_PER_SEC = 0.5
local PURSUIT_MAX_BONUS_SPEED = 18
local BASE_CHASE_SPEED = 20
local BASE_STUN_DURATION = 4
local STUN_DECAY_PER_USE = 0.6
local MIN_STUN_DURATION = 1
local STUN_RESISTANCE_RECOVERY_TIME = 45
local RETREAT_HOLD_TIME = 3

local OWL_START_DAY = 10
local OWL_SPAWN_CHANCE = 0.35
local PERCH_DURATION_MIN = 8
local PERCH_DURATION_MAX = 20
local PERCH_LAND_DISTANCE = 25
local PERCH_LAND_HEIGHT = 60
local FLY_TWEEN_TIME = 2.5
local FLY_AWAY_HEIGHT = 200

local DETECTION_RANGE = 60
local MOVEMENT_THRESHOLD = 2
local DETECTION_FILL_RATE = 0.8
local DETECTION_DECAY_RATE = 0.4
local WOLF_SUMMON_CHANCE = 0.3
local WOLF_SUMMON_DISTANCE = 35

local DEFAULT_R15_WALK_ID = "rbxassetid://913402848"
local DEFAULT_R15_IDLE_ID = "rbxassetid://507766388"

-- | State Management | --
local worldService: any = nil
local timeService: any = nil
local runStateService: any = nil
local campfireService: any = nil
local spawnService: any = nil
local animalAIService: any = nil
local inventoryService: any = nil
local deerService: any = nil
local playerLifeService: any = nil

local owl: any = nil
local lastPhase = ""
local owlActiveTonight = false
local wolfSummoned = false

-- // FUNCTIONS // --

-- | Private | --

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
    @summary  Load default R15 walk/idle AnimationTracks for the Owl.
    @param    data  table (owl state)
]]
local function buildAnimationTracks(data)
	data.tracks = {}
	local humanoid = data.humanoid
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

	data.tracks.Walk = loadTrack(DEFAULT_R15_WALK_ID, true)
	data.tracks.Idle = loadTrack(DEFAULT_R15_IDLE_ID, true)
end

--[[
    @summary  Stop every currently-playing track on the Owl.
    @param    data  table
]]
local function stopAllTracks(data)
	for _, track in pairs(data.tracks) do
		if track.IsPlaying then
			track:Stop(0.15)
		end
	end
end

--[[
    @summary  Play a named track if it exists.
    @param    data  table
    @param    name  string
]]
local function playTrack(data, name: string)
	local track = data.tracks[name]
	if track and not track.IsPlaying then
		stopAllTracks(data)
		track:Play(0.15)
	end
end

--[[
    @summary  Collect arm Motor6Ds for procedural wing flap.
    @param    model  Model
    @returns  { { motor: Motor6D, originalC0: CFrame, side: string } }
]]
local function collectWingJoints(model: Model)
	local joints = {}
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("Motor6D") and descendant.Part1 then
			local partName = descendant.Part1.Name
			local lower = partName:lower()
			if lower:find("arm") or lower:find("hand") then
				local side = if lower:find("left") or lower:find("%.l") then "Left" else "Right"
				table.insert(joints, {
					motor = descendant,
					originalC0 = descendant.C0,
					side = side,
				})
			end
		end
	end
	return joints
end

--[[
    @summary  Animate wing flaps procedurally via arm Motor6D offsets.
    @param    data     table
    @param    speed    number  -- flap speed multiplier
    @param    dt       number  -- delta time
]]
local function updateWingFlap(data, speed: number, dt: number)
	data.flapTime = (data.flapTime or 0) + dt * speed
	local angle = math.sin(data.flapTime * 6) * math.rad(35)
	for _, joint in ipairs(data.wingJoints) do
		local base = joint.originalC0
		local rot = if joint.side == "Left"
			then CFrame.Angles(0, 0, angle)
			else CFrame.Angles(0, 0, -angle)
		joint.motor.C0 = base * rot
	end
end

--[[
    @summary  Spawn the Owl model into the world at the dormant position.
]]
local function spawnOwl()
	if owl then
		return
	end

	local template = NPC_SOURCE_PATH:FindFirstChild(OWL_MODEL_NAME)
	if not template or not template:IsA("Model") then
		warn("[OwlService] Missing Owl template in", NPC_SOURCE_PATH:GetFullName())
		return
	end

	local model = template:Clone()
	model.Parent = workspace
	model:PivotTo(CFrame.new(DORMANT_HOLDING_POSITION))

	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local rootPart = model:FindFirstChild("HumanoidRootPart")
	if not humanoid or not rootPart then
		warn("[OwlService] Owl template missing Humanoid or HumanoidRootPart")
		model:Destroy()
		return
	end

	owl = {
		model = model,
		humanoid = humanoid,
		rootPart = rootPart,
		state = "Dormant",
		target = nil,
		detectionMeter = 0,
		perchUntil = 0,
		lastContactTime = 0,
		consecutiveStuns = 0,
		lastStunTime = 0,
		stunUntil = 0,
		retreatUntil = 0,
		nextDecisionTime = 0,
		pursuitStartTime = nil,
		flapTime = 0,
		wingJoints = collectWingJoints(model),
		flyHeartbeat = nil,
	}

	buildAnimationTracks(owl)

	CombatTargetRegistry.Register(model, {
		ApplyDamage = function()
			return false, true
		end,
		IsImmune = true,
	})

end

--[[
    @summary  Pick a landing position near a random player, not near campfire.
    @returns  Vector3?
]]
local function pickLandingPosition(): Vector3?
	local players = runStateService:GetMembers()
	local valid = {}
	for _, player in ipairs(players) do
		if not runStateService:IsActive() or not runStateService:IsMember(player) then
			continue
		end
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
		table.insert(valid, rootPart.Position)
	end

	if #valid == 0 then
		return nil
	end

	local chosen = valid[math.random(1, #valid)]
	local angle = math.random() * math.pi * 2
	local offset = Vector3.new(math.cos(angle) * PERCH_LAND_DISTANCE, 0, math.sin(angle) * PERCH_LAND_DISTANCE)
	return chosen + offset
end

--[[
    @summary  Tween the Owl model from its current position to a target CFrame.
    @param    targetCFrame  CFrame
    @param    duration      number
    @param    callback      function?  -- called on completion
]]
local function flyTo(targetCFrame: CFrame, duration: number, callback: (() -> ())?)
	if not owl or not owl.rootPart then
		return
	end

	-- Clean up any previous flight
	if owl.flyHeartbeat then
		owl.flyHeartbeat:Disconnect()
		owl.flyHeartbeat = nil
	end

	owl.humanoid.WalkSpeed = 0
	stopAllTracks(owl)

	local startCFrame = owl.model:GetPivot()
	local startTime = os.clock()

	-- Anchor the rootPart during flight so physics doesn't fight the tween
	owl.rootPart.Anchored = true

	local function cleanup()
		if owl then
			owl.rootPart.Anchored = false
		end
	end

	owl.flyHeartbeat = RunService.Heartbeat:Connect(function()
		if not owl or not owl.flyHeartbeat then
			return
		end
		local elapsed = os.clock() - startTime
		local alpha = math.clamp(elapsed / duration, 0, 1)
		local eased = alpha * alpha * (3 - 2 * alpha)
		local pos = startCFrame.Position:Lerp(targetCFrame.Position, eased)
		local rot = startCFrame.Rotation:Lerp(targetCFrame.Rotation, eased)
		owl.model:PivotTo(CFrame.fromMatrix(pos, rot.XVector, rot.YVector, rot.ZVector))
		updateWingFlap(owl, 3, 1 / 60)
		if alpha >= 1 then
			owl.flyHeartbeat:Disconnect()
			owl.flyHeartbeat = nil
			owl.model:PivotTo(targetCFrame)
			cleanup()
			if callback then
				callback()
			end
		end
	end)
end

--[[
    @summary  Transition to FlyingIn — tween from above to a landing spot.
]]
local function enterFlyingIn()
	if not owl then
		return
	end
	owl.state = "FlyingIn"
	wolfSummoned = false

	local landingPos = pickLandingPosition()
	if not landingPos then
		landingPos = (worldService and worldService:GetCampfireCFrame() or CFrame.new()).Position
			+ Vector3.new(50, 0, 50)
	end

	-- Start from above the landing position
	local startPos = landingPos + Vector3.new(0, PERCH_LAND_HEIGHT, 0)
	owl.model:PivotTo(CFrame.new(startPos))

	local targetCFrame = CFrame.new(landingPos + Vector3.new(0, 3, 0), Vector3.new(landingPos.X, landingPos.Y, landingPos.Z - 1))

	flyTo(targetCFrame, FLY_TWEEN_TIME, function()
		if owl and owl.state == "FlyingIn" then
			owl.state = "Perched"
			owl.detectionMeter = 0
			owl.perchUntil = os.clock() + math.random(PERCH_DURATION_MIN, PERCH_DURATION_MAX)
			playTrack(owl, "Idle")
		end
	end)
end

--[[
    @summary  Transition to FlyingAway — tween upward and go dormant.
    @param    dropFeather  boolean  -- if true, spawn a feather at perch
]]
local function enterFlyingAway(dropFeather: boolean)
	if not owl then
		return
	end
	owl.state = "FlyingAway"
	owl.target = nil
	owl.pursuitStartTime = nil
	owl.detectionMeter = 0

	broadcastToAll(OwlService.Client.OwlRetreated)

	if dropFeather and owl.rootPart then
		local featherPos = owl.rootPart.Position
		task.delay(0.5, function()
			if inventoryService then
				local model = inventoryService:BuildDropModel("OwlFeather")
				if model then
					model:PivotTo(CFrame.new(featherPos + Vector3.new(0, 1, 0)))
					local baseMap = worldService and worldService:GetBaseMap()
					model.Parent = baseMap or workspace
					Debris:AddItem(model, 300)
				end
			end
		end)
	end

	local currentPos = owl.model:GetPivot().Position
	local awayPos = currentPos + Vector3.new(0, FLY_AWAY_HEIGHT, 0)
	flyTo(CFrame.new(awayPos), FLY_TWEEN_TIME, function()
		if owl then
			owl.state = "Dormant"
			owl.model:PivotTo(CFrame.new(DORMANT_HOLDING_POSITION))
			owl.humanoid.WalkSpeed = 0
			stopAllTracks(owl)
		end
	end)
end

--[[
    @summary  Transition to Chasing — scream and pursue the target.
    @param    target  Player
]]
local function enterChasing(target: Player)
	if not owl then
		return
	end
	owl.state = "Chasing"
	owl.target = target
	owl.pursuitStartTime = os.clock()
	owl.detectionMeter = 0
	broadcastToAll(OwlService.Client.OwlScream, owl.rootPart.Position)
end

--[[
    @summary  Transition to Retreating — move away from campfire.
]]
local function enterRetreating()
	if not owl then
		return
	end
	owl.state = "Retreating"
	owl.retreatUntil = os.clock() + RETREAT_HOLD_TIME
	owl.target = nil
	owl.pursuitStartTime = nil
end

--[[
    @summary  Summon 1-2 wolves near the perched Owl to scare players.
]]
local function summonWolves()
	if not owl or not animalAIService then
		return
	end
	local pos = owl.rootPart.Position
	for _ = 1, math.random(1, 2) do
		local angle = math.random() * math.pi * 2
		local offset = Vector3.new(math.cos(angle) * WOLF_SUMMON_DISTANCE, 0, math.sin(angle) * WOLF_SUMMON_DISTANCE)
		animalAIService:SpawnNpc("WolfModel", CFrame.new(pos + offset + Vector3.new(0, 5, 0)))
	end
	wolfSummoned = true
end

--[[
    @summary  Compute the movement-based detection meter while perched.
              Fills when nearby players move, decays when all are still.
]]
local function updateDetection(dt: number)
	if not owl or owl.state ~= "Perched" then
		return
	end

	local anyMoving = false
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
		local dist = (rootPart.Position - owl.rootPart.Position).Magnitude
		if dist <= DETECTION_RANGE then
			local velocity = rootPart.AssemblyLinearVelocity
			local speed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
			if speed > MOVEMENT_THRESHOLD then
				anyMoving = true
				break
			end
		end
	end

	if anyMoving then
		owl.detectionMeter = math.clamp(owl.detectionMeter + DETECTION_FILL_RATE * dt, 0, 1)
	else
		owl.detectionMeter = math.clamp(owl.detectionMeter - DETECTION_DECAY_RATE * dt, 0, 1)
	end

	broadcastToAll(OwlService.Client.OwlDetection, owl.detectionMeter)

	if owl.detectionMeter >= 1.0 then
		local target
		-- Find the nearest moving player to chase
		local nearestDist = math.huge
		for _, player in ipairs(runStateService:GetMembers()) do
			if not runStateService:IsActive() or not runStateService:IsMember(player) then
				continue
			end
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
			local dist = (rootPart.Position - owl.rootPart.Position).Magnitude
			if dist < nearestDist and dist <= DETECTION_RANGE then
				nearestDist = dist
				target = player
			end
		end
		if target then
			enterChasing(target)
		else
			-- No valid target, reset meter
			owl.detectionMeter = 0
		end
	end
end

--[[
    @summary  Find the nearest huntable player from a position.
    @param    fromPosition  Vector3
    @returns  Player?
]]
local function findHuntableTarget(fromPosition: Vector3): Player?
	local nearest: Player? = nil
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
		end
	end
	return nearest
end

--[[
    @summary  Compute pursuit speed based on time chasing.
    @returns  number
]]
local function computePursuitSpeed(): number
	if not owl or not owl.pursuitStartTime then
		return BASE_CHASE_SPEED
	end
	local elapsed = os.clock() - owl.pursuitStartTime
	local bonus = math.min(elapsed * PURSUIT_ACCEL_PER_SEC, PURSUIT_MAX_BONUS_SPEED)
	return BASE_CHASE_SPEED + bonus
end

--[[
    @summary  Main state decision logic for the Owl.
]]
local function updateOwlState()
	if not owl then
		return
	end
	local now = os.clock()

	if owl.state == "Stunned" then
		if now >= owl.stunUntil then
			if owl.target then
				local character = owl.target.Character
				local rootPart = character and character:FindFirstChild("HumanoidRootPart")
				if rootPart and not (campfireService and campfireService:IsInSafeZone(rootPart.Position)) then
					owl.state = "Chasing"
				else
					enterRetreating()
				end
			else
				enterRetreating()
			end
		end
		return
	end

	if owl.state == "Retreating" then
		if now >= owl.retreatUntil then
			enterFlyingAway(false)
		end
		return
	end

	if owl.state == "FlyingIn" or owl.state == "FlyingAway" then
		return
	end

	-- Dawn check — fly away without feather
	if timeService and timeService:GetCurrentPhase() ~= "Night" then
		if owl.state ~= "Dormant" then
			enterFlyingAway(false)
		end
		return
	end

	if owl.state == "Perched" then
		-- Check if perch time expired with no full detection → fly away with feather
		if now >= owl.perchUntil and owl.detectionMeter < 1.0 then
			enterFlyingAway(true)
			return
		end

		-- Random wolf summon
		if not wolfSummoned and math.random() <= WOLF_SUMMON_CHANCE * 0.02 then
			summonWolves()
		end
		return
	end

	if owl.state == "Chasing" then
		if owl.target then
			local character = owl.target.Character
			local rootPart = character and character:FindFirstChild("HumanoidRootPart")
			if not rootPart or (campfireService and campfireService:IsInSafeZone(rootPart.Position)) then
				enterRetreating()
				return
			end
		else
			-- Lost target, try to find a new one
			local newTarget = findHuntableTarget(owl.rootPart.Position)
			if newTarget then
				owl.target = newTarget
				owl.pursuitStartTime = os.clock()
			else
				enterRetreating()
				return
			end
		end
	end
end

--[[
    @summary  Execute movement/behavior for the Owl's current state.
]]
local function runOwlBehavior(dt: number)
	if not owl then
		return
	end

	if owl.state == "Dormant" or owl.state == "FlyingIn" or owl.state == "FlyingAway" then
		owl.humanoid.WalkSpeed = 0
		-- Wing flap is handled by flyTo's heartbeat during flight
		return
	end

	if owl.state == "Stunned" then
		owl.humanoid.WalkSpeed = 0
		playTrack(owl, "Idle")
		updateWingFlap(owl, 0.3, dt)
		return
	end

	if owl.state == "Retreating" then
		owl.humanoid.WalkSpeed = BASE_CHASE_SPEED
		playTrack(owl, "Walk")
		-- Move away from the campfire
		local campfirePos = (worldService and worldService:GetCampfireCFrame() or CFrame.new()).Position
		local awayDir = (owl.rootPart.Position - campfirePos)
		if awayDir.Magnitude < 1 then
			awayDir = Vector3.new(1, 0, 0)
		end
		awayDir = Vector3.new(awayDir.X, 0, awayDir.Z).Unit
		owl.humanoid:MoveTo(owl.rootPart.Position + awayDir * 30)
		updateWingFlap(owl, 2, dt)
		return
	end

	if owl.state == "Perched" then
		owl.humanoid.WalkSpeed = 0
		playTrack(owl, "Idle")
		updateWingFlap(owl, 0.5, dt)
		return
	end

	if owl.state == "Chasing" and owl.target then
		local character = owl.target.Character
		local rootPart = character and character:FindFirstChild("HumanoidRootPart")
		if not rootPart then
			return
		end

		local speed = computePursuitSpeed()
		owl.humanoid.WalkSpeed = speed
		playTrack(owl, "Walk")
		owl.humanoid:MoveTo(rootPart.Position)

		local dist = (owl.rootPart.Position - rootPart.Position).Magnitude
		local now = os.clock()
		if dist <= CONTACT_RANGE and (now - owl.lastContactTime) >= CONTACT_COOLDOWN then
			owl.lastContactTime = now
			local targetPlayer = owl.target :: Player?
			if targetPlayer and playerLifeService and playerLifeService:IsAlive(targetPlayer) then
				local damage = 25 + (timeService and timeService:GetCycleIndex() or 1) * 2
				playerLifeService:ApplyDamage(targetPlayer, damage, "Owl")
				broadcastToAll(OwlService.Client.OwlContact, owl.rootPart.Position)
			end
		end

		updateWingFlap(owl, 2.5, dt)
	end
end

--[[
    @summary  Heartbeat-driven tick for the Owl.
    @param    dt  number
]]
local function onHeartbeat(dt: number)
	if not owl then
		return
	end

	-- Detection meter updates every frame while perched
	if owl.state == "Perched" then
		updateDetection(dt)
	end

	local now = os.clock()
	if now >= owl.nextDecisionTime then
		owl.nextDecisionTime = now + DECISION_INTERVAL
		updateOwlState()
	end
	runOwlBehavior(dt)
end

--[[
    @summary  Check for night transition to potentially activate the Owl.
]]
local function checkNightTransition()
	if not timeService or not timeService:IsRunning() then
		return
	end

	local phase = timeService:GetCurrentPhase()
	if phase == lastPhase then
		return
	end
	lastPhase = phase

	if phase == "Night" then
		local dayNumber = timeService:GetDayNumber()
		if dayNumber >= OWL_START_DAY and not owlActiveTonight then
			-- Roll for Owl activation
			if math.random() <= OWL_SPAWN_CHANCE then
				owlActiveTonight = true
				-- Suppress the Deer for this night
				if deerService then
					deerService:SuppressDeer(true)
				end
				-- Announce and activate after a short delay
				task.delay(3, function()
					if owlActiveTonight and owl and owl.state == "Dormant" then
						broadcastToAll(OwlService.Client.OwlActive)
						enterFlyingIn()
					end
				end)
			end
		end
	elseif phase == "Day" then
		-- Reset for the next night
		if owlActiveTonight then
			owlActiveTonight = false
			if deerService then
				deerService:SuppressDeer(false)
			end
		end
	end
end

-- | Public | --

--[[
    @summary  Return the Owl to its hidden dormant state.
]]
function OwlService:ResetForRun()
	owlActiveTonight = false
	wolfSummoned = false
	lastPhase = ""
	if not owl then
		return
	end
	if owl.flyHeartbeat then
		owl.flyHeartbeat:Disconnect()
		owl.flyHeartbeat = nil
	end
	owl.state = "Dormant"
	owl.target = nil
	owl.detectionMeter = 0
	owl.pursuitStartTime = nil
	owl.rootPart.Anchored = true
	owl.humanoid.WalkSpeed = 0
	stopAllTracks(owl)
	owl.model:PivotTo(CFrame.new(DORMANT_HOLDING_POSITION))
	if deerService then
		deerService:SuppressDeer(false)
	end
end

--[[
    @summary  Interrupt the Owl's pursuit with a flashlight stun.
    @param    model   Model   -- the Owl model
    @param    player  Player  -- the player holding the flashlight
    @returns  boolean         -- true if the stun was applied
]]
function OwlService:ApplyFlashlightStun(model: Model, player: Player): boolean
	if not owl or owl.model ~= model then
		return false
	end
	if owl.state ~= "Chasing" then
		return false
	end

	local now = os.clock()
	if (now - owl.lastStunTime) >= STUN_RESISTANCE_RECOVERY_TIME then
		owl.consecutiveStuns = 0
	end
	owl.consecutiveStuns += 1
	owl.lastStunTime = now

	local duration = math.max(
		BASE_STUN_DURATION - (owl.consecutiveStuns - 1) * STUN_DECAY_PER_USE,
		MIN_STUN_DURATION
	)

	owl.state = "Stunned"
	owl.stunUntil = now + duration
	owl.humanoid.WalkSpeed = 0
	stopAllTracks(owl)
	playTrack(owl, "Idle")

	broadcastToAll(OwlService.Client.OwlStunned, owl.rootPart.Position, duration)
	return true
end

-- // INITIALIZATION // --

function OwlService:KnitStart()
	worldService = Knit.GetService("WorldService")
	timeService = Knit.GetService("TimeService")
	runStateService = Knit.GetService("RunStateService")
	campfireService = Knit.GetService("CampfireService")
	spawnService = Knit.GetService("SpawnService")
	animalAIService = Knit.GetService("AnimalAIService")
	inventoryService = Knit.GetService("InventoryService")
	deerService = Knit.GetService("DeerService")
	playerLifeService = Knit.GetService("PlayerLifeService")

	task.delay(3, function()
		spawnOwl()
	end)

	RunService.Heartbeat:Connect(function(dt)
		checkNightTransition()
		onHeartbeat(dt)
	end)

end

return OwlService
