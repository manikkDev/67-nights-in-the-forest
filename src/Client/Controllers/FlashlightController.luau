--[[
    @file    FlashlightController.luau
    @author  manik
    @date    2025

    @summary
    Client-side flashlight toggle with UI and beam-state reporting.

    @description
    Toggles the equipped Flashlight's SpotLight/Sound locally for
    instant feedback, and reports the on/off state to FlashlightService
    so the server can independently validate beam alignment against
    the Deer/Ram Monster stalkers before applying any stun.

    Shows a small bottom-center indicator whenever the flashlight is
    in the player inventory so they always know the toggle state.

    @exports
    - FlashlightController (Knit Controller)
]]

-- // VARIABLES // --

-- | Services | --
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

-- | Modules | --
local Knit = require(ReplicatedStorage.Packages.Knit)
local Janitor = require(ReplicatedStorage.Packages.Janitor)

-- | Objects | --
local FlashlightController = Knit.CreateController({
	Name = "FlashlightController",
})

-- | Configuration | --
local FLASHLIGHT_TOOL_NAME = "Flashlight"
local UI_ICON_SIZE = 44
local UI_ICON_MARGIN = 8

-- | State Management | --
local janitor = Janitor.new()
local toolJanitor = Janitor.new()
local charJanitor = Janitor.new()
local gameStateController: any = nil
local flashlightService: any = nil
local beamOn = false
local indicatorGui: ScreenGui? = nil
local indicatorFrame: Frame? = nil
local indicatorIcon: TextLabel? = nil
local indicatorLabel: TextLabel? = nil

-- // FUNCTIONS // --

--[[
    @summary  Update the on-screen flashlight indicator.
    @param    lit  boolean
]]
local function updateIndicator(lit: boolean)
	beamOn = lit
	if not indicatorFrame then
		return
	end

	if lit then
		indicatorFrame.BackgroundColor3 = Color3.fromRGB(60, 160, 255)
		indicatorIcon.Text = "🔦"
		indicatorLabel.Text = "ON"
		indicatorLabel.TextColor3 = Color3.fromRGB(200, 235, 255)
		TweenService:Create(indicatorFrame, TweenInfo.new(0.2), {
			BackgroundTransparency = 0.1,
		}):Play()
	else
		indicatorFrame.BackgroundColor3 = Color3.fromRGB(50, 50, 55)
		indicatorIcon.Text = "🔦"
		indicatorLabel.Text = "OFF"
		indicatorLabel.TextColor3 = Color3.fromRGB(160, 160, 170)
		TweenService:Create(indicatorFrame, TweenInfo.new(0.2), {
			BackgroundTransparency = 0.2,
		}):Play()
	end
end

--[[
    @summary  Report the local player current beam state to the server.
    @param    isActive  boolean
]]
local function reportBeamState(isActive: boolean)
	beamOn = isActive
	if flashlightService then
		flashlightService.SetBeamActive(isActive)
	end
	updateIndicator(isActive)
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
    @summary  Turn the flashlight beam off.
    @param    tool  Tool
]]
local function turnOff(tool: Tool)
	local handle = tool:FindFirstChild("Handle")
	if not handle then
		return
	end
	local spotLight = handle:FindFirstChildOfClass("SpotLight")
	if spotLight then
		spotLight.Enabled = false
	end
	reportBeamState(false)
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
		turnOff(tool)
	end), "Disconnect")
end

