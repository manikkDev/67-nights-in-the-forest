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
local DEFEAT_COLOR = Color3.fromRGB(210, 55, 50)
local DEFEAT_SUBTITLE = Color3.fromRGB(200, 140, 135)
local SUBTITLE_COLOR = Color3.fromRGB(170, 170, 175)
local CARD_BG = Color3.fromRGB(18, 20, 24)
local CARD_STROKE = Color3.fromRGB(50, 52, 58)
local CARD_VALUE_COLOR = Color3.fromRGB(240, 240, 235)
local CARD_LABEL_COLOR = Color3.fromRGB(140, 142, 150)
local BUTTON_BG = Color3.fromRGB(30, 32, 38)
local BUTTON_BG_HOVER = Color3.fromRGB(42, 44, 52)
local BUTTON_TEXT = Color3.fromRGB(230, 230, 235)
local MULTIPLIER_COLOR = Color3.fromRGB(240, 200, 110)
local DEFEAT_MEMBER_ALIVE = Color3.fromRGB(80, 200, 100)
local DEFEAT_MEMBER_DOWNED = Color3.fromRGB(210, 160, 50)
local DEFEAT_MEMBER_ELIM = Color3.fromRGB(180, 65, 60)

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
local defeatPanel: Frame? = nil
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
    @summary  Build support functions for the defeat team-status panel.
]]
local function buildDefeatPanel(parent: Frame): Frame
	local panel = Instance.new("Frame")
	panel.Name = "DefeatPanel"
	panel.Size = UDim2.new(1, 0, 0, 0)
	panel.AutomaticSize = Enum.AutomaticSize.Y
	panel.BackgroundTransparency = 1
	panel.LayoutOrder = 5
	panel.Parent = parent
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Parent = panel
	return panel
end

