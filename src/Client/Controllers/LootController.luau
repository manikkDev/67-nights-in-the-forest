--[[
    @file    LootController.luau
    @author  manik
    @date    2025

    @summary
    Client-side chest loot UI panel and opening VFX.

    @description
    Listens to LootService.ChestOpened to show a professional loot
    panel displaying what items were inside the chest, with icons,
    quantities, and descriptions.  Also plays client-side particle
    burst, light flash, and sound at the chest position for instant
    feedback.

    @exports
    - LootController (Knit Controller)
]]

-- // VARIABLES // --

-- | Services | --
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

-- | Modules | --
local Knit = require(ReplicatedStorage.Packages.Knit)

-- | Objects | --
local LootController = Knit.CreateController({
	Name = "LootController",
})

-- | Configuration | --
local CHEST_OPEN_SOUND_ID = "rbxassetid://9120873624"
local PANEL_AUTO_DISMISS = 8

-- Item display data: colors and descriptions for loot UI rows.
local ITEM_COLORS = {
	Wood = Color3.fromRGB(170, 110, 65),
	Scrap = Color3.fromRGB(150, 155, 165),
	Coal = Color3.fromRGB(70, 70, 75),
	Bandage = Color3.fromRGB(235, 235, 225),
	CultistGem = Color3.fromRGB(175, 90, 210),
	Berries = Color3.fromRGB(195, 50, 80),
	Mushrooms = Color3.fromRGB(210, 110, 95),
	RawMeat = Color3.fromRGB(200, 100, 100),
	CookedMeat = Color3.fromRGB(215, 160, 80),
	RabbitMeat = Color3.fromRGB(200, 100, 100),
	Spear = Color3.fromRGB(170, 170, 180),
}

local ITEM_DESCRIPTIONS = {
	Wood = "Used for building and fueling campfires.",
	Scrap = "Salvaged metal used for advanced crafting.",
	Coal = "Burns far longer than wood in the campfire.",
	Bandage = "Revives a downed teammate.",
	CultistGem = "A rare cultist relic used in late crafting.",
	Berries = "Restores a small amount of hunger.",
	Mushrooms = "Restores a small amount of hunger.",
	RawMeat = "Cook it at the campfire to restore more hunger.",
	CookedMeat = "A filling meal that restores lots of hunger.",
	RabbitMeat = "Fresh rabbit meat. Cook it at the campfire.",
	Spear = "A melee weapon for combat against enemies.",
}

local TIER_DISPLAY = {
	Basic = "Basic Chest",
	Gold = "Gold Chest",
	CaveDino = "Dino Cave Chest",
}

local TIER_COLORS = {
	Basic = Color3.fromRGB(180, 140, 80),
	Gold = Color3.fromRGB(255, 200, 60),
	CaveDino = Color3.fromRGB(190, 55, 50),
}

-- | State Management | --
local lootGui: ScreenGui? = nil
local overlay: Frame? = nil
local panel: Frame? = nil
local dismissTimer: number? = nil

-- // FUNCTIONS // --

--[[
    @summary  Spawn client-side VFX (particles + light + sound) at a
              chest position for instant feedback.
    @param    position  Vector3
]]
local function spawnClientVFX(position: Vector3)
	local anchor = Instance.new("Part")
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.Position = position + Vector3.new(0, 1, 0)
	anchor.Parent = workspace

	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	emitter.Color = ColorSequence.new(Color3.fromRGB(255, 215, 120))
	emitter.Lifetime = NumberRange.new(0.4, 0.8)
	emitter.Speed = NumberRange.new(6, 12)
	emitter.SpreadAngle = Vector2.new(45, 45)
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1.5),
		NumberSequenceKeypoint.new(1, 0.1),
	})
	emitter.Rate = 0
	emitter.Parent = anchor
	emitter:Emit(30)

	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 215, 120)
	light.Brightness = 5
	light.Range = 15
	light.Parent = anchor
	TweenService:Create(light, TweenInfo.new(0.6, Enum.EasingStyle.Quad), { Brightness = 0 }):Play()

	local sound = Instance.new("Sound")
	sound.SoundId = CHEST_OPEN_SOUND_ID
	sound.Volume = 1
	sound.Parent = anchor
	sound:Play()

	Debris:AddItem(anchor, 3)
