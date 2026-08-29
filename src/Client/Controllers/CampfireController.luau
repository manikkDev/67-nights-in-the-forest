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
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

-- | Modules | --
local Knit = require(ReplicatedStorage.Packages.Knit)
local ServerRole = require(ReplicatedStorage.Shared.ServerRole)
local WorldProgressionConfig = require(ReplicatedStorage.Shared.WorldProgressionConfig)

-- | Objects | --
local CampfireController = Knit.CreateController({
	Name = "CampfireController",
})

-- | Configuration | --
local PANEL_WIDTH = 250
local PANEL_HEIGHT = 130
local PANEL_MARGIN = 14
local BAR_HEIGHT = 10
local BILLBOARD_WIDTH = 8
local BILLBOARD_HEIGHT = 1.2
local BILLBOARD_Y_OFFSET = 3.5
local TOP_BAR_COLOR = Color3.fromRGB(245, 220, 0)
local BASE_CAMP_RANGE = 18
local SHOW_RANGE_BONUS = 8
local BAR_TWEEN_INFO = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local WARNING_TWEEN_INFO = TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local LEVELUP_TWEEN_INFO = TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local LEVELUP_HOLD_TIME = 3

-- | State Management | --
local campfireGui: ScreenGui? = nil
local warningGui: ScreenGui? = nil
local fuelFill: Frame? = nil
local levelFill: Frame? = nil
local fuelValueLabel: TextLabel? = nil
local levelValueLabel: TextLabel? = nil
local levelLabel: TextLabel? = nil
local statusLabel: TextLabel? = nil
local warningLabel: TextLabel? = nil
local hasFuelState = false

local levelUpGui: ScreenGui? = nil
local levelUpBanner: Frame? = nil
local levelUpBackground: Frame? = nil
local levelUpStroke: UIStroke? = nil
local levelUpTitle: TextLabel? = nil
local levelUpSubtitle: TextLabel? = nil
local levelUpShowingLevel: number = 0

local topLevelBillboard: BillboardGui? = nil
local topLevelText: TextLabel? = nil
local topLevelFill: Frame? = nil
local isLit = false
local currentSafeZoneRadius = 0
local campfireService: any = nil

-- // FUNCTIONS // --

--[[
    @summary  Update the fuel bar colour and fill size.
    @param    fuel     number
    @param    maxFuel  number
    @param    isLit    boolean
]]
local function setFuelBar(fuel: number, maxFuel: number, lit: boolean)
	isLit = lit
	if not fuelFill then
		return
	end

	local fraction = if maxFuel > 0 then math.clamp(fuel / maxFuel, 0, 1) else 0
	local color = Color3.fromRGB(245, 140, 50):Lerp(Color3.fromRGB(220, 60, 60), 1 - fraction)

	fuelFill.BackgroundColor3 = color
	local fillGradient = fuelFill:FindFirstChildOfClass("UIGradient") :: UIGradient?
	if fillGradient then
		fillGradient.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, color),
			ColorSequenceKeypoint.new(1, color:Lerp(Color3.new(0, 0, 0), 0.35)),
		})
	end
	local fillStroke = fuelFill:FindFirstChildOfClass("UIStroke") :: UIStroke?
	if fillStroke then
		fillStroke.Color = color
	end
	TweenService:Create(fuelFill, BAR_TWEEN_INFO, { Size = UDim2.new(fraction, 0, 1, 0) }):Play()

	if fuelValueLabel then
		fuelValueLabel.Text = tostring(math.round(fuel)) .. " / " .. tostring(math.round(maxFuel))
		fuelValueLabel.TextColor3 = color
	end

	if statusLabel then
		statusLabel.Text = if isLit then "Lit" else "OUT"
		statusLabel.TextColor3 = if isLit then Color3.fromRGB(120, 220, 120) else Color3.fromRGB(220, 80, 80)
	end
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
    @summary  Update visibility of the world-space level progress billboard.
]]
local function onHeartbeat(dt: number)
	-- State variables (isLit, currentSafeZoneRadius) are kept up-to-date by
	-- :Observe() callbacks on the ClientRemoteProperty objects. Do NOT poll
	-- :Get() here — it returns nil before the property has synced from the
	-- server, which would overwrite correct values with 0/false.
	if not topLevelBillboard or not topLevelBillboard.Adornee then
		return
	end

	local character = Players.LocalPlayer.Character
	if not character then
		topLevelBillboard.Enabled = false
		return
	end

	local hrp = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hrp then
		topLevelBillboard.Enabled = false
		return
	end

	local showRange = math.max(currentSafeZoneRadius, BASE_CAMP_RANGE) + SHOW_RANGE_BONUS
	local adornee = topLevelBillboard.Adornee
	if not adornee or not adornee:IsA("BasePart") then
		topLevelBillboard.Enabled = false
		return
	end
	local distance = (hrp.Position - (adornee :: BasePart).Position).Magnitude
	local show = distance <= showRange
	if topLevelBillboard.Enabled ~= show then
		topLevelBillboard.Enabled = show
	end
