--[[
    @file    RaidBannerController.luau
    @author  manik
    @date    2025

    @summary
    Full cultist raid UI: warning banners, cinematic cutscene, raid tracker.

    @description
    Listens to CultistRaidService signals and renders a multi-stage UI:

    1. Day-before warning — red flashing banner at top-center.
    2. Pre-night warning — more urgent red flashing banner.
    3. Cinematic cutscene — full-screen dark overlay with parchment-style
       text card that slides in and fades out.
    4. Raid tracker HUD — persistent top-center panel showing remaining
       enemy count and a total health bar; updates in real-time.
    5. Raid cleared / failed banners.

    All transitions use TweenService for smooth animation and follow the
    established dark UI design language (GothamBlack/GothamBold, UICorner,
    UIStroke, solid opaque backgrounds).

    @exports
    - RaidBannerController (Knit Controller)
]]

-- // VARIABLES // --

-- | Services | --
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

-- | Modules | --
local Knit = require(ReplicatedStorage.Packages.Knit)

-- | Objects | --
local RaidBannerController = Knit.CreateController({
	Name = "RaidBannerController",
})

-- | Configuration | --
local WARNING_COLOR = Color3.fromRGB(220, 50, 50)
local CLEARED_COLOR = Color3.fromRGB(80, 200, 100)
local FAILED_COLOR = Color3.fromRGB(220, 60, 50)
local PARCHMENT_COLOR = Color3.fromRGB(28, 22, 30)
local PANEL_BG = Color3.fromRGB(38, 38, 46)
local TRACKER_BG = Color3.fromRGB(20, 18, 26)

-- | State Management | --
local screenGui: ScreenGui? = nil
local warningBanner: Frame? = nil
local warningLabel: TextLabel? = nil
local warningPulseThread: thread? = nil
local cutsceneOverlay: Frame? = nil
local trackerPanel: Frame? = nil
local trackerCountLabel: TextLabel? = nil
local trackerFill: Frame? = nil
local trackerThread: thread? = nil
local cutsceneThread: thread? = nil
local raidActive = false

-- // FUNCTIONS // --

-- | GUI Construction | --

