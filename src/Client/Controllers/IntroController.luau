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

    @exports
    - IntroController (Knit controller)
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
local UiSoundUtil = require(ReplicatedStorage.Shared.UiSoundUtil)

-- | Objects | --
local IntroController = Knit.CreateController({
	Name = "IntroController",
})

-- | Configuration | --
-- Fade/reveal timing
local PANEL_FADE = 0.3
local STORY_FADE = Constants.MATCH_STORY_FADE_SECONDS or 1.2
local REVEAL_SECONDS = Constants.MATCH_REVEAL_SECONDS or 2.5

-- Title-screen palette (IntroAssets colors with inline fallbacks)
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

-- Story-screen palette
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
local leaveButton: TextButton? = nil
local rosterLabel: TextLabel? = nil
local statusLabel: TextLabel? = nil
local sizeButtons: { TextButton } = {}
local selectedSize = 1
local sessionSnapshot: { [string]: any }? = nil
local countdownEndsAt: number? = nil
local flowState = "Lobby"
local introFinished = false
local titleDismissed = false
local savedWalkSpeed = 16
local savedJumpPower = 50
local savedJumpHeight = 7.2
local movementLocked = false
local gameStateController: any = nil

-- // FUNCTIONS // --

--[[
    @summary  Create and play a tween, returning it.
    @param    instance  Instance
    @param    info      TweenInfo
    @param    props     { [string]: any }
    @returns  Tween
]]
local function tween(instance: Instance, info: TweenInfo, props: { [string]: any })
	local t = TweenService:Create(instance, info, props)
	t:Play()
	return t
end

--[[
    @summary  Tween a text object's TextTransparency and stroke
              transparency toward a target.
    @param    textObject     TextLabel | TextButton
    @param    transparency   number
    @param    duration       number  -- seconds
]]
local function fadeText(textObject: TextLabel | TextButton, transparency: number, duration: number)
	tween(textObject, TweenInfo.new(duration, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
		TextTransparency = transparency,
		TextStrokeTransparency = math.clamp(transparency + 0.4, 0, 1),
	})
end

--[[
    @summary  Fade a GuiObject's background plus all text/image
              descendants to a target transparency.
    @param    guiObject      GuiObject
    @param    transparency   number
    @param    duration       number  -- seconds
]]
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

--[[
    @summary  Snap a GuiObject and its text/image descendants to a
              transparency (no tween). Leaves fully-hidden backgrounds
              hidden.
    @param    guiObject      GuiObject
    @param    transparency   number
]]
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

--[[
    @summary  Freeze the player during the intro — saves WalkSpeed/
              JumpPower/JumpHeight then zeroes them.
]]
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

--[[
    @summary  Restore the saved WalkSpeed/JumpPower/JumpHeight.
]]
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

--[[
    @summary  Switch the camera to Scriptable for intro cinematics.
]]
local function lockCamera()
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	camera.CameraType = Enum.CameraType.Scriptable
end

--[[
    @summary  Restore the camera to Custom targeting the player's
              humanoid.
]]
local function unlockCamera()
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	camera.CameraType = Enum.CameraType.Custom
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		camera.CameraSubject = humanoid
	end
end

--[[
    @summary  Format a countdown as a whole-second string (min 0).
    @param    seconds  number
    @returns  string
]]
local function formatCountdown(seconds: number): string
	return tostring(math.max(0, math.floor(seconds + 0.5)))
end

--[[
    @summary  Create a styled TextLabel for the intro screens.
    @param    parent    Instance
    @param    name      string
    @param    text      string
    @param    size      number   -- TextSize
    @param    color     Color3
    @param    position  UDim2
    @param    sizeDim   UDim2
    @returns  TextLabel
]]
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

--[[
    @summary  Create a styled TextButton for the intro screens.
    @param    parent    Instance
    @param    name      string
    @param    text      string
    @param    textSize  number
    @param    color     Color3
    @param    position  UDim2
    @param    sizeDim   UDim2
    @param    radius    number?  -- corner radius
    @returns  TextButton
]]
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

--[[
    @summary  Create a circular party-size TextButton.
    @param    parent    Instance
    @param    name      string
    @param    text      string
    @param    color     Color3
    @param    position  UDim2
    @param    sizeDim   UDim2
    @returns  TextButton
]]
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

