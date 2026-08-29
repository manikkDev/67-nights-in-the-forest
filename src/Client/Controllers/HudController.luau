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
local ServerRole = require(ReplicatedStorage.Shared.ServerRole)

-- | Objects | --
local HudController = Knit.CreateController({
	Name = "HudController",
})

-- | Configuration | --
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
local _shadow: Frame? = nil
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

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "PhaseIndicator"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true
	screenGui.DisplayOrder = 50
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.Enabled = false
	screenGui.Parent = playerGui
	phaseGui = screenGui

	local shadowFrame = Instance.new("Frame")
	shadowFrame.Name = "BannerShadow"
	shadowFrame.Size = UDim2.new(0, 144, 0, 40)
	shadowFrame.Position = UDim2.new(0.5, 2, 0, 14)
	shadowFrame.AnchorPoint = Vector2.new(0.5, 0)
	shadowFrame.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	shadowFrame.BackgroundTransparency = 0.55
	shadowFrame.BorderSizePixel = 0
	shadowFrame.ZIndex = 1
	shadowFrame.Parent = screenGui
	_shadow = shadowFrame

	local shadowCorner = Instance.new("UICorner")
	shadowCorner.CornerRadius = UDim.new(0, 10)
	shadowCorner.Parent = shadowFrame

	local bannerFrame = Instance.new("Frame")
	bannerFrame.Name = "PhaseBanner"
	bannerFrame.Size = UDim2.new(0, 140, 0, 36)
	bannerFrame.Position = UDim2.new(0.5, 0, 0, 12)
	bannerFrame.AnchorPoint = Vector2.new(0.5, 0)
	bannerFrame.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	bannerFrame.BackgroundTransparency = 0.15
	bannerFrame.BorderSizePixel = 0
	bannerFrame.ZIndex = 2
	bannerFrame.Parent = screenGui
	banner = bannerFrame

	local bannerCorner = Instance.new("UICorner")
	bannerCorner.CornerRadius = UDim.new(0, 10)
	bannerCorner.Parent = bannerFrame

	local uiGradient = Instance.new("UIGradient")
	uiGradient.Rotation = 90
	uiGradient.Color = DAY_GRADIENT
	uiGradient.Parent = bannerFrame
	gradient = uiGradient

	local uiStroke = Instance.new("UIStroke")
	uiStroke.Thickness = 1.5
	uiStroke.Transparency = 0.25
	uiStroke.Color = DAY_STROKE_COLOR
	uiStroke.Parent = bannerFrame
	stroke = uiStroke

	local textLabel = Instance.new("TextLabel")
	textLabel.Name = "PhaseText"
	textLabel.Size = UDim2.new(1, -16, 1, 0)
	textLabel.Position = UDim2.new(0, 8, 0, 0)
	textLabel.BackgroundTransparency = 1
	textLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	textLabel.Font = Enum.Font.GothamBlack
	textLabel.TextSize = 20
	textLabel.TextXAlignment = Enum.TextXAlignment.Center
	textLabel.TextYAlignment = Enum.TextYAlignment.Center
	textLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	textLabel.TextStrokeTransparency = 0.3
	textLabel.Text = "Day 1"
	textLabel.ZIndex = 3
	textLabel.Parent = bannerFrame
	phaseText = textLabel
end

--[[
    @summary  Update banner colors and text for the current phase.
    @param   phase  string  -- "Day" or "Night"
]]
local function updateBanner(phase: string, dayNumber: number)
	if not banner or not phaseText or not stroke or not gradient then
		return
	end
	local isDay = phase == "Day"
	phaseText.Text = phase .. " " .. dayNumber
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
	if not ServerRole.IsGameServer() then return end
	createPhaseUi()
end

function HudController:KnitStart()
	if not ServerRole.IsGameServer() then return end
	gameStateController = Knit.GetController("GameStateController")
	local timeService = Knit.GetService("TimeService")
	local runStateService = Knit.GetService("RunStateService")

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

	timeService.DayStarted:Connect(function()
		if labelsEnabled then
			showDay()
		end
	end)

	timeService.NightStarted:Connect(function()
		if labelsEnabled then
			showNight()
		end
	end)

	timeService.DawnAdvanced:Connect(function(payload)
		if typeof(payload) == "table" and typeof(payload.displayedDay) == "number" then
			currentDayNumber = payload.displayedDay
		end
		if labelsEnabled then
			showDay()
		end
	end)

	timeService:GetProgress():andThen(function(progress)
		if typeof(progress) == "table" and typeof(progress.displayedDay) == "number" then
			currentDayNumber = progress.displayedDay
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

	runStateService.RunPhaseChanged:Connect(function(payload)
		if typeof(payload) == "table" and payload.phase == "Lobby" then
			labelsEnabled = false
			currentDayNumber = 1
			if phaseGui then
				phaseGui.Enabled = false
			end
		end
	end)
end

return HudController
