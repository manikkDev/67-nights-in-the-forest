--[[
    @file    SpawnService.luau
    @author  manik
    @date    2025

    @summary
    Server-authoritative lobby-to-game teleportation.

    @description
    Wires the lobby-map teleporter pads (Teleporter1/2/3 EnterPart)
    to teleport players to the base-map Campfire on touch.  Also
    exposes a Knit Remote for programmatic spawn requests.

    @exports
    - Knit Remote: RequestSpawn  -> void  (client -> server)
    - SpawnService:SpawnPlayer(player)    (server only)
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
local SpawnService = Knit.CreateService({
	Name = "SpawnService",
	Client = {
		RequestSpawn = Knit.CreateSignal(),
		PlayerSpawned = Knit.CreateSignal(),
	},
})

SpawnService.PlayerSpawned = Signal.new()

-- | Configuration | --
local SPAWN_RADIUS = 15
local SPAWN_HEIGHT = 5
local TELEPORT_COOLDOWN = 5

-- | State Management | --
local worldService: any = nil
local matchFlowService: any = nil
local runStateService: any = nil
local spawnedPlayers: { [Player]: boolean } = {}
local teleportCooldowns: { [Player]: number } = {}

-- // FUNCTIONS // --

--[[
    @summary  Teleport a player's character to a random point around the Campfire.
    @desc    Uses math.random so players do not stack on each other.
             Server-authoritative — the client cannot choose a position.
    @param   player  Player  -- the Roblox player
]]
function SpawnService:SpawnPlayer(player: Player)
	if spawnedPlayers[player] then
		return
	end

	local character = player.Character
	if not character then
		return
	end

	local primaryPart = character:FindFirstChild("HumanoidRootPart") or character.PrimaryPart
	if not primaryPart then
		return
	end

	local campfireCFrame = worldService and worldService:GetCampfireCFrame() or nil
	if not campfireCFrame then
		warn("[SpawnService] Campfire CFrame not available")
		return
	end

	local angle = math.random() * math.pi * 2
	local offsetX = math.cos(angle) * SPAWN_RADIUS
	local offsetZ = math.sin(angle) * SPAWN_RADIUS

	local targetCFrame = campfireCFrame * CFrame.new(offsetX, SPAWN_HEIGHT, offsetZ)
	primaryPart.CFrame = targetCFrame

	spawnedPlayers[player] = true
	SpawnService.Client.PlayerSpawned:Fire(player)
	SpawnService.PlayerSpawned:Fire(player)
end

--[[
    @summary  Wire all teleporter EnterParts in the lobby-map for touch teleport.
    @desc    Finds Teleporter1/2/3 models in the lobby-map and connects
             Touched events on their EnterPart children.  When a player
             touches an EnterPart, they are teleported to the base-map.
]]
local function wireTeleporters()
	if not worldService then
		task.defer(wireTeleporters)
		return
	end
	local lobbyMap = worldService:GetLobbyMap()
	if not lobbyMap then
		task.defer(wireTeleporters)
		return
	end

	for _, child in ipairs(lobbyMap:GetChildren()) do
		if child:IsA("Model") and child.Name:match("^Teleporter%d") then
			-- Connect Touched on ALL EnterPart children (each teleporter has 4)
			for _, desc in ipairs(child:GetDescendants()) do
				if desc.Name == "EnterPart" and desc:IsA("BasePart") then
					desc.Touched:Connect(function(hit)
						local character = hit:FindFirstAncestorOfClass("Model")
						if not character then return end
						local player = Players:GetPlayerFromCharacter(character)
						if not player then return end
						if spawnedPlayers[player] then return end

						local now = os.clock()
						if teleportCooldowns[player] and (now - teleportCooldowns[player]) < TELEPORT_COOLDOWN then
							return
						end
						teleportCooldowns[player] = now

						-- Move the player inside the teleporter box instantly before the UI opens.
						local teleporter = desc:FindFirstAncestorOfClass("Model")
						local destination = teleporter and teleporter:FindFirstChild("TeleportHere")
						if destination and destination:IsA("BasePart") then
							local hrp = character:FindFirstChild("HumanoidRootPart") or character.PrimaryPart
							if hrp then
								hrp.CFrame = destination.CFrame * CFrame.new(0, 3, 0)
								local humanoid = character:FindFirstChildOfClass("Humanoid")
								if humanoid then
									humanoid:Move(Vector3.new(), true)
								end
							end
						end

						if matchFlowService then
							matchFlowService:EnterWaiting(player)
						else
							SpawnService:SpawnPlayer(player)
						end
					end)
				end
			end
		end
	end
end

--[[
    @summary  Client-facing remote requesting teleportation to the game map.
    @desc    The server validates that the player has not already spawned
             and that a character exists before teleporting.
    @param   player  Player  -- injected by Knit
]]
function SpawnService.Client:RequestSpawn(player: Player)
	if matchFlowService then
		matchFlowService:EnterWaiting(player)
	else
		self.Server:SpawnPlayer(player)
	end
end

--[[
    @summary  Check whether a player has been teleported to the game map.
    @param    player  Player
    @returns  boolean
]]
function SpawnService:IsPlayerSpawned(player: Player): boolean
	return spawnedPlayers[player] == true
end

-- // INITIALIZATION // --

--[[
    @summary  Clear the spawned flag so a player can join the next run.
    @param    player  Player
]]
function SpawnService:ResetPlayer(player: Player)
	spawnedPlayers[player] = nil
	teleportCooldowns[player] = nil
end

--[[
    @summary  Move an existing character back to a safe lobby position.
    @param    player  Player
    @returns  boolean
]]
function SpawnService:ReturnToLobby(player: Player): boolean
	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	local lobbyMap = worldService and worldService:GetLobbyMap()
	if not rootPart or not rootPart:IsA("BasePart") or not lobbyMap then
		return false
	end
	local destination = lobbyMap:FindFirstChild("TeleportHere", true)
	local targetCFrame = if destination and destination:IsA("BasePart")
		then destination.CFrame * CFrame.new(0, 4, 0)
		else lobbyMap:GetPivot() * CFrame.new(0, 8, 0)
	rootPart.Anchored = false
	rootPart.CFrame = targetCFrame
	self:ResetPlayer(player)
	return true
end

--[[
    @summary  Studio-only shortcut that skips the lobby and starts a run.
    @param    player  Player
]]
local function autoSpawnPlayer(player: Player)
	if not RunConfig.IsTestEnabled("SkipLobby") then
		return
	end
	if spawnedPlayers[player] then
		return
	end

	if not player.Character then
		player.CharacterAdded:Wait()
	end
	task.wait(0.5)

	if not player.Parent then
		return
	end

	if runStateService and runStateService:GetPhase() == "Lobby" then
		local startedRunId = nil
		for _ = 1, 30 do
			startedRunId = runStateService:StartRun({ player })
			if startedRunId or not player.Parent or runStateService:GetPhase() ~= "Lobby" then
				break
			end
			task.wait(0.5)
		end
		if not startedRunId and runStateService:GetPhase() == "Lobby" then
			warn("[SpawnService] Studio test could not start because the profile was not ready")
			return
		end
	end
	SpawnService:SpawnPlayer(player)

	local timeService = Knit.GetService("TimeService")
	if timeService and not timeService:IsRunning() then
		timeService:StartMatch()
	end

	task.wait(1)

	if not player.Parent then
		return
	end

	if RunConfig.IsTestEnabled("ForceNight") then
		local Lighting = game:GetService("Lighting")
		Lighting.ClockTime = 0
		Lighting.Ambient = Color3.fromRGB(20, 22, 32)
		Lighting.OutdoorAmbient = Color3.fromRGB(12, 14, 20)
		Lighting.Brightness = 0.35
	end

	if matchFlowService then
		matchFlowService.Client.FlowStateChanged:Fire(player, "InGame")
	end
end

function SpawnService:KnitStart()
	worldService = Knit.GetService("WorldService")
	matchFlowService = Knit.GetService("MatchFlowService")
	runStateService = Knit.GetService("RunStateService")
	wireTeleporters()

	if RunConfig.IsTestEnabled("SkipLobby") then
		warn("[SpawnService] Studio test: SkipLobby is enabled")
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
	teleportCooldowns[player] = nil
end)

return SpawnService
