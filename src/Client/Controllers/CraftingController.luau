--[[
    @file    CraftingController.luau
    @author  manik
    @date    2025

    @summary
    Responsive crafting bench menu for keyboard, touch, and gamepad.

    @description
    Professional crafting UI with:
    - Confirmation dialog before purchasing any recipe
    - UI click sounds on every button interaction
    - Animated success notifications (bench upgrade banner, unlock toast,
      item crafted toast)
    - Refined cohesive color palette with hover effects
]]

-- // VARIABLES // --

-- | Services | --
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

-- | Modules | --
local Knit = require(ReplicatedStorage.Packages.Knit)
local RecipeConfig = require(ReplicatedStorage.Shared.RecipeConfig)
local UiSoundUtil = require(ReplicatedStorage.Shared.UiSoundUtil)

-- | Objects | --
local CraftingController = Knit.CreateController({
	Name = "CraftingController",
})

-- | Configuration | --
-- Refined cohesive color palette — calm blue-greys with purposeful accents
local COLOR = {
	Panel = Color3.fromRGB(38, 38, 46),
	PanelGradientTop = Color3.fromRGB(45, 45, 54),
	PanelGradientBottom = Color3.fromRGB(32, 32, 40),
	ListBg = Color3.fromRGB(30, 30, 37),
	ResourceBar = Color3.fromRGB(28, 28, 35),
	Hairline = Color3.fromRGB(80, 80, 95),
	Stroke = Color3.fromRGB(70, 70, 85),
	StrokeTransparency = 0.5,
	-- Card states
	CardAffordable = Color3.fromRGB(42, 52, 62),
	CardAffordableHover = Color3.fromRGB(52, 64, 76),
	CardCantAfford = Color3.fromRGB(52, 42, 42),
	CardTierLocked = Color3.fromRGB(40, 40, 48),
	CardCapReached = Color3.fromRGB(42, 48, 42),
	-- Text
	TextPrimary = Color3.fromRGB(240, 240, 245),
	TextMuted = Color3.fromRGB(170, 170, 185),
	TextDim = Color3.fromRGB(140, 140, 150),
	TextDimmer = Color3.fromRGB(110, 110, 120),
	-- Status
	StatusAmber = Color3.fromRGB(200, 160, 80),
	StatusGreen = Color3.fromRGB(100, 200, 120),
	StatusRed = Color3.fromRGB(220, 120, 120),
	-- Buttons
	ConfirmBg = Color3.fromRGB(50, 130, 70),
	ConfirmHover = Color3.fromRGB(60, 150, 85),
	CancelBg = Color3.fromRGB(140, 55, 55),
	CancelHover = Color3.fromRGB(160, 65, 65),
	CloseBg = Color3.fromRGB(180, 55, 55),
	-- Notification
	NotifBg = Color3.fromRGB(38, 38, 46),
	NotifUpgrade = Color3.fromRGB(255, 200, 60),
	NotifUnlock = Color3.fromRGB(100, 200, 120),
	NotifItem = Color3.fromRGB(85, 170, 220),
}

-- Tween timings
local TWEEN_HOVER = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local TWEEN_NOTIF_IN = TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local TWEEN_NOTIF_OUT = TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

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

-- Confirmation dialog state
local confirmOverlay: Frame? = nil
local confirmCard: Frame? = nil
local confirmTitle: TextLabel? = nil
local confirmDesc: TextLabel? = nil
local confirmCost: TextLabel? = nil
local confirmButton: TextButton? = nil
local cancelButton: TextButton? = nil
local pendingRecipeId: string? = nil

-- Notification state
local notifGui: ScreenGui? = nil
local notifBanner: Frame? = nil
local notifTitle: TextLabel? = nil
local notifSubtitle: TextLabel? = nil
local notifStroke: UIStroke? = nil
local notifThread: thread? = nil

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

		-- Refined card colors
		if tierLocked then
			button.BackgroundColor3 = COLOR.CardTierLocked
		elseif capReached then
			button.BackgroundColor3 = COLOR.CardCapReached
		elseif affordable then
			button.BackgroundColor3 = COLOR.CardAffordable
		else
			button.BackgroundColor3 = COLOR.CardCantAfford
		end

		-- Update the status label on the card
		local statusLabel = button:FindFirstChild("RecipeStatus") :: TextLabel?
		if statusLabel then
			if tierLocked then
				statusLabel.Text = "Tier " .. tostring(recipe.Tier)
				statusLabel.TextColor3 = COLOR.StatusAmber
			elseif capReached then
				statusLabel.Text = "Built"
				statusLabel.TextColor3 = COLOR.StatusGreen
			elseif not affordable then
				statusLabel.Text = "Need resources"
				statusLabel.TextColor3 = COLOR.StatusRed
			else
				statusLabel.Text = ""
			end
		end

		-- Dim the name/cost text when unavailable
		local nameLabel = button:FindFirstChild("RecipeName") :: TextLabel?
		local costLabel = button:FindFirstChild("RecipeCost") :: TextLabel?
		local available = not tierLocked and not capReached and affordable
		if nameLabel then
			nameLabel.TextColor3 = if available then COLOR.TextPrimary else COLOR.TextDim
		end
		if costLabel then
			costLabel.TextColor3 = if available then COLOR.TextMuted else COLOR.TextDimmer
		end
	end
