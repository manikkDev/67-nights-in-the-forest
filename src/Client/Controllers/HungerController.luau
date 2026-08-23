--[[
    @file    HungerController.luau
    @author  manik
    @date    2025

    @summary
    Compact, polished survival HUD showing health and hunger.

    @description
    Builds a modern "VITALS" card in the top-left with icon + bar +
    percentage for each stat, matching the dark-slate / warm-stroke
    visual style used by the inventory and campfire systems.
]]

-- // VARIABLES // --

-- | Services | --
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

-- | Modules | --
local Knit = require(ReplicatedStorage.Packages.Knit)

-- | Objects | --
local HungerController = Knit.CreateController({
	Name = "HungerController",
})

-- | Configuration | --
local TWEEN_INFO = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local CARD_BG = Color3.fromRGB(38, 40, 48)
local CARD_STROKE = Color3.fromRGB(230, 160, 70)
local TEXT_LIGHT = Color3.fromRGB(240, 240, 245)
local TEXT_DIM = Color3.fromRGB(170, 170, 180)
local BAR_BG = Color3.fromRGB(28, 28, 34)
local BAR_STROKE = Color3.fromRGB(80, 80, 90)

local HEALTH_COLOR = Color3.fromRGB(230, 75, 75)
local HUNGER_COLOR = Color3.fromRGB(230, 170, 50)

-- | State Management | --
local healthFill: Frame? = nil
local hungerFill: Frame? = nil
local healthValueLabel: TextLabel? = nil
local hungerValueLabel: TextLabel? = nil
local survivalGui: ScreenGui? = nil

-- // FUNCTIONS // --

local function setFillAndLabel(fill: Frame?, label: TextLabel?, current: number, max: number, color: Color3)
	if not fill or not label then
		return
	end
	local clamped = math.clamp(if max > 0 then current / max else 0, 0, 1)
	local percent = math.round(clamped * 100)

	TweenService:Create(fill, TWEEN_INFO, { Size = UDim2.new(clamped, 0, 1, 0) }):Play()

	label.Text = tostring(percent) .. "%"
	label.TextColor3 = color:Lerp(TEXT_DIM, 1 - clamped)
end

local function buildStatRow(parent: Frame, name: string, y: number, labelText: string, color: Color3): (Frame, TextLabel)
	local icon = Instance.new("Frame")
	icon.Name = name .. "Icon"
	icon.Size = UDim2.new(0, 18, 0, 18)
	icon.Position = UDim2.new(0, 10, 0, y + 4)
	icon.BackgroundColor3 = color
	icon.BorderSizePixel = 0
	icon.Parent = parent

	local iconCorner = Instance.new("UICorner")
	iconCorner.CornerRadius = UDim.new(1, 0)
	iconCorner.Parent = icon

	local iconStroke = Instance.new("UIStroke")
	iconStroke.Color = color
	iconStroke.Transparency = 0.4
	iconStroke.Thickness = 1.5
	iconStroke.Parent = icon

	local label = Instance.new("TextLabel")
	label.Name = name .. "Label"
	label.Size = UDim2.new(0, 52, 0, 18)
	label.Position = UDim2.new(0, 34, 0, y + 4)
	label.BackgroundTransparency = 1
	label.Text = labelText
	label.TextColor3 = TEXT_DIM
	label.Font = Enum.Font.GothamBold
	label.TextSize = 11
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Parent = parent

	local barBackground = Instance.new("Frame")
	barBackground.Name = name .. "BarBackground"
	barBackground.Size = UDim2.new(0, 110, 0, 10)
	barBackground.Position = UDim2.new(0, 88, 0, y + 7)
	barBackground.BackgroundColor3 = BAR_BG
	barBackground.BackgroundTransparency = 0.05
	barBackground.BorderSizePixel = 0
	barBackground.Parent = parent

	local bgCorner = Instance.new("UICorner")
	bgCorner.CornerRadius = UDim.new(0, 4)
	bgCorner.Parent = barBackground

	local bgStroke = Instance.new("UIStroke")
	bgStroke.Color = BAR_STROKE
	bgStroke.Transparency = 0.5
	bgStroke.Thickness = 1
	bgStroke.Parent = barBackground

	local barFill = Instance.new("Frame")
	barFill.Name = name .. "BarFill"
	barFill.Size = UDim2.new(1, 0, 1, 0)
	barFill.BackgroundColor3 = color
	barFill.BackgroundTransparency = 0.05
	barFill.BorderSizePixel = 0
	barFill.Parent = barBackground

	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0, 4)
	fillCorner.Parent = barFill

	local fillGradient = Instance.new("UIGradient")
	fillGradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, color),
		ColorSequenceKeypoint.new(1, color:Lerp(Color3.new(0, 0, 0), 0.35)),
	})
	fillGradient.Rotation = 90
	fillGradient.Parent = barFill

	local fillStroke = Instance.new("UIStroke")
	fillStroke.Color = color
	fillStroke.Transparency = 0.65
	fillStroke.Thickness = 1
	fillStroke.Parent = barFill

	local valueLabel = Instance.new("TextLabel")
	valueLabel.Name = name .. "Value"
	valueLabel.Size = UDim2.new(0, 44, 0, 18)
	valueLabel.Position = UDim2.new(0, 200, 0, y + 4)
	valueLabel.BackgroundTransparency = 1
	valueLabel.Text = "100%"
	valueLabel.TextColor3 = TEXT_LIGHT
	valueLabel.Font = Enum.Font.GothamBold
	valueLabel.TextSize = 12
	valueLabel.TextXAlignment = Enum.TextXAlignment.Right
	valueLabel.Parent = parent

	return barFill, valueLabel
