--[[
    @file    WorldBoundaryController.luau
    @author  manik
    @date    2025

    @summary
    Client-side fog boundary visuals and proximity warning.

    @description
    Renders a realistic, moving fog wall at the current access radius
    using dense ParticleEmitters layered on dark semi-opaque panels.
    The fog drifts, swirls, and reacts to lighting so it feels alive.
    A warning HUD + ColorCorrection effect appear when the player
    approaches the boundary.
]]

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Knit = require(ReplicatedStorage.Packages.Knit)
local WorldProgressionConfig = require(ReplicatedStorage.Shared.WorldProgressionConfig)

local WorldBoundaryController = Knit.CreateController({
	Name = "WorldBoundaryController",
})

local worldService: any = nil
local progressionService: any = nil
local campfirePosition: Vector3? = nil
local accessRadius = WorldProgressionConfig.GetAccessRadius(1)
local visualFolder: Folder? = nil
local fogPanels: { Part } = {}
local fogEmitters: { ParticleEmitter } = {}
local warningGui: ScreenGui? = nil
local warningFrame: Frame? = nil
local warningLabel: TextLabel? = nil
local proximityEffect: ColorCorrectionEffect? = nil
local updateTimer = 0
local warningVisible = false
local windPhase = 0

local function segmentCount(): number
	return if UserInputService.TouchEnabled
		then WorldProgressionConfig.Boundary.MobileSegments
		else WorldProgressionConfig.Boundary.DesktopSegments
end

--[[
    @summary  Create the local fog visual folder, dark panels, and
              particle emitters that form the fog wall.
]]
local function ensureVisuals()
	if visualFolder and visualFolder.Parent then
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = "LocalFogBoundary"
	folder.Parent = workspace
	visualFolder = folder

	local count = segmentCount()
	local isMobile = UserInputService.TouchEnabled

	for index = 1, count do
		-- Dark semi-opaque panel that blocks vision through the fog wall.
		local panel = Instance.new("Part")
		panel.Name = "FogPanel" .. index
		panel.Anchored = true
		panel.CanCollide = false
		panel.CanTouch = false
		panel.CanQuery = false
		panel.CastShadow = false
		panel.Material = Enum.Material.SmoothPlastic
		panel.Color = Color3.fromRGB(22, 24, 28)
		panel.Transparency = 0.45
		panel.Parent = folder
		table.insert(fogPanels, panel)

		-- Dense fog particle emitter on every panel.
		local fog = Instance.new("ParticleEmitter")
		fog.Name = "BoundaryFog"
		fog.Rate = if isMobile then 10 else 18
		fog.Lifetime = NumberRange.new(4, 7)
		fog.Speed = NumberRange.new(0.8, 2.2)
		fog.SpreadAngle = Vector2.new(45, 25)
		fog.RotSpeed = NumberRange.new(-12, 12)
		fog.Rotation = NumberRange.new(0, 360)
		fog.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 14),
			NumberSequenceKeypoint.new(0.3, 26),
			NumberSequenceKeypoint.new(0.7, 38),
			NumberSequenceKeypoint.new(1, 50),
		})
		fog.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.15, 0.35),
			NumberSequenceKeypoint.new(0.5, 0.25),
			NumberSequenceKeypoint.new(0.85, 0.45),
			NumberSequenceKeypoint.new(1, 1),
		})
		fog.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(85, 90, 100)),
			ColorSequenceKeypoint.new(0.5, Color3.fromRGB(55, 60, 70)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(30, 34, 42)),
		})
		fog.LightInfluence = 0.6
		fog.Acceleration = Vector3.new(0, 0.5, 0)
		fog.Parent = panel
		table.insert(fogEmitters, fog)

		-- Secondary wispy mist layer for depth on every 3rd panel.
		if index % 3 == 0 and not isMobile then
			local mist = Instance.new("ParticleEmitter")
			mist.Name = "BoundaryMist"
			mist.Rate = 6
			mist.Lifetime = NumberRange.new(6, 10)
			mist.Speed = NumberRange.new(0.3, 0.9)
			mist.SpreadAngle = Vector2.new(180, 40)
			mist.RotSpeed = NumberRange.new(-5, 5)
			mist.Rotation = NumberRange.new(0, 360)
			mist.Size = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 30),
				NumberSequenceKeypoint.new(0.5, 55),
				NumberSequenceKeypoint.new(1, 70),
			})
			mist.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.2, 0.6),
				NumberSequenceKeypoint.new(0.8, 0.75),
				NumberSequenceKeypoint.new(1, 1),
			})
			mist.Color = ColorSequence.new(
				Color3.fromRGB(120, 125, 135),
				Color3.fromRGB(60, 65, 75)
			)
			mist.LightInfluence = 0.75
			mist.Acceleration = Vector3.new(0, 0.3, 0)
			mist.Parent = panel
		end
	end
end

--[[
    @summary  Position and size all fog panels/emitters around the
              campfire at the current access radius.
    @param    radius   number
    @param    animated boolean -- tween to new positions
]]
local function updateVisualRadius(radius: number, animated: boolean)
	if not campfirePosition then
		return
	end
	ensureVisuals()
	local count = #fogPanels
	local height = WorldProgressionConfig.Boundary.Height
	local length = 2 * math.pi * radius / count + 14
	for index, part in ipairs(fogPanels) do
		local angle = (index - 1) * 2 * math.pi / count
		local radial = Vector3.new(math.cos(angle), 0, math.sin(angle))
		local position = campfirePosition + radial * radius
		position = Vector3.new(position.X, campfirePosition.Y + height * 0.5 - 10, position.Z)
		local cframe = CFrame.lookAt(position, position - radial)
		local properties = {
			CFrame = cframe,
			Size = Vector3.new(length, height, 10),
		}
		if animated then
			TweenService:Create(part, TweenInfo.new(2.2, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), properties):Play()
		else
			part.CFrame = cframe
			part.Size = properties.Size
		end
	end
end

--[[
    @summary  Animate fog drift direction over time so the wall
              feels alive rather than static.
    @param    dt number
]]
local function animateFog(dt: number)
	windPhase += dt * 0.3
	local driftX = math.cos(windPhase) * 1.5
	local driftZ = math.sin(windPhase * 0.7) * 1.0
	for _, emitter in ipairs(fogEmitters) do
		if emitter and emitter.Parent then
			emitter.Acceleration = Vector3.new(driftX, 0.5, driftZ)
		end
	end
end

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
	worldService = Knit.GetService("WorldService")
	progressionService = Knit.GetService("WorldProgressionService")
	ensureWarning()
	worldService:GetCampfirePosition():andThen(function(position: Vector3?)
		campfirePosition = position
		updateVisualRadius(accessRadius, false)
	end)
	progressionService.AccessRadius:Observe(function(radius: number)
		if typeof(radius) == "number" then
			local animated = radius > accessRadius
			accessRadius = radius
			updateVisualRadius(radius, animated)
		end
	end)
	progressionService.BoundaryExpanded:Connect(function(_level: number, radius: number)
		accessRadius = radius
		updateVisualRadius(radius, true)
	end)
	RunService.Heartbeat:Connect(function(dt)
		animateFog(dt)
		updateProximity(dt)
	end)
end

return WorldBoundaryController
