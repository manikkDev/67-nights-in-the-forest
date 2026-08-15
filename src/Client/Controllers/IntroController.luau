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
local StarterGui = game:GetService("StarterGui")

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

local TITLE_OUT = 1.0
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

local function fadeText(textObject: TextLabel | TextButton, transparency: number, duration: number)
	tween(textObject, TweenInfo.new(duration, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
		TextTransparency = transparency,
		TextStrokeTransparency = math.clamp(transparency + 0.4, 0, 1),
	})
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
			local imageProps: { [string]: any } = { ImageTransparency = transparency }
			if desc.Image == "rbxassetid://0" or desc.Image == "" then
				imageProps.BackgroundTransparency = transparency
			end
			tween(desc, TweenInfo.new(duration, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), imageProps)
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
			desc.BackgroundTransparency = transparency
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

local function buildTitleScreen()
	if not screenGui then
		return
	end

	local title = Instance.new("Frame")
	title.Name = "TitleScreen"
	title.Size = UDim2.fromScale(1, 1)
	title.BackgroundColor3 = STORY_BACK
	title.BorderSizePixel = 0
	title.Visible = false
	title.ZIndex = 5
	title.Parent = screenGui
	titleScreen = title

	local header = makeLabel(title, "TitleHeader",
		"THIS GAME IS BASED ON A TRUE STORY. SOME DETAILS HAVE BEEN CHANGED",
		30, STORY_HEADER,
		UDim2.fromScale(0.5, 0.05), UDim2.new(0.9, 0, 0, 70))
	header.AnchorPoint = Vector2.new(0.5, 0)
	header.TextXAlignment = Enum.TextXAlignment.Center
	header.TextYAlignment = Enum.TextYAlignment.Top
	header.TextWrapped = true
	header.ZIndex = 10
	header.Font = Enum.Font.Bangers
	header.TextStrokeColor3 = Color3.new(0, 0, 0)
	header.TextStrokeTransparency = 1

	local panelsHolder = Instance.new("Frame")
	panelsHolder.Name = "PanelsHolder"
	panelsHolder.AnchorPoint = Vector2.new(0.5, 0.5)
	panelsHolder.Position = UDim2.fromScale(0.5, 0.52)
	panelsHolder.Size = UDim2.new(0.95, 0, 0.65, 0)
	panelsHolder.BackgroundTransparency = 1
	panelsHolder.BorderSizePixel = 0
	panelsHolder.ZIndex = 6
	panelsHolder.ClipsDescendants = true
	panelsHolder.Parent = title

	local holderList = Instance.new("UIListLayout")
	holderList.FillDirection = Enum.FillDirection.Horizontal
	holderList.HorizontalAlignment = Enum.HorizontalAlignment.Center
	holderList.VerticalAlignment = Enum.VerticalAlignment.Center
	holderList.Padding = UDim.new(0, 12)
	holderList.SortOrder = Enum.SortOrder.LayoutOrder
	holderList.Parent = panelsHolder

	local imageIds = IntroAssets.StoryPanelImages or {}
	local storyPanels = IntroAssets.StoryPanels or {}

	for i = 1, 4 do
		local panel = Instance.new("Frame")
		panel.Name = "StoryPanel" .. i
		panel.Size = UDim2.new(0.18, 0, 0.62, 0)
		panel.BackgroundColor3 = STORY_PANEL
		panel.BackgroundTransparency = 1
		panel.BorderSizePixel = 0
		panel.ZIndex = 7
		panel.LayoutOrder = i
		panel.ClipsDescendants = true
		panel.Parent = panelsHolder

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 8)
		corner.Parent = panel

		local stroke = Instance.new("UIStroke")
		stroke.Color = Color3.fromRGB(60, 60, 60)
		stroke.Thickness = 1
		stroke.Transparency = 0.4
		stroke.Parent = panel

		local pad = Instance.new("UIPadding")
		pad.PaddingTop = UDim.new(0, 8)
		pad.PaddingBottom = UDim.new(0, 8)
		pad.PaddingLeft = UDim.new(0, 8)
		pad.PaddingRight = UDim.new(0, 8)
		pad.Parent = panel

		local list = Instance.new("UIListLayout")
		list.FillDirection = Enum.FillDirection.Vertical
		list.HorizontalAlignment = Enum.HorizontalAlignment.Center
		list.VerticalAlignment = Enum.VerticalAlignment.Top
		list.Padding = UDim.new(0, 4)
		list.SortOrder = Enum.SortOrder.LayoutOrder
		list.Parent = panel

		local image = Instance.new("ImageLabel")
		image.Name = "Image"
		image.LayoutOrder = 1
		image.Size = UDim2.new(1, 0, 0.7, 0)
		image.BackgroundColor3 = STORY_PLACEHOLDER
		image.BackgroundTransparency = 1
		image.BorderSizePixel = 0
		image.ScaleType = Enum.ScaleType.Crop
		image.ZIndex = 8
		image.Parent = panel

		local id = imageIds[i]
		if id and id ~= "" then
			image.Image = id
			image.BackgroundTransparency = 1
		end

		local caption = makeLabel(panel, "Caption",
			typeof(storyPanels[i]) == "table" and storyPanels[i].caption or "",
			14, STORY_CAPTION,
			UDim2.new(), UDim2.new(1, 0, 0.28, 0))
		caption.LayoutOrder = 2
		caption.ZIndex = 8
		caption.TextWrapped = true
		caption.TextXAlignment = Enum.TextXAlignment.Center
		caption.TextYAlignment = Enum.TextYAlignment.Center
		caption.Font = Enum.Font.Gotham
		caption.RichText = true
	end

	local play = Instance.new("TextButton")
	play.Name = "PlayButton"
	play.Text = "PLAY"
	play.TextColor3 = Color3.new(1, 1, 1)
	play.TextSize = 46
	play.Font = Enum.Font.Bangers
	play.TextStrokeColor3 = Color3.new(0, 0, 0)
	play.TextStrokeTransparency = 1
	play.AutoButtonColor = true
	play.BackgroundColor3 = PLAY
	play.BackgroundTransparency = 0
	play.Position = UDim2.new(0.5, 0, 1, -70)
	play.Size = UDim2.fromOffset(280, 64)
	play.AnchorPoint = Vector2.new(0.5, 0.5)
	play.ZIndex = 10
	play.Parent = title

	local playCorner = Instance.new("UICorner")
	playCorner.CornerRadius = UDim.new(0, 12)
	playCorner.Parent = play
