--[[
    @file    EndingController.luau
    @author  manik
    @date    2025

    @summary
    Cinematic Day 67 victory or defeat presentation with final run
    statistics, staggered card animations, and a Return-to-Lobby button.
]]

-- // VARIABLES // --

-- | Services | --
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

-- | Modules | --
local Knit = require(ReplicatedStorage.Packages.Knit)

-- | Objects | --
local EndingController = Knit.CreateController({
	Name = "EndingController",
})

-- | Configuration | --
local BACKDROP_COLOR = Color3.fromRGB(5, 7, 9)
local VICTORY_COLOR = Color3.fromRGB(240, 220, 165)
local DEFEAT_COLOR = Color3.fromRGB(200, 60, 55)
local SUBTITLE_COLOR = Color3.fromRGB(170, 170, 175)
local CARD_BG = Color3.fromRGB(18, 20, 24)
local CARD_STROKE = Color3.fromRGB(50, 52, 58)
local CARD_VALUE_COLOR = Color3.fromRGB(240, 240, 235)
local CARD_LABEL_COLOR = Color3.fromRGB(140, 142, 150)
local BUTTON_BG = Color3.fromRGB(30, 32, 38)
local BUTTON_BG_HOVER = Color3.fromRGB(42, 44, 52)
local BUTTON_TEXT = Color3.fromRGB(230, 230, 235)
local MULTIPLIER_COLOR = Color3.fromRGB(240, 200, 110)

local CARD_WIDTH = 180
local CARD_HEIGHT = 90
local CARD_GAP = 14
local CARDS_PER_ROW = 2

-- | State Management | --
local endingService: any = nil
local runStateService: any = nil
local gui: ScreenGui? = nil
local backdrop: Frame? = nil
local titleLabels: { TextLabel } = {}
local subtitleLabel: TextLabel? = nil
local multiplierBadge: Frame? = nil
local multiplierLabel: TextLabel? = nil
local cardContainer: Frame? = nil
local statCards: { { frame: Frame, value: TextLabel, label: TextLabel } } = {}
local returnButton: TextButton? = nil
local isVictory = false

-- // FUNCTIONS // --

--[[
    @summary  Format seconds as minutes and seconds.
    @param    seconds  number
    @returns  string
]]
local function formatTime(seconds: number): string
	local total = math.max(0, math.floor(seconds))
	return string.format("%02d:%02d", math.floor(total / 60), total % 60)
end

--[[
    @summary  Build a single stat card.
    @param    parent  Instance
    @param    index   number  -- for layout positioning
    @returns  table   -- { frame, value, label }
]]
local function buildStatCard(parent: Instance, index: number)
	local col = (index - 1) % CARDS_PER_ROW
	local row = math.floor((index - 1) / CARDS_PER_ROW)

	local totalWidth = CARDS_PER_ROW * CARD_WIDTH + (CARDS_PER_ROW - 1) * CARD_GAP
	local startX = -totalWidth / 2

	local card = Instance.new("Frame")
	card.Name = "StatCard" .. tostring(index)
	card.AnchorPoint = Vector2.new(0, 0.5)
	card.Size = UDim2.fromOffset(CARD_WIDTH, CARD_HEIGHT)
	card.Position = UDim2.fromScale(0.5, 0.5)
		+ UDim2.fromOffset(startX + col * (CARD_WIDTH + CARD_GAP), row * (CARD_HEIGHT + CARD_GAP))
	card.BackgroundColor3 = CARD_BG
	card.BackgroundTransparency = 1
	card.BorderSizePixel = 0
	card.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = card

	local stroke = Instance.new("UIStroke")
	stroke.Color = CARD_STROKE
	stroke.Thickness = 1
	stroke.Transparency = 1
	stroke.Parent = card

	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(28, 30, 36)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(14, 16, 20)),
	})
	gradient.Rotation = 90
	gradient.Parent = card

	local valueLabel = Instance.new("TextLabel")
	valueLabel.Name = "Value"
	valueLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	valueLabel.Position = UDim2.new(0.5, 0, 0.38, 0)
	valueLabel.Size = UDim2.new(1, -16, 0, 36)
	valueLabel.BackgroundTransparency = 1
	valueLabel.Font = Enum.Font.GothamBlack
	valueLabel.Text = "--"
	valueLabel.TextColor3 = CARD_VALUE_COLOR
	valueLabel.TextSize = 28
	valueLabel.TextTransparency = 1
	valueLabel.Parent = card
	local valueConstraint = Instance.new("UITextSizeConstraint")
	valueConstraint.MaxTextSize = 28
	valueConstraint.MinTextSize = 18
	valueConstraint.Parent = valueLabel

	local labelLabel = Instance.new("TextLabel")
	labelLabel.Name = "Label"
	labelLabel.AnchorPoint = Vector2.new(0.5, 0)
	labelLabel.Position = UDim2.new(0.5, 0, 0.72, 0)
	labelLabel.Size = UDim2.new(1, -16, 0, 18)
	labelLabel.BackgroundTransparency = 1
	labelLabel.Font = Enum.Font.GothamBold
	labelLabel.Text = ""
	labelLabel.TextColor3 = CARD_LABEL_COLOR
	labelLabel.TextSize = 13
	labelLabel.TextTransparency = 1
	labelLabel.Parent = card

	return { frame = card, value = valueLabel, label = labelLabel, stroke = stroke }