end

--[[
    @summary  Track safe zone radius for the billboard show range.
]]
local function onSafeZoneChanged(radius: number, active: boolean)
	currentSafeZoneRadius = radius
	isLit = active
end

--[[
    @summary  Update the level bar fill size and level label.
    @param    level       number
    @param    progress    number
    @param    requirement number
]]
local function setTopLevelBar(level: number, progress: number, requirement: number)
	if topLevelText then
		topLevelText.Text = "level " .. tostring(level) .. " progress: " .. tostring(math.round(progress)) .. "/" .. tostring(math.round(requirement))
	end
	if topLevelFill then
		local fraction = if requirement > 0 then math.clamp(progress / requirement, 0, 1) else 1
		TweenService:Create(topLevelFill, BAR_TWEEN_INFO, { Size = UDim2.new(fraction, 0, 1, 0) }):Play()
	end
end

local function setLevelBar(level: number, progress: number, requirement: number)
	if levelLabel then
		levelLabel.Text = "LVL " .. tostring(level)
	end
	if not levelFill then
		return
	end

	local fraction = if requirement > 0 then math.clamp(progress / requirement, 0, 1) else 1
	TweenService:Create(levelFill, BAR_TWEEN_INFO, { Size = UDim2.new(fraction, 0, 1, 0) }):Play()

	if levelValueLabel and levelFill then
		levelValueLabel.Text = tostring(math.round(progress)) .. " / " .. tostring(math.round(requirement))
		levelValueLabel.TextColor3 = levelFill.BackgroundColor3
	end

	setTopLevelBar(level, progress, requirement)
end

--[[
    @summary  Build or rebuild the warning ScreenGui.
    @returns  TextLabel
]]
local function buildWarning(): TextLabel
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	if not playerGui then
		return Instance.new("TextLabel")
	end
	local existing = playerGui:FindFirstChild("CampfireWarningGui")
	if existing then
		existing:Destroy()
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = "CampfireWarningGui"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.Enabled = false
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
	label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	label.TextStrokeTransparency = 0.3
	label.Parent = gui

	warningLabel = label
	warningGui = gui
	return label
end