--[[
    @summary  Refresh party-size button states — interactive only for
              the host while the session is in Waiting; locked during
              Countdown.
]]
local function updateSizeButtons()
	-- Size buttons are only interactive for the HOST during setup (Waiting state).
	-- Once the lobby is opened (Countdown), capacity is locked — no changes allowed.
	local isHostInWaiting = flowState == "Waiting" and sessionSnapshot ~= nil and sessionSnapshot.isHost == true
	local isHostInCountdown = flowState == "Countdown" and sessionSnapshot ~= nil and sessionSnapshot.isHost == true
	for i, button in ipairs(sizeButtons) do
		-- Active only during setup phase
		button.Active = isHostInWaiting
		button.AutoButtonColor = isHostInWaiting
		if i == selectedSize then
			button.BackgroundColor3 = if isHostInWaiting then SIZE_SELECTED else Color3.fromRGB(55, 58, 65)
			button.TextColor3 = if isHostInWaiting then Color3.new(0.1, 0.1, 0.1) else Color3.fromRGB(160, 160, 160)
		else
			button.BackgroundColor3 = SIZE_DISABLED
			button.TextColor3 = Color3.new(0.6, 0.6, 0.6)
		end
	end
	if createButton then
		createButton.Visible = true
		if flowState == "Waiting" then
			createButton.Active = isHostInWaiting
			createButton.AutoButtonColor = isHostInWaiting
			createButton.Text = if isHostInWaiting then "Open Lobby" else "Waiting for Host..."
			createButton.BackgroundColor3 = if isHostInWaiting then CREATE else SIZE_DISABLED
		else
			-- During Countdown: "Start Now" is available to host, others see "Lobby Open"
			createButton.Active = isHostInCountdown
			createButton.AutoButtonColor = isHostInCountdown
			createButton.Text = if isHostInCountdown then "Start Now" else "Lobby Open..."
			createButton.BackgroundColor3 = if isHostInCountdown then Color3.fromRGB(40, 170, 80) else SIZE_DISABLED
		end
	end
	if countdownLabel then
		countdownLabel.Visible = (flowState == "Countdown")
	end
end