end

--[[
    @summary  Build the ending overlay once.
]]
local function buildUi()
	if gui then
		return
	end
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "EndingGui"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true
	screenGui.DisplayOrder = 100
	screenGui.Enabled = false
	screenGui.Parent = playerGui
	gui = screenGui

	-- === Backdrop with vignette ===
	local backdropFrame = Instance.new("Frame")
	backdropFrame.Name = "Backdrop"
	backdropFrame.Size = UDim2.fromScale(1, 1)
	backdropFrame.BackgroundColor3 = BACKDROP_COLOR
	backdropFrame.BackgroundTransparency = 1
	backdropFrame.BorderSizePixel = 0
	backdropFrame.Parent = screenGui
	backdrop = backdropFrame

	local vignette = Instance.new("UIGradient")
	vignette.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(0, 0, 0)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(12, 14, 18)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(0, 0, 0)),
	})
	vignette.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.0),
		NumberSequenceKeypoint.new(0.5, 0.08),
		NumberSequenceKeypoint.new(1, 0.0),
	})
	vignette.Parent = backdropFrame

	-- === Centered content container ===
	local container = Instance.new("Frame")
	container.Name = "Content"
	container.AnchorPoint = Vector2.new(0.5, 0.5)
	container.Position = UDim2.fromScale(0.5, 0.5)
	container.Size = UDim2.fromOffset(440, 0)
	container.AutomaticSize = Enum.AutomaticSize.Y
	container.BackgroundTransparency = 1
	container.Parent = backdropFrame

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 0)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Parent = container

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 0)
	padding.PaddingBottom = UDim.new(0, 0)
	padding.PaddingLeft = UDim.new(0, 0)
	padding.PaddingRight = UDim.new(0, 0)
	padding.Parent = container

	-- === Title (two lines for dramatic effect) ===
	local titleLine1 = Instance.new("TextLabel")
	titleLine1.Name = "TitleLine1"
	titleLine1.Size = UDim2.new(1, 0, 0, 56)
	titleLine1.BackgroundTransparency = 1
	titleLine1.Font = Enum.Font.GothamBlack
	titleLine1.Text = ""
	titleLine1.TextColor3 = DEFEAT_COLOR
	titleLine1.TextTransparency = 1
	titleLine1.TextSize = 44
	titleLine1.LayoutOrder = 1
	titleLine1.Parent = container
	local tc1 = Instance.new("UITextSizeConstraint")
	tc1.MaxTextSize = 44
	tc1.MinTextSize = 24
	tc1.Parent = titleLine1
	titleLine1.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	titleLine1.TextStrokeTransparency = 0.4

	local titleLine2 = Instance.new("TextLabel")
	titleLine2.Name = "TitleLine2"
	titleLine2.Size = UDim2.new(1, 0, 0, 56)
	titleLine2.BackgroundTransparency = 1
	titleLine2.Font = Enum.Font.GothamBlack
	titleLine2.Text = ""
	titleLine2.TextColor3 = DEFEAT_COLOR
	titleLine2.TextTransparency = 1
	titleLine2.TextSize = 44
	titleLine2.LayoutOrder = 2
	titleLine2.Parent = container
	local tc2 = Instance.new("UITextSizeConstraint")
	tc2.MaxTextSize = 44
	tc2.MinTextSize = 24
	tc2.Parent = titleLine2
	titleLine2.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	titleLine2.TextStrokeTransparency = 0.4

	titleLabels = { titleLine1, titleLine2 }

	-- === Subtitle ===
	local subtitle = Instance.new("TextLabel")
	subtitle.Name = "Subtitle"
	subtitle.Size = UDim2.new(1, 0, 0, 24)
	subtitle.BackgroundTransparency = 1
	subtitle.Font = Enum.Font.Gotham
	subtitle.Text = ""
	subtitle.TextColor3 = SUBTITLE_COLOR
	subtitle.TextTransparency = 1
	subtitle.TextSize = 17
	subtitle.LayoutOrder = 3
	subtitle.Parent = container
	subtitleLabel = subtitle

	-- === Multiplier badge ===
	local badge = Instance.new("Frame")
	badge.Name = "MultiplierBadge"
	badge.Size = UDim2.fromOffset(140, 26)
	badge.BackgroundColor3 = Color3.fromRGB(40, 36, 24)
	badge.BackgroundTransparency = 1
	badge.BorderSizePixel = 0
	badge.LayoutOrder = 4
	badge.Parent = container
	multiplierBadge = badge

	local badgeCorner = Instance.new("UICorner")
	badgeCorner.CornerRadius = UDim.new(0, 13)
	badgeCorner.Parent = badge

	local badgeStroke = Instance.new("UIStroke")
	badgeStroke.Color = MULTIPLIER_COLOR
	badgeStroke.Thickness = 1
	badgeStroke.Transparency = 1
	badgeStroke.Parent = badge

	local badgeLabel = Instance.new("TextLabel")
	badgeLabel.Name = "Text"
	badgeLabel.Size = UDim2.fromScale(1, 1)
	badgeLabel.BackgroundTransparency = 1
	badgeLabel.Font = Enum.Font.GothamBold
	badgeLabel.Text = ""
	badgeLabel.TextColor3 = MULTIPLIER_COLOR
	badgeLabel.TextTransparency = 1
	badgeLabel.TextSize = 14
	badgeLabel.Parent = badge
	multiplierLabel = badgeLabel

	-- === Stat cards container ===
	local cardsFrame = Instance.new("Frame")
	cardsFrame.Name = "StatCards"
	cardsFrame.Size = UDim2.new(1, 0, 0, 0)
	cardsFrame.AutomaticSize = Enum.AutomaticSize.Y
	cardsFrame.BackgroundTransparency = 1
	cardsFrame.LayoutOrder = 5
	cardsFrame.Parent = container
	cardContainer = cardsFrame

	-- Build 8 stat cards
	for i = 1, 8 do
		local card = buildStatCard(cardsFrame, i)
		table.insert(statCards, card)
	end

	-- === Return button ===
	local button = Instance.new("TextButton")
	button.Name = "ReturnButton"
	button.Size = UDim2.fromOffset(220, 44)
	button.BackgroundColor3 = BUTTON_BG
	button.BackgroundTransparency = 1
	button.BorderSizePixel = 0
	button.Font = Enum.Font.GothamBold
	button.Text = "Return to Lobby"
	button.TextColor3 = BUTTON_TEXT
	button.TextTransparency = 1
	button.TextSize = 16
	button.LayoutOrder = 6
	button.Parent = container
	returnButton = button

	local btnCorner = Instance.new("UICorner")
	btnCorner.CornerRadius = UDim.new(0, 22)
	btnCorner.Parent = button

	local btnStroke = Instance.new("UIStroke")
	btnStroke.Color = Color3.fromRGB(70, 72, 80)
	btnStroke.Thickness = 1
	btnStroke.Transparency = 1
	btnStroke.Parent = button

	-- Hover effect
	button.MouseEnter:Connect(function()
		TweenService:Create(button, TweenInfo.new(0.15, Enum.EasingStyle.Quad), {
			BackgroundColor3 = BUTTON_BG_HOVER,
		}):Play()
	end)
	button.MouseLeave:Connect(function()
		TweenService:Create(button, TweenInfo.new(0.15, Enum.EasingStyle.Quad), {
			BackgroundColor3 = BUTTON_BG,
		}):Play()
	end)
	button.Activated:Connect(function()
		if endingService then
			endingService:RequestEarlyReturn()
		end
	end)