--[[
    @summary  Build the centered level-up banner.
    @returns  Frame
]]
local function buildLevelUpBanner(): Frame
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	if not playerGui then
		return Instance.new("Frame")
	end
	local existing = playerGui:FindFirstChild("CampfireLevelUpGui")
	if existing then
		existing:Destroy()
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = "CampfireLevelUpGui"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 10
	gui.Enabled = false
	gui.Parent = playerGui
	levelUpGui = gui

	local banner = Instance.new("Frame")
	banner.Name = "Banner"
	banner.AnchorPoint = Vector2.new(0.5, 0.5)
	banner.Position = UDim2.new(0.5, 0, 0.5, -40)
	banner.Size = UDim2.new(0, 360, 0, 80)
	banner.BackgroundTransparency = 1
	banner.BorderSizePixel = 0
	banner.Parent = gui
	levelUpBanner = banner

	local background = Instance.new("Frame")
	background.Name = "Background"
	background.Size = UDim2.new(1, 0, 1, 0)
	background.BackgroundColor3 = Color3.fromRGB(42, 44, 54)
	background.BackgroundTransparency = 1
	background.BorderSizePixel = 0
	background.Parent = banner
	levelUpBackground = background

	local bgCorner = Instance.new("UICorner")
	bgCorner.CornerRadius = UDim.new(0, 10)
	bgCorner.Parent = background

	local bgStroke = Instance.new("UIStroke")
	bgStroke.Color = Color3.fromRGB(230, 160, 70)
	bgStroke.Transparency = 1
	bgStroke.Thickness = 2
	bgStroke.Parent = background
	levelUpStroke = bgStroke

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
	title.TextTransparency = 1
	title.Text = "CAMPFIRE LEVEL 2!"
	title.TextColor3 = Color3.fromRGB(255, 230, 180)
	title.Font = Enum.Font.GothamBlack
	title.TextSize = 24
	title.TextXAlignment = Enum.TextXAlignment.Center
	title.TextYAlignment = Enum.TextYAlignment.Bottom
	title.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	title.TextStrokeTransparency = 0.3
	title.Parent = banner
	levelUpTitle = title

	local subtitle = Instance.new("TextLabel")
	subtitle.Name = "Subtitle"
	subtitle.Size = UDim2.new(1, 0, 0.4, 0)
	subtitle.Position = UDim2.new(0, 0, 0.6, 0)
	subtitle.BackgroundTransparency = 1
	subtitle.TextTransparency = 1
	subtitle.Text = "Safe zone expanded"
	subtitle.TextColor3 = Color3.fromRGB(240, 240, 245)
	subtitle.Font = Enum.Font.GothamBold
	subtitle.TextSize = 15
	subtitle.TextXAlignment = Enum.TextXAlignment.Center
	subtitle.TextYAlignment = Enum.TextYAlignment.Top
	subtitle.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	subtitle.TextStrokeTransparency = 0.4
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
local function buildStatRow(parent: Frame, name: string, y: number, labelText: string, color: Color3): (Frame, TextLabel)
	local panel = parent

	local icon = Instance.new("Frame")
	icon.Name = name .. "Icon"
	icon.Size = UDim2.new(0, 16, 0, 16)
	icon.Position = UDim2.new(0, PANEL_MARGIN, 0, y + 2)
	icon.BackgroundColor3 = color
	icon.BorderSizePixel = 0
	icon.Parent = panel

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
	label.Size = UDim2.new(0, 44, 0, 16)
	label.Position = UDim2.new(0, PANEL_MARGIN + 22, 0, y + 2)
	label.BackgroundTransparency = 1
	label.Text = labelText
	label.TextColor3 = Color3.fromRGB(220, 220, 225)
	label.Font = Enum.Font.GothamBold
	label.TextSize = 13
	label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	label.TextStrokeTransparency = 0.4
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Parent = panel

	local barBackground = Instance.new("Frame")
	barBackground.Name = name .. "BarBackground"
	barBackground.Size = UDim2.new(0, 96, 0, BAR_HEIGHT)
	barBackground.Position = UDim2.new(0, PANEL_MARGIN + 70, 0, y + 5)
	barBackground.BackgroundColor3 = Color3.fromRGB(28, 28, 34)
	barBackground.BackgroundTransparency = 0.05
	barBackground.BorderSizePixel = 0
	barBackground.Parent = panel

	local bgCorner = Instance.new("UICorner")
	bgCorner.CornerRadius = UDim.new(0, 4)
	bgCorner.Parent = barBackground

	local bgStroke = Instance.new("UIStroke")
	bgStroke.Color = Color3.fromRGB(80, 80, 90)
	bgStroke.Transparency = 0.5
	bgStroke.Thickness = 1
	bgStroke.Parent = barBackground

	local fill = Instance.new("Frame")
	fill.Name = name .. "Fill"
	fill.Size = UDim2.new(1, 0, 1, 0)
	fill.BackgroundColor3 = color
	fill.BackgroundTransparency = 0.05
	fill.BorderSizePixel = 0
	fill.Parent = barBackground

	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0, 4)
	fillCorner.Parent = fill

	local fillGradient = Instance.new("UIGradient")
	fillGradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, color),
		ColorSequenceKeypoint.new(1, color:Lerp(Color3.new(0, 0, 0), 0.35)),
	})
	fillGradient.Rotation = 90
	fillGradient.Parent = fill

	local fillStroke = Instance.new("UIStroke")
	fillStroke.Color = color
	fillStroke.Transparency = 0.65
	fillStroke.Thickness = 1
	fillStroke.Parent = fill

	local valueLabel = Instance.new("TextLabel")
	valueLabel.Name = name .. "Value"
	valueLabel.Size = UDim2.new(0, 52, 0, 16)
	valueLabel.Position = UDim2.new(0, PANEL_WIDTH - PANEL_MARGIN - 52, 0, y + 2)
	valueLabel.BackgroundTransparency = 1
	valueLabel.Text = "0/0"
	valueLabel.TextColor3 = Color3.fromRGB(240, 240, 245)
	valueLabel.Font = Enum.Font.GothamBold
	valueLabel.TextSize = 13
	valueLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	valueLabel.TextStrokeTransparency = 0.4
	valueLabel.TextXAlignment = Enum.TextXAlignment.Right
	valueLabel.Parent = panel

	return fill, valueLabel
