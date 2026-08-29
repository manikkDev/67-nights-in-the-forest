--[[
    @file    InventoryController.luau
    @author  manik
    @date    2026

    @summary
    Professional carry-bag inventory UI — compact right-side sidebar.

    @description
    A vertical resource sidebar that slides in from the right when the Carry Bag
    tool is equipped. Each resource row shows a coloured icon slot, the resource
    name, a bold count, and (on hover) Eat / Drop action pills. A slim capacity
    bar with a numeric readout sits at the bottom of the panel.

    On touch devices the action pills stay visible because there is no hover.

    @exports
    - InventoryController (Knit Controller)
]]

-- // VARIABLES // --

-- | Services | --
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

-- | Modules | --
local Knit = require(ReplicatedStorage.Packages.Knit)
local ServerRole = require(ReplicatedStorage.Shared.ServerRole)
local JunkItemConfig = require(ReplicatedStorage.Shared.JunkItemConfig)

-- | Objects | --
local InventoryController = Knit.CreateController({
	Name = "InventoryController",
})

-- | Configuration | --
local BAG_TOOL_NAME = "Carry Bag"

-- Panel dimensions
local PANEL_WIDTH = 280
local PANEL_MARGIN = 32
local ROW_HEIGHT = 46
local ROW_GAP = 4
local PANEL_PADDING = 10
local PANEL_GAP = 8
local ICON_SIZE = 30
local HEADER_HEIGHT = 20
local CAPACITY_CONTAINER_HEIGHT = 24
local DROP_ALL_HEIGHT = 30
local ROW_PADDING_X = 8
local ROW_PADDING_Y = 6
local ACTION_BUTTON_WIDTH = 34
local ACTION_GAP = 4
local CAPACITY_HEIGHT = 4

-- Maximum bag panel height before the row list starts scrolling.
-- Keeps the panel on-screen regardless of how many resource types exist.
local MAX_PANEL_HEIGHT = 460

--[[
    @summary  Format large counts compactly (e.g. 1.2k, 12k, 1.0M).
    @param    n  number
    @returns  string
]]
local function formatCount(n: number): string
	if n < 1000 then
		return tostring(n)
	elseif n < 10000 then
		return string.format("%.1fk", n / 1000)
	elseif n < 1000000 then
		return string.format("%.0fk", n / 1000)
	else
		return string.format("%.1fM", n / 1000000)
	end
end

-- Tween timings
local TWEEN_SLIDE = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local TWEEN_BOUNCE = TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local TWEEN_HOVER = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local TWEEN_FADE = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local TWEEN_COUNT_POP = TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local TWEEN_CAPACITY = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

-- Content data
local EDIBLE_RESOURCES = { Berries = true, Mushrooms = true, RawMeat = true, CookedMeat = true }
local ROW_ORDER = {
	"Wood",
	"WoodenSheet",
	"Scrap",
	"Coal",
	"Berries",
	"Mushrooms",
	"RawMeat",
	"CookedMeat",
	"Bandage",
	"CultistGem",
	"Bolt",
	"SheetMetal",
	"OldRadio",
	"BrokenFan",
	"BrokenMicrowave",
	"Tyre",
	"MetalChair",
}
local ROW_COLORS = {
	Wood = Color3.fromRGB(170, 110, 65),
	WoodenSheet = Color3.fromRGB(200, 175, 120),
	Scrap = Color3.fromRGB(150, 155, 165),
	Coal = Color3.fromRGB(70, 70, 75),
	Bandage = Color3.fromRGB(235, 235, 225),
	CultistGem = Color3.fromRGB(175, 90, 210),
	Berries = Color3.fromRGB(195, 50, 80),
	Mushrooms = Color3.fromRGB(210, 110, 95),
	RawMeat = Color3.fromRGB(200, 100, 100),
	CookedMeat = Color3.fromRGB(215, 160, 80),
	Bolt = Color3.fromRGB(140, 140, 145),
	SheetMetal = Color3.fromRGB(170, 170, 175),
	OldRadio = Color3.fromRGB(80, 60, 45),
	BrokenFan = Color3.fromRGB(100, 100, 105),
	BrokenMicrowave = Color3.fromRGB(220, 220, 215),
	Tyre = Color3.fromRGB(30, 30, 30),
	MetalChair = Color3.fromRGB(90, 95, 100),
}
local ROW_DESCRIPTIONS = {
	Wood = "Used for building and fueling campfires.",
	WoodenSheet = "Shredded from wood at the Shredder. Used for advanced crafting.",
	Scrap = "Salvaged metal used for advanced crafting.",
	Coal = "Burns far longer than wood in the campfire.",
	Bandage = "Revives a downed teammate.",
	CultistGem = "A rare cultist relic used in late crafting.",
	Berries = "Restores a small amount of hunger.",
	Mushrooms = "Restores a small amount of hunger.",
	RawMeat = "Cook it at the campfire to restore more hunger.",
	CookedMeat = "A filling meal that restores lots of hunger.",
	Bolt = "Junk. Grind at the Shredder for 1 Scrap.",
	SheetMetal = "Junk. Grind at the Shredder for 1 Scrap.",
	OldRadio = "Junk. Grind at the Shredder for 2 Scrap.",
	BrokenFan = "Junk. Grind at the Shredder for 2 Scrap.",
	BrokenMicrowave = "Junk. Grind at the Shredder for 3 Scrap.",
	Tyre = "Junk. Grind at the Shredder for 3 Scrap.",
	MetalChair = "Junk. Grind at the Shredder for 3 Scrap.",
}

-- | State Management | --
local localPlayer = Players.LocalPlayer

type RowEntry = {
	row: Frame,
	icon: Frame,
	countLabel: TextLabel,
	nameLabel: TextLabel,
	countBadge: TextLabel,
	eatButton: TextButton,
	dropButton: TextButton,
	actionContainer: Frame,
	lastCount: number,
}

