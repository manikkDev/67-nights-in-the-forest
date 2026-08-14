--[[
    @file    IntroController.luau
    @author  manik
    @date    2025

    @summary
    Client presenter for title splash, waiting room, and Day 1 card.

    @description
    Builds one ScreenGui with three frames. Title plays on join.
    Waiting/Starting/InGame come from MatchFlowService. Gameplay
    unlocks only after the Day 1 card fades out.
]]

-- // VARIABLES // --

-- | Services | --
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

-- | Modules | --
local Knit = require(ReplicatedStorage.Packages.Knit)
local Janitor = require(ReplicatedStorage.Packages.Janitor)
local IntroAssets = require(ReplicatedStorage.Shared.IntroAssets)

-- | Objects | --
local IntroController = Knit.CreateController({
	Name = "IntroController",
})

-- | Configuration | --
local TITLE_HOLD = 5
local TITLE_FADE = 0.6
local WAITING_FADE = 0.4
local DAY1_IN = 0.8
local DAY1_HOLD = 1.8
local DAY1_OUT = 1.2
local CREAM = IntroAssets.TitleColor or Color3.fromRGB(232, 220, 190)
local MUTED = IntroAssets.SubtitleColor or Color3.fromRGB(170, 160, 140)
local GREEN = IntroAssets.AccentGreen or Color3.fromRGB(80, 170, 70)

-- | State Management | --
local player = Players.LocalPlayer
local janitor = Janitor.new()
local waitingJanitor = Janitor.new()
local screenGui: ScreenGui? = nil
local titleFrame: Frame? = nil
local waitingFrame: Frame? = nil
local dayFrame: Frame? = nil
local timerLabel: TextLabel? = nil
local startButton: TextButton? = nil
local rosterHolder: Frame? = nil
local countdownEndsAt: number? = nil
local flowState = "Lobby"
local titleDismissed = false
local introFinished = false
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

local function formatTimer(seconds: number): string
	seconds = math.max(0, math.floor(seconds + 0.5))
	local minutes = math.floor(seconds / 60)
	local remain = seconds % 60
	return string.format("%02d:%02d", minutes, remain)
end

local function makeLabel(parent: Instance, name: string, text: string, size: number, color: Color3, yScale: number, yOffset: number, height: number): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, -40, 0, height)
	label.Position = UDim2.new(0, 20, yScale, yOffset)
	label.Font = Enum.Font.GothamBlack
	label.TextSize = size
	label.TextColor3 = color
	label.Text = text
	label.TextWrapped = true
	label.ZIndex = 5
	label.Parent = parent
	return label
end