--[[
    @summary  Render a session snapshot — syncs selectedSize from
              capacity and rebuilds the roster lines with host/member
              badges.
    @param    snapshot  { [string]: any }
]]
local function renderSession(snapshot: { [string]: any })
	sessionSnapshot = snapshot
	if typeof(snapshot.capacity) == "number" then
		selectedSize = math.clamp(math.floor(snapshot.capacity), 1, 5)
	end
	local roster = if typeof(snapshot.roster) == "table" then snapshot.roster else {}
	local lines = {}
	for _, member in ipairs(roster) do
		if typeof(member) == "table" then
			local prefix = member.isHost and '<b><font color="#FFD232">★ HOST</font></b>' or '<font color="#A0A0A0">● MEMBER</font>'
			table.insert(lines, prefix .. "  " .. tostring(member.name or member.username or "Player"))
		end
	end
	if rosterLabel then
		rosterLabel.Text = #lines > 0 and table.concat(lines, "\n") or '<font color="#666666">No players yet...</font>'
	end
	if statusLabel then
		local stateLabel = if flowState == "Waiting" then "Setting up" else "Lobby Open"
		local hostLabel = if snapshot.isHost then "You are host" else "Hosted by teammate"
		statusLabel.Text = ("%s  ·  %d/%d players  ·  %s"):format(stateLabel, #roster, selectedSize, hostLabel)
	end
	updateSizeButtons()
end

--[[
    @summary  Build the intro ScreenGui — create-party frame, size
              buttons, roster, countdown label, and leave/close wiring.
]]
local function buildGui()
	local playerGui = player:WaitForChild("PlayerGui")
	if not playerGui then
		return
	end
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
	panel.Size = UDim2.new(0.9, 0, 0.86, 0)
	panel.BackgroundColor3 = Color3.fromRGB(18, 20, 24)
	panel.BackgroundTransparency = 0.15
	panel.BorderSizePixel = 0
	panel.Visible = false
	panel.ZIndex = 20
	panel.Parent = gui
	createPartyFrame = panel
	local panelCorner = Instance.new("UICorner")
	panelCorner.CornerRadius = UDim.new(0, 16)
	panelCorner.Parent = panel
	local panelStroke = Instance.new("UIStroke")
	panelStroke.Color = Color3.fromRGB(80, 90, 110)
	panelStroke.Thickness = 2
	panelStroke.Parent = panel
	local panelSize = Instance.new("UISizeConstraint")
	panelSize.MinSize = Vector2.new(300, 440)
	panelSize.MaxSize = Vector2.new(540, 580)
	panelSize.Parent = panel

	local close = makeCircleButton(panel, "CloseButton", "X", CLOSE,
		UDim2.new(1, -12, 0, 12), UDim2.fromOffset(36, 36))
	close.AnchorPoint = Vector2.new(1, 0)
	close.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	close.TextStrokeTransparency = 0.3

	local title = makeLabel(panel, "CreatePartyTitle", "Create Party", 28, HANDWRITTEN,
		UDim2.fromScale(0.5, 0.06), UDim2.new(0, 260, 0, 40))
	title.AnchorPoint = Vector2.new(0.5, 0)
	title.Font = Enum.Font.GothamBold
	title.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	title.TextStrokeTransparency = 0.3

	local status = makeLabel(panel, "StatusLabel", "Waiting for queue...", 16, BODY,
		UDim2.fromScale(0.5, 0.14), UDim2.new(0.88, 0, 0, 34))
	status.AnchorPoint = Vector2.new(0.5, 0)
	statusLabel = status

	local partySize = makeLabel(panel, "PartySizeTitle", "Party Capacity", 24, BODY,
		UDim2.fromScale(0.5, 0.22), UDim2.new(0, 260, 0, 34))
	partySize.AnchorPoint = Vector2.new(0.5, 0)

	local sizeHolder = Instance.new("Frame")
	sizeHolder.Name = "SizeHolder"
	sizeHolder.AnchorPoint = Vector2.new(0.5, 0)
	sizeHolder.Position = UDim2.fromScale(0.5, 0.29)
	sizeHolder.Size = UDim2.new(0.88, 0, 0, 48)
	sizeHolder.BackgroundTransparency = 1
	sizeHolder.ZIndex = 22
	sizeHolder.Parent = panel
	local sizeList = Instance.new("UIListLayout")
	sizeList.FillDirection = Enum.FillDirection.Horizontal
	sizeList.HorizontalAlignment = Enum.HorizontalAlignment.Center
	sizeList.VerticalAlignment = Enum.VerticalAlignment.Center
	sizeList.Padding = UDim.new(0, 8)
	sizeList.Parent = sizeHolder

	for i = 1, 5 do
		local btn = makeButton(sizeHolder, "Size" .. i, tostring(i), 20, SIZE_BTN,
			UDim2.new(), UDim2.fromOffset(44, 44), 8)
		btn.LayoutOrder = i
		table.insert(sizeButtons, btn)
	end

	local roster = makeLabel(panel, "RosterLabel", "Waiting for players...", 18, BODY,
		UDim2.fromScale(0.08, 0.41), UDim2.new(0.84, 0, 0.27, 0))
	roster.TextXAlignment = Enum.TextXAlignment.Left
	roster.TextYAlignment = Enum.TextYAlignment.Top
	roster.RichText = true
	rosterLabel = roster

	local createBtn = makeButton(panel, "CreateButton", "Start", 22, CREATE,
		UDim2.fromScale(0.5, 0.72), UDim2.new(0.78, 0, 0, 48), 10)
	createBtn.AnchorPoint = Vector2.new(0.5, 0)
	createButton = createBtn

	local leaveBtn = makeButton(panel, "LeaveButton", "Leave", 19, CLOSE,
		UDim2.fromScale(0.5, 0.83), UDim2.new(0.48, 0, 0, 42), 10)
	leaveBtn.AnchorPoint = Vector2.new(0.5, 0)
	leaveButton = leaveBtn

	local countLabel = makeLabel(panel, "CountdownLabel", "Starting in: 45s", 22, CREAM,
		UDim2.fromScale(0.5, 0.64), UDim2.new(0, 320, 0, 30))
	countLabel.AnchorPoint = Vector2.new(0.5, 0)
	countLabel.Visible = false
	countLabel.Font = Enum.Font.GothamBold
	countLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	countLabel.TextStrokeTransparency = 0.3
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
	story1.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	story1.TextStrokeTransparency = 0.4

	local story2 = makeLabel(story, "StoryLine2", "• Finding the Missing Children will help", 32, STORY,
		UDim2.fromScale(0.1, 0.55), UDim2.fromScale(0.8, 0.1))
	story2.TextXAlignment = Enum.TextXAlignment.Center
	story2.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	story2.TextStrokeTransparency = 0.4

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
	dayText.Font = Enum.Font.GothamBold
	dayText.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	dayText.TextStrokeTransparency = 0.3

	updateSizeButtons()
end

--[[
    @summary  Build the hidden title-screen frame — logo, subtitle,
              and the PLAY button.
    @desc     No-op until the intro ScreenGui exists.
]]
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
	header.TextStrokeTransparency = 0.3

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
			15, STORY_CAPTION,
			UDim2.new(), UDim2.new(1, 0, 0.28, 0))
		caption.LayoutOrder = 2
		caption.ZIndex = 8
		caption.TextWrapped = true
		caption.TextXAlignment = Enum.TextXAlignment.Center
		caption.TextYAlignment = Enum.TextYAlignment.Center
		caption.Font = Enum.Font.GothamBold
		caption.RichText = true
		caption.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
		caption.TextStrokeTransparency = 0.4
	end

	local play = Instance.new("TextButton")
	play.Name = "PlayButton"
	play.Text = "PLAY"
	play.TextColor3 = Color3.new(1, 1, 1)
	play.TextSize = 46
	play.Font = Enum.Font.Bangers
	play.TextStrokeColor3 = Color3.new(0, 0, 0)
	play.TextStrokeTransparency = 0.3
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