local rowEntries: { [string]: RowEntry } = {}

local bagPanel: Frame? = nil
local bagGui: ScreenGui? = nil
local bagShadow: Frame? = nil
local capacityFill: Frame? = nil
local capacityText: TextLabel? = nil
local tooltipFrame: Frame? = nil
local tooltipTitle: TextLabel? = nil
local tooltipCount: TextLabel? = nil
local tooltipDesc: TextLabel? = nil

local isOpen = false
local useHover = UserInputService.MouseEnabled and not UserInputService.TouchEnabled
local gameStateController: any = nil

-- // FUNCTIONS // --

--[[
    @summary  Build the hover tooltip that appears to the left of a row.
]]
local function buildTooltip(parent: ScreenGui): Frame
	local tooltip = Instance.new("Frame")
	tooltip.Name = "CarryBagTooltip"
	tooltip.Size = UDim2.new(0, 240, 0, 0)
	tooltip.AutomaticSize = Enum.AutomaticSize.Y
	tooltip.BackgroundColor3 = Color3.fromRGB(24, 24, 28)
	tooltip.BackgroundTransparency = 1
	tooltip.BorderSizePixel = 0
	tooltip.ZIndex = 50
	tooltip.Visible = false
	tooltip.Parent = parent

	local tooltipGradient = Instance.new("UIGradient")
	tooltipGradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(235, 235, 245)),
	})
	tooltipGradient.Rotation = 90
	tooltipGradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.15),
		NumberSequenceKeypoint.new(1, 0.35),
	})
	tooltipGradient.Parent = tooltip

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = tooltip

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(100, 100, 115)
	stroke.Thickness = 1
	stroke.Transparency = 0.1
	stroke.Parent = tooltip

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 4)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = tooltip

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 12)
	padding.PaddingRight = UDim.new(0, 12)
	padding.PaddingTop = UDim.new(0, 10)
	padding.PaddingBottom = UDim.new(0, 10)
	padding.Parent = tooltip

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(1, 0, 0, 18)
	title.BackgroundTransparency = 1
	title.TextColor3 = Color3.fromRGB(245, 245, 245)
	title.Font = Enum.Font.GothamBlack
	title.TextSize = 16
	title.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	title.TextStrokeTransparency = 0.3
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextYAlignment = Enum.TextYAlignment.Top
	title.LayoutOrder = 1
	title.Parent = tooltip

	local count = Instance.new("TextLabel")
	count.Name = "Count"
	count.Size = UDim2.new(1, 0, 0, 16)
	count.BackgroundTransparency = 1
	count.TextColor3 = Color3.fromRGB(200, 200, 210)
	count.Font = Enum.Font.GothamBold
	count.TextSize = 13
	count.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	count.TextStrokeTransparency = 0.4
	count.TextXAlignment = Enum.TextXAlignment.Left
	count.TextYAlignment = Enum.TextYAlignment.Top
	count.LayoutOrder = 2
	count.Parent = tooltip

	local desc = Instance.new("TextLabel")
	desc.Name = "Description"
	desc.Size = UDim2.new(1, 0, 0, 0)
	desc.AutomaticSize = Enum.AutomaticSize.Y
	desc.BackgroundTransparency = 1
	desc.TextColor3 = Color3.fromRGB(170, 170, 185)
	desc.Font = Enum.Font.GothamBold
	desc.TextSize = 14
	desc.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	desc.TextStrokeTransparency = 0.4
	desc.TextWrapped = true
	desc.TextXAlignment = Enum.TextXAlignment.Left
	desc.TextYAlignment = Enum.TextYAlignment.Top
	desc.LayoutOrder = 3
	desc.Parent = tooltip

	tooltipTitle = title
	tooltipCount = count
	tooltipDesc = desc

	return tooltip
end

--[[
    @summary  Show the tooltip anchored to the left of the given row.
]]
local function showTooltip(row: Frame, resourceName: string, count: number)
	if not tooltipFrame or not tooltipTitle or not tooltipCount or not tooltipDesc then
		return
	end

	local junkConfig = JunkItemConfig[resourceName]
	local displayName = junkConfig and junkConfig.DisplayName or resourceName
	tooltipTitle.Text = displayName
	tooltipCount.Text = "Count: " .. formatCount(count)
	tooltipDesc.Text = ROW_DESCRIPTIONS[resourceName] or ""

	local color = ROW_COLORS[resourceName] or Color3.fromRGB(245, 245, 245)
	tooltipTitle.TextColor3 = color

	local stroke = tooltipFrame:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = color
	end

	local rowPos = row.AbsolutePosition
	local rowSize = row.AbsoluteSize

	-- Tooltip width is fixed at 240, height is automatic.
	local targetX = rowPos.X - 240 - 14
	local targetY = rowPos.Y + (rowSize.Y - 60) / 2

	-- Clamp to screen edges.
	local viewport = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize
	if viewport then
		targetX = math.max(8, math.min(targetX, viewport.X - 248))
		targetY = math.max(8, math.min(targetY, viewport.Y - 60))
	end

	tooltipFrame.Position = UDim2.fromOffset(targetX, targetY)
	tooltipFrame.Visible = true

	TweenService:Create(tooltipFrame, TWEEN_FADE, { BackgroundTransparency = 0 }):Play()
end

--[[
    @summary  Hide the tooltip.
]]
local function hideTooltip()
	if tooltipFrame then
		local tween = TweenService:Create(tooltipFrame, TWEEN_FADE, { BackgroundTransparency = 1 })
		tween:Play()
		tween.Completed:Connect(function()
			if tooltipFrame and tooltipFrame.BackgroundTransparency >= 0.99 then
				tooltipFrame.Visible = false
			end
		end)
	end
end

