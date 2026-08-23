--[[
    @file    EndingController.luau
    @author  manik
    @date    2025

    @summary
    Day 67 victory and defeat presentation with final run statistics.
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

-- | State Management | --
local endingService: any = nil
local runStateService: any = nil
local gui: ScreenGui? = nil
local backdrop: Frame? = nil
local titleLabel: TextLabel? = nil
local subtitleLabel: TextLabel? = nil
local statsLabel: TextLabel? = nil

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
    @summary  Build the ending overlay once.
]]
local function buildUi()
	if gui then
		return
	end
	gui = Instance.new("ScreenGui")
	gui.Name = "EndingGui"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 100
	gui.Enabled = false
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	backdrop = Instance.new("Frame")
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Color3.fromRGB(5, 7, 9)
	backdrop.BackgroundTransparency = 1
	backdrop.BorderSizePixel = 0
	backdrop.Parent = gui

	titleLabel = Instance.new("TextLabel")
	titleLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	titleLabel.Position = UDim2.fromScale(0.5, 0.24)
	titleLabel.Size = UDim2.new(0.9, 0, 0, 78)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Font = Enum.Font.GothamBlack
	titleLabel.Text = "DAY 67 SURVIVED"
	titleLabel.TextColor3 = Color3.fromRGB(240, 220, 165)
	titleLabel.TextTransparency = 1
	titleLabel.TextScaled = true
	titleLabel.Parent = backdrop
	local titleConstraint = Instance.new("UITextSizeConstraint")
	titleConstraint.MaxTextSize = 52
	titleConstraint.MinTextSize = 25
	titleConstraint.Parent = titleLabel

	subtitleLabel = Instance.new("TextLabel")
	subtitleLabel.AnchorPoint = Vector2.new(0.5, 0)
	subtitleLabel.Position = UDim2.fromScale(0.5, 0.32)
	subtitleLabel.Size = UDim2.new(0.9, 0, 0, 36)
	subtitleLabel.BackgroundTransparency = 1
	subtitleLabel.Font = Enum.Font.Gotham
	subtitleLabel.TextColor3 = Color3.fromRGB(190, 190, 185)
	subtitleLabel.TextSize = 19
	subtitleLabel.TextTransparency = 1
	subtitleLabel.Parent = backdrop

	statsLabel = Instance.new("TextLabel")
	statsLabel.AnchorPoint = Vector2.new(0.5, 0)
	statsLabel.Position = UDim2.fromScale(0.5, 0.41)
	statsLabel.Size = UDim2.new(0.86, 0, 0.48, 0)
	statsLabel.BackgroundColor3 = Color3.fromRGB(18, 20, 22)
	statsLabel.BackgroundTransparency = 0.2
	statsLabel.Font = Enum.Font.Gotham
	statsLabel.TextColor3 = Color3.fromRGB(225, 225, 220)
	statsLabel.TextSize = 18
	statsLabel.TextWrapped = true
	statsLabel.TextYAlignment = Enum.TextYAlignment.Top
	statsLabel.Text = ""
	statsLabel.TextTransparency = 1
	statsLabel.Parent = backdrop
	local statsCorner = Instance.new("UICorner")
	statsCorner.CornerRadius = UDim.new(0, 12)
	statsCorner.Parent = statsLabel
end

--[[
    @summary  Show the shared victory or defeat title transition.
    @param    payload  table
]]
local function showEnding(payload)
	buildUi()
	gui.Enabled = true
	backdrop.BackgroundTransparency = 1
	titleLabel.TextTransparency = 1
	subtitleLabel.TextTransparency = 1
	statsLabel.TextTransparency = 1
	statsLabel.Text = ""
	titleLabel.Text = if payload.victory then "DAY 67 SURVIVED" else "THE FOREST CLAIMED THE TEAM"
	titleLabel.TextColor3 = if payload.victory then Color3.fromRGB(240, 220, 165) else Color3.fromRGB(220, 75, 70)
	subtitleLabel.Text = "Reached Day " .. tostring(payload.displayedDay or 1) .. " in " .. formatTime(payload.elapsedSeconds or 0)
	TweenService:Create(backdrop, TweenInfo.new(0.8), { BackgroundTransparency = 0.08 }):Play()
	TweenService:Create(titleLabel, TweenInfo.new(0.8), { TextTransparency = 0 }):Play()
	TweenService:Create(subtitleLabel, TweenInfo.new(1), { TextTransparency = 0 }):Play()
end

--[[
    @summary  Populate the personal result details.
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
	statsLabel.Text = table.concat({
		"RUN RESULTS",
		"",
		string.format("Displayed Day        %d / %d", result.displayedDay or 1, result.goalDay or 67),
		string.format("Real Nights          %d", result.cycleIndex or 1),
		string.format("Run Time             %s", formatTime(result.elapsedSeconds or 0)),
		string.format("Day Multiplier       %dx  (Beds +%d, Children +%d)", result.multiplier or 1, bedCount, childCount),
		string.format("Children Rescued     %d / 4", result.childrenRescued or 0),
		string.format("Structures Built     %d", result.structuresBuilt or 0),
		string.format("Trees Chopped        %d", result.treesChopped or 0),
		string.format("Wolves Defeated      %d", result.wolvesKilled or 0),
		string.format("Cultists Defeated    %d", result.cultistsKilled or 0),
		string.format("Revives / Downs      %d / %d", result.revives or 0, result.downs or 0),
		"",
		if result.recordSaved then "Lifetime records saved" else "Records will retry next run",
	}, "\n")
	TweenService:Create(statsLabel, TweenInfo.new(0.6), { TextTransparency = 0 }):Play()
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
			gui.Enabled = false
		end
	end)
end

return EndingController
