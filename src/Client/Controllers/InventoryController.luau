--[[
    @file    InventoryController.luau
    @author  manik
    @date    2025

    @summary
    Live inventory HUD panel and click-to-eat food interaction.

    @description
    Builds a resource panel (Wood, Stone, Berries, Mushrooms, RawMeat,
    CookedMeat) plus a carry-capacity readout, bound to
    InventoryService's ResourcesChanged signal.  Berries/Mushrooms/
    RawMeat/CookedMeat rows are clickable — clicking one calls
    ForageService.RequestEat to consume it and restore Hunger.

    @exports
    - InventoryController (Knit Controller)
]]

-- // VARIABLES // --

-- | Services | --
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- | Modules | --
local Knit = require(ReplicatedStorage.Packages.Knit)

-- | Objects | --
local InventoryController = Knit.CreateController({
	Name = "InventoryController",
})

-- | Configuration | --
local PANEL_WIDTH = 190
local ROW_HEIGHT = 26
local ROW_SPACING = 4
local EDIBLE_RESOURCES = { Berries = true, Mushrooms = true, RawMeat = true, CookedMeat = true }
local ROW_ORDER = { "Wood", "Stone", "Berries", "Mushrooms", "RawMeat", "CookedMeat" }
local ROW_COLORS = {
	Wood = Color3.fromRGB(150, 100, 60),
	Stone = Color3.fromRGB(140, 140, 140),
	Berries = Color3.fromRGB(180, 40, 70),
	Mushrooms = Color3.fromRGB(200, 90, 80),
	RawMeat = Color3.fromRGB(190, 90, 90),
	CookedMeat = Color3.fromRGB(200, 150, 70),
}

-- | State Management | --
local rowLabels: { [string]: TextLabel } = {}
local capacityLabel: TextLabel? = nil
local currentCapacity = 40

-- // FUNCTIONS // --

--[[
    @summary  Build the inventory ScreenGui and one row per resource.
    @returns  ScreenGui
]]
local function buildPanel(): ScreenGui
	local gui = Instance.new("ScreenGui")
	gui.Name = "InventoryGui"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true

	local frame = Instance.new("Frame")
	frame.Name = "Panel"
	frame.AnchorPoint = Vector2.new(1, 1)
	frame.Position = UDim2.new(1, -20, 1, -20)
	frame.Size = UDim2.new(0, PANEL_WIDTH, 0, (ROW_HEIGHT + ROW_SPACING) * (#ROW_ORDER + 1))
	frame.BackgroundColor3 = Color3.fromRGB(15, 15, 15)
	frame.BackgroundTransparency = 0.35
	frame.BorderSizePixel = 0
	frame.Parent = gui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = frame

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, ROW_SPACING)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Parent = frame

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, ROW_SPACING)
	padding.PaddingBottom = UDim.new(0, ROW_SPACING)
	padding.Parent = frame

	capacityLabel = Instance.new("TextLabel")
	capacityLabel.Name = "CapacityLabel"
	capacityLabel.Size = UDim2.new(1, -12, 0, ROW_HEIGHT)
	capacityLabel.BackgroundTransparency = 1
	capacityLabel.TextColor3 = Color3.fromRGB(230, 230, 230)
	capacityLabel.Font = Enum.Font.GothamBold
	capacityLabel.TextSize = 14
	capacityLabel.Text = "Carrying 0 / " .. currentCapacity
	capacityLabel.LayoutOrder = 0
	capacityLabel.Parent = frame

	for i, resourceName in ipairs(ROW_ORDER) do
		local row = Instance.new(EDIBLE_RESOURCES[resourceName] and "TextButton" or "Frame")
		row.Name = resourceName .. "Row"
		row.Size = UDim2.new(1, -12, 0, ROW_HEIGHT)
		row.BackgroundColor3 = ROW_COLORS[resourceName] or Color3.fromRGB(80, 80, 80)
		row.BackgroundTransparency = 0.4
		row.BorderSizePixel = 0
		row.LayoutOrder = i
		if row:IsA("TextButton") then
			row.AutoButtonColor = true
			row.Text = ""
		end
		row.Parent = frame

		local rowCorner = Instance.new("UICorner")
		rowCorner.CornerRadius = UDim.new(0, 6)
		rowCorner.Parent = row

		local label = Instance.new("TextLabel")
		label.Name = "Label"
		label.Size = UDim2.new(1, -10, 1, 0)
		label.Position = UDim2.new(0, 10, 0, 0)
		label.BackgroundTransparency = 1
		label.TextColor3 = Color3.fromRGB(255, 255, 255)
		label.Font = Enum.Font.Gotham
		label.TextSize = 14
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.Text = resourceName .. ": 0"
		label.Parent = row

		rowLabels[resourceName] = label
	end

	return gui
end

--[[
    @summary  Refresh every row's text and the capacity readout.
    @param    resources  table   -- { [resourceName]: count }
    @param    capacity   number  -- max total units carryable
]]
local function updateDisplay(resources: { [string]: number }?, capacity: number?)
	resources = resources or {}
	capacity = capacity or currentCapacity
	currentCapacity = capacity
	local total = 0
	for resourceName, label in pairs(rowLabels) do
		local count = resources[resourceName] or 0
		total += count
		local suffix = EDIBLE_RESOURCES[resourceName] and " (click to eat)" or ""
		label.Text = ("%s: %d%s"):format(resourceName, count, suffix)
	end
	if capacityLabel then
		capacityLabel.Text = ("Carrying %d / %d"):format(total, capacity)
	end
end

--[[
    @summary  Wire click-to-eat on all edible resource rows.
    @param    gui  ScreenGui  -- the inventory panel gui
]]
local function wireEatButtons(gui: ScreenGui)
	local forageService = Knit.GetService("ForageService")
	local frame = gui:FindFirstChild("Panel")
	if not frame then
		return
	end

	for resourceName in pairs(EDIBLE_RESOURCES) do
		local row = frame:FindFirstChild(resourceName .. "Row")
		if row and row:IsA("TextButton") then
			row.MouseButton1Click:Connect(function()
				forageService.RequestEat(resourceName)
			end)
		end
	end
end

-- // INITIALIZATION // --

function InventoryController:KnitInit()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local gui = buildPanel()
	gui.Parent = playerGui
	updateDisplay({}, currentCapacity)

	InventoryController._gui = gui
end

function InventoryController:KnitStart()
	local inventoryService = Knit.GetService("InventoryService")

	wireEatButtons(InventoryController._gui)

	inventoryService.ResourcesChanged:Connect(function(resources, capacity)
		updateDisplay(resources, capacity)
	end)

	local snapshot = inventoryService.GetSnapshot()
	if snapshot then
		updateDisplay(snapshot.resources, snapshot.capacity)
	end

	print("[InventoryController] Initialised — inventory panel bound")
end

return InventoryController