--[[
    @summary  Build a small pill-style action button.
]]
local function buildPillButton(name: string, text: string, color: Color3, hoverColor: Color3, parent: Frame): TextButton
	local button = Instance.new("TextButton")
	button.Name = name
	button.Size = UDim2.new(0, ACTION_BUTTON_WIDTH, 0, 24)
	button.BackgroundColor3 = color
	button.BackgroundTransparency = 0.15
	button.BorderSizePixel = 0
	button.AutoButtonColor = false
	button.Text = text
	button.TextColor3 = Color3.fromRGB(255, 255, 255)
	button.Font = Enum.Font.GothamBold
	button.TextSize = 11
	button.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	button.TextStrokeTransparency = 0.3
	button.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = button

	local stroke = Instance.new("UIStroke")
	stroke.Color = hoverColor
	stroke.Thickness = 1
	stroke.Transparency = 0.7
	stroke.Parent = button

	button.MouseEnter:Connect(function()
		TweenService:Create(button, TWEEN_HOVER, { BackgroundColor3 = hoverColor, Size = UDim2.new(0, ACTION_BUTTON_WIDTH + 4, 0, 24) }):Play()
	end)
	button.MouseLeave:Connect(function()
		TweenService:Create(button, TWEEN_HOVER, { BackgroundColor3 = color, Size = UDim2.new(0, ACTION_BUTTON_WIDTH, 0, 24) }):Play()
	end)
	button.MouseButton1Down:Connect(function()
		TweenService:Create(button, TWEEN_HOVER, { Size = UDim2.new(0, ACTION_BUTTON_WIDTH - 2, 0, 22) }):Play()
	end)
	button.MouseButton1Up:Connect(function()
		TweenService:Create(button, TWEEN_HOVER, { Size = UDim2.new(0, ACTION_BUTTON_WIDTH, 0, 24) }):Play()
	end)

	return button
end

--[[
    @summary  Build the capacity bar with numeric label at the bottom of the panel.
]]
local function buildCapacityBar(parent: Frame, y: number)
	local contentW = PANEL_WIDTH - 2 * PANEL_PADDING
	local container = Instance.new("Frame")
	container.Name = "CapacityContainer"
	container.Position = UDim2.new(0, PANEL_PADDING, 0, y)
	container.Size = UDim2.new(0, contentW, 0, CAPACITY_HEIGHT + 20)
	container.BackgroundTransparency = 1
	container.BorderSizePixel = 0
	container.Parent = parent

	local barBackground = Instance.new("Frame")
	barBackground.Name = "CapacityBarBackground"
	barBackground.Size = UDim2.new(1, 0, 0, CAPACITY_HEIGHT)
	barBackground.Position = UDim2.new(0, 0, 0, 0)
	barBackground.BackgroundColor3 = Color3.fromRGB(35, 35, 42)
	barBackground.BackgroundTransparency = 0.2
	barBackground.BorderSizePixel = 0
	barBackground.Parent = container

	local bgCorner = Instance.new("UICorner")
	bgCorner.CornerRadius = UDim.new(1, 0)
	bgCorner.Parent = barBackground

	local fill = Instance.new("Frame")
	fill.Name = "CapacityFill"
	fill.Size = UDim2.new(0, 0, 1, 0)
	fill.BackgroundColor3 = Color3.fromRGB(110, 210, 130)
	fill.BackgroundTransparency = 0.05
	fill.BorderSizePixel = 0
	fill.Parent = barBackground

	local fillGradient = Instance.new("UIGradient")
	fillGradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(200, 200, 200)),
	})
	fillGradient.Rotation = 90
	fillGradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.7),
		NumberSequenceKeypoint.new(1, 0.9),
	})
	fillGradient.Parent = fill

	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(1, 0)
	fillCorner.Parent = fill

	local glow = Instance.new("Frame")
	glow.Name = "CapacityGlow"
	glow.Size = UDim2.new(1, 0, 1, 6)
	glow.Position = UDim2.new(0, 0, 0, -3)
	glow.BackgroundColor3 = Color3.fromRGB(110, 210, 130)
	glow.BackgroundTransparency = 0.6
	glow.BorderSizePixel = 0
	glow.ZIndex = 0
	glow.Parent = fill

	local glowCorner = Instance.new("UICorner")
	glowCorner.CornerRadius = UDim.new(1, 0)
	glowCorner.Parent = glow

	local glowGradient = Instance.new("UIGradient")
	glowGradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.7),
		NumberSequenceKeypoint.new(0.5, 0.9),
		NumberSequenceKeypoint.new(1, 1),
	})
	glowGradient.Parent = glow

	local label = Instance.new("TextLabel")
	label.Name = "CapacityText"
	label.Size = UDim2.new(1, 0, 0, 16)
	label.Position = UDim2.new(0, 0, 0, CAPACITY_HEIGHT + 4)
	label.BackgroundTransparency = 1
	label.Text = "0/5"
	label.TextColor3 = Color3.fromRGB(200, 200, 210)
	label.Font = Enum.Font.GothamBold
	label.TextSize = 14
	label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	label.TextStrokeTransparency = 0.4
	label.TextXAlignment = Enum.TextXAlignment.Right
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.Parent = container

	capacityFill = fill
	capacityText = label
end