end

--[[
    @summary  Reset all UI elements to their hidden state.
]]
local function resetUi()
	if backdrop then
		backdrop.BackgroundTransparency = 1
	end
	for _, tl in ipairs(titleLabels) do
		tl.TextTransparency = 1
		tl.Position = UDim2.new(0, 0, 0, -20)
	end
	if subtitleLabel then
		subtitleLabel.TextTransparency = 1
	end
	if multiplierBadge then
		multiplierBadge.BackgroundTransparency = 1
		local stroke = multiplierBadge:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Transparency = 1
		end
	end
	if multiplierLabel then
		multiplierLabel.TextTransparency = 1
	end
	for _, card in ipairs(statCards) do
		card.frame.BackgroundTransparency = 1
		card.value.TextTransparency = 1
		card.label.TextTransparency = 1
		if card.stroke then
			card.stroke.Transparency = 1
		end
		card.frame.Position = UDim2.fromScale(0.5, 0.5)
			+ UDim2.fromOffset(
				((tonumber(string.sub(card.frame.Name, 8)) or 1) - 1) % CARDS_PER_ROW * (CARD_WIDTH + CARD_GAP) - (CARDS_PER_ROW * CARD_WIDTH + (CARDS_PER_ROW - 1) * CARD_GAP) / 2,
				math.floor(((tonumber(string.sub(card.frame.Name, 8)) or 1) - 1) / CARDS_PER_ROW) * (CARD_HEIGHT + CARD_GAP) + 15
			)
	end
	if returnButton then
		returnButton.BackgroundTransparency = 1
		returnButton.TextTransparency = 1
		local stroke = returnButton:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Transparency = 1
		end
	end
