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
local notifFrame: Frame? = nil
local notifLabel: TextLabel? = nil
local notifJanitor = Janitor.new()
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
	-- Teammate downed notification banner (top-center)
	local notif = Instance.new("Frame")
	notif.Name = "TeammateDowned"
	notif.AnchorPoint = Vector2.new(0.5, 0)
	notif.Position = UDim2.new(0.5, 0, 0, 14)
	notif.Size = UDim2.new(0.55, 0, 0, 36)
	notif.BackgroundColor3 = Color3.fromRGB(42, 32, 12)
	notif.BackgroundTransparency = 1
	notif.BorderSizePixel = 0
	notif.Visible = false
	notif.Parent = screenGui
	local nc = Instance.new("UISizeConstraint")
	nc.MaxSize = Vector2.new(380, 36)
	nc.Parent = notif
	local ncorner = Instance.new("UICorner")
	ncorner.CornerRadius = UDim.new(0, 10)
	ncorner.Parent = notif
	local nstroke = Instance.new("UIStroke")
	nstroke.Color = Color3.fromRGB(195, 148, 55)
	nstroke.Thickness = 1
	nstroke.Transparency = 0.2
	nstroke.Parent = notif
	local nlabel = Instance.new("TextLabel")
	nlabel.Size = UDim2.fromScale(1, 1)
	nlabel.BackgroundTransparency = 1
	nlabel.Font = Enum.Font.GothamBold
	nlabel.Text = ""
	nlabel.TextColor3 = Color3.fromRGB(235, 178, 70)
	nlabel.TextSize = 14
	nlabel.TextTransparency = 1
	nlabel.Parent = notif
	notifFrame = notif
	notifLabel = nlabel
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
	if not ServerRole.IsGameServer() then return end
	lifeService = Knit.GetService("PlayerLifeService")
	local runStateService = Knit.GetService("RunStateService")
	buildUi()
	task.spawn(disableReset)
	-- Teammate downed/revived notification
	local function showDownedNotification(displayName: string, state: string)
		if not notifFrame or not notifLabel then return end
		local TweenService = game:GetService("TweenService")
		notifJanitor:Cleanup()
		local text = if state == "Downed"
			then ("⚠ " .. displayName .. " is DOWNED!")
			else ("✓ " .. displayName .. " was revived")
		local color = if state == "Downed"
			then Color3.fromRGB(235, 178, 70)
			else Color3.fromRGB(90, 200, 110)
		notifLabel.Text = text
		notifLabel.TextColor3 = color
		notifFrame.Visible = true
		notifFrame.BackgroundTransparency = 1
		notifLabel.TextTransparency = 1
		TweenService:Create(notifFrame, TweenInfo.new(0.25, Enum.EasingStyle.Quad), { BackgroundTransparency = 0.1 }):Play()
		TweenService:Create(notifLabel, TweenInfo.new(0.25), { TextTransparency = 0 }):Play()
		local t = task.delay(4.0, function()
			TweenService:Create(notifFrame, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { BackgroundTransparency = 1 }):Play()
			TweenService:Create(notifLabel, TweenInfo.new(0.4), { TextTransparency = 1 }):Play()
			task.delay(0.45, function()
				if notifFrame then notifFrame.Visible = false end
			end)
		end)
		notifJanitor:Add(function() task.cancel(t) end)
	end

	janitor:Add(lifeService.LifeStateChanged:Connect(function(payload)
		if typeof(payload) ~= "table" then return end
		if payload.userId == localPlayer.UserId then
			applyState(payload.state, payload)
		else
			-- Notify the local player when a teammate goes down or gets revived
			if payload.state == "Downed" or payload.state == "Alive" then
				local teammate = Players:GetPlayerByUserId(payload.userId)
				local name = teammate and teammate.DisplayName or tostring(payload.userId)
				showDownedNotification(name, payload.state)
			end
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
