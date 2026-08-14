--[[
    @file    IntroController.luau
    @author  manik
    @date    2025

    @summary
    Client presenter for the Create Party lobby and match intro.

    @description
    Shows a "Create Party" panel on teleporter touch. Only party size 1
    is enabled. Clicking Create starts a 5-second countdown, then fades
    to the story text, teleports the player, shows Day 1 on black, and
    slowly reveals the base map before gameplay begins.
]]

-- // VARIABLES // --

-- | Services | --
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

-- | Modules | --
local Knit = require(ReplicatedStorage.Packages.Knit)
local Janitor = require(ReplicatedStorage.Packages.Janitor)
local IntroAssets = require(ReplicatedStorage.Shared.IntroAssets)
local Constants = require(ReplicatedStorage.Shared.Constants)

-- | Objects | --
local IntroController = Knit.CreateController({
	Name = "IntroController",
})

-- | Configuration | --
local PANEL_FADE = 0.3
local STORY_FADE = Constants.MATCH_STORY_FADE_SECONDS or 1.2
local REVEAL_SECONDS = Constants.MATCH_REVEAL_SECONDS or 2.5

local PANEL = IntroAssets.PanelBackdrop or Color3.fromRGB(25, 25, 25)
local PANEL_ALPHA = IntroAssets.PanelBackgroundTransparency or 0.25
local CREAM = IntroAssets.TitleColor or Color3.fromRGB(232, 220, 190)
local HANDWRITTEN = IntroAssets.TitleHandwritten or CREAM
local BODY = IntroAssets.BodyText or CREAM
local SIZE_BTN = IntroAssets.SizeButton or Color3.fromRGB(160, 160, 160)
local SIZE_DISABLED = IntroAssets.SizeButtonDisabled or Color3.fromRGB(90, 90, 90)
local SIZE_SELECTED = IntroAssets.SizeButtonSelected or Color3.fromRGB(255, 210, 50)
local CREATE = IntroAssets.CreateButton or Color3.fromRGB(95, 190, 70)
local CLOSE = IntroAssets.CloseButton or Color3.fromRGB(220, 60, 60)
local CUSTOMIZE = IntroAssets.CustomizeButton or Color3.fromRGB(80, 80, 80)
local STORY = IntroAssets.StoryText or Color3.fromRGB(170, 90, 90)

local TITLE_IN = 0.5
local TITLE_OUT = 0.4
local STORY_BACK = IntroAssets.StoryScreenBackdrop or Color3.fromRGB(10, 10, 10)
local STORY_HEADER = IntroAssets.StoryHeaderColor or Color3.fromRGB(220, 60, 60)
local STORY_PANEL = IntroAssets.StoryPanelBackdrop or Color3.fromRGB(30, 30, 30)
local STORY_CAPTION = IntroAssets.StoryPanelCaption or Color3.fromRGB(230, 220, 200)
local STORY_PLACEHOLDER = IntroAssets.StoryPanelPlaceholder or Color3.fromRGB(55, 55, 55)
local PLAY = IntroAssets.PlayButtonColor or Color3.fromRGB(95, 190, 70)

-- | State Management | --
local player = Players.LocalPlayer
local janitor = Janitor.new()
local waitingJanitor = Janitor.new()
local screenGui: ScreenGui? = nil
local titleScreen: Frame? = nil
local createPartyFrame: Frame? = nil
local storyFrame: Frame? = nil
local dayFrame: Frame? = nil
local countdownLabel: TextLabel? = nil
local createButton: TextButton? = nil
local sizeButtons: { TextButton } = {}
local selectedSize = 1
local countdownEndsAt: number? = nil
local flowState = "Lobby"
local introFinished = false
local titleDismissed = false
local savedWalkSpeed = 16
local savedJumpPower = 50
local savedJumpHeight = 7.2
local movementLocked = false
local gameStateController: any? = nil

-- // FUNCTIONS // --

local function tween(instance: Instance, info: TweenInfo, props: { [string]: any })
	local t = TweenService:Create(instance, info, props)
	t:Play()
	return t
end

local function fadeGui(guiObject: GuiObject, transparency: number, duration: number)
	tween(guiObject, TweenInfo.new(duration, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
		BackgroundTransparency = transparency,
	})
	for _, desc in ipairs(guiObject:GetDescendants()) do
		if desc:IsA("TextLabel") or desc:IsA("TextButton") then
			tween(desc, TweenInfo.new(duration, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
				TextTransparency = transparency,
				TextStrokeTransparency = math.clamp(transparency + 0.4, 0, 1),
			})
		elseif desc:IsA("ImageLabel") then
			tween(desc, TweenInfo.new(duration, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
				ImageTransparency = transparency,
			})
		elseif desc:IsA("Frame") and desc.BackgroundTransparency < 1 then
			tween(desc, TweenInfo.new(duration, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
				BackgroundTransparency = math.max(desc.BackgroundTransparency, transparency),
			})
		end
	end
