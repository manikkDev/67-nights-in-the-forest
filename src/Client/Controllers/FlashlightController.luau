--[[
    @file    FlashlightController.luau
    @author  manik
    @date    2025

    @summary
    Client-side flashlight toggle and battery HUD.

    @description
    Toggles the equipped Flashlight's SpotLight/Sound locally and
    reports the beam state to the server. Listens to FlashlightService
    for battery updates and displays a compact bottom-right panel with:

      - Flashlight ON/OFF indicator
      - Battery percentage and bar
      - Low-battery warning when below 20%
      - Beam state icon

    The panel only appears while the player owns a Flashlight.

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
local PANEL_WIDTH = 160
local PANEL_HEIGHT = 58
local PANEL_MARGIN = 12
local LOW_BATTERY_THRESHOLD = 20
local WARNING_FLASH_INTERVAL = 0.35

-- | State Management | --
local janitor = Janitor.new()
local toolJanitor = Janitor.new()
local charJanitor = Janitor.new()
local gameStateController: any = nil
local flashlightService: any = nil

local beamOn = false
local batteryPercent = 100
local lowBatteryWarning = false

local panelGui: ScreenGui? = nil
local panelFrame: Frame? = nil
local batteryBar: Frame? = nil
local batteryFill: Frame? = nil
local batteryText: TextLabel? = nil
local statusText: TextLabel? = nil
local warningLabel: TextLabel? = nil
local warningThread: thread? = nil
local refreshPanelVisibility: () -> ()

-- // FUNCTIONS // --

--[[
    @summary  Return the equipped Flashlight Tool, if any.
    @returns  Tool?
]]
local function getEquippedFlashlight(): Tool?
	local character = Players.LocalPlayer.Character
	if not character then
		return nil
	end
	local tool = character:FindFirstChild(FLASHLIGHT_TOOL_NAME)
	if tool and tool:IsA("Tool") then
		return tool
	end
	return nil
end

--[[
    @summary  Turn the flashlight visual beam off.
    @param    tool  Tool
]]
local function turnOffVisuals(tool: Tool)
	local handle = tool:FindFirstChild("Handle")
	if not handle then
		return
	end
	local spotLight = handle:FindFirstChildOfClass("SpotLight")
	if spotLight then
		spotLight.Enabled = false
	end
	local fillLight = handle:FindFirstChild("FillLight")
	if fillLight and fillLight:IsA("PointLight") then
		fillLight.Enabled = false
	end
end

--[[
    @summary  Get the color the battery bar should be at a given percent.
    @param    percent  number
    @returns  Color3
]]
local function batteryColor(percent: number): Color3
	if percent <= 20 then
		return Color3.fromRGB(255, 60, 60)
	elseif percent <= 50 then
		return Color3.fromRGB(255, 180, 40)
	end
	return Color3.fromRGB(60, 220, 120)
end

--[[
    @summary  Stop the low-battery warning pulse.
]]
local function stopWarningFlash()
	lowBatteryWarning = false
	warningThread = nil
	if warningLabel then
		warningLabel.TextTransparency = 0
	end
end

--[[
    @summary  Pulse the low-battery warning text.
]]
local function startWarningFlash()
	if warningThread then
		return
	end
	lowBatteryWarning = true
	warningThread = task.spawn(function()
		while lowBatteryWarning and warningLabel do
			TweenService:Create(warningLabel, TweenInfo.new(WARNING_FLASH_INTERVAL, Enum.EasingStyle.Sine), {
				TextTransparency = 0.3,
			}):Play()
			task.wait(WARNING_FLASH_INTERVAL)
			if not lowBatteryWarning or not warningLabel then
				break
			end
			TweenService:Create(warningLabel, TweenInfo.new(WARNING_FLASH_INTERVAL, Enum.EasingStyle.Sine), {
				TextTransparency = 1,
			}):Play()
			task.wait(WARNING_FLASH_INTERVAL)
		end
		warningThread = nil
	end)
end

--[[
    @summary  Update the on-screen battery bar and percentage text.
]]
local function updateBatteryUI()
	if not panelFrame or not batteryBar or not batteryFill or not batteryText or not statusText or not warningLabel then
		return
	end

	batteryPercent = if batteryPercent then batteryPercent else 0
	beamOn = if beamOn == true then true else false

	batteryText.Text = string.format("%d%%", batteryPercent)
	statusText.Text = if beamOn then "ON" else "OFF"
	statusText.TextColor3 = if beamOn then Color3.fromRGB(120, 200, 255) else Color3.fromRGB(160, 160, 170)

	local scale = math.clamp(batteryPercent / 100, 0, 1)
	batteryFill.Size = UDim2.new(scale, 0, 1, 0)
	batteryFill.BackgroundColor3 = batteryColor(batteryPercent)

	if batteryPercent <= LOW_BATTERY_THRESHOLD then
		warningLabel.Text = "LOW BATTERY"
		warningLabel.TextColor3 = Color3.fromRGB(255, 80, 80)
		startWarningFlash()
	else
		warningLabel.Text = ""
		stopWarningFlash()
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
	updateBatteryUI()
end

--[[
    @summary  Apply a battery state update from the server.
    @param    percent  number
    @param    isOn     boolean
]]
local function applyBatteryUpdate(percent: number, isOn: boolean)
	batteryPercent = if typeof(percent) == "number" then math.clamp(percent, 0, 100) else 0
	beamOn = if isOn == true then true else false
	updateBatteryUI()

	-- If the server says battery is empty, force the visual beam off
	if not isOn and batteryPercent <= 0 then
		local tool = getEquippedFlashlight()
		if tool then
			turnOffVisuals(tool)
		end
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
	local fillLight = handle:FindFirstChild("FillLight")
	local sound = handle:FindFirstChildOfClass("Sound")
	if spotLight then
		local newState = not spotLight.Enabled
		if newState and batteryPercent <= 0 then
			-- Cannot turn on with empty battery
			return
		end
		spotLight.Enabled = newState
		if fillLight and fillLight:IsA("PointLight") then
			fillLight.Enabled = newState
		end
		reportBeamState(newState)
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
		turnOffVisuals(tool)
		reportBeamState(false)
	end), "Disconnect")
