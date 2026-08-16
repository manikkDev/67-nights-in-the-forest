--[[
    @file    FlashlightController.luau
    @author  manik
    @date    2025

    @summary
    Client-side flashlight toggle and beam-state reporting.

    @description
    Toggles the equipped Flashlight's SpotLight/Sound locally for
    instant feedback, and reports the on/off state to FlashlightService
    so the server can independently validate beam alignment against
    the Deer/Ram Monster stalkers before applying any stun.

    @exports
    - FlashlightController (Knit Controller)
]]

-- // VARIABLES // --

-- | Services | --
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- | Modules | --
local Knit = require(ReplicatedStorage.Packages.Knit)
local Janitor = require(ReplicatedStorage.Packages.Janitor)

-- | Objects | --
local FlashlightController = Knit.CreateController({
	Name = "FlashlightController",
})

-- | Configuration | --
local FLASHLIGHT_TOOL_NAME = "Flashlight"

-- | State Management | --
local janitor = Janitor.new()
local toolJanitor = Janitor.new()
local charJanitor = Janitor.new()
local gameStateController: any = nil
local flashlightService: any = nil
local beamOn = false

-- // FUNCTIONS // --

--[[
    @summary  Report the local player's current beam state to the server.
    @param    isActive  boolean
]]
local function reportBeamState(isActive: boolean)
	beamOn = isActive
	if flashlightService then
		flashlightService.SetBeamActive(isActive)
	end
end

--[[
    @summary  Toggle the SpotLight/Sound on an equipped Flashlight tool.
    @param    tool  Tool
]]
local function toggleBeam(tool: Tool)
	local handle = tool:FindFirstChild("Handle")
	if not handle then
		return
	end
	local spotLight = handle:FindFirstChildOfClass("SpotLight")
	local sound = handle:FindFirstChildOfClass("Sound")
	if spotLight then
		spotLight.Enabled = not spotLight.Enabled
		reportBeamState(spotLight.Enabled)
	end
	if sound then
		sound:Play()
	end
end

--[[
    @summary  Wire Tool.Activated on the given Flashlight tool.
    @param    tool  Tool
]]
local function wireTool(tool: Tool)
	toolJanitor:Cleanup()
	toolJanitor:Add(tool.Activated:Connect(function()
		if not gameStateController or not gameStateController:IsInGame() then
			return
		end
		toggleBeam(tool)
	end), "Disconnect")
	toolJanitor:Add(tool.Unequipped:Connect(function()
		reportBeamState(false)
	end), "Disconnect")
end

--[[
    @summary  Watch the player's Backpack and Character for the
              Flashlight tool being equipped.
    @param    player  Player
]]
local function watchForFlashlight(player: Player)
	local function checkCharacter(character: Model)
		toolJanitor:Cleanup()
		charJanitor:Cleanup()
		reportBeamState(false)

		local tool = character:FindFirstChild(FLASHLIGHT_TOOL_NAME)
		if tool and tool:IsA("Tool") then
			wireTool(tool)
		end

		charJanitor:Add(character.ChildAdded:Connect(function(child)
			if child:IsA("Tool") and child.Name == FLASHLIGHT_TOOL_NAME then
				wireTool(child)
			end
		end), "Disconnect")
	end

	janitor:Cleanup()
	janitor:Add(player.CharacterAdded:Connect(checkCharacter), "Disconnect")
	janitor:Add(player.CharacterRemoving:Connect(function()
		reportBeamState(false)
	end), "Disconnect")

	if player.Character then
		checkCharacter(player.Character)
	end
end

-- // INITIALIZATION // --

function FlashlightController:KnitStart()
	gameStateController = Knit.GetController("GameStateController")
	flashlightService = Knit.GetService("FlashlightService")

	local player = Players.LocalPlayer

	local function onGameStarted()
		watchForFlashlight(player)
	end

	if gameStateController and gameStateController:IsInGame() then
		onGameStarted()
	else
		if gameStateController then
			gameStateController.GameStarted:Connect(onGameStarted)
		end
	end

	print("[FlashlightController] Initialised — flashlight toggle/beam report active")
end

return FlashlightController
