--[[
    @file    InventoryController.luau
    @author  manik
    @date    2025

    @summary
    Compact, animated carry-bag inventory UI.

    @description
    A slide-out vertical resource bar that appears when the Carry Bag tool is
    equipped. Collapsed it is a slim 64 px strip with icons and counts.
    Hovering expands it to 240 px and reveals names, Eat buttons, and Drop All.
    On touch devices the bar stays expanded so all controls remain reachable.

    @exports
    - InventoryController (Knit Controller)
]]

-- // VARIABLES // --

-- | Services | --
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")

-- | Modules | --
local Knit = require(ReplicatedStorage.Packages.Knit)

-- | Objects | --
local InventoryController = Knit.CreateController({
	Name = "InventoryController",
})

-- | Configuration | --
local BAG_TOOL_NAME = "Carry Bag"

-- Panel dimensions
local COLLAPSED_WIDTH = 64
local EXPANDED_WIDTH = 240
local SAFE_MARGIN_X = 20
local SAFE_MARGIN_Y = 20
local OFF_SCREEN_MARGIN = 24

-- Row dimensions
local ROW_HEIGHT = 42
local ICON_SIZE = 32
local LAYOUT_PADDING = 6
local ROW_PADDING_X = 6
local ROW_PADDING_Y = 4
local CAPACITY_HEIGHT = 4

-- Tween timings
local TWEEN_SLIDE = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local TWEEN_EXPAND = TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local TWEEN_HOVER = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local TWEEN_COUNT_POP = TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local TWEEN_COLOR = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

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

-- | State Management | --
local localPlayer = Players.LocalPlayer

local rowEntries: { [string]: {
	row: Frame,
	icon: Frame,
	badge: TextLabel,
	details: Frame,
	nameLabel: TextLabel,
	countLabel: TextLabel,
	eatButton: TextButton,
	lastCount: number,
} } = {}

local bagGui: ScreenGui? = nil
local bagPanel: Frame? = nil
local panelLayout: UIListLayout? = nil
local rowsContainer: Frame? = nil
local capacityFill: Frame? = nil
local dropAllContainer: Frame? = nil
local tooltipFrame: Frame? = nil
local tooltipLabel: TextLabel? = nil

local isOpen = false
local isExpanded = false
local useHover = UserInputService.MouseEnabled and not UserInputService.TouchEnabled
local collapseDebounce: thread? = nil

-- // FUNCTIONS // --

--[[
    @summary  Build the mouse-following tooltip used for collapsed rows.
]]
local function buildTooltip(): Frame
	local tooltip = Instance.new("Frame")
	tooltip.Name = "NameTooltip"
	tooltip.Size = UDim2.new(0, 0, 0, 26)
	tooltip.AutomaticSize = Enum.AutomaticSize.X
	tooltip.BackgroundColor3 = Color3.fromRGB(24, 24, 28)
	tooltip.BackgroundTransparency = 0.06
	tooltip.BorderSizePixel = 0
	tooltip.ZIndex = 50
	tooltip.Visible = false

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = tooltip

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(120, 120, 135)
	stroke.Thickness = 1
	stroke.Parent = tooltip

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 10)
	padding.PaddingRight = UDim.new(0, 10)
	padding.PaddingTop = UDim.new(0, 4)
	padding.PaddingBottom = UDim.new(0, 4)
	padding.Parent = tooltip

	local label = Instance.new("TextLabel")
	label.Name = "TooltipText"
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.TextColor3 = Color3.fromRGB(245, 245, 245)
	label.Font = Enum.Font.GothamBold
	label.TextSize = 13
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.Parent = tooltip

	tooltipLabel = label
	return tooltip
end

--[[
    @summary  Show or move the tooltip to the current mouse position.
]]
local function showTooltip(name: string)
	if not tooltipFrame then
		return
	end
	tooltipFrame.Visible = true
	tooltipLabel.Text = name

	local mouse = UserInputService:GetMouseLocation()
	tooltipFrame.Position = UDim2.fromOffset(mouse.X + 12, mouse.Y - 36)