--[[
    @summary  Build the raid UI ScreenGui and all sub-components once.
]]
local function ensureGui()
	if screenGui then
		return
	end
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

	local gui = Instance.new("ScreenGui")
	gui.Name = "RaidBanner"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 50
	gui.Parent = playerGui
	screenGui = gui

	-- === Warning Banner ===
	local wb = Instance.new("Frame")
	wb.Name = "WarningBanner"
	wb.AnchorPoint = Vector2.new(0.5, 0)
	wb.Position = UDim2.new(0.5, 0, 0.06, 0)
	wb.Size = UDim2.new(0, 640, 0, 54)
	wb.BackgroundColor3 = Color3.fromRGB(60, 12, 12)
	wb.BackgroundTransparency = 1
	wb.Visible = false
	wb.Parent = gui

	local wbCorner = Instance.new("UICorner")
	wbCorner.CornerRadius = UDim.new(0, 10)
	wbCorner.Parent = wb

	local wbStroke = Instance.new("UIStroke")
	wbStroke.Color = WARNING_COLOR
	wbStroke.Transparency = 1
	wbStroke.Thickness = 2
	wbStroke.Parent = wb

	local wl = Instance.new("TextLabel")
	wl.Name = "Label"
	wl.Size = UDim2.new(1, -24, 1, 0)
	wl.Position = UDim2.new(0, 12, 0, 0)
	wl.BackgroundTransparency = 1
	wl.Font = Enum.Font.GothamBlack
	wl.TextSize = 20
	wl.TextColor3 = WARNING_COLOR
	wl.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	wl.TextStrokeTransparency = 0.3
	wl.TextTransparency = 1
	wl.Text = ""
	wl.Parent = wb

	warningBanner = wb
	warningLabel = wl

	-- === Cinematic Cutscene Overlay ===
	local co = Instance.new("Frame")
	co.Name = "CutsceneOverlay"
	co.Size = UDim2.new(1, 0, 1, 0)
	co.BackgroundColor3 = Color3.fromRGB(8, 6, 12)
	co.BackgroundTransparency = 1
	co.Visible = false
	co.Active = false
	co.Parent = gui

	-- Parchment-style card
	local card = Instance.new("Frame")
	card.Name = "Card"
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position = UDim2.new(0.5, 0, 0.5, 0)
	card.Size = UDim2.new(0, 560, 0, 180)
	card.BackgroundColor3 = PARCHMENT_COLOR
	card.BackgroundTransparency = 1
	card.Parent = co

	local cardCorner = Instance.new("UICorner")
	cardCorner.CornerRadius = UDim.new(0, 14)
	cardCorner.Parent = card

	local cardStroke = Instance.new("UIStroke")
	cardStroke.Color = Color3.fromRGB(120, 80, 100)
	cardStroke.Transparency = 1
	cardStroke.Thickness = 2
	cardStroke.Parent = card

	local cardPad = Instance.new("UIPadding")
	cardPad.PaddingTop = UDim.new(0, 28)
	cardPad.PaddingBottom = UDim.new(0, 28)
	cardPad.PaddingLeft = UDim.new(0, 32)
	cardPad.PaddingRight = UDim.new(0, 32)
	cardPad.Parent = card

	local cutTitle = Instance.new("TextLabel")
	cutTitle.Name = "Title"
	cutTitle.Size = UDim2.new(1, 0, 0, 50)
	cutTitle.Position = UDim2.new(0, 0, 0, 0)
	cutTitle.BackgroundTransparency = 1
	cutTitle.Font = Enum.Font.GothamBlack
	cutTitle.TextSize = 26
	cutTitle.TextColor3 = Color3.fromRGB(230, 220, 210)
	cutTitle.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	cutTitle.TextStrokeTransparency = 0.4
	cutTitle.TextTransparency = 1
	cutTitle.Text = "A mysterious group approaches your campfire..."
	cutTitle.Parent = card

	local cutSub = Instance.new("TextLabel")
	cutSub.Name = "Subtitle"
	cutSub.Size = UDim2.new(1, 0, 0, 28)
	cutSub.Position = UDim2.new(0, 0, 0, 58)
	cutSub.BackgroundTransparency = 1
	cutSub.Font = Enum.Font.GothamBold
	cutSub.TextSize = 16
	cutSub.TextColor3 = Color3.fromRGB(200, 80, 80)
	cutSub.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	cutSub.TextStrokeTransparency = 0.4
	cutSub.TextTransparency = 1
	cutSub.Text = ""
	cutSub.Parent = card

	cutsceneOverlay = co

	-- === Raid Tracker HUD ===
	local tp = Instance.new("Frame")
	tp.Name = "TrackerPanel"
	tp.AnchorPoint = Vector2.new(0.5, 0)
	tp.Position = UDim2.new(0.5, 0, 0.06, 0)
	tp.Size = UDim2.new(0, 360, 0, 72)
	tp.BackgroundColor3 = TRACKER_BG
	tp.BackgroundTransparency = 1
	tp.Visible = false
	tp.Parent = gui

	local tpCorner = Instance.new("UICorner")
	tpCorner.CornerRadius = UDim.new(0, 12)
	tpCorner.Parent = tp

	local tpStroke = Instance.new("UIStroke")
	tpStroke.Color = WARNING_COLOR
	tpStroke.Transparency = 1
	tpStroke.Thickness = 2
	tpStroke.Parent = tp

	local tpPad = Instance.new("UIPadding")
	tpPad.PaddingTop = UDim.new(0, 10)
	tpPad.PaddingBottom = UDim.new(0, 10)
	tpPad.PaddingLeft = UDim.new(0, 16)
	tpPad.PaddingRight = UDim.new(0, 16)
	tpPad.Parent = tp

	-- Layout: title row + bar row
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.Padding = UDim.new(0, 6)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Parent = tp

	-- Title + count row
	local titleRow = Instance.new("Frame")
	titleRow.Name = "TitleRow"
	titleRow.Size = UDim2.new(1, 0, 0, 22)
	titleRow.BackgroundTransparency = 1
	titleRow.Parent = tp

	local titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "Title"
	titleLabel.Size = UDim2.new(0.5, 0, 1, 0)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Font = Enum.Font.GothamBlack
	titleLabel.TextSize = 16
	titleLabel.TextColor3 = WARNING_COLOR
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.Text = "CULTIST RAID"
	titleLabel.Parent = titleRow

	trackerCountLabel = Instance.new("TextLabel")
	trackerCountLabel.Name = "Count"
	trackerCountLabel.Size = UDim2.new(0.5, 0, 1, 0)
	trackerCountLabel.Position = UDim2.new(0.5, 0, 0, 0)
	trackerCountLabel.BackgroundTransparency = 1
	trackerCountLabel.Font = Enum.Font.GothamBold
	trackerCountLabel.TextSize = 15
	trackerCountLabel.TextColor3 = Color3.fromRGB(230, 230, 235)
	trackerCountLabel.TextXAlignment = Enum.TextXAlignment.Right
	trackerCountLabel.Text = "Enemies: 0 / 0"
	trackerCountLabel.Parent = titleRow

	-- Health bar row
	local barRow = Instance.new("Frame")
	barRow.Name = "BarRow"
	barRow.Size = UDim2.new(1, 0, 0, 16)
	barRow.BackgroundColor3 = Color3.fromRGB(15, 12, 18)
	barRow.BackgroundTransparency = 1
	barRow.Parent = tp

	local barCorner = Instance.new("UICorner")
	barCorner.CornerRadius = UDim.new(0, 6)
	barCorner.Parent = barRow

	local barStroke = Instance.new("UIStroke")
	barStroke.Color = Color3.fromRGB(80, 60, 60)
	barStroke.Transparency = 1
	barStroke.Thickness = 1
	barStroke.Parent = barRow

	trackerFill = Instance.new("Frame")
	trackerFill.Name = "Fill"
	trackerFill.Size = UDim2.new(1, 0, 1, 0)
	trackerFill.BackgroundColor3 = Color3.fromRGB(220, 50, 50)
	trackerFill.BackgroundTransparency = 1
	trackerFill.BorderSizePixel = 0
	trackerFill.Parent = barRow

	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0, 6)
	fillCorner.Parent = trackerFill

	trackerPanel = tp