local function applyDeerImage(image: ImageLabel, assetId: string)
	if typeof(assetId) == "string" and assetId ~= "" then
		image.Image = assetId
		image.ImageColor3 = Color3.new(1, 1, 1)
		image.ImageTransparency = 0.15
	else
		image.Image = "rbxasset://textures/ui/GuiImagePlaceholder.png"
		image.ImageColor3 = Color3.fromRGB(18, 18, 18)
		image.ImageTransparency = 0.35
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

	local title = Instance.new("Frame")
	title.Name = "TitleFrame"
	title.Size = UDim2.fromScale(1, 1)
	title.BackgroundColor3 = Color3.new(0, 0, 0)
	title.BorderSizePixel = 0
	title.Visible = false
	title.ZIndex = 10
	title.Parent = gui
	titleFrame = title

	local titleDeer = Instance.new("ImageLabel")
	titleDeer.Name = "Deer"
	titleDeer.AnchorPoint = Vector2.new(0.5, 0.5)
	titleDeer.Position = UDim2.fromScale(0.5, 0.42)
	titleDeer.Size = UDim2.fromOffset(420, 420)
	titleDeer.BackgroundTransparency = 1
	titleDeer.ScaleType = Enum.ScaleType.Fit
	titleDeer.ZIndex = 11
	titleDeer.Parent = title
	applyDeerImage(titleDeer, IntroAssets.TitleDeerImage)

	makeLabel(title, "GameTitle", "67 NIGHTS", 64, CREAM, 0.58, 0, 72).Font = Enum.Font.GothamBlack
	makeLabel(title, "GameSubtitle", "IN THE FOREST", 28, MUTED, 0.58, 68, 36).Font = Enum.Font.Gotham

	local waiting = Instance.new("Frame")
	waiting.Name = "WaitingFrame"
	waiting.Size = UDim2.fromScale(1, 1)
	waiting.BackgroundColor3 = Color3.new(0, 0, 0)
	waiting.BorderSizePixel = 0
	waiting.Visible = false
	waiting.ZIndex = 20
	waiting.Parent = gui
	waitingFrame = waiting

	local waitingDeer = Instance.new("ImageLabel")
	waitingDeer.Name = "Deer"
	waitingDeer.AnchorPoint = Vector2.new(0.5, 0)
	waitingDeer.Position = UDim2.new(0.5, 0, 0, 24)
	waitingDeer.Size = UDim2.fromOffset(180, 180)
	waitingDeer.BackgroundTransparency = 1
	waitingDeer.ScaleType = Enum.ScaleType.Fit
	waitingDeer.ZIndex = 21
	waitingDeer.Parent = waiting
	applyDeerImage(waitingDeer, IntroAssets.WaitingDeerImage)

	makeLabel(waiting, "TheDeer", "THE DEER", 42, CREAM, 0, 200, 48)
	makeLabel(waiting, "WaitingText", "Waiting for players...", 22, MUTED, 0, 248, 28).Font = Enum.Font.Gotham

	local timer = Instance.new("TextLabel")
	timer.Name = "Timer"
	timer.BackgroundTransparency = 1
	timer.AnchorPoint = Vector2.new(0.5, 0.5)
	timer.Position = UDim2.fromScale(0.5, 0.52)
	timer.Size = UDim2.fromOffset(420, 120)
	timer.Font = Enum.Font.GothamBlack
	timer.TextSize = 96
	timer.TextColor3 = CREAM
	timer.Text = "59:59"
	timer.ZIndex = 22
	timer.Parent = waiting
	timerLabel = timer

	local start = Instance.new("TextButton")
	start.Name = "StartButton"
	start.AnchorPoint = Vector2.new(0.5, 1)
	start.Position = UDim2.new(0.5, 0, 1, -110)
	start.Size = UDim2.fromOffset(220, 52)
	start.BackgroundColor3 = GREEN
	start.BorderSizePixel = 0
	start.Font = Enum.Font.GothamBlack
	start.TextSize = 22
	start.TextColor3 = Color3.new(1, 1, 1)
	start.Text = "START"
	start.AutoButtonColor = true
	start.ZIndex = 23
	start.Parent = waiting
	local startCorner = Instance.new("UICorner")
	startCorner.CornerRadius = UDim.new(0, 6)
	startCorner.Parent = start
	startButton = start

	local roster = Instance.new("Frame")
	roster.Name = "Roster"
	roster.AnchorPoint = Vector2.new(0.5, 1)
	roster.Position = UDim2.new(0.5, 0, 1, -24)
	roster.Size = UDim2.fromOffset(360, 70)
	roster.BackgroundTransparency = 1
	roster.ZIndex = 23
	roster.Parent = waiting
	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Vertical
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.Padding = UDim.new(0, 4)
	list.Parent = roster
	rosterHolder = roster

	local day = Instance.new("Frame")
	day.Name = "DayFrame"
	day.Size = UDim2.fromScale(1, 1)
	day.BackgroundColor3 = Color3.new(0, 0, 0)
	day.BorderSizePixel = 0
	day.Visible = false
	day.ZIndex = 30
	day.Parent = gui
	dayFrame = day

	local dayLabel = Instance.new("TextLabel")
	dayLabel.Name = "DayText"
	dayLabel.BackgroundTransparency = 1
	dayLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	dayLabel.Position = UDim2.fromScale(0.5, 0.5)
	dayLabel.Size = UDim2.fromOffset(400, 90)
	dayLabel.Font = Enum.Font.Gotham
	dayLabel.TextSize = 54
	dayLabel.TextColor3 = CREAM
	dayLabel.Text = "Day 1"
	dayLabel.ZIndex = 31
	dayLabel.Parent = day
end

local function destroyTitle()
	if titleFrame then
		titleFrame:Destroy()
		titleFrame = nil
	end
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
	titleFrame = nil
	waitingFrame = nil
	dayFrame = nil
	timerLabel = nil
	startButton = nil
	rosterHolder = nil
end

local function dismissTitle()
	if titleDismissed or not titleFrame then
		return
	end
	titleDismissed = true
	fadeGui(titleFrame, 1, TITLE_FADE)
	task.delay(TITLE_FADE, function()
		destroyTitle()
	end)
end

