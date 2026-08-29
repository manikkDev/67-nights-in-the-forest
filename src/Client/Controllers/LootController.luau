--[[
    @file    LootController.luau
    @author  manik
    @date    2025

    @summary
    Client-side chest loot UI panel and opening VFX.

    @description
    Listens to LootService.ChestOpened to show a compact loot panel
    displaying what items were inside the chest, with icons,
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

-- Green accent palette for a clean, professional look.
local ACCENT_COLOR = Color3.fromRGB(80, 200, 120)
local ACCENT_DIM = Color3.fromRGB(50, 140, 80)

-- | State Management | --
local lootGui: ScreenGui? = nil
local overlay: Frame? = nil
local panel: Frame? = nil
local dismissTimer: thread? = nil

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
    @summary  Build a single compact item row inside the loot panel.
    @param    parent    Frame
    @param    itemName  string
    @param    count     number
]]
local function buildItemRow(parent: Frame, itemName: string, count: number)
	local row = Instance.new("Frame")
	row.Name = "ItemRow" .. itemName
	row.Size = UDim2.new(1, 0, 0, 44)
	row.BackgroundColor3 = Color3.fromRGB(35, 38, 44)
	row.BackgroundTransparency = 0.4
	row.BorderSizePixel = 0
	row.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = row

	local icon = Instance.new("Frame")
	icon.Name = "Icon"
	icon.Size = UDim2.new(0, 32, 0, 32)
	icon.Position = UDim2.new(0, 8, 0.5, -16)
	icon.BackgroundColor3 = ITEM_COLORS[itemName] or Color3.fromRGB(120, 120, 130)
	icon.BorderSizePixel = 0
	icon.Parent = row

	local iconCorner = Instance.new("UICorner")
	iconCorner.CornerRadius = UDim.new(0, 6)
	iconCorner.Parent = icon

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "Name"
	nameLabel.Size = UDim2.new(1, -120, 0, 20)
	nameLabel.Position = UDim2.new(0, 48, 0, 4)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextSize = 14
	nameLabel.TextColor3 = Color3.fromRGB(235, 238, 242)
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.Text = itemName
	nameLabel.Parent = row

	local descLabel = Instance.new("TextLabel")
	descLabel.Name = "Desc"
	descLabel.Size = UDim2.new(1, -120, 0, 16)
	descLabel.Position = UDim2.new(0, 48, 0, 24)
	descLabel.BackgroundTransparency = 1
	descLabel.Font = Enum.Font.Gotham
	descLabel.TextSize = 11
	descLabel.TextColor3 = Color3.fromRGB(150, 155, 165)
	descLabel.TextXAlignment = Enum.TextXAlignment.Left
	descLabel.Text = ITEM_DESCRIPTIONS[itemName] or ""
	descLabel.Parent = row

	local countBadge = Instance.new("TextLabel")
	countBadge.Name = "Count"
	countBadge.Size = UDim2.new(0, 40, 0, 22)
	countBadge.Position = UDim2.new(1, -48, 0.5, -11)
	countBadge.BackgroundColor3 = Color3.fromRGB(40, 48, 40)
	countBadge.BackgroundTransparency = 0.2
	countBadge.Font = Enum.Font.GothamBold
	countBadge.TextSize = 13
	countBadge.TextColor3 = ACCENT_COLOR
	countBadge.Text = "x" .. tostring(count)
	countBadge.Parent = row

	local badgeCorner = Instance.new("UICorner")
	badgeCorner.CornerRadius = UDim.new(0, 5)
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
	if dismissTimer then
		task.cancel(dismissTimer)
		dismissTimer = nil
	end
	if overlay then
		overlay.Visible = true
	end

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

	-- Compact panel sizing.
	local PANEL_WIDTH = 360
	local rowCount = #itemNames
	local rowsHeight = rowCount * 50 -- 44px row + 6px padding
	local PANEL_HEIGHT = 70 + rowsHeight + 16 -- header + rows + bottom padding

	-- Build the panel.
	local newPanel = Instance.new("Frame")
	newPanel.Name = "LootPanel"
	newPanel.Size = UDim2.new(0, PANEL_WIDTH, 0, PANEL_HEIGHT)
	newPanel.Position = UDim2.new(0.5, -PANEL_WIDTH / 2, 0.5, -PANEL_HEIGHT / 2 + 40)
	newPanel.BackgroundColor3 = Color3.fromRGB(24, 28, 32)
	newPanel.BackgroundTransparency = 0.03
	newPanel.BorderSizePixel = 0
	newPanel.ClipsDescendants = true
	newPanel.Parent = lootGui

	local panelCorner = Instance.new("UICorner")
	panelCorner.CornerRadius = UDim.new(0, 12)
	panelCorner.Parent = newPanel

	local panelStroke = Instance.new("UIStroke")
	panelStroke.Color = ACCENT_COLOR
	panelStroke.Thickness = 1.5
	panelStroke.Transparency = 0.25
	panelStroke.Parent = newPanel

	local panelGradient = Instance.new("UIGradient")
	panelGradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(32, 38, 42)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(22, 26, 30)),
	})
	panelGradient.Rotation = 90
	panelGradient.Parent = newPanel

	-- Close (X) button at top-right corner.
	local closeBtn = Instance.new("TextButton")
	closeBtn.Name = "CloseX"
	closeBtn.Size = UDim2.new(0, 28, 0, 28)
	closeBtn.Position = UDim2.new(1, -34, 0, 6)
	closeBtn.BackgroundColor3 = Color3.fromRGB(40, 45, 50)
	closeBtn.BackgroundTransparency = 0.3
	closeBtn.Font = Enum.Font.GothamBold
	closeBtn.TextSize = 16
	closeBtn.TextColor3 = Color3.fromRGB(180, 185, 190)
	closeBtn.Text = "X"
	closeBtn.AutoButtonColor = true
	closeBtn.Parent = newPanel

	local closeCorner = Instance.new("UICorner")
	closeCorner.CornerRadius = UDim.new(0, 6)
	closeCorner.Parent = closeBtn

	-- Header (title + subtitle) — left-aligned, compact.
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(1, -44, 0, 24)
	title.Position = UDim2.new(0, 16, 0, 10)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBold
	title.TextSize = 18
	title.TextColor3 = ACCENT_COLOR
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Text = "Chest Opened"
	title.Parent = newPanel

	local subtitle = Instance.new("TextLabel")
	subtitle.Name = "Subtitle"
	subtitle.Size = UDim2.new(1, -44, 0, 16)
	subtitle.Position = UDim2.new(0, 16, 0, 34)
	subtitle.BackgroundTransparency = 1
	subtitle.Font = Enum.Font.Gotham
	subtitle.TextSize = 12
	subtitle.TextColor3 = Color3.fromRGB(140, 148, 158)
	subtitle.TextXAlignment = Enum.TextXAlignment.Left
	subtitle.Text = tierName
	subtitle.Parent = newPanel

	-- Separator line.
	local separator = Instance.new("Frame")
	separator.Name = "Separator"
	separator.Size = UDim2.new(1, -32, 0, 1)
	separator.Position = UDim2.new(0, 16, 0, 56)
	separator.BackgroundColor3 = ACCENT_DIM
	separator.BackgroundTransparency = 0.5
	separator.BorderSizePixel = 0
	separator.Parent = newPanel

	-- Item rows container.
	local rowsFrame = Instance.new("Frame")
	rowsFrame.Name = "Rows"
	rowsFrame.Size = UDim2.new(1, -32, 0, rowsHeight)
	rowsFrame.Position = UDim2.new(0, 16, 0, 64)
	rowsFrame.BackgroundTransparency = 1
	rowsFrame.BorderSizePixel = 0
	rowsFrame.Parent = newPanel

	local rowsLayout = Instance.new("UIListLayout")
	rowsLayout.Padding = UDim.new(0, 6)
	rowsLayout.FillDirection = Enum.FillDirection.Vertical
	rowsLayout.Parent = rowsFrame

	for _, itemName in ipairs(itemNames) do
		buildItemRow(rowsFrame, itemName, granted[itemName])
	end

	-- Entrance animation.
	local closedPos = UDim2.new(0.5, -PANEL_WIDTH / 2, 0.5, -PANEL_HEIGHT / 2 + 40)
	local openPos = UDim2.new(0.5, -PANEL_WIDTH / 2, 0.5, -PANEL_HEIGHT / 2)
	newPanel.Position = closedPos
	newPanel.BackgroundTransparency = 1
	TweenService:Create(newPanel, TweenInfo.new(0.3, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
		Position = openPos,
		BackgroundTransparency = 0.03,
	}):Play()

	panel = newPanel

	-- Auto-dismiss timer.
	dismissTimer = task.delay(PANEL_AUTO_DISMISS, function()
		LootController:DismissPanel()
	end)

	-- Close button handler.
	closeBtn.Activated:Connect(function()
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
		local closed = fadePanel.Position + UDim2.new(0, 0, 0, 40)
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
