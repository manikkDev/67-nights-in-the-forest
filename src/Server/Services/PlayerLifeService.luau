--[[
    @file    PlayerLifeService.luau
    @author  manik
    @date    2025

    @summary
    Server-authoritative player damage, downing, teammate revive,
    bleed-out elimination, controlled character loading, and team loss.

    @exports
    - PlayerLifeService:ApplyDamage(player, amount, source) -> table
    - PlayerLifeService:GetLifeState(player) -> string
    - PlayerLifeService:IsAlive(player) -> boolean
    - Knit Signal: LifeStateChanged(userId, state, payload)
]]

-- // VARIABLES // --

-- | Services | --
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- | Modules | --
local Knit = require(ReplicatedStorage.Packages.Knit)
local Signal = require(ReplicatedStorage.Packages.Signal)
local RunConfig = require(ReplicatedStorage.Shared.RunConfig)

-- | Objects | --
local PlayerLifeService = Knit.CreateService({
	Name = "PlayerLifeService",
	Client = {
		LifeStateChanged = Knit.CreateSignal(),
		TeammateDowned = Knit.CreateSignal(),
		ReviveCompleted = Knit.CreateSignal(),
	},
})

PlayerLifeService.PlayerDowned = Signal.new()
PlayerLifeService.PlayerRevived = Signal.new()
PlayerLifeService.PlayerEliminated = Signal.new()

export type LifeState = "Lobby" | "Alive" | "Downed" | "Eliminated"

-- | State Management | --
local runStateService: any = nil
local inventoryService: any = nil
local spawnService: any = nil

local lifeStates: { [Player]: LifeState } = {}
local downTokens: { [Player]: string } = {}
local savedMovement: { [Player]: { walkSpeed: number, jumpPower: number, autoRotate: boolean } } = {}
local graceUntil: { [Player]: number } = {}
local loadingCharacters: { [Player]: boolean } = {}

-- // FUNCTIONS // --

-- | Private | --

--[[
    @summary  Broadcast one player's life-state change to all run members.
    @param    player   Player
    @param    state    LifeState
    @param    payload  table?
]]
local function broadcastState(player: Player, state: LifeState, payload: { [string]: any }?)
	local data = payload or {}
	data.userId = player.UserId
	data.state = state
	for _, member in ipairs(Players:GetPlayers()) do
		PlayerLifeService.Client.LifeStateChanged:Fire(member, data)
	end
end

--[[
    @summary  Load one player's character without overlapping load calls.
    @param    player  Player
    @returns  boolean
]]
local function loadCharacter(player: Player): boolean
	if loadingCharacters[player] or not player.Parent then
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

