--[[
    @file    HealthBarController.luau
    @author  manik
    @date    2025

    @summary
    Client-side health bars and floating damage numbers for all
    AnimalAIService NPCs.

    @description
    Subscribes to AnimalAIService.NpcHealthChanged and renders a
    professional BillboardGui health bar above each damaged NPC,
    plus a floating damage number that rises and fades.  Health bars
    auto-hide after 5 seconds without a hit.  Bar colour interpolates
    from green → yellow → red based on health ratio.

    @exports
    - HealthBarController (Knit Controller)
]]

-- // VARIABLES // --

-- | Services | --
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")

-- | Modules | --
local Knit = require(ReplicatedStorage.Packages.Knit)

-- | Objects | --
local HealthBarController = Knit.CreateController({
	Name = "HealthBarController",
})

-- | Configuration | --
local BAR_WIDTH = 6
local BAR_HEIGHT = 0.7
local BAR_OFFSET = Vector3.new(0, 4, 0)
local BAR_HIDE_DELAY = 5
local BAR_FADE_DURATION = 0.4
local DAMAGE_NUMBER_LIFETIME = 1.2
local DAMAGE_NUMBER_RISE = 3
local DAMAGE_NUMBER_MAX_OFFSET = 1.5

-- | State Management | --
local activeBars: { [Model]: { gui: BillboardGui, fill: Frame, bg: Frame, lastHit: number } } = {}

-- // FUNCTIONS // --

-- | Private | --

--[[
    @summary  Pick a colour along the green → yellow → red gradient
              based on a 0–1 health ratio.
    @param    ratio  number
    @returns  Color3
]]
local function healthColor(ratio: number): Color3
	ratio = math.clamp(ratio, 0, 1)
	if ratio > 0.5 then
		-- Green to Yellow
		local t = (1 - ratio) * 2
		return Color3.fromRGB(0, 255, 60):Lerp(Color3.fromRGB(255, 255, 0), t)
	else
		-- Yellow to Red
		local t = 1 - (ratio * 2)
		return Color3.fromRGB(255, 255, 0):Lerp(Color3.fromRGB(255, 0, 0), t)
	end
end

--[[
    @summary  Create a BillboardGui health bar above a model.
    @param    model  Model
    @returns  BillboardGui, Frame
]]
local function createHealthBar(model: Model): (BillboardGui, Frame, Frame)
	local gui = Instance.new("BillboardGui")
	gui.Name = "NpcHealthBar"
	gui.Adornee = model
	gui.Size = UDim2.fromScale(BAR_WIDTH / 3, BAR_HEIGHT)
	gui.StudsOffsetWorldSpace = BAR_OFFSET
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.MaxDistance = 120
	gui.ResetOnSpawn = false

	-- Background frame (dark rounded container)
	local bg = Instance.new("Frame")
	bg.Name = "Background"
	bg.Size = UDim2.fromScale(1, 1)
	bg.BackgroundColor3 = Color3.fromRGB(15, 15, 20)
	bg.BackgroundTransparency = 0.5
	bg.BorderSizePixel = 0
	bg.Parent = gui

	local bgCorner = Instance.new("UICorner")
	bgCorner.CornerRadius = UDim.new(0.3, 0)
	bgCorner.Parent = bg

	local bgStroke = Instance.new("UIStroke")
	bgStroke.Color = Color3.fromRGB(255, 255, 255)
	bgStroke.Transparency = 0.6
	bgStroke.Thickness = 1.5
	bgStroke.Parent = bg

	-- Padding container
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0.06, 0)
	pad.PaddingRight = UDim.new(0.06, 0)
	pad.PaddingTop = UDim.new(0.1, 0)
	pad.PaddingBottom = UDim.new(0.1, 0)
	pad.Parent = bg

	-- Fill bar
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = Color3.fromRGB(0, 255, 60)
	fill.BorderSizePixel = 0
	fill.Parent = bg

	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0.25, 0)
	fillCorner.Parent = fill

	gui.Parent = model

	return gui, fill, bg
end

