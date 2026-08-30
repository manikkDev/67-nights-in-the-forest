--[[
    @file    SpawnService.luau
    @author  manik
    @date    2025

    @summary
    Server-authoritative queue entry and run-member character spawning.

    @description
    Teleporter1/2/3 touches enter isolated MatchFlow queues. Only current run
    members may spawn at the campfire. This service owns fresh character loads,
    deterministic party spacing, and deterministic lobby returns.
]]

-- // VARIABLES // --

-- | Services | --
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- | Modules | --
local Knit = require(ReplicatedStorage.Packages.Knit)
local Signal = require(ReplicatedStorage.Packages.Signal)
local RunConfig = require(ReplicatedStorage.Shared.RunConfig)
local Constants = require(ReplicatedStorage.Shared.Constants)

-- | Objects | --
local SpawnService = Knit.CreateService({
	Name = "SpawnService",
	Client = {
		RequestSpawn = Knit.CreateSignal(),
		PlayerSpawned = Knit.CreateSignal(),
	},
})

SpawnService.PlayerSpawned = Signal.new()

-- | Configuration | --
local SPAWN_RADIUS = 12
local SPAWN_HEIGHT = 5
local TOUCH_COOLDOWN = 1
local CHARACTER_TIMEOUT = 12

-- | State Management | --
local worldService: any = nil
local matchFlowService: any = nil
local runStateService: any = nil
local spawnedPlayers: { [Player]: boolean } = {}
local spawningPlayers: { [Player]: boolean } = {}
local touchCooldowns: { [Player]: number } = {}

-- // FUNCTIONS // --

-- | Character Safety | --
local function loadFreshCharacter(player: Player): Model?
	if player.Parent ~= Players then
		return nil
	end
	local ok, err = pcall(function()
		player:LoadCharacter()
	end)
	if not ok then
		warn("[SpawnService] Character reload failed for", player.Name, err)
	end
	local deadline = os.clock() + CHARACTER_TIMEOUT
	while player.Parent == Players and os.clock() < deadline do
		local character = player.Character
		if character and character.Parent and character:FindFirstChild("HumanoidRootPart") then
			return character
		end
		task.wait(0.1)
	end
	return nil
end

local function queueAllowed(queueId: string): boolean
	for _, allowed in ipairs(Constants.PARTY_QUEUE_IDS or {}) do
		if queueId == allowed then
			return true
		end
	end
	return false
end

local function deterministicLobbyCFrame(): CFrame?
	local lobbyMap = worldService and worldService:GetLobbyMap()
	if not lobbyMap then
		return nil
	end
	for _, name in ipairs({ "LobbySpawn", "SpawnLocation", "TeleportHere" }) do
		local destination = lobbyMap:FindFirstChild(name, true)
		if destination and destination:IsA("BasePart") then
			return destination.CFrame * CFrame.new(0, 4, 0)
		end
	end
	return lobbyMap:GetPivot() * CFrame.new(0, 8, 0)
end

-- | Run Spawning | --
function SpawnService:SpawnPlayer(player: Player, slot: number?, partySize: number?): boolean
	if spawnedPlayers[player] then
		return true
	end
	if spawningPlayers[player] or not runStateService or not runStateService:IsMember(player) then
		return false
	end
	spawningPlayers[player] = true

	local campfireCFrame = worldService and worldService:GetCampfireCFrame()
	if not campfireCFrame then
		spawningPlayers[player] = nil
		warn("[SpawnService] Campfire CFrame not available")
		return false
	end
	local character = loadFreshCharacter(player)
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	if not rootPart or not rootPart:IsA("BasePart") or not runStateService:IsMember(player) then
		spawningPlayers[player] = nil
		return false
	end

	local count = math.max(1, partySize or 1)
	local index = math.clamp(slot or 1, 1, count)
	local angle = ((index - 1) / count) * math.pi * 2
	local target = campfireCFrame * CFrame.new(math.cos(angle) * SPAWN_RADIUS, SPAWN_HEIGHT, math.sin(angle) * SPAWN_RADIUS)
	rootPart.Anchored = false
	character:PivotTo(target)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid:Move(Vector3.zero, false)
	end

	spawningPlayers[player] = nil
	spawnedPlayers[player] = true
	SpawnService.Client.PlayerSpawned:Fire(player)
	SpawnService.PlayerSpawned:Fire(player)
	return true
end

function SpawnService:SpawnParty(participants: { Player }): boolean
	local completed = 0
	local expected = #participants
	for index, player in ipairs(participants) do
		task.spawn(function()
			self:SpawnPlayer(player, index, expected)
			completed += 1
		end)
	end
	local deadline = os.clock() + CHARACTER_TIMEOUT + 2
	while completed < expected and os.clock() < deadline do
		task.wait(0.1)
	end
	return completed == expected