local function addMemberRow(parent: Frame, displayName: string, stateLabel: string, stateColor: Color3, layoutOrder: number)
	local row = Instance.new("Frame")
	row.Name = "MemberRow"
	row.Size = UDim2.new(1, -20, 0, 42)
	row.BackgroundColor3 = Color3.fromRGB(22, 24, 28)
	row.BackgroundTransparency = 0.25
	row.BorderSizePixel = 0
	row.LayoutOrder = layoutOrder
	row.Parent = parent
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 9)
	corner.Parent = row
	local dot = Instance.new("Frame")
	dot.AnchorPoint = Vector2.new(0, 0.5)
	dot.Position = UDim2.fromOffset(12, 21)
	dot.Size = UDim2.fromOffset(10, 10)
	dot.BackgroundColor3 = stateColor
	dot.BorderSizePixel = 0
	dot.Parent = row
	local dotCorner = Instance.new("UICorner")
	dotCorner.CornerRadius = UDim.new(1, 0)
	dotCorner.Parent = dot
	local nameLabel = Instance.new("TextLabel")
	nameLabel.AnchorPoint = Vector2.new(0, 0.5)
	nameLabel.Position = UDim2.fromOffset(30, 21)
	nameLabel.Size = UDim2.new(0.58, -30, 0, 28)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.Text = displayName
	nameLabel.TextColor3 = Color3.fromRGB(230, 230, 228)
	nameLabel.TextSize = 15
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
	nameLabel.Parent = row
	local stateText = Instance.new("TextLabel")
	stateText.AnchorPoint = Vector2.new(1, 0.5)
	stateText.Position = UDim2.new(1, -14, 0.5, 0)
	stateText.Size = UDim2.fromOffset(110, 24)
	stateText.BackgroundTransparency = 1
	stateText.Font = Enum.Font.GothamBold
	stateText.Text = stateLabel
	stateText.TextColor3 = stateColor
	stateText.TextSize = 13
	stateText.TextXAlignment = Enum.TextXAlignment.Right
	stateText.Parent = row
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

	-- === Full-screen backdrop (color set per victory/defeat) ===
	local backdropFrame = Instance.new("Frame")
	backdropFrame.Name = "Backdrop"
	backdropFrame.Size = UDim2.fromScale(1, 1)
	backdropFrame.BackgroundColor3 = BACKDROP_COLOR
	backdropFrame.BackgroundTransparency = 1
	backdropFrame.BorderSizePixel = 0
	backdropFrame.Parent = screenGui
	backdrop = backdropFrame

	-- Vignette overlay
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

	-- === Scrollable centered content (prevents overflow on small screens) ===
	local scrollFrame = Instance.new("ScrollingFrame")
	scrollFrame.Name = "ContentScroll"
	scrollFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	scrollFrame.Position = UDim2.fromScale(0.5, 0.5)
	scrollFrame.Size = UDim2.new(0.92, 0, 0.90, 0)
	scrollFrame.BackgroundTransparency = 1
	scrollFrame.BorderSizePixel = 0
	scrollFrame.ScrollBarThickness = 0
	scrollFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
	scrollFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scrollFrame.ClipsDescendants = true
	scrollFrame.Parent = backdropFrame
	local scrollConstraint = Instance.new("UISizeConstraint")
	scrollConstraint.MaxSize = Vector2.new(480, math.huge)
	scrollConstraint.Parent = scrollFrame

	local container = Instance.new("Frame")
	container.Name = "Content"
	container.AnchorPoint = Vector2.new(0.5, 0)
	container.Position = UDim2.fromScale(0.5, 0)
	container.Size = UDim2.new(1, 0, 0, 0)
	container.AutomaticSize = Enum.AutomaticSize.Y
	container.BackgroundTransparency = 1
	container.Parent = scrollFrame

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 4)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Parent = container

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 32)
	padding.PaddingBottom = UDim.new(0, 20)
	padding.Parent = container

	-- === Title line 1 ===
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
	titleLine1.TextStrokeTransparency = 0.35

	-- === Title line 2 ===
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
	titleLine2.TextStrokeTransparency = 0.35

	titleLabels = { titleLine1, titleLine2 }

	-- === Subtitle (day reached · run time) ===
	local subtitle = Instance.new("TextLabel")
	subtitle.Name = "Subtitle"
	subtitle.Size = UDim2.new(1, 0, 0, 28)
	subtitle.BackgroundTransparency = 1
	subtitle.Font = Enum.Font.Gotham
	subtitle.Text = ""
	subtitle.TextColor3 = SUBTITLE_COLOR
	subtitle.TextTransparency = 1
	subtitle.TextSize = 17
	subtitle.LayoutOrder = 3
	subtitle.Parent = container
	subtitleLabel = subtitle

	-- === Multiplier badge (victory only) ===
	local badge = Instance.new("Frame")
	badge.Name = "MultiplierBadge"
	badge.Size = UDim2.fromOffset(144, 28)
	badge.BackgroundColor3 = Color3.fromRGB(40, 36, 24)
	badge.BackgroundTransparency = 1
	badge.BorderSizePixel = 0
	badge.LayoutOrder = 4
	badge.Parent = container
	multiplierBadge = badge
	local badgeCorner = Instance.new("UICorner")
	badgeCorner.CornerRadius = UDim.new(0, 14)
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

	-- === Defeat team-status panel ===
	local dp = buildDefeatPanel(container)
	defeatPanel = dp

	-- === Stat cards container (victory only) ===
	local cardsFrame = Instance.new("Frame")
	cardsFrame.Name = "StatCards"
	cardsFrame.Size = UDim2.new(1, 0, 0, 0)
	cardsFrame.AutomaticSize = Enum.AutomaticSize.Y
	cardsFrame.BackgroundTransparency = 1
	cardsFrame.LayoutOrder = 5
	cardsFrame.Visible = false
	cardsFrame.Parent = container
	cardContainer = cardsFrame
	for i = 1, 8 do
		local card = buildStatCard(cardsFrame, i)
		table.insert(statCards, card)
	end

	-- === Return / Continue button ===
	local spacer = Instance.new("Frame")
	spacer.Name = "ButtonSpacer"
	spacer.Size = UDim2.new(1, 0, 0, 10)
	spacer.BackgroundTransparency = 1
	spacer.LayoutOrder = 6
	spacer.Parent = container

	local button = Instance.new("TextButton")
	button.Name = "ReturnButton"
	button.Size = UDim2.fromOffset(240, 48)
	button.BackgroundColor3 = BUTTON_BG
	button.BackgroundTransparency = 1
	button.BorderSizePixel = 0
	button.Font = Enum.Font.GothamBold
	button.Text = "Return to Lobby"
	button.TextColor3 = BUTTON_TEXT
	button.TextTransparency = 1
	button.TextSize = 16
	button.LayoutOrder = 7
	button.Parent = container
	returnButton = button
	local btnCorner = Instance.new("UICorner")
	btnCorner.CornerRadius = UDim.new(0, 24)
	btnCorner.Parent = button
	local btnStroke = Instance.new("UIStroke")
	btnStroke.Color = Color3.fromRGB(70, 72, 80)
	btnStroke.Thickness = 1
	btnStroke.Transparency = 1
	btnStroke.Parent = button
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
			endingService.RequestEarlyReturn:Fire()
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
		multiplierBadge.Visible = false
		local stroke = multiplierBadge:FindFirstChildOfClass("UIStroke")
		if stroke then stroke.Transparency = 1 end
	end
	if multiplierLabel then
		multiplierLabel.TextTransparency = 1
	end
	for _, card in ipairs(statCards) do
		card.frame.BackgroundTransparency = 1
		card.value.TextTransparency = 1
		card.label.TextTransparency = 1
		if card.stroke then card.stroke.Transparency = 1 end
		local col = (tonumber(string.sub(card.frame.Name, 9)) or 1) - 1
		local cardIndex = col + 1
		local c = (cardIndex - 1) % CARDS_PER_ROW
		local r = math.floor((cardIndex - 1) / CARDS_PER_ROW)
		local totalWidth = CARDS_PER_ROW * CARD_WIDTH + (CARDS_PER_ROW - 1) * CARD_GAP
		card.frame.Position = UDim2.fromScale(0.5, 0.5)
			+ UDim2.fromOffset(
				-totalWidth / 2 + c * (CARD_WIDTH + CARD_GAP),
				r * (CARD_HEIGHT + CARD_GAP) + 15
			)
	end
	if returnButton then
		returnButton.BackgroundTransparency = 1
		returnButton.TextTransparency = 1
		local stroke = returnButton:FindFirstChildOfClass("UIStroke")
		if stroke then stroke.Transparency = 1 end
	end
	-- Clear defeat rows
	if defeatPanel then
		for _, child in ipairs(defeatPanel:GetChildren()) do
			if child:IsA("Frame") then child:Destroy() end
		end
		defeatPanel.Visible = false
	end
	if cardContainer then cardContainer.Visible = false end
