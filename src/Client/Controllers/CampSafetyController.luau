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
local UNSAFE_BRIGHTNESS = -0.6
local UNSAFE_SATURATION = -0.5
local UNSAFE_TINT = Color3.fromRGB(40, 45, 60)

-- | State Management | --
local colorCorrection: ColorCorrectionEffect? = nil
local warningGui: ScreenGui? = nil
local warningLabel: TextLabel? = nil
local worldService: any = nil
local gameStateController: any = nil
local campfireService: any = nil
local timeService: any = nil
local campfirePosition: Vector3? = nil
local safeZoneRadius = 0
local isNight = false
local isFireActive = false
local currentState: "day" | "safeNight" | "unsafeNight" | "fireOut" = "day"
local currentCcTween: Tween? = nil
local currentWarningTween: Tween? = nil
local checkTimer = 0
local heartbeatConnection: RBXScriptConnection? = nil
local safeZoneChangedConnection: RBXScriptConnection? = nil
local gameStartedConnection: RBXScriptConnection? = nil
local phaseChangedConnection: RBXScriptConnection? = nil

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
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	if not playerGui then
		return Instance.new("TextLabel")
	end
	local existing = playerGui:FindFirstChild("CampSafetyGui")
	if existing then
		existing:Destroy()
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = "CampSafetyGui"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.Enabled = false
	gui.Parent = playerGui
	warningGui = gui

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

	local ccTween = TweenService:Create(colorCorrection, tweenInfo, ccTarget)
	ccTween:Play()
	currentCcTween = ccTween

	if warningText then
		warningLabel.Text = warningText
	end
	local warningTween = TweenService:Create(warningLabel, tweenInfo, { TextTransparency = warningTrans })
	warningTween:Play()
	currentWarningTween = warningTween
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

	-- Read the authoritative state from the server properties on every tick.
	-- This protects against missed signal events and guarantees the safe-zone
	-- radius, fire state, and day/night phase are always current — including
	-- when the campfire levels up and the radius changes.
	if timeService and timeService.GetPhaseState then
		isNight = timeService.GetPhaseState:Get() == "Night"
	end
	if campfireService then
		if campfireService.SafeZoneRadius then
			safeZoneRadius = campfireService.SafeZoneRadius:Get() or 0
		end
		if campfireService.IsLit then
			isFireActive = campfireService.IsLit:Get() == true
		end
	end

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
	gameStateController = Knit.GetController("GameStateController")
	worldService = Knit.GetService("WorldService")
	campfireService = Knit.GetService("CampfireService")
	timeService = Knit.GetService("TimeService")

	-- Fast path: update when the server explicitly tells us the safe zone changed.
	if safeZoneChangedConnection then
		safeZoneChangedConnection:Disconnect()
	end
	safeZoneChangedConnection = campfireService.SafeZoneChanged:Connect(function(radius, isActive)
		isFireActive = isActive == true
		safeZoneRadius = if isActive then radius or 0 else 0
	end)

	-- Property listeners keep the local state authoritative even if we miss
	-- a signal or join between broadcasts.
	if campfireService.IsLit and campfireService.IsLit.Changed then
		campfireService.IsLit.Changed:Connect(function(newValue: any)
			isFireActive = newValue == true
		end)
	end
	if campfireService.SafeZoneRadius and campfireService.SafeZoneRadius.Changed then
		campfireService.SafeZoneRadius.Changed:Connect(function(newValue: any)
			safeZoneRadius = newValue or 0
		end)
	end

	-- Fallback: request the current safe-zone state in case the initial signal
	-- was fired before this controller connected. Uses the correct client call
	-- syntax so the remote runs on the local player.
	local ok, radius, lit = pcall(function()
		return campfireService:GetSafeZoneInfo()
	end)
	if ok then
		isFireActive = lit == true
		safeZoneRadius = if isFireActive then radius or 0 else 0
	end

	-- Observe the authoritative phase property so the client can't get stuck
	-- in the wrong day/night state if a DayStarted/NightStarted event is missed.
	if phaseChangedConnection then
		phaseChangedConnection:Disconnect()
	end
	local phaseState = timeService.GetPhaseState
	if phaseState then
		isNight = phaseState:Get() == "Night"
		if phaseState.Changed then
			phaseChangedConnection = phaseState.Changed:Connect(function(newValue: any)
				isNight = newValue == "Night"
			end)
		end
	end

	local function onGameStarted()
		campfirePosition = worldService:GetCampfirePosition()
		if warningGui then
			warningGui.Enabled = true
		end
		if not heartbeatConnection then
			heartbeatConnection = RunService.Heartbeat:Connect(onHeartbeat)
		end
		task.defer(function()
			onHeartbeat(CHECK_INTERVAL)
		end)
	end

	if gameStateController and gameStateController:IsInGame() then
		onGameStarted()
	else
		if gameStartedConnection then
			gameStartedConnection:Disconnect()
		end
		if gameStateController then
			gameStartedConnection = gameStateController.GameStarted:Connect(onGameStarted)
		end
	end

	print("[CampSafetyController] Initialised — safe zone warning active")
end

return CampSafetyController