end

--[[
    @summary  Hide the tooltip.
]]
local function hideTooltip()
	if tooltipFrame then
		tooltipFrame.Visible = false
	end
end

--[[
    @summary  Build the colored capacity bar at the top of the panel.
]]
local function buildCapacityBar(parent: Frame): Frame
	local container = Instance.new("Frame")
	container.Name = "CapacityBar"
	container.Size = UDim2.new(1, 0, 0, CAPACITY_HEIGHT)
	container.BackgroundColor3 = Color3.fromRGB(45, 45, 55)
	container.BackgroundTransparency = 0.3
	container.BorderSizePixel = 0
	container.LayoutOrder = 0
	container.Parent = parent

	local containerCorner = Instance.new("UICorner")
	containerCorner.CornerRadius = UDim.new(1, 0)
	containerCorner.Parent = container

	local fill = Instance.new("Frame")
	fill.Name = "CapacityFill"
	fill.Size = UDim2.new(0, 0, 1, 0)
	fill.BackgroundColor3 = Color3.fromRGB(110, 210, 130)
	fill.BackgroundTransparency = 0.1
	fill.BorderSizePixel = 0
	fill.Parent = container

	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(1, 0)
	fillCorner.Parent = fill

	return fill
end

--[[
    @summary  Build the Drop All button, hidden in collapsed mode.
]]
local function buildDropAllButton(parent: Frame): Frame
	local container = Instance.new("Frame")
	container.Name = "DropAllContainer"
	container.Size = UDim2.new(1, 0, 0, 32)
	container.BackgroundTransparency = 1
	container.BorderSizePixel = 0
	container.ClipsDescendants = true
	container.LayoutOrder = 2
	container.Parent = parent

	local button = Instance.new("TextButton")
	button.Name = "DropAllButton"
	button.Size = UDim2.new(1, 0, 1, 0)
	button.BackgroundColor3 = Color3.fromRGB(165, 60, 60)
	button.BackgroundTransparency = 0.15
	button.BorderSizePixel = 0
	button.AutoButtonColor = true
	button.Text = "DROP ALL"
	button.TextColor3 = Color3.fromRGB(255, 255, 255)
	button.Font = Enum.Font.GothamBold
	button.TextSize = 13
	button.Parent = container

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = button

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(195, 80, 80)
	stroke.Thickness = 1
	stroke.Parent = button

	-- Subtle hover effect.
	button.MouseEnter:Connect(function()
		TweenService:Create(button, TWEEN_HOVER, { BackgroundColor3 = Color3.fromRGB(185, 70, 70) }):Play()
	end)
	button.MouseLeave:Connect(function()
		TweenService:Create(button, TWEEN_HOVER, { BackgroundColor3 = Color3.fromRGB(165, 60, 60) }):Play()
	end)

	return container
end