local function playTitle()
	if not titleFrame then
		return
	end
	titleFrame.Visible = true
	setGroupTransparency(titleFrame, 1)
	titleFrame.BackgroundTransparency = 0
	fadeGui(titleFrame, 0, TITLE_FADE)
	titleFrame.BackgroundTransparency = 0

	janitor:Add(UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
			or input.KeyCode == Enum.KeyCode.Space
			or input.KeyCode == Enum.KeyCode.Return
		then
			dismissTitle()
		end
	end), "Disconnect")

	task.delay(TITLE_HOLD, dismissTitle)
end

local function renderRoster(roster: { { userId: number, name: string, isHost: boolean } })
	if not rosterHolder then
		return
	end
	for _, child in ipairs(rosterHolder:GetChildren()) do
		if child:IsA("TextLabel") then
			child:Destroy()
		end
	end
	for _, entry in ipairs(roster) do
		local row = Instance.new("TextLabel")
		row.BackgroundTransparency = 1
		row.Size = UDim2.new(1, 0, 0, 22)
		row.Font = Enum.Font.Gotham
		row.TextSize = 16
		row.TextColor3 = CREAM
		row.Text = if entry.isHost then entry.name .. "  (Host)" else entry.name
		row.ZIndex = 24
		row.Parent = rosterHolder
	end
end

local function startCountdownLoop()
	waitingJanitor:Cleanup()
	waitingJanitor:Add(RunService.RenderStepped:Connect(function()
		if not timerLabel or not countdownEndsAt then
			return
		end
		timerLabel.Text = formatTimer(countdownEndsAt - Workspace:GetServerTimeNow())
	end), "Disconnect")
end

local function showWaiting()
	if not waitingFrame then
		return
	end
	if titleFrame then
		dismissTitle()
	end
	waitingFrame.Visible = true
	setGroupTransparency(waitingFrame, 1)
	waitingFrame.BackgroundTransparency = 0
	fadeGui(waitingFrame, 0, WAITING_FADE)
	waitingFrame.BackgroundTransparency = 0
	lockMovement()
	lockCamera()
	startCountdownLoop()
end

local function showStarting()
	if waitingFrame then
		fadeGui(waitingFrame, 1, WAITING_FADE)
		task.delay(WAITING_FADE, function()
			if waitingFrame then
				waitingFrame.Visible = false
			end
		end)
	end
	if dayFrame then
		dayFrame.Visible = true
		setGroupTransparency(dayFrame, 1)
		dayFrame.BackgroundTransparency = 0
	end
	lockMovement()
	lockCamera()
	waitingJanitor:Cleanup()
end

local function finishIntro()
	if introFinished then
		return
	end
	introFinished = true
	unlockMovement()
	unlockCamera()
	if gameStateController then
		gameStateController:MarkIntroComplete()
	end
	destroyIntroGui()
end

local function showDayCard()
	if not dayFrame then
		finishIntro()
		return
	end
	dayFrame.Visible = true
	dayFrame.BackgroundTransparency = 0
	setGroupTransparency(dayFrame, 1)
	fadeGui(dayFrame, 0, DAY1_IN)
	dayFrame.BackgroundTransparency = 0
	task.delay(DAY1_IN + DAY1_HOLD, function()
		if not dayFrame then
			finishIntro()
			return
		end
		fadeGui(dayFrame, 1, DAY1_OUT)
		task.delay(DAY1_OUT, finishIntro)
	end)
end

-- // INITIALIZATION // --

function IntroController:KnitInit()
	buildGui()
end

function IntroController:KnitStart()
	gameStateController = Knit.GetController("GameStateController")
	local matchFlow = Knit.GetService("MatchFlowService")

	playTitle()

	if startButton then
		startButton.MouseButton1Click:Connect(function()
			if flowState ~= "Waiting" then
				return
			end
			matchFlow.RequestStart:Fire()
		end)
	end

	matchFlow.FlowStateChanged:Connect(function(state: string)
		if state == flowState then
			return
		end
		flowState = state
		if state == "Waiting" then
			showWaiting()
		elseif state == "Starting" then
			showStarting()
		elseif state == "InGame" then
			showDayCard()
		end
	end)

	matchFlow.Countdown:Connect(function(payload)
		if typeof(payload) == "table" and typeof(payload.endsAt) == "number" then
			countdownEndsAt = payload.endsAt
			if timerLabel then
				timerLabel.Text = formatTimer(payload.endsAt - Workspace:GetServerTimeNow())
			end
		end
	end)

	matchFlow.RosterChanged:Connect(function(roster)
		if typeof(roster) == "table" then
			renderRoster(roster)
		end
	end)

	print("[IntroController] Initialised")
end

return IntroController
