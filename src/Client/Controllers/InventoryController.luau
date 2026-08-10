--[[
    @file    InventoryController.luau
    @author  manik
    @date    2025

    @summary
    Carry-bag UI shown only when the Carry Bag tool is equipped.

    @description
    A polished satchel-style panel that slides into view when the player
    holds the Carry Bag tool. It lists every resource, its count, the
    current / max capacity, and provides hover tooltips, eat buttons for
    food, and a Drop All button.

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
local PANEL_WIDTH = 260
local ROW_HEIGHT = 46
local ROW_SPACING = 7
local TWEEN_INFO = TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
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
local rowEntries: { [string]: { row: Frame, count: TextLabel, eat: TextButton } } = {}
local capacityBarFill: Frame? = nil
local capacityText: TextLabel? = nil
local tooltipFrame: Frame? = nil
local tooltipLabel: TextLabel? = nil
local bagGui: ScreenGui? = nil
local bagPanel: Frame? = nil
local isOpen = false
local localPlayer = Players.LocalPlayer
local buildRow: (resourceName: string, index: number, parent: Instance) -> { row: Frame, count: TextLabel, eat: TextButton }

-- // FUNCTIONS // --

--[[
    @summary  Build the tooltip that follows the cursor on row hover.
]]
local function buildTooltip(): Frame
	local tooltip = Instance.new("Frame")
	tooltip.Name = "NameTooltip"
	tooltip.Size = UDim2.new(0, 0, 0, 32)
	tooltip.AutomaticSize = Enum.AutomaticSize.X
	tooltip.BackgroundColor3 = Color3.fromRGB(22, 22, 26)
	tooltip.BackgroundTransparency = 0.05
	tooltip.BorderSizePixel = 0
	tooltip.ZIndex = 50
	tooltip.Visible = false

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = tooltip

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(140, 140, 155)
	stroke.Thickness = 1.2
	stroke.Parent = tooltip

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 12)
	padding.PaddingRight = UDim.new(0, 12)
	padding.PaddingTop = UDim.new(0, 0)
	padding.PaddingBottom = UDim.new(0, 0)
	padding.Parent = tooltip

	local label = Instance.new("TextLabel")
	label.Name = "TooltipText"
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.TextColor3 = Color3.fromRGB(245, 245, 245)
	label.Font = Enum.Font.GothamBold
	label.TextSize = 14
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.Parent = tooltip

	tooltipLabel = label
	return tooltip
end

--[[
    @summary  Show the name tooltip at the current mouse position.
]]
local function showTooltip(name: string)
	if not tooltipFrame then
		return
	end
	tooltipFrame.Visible = true
	tooltipLabel.Text = name
	local mouse = UserInputService:GetMouseLocation()
	tooltipFrame.Position = UDim2.fromOffset(mouse.X + 14, mouse.Y - 42)
end

--[[
    @summary  Hide the name tooltip.
]]
local function hideTooltip()
	if tooltipFrame then
		tooltipFrame.Visible = false
	end
end

--[[
    @summary  Build the bag panel ScreenGui with capacity and rows.
]]
local function buildBagGui(): ScreenGui
	local gui = Instance.new("ScreenGui")
	gui.Name = "CarryBagGui"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.Enabled = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	bagGui = gui

	local panel = Instance.new("Frame")
	panel.Name = "BagPanel"
	panel.AnchorPoint = Vector2.new(1, 1)
	panel.Position = UDim2.new(1, PANEL_WIDTH + 20, 1, -20)
	panel.Size = UDim2.new(0, PANEL_WIDTH, 0, 0)
	panel.AutomaticSize = Enum.AutomaticSize.Y
	panel.BackgroundColor3 = Color3.fromRGB(18, 18, 22)
	panel.BackgroundTransparency = 0.08
	panel.BorderSizePixel = 0
	panel.ClipsDescendants = false
	panel.Parent = gui

	bagPanel = panel

	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(28, 28, 34)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(12, 12, 14)),
	})
	gradient.Rotation = 90
	gradient.Parent = panel

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 18)
	corner.Parent = panel

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(80, 80, 95)
	stroke.Thickness = 1.5
	stroke.Parent = panel

	local shadow = Instance.new("Frame")
	shadow.Name = "Shadow"
	shadow.AnchorPoint = Vector2.new(0.5, 0.5)
	shadow.Position = UDim2.new(0.5, 8, 0.5, 8)
	shadow.Size = UDim2.new(1, 24, 1, 24)
	shadow.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	shadow.BackgroundTransparency = 0.65
	shadow.BorderSizePixel = 0
	shadow.ZIndex = -1
	shadow.Parent = panel

	local shadowCorner = Instance.new("UICorner")
	shadowCorner.CornerRadius = UDim.new(0, 18)
	shadowCorner.Parent = shadow

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, ROW_SPACING)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Parent = panel

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 16)
	padding.PaddingBottom = UDim.new(0, 14)
	padding.PaddingLeft = UDim.new(0, 14)
	padding.PaddingRight = UDim.new(0, 14)
	padding.Parent = panel

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(1, 0, 0, 22)
	title.BackgroundTransparency = 1
	title.Text = "Carry Bag"
	title.TextColor3 = Color3.fromRGB(230, 230, 245)
	title.Font = Enum.Font.GothamBold
	title.TextSize = 18
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.LayoutOrder = 0
	title.Parent = panel

	local capacityContainer = Instance.new("Frame")
	capacityContainer.Name = "CapacityContainer"
	capacityContainer.Size = UDim2.new(1, 0, 0, 8)
	capacityContainer.BackgroundColor3 = Color3.fromRGB(55, 55, 65)
	capacityContainer.BackgroundTransparency = 0.4
	capacityContainer.BorderSizePixel = 0
	capacityContainer.LayoutOrder = 1
	capacityContainer.Parent = panel

	local capacityCorner = Instance.new("UICorner")
	capacityCorner.CornerRadius = UDim.new(1, 0)
	capacityCorner.Parent = capacityContainer

	local fill = Instance.new("Frame")
	fill.Name = "CapacityFill"
	fill.Size = UDim2.new(0, 0, 1, 0)
	fill.BackgroundColor3 = Color3.fromRGB(110, 210, 130)
	fill.BackgroundTransparency = 0.1
	fill.BorderSizePixel = 0
	fill.Parent = capacityContainer

	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(1, 0)
	fillCorner.Parent = fill

	capacityBarFill = fill

	local capacityLabel = Instance.new("TextLabel")
	capacityLabel.Name = "CapacityText"
	capacityLabel.Size = UDim2.new(1, 0, 0, 20)
	capacityLabel.BackgroundTransparency = 1
	capacityLabel.Text = "Capacity 0 / 5"
	capacityLabel.TextColor3 = Color3.fromRGB(180, 180, 190)
	capacityLabel.Font = Enum.Font.Gotham
	capacityLabel.TextSize = 13
	capacityLabel.TextXAlignment = Enum.TextXAlignment.Right
	capacityLabel.LayoutOrder = 2
	capacityLabel.Parent = panel

	capacityText = capacityLabel

	local rowsContainer = Instance.new("Frame")
	rowsContainer.Name = "RowsContainer"
	rowsContainer.Size = UDim2.new(1, 0, 0, 0)
	rowsContainer.AutomaticSize = Enum.AutomaticSize.Y
	rowsContainer.BackgroundTransparency = 1
	rowsContainer.BorderSizePixel = 0
	rowsContainer.LayoutOrder = 3
	rowsContainer.Parent = panel

	local rowsLayout = Instance.new("UIListLayout")
	rowsLayout.Padding = UDim.new(0, ROW_SPACING)
	rowsLayout.SortOrder = Enum.SortOrder.LayoutOrder
	rowsLayout.Parent = rowsContainer

	for i, resourceName in ipairs(ROW_ORDER) do
		rowEntries[resourceName] = buildRow(resourceName, i, rowsContainer)
	end

	local dropButton = Instance.new("TextButton")
	dropButton.Name = "DropAllButton"
	dropButton.Size = UDim2.new(1, 0, 0, 38)
	dropButton.BackgroundColor3 = Color3.fromRGB(160, 60, 60)
	dropButton.BackgroundTransparency = 0.15
	dropButton.BorderSizePixel = 0
	dropButton.AutoButtonColor = true
	dropButton.Text = "DROP ALL"
	dropButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	dropButton.Font = Enum.Font.GothamBold
	dropButton.TextSize = 14
	dropButton.LayoutOrder = 4
	dropButton.Parent = panel

	local dropCorner = Instance.new("UICorner")
	dropCorner.CornerRadius = UDim.new(0, 10)
	dropCorner.Parent = dropButton

	tooltipFrame = buildTooltip()
	tooltipFrame.Parent = gui

	return gui