--[[
    @summary  Watch the player Backpack and Character for the
              Flashlight tool being equipped.
    @param    player  Player
]]
local function watchForFlashlight(player: Player)
	local function checkCharacter(character: Model)
		toolJanitor:Cleanup()
		charJanitor:Cleanup()

		local tool = character:FindFirstChild(FLASHLIGHT_TOOL_NAME)
		if tool and tool:IsA("Tool") then
			wireTool(tool)
			-- Pick up the current state if it already on
			local handle = tool:FindFirstChild("Handle")
			local spotLight = handle and handle:FindFirstChildOfClass("SpotLight")
			if spotLight then
				reportBeamState(spotLight.Enabled)
			end
		end

		charJanitor:Add(character.ChildAdded:Connect(function(child)
			if child:IsA("Tool") and child.Name == FLASHLIGHT_TOOL_NAME then
				wireTool(child)
			end
		end), "Disconnect")
		charJanitor:Add(character.ChildRemoved:Connect(function(child)
			if child:IsA("Tool") and child.Name == FLASHLIGHT_TOOL_NAME then
				reportBeamState(false)
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

--[[
    @summary  Build the on-screen flashlight indicator UI.
]]
local function buildIndicator()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

	local gui = Instance.new("ScreenGui")
	gui.Name = "FlashlightIndicator"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false
	gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets

	local frame = Instance.new("Frame")
	frame.Name = "FlashlightFrame"
	frame.AnchorPoint = Vector2.new(0.5, 1)
	frame.Position = UDim2.new(0.5, 0, 1, -80)
	frame.Size = UDim2.new(0, UI_ICON_SIZE + UI_ICON_MARGIN * 2, 0, UI_ICON_SIZE + UI_ICON_MARGIN * 2 + 18)
	frame.BackgroundColor3 = Color3.fromRGB(50, 50, 55)
	frame.BackgroundTransparency = 0.2
	frame.BorderSizePixel = 0
	frame.Visible = false
	frame.Parent = gui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = frame

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(80, 80, 90)
	stroke.Thickness = 1.5
	stroke.Transparency = 0.4
	stroke.Parent = frame

	local icon = Instance.new("TextLabel")
	icon.Name = "Icon"
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.new(0.5, 0, 0.5, -9)
	icon.Size = UDim2.new(0, UI_ICON_SIZE, 0, UI_ICON_SIZE)
	icon.BackgroundTransparency = 1
	icon.Text = "🔦"
	icon.TextSize = 28
	icon.Font = Enum.Font.GothamBold
	icon.Parent = frame

	local label = Instance.new("TextLabel")
	label.Name = "StatusLabel"
	label.AnchorPoint = Vector2.new(0.5, 0)
	label.Position = UDim2.new(0.5, 0, 1, -16)
	label.Size = UDim2.new(0, 60, 0, 14)
	label.BackgroundTransparency = 1
	label.Text = "OFF"
	label.TextColor3 = Color3.fromRGB(160, 160, 170)
	label.Font = Enum.Font.GothamBold
	label.TextSize = 11
	label.Parent = frame

	indicatorGui = gui
	indicatorFrame = frame
	indicatorIcon = icon
	indicatorLabel = label

	gui.Parent = playerGui
end

--[[
    @summary  Show or hide the indicator based on whether the
              flashlight is in the player inventory.
]]
local function refreshIndicatorVisibility()
	if not indicatorFrame then
		return
	end

	local character = Players.LocalPlayer.Character
	local backpack = Players.LocalPlayer:FindFirstChild("Backpack")

	local hasFlashlight = false
	if character and character:FindFirstChild(FLASHLIGHT_TOOL_NAME) then
		hasFlashlight = true
	elseif backpack and backpack:FindFirstChild(FLASHLIGHT_TOOL_NAME) then
		hasFlashlight = true
	end

	indicatorFrame.Visible = hasFlashlight
end

-- // INITIALIZATION // --

function FlashlightController:KnitStart()
	gameStateController = Knit.GetController("GameStateController")
	flashlightService = Knit.GetService("FlashlightService")

	local player = Players.LocalPlayer

	buildIndicator()

	local function onGameStarted()
		watchForFlashlight(player)
		-- Check periodically if the flashlight is in inventory
		task.spawn(function()
			while true do
				refreshIndicatorVisibility()
				task.wait(1)
			end
		end)
	end

	if gameStateController and gameStateController:IsInGame() then
		onGameStarted()
	else
		if gameStateController then
			gameStateController.GameStarted:Connect(onGameStarted)
		end
	end

	print("[FlashlightController] Initialised — flashlight toggle/indicator active")
end

return FlashlightController
