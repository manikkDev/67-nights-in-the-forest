--[[
    @file    CampfireController.luau
    @author  manik
    @date    2025

    @summary
    Client HUD for the shared campfire fuel and level state.

    @description
    Builds a glassmorphic bottom-left panel that shows the current fuel
    bar, level bar, and level. It listens to FuelChanged, LevelChanged,
    and SafeZoneChanged from CampfireService and shows a warning when
    the fire goes out.
]]

-- // VARIABLES // --

-- | Services | --
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

-- | Modules | --
local Knit = require(ReplicatedStorage.Packages.Knit)

-- | Objects | --
local CampfireController = Knit.CreateController({
	Name = "CampfireController",
})

-- | Configuration | --
local PANEL_WIDTH = 210
local PANEL_HEIGHT = 126
local PANEL_MARGIN = 20
local BAR_HEIGHT = 18
local BAR_TWEEN_INFO = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local WARNING_TWEEN_INFO = TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local LEVELUP_TWEEN_INFO = TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local LEVELUP_HOLD_TIME = 3

-- | State Management | --
local campfireGui: ScreenGui? = nil
local warningGui: ScreenGui? = nil
local fuelFill: Frame? = nil
local levelFill: Frame? = nil
local levelLabel: TextLabel? = nil
local statusLabel: TextLabel? = nil
local warningLabel: TextLabel? = nil

local levelUpGui: ScreenGui? = nil
local levelUpBanner: CanvasGroup? = nil
local levelUpTitle: TextLabel? = nil
local levelUpSubtitle: TextLabel? = nil

-- // FUNCTIONS // --

--[[
    @summary  Update the fuel bar colour and fill size.
    @param    fuel     number
    @param    maxFuel  number
    @param    isLit    boolean
]]
local function setFuelBar(fuel: number, maxFuel: number, isLit: boolean)
	if not fuelFill then
		return
	end

	local fraction = if maxFuel > 0 then math.clamp(fuel / maxFuel, 0, 1) else 0
	local color = Color3.fromRGB(230, 120, 30):Lerp(Color3.fromRGB(220, 60, 60), 1 - fraction)

	fuelFill.BackgroundColor3 = color
	TweenService:Create(fuelFill, BAR_TWEEN_INFO, { Size = UDim2.new(fraction, 0, 1, 0) }):Play()

	if statusLabel then
		statusLabel.Text = if isLit then "Lit" else "OUT"
		statusLabel.TextColor3 = if isLit then Color3.fromRGB(120, 220, 120) else Color3.fromRGB(220, 80, 80)
	end
end

--[[
    @summary  Update the level bar fill size and level label.
    @param    level       number
    @param    progress    number
    @param    requirement number
]]
local function setLevelBar(level: number, progress: number, requirement: number)
	if levelLabel then
		levelLabel.Text = "LVL " .. tostring(level)
	end
	if not levelFill then
		return
	end

	local fraction = if requirement > 0 then math.clamp(progress / requirement, 0, 1) else 1
	TweenService:Create(levelFill, BAR_TWEEN_INFO, { Size = UDim2.new(fraction, 0, 1, 0) }):Play()
end

--[[
    @summary  Fade the fire-out warning in or out.
    @param    isLit  boolean
]]
local function setWarning(isLit: boolean)
	if not warningLabel then
		return
	end
	local target = if isLit then 1 else 0
	TweenService:Create(warningLabel, WARNING_TWEEN_INFO, { TextTransparency = target }):Play()
end

--[[
    @summary  Build or rebuild the warning ScreenGui.
    @returns  TextLabel
]]
local function buildWarning(): TextLabel
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local existing = playerGui:FindFirstChild("CampfireWarningGui")
	if existing then
		existing:Destroy()
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = "CampfireWarningGui"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.Parent = playerGui

	local label = Instance.new("TextLabel")
	label.Name = "WarningLabel"
	label.AnchorPoint = Vector2.new(0.5, 0)
	label.Position = UDim2.new(0.5, 0, 0, 70)
	label.Size = UDim2.new(0, 500, 0, 36)
	label.BackgroundTransparency = 1
	label.TextColor3 = Color3.fromRGB(230, 80, 80)
	label.Font = Enum.Font.GothamBold
	label.TextSize = 22
	label.Text = "The campfire has gone out, you are no longer safe"
	label.TextTransparency = 1
	label.Parent = gui

	warningLabel = label
	return label
