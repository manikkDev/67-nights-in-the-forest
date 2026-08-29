--[[
    @file    ProceduralAnimController.luau
    @author  manik
    @date    2025

    @summary
    Subtle idle-breathing motion for the local player's camera.

    @description
    Applies a small sine-wave offset to Humanoid.CameraOffset while
    the character is idle (not moving, not chopping/attacking), so
    standing still doesn't read as a frozen pose.  Disabled while
    another controller is actively driving CameraOffset (chop/combat
    shake), by only nudging when the offset is already near zero.

    @exports
    - ProceduralAnimController (Knit Controller)
]]

-- // VARIABLES // --

-- | Services | --
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- | Modules | --
local Knit = require(ReplicatedStorage.Packages.Knit)
local ServerRole = require(ReplicatedStorage.Shared.ServerRole)
local Janitor = require(ReplicatedStorage.Packages.Janitor)

-- | Objects | --
local ProceduralAnimController = Knit.CreateController({
	Name = "ProceduralAnimController",
})

-- | Configuration | --
local BREATH_FREQUENCY = 1.6
local BREATH_AMPLITUDE = 0.035
local MOVE_SPEED_THRESHOLD = 1

-- | State Management | --
local janitor = Janitor.new()
local gameStateController: any = nil

-- // FUNCTIONS // --

--[[
    @summary  Heartbeat-driven idle breathing offset for the local character.
]]
local function onHeartbeat()
	if not gameStateController or not gameStateController:IsInGame() then
		return
	end

	local character = Players.LocalPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not rootPart or not rootPart:IsA("BasePart") then
		return
	end

	if rootPart.AssemblyLinearVelocity.Magnitude > MOVE_SPEED_THRESHOLD then
		return
	end

	if humanoid.CameraOffset.Magnitude > BREATH_AMPLITUDE * 1.5 then
		return
	end

	local breath = math.sin(os.clock() * BREATH_FREQUENCY * math.pi) * BREATH_AMPLITUDE
	humanoid.CameraOffset = Vector3.new(0, breath, 0)
end

-- // INITIALIZATION // --

function ProceduralAnimController:KnitStart()
	if not ServerRole.IsGameServer() then return end
	gameStateController = Knit.GetController("GameStateController")
	janitor:Add(RunService.Heartbeat:Connect(onHeartbeat), "Disconnect")
end

return ProceduralAnimController