--[[
    @summary  Build a single resource row with icon, collapsed count badge,
              and expandable details.
]]
local function buildRow(resourceName: string, index: number, parent: Frame)
	local color = ROW_COLORS[resourceName] or Color3.fromRGB(120, 120, 120)

	local row = Instance.new("Frame")
	row.Name = resourceName .. "Row"
	row.Size = UDim2.new(1, 0, 0, ROW_HEIGHT)
	row.BackgroundColor3 = Color3.fromRGB(40, 40, 48)
	row.BackgroundTransparency = 0.6
	row.BorderSizePixel = 0
	row.LayoutOrder = index
	row.ClipsDescendants = true
	row.Parent = parent

	local rowCorner = Instance.new("UICorner")
	rowCorner.CornerRadius = UDim.new(0, 8)
	rowCorner.Parent = row

	local rowLayout = Instance.new("UIListLayout")
	rowLayout.Name = "RowLayout"
	rowLayout.Padding = UDim.new(0, LAYOUT_PADDING)
	rowLayout.SortOrder = Enum.SortOrder.LayoutOrder
	rowLayout.FillDirection = Enum.FillDirection.Horizontal
	rowLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	rowLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	rowLayout.Parent = row

	local rowPadding = Instance.new("UIPadding")
	rowPadding.PaddingLeft = UDim.new(0, ROW_PADDING_X)
	rowPadding.PaddingRight = UDim.new(0, ROW_PADDING_X)
	rowPadding.PaddingTop = UDim.new(0, ROW_PADDING_Y)
	rowPadding.PaddingBottom = UDim.new(0, ROW_PADDING_Y)
	rowPadding.Parent = row

	-- Icon with resource initial.
	local icon = Instance.new("Frame")
	icon.Name = "Icon"
	icon.Size = UDim2.new(0, ICON_SIZE, 0, ICON_SIZE)
	icon.BackgroundColor3 = color
	icon.BackgroundTransparency = 0.15
	icon.BorderSizePixel = 0
	icon.Active = false
	icon.Parent = row

	local iconCorner = Instance.new("UICorner")
	iconCorner.CornerRadius = UDim.new(0, 7)
	iconCorner.Parent = icon

	local iconInitial = Instance.new("TextLabel")
	iconInitial.Name = "Initial"
	iconInitial.Size = UDim2.new(1, 0, 1, 0)
	iconInitial.BackgroundTransparency = 1
	iconInitial.Text = string.sub(resourceName, 1, 1)
	iconInitial.TextColor3 = Color3.fromRGB(255, 255, 255)
	iconInitial.Font = Enum.Font.GothamBold
	iconInitial.TextSize = 15
	iconInitial.TextXAlignment = Enum.TextXAlignment.Center
	iconInitial.TextYAlignment = Enum.TextYAlignment.Center
	iconInitial.Active = false
	iconInitial.Parent = icon

	-- Count badge overlaid on the icon, visible when collapsed.
	local badge = Instance.new("TextLabel")
	badge.Name = "CountBadge"
	badge.Size = UDim2.new(0, 22, 0, 15)
	badge.Position = UDim2.new(1, -18, 1, -13)
	badge.BackgroundColor3 = Color3.fromRGB(20, 20, 24)
	badge.BackgroundTransparency = 0.25
	badge.BorderSizePixel = 0
	badge.Text = "0"
	badge.TextColor3 = Color3.fromRGB(255, 255, 255)
	badge.Font = Enum.Font.GothamBold
	badge.TextSize = 10
	badge.TextXAlignment = Enum.TextXAlignment.Center
	badge.TextYAlignment = Enum.TextYAlignment.Center
	badge.Parent = icon

	local badgeCorner = Instance.new("UICorner")
	badgeCorner.CornerRadius = UDim.new(0, 4)
	badgeCorner.Parent = badge

	-- Expandable details (name, count, eat).
	local details = Instance.new("Frame")
	details.Name = "Details"
	details.Size = UDim2.new(0, 0, 1, -ROW_PADDING_Y * 2)
	details.BackgroundTransparency = 1
	details.BorderSizePixel = 0
	details.ClipsDescendants = true
	details.Parent = row

	local detailsLayout = Instance.new("UIListLayout")
	detailsLayout.Padding = UDim.new(0, 1)
	detailsLayout.SortOrder = Enum.SortOrder.LayoutOrder
	detailsLayout.FillDirection = Enum.FillDirection.Vertical
	detailsLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	detailsLayout.Parent = details

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "Name"
	nameLabel.Size = UDim2.new(1, 0, 0, 13)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = resourceName
	nameLabel.TextColor3 = Color3.fromRGB(230, 230, 240)
	nameLabel.Font = Enum.Font.Gotham
	nameLabel.TextSize = 12
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.TextYAlignment = Enum.TextYAlignment.Center
	nameLabel.TextTransparency = 0
	nameLabel.Parent = details

	local bottomRow = Instance.new("Frame")
	bottomRow.Name = "BottomRow"
	bottomRow.Size = UDim2.new(1, 0, 0, 22)
	bottomRow.BackgroundTransparency = 1
	bottomRow.BorderSizePixel = 0
	bottomRow.Parent = details

	local bottomLayout = Instance.new("UIListLayout")
	bottomLayout.Padding = UDim.new(0, 6)
	bottomLayout.SortOrder = Enum.SortOrder.LayoutOrder
	bottomLayout.FillDirection = Enum.FillDirection.Horizontal
	bottomLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	bottomLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	bottomLayout.Parent = bottomRow

	local countLabel = Instance.new("TextLabel")
	countLabel.Name = "Count"
	countLabel.Size = UDim2.new(1, -50, 1, 0)
	countLabel.BackgroundTransparency = 1
	countLabel.Text = "0"
	countLabel.TextColor3 = Color3.fromRGB(210, 210, 220)
	countLabel.Font = Enum.Font.GothamBold
	countLabel.TextSize = 15
	countLabel.TextXAlignment = Enum.TextXAlignment.Left
	countLabel.TextYAlignment = Enum.TextYAlignment.Center
	countLabel.Parent = bottomRow

	local eatButton = Instance.new("TextButton")
	eatButton.Name = "EatButton"
	eatButton.Size = UDim2.new(0, 44, 1, 0)
	eatButton.BackgroundColor3 = Color3.fromRGB(70, 150, 90)
	eatButton.BackgroundTransparency = 0.15
	eatButton.BorderSizePixel = 0
	eatButton.AutoButtonColor = true
	eatButton.Text = "EAT"
	eatButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	eatButton.Font = Enum.Font.GothamBold
	eatButton.TextSize = 11
	eatButton.Visible = EDIBLE_RESOURCES[resourceName] == true
	eatButton.Parent = bottomRow

	local eatCorner = Instance.new("UICorner")
	eatCorner.CornerRadius = UDim.new(0, 6)
	eatCorner.Parent = eatButton

	-- Row hover interactions.
	local function onEnter()
		TweenService:Create(row, TWEEN_HOVER, { BackgroundTransparency = 0.35 }):Play()
		TweenService:Create(icon, TWEEN_HOVER, { BackgroundTransparency = 0.05 }):Play()
		if not isExpanded then
			showTooltip(resourceName)
		end
	end

	local function onLeave()
		TweenService:Create(row, TWEEN_HOVER, { BackgroundTransparency = 0.6 }):Play()
		TweenService:Create(icon, TWEEN_HOVER, { BackgroundTransparency = 0.15 }):Play()
		hideTooltip()
	end

	row.MouseEnter:Connect(onEnter)
	row.MouseLeave:Connect(onLeave)

	rowEntries[resourceName] = {
		row = row,
		icon = icon,
		badge = badge,
		details = details,
		nameLabel = nameLabel,
		countLabel = countLabel,
		eatButton = eatButton,
		lastCount = 0,
	}
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

	bagGui = gui

	local panel = Instance.new("Frame")
	panel.Name = "BagPanel"
	panel.AnchorPoint = Vector2.new(1, 1)
	panel.Position = UDim2.new(1, COLLAPSED_WIDTH + OFF_SCREEN_MARGIN, 1, -SAFE_MARGIN_Y)
	panel.Size = UDim2.new(0, COLLAPSED_WIDTH, 0, 0)
	panel.AutomaticSize = Enum.AutomaticSize.Y
	panel.BackgroundColor3 = Color3.fromRGB(18, 18, 22)
	panel.BackgroundTransparency = 0.1
	panel.BorderSizePixel = 0
	panel.ClipsDescendants = true
	panel.Active = true
	panel.Parent = gui

	bagPanel = panel

	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(30, 30, 36)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(14, 14, 16)),
	})
	gradient.Rotation = 90
	gradient.Parent = panel

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 14)
	corner.Parent = panel

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(80, 80, 95)
	stroke.Thickness = 1.5
	stroke.Parent = panel

	-- Soft drop shadow that follows the panel size.
	local shadow = Instance.new("Frame")
	shadow.Name = "Shadow"
	shadow.AnchorPoint = Vector2.new(0.5, 0.5)
	shadow.Position = UDim2.new(0.5, 6, 0.5, 6)
	shadow.Size = UDim2.new(1, 20, 1, 20)
	shadow.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	shadow.BackgroundTransparency = 0.7
	shadow.BorderSizePixel = 0
	shadow.ZIndex = -1
	shadow.Parent = panel

	local shadowCorner = Instance.new("UICorner")
	shadowCorner.CornerRadius = UDim.new(0, 14)
	shadowCorner.Parent = shadow

	local layout = Instance.new("UIListLayout")
	layout.Name = "PanelLayout"
	layout.Padding = UDim.new(0, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Parent = panel

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 10)
	padding.PaddingBottom = UDim.new(0, 10)
	padding.PaddingLeft = UDim.new(0, 8)
	padding.PaddingRight = UDim.new(0, 8)
	padding.Parent = panel

	panelLayout = layout

	capacityFill = buildCapacityBar(panel)

	local rowsContainer = Instance.new("Frame")
	rowsContainer.Name = "RowsContainer"
	rowsContainer.Size = UDim2.new(1, 0, 0, 0)
	rowsContainer.AutomaticSize = Enum.AutomaticSize.Y
	rowsContainer.BackgroundTransparency = 1
	rowsContainer.BorderSizePixel = 0
	rowsContainer.LayoutOrder = 1
	rowsContainer.Parent = panel

	for i, resourceName in ipairs(ROW_ORDER) do
		buildRow(resourceName, i, rowsContainer)
	end

	dropAllContainer = buildDropAllButton(panel)
	dropAllContainer.Visible = false

	tooltipFrame = buildTooltip()
	tooltipFrame.Parent = gui

	-- Panel hover expand/collapse (desktop only).
	if useHover then
		panel.MouseEnter:Connect(function()
			if collapseDebounce then
				task.cancel(collapseDebounce)
				collapseDebounce = nil
			end
			if not isExpanded then
				InventoryController.ExpandBag()
			end
		end)

		panel.MouseLeave:Connect(function()
			if collapseDebounce then
				task.cancel(collapseDebounce)
				collapseDebounce = nil
			end
			collapseDebounce = task.delay(0.15, function()
				if isExpanded then
					InventoryController.CollapseBag()
				end
				collapseDebounce = nil
			end)
		end)
	else
		-- Touch: always expanded so controls stay reachable.
		dropAllContainer.Visible = true
		for _, entry in pairs(rowEntries) do
			entry.details.Visible = true
			entry.badge.Visible = false
		end
	end

	return gui
