--[[
    @file    CraftingController.luau
    @author  manik
    @date    2025

    @summary
    Responsive crafting bench menu for keyboard, touch, and gamepad.
]]

-- // VARIABLES // --

-- | Services | --
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")

-- | Modules | --
local Knit = require(ReplicatedStorage.Packages.Knit)
local RecipeConfig = require(ReplicatedStorage.Shared.RecipeConfig)

-- | Objects | --
local CraftingController = Knit.CreateController({
	Name = "CraftingController",
})

-- | State Management | --
local craftingService: any = nil
local gui: ScreenGui? = nil
local _panel: Frame? = nil
local titleLabel: TextLabel? = nil
local resourcesLabel: TextLabel? = nil
local _listFrame: ScrollingFrame? = nil
local buttons: { [string]: TextButton } = {}
local currentState: { tier: number, resources: { [string]: number }, recipeCounts: { [string]: number }, unlocks: { [string]: boolean } } = { tier = 1, resources = {}, recipeCounts = {}, unlocks = {} }
local requestPending = false

-- // FUNCTIONS // --

--[[
    @summary  Return a stable recipe order for the menu.
    @returns  { table }
]]
local function orderedRecipes()
	local recipes = {}
	for _, recipe in pairs(RecipeConfig) do
		table.insert(recipes, recipe)
	end
	table.sort(recipes, function(a, b)
		if a.Tier ~= b.Tier then
			return a.Tier < b.Tier
		end
		return a.DisplayName < b.DisplayName
	end)
	return recipes
end

--[[
    @summary  Format a resource-cost map into readable text.
    @param    cost  table
    @returns  string
]]
local function formatCost(cost): string
	local parts = {}
	for resourceName, amount in pairs(cost) do
		table.insert(parts, amount .. " " .. resourceName)
	end
	table.sort(parts)
	return table.concat(parts, "  |  ")
end

--[[
    @summary  Return whether the current snapshot can pay one recipe.
    @param    recipe  table
    @returns  boolean
]]
local function canAfford(recipe): boolean
	for resourceName, amount in pairs(recipe.Cost) do
		if (currentState.resources[resourceName] or 0) < amount then
			return false
		end
	end
	return true
end

--[[
    @summary  Refresh recipe buttons from the authoritative snapshot.
]]
local function refreshDisplay()
	if titleLabel then
		titleLabel.Text = "CRAFTING BENCH  •  TIER " .. tostring(currentState.tier)
	end
	if resourcesLabel then
		resourcesLabel.Text = string.format(
			"Wood %d   Scrap %d   Cultist Gems %d",
			currentState.resources.Wood or 0,
			currentState.resources.Scrap or 0,
			currentState.resources.CultistGem or 0
		)
	end
	for recipeId, button in pairs(buttons) do
		local recipe = RecipeConfig[recipeId]
		local count = currentState.recipeCounts[recipeId] or 0
		local capReached = recipe.RunCap and count >= recipe.RunCap
		local tierLocked = recipe.Tier > currentState.tier
		local affordable = canAfford(recipe)
		button.Active = not requestPending and not capReached and not tierLocked and affordable
		button.AutoButtonColor = button.Active
		-- Match carry bag row colors: dimmed when unavailable, warm when active.
		button.BackgroundColor3 = if tierLocked
			then Color3.fromRGB(45, 45, 52)
			elseif capReached
			then Color3.fromRGB(50, 60, 50)
			elseif affordable
			then Color3.fromRGB(55, 55, 65)
			else Color3.fromRGB(70, 50, 50)
		button.BackgroundTransparency = if affordable and not tierLocked and not capReached then 0.3 else 0.5
		local statusText = if tierLocked
			then "  [Tier " .. tostring(recipe.Tier) .. "]"
			elseif capReached then "  [Built]"
			else ""
		button.Text = recipe.DisplayName .. "  —  " .. formatCost(recipe.Cost) .. statusText
	end
end

--[[
    @summary  Request one recipe and surface its result in the menu.
    @param    recipeId  string
]]
local function requestCraft(recipeId: string)
	if requestPending or not craftingService then
		return
	end
	requestPending = true
	refreshDisplay()
	craftingService:RequestCraft(recipeId):andThen(function(result)
		requestPending = false
		if typeof(result) == "table" and result.ok ~= true and resourcesLabel then
			resourcesLabel.Text = "Cannot craft: " .. tostring(result.code)
		end
		craftingService:GetBenchState():andThen(function(snapshot)
			if typeof(snapshot) == "table" then
				currentState = snapshot
				refreshDisplay()
			end
		end)
	end):catch(function()
		requestPending = false
		if resourcesLabel then
			resourcesLabel.Text = "Crafting request failed"
		end
		refreshDisplay()
	end)
end

--[[
    @summary  Close the menu and exit gamepad selection mode.
]]
local function closeMenu()
	if gui then
		gui.Enabled = false
	end
	GuiService.SelectedObject = nil
end