end

-- | Warning Banner | --

--[[
    @summary  Show the warning banner with pulsing red animation.
    @param    text       string
    @param    urgent     boolean  -- faster pulse if true
]]
local function showWarningBanner(text: string, urgent: boolean?)
	ensureGui()
	if not warningBanner or not warningLabel then
		return
	end

	-- Cancel any existing pulse loop
	if warningPulseThread then
		task.cancel(warningPulseThread)
	end

	warningLabel.Text = text
	warningBanner.Visible = true

	-- Fade in
	TweenService:Create(warningBanner, TweenInfo.new(0.3), {
		BackgroundTransparency = 0.1,
	}):Play()
	TweenService:Create(warningLabel, TweenInfo.new(0.3), {
		TextTransparency = 0,
	}):Play()
	local stroke = warningBanner:FindFirstChildOfClass("UIStroke")
	if stroke then
		TweenService:Create(stroke, TweenInfo.new(0.3), {
			Transparency = 0.3,
		}):Play()
	end

	-- Pulsing loop
	local pulseSpeed = if urgent then 0.5 else 0.9
	warningPulseThread = task.spawn(function()
		local dir = 1
		local t = 0
		while true do
			t += RunService.Heartbeat:Wait() * (1 / pulseSpeed)
			if t >= 1 then
				t = 0
				dir = -dir
			end
			local alpha = if dir == 1 then t else (1 - t)
			local transparency = 0.1 + alpha * 0.35
			if warningBanner then
				warningBanner.BackgroundTransparency = transparency
			end
		end
	end)
end

--[[
    @summary  Hide the warning banner with fade-out.
]]
local function hideWarningBanner()
	if not warningBanner or not warningLabel then
		return
	end
	if warningPulseThread then
		task.cancel(warningPulseThread)
		warningPulseThread = nil
	end
	TweenService:Create(warningBanner, TweenInfo.new(0.5), {
		BackgroundTransparency = 1,
	}):Play()
	TweenService:Create(warningLabel, TweenInfo.new(0.5), {
		TextTransparency = 1,
	}):Play()
	local stroke = warningBanner:FindFirstChildOfClass("UIStroke")
	if stroke then
		TweenService:Create(stroke, TweenInfo.new(0.5), {
			Transparency = 1,
		}):Play()
	end
	task.delay(0.6, function()
		if warningBanner then
			warningBanner.Visible = false
		end
	end)
end

-- | Cinematic Cutscene | --