end

--[[
    @summary  Show the victory or defeat title transition.
    @param    payload  table
]]
local function showEnding(payload)
	buildUi()
	if not gui or not backdrop then return end
	isVictory = payload.victory == true
	gui.Enabled = true
	resetUi()

	-- Backdrop tint differs per outcome
	backdrop.BackgroundColor3 = if isVictory then BACKDROP_COLOR else Color3.fromRGB(12, 4, 4)

	-- Title text and color
	local titleColor = if isVictory then VICTORY_COLOR else DEFEAT_COLOR
	if isVictory then
		titleLabels[1].Text = "DAY 67"
		titleLabels[2].Text = "SURVIVED"
	else
		titleLabels[1].Text = "YOUR TEAM"
		titleLabels[2].Text = "HAS FALLEN"
	end
	for _, tl in ipairs(titleLabels) do tl.TextColor3 = titleColor end

	-- Subtitle
	if subtitleLabel then
		subtitleLabel.TextColor3 = if isVictory then SUBTITLE_COLOR else DEFEAT_SUBTITLE
		subtitleLabel.Text = string.format(
			if isVictory then "Survived to Day %d  \xC2\xB7  %s" else "Fell on Day %d  \xC2\xB7  Lasted %s",
			payload.displayedDay or 1,
			formatTime(payload.elapsedSeconds or 0)
		)
	end

	-- Multiplier badge — victory only
	if isVictory and payload.multiplier and payload.multiplier > 1 then
		if multiplierLabel then
			multiplierLabel.Text = string.format("\xE2\x9C\xA6  %dx Multiplier", payload.multiplier)
		end
		if multiplierBadge then multiplierBadge.Visible = true end
	else
		if multiplierBadge then multiplierBadge.Visible = false end
	end

	-- Reveal correct section
	if cardContainer then cardContainer.Visible = isVictory end
	if defeatPanel then defeatPanel.Visible = not isVictory end

	-- Button text
	if returnButton then
		returnButton.Text = if isVictory then "Continue" else "Return to Lobby"
	end

	-- === Animation sequence ===
	TweenService:Create(backdrop, TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		BackgroundTransparency = 0.06,
	}):Play()
	task.delay(0.3, function()
		if not gui or not gui.Enabled then return end
		TweenService:Create(titleLabels[1], TweenInfo.new(0.7, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
			TextTransparency = 0,
			Position = UDim2.new(0, 0, 0, 0),
		}):Play()
	end)
	task.delay(0.48, function()
		if not gui or not gui.Enabled then return end
		TweenService:Create(titleLabels[2], TweenInfo.new(0.7, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
			TextTransparency = 0,
			Position = UDim2.new(0, 0, 0, 0),
		}):Play()
	end)
	task.delay(0.85, function()
		if not gui or not gui.Enabled then return end
		if subtitleLabel then
			TweenService:Create(subtitleLabel, TweenInfo.new(0.5, Enum.EasingStyle.Quad), {
				TextTransparency = 0,
			}):Play()
		end
	end)
	if isVictory and payload.multiplier and payload.multiplier > 1 then
		task.delay(1.0, function()
			if not gui or not gui.Enabled then return end
			if multiplierBadge then
				TweenService:Create(multiplierBadge, TweenInfo.new(0.4, Enum.EasingStyle.Quad), {
					BackgroundTransparency = 0.1,
				}):Play()
				local stroke = multiplierBadge:FindFirstChildOfClass("UIStroke")
				if stroke then TweenService:Create(stroke, TweenInfo.new(0.4), { Transparency = 0.3 }):Play() end
			end
			if multiplierLabel then
				TweenService:Create(multiplierLabel, TweenInfo.new(0.4), { TextTransparency = 0 }):Play()
			end
		end)
	end
