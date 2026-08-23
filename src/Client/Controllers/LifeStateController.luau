--[[
    @file    LifeStateController.luau
    @author  manik
    @date    2025

    @summary
    Downed timer, teammate alerts, revive feedback, spectator camera,
    and reset-button protection for the managed life-state system.
]]

-- // VARIABLES // --

-- | Services | --
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local RunService = game:GetService("RunService")
local ContextActionService = game:GetService("ContextActionService")

-- | Modules | --
local Knit = require(ReplicatedStorage.Packages.Knit)
local Janitor = require(ReplicatedStorage.Packages.Janitor)

-- | Objects | --
local LifeStateController = Knit.CreateController({
	Name = "LifeStateController",
})
local janitor = Janitor.new()

-- | Configuration | --
local NEXT_ACTION = "SpectateNext"
local PREVIOUS_ACTION = "SpectatePrevious"

-- | State Management | --
local lifeService: any = nil
local gui: ScreenGui? = nil
local overlay: Frame? = nil
local titleLabel: TextLabel? = nil
local timerLabel: TextLabel? = nil
local hintLabel: TextLabel? = nil
local selfState = "Lobby"
local bleedOutAt = 0
local spectateIndex = 1

-- // FUNCTIONS // --

--[[
    @summary  Build the life-state overlay once.
]]
local function buildUi()
	if gui then
		return
	end
	gui = Instance.new("ScreenGui")
	gui.Name = "LifeStateGui"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.Enabled = false
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	overlay = Instance.new("Frame")
	overlay.Size = UDim2.fromScale(1, 1)
	overlay.BackgroundColor3 = Color3.fromRGB(45, 5, 8)
	overlay.BackgroundTransparency = 0.42
	overlay.BorderSizePixel = 0
	overlay.Parent = gui

	titleLabel = Instance.new("TextLabel")
	titleLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	titleLabel.Position = UDim2.fromScale(0.5, 0.4)
	titleLabel.Size = UDim2.new(0.9, 0, 0, 60)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Font = Enum.Font.GothamBlack
	titleLabel.Text = "YOU ARE DOWNED"
	titleLabel.TextColor3 = Color3.fromRGB(245, 225, 215)
	titleLabel.TextScaled = true
	titleLabel.Parent = overlay
	local titleConstraint = Instance.new("UITextSizeConstraint")
	titleConstraint.MaxTextSize = 40
	titleConstraint.MinTextSize = 20
	titleConstraint.Parent = titleLabel

	timerLabel = Instance.new("TextLabel")
	timerLabel.AnchorPoint = Vector2.new(0.5, 0)
	timerLabel.Position = UDim2.fromScale(0.5, 0.48)
	timerLabel.Size = UDim2.fromOffset(240, 48)
	timerLabel.BackgroundTransparency = 1
	timerLabel.Font = Enum.Font.GothamBlack
	timerLabel.Text = "45.0"
	timerLabel.TextColor3 = Color3.fromRGB(255, 90, 80)
	timerLabel.TextSize = 34
	timerLabel.Parent = overlay

	hintLabel = Instance.new("TextLabel")
	hintLabel.AnchorPoint = Vector2.new(0.5, 0)
	hintLabel.Position = UDim2.fromScale(0.5, 0.56)
	hintLabel.Size = UDim2.new(0.85, 0, 0, 52)
	hintLabel.BackgroundTransparency = 1
	hintLabel.Font = Enum.Font.Gotham
	hintLabel.Text = "A teammate needs a Bandage to revive you"
	hintLabel.TextColor3 = Color3.fromRGB(225, 215, 210)
	hintLabel.TextSize = 17
	hintLabel.TextWrapped = true
	hintLabel.Parent = overlay
end

--[[
    @summary  Return living teammates that can be spectated.
    @returns  { Player }
]]
local function livingTeammates(): { Player }
	local list = {}
	for _, player in ipairs(Players:GetPlayers()) do
		if player ~= Players.LocalPlayer
			and player.Character
			and player.Character:GetAttribute("LifeState") == "Alive"
		then
			table.insert(list, player)
		end
	end
	return list
end