--[[
    @summary  Spawn a floating damage number at a world position.
    @param    position  Vector3
    @param    amount    number
]]
local function spawnDamageNumber(position: Vector3, amount: number)
	local attachment = Instance.new("Part")
	attachment.Anchored = true
	attachment.CanCollide = false
	attachment.CanQuery = false
	attachment.Transparency = 1
	attachment.Size = Vector3.new(0.2, 0.2, 0.2)
	attachment.Position = position + Vector3.new(
		(math.random() - 0.5) * DAMAGE_NUMBER_MAX_OFFSET,
		0,
		(math.random() - 0.5) * DAMAGE_NUMBER_MAX_OFFSET
	)
	attachment.Parent = workspace

	local gui = Instance.new("BillboardGui")
	gui.Adornee = attachment
	gui.Size = UDim2.fromScale(4, 2)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 0, 0)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.MaxDistance = 100
	gui.Parent = attachment

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = "-" .. tostring(amount)
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = if amount >= 25
		then Color3.fromRGB(255, 60, 60)
		elseif amount >= 15
			then Color3.fromRGB(255, 140, 60)
			else Color3.fromRGB(255, 200, 80)
	label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	label.TextStrokeTransparency = 0.2
	label.Parent = gui

	-- Scale pop: start small, pop to full
	gui.Size = UDim2.fromScale(2, 1)
	TweenService:Create(gui, TweenInfo.new(0.12, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Size = UDim2.fromScale(4, 2),
	}):Play()

	-- Tween upward and fade
	local startPos = attachment.Position
	local endPos = startPos + Vector3.new(0, DAMAGE_NUMBER_RISE, 0)

	local tweenInfo = TweenInfo.new(DAMAGE_NUMBER_LIFETIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

	TweenService:Create(attachment, tweenInfo, { Position = endPos }):Play()
	TweenService:Create(label, tweenInfo, { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()

	Debris:AddItem(attachment, DAMAGE_NUMBER_LIFETIME + 0.2)
end

--[[
    @summary  Show or update a health bar for a damaged NPC.
    @param    model        Model
    @param    healthRatio  number  (0–1)
    @param    damage       number
    @param    position     Vector3
]]
local function onNpcHealthChanged(model: Model, healthRatio: number, damage: number, position: Vector3)
	if not model or not model.Parent then
		return
	end

	local entry = activeBars[model]
	if not entry then
		local gui, fill, bg = createHealthBar(model)
		entry = {
			gui = gui,
			fill = fill,
			bg = bg,
			lastHit = os.clock(),
		}
		activeBars[model] = entry

		-- Start invisible and fade in
		bg.BackgroundTransparency = 1
		fill.BackgroundTransparency = 1
		TweenService:Create(bg, TweenInfo.new(0.2), { BackgroundTransparency = 0.15 }):Play()
		TweenService:Create(fill, TweenInfo.new(0.2), { BackgroundTransparency = 0 }):Play()
	end

	entry.lastHit = os.clock()

	-- Tween fill width and colour
	local targetSize = UDim2.fromScale(math.clamp(healthRatio, 0, 1), 1)
	local targetColor = healthColor(healthRatio)

	TweenService:Create(entry.fill, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = targetSize,
		BackgroundColor3 = targetColor,
	}):Play()

	-- Spawn damage number
	if damage > 0 then
		spawnDamageNumber(position, damage)
	end
end

--[[
    @summary  Hide and clean up a health bar for a model.
    @param    model  Model
]]
local function removeHealthBar(model: Model)
	local entry = activeBars[model]
	if not entry then
		return
	end
	activeBars[model] = nil

	-- Fade out
	TweenService:Create(entry.bg, TweenInfo.new(BAR_FADE_DURATION), { BackgroundTransparency = 1 }):Play()
	TweenService:Create(entry.fill, TweenInfo.new(BAR_FADE_DURATION), { BackgroundTransparency = 1 }):Play()

	Debris:AddItem(entry.gui, BAR_FADE_DURATION + 0.1)
end

-- | Heartbeat | --

--[[
    @summary  Periodically hide health bars that haven't been hit recently.
]]
local function startHideLoop()
	RunService.Heartbeat:Connect(function()
		local now = os.clock()
		for model, entry in pairs(activeBars) do
			if not model.Parent then
				removeHealthBar(model)
			elseif (now - entry.lastHit) > BAR_HIDE_DELAY then
				removeHealthBar(model)
			end
		end
	end)
end

-- // INITIALIZATION // --

function HealthBarController:KnitStart()
	local animalAIService = Knit.GetService("AnimalAIService")

	animalAIService.NpcHealthChanged:Connect(function(model: Model, healthRatio: number, damage: number, position: Vector3)
		onNpcHealthChanged(model, healthRatio, damage, position)
	end)

	animalAIService.NpcDied:Connect(function(model: Model, _position: Vector3, _key: string)
		if model then
			removeHealthBar(model)
		end
	end)

	startHideLoop()
end

return HealthBarController
