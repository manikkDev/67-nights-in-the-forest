--[[
    @file    WorldBoundaryController.luau
    @author  manik
    @date    2025

    @summary
    Client-side boundary proximity warning.

    @description
    Fog wall visuals have been removed. The controller now only shows
    a warning HUD + ColorCorrection effect when the player approaches
    the boundary edge.
]]

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Knit = require(ReplicatedStorage.Packages.Knit)
local ServerRole = require(ReplicatedStorage.Shared.ServerRole)
local WorldProgressionConfig = require(ReplicatedStorage.Shared.WorldProgressionConfig)

local WorldBoundaryController = Knit.CreateController({
	Name = "WorldBoundaryController",
})

local worldService: any = nil
local progressionService: any = nil
local campfirePosition: Vector3? = nil
local accessRadius = WorldProgressionConfig.GetAccessRadius(1)
local warningGui: ScreenGui? = nil
local warningFrame: Frame? = nil
local warningLabel: TextLabel? = nil
local proximityEffect: ColorCorrectionEffect? = nil
local updateTimer = 0
local warningVisible = false

local function ensureWarning()
	if warningGui then
		return
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = "WorldBoundaryGui"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 18
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	local frame = Instance.new("Frame")
	frame.AnchorPoint = Vector2.new(0.5, 1)
	frame.Position = UDim2.new(0.5, 0, 0.9, 0)
	frame.Size = UDim2.new(0, 430, 0, 58)
	frame.BackgroundColor3 = Color3.fromRGB(25, 28, 34)
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
	frame.Visible = false
	frame.Parent = gui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = frame
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(130, 140, 155)
	stroke.Transparency = 1
	stroke.Thickness = 1.5
	stroke.Parent = frame

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, -24, 1, 0)
	label.Position = UDim2.new(0, 12, 0, 0)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextSize = 16
	label.TextWrapped = true
	label.TextColor3 = Color3.fromRGB(225, 230, 238)
	label.TextTransparency = 1
	label.Text = "The fog is too dense. Upgrade the campfire to clear a path."
	label.Parent = frame

	local effect = Instance.new("ColorCorrectionEffect")
	effect.Name = "BoundaryFogCorrection"
	effect.Brightness = 0
	effect.Contrast = 0
	effect.Saturation = 0
	effect.TintColor = Color3.new(1, 1, 1)
	effect.Parent = Lighting

	warningGui = gui
	warningFrame = frame
	warningLabel = label
	proximityEffect = effect
end

local function setWarning(visible: boolean)
	if visible == warningVisible then
		return
	end
	warningVisible = visible
	ensureWarning()
	if not warningFrame or not warningLabel or not proximityEffect then
		return
	end
	warningFrame.Visible = true
	local stroke = warningFrame:FindFirstChildOfClass("UIStroke")
	TweenService:Create(warningFrame, TweenInfo.new(0.35), { BackgroundTransparency = if visible then 0.08 else 1 }):Play()
	TweenService:Create(warningLabel, TweenInfo.new(0.35), { TextTransparency = if visible then 0 else 1 }):Play()
	TweenService:Create(proximityEffect, TweenInfo.new(0.45), {
		Brightness = if visible then -0.07 else 0,
		Contrast = if visible then 0.1 else 0,
		Saturation = if visible then -0.25 else 0,
		TintColor = if visible then Color3.fromRGB(195, 205, 215) else Color3.new(1, 1, 1),
	}):Play()
	if stroke then
		TweenService:Create(stroke, TweenInfo.new(0.35), { Transparency = if visible then 0.3 else 1 }):Play()
	end
	if not visible then
		task.delay(0.4, function()
			if warningFrame and not warningVisible then
				warningFrame.Visible = false
			end
		end)
	end
end

local function updateProximity(dt: number)
	updateTimer += dt
	if updateTimer < 0.15 then
		return
	end
	updateTimer = 0
	if not campfirePosition then
		return
	end
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		setWarning(false)
		return
	end
	local delta = Vector3.new(root.Position.X - campfirePosition.X, 0, root.Position.Z - campfirePosition.Z)
	setWarning(delta.Magnitude >= accessRadius - 50)
end

function WorldBoundaryController:KnitStart()
	if ServerRole.IsLobby() then return end
	worldService = Knit.GetService("WorldService")
	progressionService = Knit.GetService("WorldProgressionService")
	ensureWarning()
	worldService:GetCampfirePosition():andThen(function(position: Vector3?)
		campfirePosition = position
	end)
	progressionService.AccessRadius:Observe(function(radius: number)
		if typeof(radius) == "number" then
			accessRadius = radius
		end
	end)
	progressionService.BoundaryExpanded:Connect(function(_level: number, radius: number)
		accessRadius = radius
	end)
	RunService.Heartbeat:Connect(function(dt)
		updateProximity(dt)
	end)
end

return WorldBoundaryController