end

local function _findCampfireFire(): BasePart?
	local baseMap = workspace:FindFirstChild("Base-map")
	if not baseMap then
		return nil
	end
	local bonfire = baseMap:FindFirstChild("Bonfire")
	if not bonfire then
		return nil
	end
	return bonfire:FindFirstChild("Fire") :: BasePart?
end

--[[
    @summary  Build the world-space BillboardGui above the campfire.
]]
local function buildTopLevelProgressBar()
	task.spawn(function()
		local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
		if not playerGui then
			return
		end

		local existing = playerGui:FindFirstChild("CampfireLevelProgressBillboard")
		if existing then
			existing:Destroy()
		end

		-- The map/bonfire can take time to load, so wait for it instead of timing out quickly.
		local baseMap = workspace:WaitForChild("Base-map")
		if not baseMap then
			warn("[CampfireController] Base-map not found for billboard")
			return
		end
		local bonfire = baseMap:WaitForChild("Bonfire")
		if not bonfire then
			warn("[CampfireController] Bonfire not found for billboard")
			return
		end
		local firePart = bonfire:WaitForChild("Fire", 60) :: BasePart?
		if not firePart then
			-- The Fire part may stream in after a delay; try a slower retry.
			local start = os.clock()
			while not firePart and (os.clock() - start) < 60 do
				firePart = bonfire:FindFirstChild("Fire") :: BasePart?
				if not firePart then
					task.wait(1)
				end
			end
			if not firePart then
				warn("[CampfireController] Could not find campfire Fire part for billboard")
				return
			end
		end

		-- Remove any old placeholder billboard that may exist on the fire part.
		for _, child in ipairs(firePart:GetChildren()) do
			if child:IsA("BillboardGui") then
				child:Destroy()
			end
		end

		local billboard = Instance.new("BillboardGui")
		billboard.Name = "CampfireLevelProgressBillboard"
		billboard.Adornee = firePart
		billboard.AlwaysOnTop = true
		billboard.LightInfluence = 0
		billboard.Size = UDim2.new(BILLBOARD_WIDTH, 0, BILLBOARD_HEIGHT, 0)
		billboard.StudsOffsetWorldSpace = Vector3.new(0, BILLBOARD_Y_OFFSET, 0)
		billboard.Enabled = false
		billboard.Parent = firePart
		topLevelBillboard = billboard

		local container = Instance.new("Frame")
		container.Name = "Container"
		container.Size = UDim2.new(1, 0, 1, 0)
		container.BackgroundTransparency = 1
		container.BorderSizePixel = 0
		container.Parent = billboard

		local textLabel = Instance.new("TextLabel")
		textLabel.Name = "LevelText"
		textLabel.Size = UDim2.new(1, 0, 0.45, 0)
		textLabel.Position = UDim2.new(0, 0, 0, 0)
		textLabel.BackgroundTransparency = 1
		textLabel.Text = "level 1 progress: 0/100"
		textLabel.TextColor3 = Color3.fromRGB(240, 240, 240)
		textLabel.Font = Enum.Font.GothamBold
		textLabel.TextScaled = true
		textLabel.TextXAlignment = Enum.TextXAlignment.Center
		textLabel.TextYAlignment = Enum.TextYAlignment.Bottom

		local textStroke = Instance.new("UIStroke")
		textStroke.Color = Color3.fromRGB(0, 0, 0)
		textStroke.Thickness = 1.5
		textStroke.Transparency = 0.4
		textStroke.Parent = textLabel

		textLabel.Parent = container
		topLevelText = textLabel

		local barBackground = Instance.new("Frame")
		barBackground.Name = "BarBackground"
		barBackground.Size = UDim2.new(1, 0, 0.45, 0)
		barBackground.Position = UDim2.new(0, 0, 0.55, 0)
		barBackground.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
		barBackground.BorderSizePixel = 0
		barBackground.Parent = container

		local barFill = Instance.new("Frame")
		barFill.Name = "BarFill"
		barFill.Size = UDim2.new(1, 0, 1, 0)
		barFill.BackgroundColor3 = TOP_BAR_COLOR
		barFill.BorderSizePixel = 0
		barFill.Parent = barBackground
		topLevelFill = barFill
	end)