--[[
    @summary  Build the Drop All button that lives at the bottom of the panel.
]]
local function buildDropAllButton(parent: Frame, y: number): TextButton
	local contentW = PANEL_WIDTH - 2 * PANEL_PADDING
	local container = Instance.new("Frame")
	container.Name = "DropAllContainer"
	container.Position = UDim2.new(0, PANEL_PADDING, 0, y)
	container.Size = UDim2.new(0, contentW, 0, DROP_ALL_HEIGHT)
	container.BackgroundTransparency = 1
	container.BorderSizePixel = 0
	container.Parent = parent

	local button = Instance.new("TextButton")
	button.Name = "DropAllButton"
	button.Size = UDim2.new(1, 0, 1, 0)
	button.BackgroundColor3 = Color3.fromRGB(160, 60, 60)
	button.BackgroundTransparency = 0.12
	button.BorderSizePixel = 0
	button.AutoButtonColor = false
	button.Text = "DROP ALL"
	button.TextColor3 = Color3.fromRGB(255, 255, 255)
	button.Font = Enum.Font.GothamBlack
	button.TextSize = 15
	button.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	button.TextStrokeTransparency = 0.3
	button.Parent = container

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = button

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(190, 75, 75)
	stroke.Thickness = 1
	stroke.Transparency = 0.3
	stroke.Parent = button

	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(200, 200, 200)),
	})
	gradient.Rotation = 90
	gradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.6),
		NumberSequenceKeypoint.new(1, 0.85),
	})
	gradient.Parent = button

	button.MouseEnter:Connect(function()
		TweenService:Create(button, TWEEN_HOVER, { BackgroundColor3 = Color3.fromRGB(190, 75, 75), Size = UDim2.new(1, 4, 1, 4) }):Play()
		TweenService:Create(stroke, TWEEN_HOVER, { Color = Color3.fromRGB(210, 95, 95) }):Play()
	end)
	button.MouseLeave:Connect(function()
		TweenService:Create(button, TWEEN_HOVER, { BackgroundColor3 = Color3.fromRGB(160, 60, 60), Size = UDim2.new(1, 0, 1, 0) }):Play()
		TweenService:Create(stroke, TWEEN_HOVER, { Color = Color3.fromRGB(190, 75, 75) }):Play()
	end)
	button.MouseButton1Down:Connect(function()
		TweenService:Create(button, TWEEN_HOVER, { Size = UDim2.new(1, -2, 1, -2) }):Play()
	end)
	button.MouseButton1Up:Connect(function()
		TweenService:Create(button, TWEEN_HOVER, { Size = UDim2.new(1, 0, 1, 0) }):Play()
	end)

	return button
end