end

--[[
    @summary  Show an animated success notification.
    @param    title     string  -- main text (e.g. "CRAFTING BENCH UPGRADED!")
    @param    subtitle  string  -- secondary text (e.g. "Now at Tier 2")
    @param    accent    Color3  -- accent color for the stroke/title
]]
local function showNotification(title: string, subtitle: string, accent: Color3)
	if not notifGui then
		return
	end
	-- Kill any existing notification thread
	if notifThread then
		task.cancel(notifThread)
		notifThread = nil
	end

	notifTitle.Text = title
	notifSubtitle.Text = subtitle
	notifTitle.TextColor3 = accent
	notifStroke.Color = accent

	-- Start hidden, positioned above center
	notifBanner.Position = UDim2.new(0.5, 0, 0.5, 80)
	notifBanner.Size = UDim2.new(0, 380, 0, 76)
	notifGui.Enabled = true

	-- Animate in
	local inTweens = {
		TweenService:Create(notifBanner, TWEEN_NOTIF_IN, { Position = UDim2.new(0.5, 0, 0.5, -30) }),
		TweenService:Create(notifTitle, TWEEN_NOTIF_IN, { TextTransparency = 0 }),
		TweenService:Create(notifSubtitle, TWEEN_NOTIF_IN, { TextTransparency = 0 }),
		TweenService:Create(notifStroke, TWEEN_NOTIF_IN, { Transparency = 0.3 }),
	}
	for _, tween in ipairs(inTweens) do
		tween:Play()
	end

	notifThread = task.spawn(function()
		inTweens[1].Completed:Wait()
		task.wait(2.0)
		-- Animate out
		local outTweens = {
			TweenService:Create(notifBanner, TWEEN_NOTIF_OUT, { Position = UDim2.new(0.5, 0, 0.5, -100) }),
			TweenService:Create(notifTitle, TWEEN_NOTIF_OUT, { TextTransparency = 1 }),
			TweenService:Create(notifSubtitle, TWEEN_NOTIF_OUT, { TextTransparency = 1 }),
			TweenService:Create(notifStroke, TWEEN_NOTIF_OUT, { Transparency = 1 }),
		}
		for _, tween in ipairs(outTweens) do
			tween:Play()
		end
		outTweens[1].Completed:Wait()
		notifGui.Enabled = false
		notifThread = nil
	end)
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
		if typeof(result) == "table" and result.ok == true then
			-- Play success sound
			UiSoundUtil.playSuccess()
			-- Show appropriate notification based on output kind
			local recipe = RecipeConfig[recipeId]
			if recipe then
				if recipe.OutputKind == "BenchUpgrade" then
					UiSoundUtil.playLevelUp()
					local newTier = tonumber(recipe.OutputId) or currentState.tier
					showNotification(
						"CRAFTING BENCH UPGRADED!",
						"Now at Tier " .. tostring(newTier),
						COLOR.NotifUpgrade
					)
				elseif recipe.OutputKind == "Unlock" then
					showNotification(
						recipe.DisplayName:upper() .. " UNLOCKED!",
						recipe.Description,
						COLOR.NotifUnlock
					)
				elseif recipe.OutputKind == "Placement" then
					showNotification(
						recipe.DisplayName .. " Crafted!",
						"Place it in the build zone",
						COLOR.NotifItem
					)
				elseif recipe.OutputKind == "Item" then
					showNotification(
						recipe.DisplayName .. " Crafted!",
						"Added to your inventory",
						COLOR.NotifItem
					)
				end
			end
		elseif typeof(result) == "table" and result.ok ~= true and resourcesLabel then
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
    @summary  Show the confirmation dialog for a recipe.
    @param    recipeId  string
]]
local function showConfirmDialog(recipeId: string)
	local recipe = RecipeConfig[recipeId]
	if not recipe or not confirmOverlay then
		return
	end
	pendingRecipeId = recipeId
	confirmTitle.Text = recipe.DisplayName
	confirmDesc.Text = recipe.Description
	confirmCost.Text = "Cost: " .. formatCost(recipe.Cost)
	confirmOverlay.Visible = true