end

local function setGroupTransparency(guiObject: GuiObject, transparency: number)
	guiObject.BackgroundTransparency = if guiObject.BackgroundTransparency < 1 then transparency else 1
	for _, desc in ipairs(guiObject:GetDescendants()) do
		if desc:IsA("TextLabel") or desc:IsA("TextButton") then
			desc.TextTransparency = transparency
			desc.TextStrokeTransparency = math.clamp(transparency + 0.4, 0, 1)
		elseif desc:IsA("ImageLabel") then
			desc.ImageTransparency = transparency
		end
	end
end

local function lockMovement()
	if movementLocked then
		return
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	savedWalkSpeed = humanoid.WalkSpeed
	savedJumpPower = humanoid.JumpPower
	savedJumpHeight = humanoid.JumpHeight
	humanoid.WalkSpeed = 0
	humanoid.JumpPower = 0
	humanoid.JumpHeight = 0
	movementLocked = true
end

local function unlockMovement()
	if not movementLocked then
		return
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = savedWalkSpeed
		humanoid.JumpPower = savedJumpPower
		humanoid.JumpHeight = savedJumpHeight
	end
	movementLocked = false
end

local function lockCamera()
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	camera.CameraType = Enum.CameraType.Scriptable
end

local function unlockCamera()
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	camera.CameraType = Enum.CameraType.Custom
end

local function formatCountdown(seconds: number): string
	return tostring(math.max(0, math.floor(seconds + 0.5)))
end

local function makeLabel(parent: Instance, name: string, text: string, size: number, color: Color3, position: UDim2, sizeDim: UDim2): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Size = sizeDim
	label.Position = position
	label.Font = Enum.Font.GothamBlack
	label.TextSize = size
	label.TextColor3 = color
	label.Text = text
	label.TextWrapped = true
	label.ZIndex = 10
	label.Parent = parent
	return label
end

local function makeButton(parent: Instance, name: string, text: string, textSize: number, color: Color3, position: UDim2, sizeDim: UDim2, radius: number?): TextButton
	local button = Instance.new("TextButton")
	button.Name = name
	button.Text = text
	button.TextColor3 = Color3.new(1, 1, 1)
	button.TextSize = textSize
	button.Font = Enum.Font.GothamBlack
	button.AutoButtonColor = true
	button.BackgroundColor3 = color
	button.BackgroundTransparency = 0
	button.Position = position
	button.Size = sizeDim
	button.ZIndex = 10
	button.Parent = parent
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius or 8)
	corner.Parent = button
	return button
end

local function makeCircleButton(parent: Instance, name: string, text: string, color: Color3, position: UDim2, sizeDim: UDim2): TextButton
	local button = Instance.new("TextButton")
	button.Name = name
	button.Text = text
	button.TextColor3 = Color3.new(1, 1, 1)
	button.TextSize = 24
	button.Font = Enum.Font.GothamBlack
	button.AutoButtonColor = true
	button.BackgroundColor3 = color
	button.BackgroundTransparency = 0
	button.Position = position
	button.Size = sizeDim
	button.ZIndex = 10
	button.Parent = parent
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = button
	return button
end

local function updateSizeButtons()
	for i, button in ipairs(sizeButtons) do
		if i == selectedSize then
			button.BackgroundColor3 = SIZE_SELECTED
			button.TextColor3 = Color3.new(0.1, 0.1, 0.1)
		else
			button.BackgroundColor3 = if i == 1 then SIZE_BTN else SIZE_DISABLED
			button.TextColor3 = if i == 1 then Color3.new(1, 1, 1) else Color3.new(0.6, 0.6, 0.6)
		end
	end
	if createButton then
		createButton.Text = "Create"
		createButton.BackgroundColor3 = CREATE
	end
end

