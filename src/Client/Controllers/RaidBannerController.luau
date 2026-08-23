--[[
    @file    RaidBannerController.luau
    @author  manik
    @date    2025

    @summary
    Shows the Cultist raid warning/started/cleared banner.

    @description
    Builds its own ScreenGui (no pre-placed one exists for raids) and
    fades a centred banner in and out in response to
    CultistRaidService's signals.

    @exports
    - RaidBannerController (Knit Controller)
]]

-- // VARIABLES // --

-- | Services | --
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

-- | Modules | --
local Knit = require(ReplicatedStorage.Packages.Knit)

-- | Objects | --
local RaidBannerController = Knit.CreateController({
	Name = "RaidBannerController",
})

-- | Configuration | --
local FADE_IN_TIME = 0.4
local HOLD_TIME = 3.5
local FADE_OUT_TIME = 0.8
local WARNING_COLOR = Color3.fromRGB(200, 40, 40)
local CLEARED_COLOR = Color3.fromRGB(80, 200, 100)

-- | State Management | --
local screenGui: ScreenGui? = nil
local banner: TextLabel? = nil
local activeThread: thread? = nil

-- // FUNCTIONS // --

--[[
    @summary  Build the raid banner ScreenGui once.
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
	gui.Parent = playerGui

	local label = Instance.new("TextLabel")
	label.Name = "Banner"
	label.AnchorPoint = Vector2.new(0.5, 0)
	label.Position = UDim2.new(0.5, 0, 0.08, 0)
	label.Size = UDim2.new(0, 620, 0, 60)
	label.BackgroundColor3 = Color3.fromRGB(10, 10, 10)
	label.BackgroundTransparency = 0.25
	label.TextColor3 = WARNING_COLOR
	label.Font = Enum.Font.GothamBlack
	label.TextSize = 26
	label.TextTransparency = 1
	label.BackgroundTransparency = 1
	label.Text = ""
	label.Parent = gui

	screenGui = gui
	banner = label
end

--[[
    @summary  Fade the banner in, hold, then fade it out with the given text/color.
    @param    text   string
    @param    color  Color3
]]
local function showBanner(text: string, color: Color3)
	ensureGui()
	if not banner then
		return
	end

	if activeThread then
		task.cancel(activeThread)
	end

	activeThread = task.spawn(function()
		banner.Text = text
		banner.TextColor3 = color
		TweenService:Create(banner, TweenInfo.new(FADE_IN_TIME), {
			TextTransparency = 0,
			BackgroundTransparency = 0.25,
		}):Play()
		task.wait(FADE_IN_TIME + HOLD_TIME)
		TweenService:Create(banner, TweenInfo.new(FADE_OUT_TIME), {
			TextTransparency = 1,
			BackgroundTransparency = 1,
		}):Play()
		activeThread = nil
	end)
end

-- // INITIALIZATION // --

function RaidBannerController:KnitStart()
	local cultistRaidService = Knit.GetService("CultistRaidService")

	cultistRaidService.RaidWarning:Connect(function(_dayNumber: number)
		showBanner("Something evil is approaching your campfire... it arrives tonight.", WARNING_COLOR)
	end)

	cultistRaidService.RaidStarted:Connect(function(_dayNumber: number, cultistCount: number)
		showBanner(("Cultists are attacking the camp! (%d raiders)"):format(cultistCount), WARNING_COLOR)
	end)

	cultistRaidService.RaidCleared:Connect(function(_dayNumber: number)
		showBanner("The raid has been repelled.", CLEARED_COLOR)
	end)

end

return RaidBannerController