--[[
    @summary  Build a single resource row with icon, labels, and action pills.
]]
local function buildRow(resourceName: string, index: number, parent: Frame): RowEntry
	local color = ROW_COLORS[resourceName] or Color3.fromRGB(120, 120, 120)
	local junkConfig = JunkItemConfig[resourceName]
	local displayName = junkConfig and junkConfig.DisplayName or resourceName

	local row = Instance.new("Frame")
	row.Name = resourceName .. "Row"
	row.Size = UDim2.new(1, 0, 0, ROW_HEIGHT)
	row.BackgroundColor3 = Color3.fromRGB(35, 35, 42)
	row.BackgroundTransparency = 0.3
	row.BorderSizePixel = 0
	row.LayoutOrder = index
	row.ClipsDescendants = true
	row.Parent = parent

	local rowCorner = Instance.new("UICorner")
	rowCorner.CornerRadius = UDim.new(0, 8)
	rowCorner.Parent = row

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, ROW_PADDING_X)
	padding.PaddingRight = UDim.new(0, ROW_PADDING_X)
	padding.PaddingTop = UDim.new(0, ROW_PADDING_Y)
	padding.PaddingBottom = UDim.new(0, ROW_PADDING_Y)
	padding.Parent = row

	-- Icon slot with initial.
	local icon = Instance.new("Frame")
	icon.Name = "IconSlot"
	icon.Size = UDim2.new(0, ICON_SIZE, 0, ICON_SIZE)
	icon.Position = UDim2.new(0, 0, 0.5, -ICON_SIZE / 2)
	icon.BackgroundColor3 = color
	icon.BackgroundTransparency = 0.15
	icon.BorderSizePixel = 0
	icon.Parent = row

	local iconGradient = Instance.new("UIGradient")
	iconGradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(200, 200, 200)),
	})
	iconGradient.Rotation = -45
	iconGradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.1),
		NumberSequenceKeypoint.new(1, 0.25),
	})
	iconGradient.Parent = icon

	local iconStroke = Instance.new("UIStroke")
	iconStroke.Color = Color3.fromRGB(255, 255, 255)
	iconStroke.Thickness = 1
	iconStroke.Transparency = 0.5
	iconStroke.Parent = icon

	local iconCorner = Instance.new("UICorner")
	iconCorner.CornerRadius = UDim.new(0, 8)
	iconCorner.Parent = icon

	local iconInitial = Instance.new("TextLabel")
	iconInitial.Name = "Initial"
	iconInitial.Size = UDim2.new(1, 0, 1, 0)
	iconInitial.BackgroundTransparency = 1
	-- Show bolt symbol for junk items, first letter for everything else
	if junkConfig then
		local bolts = ""
		for _ = 1, junkConfig.BoltCount do
			bolts ..= "\u{1F529}"
		end
		iconInitial.Text = bolts
		iconInitial.Font = Enum.Font.GothamBold
		iconInitial.TextSize = 13
	else
		iconInitial.Text = string.sub(resourceName, 1, 1)
		iconInitial.Font = Enum.Font.GothamBlack
		iconInitial.TextSize = 15
	end
	iconInitial.TextColor3 = Color3.fromRGB(255, 255, 255)
	iconInitial.TextXAlignment = Enum.TextXAlignment.Center
	iconInitial.TextYAlignment = Enum.TextYAlignment.Center
	iconInitial.Parent = icon

	-- Count badge overlaid on the icon.
	local badge = Instance.new("TextLabel")
	badge.Name = "CountBadge"
	badge.Size = UDim2.new(0, 22, 0, 16)
	badge.Position = UDim2.new(1, -16, 1, -14)
	badge.BackgroundColor3 = Color3.fromRGB(20, 20, 24)
	badge.BackgroundTransparency = 0.15
	badge.BorderSizePixel = 0
	badge.Text = "0"
	badge.TextColor3 = Color3.fromRGB(255, 255, 255)
	badge.Font = Enum.Font.GothamBold
	badge.TextSize = 11
	badge.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	badge.TextStrokeTransparency = 0.4
	badge.TextXAlignment = Enum.TextXAlignment.Center
	badge.TextYAlignment = Enum.TextYAlignment.Center
	badge.Parent = icon

	local badgeCorner = Instance.new("UICorner")
	badgeCorner.CornerRadius = UDim.new(0, 4)
	badgeCorner.Parent = badge

	-- Name + count block in the centre.
	local textContainer = Instance.new("Frame")
	textContainer.Name = "TextContainer"
	textContainer.Size = UDim2.new(1, -(ICON_SIZE + ACTION_BUTTON_WIDTH * 2 + ACTION_GAP + 12), 1, 0)
	textContainer.Position = UDim2.new(0, ICON_SIZE + 10, 0, 0)
	textContainer.BackgroundTransparency = 1
	textContainer.BorderSizePixel = 0
	textContainer.ClipsDescendants = true
	textContainer.Parent = row

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "Name"
	nameLabel.Size = UDim2.new(1, 0, 0, 20)
	nameLabel.Position = UDim2.new(0, 0, 0, 2)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = displayName
	nameLabel.TextColor3 = Color3.fromRGB(225, 225, 235)
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextSize = 14
	nameLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	nameLabel.TextStrokeTransparency = 0.3
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.TextYAlignment = Enum.TextYAlignment.Bottom
	nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
	nameLabel.Parent = textContainer

	local countLabel = Instance.new("TextLabel")
	countLabel.Name = "Count"
	countLabel.Size = UDim2.new(1, 0, 0, 16)
	countLabel.Position = UDim2.new(0, 0, 0, 22)
	countLabel.BackgroundTransparency = 1
	countLabel.Text = "0"
	countLabel.TextColor3 = Color3.fromRGB(180, 180, 190)
	countLabel.Font = Enum.Font.GothamBold
	countLabel.TextSize = 13
	countLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	countLabel.TextStrokeTransparency = 0.4
	countLabel.TextXAlignment = Enum.TextXAlignment.Left
	countLabel.TextYAlignment = Enum.TextYAlignment.Top
	countLabel.TextTruncate = Enum.TextTruncate.AtEnd
	countLabel.Parent = textContainer

	-- Action buttons container on the right.
	local actionContainer = Instance.new("Frame")
	actionContainer.Name = "ActionContainer"
	actionContainer.Size = UDim2.new(0, ACTION_BUTTON_WIDTH * 2 + ACTION_GAP, 1, 0)
	actionContainer.Position = UDim2.new(1, -(ACTION_BUTTON_WIDTH * 2 + ACTION_GAP), 0, 0)
	actionContainer.BackgroundTransparency = 1
	actionContainer.BorderSizePixel = 0
	actionContainer.ClipsDescendants = false
	actionContainer.Parent = row

	local eatButton = buildPillButton(
		"EatButton",
		"EAT",
		Color3.fromRGB(65, 155, 90),
		Color3.fromRGB(80, 180, 110),
		actionContainer
	)
	eatButton.Position = UDim2.new(0, 0, 0.5, -12)
	eatButton.Visible = EDIBLE_RESOURCES[resourceName] == true

	local dropButton = buildPillButton(
		"DropButton",
		"DROP",
		Color3.fromRGB(170, 75, 65),
		Color3.fromRGB(195, 90, 75),
		actionContainer
	)
	dropButton.Position = UDim2.new(0, ACTION_BUTTON_WIDTH + ACTION_GAP, 0.5, -12)

	-- Keep action buttons always visible so hover/click is reliable.
	-- Hover effects are still handled by onEnter/onLeave.
	actionContainer.BackgroundTransparency = 1

	local entry: RowEntry = {
		row = row,
		icon = icon,
		countLabel = countLabel,
		nameLabel = nameLabel,
		countBadge = badge,
		eatButton = eatButton,
		dropButton = dropButton,
		actionContainer = actionContainer,
		lastCount = 0,
	}

	-- Row hover interactions (desktop only).
	if useHover then
		local function onEnter()
			TweenService:Create(row, TWEEN_HOVER, { BackgroundColor3 = Color3.fromRGB(48, 48, 58), BackgroundTransparency = 0.3 }):Play()
			TweenService:Create(icon, TWEEN_HOVER, { BackgroundTransparency = 0.05, Size = UDim2.new(0, ICON_SIZE + 4, 0, ICON_SIZE + 4), Position = UDim2.new(0, -2, 0.5, -(ICON_SIZE + 4) / 2) }):Play()
			TweenService:Create(iconStroke, TWEEN_HOVER, { Transparency = 0.35 }):Play()
			TweenService:Create(entry.nameLabel, TWEEN_HOVER, { TextColor3 = Color3.fromRGB(255, 255, 255) }):Play()
			TweenService:Create(entry.countLabel, TWEEN_HOVER, { TextColor3 = Color3.fromRGB(225, 225, 235) }):Play()

			showTooltip(row, resourceName, entry.lastCount)
		end

		local function onLeave()
			TweenService:Create(row, TWEEN_HOVER, { BackgroundColor3 = Color3.fromRGB(35, 35, 42), BackgroundTransparency = 0.3 }):Play()
			TweenService:Create(icon, TWEEN_HOVER, { BackgroundTransparency = 0.15, Size = UDim2.new(0, ICON_SIZE, 0, ICON_SIZE), Position = UDim2.new(0, 0, 0.5, -ICON_SIZE / 2) }):Play()
			TweenService:Create(iconStroke, TWEEN_HOVER, { Transparency = 0.5 }):Play()
			TweenService:Create(entry.nameLabel, TWEEN_HOVER, { TextColor3 = Color3.fromRGB(225, 225, 235) }):Play()
			TweenService:Create(entry.countLabel, TWEEN_HOVER, { TextColor3 = Color3.fromRGB(180, 180, 190) }):Play()

			hideTooltip()
		end

		row.MouseEnter:Connect(onEnter)
		row.MouseLeave:Connect(onLeave)
		icon.MouseEnter:Connect(onEnter)
		icon.MouseLeave:Connect(onLeave)
		textContainer.MouseEnter:Connect(onEnter)
		textContainer.MouseLeave:Connect(onLeave)
		actionContainer.MouseEnter:Connect(onEnter)
		actionContainer.MouseLeave:Connect(onLeave)
	end

	rowEntries[resourceName] = entry
	return entry