--[[
    @summary  Build the crafting interface once for the local player.
    @desc     Styled to match the carry bag panel: dark panel with
              gradient, rounded corners, UIStroke border, GothamBlack
              header with hairline separator, and consistent row
              styling with UICorner.
]]
local function buildUi()
	if gui and gui.Parent then
		return
	end
	gui = nil
	_panel = nil
	titleLabel = nil
	resourcesLabel = nil
	_listFrame = nil
	table.clear(buttons)

	-- Layout constants (matching the carry bag design language).
	local PANEL_PADDING = 12
	local PANEL_GAP = 8
	local HEADER_HEIGHT = 22
	local RESOURCES_HEIGHT = 20
	local SCROLL_BAR_THICKNESS = 6

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "CraftingGui"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = false
	screenGui.Enabled = false
	screenGui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	gui = screenGui

	-- Main panel: centered, dark with gradient (same as carry bag).
	local panelFrame = Instance.new("Frame")
	panelFrame.Name = "Panel"
	panelFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	panelFrame.Position = UDim2.fromScale(0.5, 0.5)
	panelFrame.Size = UDim2.new(0.82, 0, 0.82, 0)
	panelFrame.BackgroundColor3 = Color3.fromRGB(55, 55, 65)
	panelFrame.BackgroundTransparency = 0.15
	panelFrame.BorderSizePixel = 0
	panelFrame.ClipsDescendants = false
	panelFrame.Parent = screenGui
	_panel = panelFrame

	local sizeConstraint = Instance.new("UISizeConstraint")
	sizeConstraint.MaxSize = Vector2.new(720, 620)
	sizeConstraint.MinSize = Vector2.new(300, 360)
	sizeConstraint.Parent = panelFrame

	-- Gradient (same as carry bag).
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
	panelGradient.Parent = panelFrame

	-- Rounded corners (same as carry bag).
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 16)
	corner.Parent = panelFrame

	-- UIStroke border (same as carry bag).
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(170, 170, 190)
	stroke.Thickness = 1.5
	stroke.Transparency = 0.3
	stroke.Parent = panelFrame

	local contentW = UDim2.new(1, -2 * PANEL_PADDING, 0, 0)
	local y = PANEL_PADDING

	-- Header (matching carry bag header style).
	local title = Instance.new("TextLabel")
	title.Name = "Header"
	title.Position = UDim2.new(0, PANEL_PADDING, 0, y)
	title.Size = UDim2.new(1, -2 * PANEL_PADDING, 0, HEADER_HEIGHT)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBlack
	title.TextColor3 = Color3.fromRGB(245, 245, 245)
	title.TextSize = 15
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextYAlignment = Enum.TextYAlignment.Center
	title.Parent = panelFrame
	titleLabel = title

	-- Hairline separator (same as carry bag).
	local hairline = Instance.new("Frame")
	hairline.Name = "HeaderHairline"
	hairline.Position = UDim2.new(0, PANEL_PADDING, 0, y + HEADER_HEIGHT - 2)
	hairline.Size = UDim2.new(1, -2 * PANEL_PADDING, 0, 1)
	hairline.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	hairline.BackgroundTransparency = 0.9
	hairline.BorderSizePixel = 0
	hairline.Parent = panelFrame

	y = y + HEADER_HEIGHT + PANEL_GAP

	-- Close button (matching carry bag's rounded style).
	local close = Instance.new("TextButton")
	close.Name = "Close"
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, -PANEL_PADDING, 0, PANEL_PADDING)
	close.Size = UDim2.fromOffset(36, HEADER_HEIGHT)
	close.BackgroundColor3 = Color3.fromRGB(160, 60, 60)
	close.BackgroundTransparency = 0.12
	close.BorderSizePixel = 0
	close.AutoButtonColor = false
	close.Font = Enum.Font.GothamBlack
	close.Text = "X"
	close.TextColor3 = Color3.fromRGB(255, 255, 255)
	close.TextSize = 14
	close.Parent = panelFrame
	local closeCorner = Instance.new("UICorner")
	closeCorner.CornerRadius = UDim.new(1, 0)
	closeCorner.Parent = close
	local closeStroke = Instance.new("UIStroke")
	closeStroke.Color = Color3.fromRGB(190, 75, 75)
	closeStroke.Thickness = 1
	closeStroke.Transparency = 0.4
	closeStroke.Parent = close
	close.Activated:Connect(closeMenu)

	-- Resources summary line.
	local resources = Instance.new("TextLabel")
	resources.Name = "Resources"
	resources.Position = UDim2.new(0, PANEL_PADDING, 0, y)
	resources.Size = UDim2.new(1, -2 * PANEL_PADDING, 0, RESOURCES_HEIGHT)
	resources.BackgroundTransparency = 1
	resources.Font = Enum.Font.GothamBold
	resources.TextColor3 = Color3.fromRGB(200, 200, 210)
	resources.TextSize = 13
	resources.TextXAlignment = Enum.TextXAlignment.Left
	resources.TextYAlignment = Enum.TextYAlignment.Center
	resources.Parent = panelFrame
	resourcesLabel = resources

	y = y + RESOURCES_HEIGHT + PANEL_GAP

	-- Recipe list (scrollable, same scrollbar style as carry bag).
	local recipeList = Instance.new("ScrollingFrame")
	recipeList.Name = "Recipes"
	recipeList.Position = UDim2.new(0, PANEL_PADDING, 0, y)
	recipeList.Size = UDim2.new(1, -2 * PANEL_PADDING, 1, -y - PANEL_PADDING)
	recipeList.BackgroundTransparency = 1
	recipeList.BorderSizePixel = 0
	recipeList.ScrollBarThickness = SCROLL_BAR_THICKNESS
	recipeList.ScrollBarImageColor3 = Color3.fromRGB(180, 180, 190)
	recipeList.ScrollingDirection = Enum.ScrollingDirection.Y
	recipeList.AutomaticCanvasSize = Enum.AutomaticSize.Y
	recipeList.CanvasSize = UDim2.new()
	recipeList.Parent = panelFrame
	_listFrame = recipeList

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = recipeList

	for order, recipe in ipairs(orderedRecipes()) do
		local button = Instance.new("TextButton")
		button.Name = recipe.Id
		button.LayoutOrder = order
		button.Size = UDim2.new(1, -8, 0, 56)
		button.BackgroundColor3 = Color3.fromRGB(35, 35, 42)
		button.BackgroundTransparency = 0.3
		button.BorderSizePixel = 0
		button.AutoButtonColor = false
		button.Font = Enum.Font.GothamBold
		button.TextColor3 = Color3.fromRGB(225, 225, 235)
		button.TextSize = 14
		button.TextWrapped = true
		button.TextXAlignment = Enum.TextXAlignment.Left
		button.TextYAlignment = Enum.TextYAlignment.Center
		button.Selectable = true
		button.Parent = recipeList

		local buttonCorner = Instance.new("UICorner")
		buttonCorner.CornerRadius = UDim.new(0, 8)
		buttonCorner.Parent = button

		local buttonPadding = Instance.new("UIPadding")
		buttonPadding.PaddingLeft = UDim.new(0, 10)
		buttonPadding.PaddingRight = UDim.new(0, 10)
		buttonPadding.PaddingTop = UDim.new(0, 5)
		buttonPadding.PaddingBottom = UDim.new(0, 5)
		buttonPadding.Parent = button

		button.Activated:Connect(function()
			requestCraft(recipe.Id)
		end)
		buttons[recipe.Id] = button
	end