end

--[[
    @summary  Build a single item row inside the loot panel.
    @param    parent    Frame
    @param    itemName  string
    @param    count     number
]]
local function buildItemRow(parent: Frame, itemName: string, count: number)
	local row = Instance.new("Frame")
	row.Name = "ItemRow" .. itemName
	row.Size = UDim2.new(1, 0, 0, 58)
	row.BackgroundColor3 = Color3.fromRGB(38, 41, 48)
	row.BackgroundTransparency = 0.3
	row.BorderSizePixel = 0
	row.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = row

	local icon = Instance.new("Frame")
	icon.Name = "Icon"
	icon.Size = UDim2.new(0, 40, 0, 40)
	icon.Position = UDim2.new(0, 12, 0.5, -20)
	icon.BackgroundColor3 = ITEM_COLORS[itemName] or Color3.fromRGB(120, 120, 130)
	icon.BorderSizePixel = 0
	icon.Parent = row

	local iconCorner = Instance.new("UICorner")
	iconCorner.CornerRadius = UDim.new(0, 8)
	iconCorner.Parent = icon

	local iconStroke = Instance.new("UIStroke")
	iconStroke.Color = Color3.fromRGB(255, 255, 255)
	iconStroke.Transparency = 0.7
	iconStroke.Thickness = 1
	iconStroke.Parent = icon

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "Name"
	nameLabel.Size = UDim2.new(1, -135, 0, 22)
	nameLabel.Position = UDim2.new(0, 64, 0, 7)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextSize = 16
	nameLabel.TextColor3 = Color3.fromRGB(240, 240, 245)
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.Text = itemName
	nameLabel.Parent = row

	local descLabel = Instance.new("TextLabel")
	descLabel.Name = "Desc"
	descLabel.Size = UDim2.new(1, -135, 0, 18)
	descLabel.Position = UDim2.new(0, 64, 0, 30)
	descLabel.BackgroundTransparency = 1
	descLabel.Font = Enum.Font.Gotham
	descLabel.TextSize = 12
	descLabel.TextColor3 = Color3.fromRGB(160, 165, 175)
	descLabel.TextXAlignment = Enum.TextXAlignment.Left
	descLabel.Text = ITEM_DESCRIPTIONS[itemName] or ""
	descLabel.Parent = row

	local countBadge = Instance.new("TextLabel")
	countBadge.Name = "Count"
	countBadge.Size = UDim2.new(0, 48, 0, 28)
	countBadge.Position = UDim2.new(1, -60, 0.5, -14)
	countBadge.BackgroundColor3 = Color3.fromRGB(50, 55, 65)
	countBadge.BackgroundTransparency = 0.2
	countBadge.Font = Enum.Font.GothamBold
	countLabel.TextSize = 14
	countBadge.TextColor3 = Color3.fromRGB(255, 215, 120)
	countBadge.Text = "x" .. tostring(count)
	countBadge.Parent = row

	local badgeCorner = Instance.new("UICorner")
	badgeCorner.CornerRadius = UDim.new(0, 6)
	badgeCorner.Parent = countBadge
end