end

--[[
    @summary  Build one resource row with icon, name, count and optional eat button.
]]
buildRow = function(resourceName: string, index: number, parent: Instance): { row: Frame, count: TextLabel, eat: TextButton }
	local color = ROW_COLORS[resourceName] or Color3.fromRGB(120, 120, 120)

	local row = Instance.new("Frame")
	row.Name = resourceName .. "Row"
	row.Size = UDim2.new(1, 0, 0, ROW_HEIGHT)
	row.BackgroundColor3 = Color3.fromRGB(35, 35, 42)
	row.BackgroundTransparency = 0.55
	row.BorderSizePixel = 0
	row.LayoutOrder = index
	row.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = row

	local icon = Instance.new("Frame")
	icon.Name = "Icon"
	icon.Size = UDim2.new(0, 28, 0, 28)
	icon.Position = UDim2.new(0, 9, 0.5, -14)
	icon.BackgroundColor3 = color
	icon.BackgroundTransparency = 0.15
	icon.BorderSizePixel = 0
	icon.Active = false
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
	iconInitial.Active = false
	iconInitial.Parent = icon

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "Name"
	nameLabel.Size = UDim2.new(0.45, -40, 1, 0)
	nameLabel.Position = UDim2.new(0, 46, 0, 0)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = resourceName
	nameLabel.TextColor3 = Color3.fromRGB(230, 230, 240)
	nameLabel.Font = Enum.Font.Gotham
	nameLabel.TextSize = 14
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.TextYAlignment = Enum.TextYAlignment.Center
	nameLabel.Active = false
	nameLabel.Parent = row

	local countLabel = Instance.new("TextLabel")
	countLabel.Name = "Count"
	countLabel.Size = UDim2.new(0.25, -10, 1, 0)
	countLabel.Position = UDim2.new(0.55, 0, 0, 0)
	countLabel.BackgroundTransparency = 1
	countLabel.Text = "0"
	countLabel.TextColor3 = Color3.fromRGB(200, 200, 210)
	countLabel.Font = Enum.Font.GothamBold
	countLabel.TextSize = 15
	countLabel.TextXAlignment = Enum.TextXAlignment.Right
	countLabel.TextYAlignment = Enum.TextYAlignment.Center
	countLabel.Active = false
	countLabel.Parent = row

	local eatButton = Instance.new("TextButton")
	eatButton.Name = "EatButton"
	eatButton.Size = UDim2.new(0, 46, 0, 28)
	eatButton.Position = UDim2.new(1, -55, 0.5, -14)
	eatButton.BackgroundColor3 = Color3.fromRGB(70, 150, 90)
	eatButton.BackgroundTransparency = 0.15
	eatButton.BorderSizePixel = 0
	eatButton.AutoButtonColor = true
	eatButton.Text = "Eat"
	eatButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	eatButton.Font = Enum.Font.GothamBold
	eatButton.TextSize = 12
	eatButton.Visible = EDIBLE_RESOURCES[resourceName] == true
	eatButton.Parent = row

	local eatCorner = Instance.new("UICorner")
	eatCorner.CornerRadius = UDim.new(0, 7)
	eatCorner.Parent = eatButton

	-- Hover highlight and tooltip.
	local function onEnter()
		TweenService:Create(row, TweenInfo.new(0.12), { BackgroundTransparency = 0.25 }):Play()
		showTooltip(resourceName)
	end

	local function onLeave()
		TweenService:Create(row, TweenInfo.new(0.12), { BackgroundTransparency = 0.55 }):Play()
		hideTooltip()
	end

	local function onMove()
		showTooltip(resourceName)
	end

	row.MouseEnter:Connect(onEnter)
	row.MouseLeave:Connect(onLeave)
	row.MouseMoved:Connect(onMove)

	return { row = row, count = countLabel, eat = eatButton }