end

--[[
    @summary  Watch the player Backpack and Character for the
              Flashlight tool being equipped.
    @param    player  Player
]]
local function watchForFlashlight(player: Player)
	local function onToolSetChanged()
		refreshPanelVisibility()
	end

	local function checkCharacter(character: Model)
		toolJanitor:Cleanup()
		charJanitor:Cleanup()

		local tool = character:FindFirstChild(FLASHLIGHT_TOOL_NAME)
		if tool and tool:IsA("Tool") then
			wireTool(tool)
			-- Sync visual state with server
			local handle = tool:FindFirstChild("Handle")
			local spotLight = handle and handle:FindFirstChildOfClass("SpotLight")
			if spotLight then
				local fillLight = handle:FindFirstChild("FillLight")
				if fillLight and fillLight:IsA("PointLight") then
					fillLight.Enabled = spotLight.Enabled
				end
				reportBeamState(spotLight.Enabled)
			end
		end

		charJanitor:Add(character.ChildAdded:Connect(function(child)
			if child:IsA("Tool") and child.Name == FLASHLIGHT_TOOL_NAME then
				wireTool(child)
				onToolSetChanged()
			end
		end), "Disconnect")
		charJanitor:Add(character.ChildRemoved:Connect(function(child)
			if child:IsA("Tool") and child.Name == FLASHLIGHT_TOOL_NAME then
				reportBeamState(false)
				onToolSetChanged()
			end
		end), "Disconnect")

		onToolSetChanged()
	end

	janitor:Cleanup()
	janitor:Add(player.CharacterAdded:Connect(checkCharacter), "Disconnect")
	janitor:Add(player.CharacterRemoving:Connect(function()
		reportBeamState(false)
		onToolSetChanged()
	end), "Disconnect")

	-- Watch the backpack so the panel appears as soon as the flashlight is given.
	local backpack = player:FindFirstChild("Backpack")
	if backpack then
		janitor:Add(backpack.ChildAdded:Connect(onToolSetChanged), "Disconnect")
		janitor:Add(backpack.ChildRemoved:Connect(onToolSetChanged), "Disconnect")
	end
	janitor:Add(player.ChildAdded:Connect(function(child)
		if child:IsA("Backpack") then
			janitor:Add(child.ChildAdded:Connect(onToolSetChanged), "Disconnect")
			janitor:Add(child.ChildRemoved:Connect(onToolSetChanged), "Disconnect")
			onToolSetChanged()
		end
	end), "Disconnect")

	if player.Character then
		checkCharacter(player.Character)
	else
		onToolSetChanged()
	end
end