end

local function showTitleScreen()
	if not titleScreen or titleDismissed then
		return
	end

	titleScreen.Visible = true
	titleScreen.BackgroundTransparency = 1
	setGroupTransparency(titleScreen, 1)

	if screenGui then
		screenGui.DisplayOrder = 10000
	end
	pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, false)
	end)

	local camera = Workspace.CurrentCamera
	if camera then
		camera.CameraType = Enum.CameraType.Scriptable
	end
	lockMovement()
	lockCamera()

	-- fade in background
	tween(titleScreen, TweenInfo.new(0.4, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
		BackgroundTransparency = 0,
	})

	local header = titleScreen:FindFirstChild("TitleHeader")
	if header and header:IsA("TextLabel") then
		task.delay(0.15, function()
			fadeText(header, 0, 0.5)
		end)
	end

	local panelsHolder = titleScreen:FindFirstChild("PanelsHolder")
	if panelsHolder then
		for i, panel in ipairs(panelsHolder:GetChildren()) do
			if panel:IsA("Frame") then
				task.delay(0.35 + (i - 1) * 0.1, function()
					fadeGui(panel, 0, 0.4)
				end)
			end
		end
	end

	local play = titleScreen:FindFirstChild("PlayButton")
	if play and (play:IsA("TextButton") or play:IsA("TextLabel")) then
		task.delay(0.85, function()
			fadeText(play, 0, 0.4)
		end)
	end
end

local function hideTitleScreen(fromPlay: boolean?)
	if not titleScreen or titleDismissed then
		return
	end
	titleDismissed = true
	fadeGui(titleScreen, 1, TITLE_OUT)

	local play = titleScreen:FindFirstChild("PlayButton")
	if play and play:IsA("TextButton") then
		tween(play, TweenInfo.new(TITLE_OUT, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
			BackgroundTransparency = 1,
		})
	end

	task.delay(TITLE_OUT, function()
		if titleScreen then
			titleScreen.Visible = false
		end
		if screenGui then
			screenGui.DisplayOrder = 80
		end
		pcall(function()
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, true)
		end)
		if fromPlay then
			unlockMovement()
			unlockCamera()
		end
	end)
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
	if titleScreen then
		if titleScreen.Visible then
			hideTitleScreen()
		end
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

	-- Teleport already happened while the screen was black; snap the
	-- camera to the player at the campfire before the reveal begins.
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local camera = Workspace.CurrentCamera
	if camera and humanoid then
		camera.CameraType = Enum.CameraType.Custom
		camera.CameraSubject = humanoid
	end
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
	buildTitleScreen()
end

function IntroController:KnitStart()
	gameStateController = Knit.GetController("GameStateController")
	local matchFlow = Knit.GetService("MatchFlowService")

	-- Title screen PLAY button dismisses it and lets the player roam the lobby.
	if titleScreen then
		local play = titleScreen:FindFirstChild("PlayButton")
		if play then
			play.MouseButton1Click:Connect(function()
				hideTitleScreen(true)
			end)
		end
	end

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
		-- Title screen is only for the Lobby; dismiss it once the game flow advances.
		if titleScreen then
			if titleScreen.Visible and state ~= "Lobby" then
				hideTitleScreen()
			end
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

	-- If the player is still in the Lobby, show the title screen immediately.
	if flowState == "Lobby" then
		showTitleScreen()
	end

	print("[IntroController] Initialised")
end

return IntroController