end

local function buildSurvivalGui()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	if not playerGui then
		return
	end
	local existing = playerGui:FindFirstChild("HealthBarFill")
	if existing then
		existing:Destroy()
	end

	local existingSurvival = playerGui:FindFirstChild("SurvivalGui")
	if existingSurvival then
		existingSurvival:Destroy()
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = "SurvivalGui"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 2
	gui.Enabled = false
	gui.Parent = playerGui
	survivalGui = gui

	local panel = Instance.new("Frame")
	panel.Name = "SurvivalPanel"
	panel.Size = UDim2.new(0, 250, 0, 96)
	panel.Position = UDim2.new(0, 20, 0, 70)
	panel.AnchorPoint = Vector2.new(0, 0)
	panel.BackgroundColor3 = CARD_BG
	panel.BackgroundTransparency = 0.02
	panel.BorderSizePixel = 0
	panel.Parent = gui

	local panelCorner = Instance.new("UICorner")
	panelCorner.CornerRadius = UDim.new(0, 12)
	panelCorner.Parent = panel

	local panelStroke = Instance.new("UIStroke")
	panelStroke.Color = CARD_STROKE
	panelStroke.Transparency = 0.25
	panelStroke.Thickness = 1.5
	panelStroke.Parent = panel

	local header = Instance.new("TextLabel")
	header.Name = "Header"
	header.Size = UDim2.new(1, -20, 0, 18)
	header.Position = UDim2.new(0, 10, 0, 6)
	header.BackgroundTransparency = 1
	header.Text = "VITALS"
	header.TextColor3 = TEXT_DIM
	header.Font = Enum.Font.GothamBold
	header.TextSize = 11
	header.TextXAlignment = Enum.TextXAlignment.Left
	header.Parent = panel

	healthFill, healthValueLabel = buildStatRow(panel, "Health", 28, "HP", HEALTH_COLOR)
	hungerFill, hungerValueLabel = buildStatRow(panel, "Hunger", 58, "HUNGER", HUNGER_COLOR)
end

--[[
    @summary  Bind the Health bar to a character's Humanoid.
    @param    character  Model  -- the local player's character
]]
local function bindHumanoid(character: Model)
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	local function updateHealth()
		setFillAndLabel(healthFill, healthValueLabel, humanoid.Health, humanoid.MaxHealth, HEALTH_COLOR)
	end
	updateHealth()
	humanoid.HealthChanged:Connect(updateHealth)
end

-- // INITIALIZATION // --

function HungerController:KnitInit()
	buildSurvivalGui()

	local player = Players.LocalPlayer
	if player.Character then
		bindHumanoid(player.Character)
	end
	player.CharacterAdded:Connect(bindHumanoid)

	-- Set initial hunger to full so the bar doesn't flash empty
	if hungerFill and hungerValueLabel then
		hungerFill.Size = UDim2.new(1, 0, 1, 0)
		hungerValueLabel.Text = "100%"
		hungerValueLabel.TextColor3 = HUNGER_COLOR
	end
end

function HungerController:KnitStart()
	local gameStateController = Knit.GetController("GameStateController")
	local hungerService = Knit.GetService("HungerService")
	local runStateService = Knit.GetService("RunStateService")

	local function showGui()
		if survivalGui then
			survivalGui.Enabled = true
		end
	end

	if gameStateController and gameStateController:IsInGame() then
		showGui()
	else
		if gameStateController then
			gameStateController.GameStarted:Connect(showGui)
		end
	end

	hungerService.HungerChanged:Connect(function(hunger, maxHunger)
		setFillAndLabel(hungerFill, hungerValueLabel, hunger, maxHunger, HUNGER_COLOR)
	end)

	runStateService.RunPhaseChanged:Connect(function(payload)
		if typeof(payload) == "table" and payload.phase == "Lobby" and survivalGui then
			survivalGui.Enabled = false
		end
	end)
end

return HungerController