end

--[[
    @summary  Build or rebuild the campfire HUD panel.
]]
local function buildGui()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	if not playerGui then
		return
	end
	local existing = playerGui:FindFirstChild("CampfireGui")
	if existing then
		existing:Destroy()
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = "CampfireGui"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 2
	gui.Enabled = false
	gui.Parent = playerGui
	campfireGui = gui

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0, 1)
	panel.Position = UDim2.new(0, PANEL_MARGIN, 1, -PANEL_MARGIN)
	panel.Size = UDim2.new(0, PANEL_WIDTH, 0, PANEL_HEIGHT)
	panel.BackgroundColor3 = Color3.fromRGB(38, 40, 48)
	panel.BackgroundTransparency = 0.02
	panel.BorderSizePixel = 0
	panel.Parent = gui

	local panelCorner = Instance.new("UICorner")
	panelCorner.CornerRadius = UDim.new(0, 12)
	panelCorner.Parent = panel

	local panelStroke = Instance.new("UIStroke")
	panelStroke.Color = Color3.fromRGB(230, 160, 70)
	panelStroke.Transparency = 0.25
	panelStroke.Thickness = 1.5
	panelStroke.Parent = panel

	-- Keep the card solid; a UIGradient here would make it look glassy/transparent.

	local header = Instance.new("TextLabel")
	header.Name = "Header"
	header.Size = UDim2.new(0, 120, 0, 22)
	header.Position = UDim2.new(0, PANEL_MARGIN, 0, 8)
	header.BackgroundTransparency = 1
	header.Text = "CAMPFIRE"
	header.TextColor3 = Color3.fromRGB(230, 220, 200)
	header.Font = Enum.Font.GothamBlack
	header.TextSize = 16
	header.TextXAlignment = Enum.TextXAlignment.Left
	header.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	header.TextStrokeTransparency = 0.3
	header.Parent = panel

	local levelLabelInstance = Instance.new("TextLabel") :: TextLabel
	levelLabelInstance.Name = "LevelLabel"
	levelLabelInstance.Size = UDim2.new(0, 70, 0, 22)
	levelLabelInstance.Position = UDim2.new(1, -PANEL_MARGIN - 70, 0, 8)
	levelLabelInstance.BackgroundTransparency = 1
	levelLabelInstance.Text = "LVL 1"
	levelLabelInstance.TextColor3 = Color3.fromRGB(230, 220, 200)
	levelLabelInstance.Font = Enum.Font.GothamBold
	levelLabelInstance.TextSize = 16
	levelLabelInstance.TextXAlignment = Enum.TextXAlignment.Right
	levelLabelInstance.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	levelLabelInstance.TextStrokeTransparency = 0.3
	levelLabelInstance.Parent = panel
	levelLabel = levelLabelInstance

	fuelFill, fuelValueLabel = buildStatRow(panel, "Fuel", 38, "FUEL", Color3.fromRGB(245, 140, 50))
	levelFill, levelValueLabel = buildStatRow(panel, "Level", 72, "LEVEL", Color3.fromRGB(240, 180, 30))

	local statusLabelInstance = Instance.new("TextLabel") :: TextLabel
	statusLabelInstance.Name = "StatusLabel"
	statusLabelInstance.Size = UDim2.new(1, -PANEL_MARGIN * 2, 0, 16)
	statusLabelInstance.Position = UDim2.new(0, PANEL_MARGIN, 0, 106)
	statusLabelInstance.BackgroundTransparency = 1
	statusLabelInstance.Text = "Lit"
	statusLabelInstance.TextColor3 = Color3.fromRGB(120, 220, 120)
	statusLabelInstance.Font = Enum.Font.GothamBold
	statusLabelInstance.TextSize = 14
	statusLabelInstance.TextXAlignment = Enum.TextXAlignment.Left
	statusLabelInstance.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	statusLabelInstance.TextStrokeTransparency = 0.4
	statusLabelInstance.Parent = panel
	statusLabel = statusLabelInstance

	buildWarning()