--[[
    @summary  Set the camera to a living teammate at the current index.
]]
local function updateSpectatorCamera()
	local targets = livingTeammates()
	if #targets == 0 then
		return
	end
	spectateIndex = ((spectateIndex - 1) % #targets) + 1
	local humanoid = targets[spectateIndex].Character and targets[spectateIndex].Character:FindFirstChildOfClass("Humanoid")
	if humanoid and workspace.CurrentCamera then
		workspace.CurrentCamera.CameraType = Enum.CameraType.Custom
		workspace.CurrentCamera.CameraSubject = humanoid
	end
	if hintLabel then
		hintLabel.Text = "Spectating " .. targets[spectateIndex].DisplayName .. "  •  Q/E or shoulders to switch"
	end
end

--[[
    @summary  Restore the local character camera after revival or lobby return.
]]
local function restoreCamera()
	local humanoid = Players.LocalPlayer.Character and Players.LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
	if humanoid and workspace.CurrentCamera then
		workspace.CurrentCamera.CameraType = Enum.CameraType.Custom
		workspace.CurrentCamera.CameraSubject = humanoid
	end
	ContextActionService:UnbindAction(NEXT_ACTION)
	ContextActionService:UnbindAction(PREVIOUS_ACTION)
end

--[[
    @summary  Cycle the spectator target in one direction.
    @param    actionName  string
    @param    inputState  UserInputState
    @returns  ContextActionResult
]]
local function onSpectateAction(actionName: string, inputState: Enum.UserInputState): Enum.ContextActionResult
	if inputState ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Sink
	end
	spectateIndex += if actionName == NEXT_ACTION then 1 else -1
	updateSpectatorCamera()
	return Enum.ContextActionResult.Sink
end

--[[
    @summary  Apply one authoritative local life-state presentation.
    @param    state    string
    @param    payload  table
]]
local function applyState(state: string, payload)
	selfState = state
	buildUi()
	if state == "Downed" then
		bleedOutAt = payload.bleedOutAt or workspace:GetServerTimeNow()
		gui.Enabled = true
		overlay.BackgroundTransparency = 0.42
		titleLabel.Text = "YOU ARE DOWNED"
		hintLabel.Text = "A teammate needs a Bandage to revive you"
	elseif state == "Eliminated" then
		gui.Enabled = true
		overlay.BackgroundTransparency = 0.25
		titleLabel.Text = "YOU WERE LOST"
		timerLabel.Text = "SPECTATING"
		ContextActionService:BindAction(NEXT_ACTION, onSpectateAction, true, Enum.KeyCode.E, Enum.KeyCode.ButtonR1)
		ContextActionService:BindAction(PREVIOUS_ACTION, onSpectateAction, true, Enum.KeyCode.Q, Enum.KeyCode.ButtonL1)
		updateSpectatorCamera()
	else
		gui.Enabled = false
		bleedOutAt = 0
		restoreCamera()
	end
end

--[[
    @summary  Disable Roblox's direct reset path after CoreGui is ready.
]]
local function disableReset()
	for _ = 1, 20 do
		local ok = pcall(function()
			StarterGui:SetCore("ResetButtonCallback", false)
		end)
		if ok then
			return
		end
		task.wait(0.25)
	end
end

-- // INITIALIZATION // --

function LifeStateController:KnitStart()
	lifeService = Knit.GetService("PlayerLifeService")
	buildUi()
	task.spawn(disableReset)

	janitor:Add(lifeService.LifeStateChanged:Connect(function(payload)
		if typeof(payload) == "table" and payload.userId == Players.LocalPlayer.UserId then
			applyState(payload.state, payload)
		end
	end), "Disconnect")

	lifeService:GetSnapshot():andThen(function(snapshot)
		if typeof(snapshot) == "table" then
			applyState(snapshot.selfState or "Lobby", {})
		end
	end)

	janitor:Add(RunService.RenderStepped:Connect(function()
		if selfState == "Downed" and timerLabel then
			local remaining = math.max(0, bleedOutAt - workspace:GetServerTimeNow())
			timerLabel.Text = string.format("%.1f", remaining)
		end
	end), "Disconnect")
end

return LifeStateController
