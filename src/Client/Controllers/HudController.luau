--[[
    @file    HudController.luau
    @author  manik
    @date    2025

    @summary
    Binds DayLabel/NightLabel GUIs to the live TimeService clock.

    @description
    Creates TextLabels inside the existing DayLabel and NightLabel
    ScreenGuis in StarterGui, then listens to TimeService signals
    to toggle visibility and update the day/night counter text.

    @exports
    - HudController (Knit Controller)
]]

-- // VARIABLES // --

-- | Services | --
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- | Modules | --
local Knit = require(ReplicatedStorage.Packages.Knit)

-- | Objects | --
local HudController = Knit.CreateController({
	Name = "HudController",
})

-- | Configuration | --
local DAY_ICON_COLOR = Color3.fromRGB(255, 210, 80)
local NIGHT_ICON_COLOR = Color3.fromRGB(220, 230, 255)
local DAY_STROKE_COLOR = Color3.fromRGB(255, 180, 60)
local NIGHT_STROKE_COLOR = Color3.fromRGB(100, 130, 220)
local DAY_GRADIENT = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(80, 70, 50)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(55, 50, 40)),
})
local NIGHT_GRADIENT = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(50, 50, 75)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(30, 30, 50)),
})

-- | State Management | --
local phaseGui: ScreenGui? = nil
local banner: Frame? = nil
local icon: Frame? = nil
local shadow: Frame? = nil
local phaseText: TextLabel? = nil
local gradient: UIGradient? = nil
local stroke: UIStroke? = nil
local currentDayNumber = 1
local gameStateController: any = nil
local labelsEnabled = false

-- // FUNCTIONS // --

--[[
    @summary  Build the top-center day/night banner and disable legacy labels.
]]
local function createPhaseUi()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	if not playerGui then
		return
	end

	for _, name in ipairs({ "DayLabel", "NightLabel" }) do
		local legacy = playerGui:FindFirstChild(name)
		if legacy and legacy:IsA("ScreenGui") then
			legacy.Enabled = false
		end
	end

	phaseGui = Instance.new("ScreenGui")
	phaseGui.Name = "PhaseIndicator"
	phaseGui.ResetOnSpawn = false
	phaseGui.IgnoreGuiInset = true
	phaseGui.DisplayOrder = 50
	phaseGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	phaseGui.Enabled = false
	phaseGui.Parent = playerGui

	shadow = Instance.new("Frame")
	shadow.Name = "BannerShadow"
	shadow.Size = UDim2.new(0, 264, 0, 52)
	shadow.Position = UDim2.new(0.5, 2, 0, 18)
	shadow.AnchorPoint = Vector2.new(0.5, 0)
	shadow.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	shadow.BackgroundTransparency = 0.55
	shadow.BorderSizePixel = 0
	shadow.ZIndex = 1
	shadow.Parent = phaseGui

	local shadowCorner = Instance.new("UICorner")
	shadowCorner.CornerRadius = UDim.new(0, 12)
	shadowCorner.Parent = shadow

	banner = Instance.new("Frame")
	banner.Name = "PhaseBanner"
	banner.Size = UDim2.new(0, 260, 0, 48)
	banner.Position = UDim2.new(0.5, 0, 0, 16)
	banner.AnchorPoint = Vector2.new(0.5, 0)
	banner.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	banner.BackgroundTransparency = 0.15
	banner.BorderSizePixel = 0
	banner.ZIndex = 2
	banner.Parent = phaseGui

	local bannerCorner = Instance.new("UICorner")
	bannerCorner.CornerRadius = UDim.new(0, 12)
	bannerCorner.Parent = banner

	gradient = Instance.new("UIGradient")
	gradient.Rotation = 90
	gradient.Color = DAY_GRADIENT
	gradient.Parent = banner

	stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Transparency = 0.25
	stroke.Color = DAY_STROKE_COLOR
	stroke.Parent = banner

	icon = Instance.new("Frame")
	icon.Name = "PhaseIcon"
	icon.Size = UDim2.new(0, 28, 0, 28)
	icon.Position = UDim2.new(0, 14, 0.5, 0)
	icon.AnchorPoint = Vector2.new(0, 0.5)
	icon.BackgroundColor3 = DAY_ICON_COLOR
	icon.BorderSizePixel = 0
	icon.ZIndex = 3
	icon.Parent = banner

	local iconCorner = Instance.new("UICorner")
	iconCorner.CornerRadius = UDim.new(1, 0)
	iconCorner.Parent = icon

	phaseText = Instance.new("TextLabel")
	phaseText.Name = "PhaseText"
	phaseText.Size = UDim2.new(1, -58, 1, 0)
	phaseText.Position = UDim2.new(0, 50, 0, 0)
	phaseText.BackgroundTransparency = 1
	phaseText.TextColor3 = Color3.fromRGB(255, 255, 255)
	phaseText.Font = Enum.Font.GothamBlack
	phaseText.TextSize = 22
	phaseText.TextXAlignment = Enum.TextXAlignment.Left
	phaseText.TextYAlignment = Enum.TextYAlignment.Center
	phaseText.Text = "Day 1"
	phaseText.ZIndex = 3
	phaseText.Parent = banner