end

function SpawnService:IsPlayerSpawned(player: Player): boolean
	return spawnedPlayers[player] == true
end

--[[
    @summary  Move an existing revivable character to a safe campfire position.
    @desc     Unlike SpawnPlayer, this deliberately preserves the in-world body
              and does not reload the character.
]]
function SpawnService:ReviveAtCampfire(player: Player): boolean
	if player.Parent ~= Players or not runStateService or not runStateService:IsActive() or not runStateService:IsMember(player) then
		return false
	end
	local campfireCFrame = worldService and worldService:GetCampfireCFrame()
	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	if not campfireCFrame or not character or not rootPart or not rootPart:IsA("BasePart") then
		return false
	end
	for _, descendant in ipairs(character:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Anchored = false
			descendant.AssemblyLinearVelocity = Vector3.zero
			descendant.AssemblyAngularVelocity = Vector3.zero
		end
	end
	character:PivotTo(campfireCFrame * CFrame.new(0, SPAWN_HEIGHT, SPAWN_RADIUS))
	return true
end

function SpawnService:ResetPlayer(player: Player)
	spawnedPlayers[player] = nil
	spawningPlayers[player] = nil
	touchCooldowns[player] = nil
end

function SpawnService:ReturnToLobby(player: Player): boolean
	local target = deterministicLobbyCFrame()
	if not target or player.Parent ~= Players then
		return false
	end
	local character = loadFreshCharacter(player)
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	if not rootPart or not rootPart:IsA("BasePart") then
		return false
	end
	rootPart.Anchored = false
	character:PivotTo(target)
	self:ResetPlayer(player)
	return true
end

-- | Teleporter Queues | --
local function wireTeleporters()
	local lobbyMap = worldService and worldService:GetLobbyMap()
	if not lobbyMap then
		task.delay(1, wireTeleporters)
		return
	end
	for _, teleporter in ipairs(lobbyMap:GetChildren()) do
		if teleporter:IsA("Model") and queueAllowed(teleporter.Name) then
			local queueId = teleporter.Name
			for _, descendant in ipairs(teleporter:GetDescendants()) do
				if descendant.Name == "EnterPart" and descendant:IsA("BasePart") then
					descendant.Touched:Connect(function(hit)
						local character = hit:FindFirstAncestorOfClass("Model")
						local player = character and Players:GetPlayerFromCharacter(character)
						if not player or spawnedPlayers[player] then
							return
						end
						local now = os.clock()
						if now - (touchCooldowns[player] or 0) < TOUCH_COOLDOWN then
							return
						end
						touchCooldowns[player] = now

						local destination = teleporter:FindFirstChild("TeleportHere")
						local rootPart = character:FindFirstChild("HumanoidRootPart")
						if destination and destination:IsA("BasePart") and rootPart and rootPart:IsA("BasePart") then
							character:PivotTo(destination.CFrame * CFrame.new(0, 3, 0))
						end
						if matchFlowService then
							matchFlowService:EnterWaiting(player, queueId)
						end
					end)
				end
			end
		end
	end
end

function SpawnService.Client:RequestSpawn(player: Player)
	self.Server:SpawnPlayer(player)
end

-- | Studio Shortcut | --
local function autoSpawnPlayer(player: Player)
	if not RunConfig.IsTestEnabled("SkipLobby") or spawnedPlayers[player] then
		return
	end
	for _ = 1, 30 do
		if not player.Parent then
			return
		end
		if runStateService:GetPhase() ~= "Lobby" then
			break
		end
		if runStateService:StartRun({ player }) then
			break
		end
		task.wait(0.5)
	end
	SpawnService:SpawnPlayer(player)
	local timeService = Knit.GetService("TimeService")
	if timeService and not timeService:IsRunning() then
		timeService:StartMatch()
	end
	if matchFlowService then
		matchFlowService.Client.FlowStateChanged:Fire(player, "InGame")
	end
end

-- // INITIALIZATION // --

function SpawnService:KnitStart()
	worldService = Knit.GetService("WorldService")
	matchFlowService = Knit.GetService("MatchFlowService")
	runStateService = Knit.GetService("RunStateService")
	wireTeleporters()

	if RunConfig.IsTestEnabled("SkipLobby") then
		task.delay(1, function()
			for _, player in ipairs(Players:GetPlayers()) do
				task.spawn(autoSpawnPlayer, player)
			end
		end)
		Players.PlayerAdded:Connect(function(player)
			task.spawn(autoSpawnPlayer, player)
		end)
	end
end

Players.PlayerRemoving:Connect(function(player)
	spawnedPlayers[player] = nil
	spawningPlayers[player] = nil
	touchCooldowns[player] = nil
end)

return SpawnService
