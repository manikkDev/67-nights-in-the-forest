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
local segments: { Part } = {}
local warningGui: ScreenGui? = nil
local warningFrame: Frame? = nil
local warningLabel: TextLabel? = nil
local proximityEffect: ColorCorrectionEffect? = nil
local updateTimer = 0
local warningVisible = false

local function segmentCount(): number
	return if UserInputService.TouchEnabled
		then WorldProgressionConfig.Boundary.MobileSegments
		else WorldProgressionConfig.Boundary.DesktopSegments
end

local function ensureVisuals()
	if visualFolder and visualFolder.Parent then
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = "LocalFogBoundary"
	folder.Parent = workspace
	visualFolder = folder

	local count = segmentCount()
	for index = 1, count do
		local part = Instance.new("Part")
		part.Name = "FogSegment" .. index
		part.Anchored = true
		part.CanCollide = false
		part.CanTouch = false
		part.CanQuery = false
		part.CastShadow = false
		part.Material = Enum.Material.ForceField
		part.Color = Color3.fromRGB(65, 70, 76)
		part.Transparency = 0.38
		part.Parent = folder
		if index % (if UserInputService.TouchEnabled then 4 else 3) == 0 then
			local fog = Instance.new("ParticleEmitter")
			fog.Name = "BoundaryMist"
			fog.Rate = if UserInputService.TouchEnabled then 2 else 4
			fog.Lifetime = NumberRange.new(3, 5)
			fog.Speed = NumberRange.new(0.4, 1.1)
			fog.SpreadAngle = Vector2.new(180, 30)
			fog.RotSpeed = NumberRange.new(-8, 8)
			fog.Rotation = NumberRange.new(0, 360)
			fog.Size = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 10),
				NumberSequenceKeypoint.new(0.5, 18),
				NumberSequenceKeypoint.new(1, 24),
			})
			fog.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.2, 0.55),
				NumberSequenceKeypoint.new(0.8, 0.7),
				NumberSequenceKeypoint.new(1, 1),
			})
			fog.Color = ColorSequence.new(Color3.fromRGB(105, 110, 118), Color3.fromRGB(45, 50, 58))
			fog.LightInfluence = 0.85
			fog.Parent = part
		end
		table.insert(segments, part)
	end
end

local function updateVisualRadius(radius: number, animated: boolean)
	if not campfirePosition then
		return
	end
	ensureVisuals()
	local count = #segments
	local height = WorldProgressionConfig.Boundary.Height
	local length = 2 * math.pi * radius / count + 10
	for index, part in ipairs(segments) do
		local angle = (index - 1) * 2 * math.pi / count
		local radial = Vector3.new(math.cos(angle), 0, math.sin(angle))
		local position = campfirePosition + radial * radius
		position = Vector3.new(position.X, campfirePosition.Y + height * 0.5 - 8, position.Z)
		local cframe = CFrame.lookAt(position, position - radial)
		local properties = {
			CFrame = cframe,
			Size = Vector3.new(length, height, 8),
		}
		if animated then
			TweenService:Create(part, TweenInfo.new(2.2, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), properties):Play()
		else
			part.CFrame = cframe
			part.Size = properties.Size
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
	setWarning(delta.Magnitude >= accessRadius - 65)
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
	RunService.Heartbeat:Connect(updateProximity)
end

return WorldBoundaryController
