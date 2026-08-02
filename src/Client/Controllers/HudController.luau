--[[
    @file    HudController.luau
    @author  manik
    @date    2025

    @summary
    Binds DayLabel/NightLabel GUIs to the live TimeService clock.

    @description
    Creates TextLabels inside the existing DayLabel and NightLabel
    ScreenGuis in StarterGui, then listens to TimeService signals
    to toggle visibility and update the day/night counter text.

    @exports
    - HudController (Knit Controller)
]]

-- // VARIABLES // --

-- | Services | --
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")

-- | Modules | --
local Knit = require(ReplicatedStorage.Packages.Knit)

-- | Objects | --
local HudController = Knit.CreateController({
	Name = "HudController",
})

-- | State | --
local dayLabelGui: ScreenGui? = nil
local nightLabelGui: ScreenGui? = nil
local dayTextLabel: TextLabel? = nil
local nightTextLabel: TextLabel? = nil
local currentDayNumber = 1

-- // FUNCTIONS // --

--[[
    @summary  Create a TextLabel inside a ScreenGui for the phase indicator.
    @param   gui  ScreenGui  -- the parent ScreenGui
    @returns TextLabel
]]
local function createPhaseLabel(gui: ScreenGui): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = "PhaseText"
	label.Size = UDim2.new(0, 200, 0, 40)
	label.Position = UDim2.new(0, 20, 0, 20)
	label.BackgroundTransparency = 0.3
	label.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.Font = Enum.Font.GothamBold
	label.TextSize = 18
	label.Text = "Day 1"
	label.Visible = true
	label.Parent = gui
	return label
end

--[[
    @summary  Update the phase label text with the current day number.
    @param   phase  string  -- "Day" or "Night"
]]
local function updateLabelText(phase: string)
	local text = phase .. " " .. currentDayNumber
	if dayTextLabel then
		dayTextLabel.Text = text
	end
	if nightTextLabel then
		nightTextLabel.Text = text
	end
end

--[[
    @summary  Show the Day GUI, hide the Night GUI.
]]
local function showDay()
	if dayLabelGui then dayLabelGui.Enabled = true end
	if nightLabelGui then nightLabelGui.Enabled = false end
	if dayTextLabel then dayTextLabel.Visible = true end
	if nightTextLabel then nightTextLabel.Visible = false end
	updateLabelText("Day")
end

--[[
    @summary  Show the Night GUI, hide the Day GUI.
]]
local function showNight()
	if dayLabelGui then dayLabelGui.Enabled = false end
	if nightLabelGui then nightLabelGui.Enabled = true end
	if dayTextLabel then dayTextLabel.Visible = false end
	if nightTextLabel then nightTextLabel.Visible = true end
	updateLabelText("Night")
end

-- // INITIALIZATION // --

function HudController:KnitInit()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

	dayLabelGui = playerGui:WaitForChild("DayLabel")
	nightLabelGui = playerGui:WaitForChild("NightLabel")

	dayTextLabel = createPhaseLabel(dayLabelGui)
	nightTextLabel = createPhaseLabel(nightLabelGui)

	-- Start in Day phase
	showDay()
end

function HudController:KnitStart()
	local timeService = Knit.GetService("TimeService")

	timeService.DayStarted:Connect(function()
		currentDayNumber += 1
		showDay()
	end)

	timeService.NightStarted:Connect(function()
		showNight()
	end)

	-- Sync to current server state via the property
	local phaseState = timeService.GetPhaseState
	if phaseState then
		local currentPhase = phaseState.Value
		if currentPhase == "Night" then
			showNight()
		else
			showDay()
		end
	end

	print("[HudController] Initialised — bound to TimeService signals")
end

return HudController
