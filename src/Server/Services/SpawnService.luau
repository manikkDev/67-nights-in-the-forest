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

-- ⚠️ TESTING ONLY — set to false before publishing to skip direct-to-game spawn
local TEST_SKIP_LOBBY = true

-- ⚠️ TESTING ONLY — give player 1000 HP and full wood on spawn for testing
local TEST_GIVE_RESOURCES = true

-- | State Management | --
local worldService: any = nil
local matchFlowService: any = nil
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
	print("[SpawnService] Teleported", player.Name, "to base-map")
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
			print("[SpawnService] Wired teleporter:", child.Name)
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

-- ⚠️ TESTING ONLY — grant 1000 HP and full wood for testing
local function grantTestResources(player: Player)
	if not TEST_GIVE_RESOURCES then return end

	-- Grant 200 HP (TEMP: normally 100)
	local character = player.Character
	if character then
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.MaxHealth = 200
			humanoid.Health = 200
		end
	end

	-- Grant full wood (fill to capacity)
	task.delay(2, function()
		local inventoryService = Knit.GetService("InventoryService")
		if inventoryService then
			local capacity = inventoryService:GetCapacity(player)
			inventoryService:AddResource(player, "Wood", capacity)
		end
	end)
end

local function autoSpawnPlayer(player: Player)
	if not TEST_SKIP_LOBBY then
		return
	end
	if spawnedPlayers[player] then
		return
	end
	-- Wait for character to be ready
	local character = player.Character
	if not character then
		local conn
		conn = player.CharacterAdded:Connect(function(char)
			conn:Disconnect()
			task.wait(0.5)
			SpawnService:SpawnPlayer(player)
			-- Start the match clock if not already running
			local timeService = Knit.GetService("TimeService")
			if timeService and not timeService:IsRunning() then
				timeService:StartMatch()
			end
			-- Give client Knit controllers time to connect signals before firing state change
			task.wait(1)
			-- Force night lighting for flashlight testing
			local Lighting = game:GetService("Lighting")
			Lighting.ClockTime = 0
			Lighting.Ambient = Color3.fromRGB(20, 22, 32)
			Lighting.OutdoorAmbient = Color3.fromRGB(12, 14, 20)
			Lighting.Brightness = 0.35
			-- Tell the client to skip lobby intro and unlock gameplay
			if matchFlowService then
				matchFlowService.Client.FlowStateChanged:Fire(player, "InGame")
			end
			grantTestResources(player)
		end)
		return
	end
	task.wait(0.5)
	SpawnService:SpawnPlayer(player)
	grantTestResources(player)
	-- Start the match clock if not already running
	local timeService = Knit.GetService("TimeService")
	if timeService and not timeService:IsRunning() then
		timeService:StartMatch()
	end
	-- Give client Knit controllers time to connect signals before firing state change
	task.wait(1)
	-- Force night lighting for flashlight testing
	local Lighting = game:GetService("Lighting")
	Lighting.ClockTime = 0
	Lighting.Ambient = Color3.fromRGB(20, 22, 32)
	Lighting.OutdoorAmbient = Color3.fromRGB(12, 14, 20)
	Lighting.Brightness = 0.35
	-- Tell the client to skip lobby intro and unlock gameplay
	if matchFlowService then
		matchFlowService.Client.FlowStateChanged:Fire(player, "InGame")
	end
	grantTestResources(player)
end

function SpawnService:KnitStart()
	worldService = Knit.GetService("WorldService")
	matchFlowService = Knit.GetService("MatchFlowService")
	wireTeleporters()

	if TEST_SKIP_LOBBY then
		print("[SpawnService] TEST_SKIP_LOBBY is ON — players will spawn directly in base-map")
		-- Give the world a moment to load before auto-spawning
		task.delay(1, function()
			for _, player in ipairs(Players:GetPlayers()) do
				autoSpawnPlayer(player)
			end
		end)
		Players.PlayerAdded:Connect(autoSpawnPlayer)
	end
end

Players.PlayerRemoving:Connect(function(player)
	spawnedPlayers[player] = nil
	teleportCooldowns[player] = nil
end)

return SpawnService