end

--[[
    @summary  Update capacity bar fill and color.
]]
local function updateCapacity(total: number, capacity: number)
	if not capacityFill then
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

	TweenService:Create(capacityFill, TWEEN_COLOR, { Size = UDim2.new(ratio, 0, 1, 0), BackgroundColor3 = color }):Play()
end

--[[
    @summary  Update all count labels, badges, capacity, and play count pop.
]]
local function updateDisplay(resources: { [string]: number }?, capacity: number?)
	resources = resources or {}

	local total = 0
	for resourceName, entry in pairs(rowEntries) do
		local count = resources[resourceName] or 0
		total += count

		entry.countLabel.Text = tostring(count)
		entry.badge.Text = tostring(count)

		-- Count pop animation when a value changes.
		if count ~= entry.lastCount then
			entry.lastCount = count
			local originalSize = entry.countLabel.TextSize
			entry.countLabel.TextSize = 18
			TweenService:Create(entry.countLabel, TWEEN_COUNT_POP, { TextSize = originalSize }):Play()
		end
	end

	updateCapacity(total, capacity or 5)
end

--[[
    @summary  Animate a single row to its expanded or collapsed state.
]]
local function setRowExpanded(entry, expanded: boolean)
	local details = entry.details
	local badge = entry.badge
	local rowLayout = entry.row:FindFirstChild("RowLayout") :: UIListLayout?

	if expanded then
		-- Details become visible and fill remaining row width.
		details.Visible = true
		TweenService:Create(details, TWEEN_EXPAND, { Size = UDim2.new(1, -(ICON_SIZE + LAYOUT_PADDING), 1, -ROW_PADDING_Y * 2) }):Play()
		badge.Visible = false
		if rowLayout then
			rowLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
		end
	else
		TweenService:Create(details, TWEEN_EXPAND, { Size = UDim2.new(0, 0, 1, -ROW_PADDING_Y * 2) }):Play()
		badge.Visible = true
		if rowLayout then
			rowLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
		end
		task.delay(TWEEN_EXPAND.Time, function()
			if not isExpanded then
				details.Visible = false
			end
		end)
	end