end

--[[
    @summary  Build the complete bag GUI ScreenGui and panel.
]]
local function buildBagGui(): ScreenGui
	local gui = Instance.new("ScreenGui")
	gui.Name = "CarryBagGui"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false
	gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Enabled = false

	-- Compute row list heights and clamp the overall panel so it never
	-- grows off the top of the screen.  The row list becomes scrollable
	-- once it exceeds the visible area.
	local rowsTotalHeight = #ROW_ORDER * ROW_HEIGHT + (#ROW_ORDER - 1) * ROW_GAP
	local baseHeight = PANEL_PADDING + HEADER_HEIGHT + PANEL_GAP
		+ PANEL_GAP + CAPACITY_CONTAINER_HEIGHT + PANEL_GAP + DROP_ALL_HEIGHT + PANEL_PADDING
	local totalHeight = math.min(MAX_PANEL_HEIGHT, baseHeight + rowsTotalHeight)
	local rowsVisibleHeight = totalHeight - baseHeight

	local panel = Instance.new("Frame")
	panel.Name = "BagPanel"
	panel.AnchorPoint = Vector2.new(1, 1)
	panel.Position = UDim2.new(1, PANEL_WIDTH + PANEL_MARGIN + 20, 1, -PANEL_MARGIN)
	panel.Size = UDim2.new(0, PANEL_WIDTH, 0, totalHeight)
	panel.BackgroundColor3 = Color3.fromRGB(55, 55, 65)
	panel.BackgroundTransparency = 0.15

	local panelGradient = Instance.new("UIGradient")
	panelGradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(220, 220, 230)),
	})
	panelGradient.Rotation = 90
	panelGradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.15),
		NumberSequenceKeypoint.new(1, 0.35),
	})
	panelGradient.Parent = panel
	panel.BorderSizePixel = 0
	panel.ClipsDescendants = false
	panel.Active = true
	panel.ZIndex = 1
	panel.Parent = gui

	bagPanel = panel
	bagGui = gui

	-- Shadow behind the panel.
	local shadow = Instance.new("Frame")
	shadow.Name = "BagShadow"
	shadow.AnchorPoint = Vector2.new(1, 1)
	shadow.Position = UDim2.new(1, PANEL_WIDTH + PANEL_MARGIN + 26, 1, -PANEL_MARGIN + 6)
	shadow.Size = UDim2.new(0, PANEL_WIDTH + 12, 0, totalHeight + 12)
	shadow.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	shadow.BackgroundTransparency = 0.45
	shadow.BorderSizePixel = 0
	shadow.ZIndex = 0
	shadow.Parent = gui

	local shadowCorner = Instance.new("UICorner")
	shadowCorner.CornerRadius = UDim.new(0, 18)
	shadowCorner.Parent = shadow

	bagShadow = shadow

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 16)
	corner.Parent = panel

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(170, 170, 190)
	stroke.Thickness = 1.5
	stroke.Transparency = 0.3
	stroke.Parent = panel

	local contentW = PANEL_WIDTH - 2 * PANEL_PADDING
	local function nextY(y: number, h: number): number
		return y + h + PANEL_GAP
	end

	local y = PANEL_PADDING

	-- Header.
	local header = Instance.new("TextLabel")
	header.Name = "Header"
	header.Position = UDim2.new(0, PANEL_PADDING, 0, y)
	header.Size = UDim2.new(0, contentW, 0, HEADER_HEIGHT)
	header.BackgroundTransparency = 1
	header.Text = "CARRY BAG"
	header.TextColor3 = Color3.fromRGB(245, 245, 245)
	header.Font = Enum.Font.GothamBlack
	header.TextSize = 16
	header.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	header.TextStrokeTransparency = 0.3
	header.TextXAlignment = Enum.TextXAlignment.Left
	header.TextYAlignment = Enum.TextYAlignment.Center
	header.Parent = panel

	local hairline = Instance.new("Frame")
	hairline.Name = "HeaderHairline"
	hairline.Position = UDim2.new(0, PANEL_PADDING, 0, y + HEADER_HEIGHT - 2)
	hairline.Size = UDim2.new(0, contentW, 0, 1)
	hairline.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	hairline.BackgroundTransparency = 0.9
	hairline.BorderSizePixel = 0
	hairline.Parent = panel

	y = nextY(y, HEADER_HEIGHT)

	-- Rows container: a ScrollingFrame so the row list can scroll when
	-- it exceeds the visible panel height.
	local rowsContainer = Instance.new("ScrollingFrame")
	rowsContainer.Name = "RowsContainer"
	rowsContainer.Position = UDim2.new(0, PANEL_PADDING, 0, y)
	rowsContainer.Size = UDim2.new(0, contentW, 0, rowsVisibleHeight)
	rowsContainer.CanvasSize = UDim2.new(0, contentW, 0, rowsTotalHeight)
	rowsContainer.BackgroundTransparency = 1
	rowsContainer.BorderSizePixel = 0
	rowsContainer.ScrollBarThickness = 6
	rowsContainer.ScrollBarImageColor3 = Color3.fromRGB(180, 180, 190)
	rowsContainer.ScrollingDirection = Enum.ScrollingDirection.Y
	rowsContainer.Parent = panel
	y = nextY(y, rowsVisibleHeight)

	local rowsLayout = Instance.new("UIListLayout")
	rowsLayout.Padding = UDim.new(0, ROW_GAP)
	rowsLayout.SortOrder = Enum.SortOrder.LayoutOrder
	rowsLayout.Parent = rowsContainer

	for i, resourceName in ipairs(ROW_ORDER) do
		buildRow(resourceName, i, rowsContainer)
	end

	buildCapacityBar(panel, y)
	y = nextY(y, CAPACITY_CONTAINER_HEIGHT)

	buildDropAllButton(panel, y)

	tooltipFrame = buildTooltip(gui)

	return gui