local function buildGui()
	local playerGui = player:WaitForChild("PlayerGui")
	local gui = Instance.new("ScreenGui")
	gui.Name = "IntroGui"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 80
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = playerGui
	screenGui = gui

	local panel = Instance.new("Frame")
	panel.Name = "CreatePartyFrame"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromOffset(420, 360)
	panel.BackgroundColor3 = PANEL
	panel.BackgroundTransparency = PANEL_ALPHA
	panel.BorderSizePixel = 0
	panel.Visible = false
	panel.ZIndex = 20
	panel.Parent = gui
	createPartyFrame = panel
	local panelCorner = Instance.new("UICorner")
	panelCorner.CornerRadius = UDim.new(0, 16)
	panelCorner.Parent = panel

	local close = makeCircleButton(panel, "CloseButton", "X", CLOSE,
		UDim2.new(1, -12, 0, 12), UDim2.fromOffset(36, 36))
	close.AnchorPoint = Vector2.new(1, 0)

	local title = makeLabel(panel, "CreatePartyTitle", "Create Party", 28, HANDWRITTEN,
		UDim2.fromScale(0.5, 0.06), UDim2.new(0, 260, 0, 40))
	title.AnchorPoint = Vector2.new(0.5, 0)
	title.Font = Enum.Font.Gotham

	local partySize = makeLabel(panel, "PartySizeTitle", "Party Size", 36, BODY,
		UDim2.fromScale(0.5, 0.22), UDim2.new(0, 260, 0, 44))
	partySize.AnchorPoint = Vector2.new(0.5, 0)

	local sizeHolder = Instance.new("Frame")
	sizeHolder.Name = "SizeHolder"
	sizeHolder.AnchorPoint = Vector2.new(0.5, 0.5)
	sizeHolder.Position = UDim2.fromScale(0.5, 0.4)
	sizeHolder.Size = UDim2.fromOffset(280, 56)
	sizeHolder.BackgroundTransparency = 1
	sizeHolder.ZIndex = 22
	sizeHolder.Parent = panel
	local sizeList = Instance.new("UIListLayout")
	sizeList.FillDirection = Enum.FillDirection.Horizontal
	sizeList.HorizontalAlignment = Enum.HorizontalAlignment.Center
	sizeList.VerticalAlignment = Enum.VerticalAlignment.Center
	sizeList.Padding = UDim.new(0, 12)
	sizeList.Parent = sizeHolder

	for i = 1, 5 do
		local btn = makeButton(sizeHolder, "Size" .. i, tostring(i), 22,
			if i == 1 then SIZE_BTN else SIZE_DISABLED,
			UDim2.new(), UDim2.fromOffset(48, 48), 8)
		btn.LayoutOrder = i
		table.insert(sizeButtons, btn)
		if i ~= 1 then
			btn.AutoButtonColor = false
			btn.Active = false
		end
	end

	local createBtn = makeButton(panel, "CreateButton", "Create", 24, CREATE,
		UDim2.fromScale(0.5, 0.58), UDim2.fromOffset(320, 52), 10)
	createBtn.AnchorPoint = Vector2.new(0.5, 0)
	createButton = createBtn

	local customize = makeButton(panel, "CustomizeButton", "customize", 18, CUSTOMIZE,
		UDim2.fromScale(0.5, 0.75), UDim2.fromOffset(140, 32), 8)
	customize.AnchorPoint = Vector2.new(0.5, 0)

	local countLabel = makeLabel(panel, "CountdownLabel", "5", 64, CREAM,
		UDim2.fromScale(0.5, 0.58), UDim2.new(0, 320, 0, 80))
	countLabel.AnchorPoint = Vector2.new(0.5, 0)
	countLabel.Visible = false
	countdownLabel = countLabel

	local story = Instance.new("Frame")
	story.Name = "StoryFrame"
	story.Size = UDim2.fromScale(1, 1)
	story.BackgroundColor3 = Color3.new(0, 0, 0)
	story.BorderSizePixel = 0
	story.BackgroundTransparency = 1
	story.Visible = false
	story.ZIndex = 30
	story.Parent = gui
	storyFrame = story

	local story1 = makeLabel(story, "StoryLine1", "• Survive 99 Nights", 48, STORY,
		UDim2.fromScale(0.1, 0.42), UDim2.fromScale(0.8, 0.12))
	story1.TextXAlignment = Enum.TextXAlignment.Center

	local story2 = makeLabel(story, "StoryLine2", "• Finding the Missing Children will help", 32, STORY,
		UDim2.fromScale(0.1, 0.55), UDim2.fromScale(0.8, 0.1))
	story2.TextXAlignment = Enum.TextXAlignment.Center

	local day = Instance.new("Frame")
	day.Name = "DayFrame"
	day.Size = UDim2.fromScale(1, 1)
	day.BackgroundColor3 = Color3.new(0, 0, 0)
	day.BorderSizePixel = 0
	day.Visible = false
	day.ZIndex = 35
	day.Parent = gui
	dayFrame = day

	local dayText = makeLabel(day, "DayText", "Day 1", 54, CREAM,
		UDim2.fromScale(0.5, 0.5), UDim2.fromOffset(400, 90))
	dayText.AnchorPoint = Vector2.new(0.5, 0.5)
	dayText.Font = Enum.Font.Gotham

	updateSizeButtons()