--[[
    @summary  Show the loot panel with granted items.
    @param    position  Vector3
    @param    tier      string
    @param    granted   table
]]
local function showLootPanel(position: Vector3, tier: string, granted: { [string]: number })
	if not lootGui then
		return
	end

	-- Clear previous panel.
	if panel then
		panel:Destroy()
		panel = nil
	end
	if overlay then
		overlay.Visible = true
	end

	local tierColor = TIER_COLORS[tier] or Color3.fromRGB(200, 180, 100)
	local tierName = TIER_DISPLAY[tier] or "Chest"

	-- Sort: tools first, then resources alphabetically.
	local itemNames = {}
	for name in pairs(granted) do
		table.insert(itemNames, name)
	end
	table.sort(itemNames, function(a, b)
		local aIsTool = (a == "Spear")
		local bIsTool = (b == "Spear")
		if aIsTool ~= bIsTool then
			return aIsTool
		end
		return a < b
	end)

	local PANEL_WIDTH = 440
	local rowCount = math.min(#itemNames, 5)
	local contentHeight = 156 + rowCount * 64
	local PANEL_HEIGHT = math.min(contentHeight + 20, 480)

	-- Build the panel.
	local newPanel = Instance.new("Frame")
	newPanel.Name = "LootPanel"
	newPanel.Size = UDim2.new(0, PANEL_WIDTH, 0, PANEL_HEIGHT)
	newPanel.Position = UDim2.new(0.5, -PANEL_WIDTH / 2, 0.5, -PANEL_HEIGHT / 2 + 60)
	newPanel.BackgroundColor3 = Color3.fromRGB(28, 30, 36)
	newPanel.BackgroundTransparency = 0.05
	newPanel.BorderSizePixel = 0
	newPanel.ClipsDescendants = true
	newPanel.Parent = lootGui

	local panelCorner = Instance.new("UICorner")
	panelCorner.CornerRadius = UDim.new(0, 16)
	panelCorner.Parent = newPanel

	local panelStroke = Instance.new("UIStroke")
	panelStroke.Color = tierColor
	panelStroke.Thickness = 2
	panelStroke.Transparency = 0.2
	panelStroke.Parent = newPanel

	local panelGradient = Instance.new("UIGradient")
	panelGradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(40, 42, 50)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(25, 27, 33)),
	})
	panelGradient.Rotation = 90
	panelGradient.Parent = newPanel

	-- Padding around all content.
	local panelPadding = Instance.new("UIPadding")
	panelPadding.PaddingLeft = UDim.new(0, 22)
	panelPadding.PaddingRight = UDim.new(0, 22)
	panelPadding.PaddingTop = UDim.new(0, 22)
	panelPadding.PaddingBottom = UDim.new(0, 22)
	panelPadding.Parent = newPanel

	-- Vertical content layout.
	local panelLayout = Instance.new("UIListLayout")
	panelLayout.Padding = UDim.new(0, 12)
	panelLayout.FillDirection = Enum.FillDirection.Vertical
	panelLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	panelLayout.Parent = newPanel

	-- Header container.
	local header = Instance.new("Frame")
	header.Name = "Header"
	header.Size = UDim2.new(1, 0, 0, 52)
	header.BackgroundTransparency = 1
	header.Parent = newPanel

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(1, 0, 0, 30)
	title.Position = UDim2.new(0, 0, 0, 0)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBold
	title.TextSize = 22
	title.TextColor3 = tierColor
	title.Text = "Chest Opened"
	title.Parent = header

	local subtitle = Instance.new("TextLabel")
	subtitle.Name = "Subtitle"
	subtitle.Size = UDim2.new(1, 0, 0, 18)
	subtitle.Position = UDim2.new(0, 0, 0, 30)
	subtitle.BackgroundTransparency = 1
	subtitle.Font = Enum.Font.Gotham
	subtitle.TextSize = 14
	subtitle.TextColor3 = Color3.fromRGB(160, 165, 175)
	subtitle.Text = tierName
	subtitle.Parent = header

	-- Separator.
	local separator = Instance.new("Frame")
	separator.Name = "Separator"
	separator.Size = UDim2.new(1, 0, 0, 2)
	separator.BackgroundColor3 = tierColor
	separator.BackgroundTransparency = 0.4
	separator.BorderSizePixel = 0
	separator.Parent = newPanel

	-- Item rows container (scrollable if more than 5 items).
	local rowsFrame = Instance.new("ScrollingFrame")
	rowsFrame.Name = "Rows"
	rowsFrame.Size = UDim2.new(1, 0, 1, -170)
	rowsFrame.BackgroundTransparency = 1
	rowsFrame.BorderSizePixel = 0
	rowsFrame.ScrollBarThickness = 6
	rowsFrame.ScrollBarImageColor3 = tierColor
	rowsFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
	rowsFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
	rowsFrame.Parent = newPanel

	local rowsLayout = Instance.new("UIListLayout")
	rowsLayout.Padding = UDim.new(0, 6)
	rowsLayout.FillDirection = Enum.FillDirection.Vertical
	rowsLayout.Parent = rowsFrame

	local rowsPadding = Instance.new("UIPadding")
	rowsPadding.PaddingRight = UDim.new(0, 6)
	rowsPadding.Parent = rowsFrame

	for _, itemName in ipairs(itemNames) do
		buildItemRow(rowsFrame, itemName, granted[itemName])
	end

	-- Spacer before close button.
	local spacer = Instance.new("Frame")
	spacer.Name = "Spacer"
	spacer.Size = UDim2.new(1, 0, 0, 0)
	spacer.BackgroundTransparency = 1
	spacer.Parent = newPanel

	-- Close button.
	local closeButton = Instance.new("TextButton")
	closeButton.Name = "CloseButton"
	closeButton.Size = UDim2.new(1, 0, 0, 44)
	closeButton.BackgroundColor3 = Color3.fromRGB(45, 48, 56)
	closeButton.BackgroundTransparency = 0.2
	closeButton.Font = Enum.Font.GothamBold
	closeButton.TextSize = 16
	closeButton.TextColor3 = Color3.fromRGB(230, 230, 235)
	closeButton.Text = "Close"
	closeButton.AutoButtonColor = true
	closeButton.Parent = newPanel

	local btnCorner = Instance.new("UICorner")
	btnCorner.CornerRadius = UDim.new(0, 10)
	btnCorner.Parent = closeButton

	local btnStroke = Instance.new("UIStroke")
	btnStroke.Color = tierColor
	btnStroke.Thickness = 1.5
	btnStroke.Transparency = 0.3
	btnStroke.Parent = closeButton

	-- Entrance animation.
	local closedPosition = UDim2.new(0.5, -PANEL_WIDTH / 2, 0.5, -PANEL_HEIGHT / 2 + 60)
	local openPosition = UDim2.new(0.5, -PANEL_WIDTH / 2, 0.5, -PANEL_HEIGHT / 2)
	newPanel.Position = closedPosition
	newPanel.BackgroundTransparency = 1
	TweenService:Create(newPanel, TweenInfo.new(0.35, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
		Position = openPosition,
		BackgroundTransparency = 0.05,
	}):Play()

	panel = newPanel

	-- Auto-dismiss timer.
	if dismissTimer then
		task.cancel(dismissTimer)
	end
	dismissTimer = task.delay(PANEL_AUTO_DISMISS, function()
		LootController:DismissPanel()
	end)

	-- Close button handler.
	closeButton.Activated:Connect(function()
		LootController:DismissPanel()
	end)