end

--[[
    @summary  Show team-member status rows for the defeat screen.
    @param    result  table
]]
local function showDefeatTeamStatus(result)
	if isVictory or not defeatPanel then return end
	local memberStates = result.memberStates or {}
	local order = 0
	for userId, info in pairs(memberStates) do
		order += 1
		local state = (typeof(info) == "table" and info.state) or tostring(info)
		local name = (typeof(info) == "table" and (info.displayName or info.name)) or tostring(userId)
		local stateLabel, stateColor
		if state == "Alive" then
			stateLabel, stateColor = "SURVIVED", DEFEAT_MEMBER_ALIVE
		elseif state == "Downed" then
			stateLabel, stateColor = "DOWNED", DEFEAT_MEMBER_DOWNED
		else
			stateLabel, stateColor = "FALLEN", DEFEAT_MEMBER_ELIM
		end
		addMemberRow(defeatPanel, name, stateLabel, stateColor, order)
	end

	-- Animate rows + button
	local rows = {}
	for _, child in ipairs(defeatPanel:GetChildren()) do
		if child:IsA("Frame") then table.insert(rows, child) end
	end
	for i, row in ipairs(rows) do
		row.BackgroundTransparency = 1
		for _, desc in ipairs(row:GetDescendants()) do
			if desc:IsA("TextLabel") then desc.TextTransparency = 1 end
			if desc:IsA("Frame") then desc.BackgroundTransparency = 1 end
		end
		task.delay(1.1 + (i - 1) * 0.12, function()
			if not gui or not gui.Enabled then return end
			TweenService:Create(row, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				BackgroundTransparency = 0.25,
			}):Play()
			for _, desc in ipairs(row:GetDescendants()) do
				if desc:IsA("TextLabel") then
					TweenService:Create(desc, TweenInfo.new(0.4), { TextTransparency = 0 }):Play()
				elseif desc:IsA("Frame") then
					TweenService:Create(desc, TweenInfo.new(0.4), { BackgroundTransparency = 0 }):Play()
				end
			end
		end)
	end
	task.delay(1.1 + #rows * 0.12 + 0.3, function()
		if not gui or not gui.Enabled then return end
		if returnButton then
			TweenService:Create(returnButton, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				BackgroundTransparency = 0,
				TextTransparency = 0,
			}):Play()
			local stroke = returnButton:FindFirstChildOfClass("UIStroke")
			if stroke then TweenService:Create(stroke, TweenInfo.new(0.5), { Transparency = 0.1 }):Play() end
		end
	end)
