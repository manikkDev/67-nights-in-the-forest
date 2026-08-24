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
local panel: Frame? = nil
local titleLabel: TextLabel? = nil
local resourcesLabel: TextLabel? = nil
local listFrame: ScrollingFrame? = nil
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
		button.BackgroundColor3 = if tierLocked
			then Color3.fromRGB(55, 55, 60)
			elseif capReached
			then Color3.fromRGB(65, 75, 65)
			elseif affordable
			then Color3.fromRGB(70, 125, 70)
			else Color3.fromRGB(100, 70, 65)
		local statusText = if tierLocked
			then "\nRequires Tier " .. tostring(recipe.Tier)
			elseif capReached then "\nBuilt"
			else ""
		button.Text = recipe.DisplayName .. "\n" .. formatCost(recipe.Cost) .. statusText
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
]]
local function buildUi()
	if gui and gui.Parent then
		return
	end
	gui = nil
	panel = nil
	titleLabel = nil
	resourcesLabel = nil
	listFrame = nil
	table.clear(buttons)

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "CraftingGui"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = false
	screenGui.Enabled = false
	screenGui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	gui = screenGui

	local panelFrame = Instance.new("Frame")
	panelFrame.Name = "Panel"
	panelFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	panelFrame.Position = UDim2.fromScale(0.5, 0.5)
	panelFrame.Size = UDim2.new(0.82, 0, 0.82, 0)
	panelFrame.BackgroundColor3 = Color3.fromRGB(24, 24, 27)
	panelFrame.BorderSizePixel = 0
	panelFrame.Parent = screenGui
	panel = panelFrame
	local sizeConstraint = Instance.new("UISizeConstraint")
	sizeConstraint.MaxSize = Vector2.new(720, 620)
	sizeConstraint.MinSize = Vector2.new(300, 360)
	sizeConstraint.Parent = panelFrame
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = panelFrame

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Position = UDim2.new(0, 18, 0, 12)
	title.Size = UDim2.new(1, -90, 0, 34)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBlack
	title.TextColor3 = Color3.fromRGB(235, 225, 195)
	title.TextSize = 22
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Parent = panelFrame
	titleLabel = title

	local close = Instance.new("TextButton")
	close.Name = "Close"
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, -12, 0, 12)
	close.Size = UDim2.fromOffset(44, 34)
	close.BackgroundColor3 = Color3.fromRGB(120, 55, 50)
	close.Font = Enum.Font.GothamBold
	close.Text = "X"
	close.TextColor3 = Color3.new(1, 1, 1)
	close.TextSize = 18
	close.Parent = panelFrame
	local closeCorner = Instance.new("UICorner")
	closeCorner.CornerRadius = UDim.new(0, 8)
	closeCorner.Parent = close
	close.Activated:Connect(closeMenu)

	local resources = Instance.new("TextLabel")
	resources.Position = UDim2.new(0, 18, 0, 51)
	resources.Size = UDim2.new(1, -36, 0, 26)
	resources.BackgroundTransparency = 1
	resources.Font = Enum.Font.Gotham
	resources.TextColor3 = Color3.fromRGB(185, 185, 190)
	resources.TextSize = 14
	resources.TextXAlignment = Enum.TextXAlignment.Left
	resources.Parent = panelFrame
	resourcesLabel = resources

	local recipeList = Instance.new("ScrollingFrame")
	recipeList.Name = "Recipes"
	recipeList.Position = UDim2.new(0, 16, 0, 84)
	recipeList.Size = UDim2.new(1, -32, 1, -100)
	recipeList.BackgroundTransparency = 1
	recipeList.BorderSizePixel = 0
	recipeList.ScrollBarThickness = 6
	recipeList.AutomaticCanvasSize = Enum.AutomaticSize.Y
	recipeList.CanvasSize = UDim2.new()
	recipeList.Parent = panelFrame
	listFrame = recipeList
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 7)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = recipeList

	for order, recipe in ipairs(orderedRecipes()) do
		local button = Instance.new("TextButton")
		button.Name = recipe.Id
		button.LayoutOrder = order
		button.Size = UDim2.new(1, -8, 0, 64)
		button.BackgroundColor3 = Color3.fromRGB(70, 125, 70)
		button.Font = Enum.Font.GothamBold
		button.TextColor3 = Color3.fromRGB(245, 245, 240)
		button.TextSize = 15
		button.TextWrapped = true
		button.Selectable = true
		button.Parent = recipeList
		local buttonCorner = Instance.new("UICorner")
		buttonCorner.CornerRadius = UDim.new(0, 8)
		buttonCorner.Parent = button
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
	craftingService.OpenCrafting:Connect(openMenu)
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