end

--[[
    @summary  Update capacity bar fill, colour, and label.
]]
local function updateCapacity(total: number, capacity: number)
	if not capacityFill or not capacityText then
		return
	end

	local ratio = math.clamp(total / capacity, 0, 1)
	local color: Color3
	if ratio >= 1 then
		color = Color3.fromRGB(220, 80, 80)
	elseif ratio >= 0.75 then
		color = Color3.fromRGB(230, 170, 60)
	else
		color = Color3.fromRGB(110, 210, 130)
	end

	TweenService:Create(capacityFill, TWEEN_CAPACITY, { Size = UDim2.new(ratio, 0, 1, 0), BackgroundColor3 = color }):Play()

	local glow = capacityFill:FindFirstChild("CapacityGlow")
	if glow and glow:IsA("Frame") then
		TweenService:Create(glow, TWEEN_CAPACITY, { BackgroundColor3 = color }):Play()
	end

	capacityText.Text = formatCount(total) .. "/" .. tostring(capacity)

	local dropAllContainer = bagPanel and bagPanel:FindFirstChild("DropAllContainer")
	local dropAllButton = dropAllContainer and dropAllContainer:FindFirstChild("DropAllButton")
	if dropAllButton and dropAllButton:IsA("TextButton") then
		dropAllButton.Active = total > 0
	end
end

--[[
    @summary  Update all count labels, badges, capacity, and play count pop.
]]
local function updateDisplay(resources: { [string]: number }?, capacity: number?)
	local resourceCounts = resources or {}

	local total = 0
	for resourceName, entry in pairs(rowEntries) do
		local count = resourceCounts[resourceName] or 0
		total += count

		entry.countLabel.Text = formatCount(count)
		entry.countBadge.Text = formatCount(count)
		entry.countBadge.Visible = count > 0

		-- Count pop animation when a value changes.
		if count ~= entry.lastCount then
			entry.lastCount = count
			local originalSize = entry.countLabel.TextSize
			entry.countLabel.TextSize = 18
			TweenService:Create(entry.countLabel, TWEEN_COUNT_POP, { TextSize = originalSize }):Play()
		end

		-- Empty row dimming.
		local dim = count == 0
		local rowTrans = dim and 0.6 or 0.3
		local iconTrans = dim and 0.45 or 0.15
		local nameColor = dim and Color3.fromRGB(160, 160, 170) or Color3.fromRGB(225, 225, 235)
		local countColor = dim and Color3.fromRGB(130, 130, 140) or Color3.fromRGB(180, 180, 190)
		if isOpen then
			TweenService:Create(entry.row, TWEEN_FADE, { BackgroundTransparency = rowTrans }):Play()
			TweenService:Create(entry.icon, TWEEN_FADE, { BackgroundTransparency = iconTrans }):Play()
			TweenService:Create(entry.nameLabel, TWEEN_FADE, { TextColor3 = nameColor }):Play()
			TweenService:Create(entry.countLabel, TWEEN_FADE, { TextColor3 = countColor }):Play()
		end

		-- Disable action buttons when there is nothing to eat/drop.
		if entry.eatButton then
			entry.eatButton.Active = count > 0
		end
		if entry.dropButton then
			entry.dropButton.Active = count > 0
		end

		-- Update tooltip if currently visible for this row.
		if tooltipFrame and tooltipFrame.Visible and tooltipTitle and tooltipCount then
			local junkCfg = JunkItemConfig[resourceName]
			local expectedTitle = junkCfg and junkCfg.DisplayName or resourceName
			if tooltipTitle.Text == expectedTitle then
				tooltipCount.Text = "Count: " .. formatCount(count)
			end
		end
	end

	updateCapacity(total, capacity or 5)
end

--[[
    @summary  Slide the bag panel onto the screen.
]]
local function showBag()
	if not gameStateController or not gameStateController:IsInGame() then
		return
	end
	if not bagPanel then
		return
	end
	if isOpen then
		return
	end
	isOpen = true
	if bagGui then
		bagGui.Enabled = true
	end

	for i, resourceName in ipairs(ROW_ORDER) do
		local entry = rowEntries[resourceName]
		if entry then
			entry.row.BackgroundTransparency = 1
			entry.icon.BackgroundTransparency = 1
			task.delay(i * 0.04, function()
				if not isOpen then
					return
				end
				TweenService:Create(entry.row, TWEEN_FADE, { BackgroundTransparency = 0.3 }):Play()
				TweenService:Create(entry.icon, TWEEN_FADE, { BackgroundTransparency = 0.15 }):Play()
			end)
		end
	end

	TweenService:Create(bagPanel, TWEEN_BOUNCE, { Position = UDim2.new(1, -PANEL_MARGIN, 1, -PANEL_MARGIN) }):Play()
	if bagShadow then
		TweenService:Create(bagShadow, TWEEN_BOUNCE, { Position = UDim2.new(1, -PANEL_MARGIN + 6, 1, -PANEL_MARGIN + 6) }):Play()
	end
end