end

--[[
    @summary  Expand the panel to show names, counts, and controls.
]]
function InventoryController.ExpandBag()
	if not bagPanel then
		return
	end
	isExpanded = true

	TweenService:Create(bagPanel, TWEEN_EXPAND, { Size = UDim2.new(0, EXPANDED_WIDTH, 0, 0) }):Play()
	if dropAllContainer then
		dropAllContainer.Visible = true
	end

	for _, entry in pairs(rowEntries) do
		setRowExpanded(entry, true)
	end

	hideTooltip()
end

--[[
    @summary  Collapse the panel back to the icon strip.
]]
function InventoryController.CollapseBag()
	if not bagPanel then
		return
	end
	isExpanded = false

	TweenService:Create(bagPanel, TWEEN_EXPAND, { Size = UDim2.new(0, COLLAPSED_WIDTH, 0, 0) }):Play()
	if dropAllContainer then
		dropAllContainer.Visible = false
	end

	for _, entry in pairs(rowEntries) do
		setRowExpanded(entry, false)
	end
end

--[[
    @summary  Slide the bag panel onto the screen.
]]
local function showBag()
	if not bagPanel or isOpen then
		return
	end
	isOpen = true

	local function finishShow()
		TweenService:Create(bagPanel, TWEEN_SLIDE, { Position = UDim2.new(1, -SAFE_MARGIN_X, 1, -SAFE_MARGIN_Y) }):Play()
		if not useHover and bagPanel then
			InventoryController.ExpandBag()
		end
	end

	if not useHover then
		InventoryController.ExpandBag()
		finishShow()
	else
		finishShow()
	end
