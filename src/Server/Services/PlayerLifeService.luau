--[[
    @file    PlayerLifeService.luau
    @author  manik
    @date    2025

    @summary
    Server-authoritative downing, persistent revivable bodies, body dragging,
    spectating, teammate revive, and team-loss resolution.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")

local Knit = require(ReplicatedStorage.Packages.Knit)
local ServerRole = require(ReplicatedStorage.Shared.ServerRole)
local Signal = require(ReplicatedStorage.Packages.Signal)
local RunConfig = require(ReplicatedStorage.Shared.RunConfig)
local AssetCatalog = require(ReplicatedStorage.Shared.AssetCatalog)
local WorldSoundUtil = require(ReplicatedStorage.Shared.WorldSoundUtil)

local PlayerLifeService = Knit.CreateService({
	Name = "PlayerLifeService",
	Client = {
		LifeStateChanged = Knit.CreateSignal(),
		TeammateDowned = Knit.CreateSignal(),
		ReviveCompleted = Knit.CreateSignal(),
		BodyDragTargetMoved = Knit.CreateSignal(),
		RequestBodyDragStart = Knit.CreateSignal(),
	},
})

PlayerLifeService.PlayerDowned = Signal.new()
PlayerLifeService.PlayerRevived = Signal.new()
PlayerLifeService.PlayerEliminated = Signal.new()

export type LifeState = "Lobby" | "Alive" | "Downed" | "Eliminated"

type MovementState = {
	walkSpeed: number,
	jumpPower: number,
	autoRotate: boolean,
	platformStand: boolean,
}

type BodyDrag = {
	target: Player,
	root: BasePart,
	dragTarget: BasePart,
	targetAttachment: Attachment,
	bodyAttachment: Attachment,
	alignPosition: AlignPosition,
	lastUpdate: number,
}

type RagdollData = {
	character: Model,
	motors: { Motor6D },
	joints: { Instance },
	collidable: { [BasePart]: boolean },
}

local runStateService: any = nil
local inventoryService: any = nil
local spawnService: any = nil

local lifeStates: { [Player]: LifeState } = {}
local downTokens: { [Player]: string } = {}
local savedMovement: { [Player]: MovementState } = {}
local graceUntil: { [Player]: number } = {}
local loadingCharacters: { [Player]: boolean } = {}
local reviveLocks: { [Player]: boolean } = {}
local bodyDrags: { [Player]: BodyDrag } = {}
local bodyDraggedBy: { [Player]: Player } = {}
local ragdollData: { [Player]: RagdollData } = {}
local dragRayParams = RaycastParams.new()
dragRayParams.FilterType = Enum.RaycastFilterType.Exclude

local function runMembers(): { Player }
	return if runStateService then runStateService:GetMembers() else {}
end

local function broadcastState(player: Player, state: LifeState, payload: { [string]: any }?)
	if not runStateService or not runStateService:IsMember(player) then
		return
	end
	local data = table.clone(payload or {})
	data.userId = player.UserId
	data.state = state
	for _, member in ipairs(runMembers()) do
		PlayerLifeService.Client.LifeStateChanged:Fire(member, data)
	end
end

local function loadCharacter(player: Player): boolean
	if loadingCharacters[player] or player.Parent ~= Players then
		return false
	end
	loadingCharacters[player] = true
	local ok, err = pcall(function()
		player:LoadCharacterAsync()
	end)
	loadingCharacters[player] = nil
	if not ok then
		warn("[PlayerLifeService] Character load failed for", player.Name, err)
	end
	return ok
end

local function removeRevivePrompts(character: Model?)
	if not character then
		return
	end
	for _, descendant in ipairs(character:GetDescendants()) do
		if descendant:IsA("ProximityPrompt")
			and (descendant.Name == "RevivePrompt" or descendant.Name == "DragBodyPrompt")
		then
			descendant:Destroy()
		end
	end
end

local function ensureRevivePrompt(player: Player)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not character or not root or not root:IsA("BasePart") then
		return
	end
	removeRevivePrompts(character)

	-- Revive prompt (requires Bandage, 5-second hold)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "RevivePrompt"
	prompt.ActionText = "Revive with Bandage"
	prompt.ObjectText = player.DisplayName
	prompt.MaxActivationDistance = RunConfig.ReviveRange
	prompt.HoldDuration = RunConfig.ReviveHoldDuration
	prompt.RequiresLineOfSight = true
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.Parent = root
	prompt.Triggered:Connect(function(reviver)
		PlayerLifeService:TryRevive(reviver, player)
	end)
	-- Drag body via click (CarryController handles click-to-drag on the client side).
	-- We no longer create a DragBodyPrompt here; the character's LifeState attribute
	-- is sufficient for clients to detect a draggable body on click.
end

-- | Ragdoll | --

local RAGDOLL_PREFIX = "LifeRagdoll_"

-- Hand the whole character assembly to the given network owner (nil = server).
-- A downed body must be server-simulated on every client or the owning client
-- keeps predicting it and fights the drag constraints.
local function setBodyNetworkOwner(character: Model, owner: Player?)
	for _, d in ipairs(character:GetDescendants()) do
		if d:IsA("BasePart") and not d.Anchored then
			pcall(function()
				d:SetNetworkOwner(owner)
			end)
		end
	end
end

local function applyRagdoll(player: Player, character: Model)
	local existing = ragdollData[player]
	if existing then
		if existing.character == character and character.Parent then
			return
		end
		ragdollData[player] = nil
	end

	local data: RagdollData = { character = character, motors = {}, joints = {}, collidable = {} }
	-- Limbs must collide with the world or the body sinks through the floor.
	for _, d in ipairs(character:GetDescendants()) do
		if d:IsA("BasePart") then
			data.collidable[d] = d.CanCollide
			if d.Name ~= "HumanoidRootPart" then
				d.CanCollide = true
			end
		end
	end
	for _, d in ipairs(character:GetDescendants()) do
		if not (d:IsA("Motor6D") and d.Enabled) then
			continue
		end
		local p0, p1 = d.Part0, d.Part1
		if not (p0 and p0:IsA("BasePart") and p1 and p1:IsA("BasePart")) then
			continue
		end
		local a0 = Instance.new("Attachment")
		a0.Name = RAGDOLL_PREFIX .. "Att0"
		a0.CFrame = d.C0
		a0.Parent = p0
		local a1 = Instance.new("Attachment")
		a1.Name = RAGDOLL_PREFIX .. "Att1"
		a1.CFrame = d.C1
		a1.Parent = p1
		local neck = p1.Name == "Head" or d.Name == "Neck"
		local socket = Instance.new("BallSocketConstraint")
		socket.Name = RAGDOLL_PREFIX .. "Socket"
		socket.Attachment0 = a0
		socket.Attachment1 = a1
		socket.LimitsEnabled = true
		socket.UpperAngle = if neck then 15 else 45
		socket.TwistLimitsEnabled = true
		socket.TwistLowerAngle = if neck then -15 else -45
		socket.TwistUpperAngle = if neck then 15 else 45
		socket.Parent = p1
		-- Adjacent parts were collision-suppressed by the Motor6D; without a
		-- NoCollisionConstraint the socketed joint jitters against itself.
		local noc = Instance.new("NoCollisionConstraint")
		noc.Name = RAGDOLL_PREFIX .. "NoCollide"
		noc.Part0 = p0
		noc.Part1 = p1
		noc.Parent = character
		d.Enabled = false
		table.insert(data.motors, d)
		table.insert(data.joints, a0)
		table.insert(data.joints, a1)
		table.insert(data.joints, socket)
		table.insert(data.joints, noc)
	end
	ragdollData[player] = data
end

local function clearRagdoll(player: Player)
	local data = ragdollData[player]
	ragdollData[player] = nil
	if not data then
		return
	end
	for _, motor in ipairs(data.motors) do
		if motor.Parent then
			motor.Enabled = true
		end
	end
	for _, joint in ipairs(data.joints) do
		if joint.Parent then
			joint:Destroy()
		end
	end
	for part, canCollide in pairs(data.collidable) do
		if part.Parent then
			part.CanCollide = canCollide
		end
	end
end

local RAGDOLL_DISABLED_STATES = {
	Enum.HumanoidStateType.FallingDown,
	Enum.HumanoidStateType.Ragdoll,
	Enum.HumanoidStateType.GettingUp,
}

local function applyBodyPresentation(player: Player, state: LifeState)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not character or not humanoid or not root or not root:IsA("BasePart") then
		return
	end
	if not savedMovement[player] then
		savedMovement[player] = {
			walkSpeed = humanoid.WalkSpeed,
			jumpPower = humanoid.JumpPower,
			autoRotate = humanoid.AutoRotate,
			platformStand = humanoid.PlatformStand,
		}
	end
	humanoid.BreakJointsOnDeath = false
	humanoid.Health = 1
	humanoid.WalkSpeed = 0
	humanoid.JumpPower = 0
	humanoid.AutoRotate = false
	humanoid.PlatformStand = true
	for _, stateType in ipairs(RAGDOLL_DISABLED_STATES) do
		humanoid:SetStateEnabled(stateType, false)
	end
	-- Stop the default health-regen script so downed bodies do not self-heal.
	local healthScript = character:FindFirstChild("Health")
	if healthScript and healthScript:IsA("BaseScript") then
		healthScript.Disabled = true
	end
	root.Anchored = false
	if not ragdollData[player] then
		-- Pitch the whole character flat (face down) before the sockets engage.
		local pivot = character:GetPivot()
		character:PivotTo(
			CFrame.new(pivot.Position + Vector3.new(0, 0.4, 0))
				* CFrame.Angles(math.rad(-90), 0, 0)
				* pivot.Rotation
		)
	end
	applyRagdoll(player, character)
	humanoid:ChangeState(Enum.HumanoidStateType.Physics)
	setBodyNetworkOwner(character, nil)
	character:SetAttribute("LifeState", state)
	ensureRevivePrompt(player)
end

local function clearBodyPresentation(player: Player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	removeRevivePrompts(character)
	clearRagdoll(player)
	if humanoid then
		for _, stateType in ipairs(RAGDOLL_DISABLED_STATES) do
			humanoid:SetStateEnabled(stateType, true)
		end
		local movement = savedMovement[player]
		humanoid.WalkSpeed = if movement then movement.walkSpeed else 16
		humanoid.JumpPower = if movement then movement.jumpPower else 50
		humanoid.AutoRotate = if movement then movement.autoRotate else true
		humanoid.PlatformStand = if movement then movement.platformStand else false
		humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
	end
	if character then
		local healthScript = character:FindFirstChild("Health")
		if healthScript and healthScript:IsA("BaseScript") then
			healthScript.Disabled = false
		end
		setBodyNetworkOwner(character, player)
		character:SetAttribute("LifeState", lifeStates[player] or "Alive")
	end
	savedMovement[player] = nil
end

local function configureCharacter(player: Player, character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if not humanoid or not humanoid:IsA("Humanoid") then
		return
	end
	humanoid.BreakJointsOnDeath = false
	humanoid.MaxHealth = RunConfig.StartingHealth
	local state = lifeStates[player] or "Lobby"
	character:SetAttribute("LifeState", state)
	if state == "Downed" or state == "Eliminated" then
		humanoid.Health = 1
		task.defer(applyBodyPresentation, player, state)
	else
		humanoid.Health = RunConfig.StartingHealth
	end
end

local function hasConnectedAliveMember(): boolean
	for _, member in ipairs(runMembers()) do
		if member.Parent == Players and lifeStates[member] == "Alive" then
			return true
		end
	end
	return false
end

local function checkTeamLoss()
	if runStateService and runStateService:IsActive() and not hasConnectedAliveMember() then
		runStateService:BeginEnding("ALL_PLAYERS_LOST", {
			displayedDay = Knit.GetService("TimeService"):GetDisplayedDay(),
			cycleIndex = Knit.GetService("TimeService"):GetCycleIndex(),
		})
	end
end

local function stopBodyDrag(dragger: Player)
	local entry = bodyDrags[dragger]
	if not entry then
		return
	end
	bodyDrags[dragger] = nil
	if bodyDraggedBy[entry.target] == dragger then
		bodyDraggedBy[entry.target] = nil
	end
	for _, instance in ipairs({ entry.alignPosition, entry.bodyAttachment, entry.targetAttachment, entry.dragTarget }) do
		if instance and instance.Parent then
			instance:Destroy()
		end
	end
	if entry.root and entry.root.Parent then
		pcall(function()
			entry.root:SetNetworkOwner(nil)
		end)
	end
end

local function stopBodyDragsFor(player: Player)
	stopBodyDrag(player)
	local dragger = bodyDraggedBy[player]
	if dragger then
		stopBodyDrag(dragger)
	end
end

local function validateBodyDrag(dragger: Player, target: Player, startRange: number): (BasePart?, BasePart?)
	if dragger == target or lifeStates[dragger] ~= "Alive" then
		return nil, nil
	end
	local targetState = lifeStates[target]
	if targetState ~= "Downed" and targetState ~= "Eliminated" then
		return nil, nil
	end
	if not runStateService:IsActive() or not runStateService:IsMember(dragger) or not runStateService:IsMember(target) then
		return nil, nil
	end
	local draggerRoot = dragger.Character and dragger.Character:FindFirstChild("HumanoidRootPart")
	local targetRoot = target.Character and target.Character:FindFirstChild("HumanoidRootPart")
	if not draggerRoot or not draggerRoot:IsA("BasePart") or not targetRoot or not targetRoot:IsA("BasePart") then
		return nil, nil
	end
	if (draggerRoot.Position - targetRoot.Position).Magnitude > startRange then
		return nil, nil
	end
	return draggerRoot, targetRoot
end

local function eliminateAfterBleedout(player: Player, token: string)
	task.wait(RunConfig.DownedDuration)
	if player.Parent ~= Players or downTokens[player] ~= token or lifeStates[player] ~= "Downed" then
		return
	end
	if not runStateService:IsActive() or not runStateService:IsMember(player) then
		return
	end
	downTokens[player] = nil
	lifeStates[player] = "Eliminated"
	applyBodyPresentation(player, "Eliminated")
	PlayerLifeService.PlayerEliminated:Fire(player)
	broadcastState(player, "Eliminated", {})
	checkTeamLoss()
end

local function downPlayer(player: Player, source: string)
	if lifeStates[player] ~= "Alive" then
		return
	end
	stopBodyDragsFor(player)
	lifeStates[player] = "Downed"
	local token = HttpService:GenerateGUID(false)
	downTokens[player] = token
	local downRoot = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if downRoot and downRoot:IsA("BasePart") then
		WorldSoundUtil.playAt(AssetCatalog.Audio.BodyFall, downRoot.Position, { volume = 0.55, maxDistance = 60, pitchJitter = 0.05 })
	end
	applyBodyPresentation(player, "Downed")
	runStateService:IncrementStat(player, "Downs", 1)
	local payload = {
		source = source,
		bleedOutAt = workspace:GetServerTimeNow() + RunConfig.DownedDuration,
	}
	broadcastState(player, "Downed", payload)
	for _, member in ipairs(runMembers()) do
		if member ~= player then
			PlayerLifeService.Client.TeammateDowned:Fire(member, player.UserId, payload.bleedOutAt)
		end
	end
	PlayerLifeService.PlayerDowned:Fire(player, source)
	task.spawn(eliminateAfterBleedout, player, token)
	checkTeamLoss()
end

function PlayerLifeService:GetLifeState(player: Player): LifeState
	return lifeStates[player] or "Lobby"
end

function PlayerLifeService:IsAlive(player: Player): boolean
	return lifeStates[player] == "Alive"
end

function PlayerLifeService:CanAct(player: Player): boolean
	if lifeStates[player] ~= "Alive" or not runStateService or not runStateService:IsActive() or not runStateService:IsMember(player) then
		return false
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return humanoid ~= nil and humanoid.Health > 0 and root ~= nil and root:IsA("BasePart")
end

function PlayerLifeService:ApplyDamage(player: Player, amount: number, source: string?): { [string]: any }
	if typeof(amount) ~= "number" or amount <= 0 or amount ~= amount then
		return { applied = 0, downed = false }
	end
	if lifeStates[player] ~= "Alive" or os.clock() < (graceUntil[player] or 0) then
		return { applied = 0, downed = false }
	end
	if not runStateService:IsActive() or not runStateService:IsMember(player) then
		return { applied = 0, downed = false }
	end
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return { applied = 0, downed = false }
	end
	local applied = math.min(amount, humanoid.Health)
	if amount >= humanoid.Health then
		humanoid.Health = 1
		downPlayer(player, source or "Unknown")
		return { applied = applied, downed = true }
	end
	humanoid.Health -= amount
	local hurtRoot = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if hurtRoot and hurtRoot:IsA("BasePart") then
		WorldSoundUtil.playAt(
			if math.random() < 0.5 then AssetCatalog.Audio.PlayerHurt else AssetCatalog.Audio.PlayerHurtAlt,
			hurtRoot.Position,
			{ volume = 0.45, maxDistance = 45, pitchJitter = 0.08 }
		)
	end
	return { applied = applied, downed = false }
end

local function validRevive(reviver: Player, target: Player): boolean
	if reviver == target or lifeStates[reviver] ~= "Alive" then
		return false
	end
	local state = lifeStates[target]
	if state ~= "Downed" and state ~= "Eliminated" then
		return false
	end
	if not runStateService:IsActive() or not runStateService:IsMember(reviver) or not runStateService:IsMember(target) then
		return false
	end
	local reviverRoot = reviver.Character and reviver.Character:FindFirstChild("HumanoidRootPart")
	local targetRoot = target.Character and target.Character:FindFirstChild("HumanoidRootPart")
	return reviverRoot ~= nil and reviverRoot:IsA("BasePart")
		and targetRoot ~= nil and targetRoot:IsA("BasePart")
		and (reviverRoot.Position - targetRoot.Position).Magnitude <= RunConfig.ReviveRange
end

function PlayerLifeService:TryRevive(reviver: Player, target: Player): boolean
	if reviveLocks[target] or not validRevive(reviver, target) then
		return false
	end
	reviveLocks[target] = true
	-- Revalidate under the lock. Resource consumption is the final validation
	-- step, so concurrent prompts can never spend more than one Bandage.
	if not validRevive(reviver, target) or inventoryService:GetResourceCount(reviver, "Bandage") < 1 then
		reviveLocks[target] = nil
		return false
	end
	if not inventoryService:ConsumeResource(reviver, "Bandage", 1) then
		reviveLocks[target] = nil
		return false
	end
	stopBodyDragsFor(target)
	if not spawnService:ReviveAtCampfire(target) then
		inventoryService:AddResource(reviver, "Bandage", 1)
		reviveLocks[target] = nil
		return false
	end
	downTokens[target] = nil
	lifeStates[target] = "Alive"
	graceUntil[target] = os.clock() + RunConfig.ReviveGracePeriod
	clearBodyPresentation(target)
	local humanoid = target.Character and target.Character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.Health = math.clamp(RunConfig.ReviveHealth, 1, humanoid.MaxHealth)
	end
	reviveLocks[target] = nil
	local revivedRoot = target.Character and target.Character:FindFirstChild("HumanoidRootPart")
	if revivedRoot and revivedRoot:IsA("BasePart") then
		WorldSoundUtil.playAt(AssetCatalog.Audio.ReviveSwell, revivedRoot.Position, { volume = 0.6, maxDistance = 60, maxLifetime = 10 })
	end
	runStateService:IncrementStat(reviver, "Revives", 1)
	PlayerLifeService.PlayerRevived:Fire(reviver, target)
	broadcastState(target, "Alive", { health = RunConfig.ReviveHealth, reviverUserId = reviver.UserId })
	for _, member in ipairs(runMembers()) do
		PlayerLifeService.Client.ReviveCompleted:Fire(member, target.UserId, reviver.UserId)
	end
	return true
end

-- | Client Remote: Use Bandage from Inventory to revive nearest downed teammate |
function PlayerLifeService.Client:RequestBandageRevive(player: Player): boolean
	if lifeStates[player] ~= "Alive" then return false end
	if not runStateService or not runStateService:IsActive() or not runStateService:IsMember(player) then return false end
	local reviverRoot = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not reviverRoot then return false end
	-- Find nearest downed member within revive range
	local nearest: Player? = nil
	local nearestDist = math.huge
	for _, member in ipairs(runMembers()) do
		if member ~= player and (lifeStates[member] == "Downed") then
			local memberRoot = member.Character and member.Character:FindFirstChild("HumanoidRootPart")
			if memberRoot then
				local dist = (reviverRoot.Position - memberRoot.Position).Magnitude
				if dist <= RunConfig.ReviveRange and dist < nearestDist then
					nearestDist = dist
					nearest = member
				end
			end
		end
	end
	if not nearest then return false end
	return PlayerLifeService:TryRevive(player, nearest)
end

function PlayerLifeService.Client:RequestBodyDragStart(player: Player, target: Player): boolean
	if typeof(target) ~= "Instance" or not target:IsA("Player") or bodyDrags[player] or bodyDraggedBy[target] then
		return false
	end
	local _, targetRoot = validateBodyDrag(player, target, RunConfig.BodyDragStartRange)
	if not targetRoot then
		return false
	end
	local targetCharacter = target.Character
	local dragTarget = Instance.new("Part")
	dragTarget.Name = "BodyDragTarget_" .. tostring(player.UserId)
	dragTarget.Size = Vector3.one
	dragTarget.Transparency = 1
	dragTarget.CanCollide = false
	dragTarget.CanQuery = false
	dragTarget.CanTouch = false
	dragTarget.Anchored = true
	dragTarget.CFrame = targetRoot.CFrame
	dragTarget.Parent = workspace
	local targetAttachment = Instance.new("Attachment")
	targetAttachment.Name = "BodyDragTargetAttachment"
	targetAttachment.Parent = dragTarget
	local bodyAttachment = Instance.new("Attachment")
	bodyAttachment.Name = "BodyDragAttachment"
	bodyAttachment.Parent = targetRoot
	local align = Instance.new("AlignPosition")
	align.Name = "BodyDragAlignPosition"
	align.Attachment0 = bodyAttachment
	align.Attachment1 = targetAttachment
	align.RigidityEnabled = false
	align.ApplyAtCenterOfMass = true
	align.Responsiveness = RunConfig.BodyDragResponsiveness
	align.MaxForce = 1.25e5
	align.Parent = targetRoot
	if targetCharacter then
		setBodyNetworkOwner(targetCharacter, nil)
	end
	bodyDrags[player] = {
		target = target,
		root = targetRoot,
		dragTarget = dragTarget,
		targetAttachment = targetAttachment,
		bodyAttachment = bodyAttachment,
		alignPosition = align,
		lastUpdate = 0,
	}
	bodyDraggedBy[target] = player
	return true
end

function PlayerLifeService.Client:RequestBodyDragStop(player: Player): boolean
	if not bodyDrags[player] then
		return false
	end
	stopBodyDrag(player)
	return true
end

function PlayerLifeService.Client:GetSnapshot(player: Player): { [string]: any }
	if not runStateService or not runStateService:IsMember(player) then
		return { selfState = lifeStates[player] or "Lobby", states = {} }
	end
	local states = {}
	for _, member in ipairs(runMembers()) do
		states[tostring(member.UserId)] = lifeStates[member] or "Lobby"
	end
	return { selfState = lifeStates[player] or "Lobby", states = states }
end

local function cleanupInvalidBodyDrags()
	local toStop = {}
	for dragger, entry in pairs(bodyDrags) do
		local draggerRoot = validateBodyDrag(dragger, entry.target, RunConfig.BodyDragMaxDistance)
		if not draggerRoot or not entry.root.Parent or not entry.dragTarget.Parent
			or (draggerRoot.Position - entry.dragTarget.Position).Magnitude > RunConfig.BodyDragMaxDistance
			or (entry.root.Position - entry.dragTarget.Position).Magnitude > RunConfig.BodyDragMaxDistance then
			table.insert(toStop, dragger)
		end
	end
	for _, dragger in ipairs(toStop) do
		stopBodyDrag(dragger)
	end
end

Players.CharacterAutoLoads = false

function PlayerLifeService:KnitStart()
	if ServerRole.IsLobby() then return end
	runStateService = Knit.GetService("RunStateService")
	inventoryService = Knit.GetService("InventoryService")
	spawnService = Knit.GetService("SpawnService")

	local function onPlayerAdded(player: Player)
		lifeStates[player] = "Lobby"
		player.CharacterAdded:Connect(function(character)
			configureCharacter(player, character)
		end)
		player.CharacterRemoving:Connect(function()
			stopBodyDragsFor(player)
			ragdollData[player] = nil
		end)
		if not player.Character then
			task.spawn(loadCharacter, player)
		end
	end
	for _, player in ipairs(Players:GetPlayers()) do
		onPlayerAdded(player)
	end
	Players.PlayerAdded:Connect(onPlayerAdded)



	runStateService.RunStarted:Connect(function()
		for _, player in ipairs(runMembers()) do
			lifeStates[player] = "Alive"
			downTokens[player] = nil
			graceUntil[player] = nil
			clearBodyPresentation(player)
			if player.Character then
				configureCharacter(player, player.Character)
			end
			broadcastState(player, "Alive", {})
		end
	end)

	runStateService.RunEnding:Connect(function()
		for dragger in pairs(bodyDrags) do
			stopBodyDrag(dragger)
		end
	end)

	runStateService.RunCleaned:Connect(function()
		for _, player in ipairs(Players:GetPlayers()) do
			lifeStates[player] = "Lobby"
			downTokens[player] = nil
			graceUntil[player] = nil
			reviveLocks[player] = nil
			stopBodyDragsFor(player)
			clearBodyPresentation(player)
			local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
			if humanoid then
				humanoid.Health = humanoid.MaxHealth
			end
			local backpack = player:FindFirstChild("Backpack")
			if backpack then backpack:ClearAllChildren() end
			local starterGear = player:FindFirstChild("StarterGear")
			if starterGear then starterGear:ClearAllChildren() end
			spawnService:ReturnToLobby(player)
			PlayerLifeService.Client.LifeStateChanged:Fire(player, { userId = player.UserId, state = "Lobby" })
		end
	end)

		Players.PlayerRemoving:Connect(function(player)
		stopBodyDragsFor(player)
		lifeStates[player] = nil
		downTokens[player] = nil
		graceUntil[player] = nil
		savedMovement[player] = nil
		loadingCharacters[player] = nil
		reviveLocks[player] = nil
		ragdollData[player] = nil
		task.defer(checkTeamLoss)
	end)
	PlayerLifeService.Client.BodyDragTargetMoved:Connect(function(player: Player, position: any)
		if typeof(position) ~= "Vector3" then
			return
		end
		local entry = bodyDrags[player]
		if not entry then
			return
		end
		local now = os.clock()
		if now - entry.lastUpdate < RunConfig.BodyDragUpdateInterval then
			return
		end
		local draggerRoot = validateBodyDrag(player, entry.target, RunConfig.BodyDragMaxDistance)
		if not draggerRoot or (draggerRoot.Position - position).Magnitude > RunConfig.BodyDragMaxDistance then
			stopBodyDrag(player)
			return
		end
		entry.lastUpdate = now
		entry.dragTarget.CFrame = CFrame.new(position)
	end)

	RunService.Heartbeat:Connect(function()
		cleanupInvalidBodyDrags()
		-- Downed/eliminated bodies stay at 1 HP; external heals or regen
		-- ticks are clamped back so nobody recovers while on the ground.
		for player, state in pairs(lifeStates) do
			if state == "Downed" or state == "Eliminated" then
				local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
				if humanoid and humanoid.Health > 1 then
					humanoid.Health = 1
				end
			end
		end
	end)
end

return PlayerLifeService