end

--[[
    @summary  Populate victory stat cards with staggered animation.
    @param    result  table
]]
local function showResults(result)
	if not isVictory then
		-- For defeat, the result payload might still carry memberStates; show them
		showDefeatTeamStatus(result)
		return
	end
	if cardContainer then cardContainer.Visible = true end
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
	for i, stat in ipairs(stats) do
		local card = statCards[i]
		if card then
			card.value.Text = stat.value
			card.label.Text = stat.label
			local col = (i - 1) % CARDS_PER_ROW
			local row = math.floor((i - 1) / CARDS_PER_ROW)
			local totalWidth = CARDS_PER_ROW * CARD_WIDTH + (CARDS_PER_ROW - 1) * CARD_GAP
			local startX = -totalWidth / 2
			local restPos = UDim2.fromScale(0.5, 0.5)
				+ UDim2.fromOffset(startX + col * (CARD_WIDTH + CARD_GAP), row * (CARD_HEIGHT + CARD_GAP))
			card.frame.Position = restPos + UDim2.fromOffset(0, 15)
			task.delay(1.1 + (i - 1) * 0.08, function()
				if not gui or not gui.Enabled then return end
				TweenService:Create(card.frame, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
					BackgroundTransparency = 0,
					Position = restPos,
				}):Play()
				TweenService:Create(card.value, TweenInfo.new(0.4), { TextTransparency = 0 }):Play()
				TweenService:Create(card.label, TweenInfo.new(0.4), { TextTransparency = 0 }):Play()
				if card.stroke then
					TweenService:Create(card.stroke, TweenInfo.new(0.4), { Transparency = 0.2 }):Play()
				end
			end)
		end
	end
	task.delay(1.1 + #stats * 0.08 + 0.3, function()
		if not gui or not gui.Enabled then return end
		if returnButton then
			TweenService:Create(returnButton, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				BackgroundTransparency = 0,
				TextTransparency = 0,
			}):Play()
			local stroke = returnButton:FindFirstChildOfClass("UIStroke")
			if stroke then TweenService:Create(stroke, TweenInfo.new(0.5), { Transparency = 0.1 }):Play() end
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
			if backdrop then
				TweenService:Create(backdrop, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
					BackgroundTransparency = 1,
				}):Play()
			end
			task.delay(0.5, function()
				if gui then gui.Enabled = false end
			end)
		end
	end)
end

return EndingController
