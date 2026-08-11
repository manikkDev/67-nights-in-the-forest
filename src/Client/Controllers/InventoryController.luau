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

-- | Objects | --
local InventoryController = Knit.CreateController({
	Name = "InventoryController",
})

-- | Configuration | --
local BAG_TOOL_NAME = "Carry Bag"

-- Panel dimensions
local PANEL_WIDTH = 220
local PANEL_MARGIN = 16
local ROW_HEIGHT = 38
local ROW_GAP = 4
local PANEL_PADDING = 10
local PANEL_GAP = 8
local ICON_SIZE = 28
local HEADER_HEIGHT = 18
local CAPACITY_CONTAINER_HEIGHT = 24
local DROP_ALL_HEIGHT = 28
local ROW_PADDING_X = 8
local ROW_PADDING_Y = 5
local ACTION_BUTTON_WIDTH = 36
local ACTION_GAP = 5
local CAPACITY_HEIGHT = 4

-- Tween timings
local TWEEN_SLIDE = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local TWEEN_HOVER = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local TWEEN_FADE = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local TWEEN_COUNT_POP = TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local TWEEN_CAPACITY = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

-- Content data
local EDIBLE_RESOURCES = { Berries = true, Mushrooms = true, RawMeat = true, CookedMeat = true }
local ROW_ORDER = { "Wood", "Stone", "Berries", "Mushrooms", "RawMeat", "CookedMeat" }
local ROW_COLORS = {
	Wood = Color3.fromRGB(170, 110, 65),
	Stone = Color3.fromRGB(155, 155, 155),
	Berries = Color3.fromRGB(195, 50, 80),
	Mushrooms = Color3.fromRGB(210, 110, 95),
	RawMeat = Color3.fromRGB(200, 100, 100),
	CookedMeat = Color3.fromRGB(215, 160, 80),
}
local ROW_DESCRIPTIONS = {
	Wood = "Used for building and fueling campfires.",
	Stone = "A sturdy material for crafting structures.",
	Berries = "Restores a small amount of hunger.",
	Mushrooms = "Restores a small amount of hunger.",
	RawMeat = "Cook it at the campfire to restore more hunger.",
	CookedMeat = "A filling meal that restores lots of hunger.",
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
local capacityFill: Frame? = nil
local capacityText: TextLabel? = nil
local tooltipFrame: Frame? = nil
local tooltipTitle: TextLabel? = nil
local tooltipCount: TextLabel? = nil
local tooltipDesc: TextLabel? = nil

local isOpen = false
local useHover = UserInputService.MouseEnabled and not UserInputService.TouchEnabled

-- // FUNCTIONS // --

--[[
    @summary  Build the hover tooltip that appears to the left of a row.
]]
local function buildTooltip(parent: ScreenGui): Frame
	local tooltip = Instance.new("Frame")
	tooltip.Name = "CarryBagTooltip"
	tooltip.Size = UDim2.new(0, 180, 0, 0)
	tooltip.AutomaticSize = Enum.AutomaticSize.Y
	tooltip.BackgroundColor3 = Color3.fromRGB(24, 24, 28)
	tooltip.BackgroundTransparency = 0.06
	tooltip.BorderSizePixel = 0
	tooltip.ZIndex = 50
	tooltip.Visible = false
	tooltip.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = tooltip

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(100, 100, 115)
	stroke.Thickness = 1
	stroke.Parent = tooltip

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 2)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = tooltip

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 10)
	padding.PaddingRight = UDim.new(0, 10)
	padding.PaddingTop = UDim.new(0, 8)
	padding.PaddingBottom = UDim.new(0, 8)
	padding.Parent = tooltip

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(1, 0, 0, 16)
	title.BackgroundTransparency = 1
	title.TextColor3 = Color3.fromRGB(245, 245, 245)
	title.Font = Enum.Font.GothamBold
	title.TextSize = 13
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextYAlignment = Enum.TextYAlignment.Top
	title.LayoutOrder = 1
	title.Parent = tooltip

	local count = Instance.new("TextLabel")
	count.Name = "Count"
	count.Size = UDim2.new(1, 0, 0, 14)
	count.BackgroundTransparency = 1
	count.TextColor3 = Color3.fromRGB(180, 180, 190)
	count.Font = Enum.Font.Gotham
	count.TextSize = 11
	count.TextXAlignment = Enum.TextXAlignment.Left
	count.TextYAlignment = Enum.TextYAlignment.Top
	count.LayoutOrder = 2
	count.Parent = tooltip

	local desc = Instance.new("TextLabel")
	desc.Name = "Description"
	desc.Size = UDim2.new(1, 0, 0, 0)
	desc.AutomaticSize = Enum.AutomaticSize.Y
	desc.BackgroundTransparency = 1
	desc.TextColor3 = Color3.fromRGB(160, 160, 170)
	desc.Font = Enum.Font.Gotham
	desc.TextSize = 11
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

	tooltipTitle.Text = resourceName
	tooltipCount.Text = "Count: " .. tostring(count)
	tooltipDesc.Text = ROW_DESCRIPTIONS[resourceName] or ""

	local rowPos = row.AbsolutePosition
	local rowSize = row.AbsoluteSize

	-- Tooltip width is fixed at 180, height is automatic.
	local targetX = rowPos.X - 180 - 10
	local targetY = rowPos.Y + (rowSize.Y - 60) / 2

	-- Clamp to screen edges.
	local viewport = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize
	if viewport then
		targetX = math.max(8, math.min(targetX, viewport.X - 188))
		targetY = math.max(8, math.min(targetY, viewport.Y - 60))
	end

	tooltipFrame.Position = UDim2.fromOffset(targetX, targetY)
	tooltipFrame.Visible = true

	TweenService:Create(tooltipFrame, TWEEN_FADE, { BackgroundTransparency = 0.06 }):Play()
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
	button.Size = UDim2.new(0, ACTION_BUTTON_WIDTH, 0, 22)
	button.BackgroundColor3 = color
	button.BackgroundTransparency = 0.15
	button.BorderSizePixel = 0
	button.AutoButtonColor = false
	button.Text = text
	button.TextColor3 = Color3.fromRGB(255, 255, 255)
	button.Font = Enum.Font.GothamBold
	button.TextSize = 10
	button.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = button

	button.MouseEnter:Connect(function()
		TweenService:Create(button, TWEEN_HOVER, { BackgroundColor3 = hoverColor }):Play()
	end)
	button.MouseLeave:Connect(function()
		TweenService:Create(button, TWEEN_HOVER, { BackgroundColor3 = color }):Play()
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
	barBackground.BackgroundColor3 = Color3.fromRGB(45, 45, 55)
	barBackground.BackgroundTransparency = 0.3
	barBackground.BorderSizePixel = 0
	barBackground.Parent = container

	local bgCorner = Instance.new("UICorner")
	bgCorner.CornerRadius = UDim.new(1, 0)
	bgCorner.Parent = barBackground

	local fill = Instance.new("Frame")
	fill.Name = "CapacityFill"
	fill.Size = UDim2.new(0, 0, 1, 0)
	fill.BackgroundColor3 = Color3.fromRGB(110, 210, 130)
	fill.BackgroundTransparency = 0.1
	fill.BorderSizePixel = 0
	fill.Parent = barBackground

	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(1, 0)
	fillCorner.Parent = fill

	local label = Instance.new("TextLabel")
	label.Name = "CapacityText"
	label.Size = UDim2.new(1, 0, 0, 16)
	label.Position = UDim2.new(0, 0, 0, CAPACITY_HEIGHT + 4)
	label.BackgroundTransparency = 1
	label.Text = "0/5"
	label.TextColor3 = Color3.fromRGB(200, 200, 210)
	label.Font = Enum.Font.GothamBold
	label.TextSize = 11
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
	container.Size = UDim2.new(0, contentW, 0, 28)
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
	button.Font = Enum.Font.GothamBold
	button.TextSize = 11
	button.Parent = container

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = button

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(190, 75, 75)
	stroke.Thickness = 1
	stroke.Parent = button

	button.MouseEnter:Connect(function()
		TweenService:Create(button, TWEEN_HOVER, { BackgroundColor3 = Color3.fromRGB(185, 70, 70) }):Play()
	end)
	button.MouseLeave:Connect(function()
		TweenService:Create(button, TWEEN_HOVER, { BackgroundColor3 = Color3.fromRGB(160, 60, 60) }):Play()
	end)

	return button
end

--[[
    @summary  Build a single resource row with icon, labels, and action pills.
]]
local function buildRow(resourceName: string, index: number, parent: Frame): RowEntry
	local color = ROW_COLORS[resourceName] or Color3.fromRGB(120, 120, 120)

	local row = Instance.new("Frame")
	row.Name = resourceName .. "Row"
	row.Size = UDim2.new(1, 0, 0, ROW_HEIGHT)
	row.BackgroundColor3 = Color3.fromRGB(35, 35, 42)
	row.BackgroundTransparency = 0.5
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

	local iconCorner = Instance.new("UICorner")
	iconCorner.CornerRadius = UDim.new(0, 6)
	iconCorner.Parent = icon

	local iconInitial = Instance.new("TextLabel")
	iconInitial.Name = "Initial"
	iconInitial.Size = UDim2.new(1, 0, 1, 0)
	iconInitial.BackgroundTransparency = 1
	iconInitial.Text = string.sub(resourceName, 1, 1)
	iconInitial.TextColor3 = Color3.fromRGB(255, 255, 255)
	iconInitial.Font = Enum.Font.GothamBold
	iconInitial.TextSize = 14
	iconInitial.TextXAlignment = Enum.TextXAlignment.Center
	iconInitial.TextYAlignment = Enum.TextYAlignment.Center
	iconInitial.Parent = icon

	-- Count badge overlaid on the icon.
	local badge = Instance.new("TextLabel")
	badge.Name = "CountBadge"
	badge.Size = UDim2.new(0, 18, 0, 14)
	badge.Position = UDim2.new(1, -14, 1, -12)
	badge.BackgroundColor3 = Color3.fromRGB(20, 20, 24)
	badge.BackgroundTransparency = 0.15
	badge.BorderSizePixel = 0
	badge.Text = "0"
	badge.TextColor3 = Color3.fromRGB(255, 255, 255)
	badge.Font = Enum.Font.GothamBold
	badge.TextSize = 9
	badge.TextXAlignment = Enum.TextXAlignment.Center
	badge.TextYAlignment = Enum.TextYAlignment.Center
	badge.Parent = icon

	local badgeCorner = Instance.new("UICorner")
	badgeCorner.CornerRadius = UDim.new(0, 4)
	badgeCorner.Parent = badge

	-- Name + count block in the centre.
	local textContainer = Instance.new("Frame")
	textContainer.Name = "TextContainer"
	textContainer.Size = UDim2.new(1, -(ICON_SIZE + ACTION_BUTTON_WIDTH * 2 + ACTION_GAP * 2 + 16), 1, 0)
	textContainer.Position = UDim2.new(0, ICON_SIZE + 10, 0, 0)
	textContainer.BackgroundTransparency = 1
	textContainer.BorderSizePixel = 0
	textContainer.ClipsDescendants = true
	textContainer.Parent = row

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "Name"
	nameLabel.Size = UDim2.new(1, 0, 0, 15)
	nameLabel.Position = UDim2.new(0, 0, 0, 0)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = resourceName
	nameLabel.TextColor3 = Color3.fromRGB(225, 225, 235)
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextSize = 12
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.TextYAlignment = Enum.TextYAlignment.Bottom
	nameLabel.Parent = textContainer

	local countLabel = Instance.new("TextLabel")
	countLabel.Name = "Count"
	countLabel.Size = UDim2.new(1, 0, 0, 14)
	countLabel.Position = UDim2.new(0, 0, 0, 15)
	countLabel.BackgroundTransparency = 1
	countLabel.Text = "0"
	countLabel.TextColor3 = Color3.fromRGB(180, 180, 190)
	countLabel.Font = Enum.Font.Gotham
	countLabel.TextSize = 11
	countLabel.TextXAlignment = Enum.TextXAlignment.Left
	countLabel.TextYAlignment = Enum.TextYAlignment.Top
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
	eatButton.Position = UDim2.new(0, 0, 0.5, -11)
	eatButton.Visible = EDIBLE_RESOURCES[resourceName] == true

	local dropButton = buildPillButton(
		"DropButton",
		"DROP",
		Color3.fromRGB(170, 75, 65),
		Color3.fromRGB(195, 90, 75),
		actionContainer
	)
	dropButton.Position = UDim2.new(0, ACTION_BUTTON_WIDTH + ACTION_GAP, 0.5, -11)

	-- Start hidden on desktop, visible on touch.
	local startVisible = not useHover
	eatButton.Visible = eatButton.Visible and startVisible
	dropButton.Visible = startVisible
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
			TweenService:Create(row, TWEEN_HOVER, { BackgroundColor3 = Color3.fromRGB(45, 45, 55), BackgroundTransparency = 0.35 }):Play()
			TweenService:Create(icon, TWEEN_HOVER, { BackgroundTransparency = 0.05 }):Play()

			if EDIBLE_RESOURCES[resourceName] then
				eatButton.Visible = true
			end
			dropButton.Visible = true

			showTooltip(row, resourceName, entry.lastCount)
		end

		local function onLeave()
			TweenService:Create(row, TWEEN_HOVER, { BackgroundColor3 = Color3.fromRGB(35, 35, 42), BackgroundTransparency = 0.5 }):Play()
			TweenService:Create(icon, TWEEN_HOVER, { BackgroundTransparency = 0.15 }):Play()

			if EDIBLE_RESOURCES[resourceName] then
				eatButton.Visible = false
			end
			dropButton.Visible = false

			hideTooltip()
		end

		row.MouseEnter:Connect(onEnter)
		row.MouseLeave:Connect(onLeave)
		icon.MouseEnter:Connect(onEnter)
		icon.MouseLeave:Connect(onLeave)
		textContainer.MouseEnter:Connect(onEnter)
		textContainer.MouseLeave:Connect(onLeave)
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
	gui.Enabled = true

	-- Compute total height explicitly.
	local rowsHeight = #ROW_ORDER * ROW_HEIGHT + (#ROW_ORDER - 1) * ROW_GAP
	local totalHeight = PANEL_PADDING + HEADER_HEIGHT + PANEL_GAP + rowsHeight
		+ PANEL_GAP + CAPACITY_CONTAINER_HEIGHT + PANEL_GAP + DROP_ALL_HEIGHT + PANEL_PADDING

	local panel = Instance.new("Frame")
	panel.Name = "BagPanel"
	panel.AnchorPoint = Vector2.new(1, 1)
	panel.Position = UDim2.new(1, PANEL_WIDTH + PANEL_MARGIN, 1, -PANEL_MARGIN)
	panel.Size = UDim2.new(0, PANEL_WIDTH, 0, totalHeight)
	panel.BackgroundColor3 = Color3.fromRGB(55, 55, 65)
	panel.BackgroundTransparency = 0.06
	panel.BorderSizePixel = 0
	panel.ClipsDescendants = false
	panel.Active = true
	panel.ZIndex = 1
	panel.Parent = gui

	bagPanel = panel

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 16)
	corner.Parent = panel

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(110, 110, 125)
	stroke.Thickness = 1
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
	header.TextSize = 12
	header.TextXAlignment = Enum.TextXAlignment.Left
	header.TextYAlignment = Enum.TextYAlignment.Center
	header.Parent = panel
	y = nextY(y, HEADER_HEIGHT)

	-- Rows container.
	local rowsContainer = Instance.new("Frame")
	rowsContainer.Name = "RowsContainer"
	rowsContainer.Position = UDim2.new(0, PANEL_PADDING, 0, y)
	rowsContainer.Size = UDim2.new(0, contentW, 0, rowsHeight)
	rowsContainer.BackgroundTransparency = 1
	rowsContainer.BorderSizePixel = 0
	rowsContainer.Parent = panel
	y = nextY(y, rowsHeight)

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
	capacityText.Text = string.format("%d/%d", total, capacity)
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

		entry.countLabel.Text = tostring(count)
		entry.countBadge.Text = tostring(count)

		-- Count pop animation when a value changes.
		if count ~= entry.lastCount then
			entry.lastCount = count
			local originalSize = entry.countLabel.TextSize
			entry.countLabel.TextSize = 14
			TweenService:Create(entry.countLabel, TWEEN_COUNT_POP, { TextSize = originalSize }):Play()
		end

		-- Update tooltip if currently visible for this row.
		if tooltipFrame and tooltipFrame.Visible and tooltipTitle and tooltipCount and tooltipTitle.Text == resourceName then
			tooltipCount.Text = "Count: " .. tostring(count)
		end
	end

	updateCapacity(total, capacity or 5)