end

--[[
    @summary  Hide the confirmation dialog.
]]
local function hideConfirmDialog()
	if confirmOverlay then
		confirmOverlay.Visible = false
	end
	pendingRecipeId = nil
end

--[[
    @summary  Close the menu and exit gamepad selection mode.
]]
local function closeMenu()
	if gui then
		gui.Enabled = false
	end
	hideConfirmDialog()
	GuiService.SelectedObject = nil
end

--[[
    @summary  Build the notification GUI once.
]]
local function buildNotifGui()
	if notifGui then
		return
	end
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "CraftingNotifGui"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = false
	screenGui.Enabled = false
	screenGui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	notifGui = screenGui

	local banner = Instance.new("Frame")
	banner.Name = "NotifBanner"
	banner.AnchorPoint = Vector2.new(0.5, 0.5)
	banner.Position = UDim2.new(0.5, 0, 0.5, -30)
	banner.Size = UDim2.new(0, 380, 0, 76)
	banner.BackgroundColor3 = COLOR.NotifBg
	banner.BackgroundTransparency = 0.05
	banner.BorderSizePixel = 0
	banner.Parent = screenGui
	notifBanner = banner

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = banner

	local stroke = Instance.new("UIStroke")
	stroke.Color = COLOR.NotifUpgrade
	stroke.Thickness = 2
	stroke.Transparency = 1
	stroke.Parent = banner
	notifStroke = stroke

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.AnchorPoint = Vector2.new(0.5, 0)
	title.Position = UDim2.new(0.5, 0, 0, 12)
	title.Size = UDim2.new(1, -24, 0, 28)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBlack
	title.TextColor3 = COLOR.NotifUpgrade
	title.TextSize = 18
	title.TextTransparency = 1
	title.TextXAlignment = Enum.TextXAlignment.Center
	title.TextYAlignment = Enum.TextYAlignment.Center
	title.Parent = banner
	notifTitle = title

	local subtitle = Instance.new("TextLabel")
	subtitle.Name = "Subtitle"
	subtitle.AnchorPoint = Vector2.new(0.5, 0)
	subtitle.Position = UDim2.new(0.5, 0, 0, 42)
	subtitle.Size = UDim2.new(1, -24, 0, 20)
	subtitle.BackgroundTransparency = 1
	subtitle.Font = Enum.Font.Gotham
	subtitle.TextColor3 = COLOR.TextMuted
	subtitle.TextSize = 13
	subtitle.TextTransparency = 1
	subtitle.TextXAlignment = Enum.TextXAlignment.Center
	subtitle.TextYAlignment = Enum.TextYAlignment.Center
	subtitle.Parent = banner
	notifSubtitle = subtitle
end