end

--[[
    @summary  Build the centered level-up banner.
    @returns  CanvasGroup
]]
local function buildLevelUpBanner(): CanvasGroup
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local existing = playerGui:FindFirstChild("CampfireLevelUpGui")
	if existing then
		existing:Destroy()
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = "CampfireLevelUpGui"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 10
	gui.Parent = playerGui
	levelUpGui = gui

	local banner = Instance.new("CanvasGroup")
	banner.Name = "Banner"
	banner.AnchorPoint = Vector2.new(0.5, 0.5)
	banner.Position = UDim2.new(0.5, 0, 0.5, -40)
	banner.Size = UDim2.new(0, 360, 0, 80)
	banner.BackgroundTransparency = 1
	banner.GroupTransparency = 1
	banner.Parent = gui
	levelUpBanner = banner

	local background = Instance.new("Frame")
	background.Name = "Background"
	background.Size = UDim2.new(1, 0, 1, 0)
	background.BackgroundColor3 = Color3.fromRGB(42, 44, 54)
	background.BackgroundTransparency = 0.05
	background.BorderSizePixel = 0
	background.Parent = banner

	local bgCorner = Instance.new("UICorner")
	bgCorner.CornerRadius = UDim.new(0, 10)
	bgCorner.Parent = background

	local bgStroke = Instance.new("UIStroke")
	bgStroke.Color = Color3.fromRGB(230, 160, 70)
	bgStroke.Transparency = 0.3
	bgStroke.Thickness = 2
	bgStroke.Parent = background

	local bgGradient = Instance.new("UIGradient")
	bgGradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(220, 210, 200)),
	})
	bgGradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.2),
		NumberSequenceKeypoint.new(1, 0.4),
	})
	bgGradient.Rotation = 90
	bgGradient.Parent = background

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(1, 0, 0.6, 0)
	title.Position = UDim2.new(0, 0, 0, 0)
	title.BackgroundTransparency = 1
	title.Text = "CAMPFIRE LEVEL 2!"
	title.TextColor3 = Color3.fromRGB(255, 230, 180)
	title.Font = Enum.Font.GothamBlack
	title.TextSize = 24
	title.TextXAlignment = Enum.TextXAlignment.Center
	title.TextYAlignment = Enum.TextYAlignment.Bottom
	title.Parent = banner
	levelUpTitle = title

	local subtitle = Instance.new("TextLabel")
	subtitle.Name = "Subtitle"
	subtitle.Size = UDim2.new(1, 0, 0.4, 0)
	subtitle.Position = UDim2.new(0, 0, 0.6, 0)
	subtitle.BackgroundTransparency = 1
	subtitle.Text = "Safe zone expanded"
	subtitle.TextColor3 = Color3.fromRGB(240, 240, 245)
	subtitle.Font = Enum.Font.GothamBold
	subtitle.TextSize = 15
	subtitle.TextXAlignment = Enum.TextXAlignment.Center
	subtitle.TextYAlignment = Enum.TextYAlignment.Top
	subtitle.Parent = banner
	levelUpSubtitle = subtitle

	return banner
end