--[[
    @summary  Fade in the title screen and raise the intro GUI's
              DisplayOrder above everything else.
]]
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

--[[
    @summary  Fade out and dismiss the title screen.
    @param    fromPlay  boolean?  -- also unlocks the camera when the
                        PLAY button triggered the dismiss
]]
local function hideTitleScreen(fromPlay: boolean?)
	if not titleScreen or titleDismissed then
		return
	end
	titleDismissed = true

	if fromPlay then
		unlockCamera()
	end

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
		end
	end)
end

--[[
    @summary  Tear down the whole intro — cleans janitors, unlocks
              movement/camera, restores CoreGui, and destroys the GUI.
]]
local function destroyIntroGui()
	waitingJanitor:Cleanup()
	janitor:Cleanup()
	unlockMovement()
	unlockCamera()
	pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, true)
	end)
	if screenGui then
		screenGui:Destroy()
		screenGui = nil
	end
	titleScreen = nil
	createPartyFrame = nil
	storyFrame = nil
	dayFrame = nil
	countdownLabel = nil
	createButton = nil
	sizeButtons = {}
end

--[[
    @summary  Per-frame RenderStepped loop that updates the
              "Starting in: Ns" countdown label from the server clock.
]]
local function startCountdownLoop()
	waitingJanitor:Cleanup()
	waitingJanitor:Add(RunService.RenderStepped:Connect(function()
		if not countdownLabel or not countdownEndsAt then
			return
		end
		countdownLabel.Text = "Starting in: " .. formatCountdown(countdownEndsAt - Workspace:GetServerTimeNow()) .. "s"
	end), "Disconnect")
end

--[[
    @summary  Show the create-party frame — resets the countdown, shows
              size buttons, and reveals the countdown label only in the
              Countdown state.
]]
local function showCreateParty()
	if not createPartyFrame then
		return
	end
	waitingJanitor:Cleanup()
	countdownEndsAt = nil
	if countdownLabel then
		countdownLabel.Visible = (flowState == "Countdown")
	end
	for _, button in ipairs(sizeButtons) do
		button.Visible = true
	end
	if createButton then
		createButton.Visible = true
	end
	for _, name in ipairs({ "PartySizeTitle", "SizeHolder", "RosterLabel", "StatusLabel" }) do
		local object = createPartyFrame:FindFirstChild(name)
		if object and object:IsA("GuiObject") then
			object.Visible = true
		end
	end
	updateSizeButtons()
	if titleScreen then
		if titleScreen.Visible then
			hideTitleScreen()
		end
	end
	if storyFrame then
		storyFrame.Visible = false
	end
	if dayFrame then
		dayFrame.Visible = false
	end
	createPartyFrame.Visible = true
	setGroupTransparency(createPartyFrame, 1)
	fadeGui(createPartyFrame, PANEL_ALPHA, PANEL_FADE)
	lockMovement()
	lockCamera()
end

--[[
    @summary  Legacy no-op — countdown UI is handled by
              showCreateParty during the Countdown state.
]]
local function showCountdown()
	-- Legacy function, UI is now handled by showCreateParty during Countdown
end

--[[
    @summary  Fade out the create-party frame and play the story
              sequence frame.
]]
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

--[[
    @summary  Hide the story frame and fade in the "Day 1" card.
]]
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