end

--[[
    @summary  Open the menu and request a fresh authoritative snapshot.
]]
local function openMenu()
	buildUi()
	print(("[CraftingController] openMenu called | gui=%s | gui.Enabled=%s"):format(
		tostring(gui ~= nil),
		tostring(gui and gui.Enabled)
	))
	-- Enable the GUI immediately so the menu is visible even if the
	-- GetBenchState request fails or is slow. The snapshot refreshes
	-- the display once it arrives.
	if gui then
		gui.Enabled = true
	end
	-- Only enter gamepad selection mode when a gamepad is actually
	-- connected. Forcing SelectedObject on mouse/touch users hijacks
	-- pointer input and breaks clicking on recipe buttons.
	if #UserInputService:GetConnectedGamepads() > 0 then
		local firstRecipe = orderedRecipes()[1]
		if firstRecipe and buttons[firstRecipe.Id] then
			GuiService.SelectedObject = buttons[firstRecipe.Id]
		end
	end
	craftingService:GetBenchState():andThen(function(snapshot)
		if typeof(snapshot) == "table" then
			currentState = snapshot
		end
		refreshDisplay()
	end):catch(function()
		-- Menu is already open; just refresh with whatever state we have.
		refreshDisplay()
	end)
end

-- // INITIALIZATION // --

function CraftingController:KnitStart()
	craftingService = Knit.GetService("CraftingService")
	local runStateService = Knit.GetService("RunStateService")
	buildUi()
	craftingService.OpenCrafting:Connect(function()
		print("[CraftingController] OpenCrafting signal received")
		openMenu()
	end)
	craftingService.CraftSucceeded:Connect(function(_recipeId, result)
		if typeof(result) == "table" and result.outputKind == "Placement" and gui and gui.Enabled then
			closeMenu()
		end
	end)
	runStateService.RunPhaseChanged:Connect(function(payload)
		if typeof(payload) == "table" and payload.phase == "Lobby" then
			closeMenu()
		end
	end)
	craftingService.CraftingStateChanged:Connect(function(snapshot)
		if typeof(snapshot) == "table" then
			currentState.tier = snapshot.tier or currentState.tier
			currentState.recipeCounts = snapshot.recipeCounts or currentState.recipeCounts
			currentState.unlocks = snapshot.unlocks or currentState.unlocks
			if gui and gui.Enabled then
				craftingService:GetBenchState():andThen(function(fullSnapshot)
					if typeof(fullSnapshot) == "table" then
						currentState = fullSnapshot
						refreshDisplay()
					end
				end)
			end
		end
	end)
end

return CraftingController