--[[
    @summary  Build a single progress bar (background + fill).
    @param    name   string
    @param    y      number
    @param    color  Color3
    @returns  Frame
]]
local function buildBar(name: string, y: number, color: Color3): Frame
	local background = Instance.new("Frame")
	background.Name = name .. "Background"
	background.Size = UDim2.new(1, -PANEL_MARGIN * 2, 0, BAR_HEIGHT)
	background.Position = UDim2.new(0, PANEL_MARGIN, 0, y)
	background.BackgroundColor3 = Color3.fromRGB(35, 35, 40)
	background.BackgroundTransparency = 0.4
	background.BorderSizePixel = 0
	background.Parent = campfireGui.Panel

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 4)
	corner.Parent = background

	local fill = Instance.new("Frame")
	fill.Name = name .. "Fill"
	fill.Size = UDim2.new(1, 0, 1, 0)
	fill.BackgroundColor3 = color
	fill.BorderSizePixel = 0
	fill.Parent = background

	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0, 4)
	fillCorner.Parent = fill

	return fill
end

--[[
    @summary  Build or rebuild the campfire HUD panel.
]]
local function buildGui()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local existing = playerGui:FindFirstChild("CampfireGui")
	if existing then
		existing:Destroy()
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = "CampfireGui"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.Parent = playerGui
	campfireGui = gui

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0, 1)
	panel.Position = UDim2.new(0, PANEL_MARGIN, 1, -PANEL_MARGIN)
	panel.Size = UDim2.new(0, PANEL_WIDTH, 0, PANEL_HEIGHT)
	panel.BackgroundColor3 = Color3.fromRGB(42, 44, 54)
	panel.BackgroundTransparency = 0.06
	panel.BorderSizePixel = 0
	panel.Parent = gui

	local panelCorner = Instance.new("UICorner")
	panelCorner.CornerRadius = UDim.new(0, 10)
	panelCorner.Parent = panel

	local panelStroke = Instance.new("UIStroke")
	panelStroke.Color = Color3.fromRGB(160, 165, 180)
	panelStroke.Transparency = 0.7
	panelStroke.Thickness = 1.5
	panelStroke.Parent = panel

	local panelGradient = Instance.new("UIGradient")
	panelGradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(200, 205, 215)),
	})
	panelGradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.96),
		NumberSequenceKeypoint.new(1, 0.99),
	})
	panelGradient.Rotation = 90
	panelGradient.Parent = panel

	local header = Instance.new("TextLabel")
	header.Name = "Header"
	header.Size = UDim2.new(0, 100, 0, 22)
	header.Position = UDim2.new(0, PANEL_MARGIN, 0, 8)
	header.BackgroundTransparency = 1
	header.Text = "CAMPFIRE"
	header.TextColor3 = Color3.fromRGB(230, 220, 200)
	header.Font = Enum.Font.GothamBold
	header.TextSize = 16
	header.TextXAlignment = Enum.TextXAlignment.Left
	header.Parent = panel

	levelLabel = Instance.new("TextLabel")
	levelLabel.Name = "LevelLabel"
	levelLabel.Size = UDim2.new(0, 70, 0, 22)
	levelLabel.Position = UDim2.new(1, -PANEL_MARGIN - 70, 0, 8)
	levelLabel.BackgroundTransparency = 1
	levelLabel.Text = "LVL 1"
	levelLabel.TextColor3 = Color3.fromRGB(230, 220, 200)
	levelLabel.Font = Enum.Font.GothamBold
	levelLabel.TextSize = 16
	levelLabel.TextXAlignment = Enum.TextXAlignment.Right
	levelLabel.Parent = panel

	local fuelText = Instance.new("TextLabel")
	fuelText.Name = "FuelText"
	fuelText.Size = UDim2.new(0, 80, 0, 14)
	fuelText.Position = UDim2.new(0, PANEL_MARGIN, 0, 34)
	fuelText.BackgroundTransparency = 1
	fuelText.Text = "Fuel"
	fuelText.TextColor3 = Color3.fromRGB(180, 180, 190)
	fuelText.Font = Enum.Font.Gotham
	fuelText.TextSize = 12
	fuelText.TextXAlignment = Enum.TextXAlignment.Left
	fuelText.Parent = panel

	fuelFill = buildBar("Fuel", 50, Color3.fromRGB(230, 120, 30))

	local levelText = Instance.new("TextLabel")
	levelText.Name = "LevelText"
	levelText.Size = UDim2.new(0, 80, 0, 14)
	levelText.Position = UDim2.new(0, PANEL_MARGIN, 0, 74)
	levelText.BackgroundTransparency = 1
	levelText.Text = "Level Bar"
	levelText.TextColor3 = Color3.fromRGB(180, 180, 190)
	levelText.Font = Enum.Font.Gotham
	levelText.TextSize = 12
	levelText.TextXAlignment = Enum.TextXAlignment.Left
	levelText.Parent = panel

	levelFill = buildBar("Level", 90, Color3.fromRGB(240, 180, 30))

	statusLabel = Instance.new("TextLabel")
	statusLabel.Name = "StatusLabel"
	statusLabel.Size = UDim2.new(1, -PANEL_MARGIN * 2, 0, 16)
	statusLabel.Position = UDim2.new(0, PANEL_MARGIN, 0, 112)
	statusLabel.BackgroundTransparency = 1
	statusLabel.Text = "Lit"
	statusLabel.TextColor3 = Color3.fromRGB(120, 220, 120)
	statusLabel.Font = Enum.Font.GothamBold
	statusLabel.TextSize = 13
	statusLabel.TextXAlignment = Enum.TextXAlignment.Left
	statusLabel.Parent = panel

	buildWarning()