--[[
    @summary  Build the confirmation dialog (part of the main GUI).
    @param    panelFrame  Frame  -- parent panel
]]
local function buildConfirmDialog(panelFrame: Frame)
	-- Dim overlay covering the entire panel
	local overlay = Instance.new("Frame")
	overlay.Name = "ConfirmOverlay"
	overlay.Size = UDim2.fromScale(1, 1)
	overlay.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	overlay.BackgroundTransparency = 0.5
	overlay.BorderSizePixel = 0
	overlay.Visible = false
	overlay.ZIndex = 10
	overlay.Parent = panelFrame
	confirmOverlay = overlay

	-- Centered confirmation card
	local card = Instance.new("Frame")
	card.Name = "ConfirmCard"
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position = UDim2.fromScale(0.5, 0.5)
	card.Size = UDim2.new(0, 340, 0, 180)
	card.BackgroundColor3 = COLOR.Panel
	card.BackgroundTransparency = 0
	card.BorderSizePixel = 0
	card.ZIndex = 11
	card.Parent = overlay
	confirmCard = card

	local cardCorner = Instance.new("UICorner")
	cardCorner.CornerRadius = UDim.new(0, 12)
	cardCorner.Parent = card

	local cardStroke = Instance.new("UIStroke")
	cardStroke.Color = COLOR.Stroke
	cardStroke.Thickness = 2
	cardStroke.Transparency = 0.2
	cardStroke.Parent = card

	-- Title
	local title = Instance.new("TextLabel")
	title.Name = "ConfirmTitle"
	title.Position = UDim2.new(0, 16, 0, 14)
	title.Size = UDim2.new(1, -32, 0, 26)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBlack
	title.TextColor3 = COLOR.TextPrimary
	title.TextSize = 18
	title.TextXAlignment = Enum.TextXAlignment.Center
	title.TextYAlignment = Enum.TextYAlignment.Center
	title.ZIndex = 12
	title.Parent = card
	confirmTitle = title

	-- Description
	local desc = Instance.new("TextLabel")
	desc.Name = "ConfirmDesc"
	desc.Position = UDim2.new(0, 16, 0, 44)
	desc.Size = UDim2.new(1, -32, 0, 32)
	desc.BackgroundTransparency = 1
	desc.Font = Enum.Font.Gotham
	desc.TextColor3 = COLOR.TextMuted
	desc.TextSize = 13
	desc.TextWrapped = true
	desc.TextXAlignment = Enum.TextXAlignment.Center
	desc.TextYAlignment = Enum.TextYAlignment.Center
	desc.ZIndex = 12
	desc.Parent = card
	confirmDesc = desc

	-- Cost
	local cost = Instance.new("TextLabel")
	cost.Name = "ConfirmCost"
	cost.Position = UDim2.new(0, 16, 0, 80)
	cost.Size = UDim2.new(1, -32, 0, 22)
	cost.BackgroundTransparency = 1
	cost.Font = Enum.Font.GothamBold
	cost.TextColor3 = COLOR.StatusAmber
	cost.TextSize = 14
	cost.TextXAlignment = Enum.TextXAlignment.Center
	cost.TextYAlignment = Enum.TextYAlignment.Center
	cost.ZIndex = 12
	cost.Parent = card
	confirmCost = cost

	-- Confirm button (green)
	local confirm = Instance.new("TextButton")
	confirm.Name = "ConfirmBtn"
	confirm.AnchorPoint = Vector2.new(1, 0)
	confirm.Position = UDim2.new(0.5, -6, 1, -48)
	confirm.Size = UDim2.new(0, 130, 0, 34)
	confirm.BackgroundColor3 = COLOR.ConfirmBg
	confirm.BackgroundTransparency = 0
	confirm.BorderSizePixel = 0
	confirm.AutoButtonColor = false
	confirm.Font = Enum.Font.GothamBold
	confirm.Text = "Confirm"
	confirm.TextColor3 = Color3.fromRGB(255, 255, 255)
	confirm.TextSize = 15
	confirm.ZIndex = 12
	confirm.Parent = card
	confirmButton = confirm
	local confirmCorner = Instance.new("UICorner")
	confirmCorner.CornerRadius = UDim.new(0, 8)
	confirmCorner.Parent = confirm
	confirm.MouseEnter:Connect(function()
		TweenService:Create(confirm, TWEEN_HOVER, { BackgroundColor3 = COLOR.ConfirmHover }):Play()
	end)
	confirm.MouseLeave:Connect(function()
		TweenService:Create(confirm, TWEEN_HOVER, { BackgroundColor3 = COLOR.ConfirmBg }):Play()
	end)
	confirm.Activated:Connect(function()
		UiSoundUtil.playClick()
		local id = pendingRecipeId
		hideConfirmDialog()
		if id then
			requestCraft(id)
		end
	end)

	-- Cancel button (red)
	local cancel = Instance.new("TextButton")
	cancel.Name = "CancelBtn"
	cancel.AnchorPoint = Vector2.new(0, 0)
	cancel.Position = UDim2.new(0.5, 6, 1, -48)
	cancel.Size = UDim2.new(0, 130, 0, 34)
	cancel.BackgroundColor3 = COLOR.CancelBg
	cancel.BackgroundTransparency = 0
	cancel.BorderSizePixel = 0
	cancel.AutoButtonColor = false
	cancel.Font = Enum.Font.GothamBold
	cancel.Text = "Cancel"
	cancel.TextColor3 = Color3.fromRGB(255, 255, 255)
	cancel.TextSize = 15
	cancel.ZIndex = 12
	cancel.Parent = card
	cancelButton = cancel
	local cancelCorner = Instance.new("UICorner")
	cancelCorner.CornerRadius = UDim.new(0, 8)
	cancelCorner.Parent = cancel
	cancel.MouseEnter:Connect(function()
		TweenService:Create(cancel, TWEEN_HOVER, { BackgroundColor3 = COLOR.CancelHover }):Play()
	end)
	cancel.MouseLeave:Connect(function()
		TweenService:Create(cancel, TWEEN_HOVER, { BackgroundColor3 = COLOR.CancelBg }):Play()
	end)
	cancel.Activated:Connect(function()
		UiSoundUtil.playClick()
		hideConfirmDialog()
	end)
