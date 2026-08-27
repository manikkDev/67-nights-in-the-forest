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
			"Wood: %d    Scrap: %d    Cultist Gems: %d",
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

		-- Solid card colors — fully opaque, clearly readable.
		if tierLocked then
			button.BackgroundColor3 = Color3.fromRGB(40, 40, 48)
		elseif capReached then
			button.BackgroundColor3 = Color3.fromRGB(35, 50, 35)
		elseif affordable then
			button.BackgroundColor3 = Color3.fromRGB(50, 70, 50)
		else
			button.BackgroundColor3 = Color3.fromRGB(60, 40, 40)
		end

		-- Update the status label on the card.
		local statusLabel = button:FindFirstChild("RecipeStatus") :: TextLabel?
		if statusLabel then
			if tierLocked then
				statusLabel.Text = "Tier " .. tostring(recipe.Tier)
				statusLabel.TextColor3 = Color3.fromRGB(200, 160, 80)
			elseif capReached then
				statusLabel.Text = "Built"
				statusLabel.TextColor3 = Color3.fromRGB(120, 200, 120)
			elseif not affordable then
				statusLabel.Text = "Need resources"
				statusLabel.TextColor3 = Color3.fromRGB(220, 120, 120)
			else
				statusLabel.Text = ""
			end
		end

		-- Dim the name/cost text when unavailable.
		local nameLabel = button:FindFirstChild("RecipeName") :: TextLabel?
		local costLabel = button:FindFirstChild("RecipeCost") :: TextLabel?
		local available = not tierLocked and not capReached and affordable
		if nameLabel then
			nameLabel.TextColor3 = if available
				then Color3.fromRGB(240, 240, 245)
				else Color3.fromRGB(140, 140, 150)
		end
		if costLabel then
			costLabel.TextColor3 = if available
				then Color3.fromRGB(170, 170, 185)
				else Color3.fromRGB(110, 110, 120)
		end
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
    @desc     Professional solid-panel layout matching the carry bag
              design language: opaque dark panel, rounded corners,
              UIStroke border, clear header with hairline, resource
              summary bar, and fully opaque recipe cards with distinct
              name / cost / status sections.
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

	-- Layout constants.
	local PANEL_PADDING = 14
	local PANEL_GAP = 10
	local HEADER_HEIGHT = 28
	local RESOURCES_HEIGHT = 28
	local ROW_HEIGHT = 64
	local ROW_GAP = 8
	local SCROLL_BAR_THICKNESS = 6

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "CraftingGui"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = false
	screenGui.Enabled = false
	screenGui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	gui = screenGui

	-- Main panel: centered, solid dark background.
	local panelFrame = Instance.new("Frame")
	panelFrame.Name = "Panel"
	panelFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	panelFrame.Position = UDim2.fromScale(0.5, 0.5)
	panelFrame.Size = UDim2.new(0.82, 0, 0.82, 0)
	panelFrame.BackgroundColor3 = Color3.fromRGB(38, 38, 46)
	panelFrame.BackgroundTransparency = 0
	panelFrame.BorderSizePixel = 0
	panelFrame.ClipsDescendants = true
	panelFrame.Parent = screenGui
	_panel = panelFrame

	local sizeConstraint = Instance.new("UISizeConstraint")
	sizeConstraint.MaxSize = Vector2.new(680, 580)
	sizeConstraint.MinSize = Vector2.new(320, 380)
	sizeConstraint.Parent = panelFrame

	-- Subtle gradient for depth (very low transparency so it stays opaque).
	local panelGradient = Instance.new("UIGradient")
	panelGradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(45, 45, 54)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(32, 32, 40)),
	})
	panelGradient.Rotation = 90
	panelGradient.Parent = panelFrame

	-- Rounded corners.
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 14)
	corner.Parent = panelFrame

	-- UIStroke border.
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(120, 120, 140)
	stroke.Thickness = 2
	stroke.Transparency = 0.2
	stroke.Parent = panelFrame

	local y = PANEL_PADDING

	-- Header row: title on the left, close button on the right.
	local title = Instance.new("TextLabel")
	title.Name = "Header"
	title.Position = UDim2.new(0, PANEL_PADDING, 0, y)
	title.Size = UDim2.new(1, -PANEL_PADDING - 50, 0, HEADER_HEIGHT)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBlack
	title.TextColor3 = Color3.fromRGB(240, 240, 245)
	title.TextSize = 18
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextYAlignment = Enum.TextYAlignment.Center
	title.Parent = panelFrame
	titleLabel = title

	-- Close button: solid, clearly visible.
	local close = Instance.new("TextButton")
	close.Name = "Close"
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, -PANEL_PADDING, 0, y)
	close.Size = UDim2.fromOffset(40, HEADER_HEIGHT)
	close.BackgroundColor3 = Color3.fromRGB(180, 55, 55)
	close.BackgroundTransparency = 0
	close.BorderSizePixel = 0
	close.AutoButtonColor = true
	close.Font = Enum.Font.GothamBold
	close.Text = "X"
	close.TextColor3 = Color3.fromRGB(255, 255, 255)
	close.TextSize = 16
	close.Parent = panelFrame
	local closeCorner = Instance.new("UICorner")
	closeCorner.CornerRadius = UDim.new(0, 8)
	closeCorner.Parent = close
	close.Activated:Connect(closeMenu)

	-- Hairline separator.
	local hairline = Instance.new("Frame")
	hairline.Name = "HeaderHairline"
	hairline.Position = UDim2.new(0, PANEL_PADDING, 0, y + HEADER_HEIGHT)
	hairline.Size = UDim2.new(1, -2 * PANEL_PADDING, 0, 1)
	hairline.BackgroundColor3 = Color3.fromRGB(80, 80, 95)
	hairline.BackgroundTransparency = 0
	hairline.BorderSizePixel = 0
	hairline.Parent = panelFrame

	y = y + HEADER_HEIGHT + PANEL_GAP

	-- Resources summary bar: solid background, clearly readable.
	local resourcesContainer = Instance.new("Frame")
	resourcesContainer.Name = "ResourcesBar"
	resourcesContainer.Position = UDim2.new(0, PANEL_PADDING, 0, y)
	resourcesContainer.Size = UDim2.new(1, -2 * PANEL_PADDING, 0, RESOURCES_HEIGHT)
	resourcesContainer.BackgroundColor3 = Color3.fromRGB(28, 28, 35)
	resourcesContainer.BackgroundTransparency = 0
	resourcesContainer.BorderSizePixel = 0
	resourcesContainer.Parent = panelFrame

	local resCorner = Instance.new("UICorner")
	resCorner.CornerRadius = UDim.new(0, 8)
	resCorner.Parent = resourcesContainer

	local resPadding = Instance.new("UIPadding")
	resPadding.PaddingLeft = UDim.new(0, 10)
	resPadding.PaddingRight = UDim.new(0, 10)
	resPadding.Parent = resourcesContainer

	local resources = Instance.new("TextLabel")
	resources.Name = "ResourcesText"
	resources.Size = UDim2.fromScale(1, 1)
	resources.BackgroundTransparency = 1
	resources.Font = Enum.Font.GothamBold
	resources.TextColor3 = Color3.fromRGB(200, 200, 215)
	resources.TextSize = 14
	resources.TextXAlignment = Enum.TextXAlignment.Left
	resources.TextYAlignment = Enum.TextYAlignment.Center
	resources.Parent = resourcesContainer
	resourcesLabel = resources

	y = y + RESOURCES_HEIGHT + PANEL_GAP

	-- Recipe list: scrollable, solid background.
	local recipeList = Instance.new("ScrollingFrame")
	recipeList.Name = "Recipes"
	recipeList.Position = UDim2.new(0, PANEL_PADDING, 0, y)
	recipeList.Size = UDim2.new(1, -2 * PANEL_PADDING, 1, -y - PANEL_PADDING)
	recipeList.BackgroundColor3 = Color3.fromRGB(30, 30, 37)
	recipeList.BackgroundTransparency = 0
	recipeList.BorderSizePixel = 0
	recipeList.ScrollBarThickness = SCROLL_BAR_THICKNESS
	recipeList.ScrollBarImageColor3 = Color3.fromRGB(160, 160, 180)
	recipeList.ScrollingDirection = Enum.ScrollingDirection.Y
	recipeList.AutomaticCanvasSize = Enum.AutomaticSize.Y
	recipeList.CanvasSize = UDim2.new()
	recipeList.Parent = panelFrame
	_listFrame = recipeList

	local listCorner = Instance.new("UICorner")
	listCorner.CornerRadius = UDim.new(0, 8)
	listCorner.Parent = recipeList

	local listPadding = Instance.new("UIPadding")
	listPadding.PaddingLeft = UDim.new(0, 6)
	listPadding.PaddingRight = UDim.new(0, 6)
	listPadding.PaddingTop = UDim.new(0, 6)
	listPadding.PaddingBottom = UDim.new(0, 6)
	listPadding.Parent = recipeList

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, ROW_GAP)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = recipeList

	for order, recipe in ipairs(orderedRecipes()) do
		-- Each recipe is a solid card with name + cost sections.
		local card = Instance.new("TextButton")
		card.Name = recipe.Id
		card.LayoutOrder = order
		card.Size = UDim2.new(1, 0, 0, ROW_HEIGHT)
		card.BackgroundColor3 = Color3.fromRGB(50, 50, 60)
		card.BackgroundTransparency = 0
		card.BorderSizePixel = 0
		card.AutoButtonColor = true
		card.Text = ""
		card.Selectable = true
		card.Parent = recipeList

		local cardCorner = Instance.new("UICorner")
		cardCorner.CornerRadius = UDim.new(0, 10)
		cardCorner.Parent = card

		local cardStroke = Instance.new("UIStroke")
		cardStroke.Color = Color3.fromRGB(90, 90, 110)
		cardStroke.Thickness = 1
		cardStroke.Transparency = 0.4
		cardStroke.Parent = card

		-- Recipe name (top line, bold).
		local nameLabel = Instance.new("TextLabel")
		nameLabel.Name = "RecipeName"
		nameLabel.Position = UDim2.new(0, 12, 0, 6)
		nameLabel.Size = UDim2.new(1, -24, 0, 22)
		nameLabel.BackgroundTransparency = 1
		nameLabel.Font = Enum.Font.GothamBold
		nameLabel.TextColor3 = Color3.fromRGB(240, 240, 245)
		nameLabel.TextSize = 15
		nameLabel.TextXAlignment = Enum.TextXAlignment.Left
		nameLabel.TextYAlignment = Enum.TextYAlignment.Center
		nameLabel.Text = recipe.DisplayName
		nameLabel.Parent = card

		-- Cost line (below name, smaller, muted).
		local costLabel = Instance.new("TextLabel")
		costLabel.Name = "RecipeCost"
		costLabel.Position = UDim2.new(0, 12, 0, 30)
		costLabel.Size = UDim2.new(1, -24, 0, 18)
		costLabel.BackgroundTransparency = 1
		costLabel.Font = Enum.Font.Gotham
		costLabel.TextColor3 = Color3.fromRGB(170, 170, 185)
		costLabel.TextSize = 13
		costLabel.TextXAlignment = Enum.TextXAlignment.Left
		costLabel.TextYAlignment = Enum.TextYAlignment.Center
		costLabel.Text = "Cost: " .. formatCost(recipe.Cost)
		costLabel.Parent = card

		-- Status label (right side, for tier/cap info).
		local statusLabel = Instance.new("TextLabel")
		statusLabel.Name = "RecipeStatus"
		statusLabel.AnchorPoint = Vector2.new(1, 0.5)
		statusLabel.Position = UDim2.new(1, -12, 0.5, 0)
		statusLabel.Size = UDim2.new(0, 100, 0, 20)
		statusLabel.BackgroundTransparency = 1
		statusLabel.Font = Enum.Font.GothamBold
		statusLabel.TextColor3 = Color3.fromRGB(200, 160, 80)
		statusLabel.TextSize = 12
		statusLabel.TextXAlignment = Enum.TextXAlignment.Right
		statusLabel.TextYAlignment = Enum.TextYAlignment.Center
		statusLabel.Text = ""
		statusLabel.Parent = card

		card.Activated:Connect(function()
			requestCraft(recipe.Id)
		end)
		buttons[recipe.Id] = card
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
