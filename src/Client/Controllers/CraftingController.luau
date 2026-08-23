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
local currentState = { tier = 1, resources = {}, recipeCounts = {}, unlocks = {} }
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
    @summary  Build the crafting interface once for the local player.
]]
local function buildUi()
	if gui then
		return
	end

	gui = Instance.new("ScreenGui")
	gui.Name = "CraftingGui"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false
	gui.Enabled = false
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.new(0.82, 0, 0.82, 0)
	panel.BackgroundColor3 = Color3.fromRGB(24, 24, 27)
	panel.BorderSizePixel = 0
	panel.Parent = gui
	local sizeConstraint = Instance.new("UISizeConstraint")
	sizeConstraint.MaxSize = Vector2.new(720, 620)
	sizeConstraint.MinSize = Vector2.new(300, 360)
	sizeConstraint.Parent = panel
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = panel

	titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "Title"
	titleLabel.Position = UDim2.new(0, 18, 0, 12)
	titleLabel.Size = UDim2.new(1, -90, 0, 34)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Font = Enum.Font.GothamBlack
	titleLabel.TextColor3 = Color3.fromRGB(235, 225, 195)
	titleLabel.TextSize = 22
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.Parent = panel

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
	close.Parent = panel
	local closeCorner = Instance.new("UICorner")
	closeCorner.CornerRadius = UDim.new(0, 8)
	closeCorner.Parent = close
	close.Activated:Connect(function()
		gui.Enabled = false
	end)

	resourcesLabel = Instance.new("TextLabel")
	resourcesLabel.Position = UDim2.new(0, 18, 0, 51)
	resourcesLabel.Size = UDim2.new(1, -36, 0, 26)
	resourcesLabel.BackgroundTransparency = 1
	resourcesLabel.Font = Enum.Font.Gotham
	resourcesLabel.TextColor3 = Color3.fromRGB(185, 185, 190)
	resourcesLabel.TextSize = 14
	resourcesLabel.TextXAlignment = Enum.TextXAlignment.Left
	resourcesLabel.Parent = panel

	listFrame = Instance.new("ScrollingFrame")
	listFrame.Name = "Recipes"
	listFrame.Position = UDim2.new(0, 16, 0, 84)
	listFrame.Size = UDim2.new(1, -32, 1, -100)
	listFrame.BackgroundTransparency = 1
	listFrame.BorderSizePixel = 0
	listFrame.ScrollBarThickness = 6
	listFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
	listFrame.CanvasSize = UDim2.new()
	listFrame.Parent = panel
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 7)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = listFrame

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
		button.Parent = listFrame
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
	craftingService:GetBenchState():andThen(function(snapshot)
		if typeof(snapshot) == "table" then
			currentState = snapshot
		end
		refreshDisplay()
		gui.Enabled = true
		local firstRecipe = orderedRecipes()[1]
		if firstRecipe and buttons[firstRecipe.Id] then
			GuiService.SelectedObject = buttons[firstRecipe.Id]
		end
	end)
end

-- // INITIALIZATION // --

function CraftingController:KnitStart()
	craftingService = Knit.GetService("CraftingService")
	buildUi()
	craftingService.OpenCrafting:Connect(openMenu)
	craftingService.CraftSucceeded:Connect(function(_recipeId, result)
		if typeof(result) == "table" and result.outputKind == "Placement" and gui then
			gui.Enabled = false
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