end

--[[
    @summary  Show the shared victory or defeat title transition.
    @param    payload  table
]]
local function showEnding(payload)
	buildUi()
	if not gui or not backdrop then
		return
	end
	isVictory = payload.victory == true
	gui.Enabled = true
	resetUi()

	-- Set title text + color
	local titleColor = if isVictory then VICTORY_COLOR else DEFEAT_COLOR
	if isVictory then
		titleLabels[1].Text = "DAY 67"
		titleLabels[2].Text = "SURVIVED"
	else
		titleLabels[1].Text = "THE FOREST"
		titleLabels[2].Text = "CLAIMED THE TEAM"
	end
	for _, tl in ipairs(titleLabels) do
		tl.TextColor3 = titleColor
	end

	-- Set subtitle
	if subtitleLabel then
		subtitleLabel.Text = string.format("Reached Day %d  ·  %s",
			payload.displayedDay or 1,
			formatTime(payload.elapsedSeconds or 0))
	end

	-- Set multiplier badge
	if multiplierLabel and payload.multiplier and payload.multiplier > 1 then
		multiplierLabel.Text = string.format("✦  %dx Multiplier", payload.multiplier)
		multiplierBadge.Visible = true
	else
		multiplierBadge.Visible = false
	end

	-- Set button text
	if returnButton then
		returnButton.Text = if isVictory then "Continue" else "Return to Lobby"
	end

	-- === Animation choreography ===

	-- 1. Backdrop fade in
	TweenService:Create(backdrop, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		BackgroundTransparency = 0.08,
	}):Play()

	-- 2. Title lines fade + slide down (staggered)
	task.delay(0.3, function()
		if not gui or not gui.Enabled then return end
		TweenService:Create(titleLabels[1], TweenInfo.new(0.7, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
			TextTransparency = 0,
			Position = UDim2.new(0, 0, 0, 0),
		}):Play()
	end)
	task.delay(0.45, function()
		if not gui or not gui.Enabled then return end
		TweenService:Create(titleLabels[2], TweenInfo.new(0.7, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
			TextTransparency = 0,
			Position = UDim2.new(0, 0, 0, 0),
		}):Play()
	end)

	-- 3. Subtitle fade in
	task.delay(0.8, function()
		if not gui or not gui.Enabled then return end
		if subtitleLabel then
			TweenService:Create(subtitleLabel, TweenInfo.new(0.5, Enum.EasingStyle.Quad), {
				TextTransparency = 0,
			}):Play()
		end
	end)

	-- 4. Multiplier badge fade in
	if payload.multiplier and payload.multiplier > 1 then
		task.delay(0.95, function()
			if not gui or not gui.Enabled then return end
			if multiplierBadge then
				TweenService:Create(multiplierBadge, TweenInfo.new(0.4, Enum.EasingStyle.Quad), {
					BackgroundTransparency = 0.1,
				}):Play()
				local stroke = multiplierBadge:FindFirstChildOfClass("UIStroke")
				if stroke then
					TweenService:Create(stroke, TweenInfo.new(0.4), { Transparency = 0.3 }):Play()
				end
			end
			if multiplierLabel then
				TweenService:Create(multiplierLabel, TweenInfo.new(0.4), { TextTransparency = 0 }):Play()
			end
		end)
	end