--[[
    @summary  Play the cinematic cutscene overlay with slide-in text.
    @param    dayNumber  number
    @param    count      number
]]
local function playCutscene(dayNumber: number, count: number)
	ensureGui()
	if not cutsceneOverlay then
		return
	end

	if cutsceneThread then
		task.cancel(cutsceneThread)
	end

	local card = cutsceneOverlay:FindFirstChild("Card")
	local title = card and card:FindFirstChild("Title") :: TextLabel?
	local sub = card and card:FindFirstChild("Subtitle") :: TextLabel?
	local cardStroke = card and card:FindFirstChildOfClass("UIStroke")

	cutsceneOverlay.Visible = true
	cutsceneOverlay.BackgroundTransparency = 1
	if card then
		card.BackgroundTransparency = 1
		card.Position = UDim2.new(0.5, 0, 0.5, 30)
	end
	if title then
		title.TextTransparency = 1
		title.Text = "A mysterious group approaches your campfire..."
	end
	if sub then
		sub.TextTransparency = 1
		sub.Text = string.format("Night %d  —  %d Cultists Incoming", dayNumber, count)
	end

	cutsceneThread = task.spawn(function()
		-- Fade in overlay
		TweenService:Create(cutsceneOverlay, TweenInfo.new(0.5), {
			BackgroundTransparency = 0.6,
		}):Play()

		-- Slide card in from below + fade in
		if card then
			TweenService:Create(card, TweenInfo.new(0.6, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
				BackgroundTransparency = 0.05,
				Position = UDim2.new(0.5, 0, 0.5, 0),
			}):Play()
		end
		if cardStroke then
			TweenService:Create(cardStroke, TweenInfo.new(0.6), {
				Transparency = 0.2,
			}):Play()
		end

		task.wait(0.3)
		if title then
			TweenService:Create(title, TweenInfo.new(0.5), {
				TextTransparency = 0,
			}):Play()
		end
		task.wait(0.4)
		if sub then
			TweenService:Create(sub, TweenInfo.new(0.5), {
				TextTransparency = 0,
			}):Play()
		end

		-- Hold
		task.wait(2.8)

		-- Fade out
		if title then
			TweenService:Create(title, TweenInfo.new(0.5), { TextTransparency = 1 }):Play()
		end
		if sub then
			TweenService:Create(sub, TweenInfo.new(0.5), { TextTransparency = 1 }):Play()
		end
		task.wait(0.3)
		if card then
			TweenService:Create(card, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
				BackgroundTransparency = 1,
				Position = UDim2.new(0.5, 0, 0.5, -30),
			}):Play()
		end
		if cardStroke then
			TweenService:Create(cardStroke, TweenInfo.new(0.6), { Transparency = 1 }):Play()
		end
		TweenService:Create(cutsceneOverlay, TweenInfo.new(0.6), {
			BackgroundTransparency = 1,
		}):Play()

		task.wait(0.7)
		if cutsceneOverlay then
			cutsceneOverlay.Visible = false
		end
		cutsceneThread = nil
	end)
end

-- | Raid Tracker HUD | --

--[[
    @summary  Show the raid tracker panel with slide-in animation.
]]
local function showTracker()
	ensureGui()
	if not trackerPanel then
		return
	end
	trackerPanel.Visible = true
	trackerPanel.Position = UDim2.new(0.5, 0, 0.06, -80)

	TweenService:Create(trackerPanel, TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Position = UDim2.new(0.5, 0, 0.06, 0),
		BackgroundTransparency = 0,
	}):Play()

	local stroke = trackerPanel:FindFirstChildOfClass("UIStroke")
	if stroke then
		TweenService:Create(stroke, TweenInfo.new(0.5), { Transparency = 0.3 }):Play()
	end

	-- Fade in fill bar
	if trackerFill then
		TweenService:Create(trackerFill, TweenInfo.new(0.5), { BackgroundTransparency = 0 }):Play()
	end

	-- Fade in the bar background
	local barRow = trackerPanel:FindFirstChild("BarRow")
	if barRow then
		TweenService:Create(barRow, TweenInfo.new(0.5), { BackgroundTransparency = 0 }):Play()
		local barStroke = barRow:FindFirstChildOfClass("UIStroke")
		if barStroke then
			TweenService:Create(barStroke, TweenInfo.new(0.5), { Transparency = 0.3 }):Play()
		end
	end
end

--[[
    @summary  Hide the raid tracker panel with slide-out animation.
]]
local function hideTracker()
	if not trackerPanel then
		return
	end
	TweenService:Create(trackerPanel, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		Position = UDim2.new(0.5, 0, 0.06, -80),
		BackgroundTransparency = 1,
	}):Play()

	local stroke = trackerPanel:FindFirstChildOfClass("UIStroke")
	if stroke then
		TweenService:Create(stroke, TweenInfo.new(0.5), { Transparency = 1 }):Play()
	end

	if trackerFill then
		TweenService:Create(trackerFill, TweenInfo.new(0.5), { BackgroundTransparency = 1 }):Play()
	end

	local barRow = trackerPanel:FindFirstChild("BarRow")
	if barRow then
		TweenService:Create(barRow, TweenInfo.new(0.5), { BackgroundTransparency = 1 }):Play()
	end

	task.delay(0.6, function()
		if trackerPanel then
			trackerPanel.Visible = false
		end
	end)