--[[
    @summary  Slide the bag panel off the screen.
]]
local function hideBag()
	if not bagPanel then
		return
	end
	if not isOpen then
		return
	end
	isOpen = false
	if bagGui then
		bagGui.Enabled = false
	end

	hideTooltip()

	for i, resourceName in ipairs(ROW_ORDER) do
		local entry = rowEntries[resourceName]
		if entry then
			task.delay(i * 0.02, function()
				TweenService:Create(entry.row, TWEEN_FADE, { BackgroundTransparency = 1 }):Play()
				TweenService:Create(entry.icon, TWEEN_FADE, { BackgroundTransparency = 1 }):Play()
			end)
		end
	end

	TweenService:Create(bagPanel, TWEEN_SLIDE, { Position = UDim2.new(1, PANEL_WIDTH + PANEL_MARGIN + 20, 1, -PANEL_MARGIN) }):Play()
	if bagShadow then
		TweenService:Create(bagShadow, TWEEN_SLIDE, { Position = UDim2.new(1, PANEL_WIDTH + PANEL_MARGIN + 26, 1, -PANEL_MARGIN + 6) }):Play()
	end
end

--[[
    @summary  Wire the Drop All button and all Eat/Drop buttons.
]]
local function wireInteractions()
	local inventoryService = Knit.GetService("InventoryService")
	local forageService = Knit.GetService("ForageService")

	if not bagPanel then
		return
	end

	local dropAllContainer = bagPanel:FindFirstChild("DropAllContainer")
	local dropAllButton = dropAllContainer and dropAllContainer:FindFirstChild("DropAllButton")
	if dropAllButton and dropAllButton:IsA("TextButton") then
		dropAllButton.MouseButton1Click:Connect(function()
			inventoryService:RequestDropAll():catch(function(err)
				warn("[InventoryController] RequestDropAll failed:", err)
			end)
		end)
	end

	for resourceName, entry in pairs(rowEntries) do
		if EDIBLE_RESOURCES[resourceName] then
			entry.eatButton.MouseButton1Click:Connect(function()
				forageService:RequestEat(resourceName):andThen(function(ate)
					if not ate then
						warn("[InventoryController] RequestEat did not consume", resourceName)
					end
				end):catch(function(err)
					warn("[InventoryController] RequestEat failed:", err)
				end)
			end)
		end

		entry.dropButton.MouseButton1Click:Connect(function()
			inventoryService:RequestDrop(resourceName, 1):catch(function(err)
				warn("[InventoryController] RequestDrop failed:", err)
			end)
		end)
	end
end

--[[
    @summary  Attach equip/unequip listeners to a Carry Bag tool.
]]
local function hookTool(tool: Tool)
	tool.Equipped:Connect(showBag)
	tool.Unequipped:Connect(hideBag)
end

--[[
    @summary  Check backpack and character for the bag tool.
]]
local function findBagTool(): Tool?
	local character = localPlayer.Character
	if character then
		local held = character:FindFirstChild(BAG_TOOL_NAME)
		if held and held:IsA("Tool") then
			return held
		end
	end

	local backpack = localPlayer:FindFirstChild("Backpack")
	if backpack then
		local stored = backpack:FindFirstChild(BAG_TOOL_NAME)
		if stored and stored:IsA("Tool") then
			return stored
		end
	end

	return nil
end

--[[
    @summary  Watch for the bag tool appearing or being equipped.
]]
local function watchBagTool()
	local tool = findBagTool()
	if tool then
		hookTool(tool)
		if tool.Parent == localPlayer.Character then
			showBag()
		end
	end

	local backpack = localPlayer:WaitForChild("Backpack")
	if not backpack then
		return
	end
	local function onChildAdded(child: Instance)
		if child.Name == BAG_TOOL_NAME and child:IsA("Tool") then
			hookTool(child)
		end
	end

	backpack.ChildAdded:Connect(onChildAdded)

	local function onCharacterAdded(character: Model)
		local held = character:WaitForChild(BAG_TOOL_NAME, 5)
		if held and held:IsA("Tool") then
			hookTool(held)
			showBag()
		end
		character.ChildRemoved:Connect(function(child)
			if child.Name == BAG_TOOL_NAME and child:IsA("Tool") then
				hideBag()
			end
		end)
	end

	if localPlayer.Character then
		onCharacterAdded(localPlayer.Character)
	end
	localPlayer.CharacterAdded:Connect(onCharacterAdded)
end

-- // INITIALIZATION // --

function InventoryController:KnitInit()
	if not ServerRole.IsGameServer() then return end
	local playerGui = localPlayer:WaitForChild("PlayerGui")
	if not playerGui then
		warn("[InventoryController] PlayerGui not found")
		return
	end
	local ok, gui = pcall(buildBagGui)
	if not ok or not gui then
		warn("[InventoryController] Failed to build bag GUI:", gui)
		return
	end
	gui.Parent = playerGui
end

function InventoryController:KnitStart()
	if not ServerRole.IsGameServer() then return end
	gameStateController = Knit.GetController("GameStateController")
	local inventoryService = Knit.GetService("InventoryService")

	local function onGameStarted()
		wireInteractions()
		watchBagTool()

		inventoryService.ResourcesChanged:Connect(function(resources, capacity)
			updateDisplay(resources, capacity)
		end)

		inventoryService:GetSnapshot():andThen(function(snapshot)
			if typeof(snapshot) == "table" then
				updateDisplay(snapshot.resources, snapshot.capacity)
			end
		end):catch(function(err)
			warn("[InventoryController] Initial snapshot failed:", err)
		end)
	end

	local ok, err = pcall(function()
		if gameStateController and gameStateController:IsInGame() then
			onGameStarted()
		else
			if gameStateController then
				gameStateController.GameStarted:Connect(onGameStarted)
			end
		end
	end)

	if not ok then
		warn("[InventoryController] KnitStart error:", err)
	end
end

return InventoryController