end

--[[
    @summary  Populate the personal result details with staggered stat cards.
    @param    result  table
]]
local function showResults(result)
	local bedCount = 0
	local childCount = 0
	for sourceName in pairs(result.multiplierSources or {}) do
		if string.sub(sourceName, 1, 4) == "Bed:" then
			bedCount += 1
		elseif string.sub(sourceName, 1, 6) == "Child:" then
			childCount += 1
		end
	end

	-- Define the 8 stats
	local stats = {
		{ value = string.format("%d / %d", result.displayedDay or 1, result.goalDay or 67), label = "Days Survived" },
		{ value = formatTime(result.elapsedSeconds or 0), label = "Run Time" },
		{ value = string.format("%d / 4", result.childrenRescued or 0), label = "Children Rescued" },
		{ value = tostring(result.structuresBuilt or 0), label = "Structures Built" },
		{ value = tostring(result.treesChopped or 0), label = "Trees Chopped" },
		{ value = tostring(result.wolvesKilled or 0), label = "Wolves Defeated" },
		{ value = tostring(result.cultistsKilled or 0), label = "Cultists Defeated" },
		{ value = string.format("%d / %d", result.revives or 0, result.downs or 0), label = "Revives / Downs" },
	}

	-- Populate and animate each card with staggered delay
	for i, stat in ipairs(stats) do
		local card = statCards[i]
		if card then
			card.value.Text = stat.value
			card.label.Text = stat.label

			-- Calculate resting position (same as buildStatCard but without +15 offset)
			local col = (i - 1) % CARDS_PER_ROW
			local row = math.floor((i - 1) / CARDS_PER_ROW)
			local totalWidth = CARDS_PER_ROW * CARD_WIDTH + (CARDS_PER_ROW - 1) * CARD_GAP
			local startX = -totalWidth / 2
			local restPos = UDim2.fromScale(0.5, 0.5)
				+ UDim2.fromOffset(startX + col * (CARD_WIDTH + CARD_GAP), row * (CARD_HEIGHT + CARD_GAP))

			-- Start position: 15px below resting
			card.frame.Position = restPos + UDim2.fromOffset(0, 15)

			-- Stagger: each card starts 80ms after previous, starting at 1.1s
			task.delay(1.1 + (i - 1) * 0.08, function()
				if not gui or not gui.Enabled then return end
				TweenService:Create(card.frame, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
					BackgroundTransparency = 0,
					Position = restPos,
				}):Play()
				TweenService:Create(card.value, TweenInfo.new(0.4, Enum.EasingStyle.Quad), {
					TextTransparency = 0,
				}):Play()
				TweenService:Create(card.label, TweenInfo.new(0.4, Enum.EasingStyle.Quad), {
					TextTransparency = 0,
				}):Play()
				if card.stroke then
					TweenService:Create(card.stroke, TweenInfo.new(0.4), { Transparency = 0.2 }):Play()
				end
			end)
		end
	end

	-- 5. Return button fades in after all cards
	task.delay(1.1 + #stats * 0.08 + 0.3, function()
		if not gui or not gui.Enabled then return end
		if returnButton then
			TweenService:Create(returnButton, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				BackgroundTransparency = 0,
				TextTransparency = 0,
			}):Play()
			local stroke = returnButton:FindFirstChildOfClass("UIStroke")
			if stroke then
				TweenService:Create(stroke, TweenInfo.new(0.5), { Transparency = 0.1 }):Play()
			end
		end
	end)
end

-- // INITIALIZATION // --

function EndingController:KnitStart()
	endingService = Knit.GetService("EndingService")
	runStateService = Knit.GetService("RunStateService")
	buildUi()
	endingService.EndingStarted:Connect(function(payload)
		if typeof(payload) == "table" then
			showEnding(payload)
		end
	end)
	endingService.ResultsReady:Connect(function(result)
		if typeof(result) == "table" then
			showResults(result)
		end
	end)
	runStateService.RunPhaseChanged:Connect(function(payload)
		if typeof(payload) == "table" and payload.phase == "Lobby" and gui then
			-- Fade out before disabling
			if backdrop then
				TweenService:Create(backdrop, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
					BackgroundTransparency = 1,
				}):Play()
			end
			task.delay(0.5, function()
				if gui then
					gui.Enabled = false
				end
			end)
		end
	end)
end

return EndingController