end

--[[
    @summary  Slide the bag panel onto the screen.
]]
local function showBag()
	if not bagPanel or isOpen then
		return
	end
	isOpen = true

	TweenService:Create(bagPanel, TWEEN_SLIDE, { Position = UDim2.new(1, -PANEL_MARGIN, 1, -PANEL_MARGIN) }):Play()
end

--[[
    @summary  Slide the bag panel off the screen.
]]
local function hideBag()
	if not bagPanel or not isOpen then
		return
	end
	isOpen = false

	hideTooltip()
	TweenService:Create(bagPanel, TWEEN_SLIDE, { Position = UDim2.new(1, PANEL_WIDTH + PANEL_MARGIN, 1, -PANEL_MARGIN) }):Play()
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
			inventoryService:RequestDropAll()
		end)
	end

	for resourceName, entry in pairs(rowEntries) do
		if EDIBLE_RESOURCES[resourceName] then
			entry.eatButton.MouseButton1Click:Connect(function()
				forageService.RequestEat(resourceName)
			end)
		end

		entry.dropButton.MouseButton1Click:Connect(function()
			inventoryService:RequestDrop(resourceName, 1)
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
	local playerGui = localPlayer:WaitForChild("PlayerGui")
	local ok, gui = pcall(buildBagGui)
	if not ok or not gui then
		warn("[InventoryController] Failed to build bag GUI:", gui)
		return
	end
	gui.Parent = playerGui
	print("[InventoryController] Bag GUI built and parented")
end

function InventoryController:KnitStart()
	local inventoryService = Knit.GetService("InventoryService")

	local ok, err = pcall(function()
		wireInteractions()
		watchBagTool()

		inventoryService.ResourcesChanged:Connect(function(resources, capacity)
			updateDisplay(resources, capacity)
		end)

		local snapshot = inventoryService.GetSnapshot()
		if snapshot then
			updateDisplay(snapshot.resources, snapshot.capacity)
		end
	end)

	if not ok then
		warn("[InventoryController] KnitStart error:", err)
	else
		print("[InventoryController] Initialised — professional carry bag UI bound")
	end
end

return InventoryController