end

--[[
    @summary  Slide the bag panel off the screen.
]]
local function hideBag()
	if not bagPanel or not isOpen then
		return
	end
	isOpen = false

	InventoryController.CollapseBag()

	local goal = {}
	goal.Position = UDim2.new(1, COLLAPSED_WIDTH + OFF_SCREEN_MARGIN, 1, -SAFE_MARGIN_Y)
	TweenService:Create(bagPanel, TWEEN_SLIDE, goal):Play()
	hideTooltip()
end

--[[
    @summary  Wire the Drop All button and all Eat buttons.
]]
local function wireInteractions()
	local inventoryService = Knit.GetService("InventoryService")
	local forageService = Knit.GetService("ForageService")

	local panel = bagPanel
	if not panel then
		return
	end

	local dropButton = dropAllContainer and dropAllContainer:FindFirstChild("DropAllButton")
	if dropButton and dropButton:IsA("TextButton") then
		dropButton.MouseButton1Click:Connect(function()
			inventoryService:RequestDropAll()
		end)
	end

	for resourceName, entry in pairs(rowEntries) do
		if EDIBLE_RESOURCES[resourceName] then
			entry.eatButton.MouseButton1Click:Connect(function()
				forageService.RequestEat(resourceName)
			end)
		end
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
	local gui = buildBagGui()
	gui.Parent = playerGui
end

function InventoryController:KnitStart()
	local inventoryService = Knit.GetService("InventoryService")

	wireInteractions()
	watchBagTool()

	inventoryService.ResourcesChanged:Connect(function(resources, capacity)
		updateDisplay(resources, capacity)
	end)

	local snapshot = inventoryService.GetSnapshot()
	if snapshot then
		updateDisplay(snapshot.resources, snapshot.capacity)
	end

	print("[InventoryController] Initialised — compact carry bag UI bound")
end

return InventoryController