end

--[[
    @summary  Update banner colors and text for the current phase.
    @param   phase  string  -- "Day" or "Night"
]]
local function updateBanner(phase: string, dayNumber: number)
	if not banner or not icon or not phaseText or not stroke or not gradient then
		return
	end
	local isDay = phase == "Day"
	phaseText.Text = phase .. " " .. dayNumber
	icon.BackgroundColor3 = if isDay then DAY_ICON_COLOR else NIGHT_ICON_COLOR
	stroke.Color = if isDay then DAY_STROKE_COLOR else NIGHT_STROKE_COLOR
	gradient.Color = if isDay then DAY_GRADIENT else NIGHT_GRADIENT
end

--[[
    @summary  Show the Day banner.
]]
local function showDay()
	if phaseGui then phaseGui.Enabled = labelsEnabled end
	updateBanner("Day", currentDayNumber)
end

--[[
    @summary  Show the Night banner.
]]
local function showNight()
	if phaseGui then phaseGui.Enabled = labelsEnabled end
	updateBanner("Night", currentDayNumber)
end

-- // INITIALIZATION // --

function HudController:KnitInit()
	createPhaseUi()
end

function HudController:KnitStart()
	gameStateController = Knit.GetController("GameStateController")
	local timeService = Knit.GetService("TimeService")

	local function enableLabels()
		labelsEnabled = true
		if phaseGui then phaseGui.Enabled = true end
	end

	if gameStateController and gameStateController:IsInGame() then
		enableLabels()
	else
		if gameStateController then
			gameStateController.GameStarted:Connect(function()
				enableLabels()
				showDay()
			end)
		end
	end

	timeService.DayStarted:Connect(function(dayNumber)
		if typeof(dayNumber) == "number" then
			currentDayNumber = dayNumber
		end
		if labelsEnabled then
			showDay()
		end
	end)

	timeService.NightStarted:Connect(function(dayNumber)
		if typeof(dayNumber) == "number" then
			currentDayNumber = dayNumber
		end
		if labelsEnabled then
			showNight()
		end
	end)

	-- Use :Observe() to sync to the current server phase state. Unlike :Get(),
	-- :Observe() fires the initial value once the property has synced from the
	-- server (via task.defer if already ready), and on every subsequent change.
	local phaseState = timeService.GetPhaseState
	if phaseState then
		phaseState:Observe(function(currentPhase: any)
			if currentPhase == "Night" then
				showNight()
			else
				showDay()
			end
		end)
	end

	print("[HudController] Initialised — day/night banner bound to TimeService")
end

return HudController