--[[
    @summary  Build the compact right-hand side battery panel.
]]
local function buildBatteryPanel()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

	local gui = Instance.new("ScreenGui")
	gui.Name = "FlashlightBatteryPanel"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false
	gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
	gui.DisplayOrder = 15

	local frame = Instance.new("Frame")
	frame.Name = "BatteryPanel"
	frame.AnchorPoint = Vector2.new(1, 0.5)
	frame.Position = UDim2.new(1, -PANEL_MARGIN, 0.5, 0)
	frame.Size = UDim2.new(0, PANEL_WIDTH, 0, PANEL_HEIGHT)
	frame.BackgroundColor3 = Color3.fromRGB(24, 24, 28)
	frame.BackgroundTransparency = 0.12
	frame.BorderSizePixel = 0
	frame.Visible = false
	frame.ZIndex = 2
	frame.Parent = gui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 14)
	corner.Parent = frame

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(60, 60, 70)
	stroke.Thickness = 1.5
	stroke.Transparency = 0.3
	stroke.Parent = frame

	-- Flashlight icon and status
	local icon = Instance.new("TextLabel")
	icon.Name = "FlashlightIcon"
	icon.Position = UDim2.new(0, 10, 0, 6)
	icon.Size = UDim2.new(0, 20, 0, 20)
	icon.BackgroundTransparency = 1
	icon.Text = "🔦"
	icon.TextSize = 18
	icon.Font = Enum.Font.GothamBold
	icon.Parent = frame

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Position = UDim2.new(0, 34, 0, 6)
	title.Size = UDim2.new(0, 70, 0, 20)
	title.BackgroundTransparency = 1
	title.Text = "FLASH"
	title.TextColor3 = Color3.fromRGB(220, 220, 230)
	title.Font = Enum.Font.GothamBold
	title.TextSize = 12
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Parent = frame

	local onOff = Instance.new("TextLabel")
	onOff.Name = "Status"
	onOff.Position = UDim2.new(1, -44, 0, 6)
	onOff.Size = UDim2.new(0, 38, 0, 20)
	onOff.BackgroundTransparency = 1
	onOff.Text = "OFF"
	onOff.TextColor3 = Color3.fromRGB(160, 160, 170)
	onOff.Font = Enum.Font.GothamBlack
	onOff.TextSize = 12
	onOff.TextXAlignment = Enum.TextXAlignment.Right
	onOff.Parent = frame

	-- Battery bar container
	local barContainer = Instance.new("Frame")
	barContainer.Name = "BatteryBarContainer"
	barContainer.Position = UDim2.new(0, 10, 0, 32)
	barContainer.Size = UDim2.new(1, -20, 0, 10)
	barContainer.BackgroundColor3 = Color3.fromRGB(40, 40, 45)
	barContainer.BackgroundTransparency = 0.2
	barContainer.BorderSizePixel = 0
	barContainer.Parent = frame

	local barCorner = Instance.new("UICorner")
	barCorner.CornerRadius = UDim.new(0, 6)
	barCorner.Parent = barContainer

	local fill = Instance.new("Frame")
	fill.Name = "BatteryFill"
	fill.Position = UDim2.new(0, 0, 0, 0)
	fill.Size = UDim2.new(1, 0, 1, 0)
	fill.BackgroundColor3 = Color3.fromRGB(60, 220, 120)
	fill.BackgroundTransparency = 0.1
	fill.BorderSizePixel = 0
	fill.Parent = barContainer

	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0, 6)
	fillCorner.Parent = fill

	local percentage = Instance.new("TextLabel")
	percentage.Name = "BatteryText"
	percentage.Position = UDim2.new(0, 10, 0, 42)
	percentage.Size = UDim2.new(0, 60, 0, 14)
	percentage.BackgroundTransparency = 1
	percentage.Text = "100%"
	percentage.TextColor3 = Color3.fromRGB(200, 200, 210)
	percentage.Font = Enum.Font.GothamBold
	percentage.TextSize = 12
	percentage.TextXAlignment = Enum.TextXAlignment.Left
	percentage.Parent = frame

	local warn = Instance.new("TextLabel")
	warn.Name = "Warning"
	warn.Position = UDim2.new(1, -70, 0, 42)
	warn.Size = UDim2.new(0, 60, 0, 14)
	warn.BackgroundTransparency = 1
	warn.Text = ""
	warn.TextColor3 = Color3.fromRGB(255, 80, 80)
	warn.Font = Enum.Font.GothamBlack
	warn.TextSize = 10
	warn.TextXAlignment = Enum.TextXAlignment.Right
	warn.Parent = frame

	panelGui = gui
	panelFrame = frame
	batteryBar = barContainer
	batteryFill = fill
	batteryText = percentage
	statusText = onOff
	warningLabel = warn

	gui.Parent = playerGui
end

refreshPanelVisibility = function()
	if not panelFrame then
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

	panelFrame.Visible = hasFlashlight
end

-- // INITIALIZATION // --

function FlashlightController:KnitStart()
	gameStateController = Knit.GetController("GameStateController")
	flashlightService = Knit.GetService("FlashlightService")

	local player = Players.LocalPlayer

	buildBatteryPanel()

	-- Request initial battery state and listen for updates
	if flashlightService then
		local ok, state = pcall(flashlightService.GetBatteryState)
		if ok and state and typeof(state) == "table" then
			batteryPercent = if typeof(state.percent) == "number" then math.clamp(state.percent, 0, 100) else 100
			beamOn = if state.isOn == true then true else false
			updateBatteryUI()
		end

		flashlightService.BatteryChanged:Connect(function(percent: number, isOn: boolean)
			applyBatteryUpdate(percent, isOn)
		end)
	end

	local function onGameStarted()
		watchForFlashlight(player)
		-- Keep panel visibility in sync
		task.spawn(function()
			while true do
				refreshPanelVisibility()
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

	updateBatteryUI()
	print("[FlashlightController] Initialised — battery panel + toggle active")
end

return FlashlightController