end

--[[
    @summary  Handler for FuelChanged signal.
]]
local function onFuelChanged(fuel: number, maxFuel: number, fraction: number, isLit: boolean)
	setFuelBar(fuel, maxFuel, isLit)

	-- Keep the warning hidden until we have seen a lit state at least once.
	if hasFuelState then
		setWarning(isLit)
	else
		setWarning(true)
		hasFuelState = true
	end
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
	if not levelUpGui or not levelUpBanner or not levelUpBackground or not levelUpStroke or not levelUpTitle or not levelUpSubtitle then
		return
	end

	-- Ignore duplicate level-up spams; only a new level should restart.
	if newLevel == levelUpShowingLevel then
		return
	end
	levelUpShowingLevel = newLevel

	levelUpTitle.Text = "CAMPFIRE LEVEL " .. tostring(newLevel) .. "!"
	levelUpSubtitle.Text = string.format(
		"Safe zone: %d studs  •  Fog cleared: %d studs",
		math.round(radius or 0),
		math.round(WorldProgressionConfig.GetAccessRadius(newLevel))
	)

	-- Start fully transparent and slide up while fading in.
	levelUpBanner.Position = UDim2.new(0.5, 0, 0.5, 60)
	levelUpBanner.Size = UDim2.new(0, 360, 0, 80)
	levelUpBackground.BackgroundTransparency = 1
	levelUpStroke.Transparency = 1
	levelUpTitle.TextTransparency = 1
	levelUpSubtitle.TextTransparency = 1
	levelUpGui.Enabled = true

	local inTweens: { Tween } = {}
	table.insert(inTweens, TweenService:Create(levelUpBanner, LEVELUP_TWEEN_INFO, {
		Position = UDim2.new(0.5, 0, 0.5, -40),
	}))
	table.insert(inTweens, TweenService:Create(levelUpBackground, LEVELUP_TWEEN_INFO, {
		BackgroundTransparency = 0.05,
	}))
	table.insert(inTweens, TweenService:Create(levelUpStroke, LEVELUP_TWEEN_INFO, {
		Transparency = 0.3,
	}))
	table.insert(inTweens, TweenService:Create(levelUpTitle, LEVELUP_TWEEN_INFO, {
		TextTransparency = 0,
	}))
	table.insert(inTweens, TweenService:Create(levelUpSubtitle, LEVELUP_TWEEN_INFO, {
		TextTransparency = 0,
	}))
	for _, tween in ipairs(inTweens) do
		tween:Play()
	end

	task.spawn(function()
		local expectedLevel = newLevel
		inTweens[1].Completed:Wait()

		if levelUpShowingLevel ~= expectedLevel then
			return
		end
		task.wait(LEVELUP_HOLD_TIME)
		if levelUpShowingLevel ~= expectedLevel or not levelUpBanner or not levelUpBackground or not levelUpStroke or not levelUpTitle or not levelUpSubtitle then
			return
		end

		local outTweens: { Tween } = {}
		table.insert(outTweens, TweenService:Create(levelUpBanner, LEVELUP_TWEEN_INFO, {
			Position = UDim2.new(0.5, 0, 0.5, -90),
		}))
		table.insert(outTweens, TweenService:Create(levelUpBackground, LEVELUP_TWEEN_INFO, {
			BackgroundTransparency = 1,
		}))
		table.insert(outTweens, TweenService:Create(levelUpStroke, LEVELUP_TWEEN_INFO, {
			Transparency = 1,
		}))
		table.insert(outTweens, TweenService:Create(levelUpTitle, LEVELUP_TWEEN_INFO, {
			TextTransparency = 1,
		}))
		table.insert(outTweens, TweenService:Create(levelUpSubtitle, LEVELUP_TWEEN_INFO, {
			TextTransparency = 1,
		}))
		for _, tween in ipairs(outTweens) do
			tween:Play()
		end
		outTweens[1].Completed:Wait()

		if levelUpGui and levelUpShowingLevel == expectedLevel then
			levelUpGui.Enabled = false
			levelUpShowingLevel = 0
		end
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
	if not ServerRole.IsGameServer() then return end
	buildGui()
	buildTopLevelProgressBar()
	buildLevelUpBanner()
	buildWarning()

	local gameStateController = Knit.GetController("GameStateController")
	local runStateService = Knit.GetService("RunStateService")
	campfireService = Knit.GetService("CampfireService")

	local function onGameStarted()
		if campfireGui then
			campfireGui.Enabled = true
		end
		if warningGui then
			warningGui.Enabled = true
		end
		if topLevelBillboard then
			topLevelBillboard.Enabled = true
		end
	end

	if gameStateController and gameStateController:IsInGame() then
		onGameStarted()
	else
		if gameStateController then
			gameStateController.GameStarted:Connect(onGameStarted)
		end
	end

	campfireService.FuelChanged:Connect(onFuelChanged)
	campfireService.LevelChanged:Connect(onLevelChanged)
	campfireService.SafeZoneChanged:Connect(onSafeZoneChanged)
	campfireService.LevelUp:Connect(onLevelUp)

	-- Use :Observe() on ClientRemoteProperty objects to keep local state
	-- authoritative. :Observe() fires the initial value once the property
	-- has synced from the server, and on every subsequent change.
	if campfireService.IsLit then
		campfireService.IsLit:Observe(function(newValue: any)
			local newLit = newValue == true
			if newLit ~= isLit then
				isLit = newLit
				setWarning(isLit)
			end
		end)
	end
	if campfireService.SafeZoneRadius then
		campfireService.SafeZoneRadius:Observe(function(newValue: any)
			currentSafeZoneRadius = newValue or 0
		end)
	end

	runStateService.RunPhaseChanged:Connect(function(payload)
		if typeof(payload) == "table" and payload.phase == "Lobby" then
			if campfireGui then campfireGui.Enabled = false end
			if warningGui then warningGui.Enabled = false end
			if levelUpGui then levelUpGui.Enabled = false end
			if topLevelBillboard then topLevelBillboard.Enabled = false end
		end
	end)

	RunService.Heartbeat:Connect(onHeartbeat)

	-- The initial state is sent by the server through the signal connections.
end

return CampfireController