end

--[[
    @summary  Build the crafting interface once for the local player.
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

	-- Layout constants
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

	-- Main panel: centered, solid dark background
	local panelFrame = Instance.new("Frame")
	panelFrame.Name = "Panel"
	panelFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	panelFrame.Position = UDim2.fromScale(0.5, 0.5)
	panelFrame.Size = UDim2.new(0.82, 0, 0.82, 0)
	panelFrame.BackgroundColor3 = COLOR.Panel
	panelFrame.BackgroundTransparency = 0
	panelFrame.BorderSizePixel = 0
	panelFrame.ClipsDescendants = true
	panelFrame.Parent = screenGui
	_panel = panelFrame

	local sizeConstraint = Instance.new("UISizeConstraint")
	sizeConstraint.MaxSize = Vector2.new(680, 580)
	sizeConstraint.MinSize = Vector2.new(320, 380)
	sizeConstraint.Parent = panelFrame

	-- Subtle gradient for depth
	local panelGradient = Instance.new("UIGradient")
	panelGradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, COLOR.PanelGradientTop),
		ColorSequenceKeypoint.new(1, COLOR.PanelGradientBottom),
	})
	panelGradient.Rotation = 90
	panelGradient.Parent = panelFrame

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 14)
	corner.Parent = panelFrame

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(120, 120, 140)
	stroke.Thickness = 2
	stroke.Transparency = 0.2
	stroke.Parent = panelFrame

	local y = PANEL_PADDING

	-- Header row: title on the left, close button on the right
	local title = Instance.new("TextLabel")
	title.Name = "Header"
	title.Position = UDim2.new(0, PANEL_PADDING, 0, y)
	title.Size = UDim2.new(1, -PANEL_PADDING - 50, 0, HEADER_HEIGHT)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBlack
	title.TextColor3 = COLOR.TextPrimary
	title.TextSize = 18
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextYAlignment = Enum.TextYAlignment.Center
	title.Parent = panelFrame
	titleLabel = title

	-- Close button
	local close = Instance.new("TextButton")
	close.Name = "Close"
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, -PANEL_PADDING, 0, y)
	close.Size = UDim2.fromOffset(40, HEADER_HEIGHT)
	close.BackgroundColor3 = COLOR.CloseBg
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
	close.Activated:Connect(function()
		UiSoundUtil.playClick()
		closeMenu()
	end)

	-- Hairline separator
	local hairline = Instance.new("Frame")
	hairline.Name = "HeaderHairline"
	hairline.Position = UDim2.new(0, PANEL_PADDING, 0, y + HEADER_HEIGHT)
	hairline.Size = UDim2.new(1, -2 * PANEL_PADDING, 0, 1)
	hairline.BackgroundColor3 = COLOR.Hairline
	hairline.BackgroundTransparency = 0
	hairline.BorderSizePixel = 0
	hairline.Parent = panelFrame

	y = y + HEADER_HEIGHT + PANEL_GAP

	-- Resources summary bar
	local resourcesContainer = Instance.new("Frame")
	resourcesContainer.Name = "ResourcesBar"
	resourcesContainer.Position = UDim2.new(0, PANEL_PADDING, 0, y)
	resourcesContainer.Size = UDim2.new(1, -2 * PANEL_PADDING, 0, RESOURCES_HEIGHT)
	resourcesContainer.BackgroundColor3 = COLOR.ResourceBar
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

	-- Recipe list: scrollable
	local recipeList = Instance.new("ScrollingFrame")
	recipeList.Name = "Recipes"
	recipeList.Position = UDim2.new(0, PANEL_PADDING, 0, y)
	recipeList.Size = UDim2.new(1, -2 * PANEL_PADDING, 1, -y - PANEL_PADDING)
	recipeList.BackgroundColor3 = COLOR.ListBg
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
		-- Each recipe is a solid card with name + cost sections
		local card = Instance.new("TextButton")
		card.Name = recipe.Id
		card.LayoutOrder = order
		card.Size = UDim2.new(1, 0, 0, ROW_HEIGHT)
		card.BackgroundColor3 = COLOR.CardAffordable
		card.BackgroundTransparency = 0
		card.BorderSizePixel = 0
		card.AutoButtonColor = false
		card.Text = ""
		card.Selectable = true
		card.Parent = recipeList

		local cardCorner = Instance.new("UICorner")
		cardCorner.CornerRadius = UDim.new(0, 10)
		cardCorner.Parent = card

		local cardStroke = Instance.new("UIStroke")
		cardStroke.Color = COLOR.Stroke
		cardStroke.Thickness = 1
		cardStroke.Transparency = COLOR.StrokeTransparency
		cardStroke.Parent = card

		-- Recipe name (top line, bold)
		local nameLabel = Instance.new("TextLabel")
		nameLabel.Name = "RecipeName"
		nameLabel.Position = UDim2.new(0, 12, 0, 6)
		nameLabel.Size = UDim2.new(1, -24, 0, 22)
		nameLabel.BackgroundTransparency = 1
		nameLabel.Font = Enum.Font.GothamBold
		nameLabel.TextColor3 = COLOR.TextPrimary
		nameLabel.TextSize = 15
		nameLabel.TextXAlignment = Enum.TextXAlignment.Left
		nameLabel.TextYAlignment = Enum.TextYAlignment.Center
		nameLabel.Text = recipe.DisplayName
		nameLabel.Parent = card

		-- Cost line (below name, smaller, muted)
		local costLabel = Instance.new("TextLabel")
		costLabel.Name = "RecipeCost"
		costLabel.Position = UDim2.new(0, 12, 0, 30)
		costLabel.Size = UDim2.new(1, -24, 0, 18)
		costLabel.BackgroundTransparency = 1
		costLabel.Font = Enum.Font.Gotham
		costLabel.TextColor3 = COLOR.TextMuted
		costLabel.TextSize = 13
		costLabel.TextXAlignment = Enum.TextXAlignment.Left
		costLabel.TextYAlignment = Enum.TextYAlignment.Center
		costLabel.Text = "Cost: " .. formatCost(recipe.Cost)
		costLabel.Parent = card

		-- Status label (right side, for tier/cap info)
		local statusLabel = Instance.new("TextLabel")
		statusLabel.Name = "RecipeStatus"
		statusLabel.AnchorPoint = Vector2.new(1, 0.5)
		statusLabel.Position = UDim2.new(1, -12, 0.5, 0)
		statusLabel.Size = UDim2.new(0, 100, 0, 20)
		statusLabel.BackgroundTransparency = 1
		statusLabel.Font = Enum.Font.GothamBold
		statusLabel.TextColor3 = COLOR.StatusAmber
		statusLabel.TextSize = 12
		statusLabel.TextXAlignment = Enum.TextXAlignment.Right
		statusLabel.TextYAlignment = Enum.TextYAlignment.Center
		statusLabel.Text = ""
		statusLabel.Parent = card

		-- Hover effect: lighten card background on mouse enter
		card.MouseEnter:Connect(function()
			if card.Active then
				TweenService:Create(card, TWEEN_HOVER, { BackgroundColor3 = COLOR.CardAffordableHover }):Play()
			end
		end)
		card.MouseLeave:Connect(function()
			if card.Active then
				TweenService:Create(card, TWEEN_HOVER, { BackgroundColor3 = COLOR.CardAffordable }):Play()
			end
		end)

		-- Click shows confirmation dialog instead of crafting directly
		card.Activated:Connect(function()
			if card.Active then
				UiSoundUtil.playClick()
				showConfirmDialog(recipe.Id)
			end
		end)
		buttons[recipe.Id] = card
	end

	-- Build the confirmation dialog as a child of the panel
	buildConfirmDialog(panelFrame)
end

--[[
    @summary  Open the menu and request a fresh authoritative snapshot.
]]
local function openMenu()
	buildUi()
	buildNotifGui()
	if gui then
		gui.Enabled = true
	end
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
		refreshDisplay()
	end)
end

-- // INITIALIZATION // --

function CraftingController:KnitStart()
	craftingService = Knit.GetService("CraftingService")
	local runStateService = Knit.GetService("RunStateService")
	buildUi()
	buildNotifGui()
	craftingService.OpenCrafting:Connect(function()
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