end

--[[
    @summary  Update capacity bar, text, and all resource counts.
]]
local function updateDisplay(resources: { [string]: number }?, capacity: number?)
	resources = resources or {}
	local total = 0
	for resourceName, entry in pairs(rowEntries) do
		local count = resources[resourceName] or 0
		total += count
		entry.count.Text = tostring(count)
	end

	local cap = capacity or 5
	if capacityText then
		capacityText.Text = ("Capacity %d / %d"):format(total, cap)
	end
	if capacityBarFill then
		local ratio = math.clamp(total / cap, 0, 1)
		TweenService:Create(capacityBarFill, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = UDim2.new(ratio, 0, 1, 0) }):Play()
		capacityBarFill.BackgroundColor3 = ratio >= 1 and Color3.fromRGB(220, 80, 80) or Color3.fromRGB(110, 210, 130)
	end
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

	local dropButton = panel:FindFirstChild("DropAllButton")
	if dropButton and dropButton:IsA("TextButton") then
		dropButton.MouseButton1Click:Connect(function()
			inventoryService:RequestDropAll()
		end)
	end

	for resourceName, entry in pairs(rowEntries) do
		if EDIBLE_RESOURCES[resourceName] then
			entry.eat.MouseButton1Click:Connect(function()
				forageService.RequestEat(resourceName)
			end)
		end
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

	local goal = {}
	goal.Position = UDim2.new(1, -20, 1, -20)
	TweenService:Create(bagPanel, TWEEN_INFO, goal):Play()
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

	local goal = {}
	goal.Position = UDim2.new(1, PANEL_WIDTH + 20, 1, -20)
	TweenService:Create(bagPanel, TWEEN_INFO, goal):Play()
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

	print("[InventoryController] Initialised — carry bag UI bound")
end

return InventoryController