end

--[[
    @summary  Handler for FuelChanged signal.
]]
local function onFuelChanged(fuel: number, maxFuel: number, fraction: number, isLit: boolean)
	setFuelBar(fuel, maxFuel, isLit)
	setWarning(isLit)
end

--[[
    @summary  Handler for LevelChanged signal.
]]
local function onLevelChanged(level: number, progress: number, requirement: number, levelFraction: number)
	setLevelBar(level, progress, requirement)
end

--[[
    @summary  Show the level-up banner then fade it out after a hold.
    @param    newLevel      number
    @param    previousLevel number
    @param    radius        number
    @param    maxFuel       number
]]
local function showLevelUp(newLevel: number, previousLevel: number, radius: number, maxFuel: number)
	if not levelUpBanner or not levelUpTitle or not levelUpSubtitle then
		return
	end

	levelUpTitle.Text = "CAMPFIRE LEVEL " .. tostring(newLevel) .. "!"
	levelUpSubtitle.Text = "Safe zone expanded to " .. tostring(math.round(radius)) .. " studs"

	-- Keep the size non-zero: CanvasGroup can bug out if it is ever
	-- scaled to (0, 0).  We fade/slide instead.
	levelUpBanner.Position = UDim2.new(0.5, 0, 0.5, 60)
	levelUpBanner.Size = UDim2.new(0, 360, 0, 80)
	levelUpBanner.GroupTransparency = 1

	TweenService:Create(levelUpBanner, LEVELUP_TWEEN_INFO, {
		Position = UDim2.new(0.5, 0, 0.5, -40),
		GroupTransparency = 0,
	}):Play()

	task.delay(LEVELUP_HOLD_TIME, function()
		if not levelUpBanner then
			return
		end
		TweenService:Create(levelUpBanner, LEVELUP_TWEEN_INFO, {
			Position = UDim2.new(0.5, 0, 0.5, -90),
			GroupTransparency = 1,
		}):Play()
	end)
end

--[[
    @summary  Handler for the LevelUp signal.
]]
local function onLevelUp(level: number, previousLevel: number, radius: number, maxFuel: number)
	showLevelUp(level, previousLevel, radius, maxFuel)
end

-- // INITIALIZATION // --

function CampfireController:KnitStart()
	buildGui()
	buildLevelUpBanner()

	local campfireService = Knit.GetService("CampfireService")
	campfireService.FuelChanged:Connect(onFuelChanged)
	campfireService.LevelChanged:Connect(onLevelChanged)
	campfireService.LevelUp:Connect(onLevelUp)

	-- The initial state is sent by the server through the signal connections.
	print("[CampfireController] Initialised")
end

return CampfireController