--[[
    @summary  End the intro — fades the day card, then unlocks
              movement/camera and tears the GUI down.
]]
local function finishIntro()
	if introFinished then
		return
	end
	introFinished = true
	if dayFrame then
		fadeGui(dayFrame, 1, REVEAL_SECONDS)
	end
	task.delay(if dayFrame then REVEAL_SECONDS else 0, function()
		if dayFrame then
			dayFrame.Visible = false
		end
		waitingJanitor:Cleanup()
		unlockMovement()
		unlockCamera()
		if gameStateController then
			gameStateController:MarkIntroComplete()
		end
	end)
end

--[[
    @summary  Reset all intro state when returning to the lobby —
              clears countdown, snapshot, and hides every frame.
]]
local function resetForLobby()
	waitingJanitor:Cleanup()
	countdownEndsAt = nil
	introFinished = false
	sessionSnapshot = nil
	selectedSize = 1
	if createPartyFrame then
		createPartyFrame.Visible = false
	end
	if storyFrame then
		storyFrame.Visible = false
	end
	if dayFrame then
		dayFrame.Visible = false
	end
	if countdownLabel then
		countdownLabel.Visible = false
	end
	for _, button in ipairs(sizeButtons) do
		button.Visible = true
	end
	if leaveButton then
		leaveButton.Visible = true
	end
	unlockMovement()
	unlockCamera()
	updateSizeButtons()
end

-- // INITIALIZATION // --

--[[
    @summary  Knit lifecycle init — builds the intro GUI and title
              screen before services start.
]]
function IntroController:KnitInit()
	buildGui()
	buildTitleScreen()
end

--[[
    @summary  Knit lifecycle start — resolves services, wires the PLAY
              button, leave/close buttons, session-state and flow-state
              observers, and shows the title screen on lobby servers.
]]
function IntroController:KnitStart()
	gameStateController = Knit.GetController("GameStateController")
	local matchFlow = Knit.GetService("MatchFlowService")

	-- Title screen PLAY button dismisses it and lets the player roam the lobby.
	if titleScreen then
		local play = titleScreen:FindFirstChild("PlayButton")
		if play then
			play.MouseButton1Click:Connect(function()
				UiSoundUtil.playClick()
				hideTitleScreen(true)
			end)
		end
	end

	if createButton then
		createButton.MouseButton1Click:Connect(function()
			UiSoundUtil.playClick()
			if (flowState == "Countdown" or flowState == "Waiting") and sessionSnapshot and sessionSnapshot.isHost == true then
				matchFlow.RequestStart:Fire()
			end
		end)
	end

	--[[
	    @summary  Play a click sound and fire RequestLeave when the
	              session is in Waiting or Countdown.
	]]
	local function requestLeave()
		UiSoundUtil.playClick()
		if flowState == "Waiting" or flowState == "Countdown" then
			matchFlow.RequestLeave:Fire()
		end
	end
	if leaveButton then
		leaveButton.MouseButton1Click:Connect(requestLeave)
	end
	if createPartyFrame then
		local close = createPartyFrame:FindFirstChild("CloseButton")
		if close and close:IsA("TextButton") then
			close.MouseButton1Click:Connect(requestLeave)
		end
	end

	for i, btn in ipairs(sizeButtons) do
		btn.MouseButton1Click:Connect(function()
			if (flowState ~= "Countdown" and flowState ~= "Waiting") or not sessionSnapshot or sessionSnapshot.isHost ~= true then
				return
			end
			UiSoundUtil.playClick()
			selectedSize = i
			updateSizeButtons()
			matchFlow.RequestSetCapacity:Fire(i)
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
		if state == "Lobby" then
			resetForLobby()
		elseif state == "Waiting" then
			showCreateParty()
		elseif state == "Countdown" then
			showCreateParty()
			startCountdownLoop()
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

	matchFlow.SessionChanged:Connect(function(snapshot)
		if typeof(snapshot) ~= "table" then
			return
		end
		if snapshot.state == "Lobby" then
			sessionSnapshot = nil
		else
			renderSession(snapshot)
		end
	end)

	matchFlow:GetSnapshot():andThen(function(snapshot)
		if typeof(snapshot) ~= "table" then
			return
		end
		if snapshot.state ~= "Lobby" then
			flowState = snapshot.state
			renderSession(snapshot)
			if snapshot.state == "Waiting" then
				showCreateParty()
			elseif snapshot.state == "Countdown" then
				countdownEndsAt = snapshot.endsAt
				showCreateParty()
				startCountdownLoop()
			end
		end
	end)

	-- If the player is still in the Lobby, show the title screen immediately.
	-- Skip if the game has already advanced past Lobby (e.g. test mode).
	if flowState == "Lobby" then
		showTitleScreen()
	end

end

return IntroController
