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
local Workspace = game:GetService("Workspace")

-- | Modules | --
local Knit = require(ReplicatedStorage.Packages.Knit)

-- | Constants | --
local SPAWN_RADIUS = 12
local SPAWN_HEIGHT = 5
local TELEPORT_COOLDOWN = 3

-- | Objects | --
local SpawnService = Knit.CreateService({
	Name = "SpawnService",
	Client = {
		RequestSpawn = Knit.CreateSignal(),
	},
})

-- | State | --
local worldService: any? = nil
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

	local campfireCFrame = worldService:GetCampfireCFrame()
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
end

--[[
    @summary  Wire all teleporter EnterParts in the lobby-map for touch teleport.
    @desc    Finds Teleporter1/2/3 models in the lobby-map and connects
             Touched events on their EnterPart children.  When a player
             touches an EnterPart, they are teleported to the base-map.
]]
local function wireTeleporters()
	local lobbyMap = worldService:GetLobbyMap()
	if not lobbyMap then
		task.defer(wireTeleporters)
		return
	end

	for _, child in ipairs(lobbyMap:GetChildren()) do
		if child:IsA("Model") and child.Name:match("^Teleporter%d") then
			local enterPart = child:FindFirstChild("EnterPart", true)
			if enterPart and enterPart:IsA("BasePart") then
				enterPart.Touched:Connect(function(hit)
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

					SpawnService:SpawnPlayer(player)
				end)
				print("[SpawnService] Wired teleporter:", child.Name)
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
	self.Server:SpawnPlayer(player)
end

-- // INITIALIZATION // --

function SpawnService:KnitStart()
	worldService = Knit.GetService("WorldService")
	wireTeleporters()
end

return SpawnService
