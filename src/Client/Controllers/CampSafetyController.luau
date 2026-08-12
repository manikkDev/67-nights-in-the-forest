--[[
    @file    CampSafetyController.luau
    @author  manik
    @date    2025

    @summary
    Darkens the screen and warns the player when they stray outside the
    Campfire's safe zone at night.

    @description
    Tracks the Campfire's world position (via WorldService), the current
    safe-zone radius (via CampfireService.SafeZoneChanged), and the
    current day/night phase (via TimeService).  On a throttled Heartbeat
    loop, computes local distance to the campfire and tweens a
    ColorCorrectionEffect darker plus fades in a warning label whenever
    the player is outside the safe zone at night.

    @exports
    - CampSafetyController (Knit Controller)
]]

-- // VARIABLES // --

-- | Services | --
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")

-- | Modules | --
local Knit = require(ReplicatedStorage.Packages.Knit)

-- | Objects | --
local CampSafetyController = Knit.CreateController({
	Name = "CampSafetyController",
})

-- | Configuration | --
local CHECK_INTERVAL = 0.25
local SAFE_TWEEN_INFO = TweenInfo.new(1.5, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
local UNSAFE_TWEEN_INFO = TweenInfo.new(0.8, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
local SAFE_BRIGHTNESS = 0.12
local SAFE_TINT = Color3.fromRGB(255, 245, 235)
local UNSAFE_BRIGHTNESS = -0.2
local UNSAFE_SATURATION = -0.4
local UNSAFE_TINT = Color3.fromRGB(180, 190, 220)

-- | State Management | --
local colorCorrection: ColorCorrectionEffect? = nil
local warningLabel: TextLabel? = nil
local worldService: any? = nil
local campfirePosition: Vector3? = nil
local safeZoneRadius = 0
local isNight = false
local isFireActive = false
local currentState: "day" | "safeNight" | "unsafeNight" | "fireOut" = "day"
local currentCcTween: Tween? = nil
local currentWarningTween: Tween? = nil
local checkTimer = 0

-- // FUNCTIONS // --

--[[
    @summary  Create (or reuse) the ColorCorrectionEffect used for the
              unsafe-at-night darkening.
    @returns  ColorCorrectionEffect
]]
local function ensureColorCorrection(): ColorCorrectionEffect
	local existing = Lighting:FindFirstChild("SafetyColorCorrection")
	if existing and existing:IsA("ColorCorrectionEffect") then
		return existing
	end

	local effect = Instance.new("ColorCorrectionEffect")
	effect.Name = "SafetyColorCorrection"
	effect.Brightness = 0
	effect.Saturation = 0
	effect.TintColor = Color3.fromRGB(255, 255, 255)
	effect.Parent = Lighting
	return effect
end

--[[
    @summary  Create the "You are unsafe" warning label.
    @returns  TextLabel
]]
local function buildWarningLabel(): TextLabel
	local gui = Instance.new("ScreenGui")
	gui.Name = "CampSafetyGui"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true

	local label = Instance.new("TextLabel")
	label.Name = "WarningLabel"
	label.AnchorPoint = Vector2.new(0.5, 0)
	label.Position = UDim2.new(0.5, 0, 0, 40)
	label.Size = UDim2.new(0, 400, 0, 30)
	label.BackgroundTransparency = 1
	label.TextColor3 = Color3.fromRGB(230, 90, 90)
	label.Font = Enum.Font.GothamBold
	label.TextSize = 18
	label.Text = "You are far from the firelight..."
	label.TextTransparency = 1
	label.Parent = gui

	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	return label
end

--[[
    @summary  Cancel any running tweens so state changes don't fight each other.
]]
local function cancelVisualTweens()
	if currentCcTween then
		currentCcTween:Cancel()
		currentCcTween = nil
	end
	if currentWarningTween then
		currentWarningTween:Cancel()
		currentWarningTween = nil
	end
end

--[[
    @summary  Tween the screen and warning to the appropriate visual state.
]]
local function updateVisuals(state: "day" | "safeNight" | "unsafeNight" | "fireOut")
	if not colorCorrection or not warningLabel then
		return
	end
	if currentState == state then
		return
	end

	currentState = state
	cancelVisualTweens()

	local ccTarget = {}
	local warningTrans = 1
	local warningText = nil
	local tweenInfo = SAFE_TWEEN_INFO

	if state == "unsafeNight" then
		ccTarget = { Brightness = UNSAFE_BRIGHTNESS, Saturation = UNSAFE_SATURATION, TintColor = UNSAFE_TINT }
		warningText = "You are far from the firelight..."
		warningTrans = 0
		tweenInfo = UNSAFE_TWEEN_INFO
	elseif state == "fireOut" then
		ccTarget = { Brightness = UNSAFE_BRIGHTNESS, Saturation = UNSAFE_SATURATION, TintColor = UNSAFE_TINT }
		warningText = "The campfire has gone out..."
		warningTrans = 0
		tweenInfo = UNSAFE_TWEEN_INFO
	elseif state == "safeNight" then
		ccTarget = { Brightness = SAFE_BRIGHTNESS, Saturation = 0, TintColor = SAFE_TINT }
		warningTrans = 1
		tweenInfo = SAFE_TWEEN_INFO
	else -- day
		ccTarget = { Brightness = 0, Saturation = 0, TintColor = Color3.fromRGB(255, 255, 255) }
		warningTrans = 1
		tweenInfo = SAFE_TWEEN_INFO
	end

	currentCcTween = TweenService:Create(colorCorrection, tweenInfo, ccTarget)
	currentCcTween:Play()

	if warningText then
		warningLabel.Text = warningText
	end
	currentWarningTween = TweenService:Create(warningLabel, tweenInfo, { TextTransparency = warningTrans })
	currentWarningTween:Play()
end

--[[
    @summary  Throttled Heartbeat check: compare the local character's
              distance to the campfire against the current safe-zone
              radius, only while it's night.
    @param    dt  number  -- delta time in seconds
]]
local function onHeartbeat(dt: number)
	checkTimer += dt
	if checkTimer < CHECK_INTERVAL then
		return
	end
	checkTimer = 0

	if not isNight then
		updateVisuals("day")
		return
	end

	if not campfirePosition then
		campfirePosition = worldService:GetCampfirePosition()
	end
	if not campfirePosition then
		updateVisuals("fireOut")
		return
	end

	if not isFireActive then
		updateVisuals("fireOut")
		return
	end

	local character = Players.LocalPlayer.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	if not rootPart or not rootPart:IsA("BasePart") then
		return
	end

	local flatDist = (Vector3.new(rootPart.Position.X, 0, rootPart.Position.Z)
		- Vector3.new(campfirePosition.X, 0, campfirePosition.Z)).Magnitude

	if flatDist > safeZoneRadius then
		updateVisuals("unsafeNight")
	else
		updateVisuals("safeNight")
	end
end

-- // INITIALIZATION // --

function CampSafetyController:KnitInit()
	colorCorrection = ensureColorCorrection()
	warningLabel = buildWarningLabel()
end

function CampSafetyController:KnitStart()
	worldService = Knit.GetService("WorldService")
	local campfireService = Knit.GetService("CampfireService")
	local timeService = Knit.GetService("TimeService")

	campfirePosition = worldService:GetCampfirePosition()

	campfireService.SafeZoneChanged:Connect(function(radius, isActive)
		isFireActive = isActive
		safeZoneRadius = isActive and radius or 0
	end)

	-- Request the current safe-zone state in case the initial signal was
	-- fired before this controller connected.
	local ok, radius, lit = pcall(campfireService.GetSafeZoneInfo, campfireService)
	if ok then
		isFireActive = lit == true
		safeZoneRadius = if isFireActive then radius else 0
	end

	timeService.DayStarted:Connect(function()
		isNight = false
	end)
	timeService.NightStarted:Connect(function()
		isNight = true
	end)

	local phaseState = timeService.GetPhaseState
	if phaseState then
		isNight = phaseState.Value == "Night"
	end

	RunService.Heartbeat:Connect(onHeartbeat)

	-- Force an immediate state evaluation so the initial warning/darkness
	-- reflects the values we just fetched.
	task.defer(function()
		onHeartbeat(CHECK_INTERVAL)
	end)

	print("[CampSafetyController] Initialised — safe zone warning active")
end

return CampSafetyController