--[[
    @summary  Configure a newly loaded character for managed life states.
    @param    player     Player
    @param    character  Model
]]
local function configureCharacter(player: Player, character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if not humanoid or not humanoid:IsA("Humanoid") then
		return
	end
	humanoid.BreakJointsOnDeath = false
	humanoid.MaxHealth = RunConfig.StartingHealth
	humanoid.Health = RunConfig.StartingHealth
	character:SetAttribute("LifeState", lifeStates[player] or "Lobby")
end

--[[
    @summary  Return whether at least one run member can still act.
    @returns  boolean
]]
local function hasLivingMember(): boolean
	if not runStateService then
		return true
	end
	for _, member in ipairs(runStateService:GetMembers()) do
		if lifeStates[member] == "Alive" then
			return true
		end
	end
	return false
end

--[[
    @summary  End the run when nobody remains capable of reviving.
]]
local function checkTeamLoss()
	if runStateService and runStateService:IsActive() and not hasLivingMember() then
		runStateService:BeginEnding("ALL_PLAYERS_LOST", {
			displayedDay = Knit.GetService("TimeService"):GetDisplayedDay(),
			cycleIndex = Knit.GetService("TimeService"):GetCycleIndex(),
		})
	end
end

--[[
    @summary  Remove movement and attach the teammate revive prompt.
    @param    player  Player
]]
local function applyDownedPresentation(player: Player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	if not character or not humanoid or not rootPart or not rootPart:IsA("BasePart") then
		return
	end

	savedMovement[player] = {
		walkSpeed = humanoid.WalkSpeed,
		jumpPower = humanoid.JumpPower,
		autoRotate = humanoid.AutoRotate,
	}
	humanoid.WalkSpeed = 0
	humanoid.JumpPower = 0
	humanoid.AutoRotate = false
	humanoid.Health = math.max(1, humanoid.Health)
	character:SetAttribute("LifeState", "Downed")

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "RevivePrompt"
	prompt.ActionText = "Revive with Bandage"
	prompt.ObjectText = player.DisplayName
	prompt.MaxActivationDistance = RunConfig.ReviveRange
	prompt.HoldDuration = RunConfig.ReviveHoldDuration
	prompt.RequiresLineOfSight = true
	prompt.Parent = rootPart
	prompt.Triggered:Connect(function(reviver)
		PlayerLifeService:TryRevive(reviver, player)
	end)
end

--[[
    @summary  Restore movement after a successful revive.
    @param    player  Player
]]
local function clearDownedPresentation(player: Player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local prompt = character and character:FindFirstChild("RevivePrompt", true)
	if prompt then
		prompt:Destroy()
	end
	if humanoid then
		local movement = savedMovement[player]
		humanoid.WalkSpeed = if movement then movement.walkSpeed else 16
		humanoid.JumpPower = if movement then movement.jumpPower else 50
		humanoid.AutoRotate = if movement then movement.autoRotate else true
	end
	if character then
		character:SetAttribute("LifeState", lifeStates[player] or "Alive")
	end
	savedMovement[player] = nil
end

--[[
    @summary  Finish a downed player's bleed-out and enter spectating.
    @param    player  Player
    @param    token   string
]]
local function eliminateAfterBleedout(player: Player, token: string)
	task.wait(RunConfig.DownedDuration)
	if not player.Parent or downTokens[player] ~= token or lifeStates[player] ~= "Downed" then
		return
	end
	if not runStateService:IsActive() then
		return
	end

	downTokens[player] = nil
	lifeStates[player] = "Eliminated"
	clearDownedPresentation(player)
	local character = player.Character
	if character then
		character:SetAttribute("LifeState", "Eliminated")
		local rootPart = character:FindFirstChild("HumanoidRootPart")
		if rootPart and rootPart:IsA("BasePart") then
			rootPart.Anchored = true
			rootPart.CFrame = CFrame.new(0, -350, 0)
		end
	end

	PlayerLifeService.PlayerEliminated:Fire(player)
	broadcastState(player, "Eliminated", {})
	checkTeamLoss()
end

--[[
    @summary  Enter the downed state and start the server bleed-out timer.
    @param    player  Player
    @param    source  string
]]
local function downPlayer(player: Player, source: string)
	if lifeStates[player] ~= "Alive" then
		return
	end
	lifeStates[player] = "Downed"
	local token = game:GetService("HttpService"):GenerateGUID(false)
	downTokens[player] = token
	applyDownedPresentation(player)
	runStateService:IncrementStat(player, "Downs", 1)

	local payload = {
		source = source,
		bleedOutAt = workspace:GetServerTimeNow() + RunConfig.DownedDuration,
	}
	broadcastState(player, "Downed", payload)
	for _, member in ipairs(runStateService:GetMembers()) do
		if member ~= player then
			PlayerLifeService.Client.TeammateDowned:Fire(member, player.UserId, payload.bleedOutAt)
		end
	end
	PlayerLifeService.PlayerDowned:Fire(player, source)
	task.spawn(eliminateAfterBleedout, player, token)
	checkTeamLoss()
end

-- | Public | --

--[[
    @summary  Return a player's authoritative life state.
    @param    player  Player
    @returns  LifeState
]]
function PlayerLifeService:GetLifeState(player: Player): LifeState
	return lifeStates[player] or "Lobby"
end

--[[
    @summary  Return whether a player may perform gameplay actions.
    @param    player  Player
    @returns  boolean
]]
function PlayerLifeService:IsAlive(player: Player): boolean
	return lifeStates[player] == "Alive"
end

--[[
    @summary  Apply validated damage and resolve lethal damage as a down.
    @param    player  Player
    @param    amount  number
    @param    source  string?
    @returns  table
]]
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

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
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
	return { applied = applied, downed = false }
end

--[[
    @summary  Revive a nearby downed teammate using one Bandage.
    @param    reviver  Player
    @param    target   Player
    @returns  boolean
]]
function PlayerLifeService:TryRevive(reviver: Player, target: Player): boolean
	if reviver == target or lifeStates[reviver] ~= "Alive" or lifeStates[target] ~= "Downed" then
		return false
	end
	if not runStateService:IsActive() or not runStateService:IsMember(reviver) or not runStateService:IsMember(target) then
		return false
	end
	local reviverRoot = reviver.Character and reviver.Character:FindFirstChild("HumanoidRootPart")
	local targetRoot = target.Character and target.Character:FindFirstChild("HumanoidRootPart")
	if not reviverRoot or not targetRoot or not reviverRoot:IsA("BasePart") or not targetRoot:IsA("BasePart") then
		return false
	end
	if (reviverRoot.Position - targetRoot.Position).Magnitude > RunConfig.ReviveRange then
		return false
	end
	if not inventoryService:ConsumeResource(reviver, "Bandage", 1) then
		return false
	end

	downTokens[target] = nil
	lifeStates[target] = "Alive"
	graceUntil[target] = os.clock() + RunConfig.ReviveGracePeriod
	local humanoid = target.Character and target.Character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.Health = math.clamp(RunConfig.ReviveHealth, 1, humanoid.MaxHealth)
	end
	clearDownedPresentation(target)
	runStateService:IncrementStat(reviver, "Revives", 1)
	PlayerLifeService.PlayerRevived:Fire(reviver, target)
	broadcastState(target, "Alive", { health = RunConfig.ReviveHealth, reviverUserId = reviver.UserId })
	for _, member in ipairs(runStateService:GetMembers()) do
		PlayerLifeService.Client.ReviveCompleted:Fire(member, target.UserId, reviver.UserId)
	end
	return true
end

--[[
    @summary  Return a client-safe snapshot of all run life states.
    @param    player  Player  -- injected by Knit
    @returns  table
]]
function PlayerLifeService.Client:GetSnapshot(player: Player): { [string]: any }
	local states = {}
	for member, state in pairs(lifeStates) do
		if member.Parent then
			states[tostring(member.UserId)] = state
		end
	end
	return { selfState = lifeStates[player] or "Lobby", states = states }
end

-- // INITIALIZATION // --

Players.CharacterAutoLoads = false

function PlayerLifeService:KnitStart()
	runStateService = Knit.GetService("RunStateService")
	inventoryService = Knit.GetService("InventoryService")
	spawnService = Knit.GetService("SpawnService")

	local function onPlayerAdded(player: Player)
		lifeStates[player] = "Lobby"
		player.CharacterAdded:Connect(function(character)
			configureCharacter(player, character)
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
		for _, player in ipairs(runStateService:GetMembers()) do
			lifeStates[player] = "Alive"
			if player.Character then
				configureCharacter(player, player.Character)
				player.Character:SetAttribute("LifeState", "Alive")
			end
			broadcastState(player, "Alive", {})
		end
	end)

	runStateService.RunCleaned:Connect(function()
		for _, player in ipairs(Players:GetPlayers()) do
			lifeStates[player] = "Lobby"
			downTokens[player] = nil
			graceUntil[player] = nil
			clearDownedPresentation(player)
			local character = player.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			if humanoid then
				humanoid.Health = humanoid.MaxHealth
				humanoid.WalkSpeed = 16
				humanoid.JumpPower = 50
				humanoid.AutoRotate = true
			end
			if character then
				character:SetAttribute("LifeState", "Lobby")
			end
			local backpack = player:FindFirstChild("Backpack")
			if backpack then
				backpack:ClearAllChildren()
			end
			local starterGear = player:FindFirstChild("StarterGear")
			if starterGear then
				starterGear:ClearAllChildren()
			end
			spawnService:ReturnToLobby(player)
			broadcastState(player, "Lobby", {})
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		lifeStates[player] = nil
		downTokens[player] = nil
		graceUntil[player] = nil
		savedMovement[player] = nil
		loadingCharacters[player] = nil
	end)
end

return PlayerLifeService