end

--[[
    @summary  Dismiss the loot panel with a fade-out animation.
]]
function LootController:DismissPanel()
	if dismissTimer then
		task.cancel(dismissTimer)
		dismissTimer = nil
	end
	if panel and panel.Parent then
		local fadePanel = panel
		local closed = fadePanel.Position + UDim2.new(0, 0, 0, 60)
		TweenService:Create(fadePanel, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Position = closed,
			BackgroundTransparency = 1,
		}):Play()
		task.delay(0.3, function()
			fadePanel:Destroy()
		end)
		panel = nil
	end
	if overlay then
		overlay.Visible = false
	end
end

-- // INITIALIZATION // --

function LootController:KnitStart()
	local gui = Instance.new("ScreenGui")
	gui.Name = "LootGui"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 20
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	lootGui = gui

	local ov = Instance.new("Frame")
	ov.Name = "Overlay"
	ov.Size = UDim2.new(1, 0, 1, 0)
	ov.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	ov.BackgroundTransparency = 0.5
	ov.BorderSizePixel = 0
	ov.Visible = false
	ov.Parent = gui
	overlay = ov

	-- Listen to ChestOpened signal.
	local lootService = Knit.GetService("LootService")
	lootService.ChestOpened:Connect(function(position: Vector3, tier: string, granted: { [string]: number }, _openerUserId: number)
		spawnClientVFX(position)
		showLootPanel(position, tier, granted)
	end)
end

return LootController