end

--[[
    @summary  Update the tracker HUD with current raid status.
    @param    remaining     number
    @param    total         number
    @param    healthRatio   number  (0–1)
]]
local function updateTracker(remaining: number, total: number, healthRatio: number)
	if not trackerCountLabel or not trackerFill then
		return
	end
	trackerCountLabel.Text = string.format("Enemies: %d / %d", remaining, total)

	local clamped = math.clamp(healthRatio, 0, 1)
	-- Color: bright red at full, dark red at empty
	local color = Color3.fromRGB(220, 50, 50):Lerp(Color3.fromRGB(80, 20, 20), 1 - clamped)
	TweenService:Create(trackerFill, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = UDim2.new(clamped, 0, 1, 0),
		BackgroundColor3 = color,
	}):Play()
end

-- | Simple Banner (cleared / failed) | --

--[[
    @summary  Show a simple fade-in/hold/fade-out banner for raid results.
    @param    text   string
    @param    color  Color3
]]
local function showResultBanner(text: string, color: Color3)
	ensureGui()
	if not warningBanner or not warningLabel then
		return
	end

	if warningPulseThread then
		task.cancel(warningPulseThread)
		warningPulseThread = nil
	end

	warningLabel.Text = text
	warningLabel.TextColor3 = color
	warningBanner.BackgroundColor3 = Color3.fromRGB(20, 20, 26)
	warningBanner.Visible = true

	TweenService:Create(warningBanner, TweenInfo.new(0.4), {
		BackgroundTransparency = 0.1,
	}):Play()
	TweenService:Create(warningLabel, TweenInfo.new(0.4), {
		TextTransparency = 0,
	}):Play()
	local stroke = warningBanner:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = color
		TweenService:Create(stroke, TweenInfo.new(0.4), { Transparency = 0.3 }):Play()
	end

	task.delay(3.5, function()
		TweenService:Create(warningBanner, TweenInfo.new(0.6), {
			BackgroundTransparency = 1,
		}):Play()
		TweenService:Create(warningLabel, TweenInfo.new(0.6), {
			TextTransparency = 1,
		}):Play()
		if stroke then
			TweenService:Create(stroke, TweenInfo.new(0.6), { Transparency = 1 }):Play()
		end
		task.delay(0.7, function()
			if warningBanner then
				warningBanner.Visible = false
			end
			-- Reset color for next use
			if warningLabel then
				warningLabel.TextColor3 = WARNING_COLOR
			end
		end)
	end)
end

-- // INITIALIZATION // --

function RaidBannerController:KnitStart()
	local cultistRaidService = Knit.GetService("CultistRaidService")

	cultistRaidService.RaidWarning:Connect(function(_dayNumber: number, phase: string)
		if phase == "preNight" then
			showWarningBanner("You will be attacked tonight — return to your campfire!", true)
		else
			showWarningBanner("Something evil is approaching your campfire... it arrives tonight.", false)
		end
	end)

	cultistRaidService.RaidStarted:Connect(function(dayNumber: number, cultistCount: number)
		raidActive = true
		-- Hide the warning banner
		hideWarningBanner()
		-- Play cinematic cutscene
		playCutscene(dayNumber, cultistCount)
		-- Show tracker after cutscene begins (slightly delayed so they overlap)
		task.delay(1.5, function()
			if raidActive then
				showTracker()
				updateTracker(cultistCount, cultistCount, 1.0)
			end
		end)
	end)

	cultistRaidService.RaidStatusUpdate:Connect(function(remaining: number, total: number, healthRatio: number)
		if raidActive then
			updateTracker(remaining, total, healthRatio)
		end
	end)

	cultistRaidService.RaidCleared:Connect(function(_dayNumber: number)
		raidActive = false
		hideTracker()
		showResultBanner("The raid has been repelled.", CLEARED_COLOR)
	end)

	cultistRaidService.RaidFailed:Connect(function(_dayNumber: number, survivors: number)
		raidActive = false
		hideTracker()
		showResultBanner(string.format("Some cultists are still alive near your fire. (%d survived)", survivors), FAILED_COLOR)
	end)
end

return RaidBannerController
