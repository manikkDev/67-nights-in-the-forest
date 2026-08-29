--[[
    @file    LifeStateController.luau
    @author  manik
    @date    2025

    @summary
    Compact downed-state status, bleed-out timer, and reset protection.
    Spectator presentation is owned by SpectateController.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local RunService = game:GetService("RunService")

local Knit = require(ReplicatedStorage.Packages.Knit)
local ServerRole = require(ReplicatedStorage.Shared.ServerRole)
local Janitor = require(ReplicatedStorage.Packages.Janitor)

local LifeStateController = Knit.CreateController({ Name = "LifeStateController" })
local janitor = Janitor.new()
local localPlayer = Players.LocalPlayer

local lifeService: any = nil
local gui: ScreenGui? = nil
local card: Frame? = nil
local timerLabel: TextLabel? = nil
local selfState = "Lobby"
local bleedOutAt = 0

local function buildUi()
	if gui then return end
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "LifeStateGui"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = false
	screenGui.DisplayOrder = 45
	screenGui.Enabled = false
	screenGui.Parent = localPlayer:WaitForChild("PlayerGui")
	gui = screenGui

	local panel = Instance.new("Frame")
	panel.Name = "DownedCard"
	panel.AnchorPoint = Vector2.new(0.5, 1)
	panel.Position = UDim2.new(0.5, 0, 1, -34)
	panel.Size = UDim2.new(0.86, 0, 0, 104)
	panel.BackgroundColor3 = Color3.fromRGB(25, 16, 18)
	panel.BackgroundTransparency = 0.08
	panel.BorderSizePixel = 0
	panel.Parent = screenGui
	card = panel
	local size = Instance.new("UISizeConstraint")
	size.MaxSize = Vector2.new(440, 104)
	size.MinSize = Vector2.new(280, 96)
	size.Parent = panel
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = panel
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(165, 58, 55)
	stroke.Thickness = 1.5
	stroke.Transparency = 0.15
	stroke.Parent = panel

	local accent = Instance.new("Frame")
	accent.Size = UDim2.new(0, 4, 1, -20)
	accent.Position = UDim2.fromOffset(10, 10)
	accent.BackgroundColor3 = Color3.fromRGB(205, 66, 58)
	accent.BorderSizePixel = 0
	accent.Parent = panel
	local accentCorner = Instance.new("UICorner")
	accentCorner.CornerRadius = UDim.new(1, 0)
	accentCorner.Parent = accent

	local title = Instance.new("TextLabel")
	title.Position = UDim2.fromOffset(28, 14)
	title.Size = UDim2.new(1, -130, 0, 28)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBold
	title.Text = "YOU ARE DOWNED"
	title.TextColor3 = Color3.fromRGB(242, 226, 220)
	title.TextSize = 21
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Parent = panel

	local timer = Instance.new("TextLabel")
	timer.AnchorPoint = Vector2.new(1, 0)
	timer.Position = UDim2.new(1, -18, 0, 13)
	timer.Size = UDim2.fromOffset(82, 32)
	timer.BackgroundTransparency = 1
	timer.Font = Enum.Font.GothamBold
	timer.Text = "45.0s"
	timer.TextColor3 = Color3.fromRGB(235, 88, 76)
	timer.TextSize = 24
	timer.TextXAlignment = Enum.TextXAlignment.Right
	timer.Parent = panel
	timerLabel = timer

	local hint = Instance.new("TextLabel")
	hint.Position = UDim2.fromOffset(28, 49)
	hint.Size = UDim2.new(1, -48, 0, 38)
	hint.BackgroundTransparency = 1
	hint.Font = Enum.Font.GothamBold
	hint.Text = "Stay put — a teammate can revive you with one Bandage."
	hint.TextColor3 = Color3.fromRGB(185, 177, 174)
	hint.TextSize = 14
	hint.TextWrapped = true
	hint.TextXAlignment = Enum.TextXAlignment.Left
	hint.TextYAlignment = Enum.TextYAlignment.Top
	hint.Parent = panel
end

local function applyState(state: string, payload: any)
	selfState = state
	buildUi()
	if state == "Downed" then
		bleedOutAt = if typeof(payload) == "table" then payload.bleedOutAt or workspace:GetServerTimeNow() else workspace:GetServerTimeNow()
		if gui then gui.Enabled = true end
	else
		bleedOutAt = 0
		if gui then gui.Enabled = false end
	end
end

local function disableReset()
	for _ = 1, 20 do
		if pcall(function() StarterGui:SetCore("ResetButtonCallback", false) end) then return end
		task.wait(0.25)
	end
end

function LifeStateController:KnitStart()
	if ServerRole.IsLobby() then return end
	lifeService = Knit.GetService("PlayerLifeService")
	local runStateService = Knit.GetService("RunStateService")
	buildUi()
	task.spawn(disableReset)
	janitor:Add(lifeService.LifeStateChanged:Connect(function(payload)
		if typeof(payload) == "table" and payload.userId == localPlayer.UserId then
			applyState(payload.state, payload)
		end
	end), "Disconnect")
	janitor:Add(runStateService.RunPhaseChanged:Connect(function(payload)
		if typeof(payload) == "table" and (payload.phase == "Ending" or payload.phase == "Ended" or payload.phase == "Lobby") then
			if gui then gui.Enabled = false end
			if payload.phase == "Lobby" then selfState = "Lobby" end
		end
	end), "Disconnect")
	lifeService:GetSnapshot():andThen(function(snapshot)
		if typeof(snapshot) == "table" then applyState(snapshot.selfState or "Lobby", {}) end
	end)
	janitor:Add(RunService.RenderStepped:Connect(function()
		if selfState == "Downed" and timerLabel then
			timerLabel.Text = string.format("%.1fs", math.max(0, bleedOutAt - workspace:GetServerTimeNow()))
		end
	end), "Disconnect")
end

return LifeStateController