end

local function destroyIntroGui()
	waitingJanitor:Cleanup()
	janitor:Cleanup()
	unlockMovement()
	unlockCamera()
	if screenGui then
		screenGui:Destroy()
		screenGui = nil
	end
	createPartyFrame = nil
	storyFrame = nil
	dayFrame = nil
	countdownLabel = nil
	createButton = nil
	sizeButtons = {}
end

local function startCountdownLoop()
	waitingJanitor:Cleanup()
	waitingJanitor:Add(RunService.RenderStepped:Connect(function()
		if not countdownLabel or not countdownEndsAt then
			return
		end
		countdownLabel.Text = formatCountdown(countdownEndsAt - Workspace:GetServerTimeNow())
	end), "Disconnect")
end

local function showCreateParty()
	if not createPartyFrame then
		return
	end
	createPartyFrame.Visible = true
	setGroupTransparency(createPartyFrame, 1)
	fadeGui(createPartyFrame, PANEL_ALPHA, PANEL_FADE)
	lockMovement()
	lockCamera()
end

local function showCountdown()
	if not createPartyFrame then
		return
	end
	for _, btn in ipairs(sizeButtons) do
		btn.Visible = false
	end
	if createButton then
		createButton.Visible = false
	end
	local customize = createPartyFrame:FindFirstChild("CustomizeButton")
	if customize then
		customize.Visible = false
	end
	if countdownLabel then
		countdownLabel.Visible = true
	end
	startCountdownLoop()
end

local function showStory()
	if not createPartyFrame then
		return
	end
	setGroupTransparency(createPartyFrame, 1)
	task.delay(PANEL_FADE, function()
		if createPartyFrame then
			createPartyFrame.Visible = false
		end
	end)
	if not storyFrame then
		return
	end
	storyFrame.Visible = true
	setGroupTransparency(storyFrame, 1)
	storyFrame.BackgroundTransparency = 1
	fadeGui(storyFrame, 0, STORY_FADE)
	storyFrame.BackgroundTransparency = 0
	lockMovement()
	lockCamera()
end

local function showDayCard()
	if storyFrame then
		storyFrame.Visible = false
	end
	if not dayFrame then
		return
	end
	dayFrame.Visible = true
	setGroupTransparency(dayFrame, 1)
	dayFrame.BackgroundTransparency = 1
	fadeGui(dayFrame, 0, 0.6)
	dayFrame.BackgroundTransparency = 0
end

local function finishIntro()
	if introFinished then
		return
	end
	introFinished = true
	if not dayFrame then
		unlockMovement()
		unlockCamera()
		if gameStateController then
			gameStateController:MarkIntroComplete()
		end
		destroyIntroGui()
		return
	end
	fadeGui(dayFrame, 1, REVEAL_SECONDS)
	task.delay(REVEAL_SECONDS, function()
		unlockMovement()
		unlockCamera()
		if gameStateController then
			gameStateController:MarkIntroComplete()
		end
		destroyIntroGui()
	end)
end

-- // INITIALIZATION // --

function IntroController:KnitInit()
	buildGui()
end

function IntroController:KnitStart()
	gameStateController = Knit.GetController("GameStateController")
	local matchFlow = Knit.GetService("MatchFlowService")

	if createButton then
		createButton.MouseButton1Click:Connect(function()
			if selectedSize ~= 1 or flowState ~= "Waiting" then
				return
			end
			matchFlow.RequestStart:Fire()
		end)
	end

	for i, btn in ipairs(sizeButtons) do
		btn.MouseButton1Click:Connect(function()
			if flowState ~= "Waiting" then
				return
			end
			if i == 1 then
				selectedSize = 1
				updateSizeButtons()
			end
		end)
	end

	matchFlow.FlowStateChanged:Connect(function(state: string)
		if state == flowState then
			return
		end
		flowState = state
		if state == "Waiting" then
			showCreateParty()
		elseif state == "Countdown" then
			showCountdown()
		elseif state == "Story" then
			showStory()
		elseif state == "Day1" then
			showDayCard()
		elseif state == "InGame" then
			finishIntro()
		end
	end)

	matchFlow.Countdown:Connect(function(payload)
		if typeof(payload) == "table" and typeof(payload.endsAt) == "number" then
			countdownEndsAt = payload.endsAt
		end
	end)

	print("[IntroController] Initialised")
end

return IntroController
