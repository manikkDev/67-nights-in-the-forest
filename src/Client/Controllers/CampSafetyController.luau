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
local TweenService = game:GetService("TweenService")

-- | Modules | --
local Knit = require(ReplicatedStorage.Packages.Knit)
local ServerRole = require(ReplicatedStorage.Shared.ServerRole)

-- | Objects | --
local CampSafetyController = Knit.CreateController({
	Name = "CampSafetyController",
})

-- | Configuration | --
local CHECK_INTERVAL = 0.25
local SAFE_TWEEN_INFO = TweenInfo.new(1.5, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
local UNSAFE_TWEEN_INFO = TweenInfo.new(0.8, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)

-- No ColorCorrection overlay — the "old movie" filter was ugly.
-- Night visibility is handled by the NightVisibilityLight (PointLight
-- on the character) and the server-side Lighting properties.

local NIGHT_VISIBILITY_COLOR = Color3.fromRGB(200, 210, 230)
local NIGHT_VISIBILITY_BRIGHTNESS = 0.8
local NIGHT_VISIBILITY_RANGE = 50

-- | State Management | --
local warningGui: ScreenGui? = nil
local warningLabel: TextLabel? = nil
local worldService: any = nil
local gameStateController: any = nil
local campfireService: any = nil
local timeService: any = nil
local campfirePosition: Vector3? = nil
local campfirePositionPending = false
local safeZoneRadius = 0
local isNight = false
local isFireActive = false
local currentState: "day" | "safeNight" | "unsafeNight" | "fireOut" = "day"
local currentWarningTween: Tween? = nil
local checkTimer = 0
local heartbeatConnection: RBXScriptConnection? = nil
local safeZoneChangedConnection: RBXScriptConnection? = nil
local gameStartedConnection: RBXScriptConnection? = nil
local visibilityLightConnection: RBXScriptConnection? = nil

-- // FUNCTIONS // --

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
	if currentWarningTween then
		currentWarningTween:Cancel()
		currentWarningTween = nil
	end
end

--[[
    @summary  Create or update a soft, invisible point light around the
              character so the player can see their immediate surroundings
              at night without a visible glowing circle.
    @param    enabled  boolean
]]
local function setVisibilityLight(enabled: boolean)
	local player = Players.LocalPlayer
	if not player then
		return
	end

	local character = player.Character
	if not character then
		return
	end

	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart or not rootPart:IsA("BasePart") then
		return
	end

	local light = rootPart:FindFirstChild("NightVisibilityLight")
	if not light or not light:IsA("PointLight") then
		light = Instance.new("PointLight")
		light.Name = "NightVisibilityLight"
		light.Color = NIGHT_VISIBILITY_COLOR
		light.Brightness = NIGHT_VISIBILITY_BRIGHTNESS
		light.Range = NIGHT_VISIBILITY_RANGE
		light.Shadows = false
		light.Parent = rootPart
	end

	light.Enabled = enabled
end

--[[
    @summary  Tween the screen and warning to the appropriate visual state.
]]
local function updateVisuals(state: "day" | "safeNight" | "unsafeNight" | "fireOut")
	if not warningLabel then
		return
	end
	if currentState == state then
		return
	end

	currentState = state
	cancelVisualTweens()

	local warningTrans = 1
	local warningText = nil
	local tweenInfo = SAFE_TWEEN_INFO

	if state == "safeNight" then
		warningTrans = 1
		tweenInfo = SAFE_TWEEN_INFO
		setVisibilityLight(true)
	elseif state == "unsafeNight" then
		warningText = "You are far from the firelight..."
		warningTrans = 0
		tweenInfo = UNSAFE_TWEEN_INFO
		setVisibilityLight(true)
	elseif state == "fireOut" then
		warningText = "The campfire has gone out..."
		warningTrans = 0
		tweenInfo = UNSAFE_TWEEN_INFO
		setVisibilityLight(true)
	else -- day
		warningTrans = 1
		tweenInfo = SAFE_TWEEN_INFO
		setVisibilityLight(false)
	end

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

	-- State variables (isNight, isFireActive, safeZoneRadius) are kept
	-- up-to-date by :Observe() callbacks on the ClientRemoteProperty objects.
	-- Do NOT poll :Get() here — it returns nil before the property has synced
	-- from the server, which would overwrite correct values with 0/false.

	if not isNight then
		updateVisuals("day")
		setVisibilityLight(false)
		return
	end

	if not campfirePosition or typeof(campfirePosition) ~= "Vector3" then
		if not campfirePositionPending then
			campfirePositionPending = true
			worldService:GetCampfirePosition():andThen(function(pos: Vector3?)
				if pos then
					campfirePosition = pos
				end
			end):catch(function() end):finally(function()
				campfirePositionPending = false
			end)
		end
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
	if not ServerRole.IsGameServer() then return end
	-- No ColorCorrection effect — removed the ugly "old movie" overlay.
	warningLabel = buildWarningLabel()
end

function CampSafetyController:KnitStart()
	if not ServerRole.IsGameServer() then return end
	gameStateController = Knit.GetController("GameStateController")
	worldService = Knit.GetService("WorldService")
	campfireService = Knit.GetService("CampfireService")
	timeService = Knit.GetService("TimeService")

	-- Use :Observe() on ClientRemoteProperty objects to keep local state
	-- authoritative. :Observe() fires the initial value once the property
	-- has synced from the server (via task.defer if already ready, or via
	-- Changed when the initial value arrives), and on every subsequent change.
	-- This replaces both :Get() polling and :Changed connections.
	if campfireService.SafeZoneRadius then
		campfireService.SafeZoneRadius:Observe(function(newValue: any)
			safeZoneRadius = newValue or 0
		end)
	end
	if campfireService.IsLit then
		campfireService.IsLit:Observe(function(newValue: any)
			isFireActive = newValue == true
		end)
	end
	if timeService.GetPhaseState then
		timeService.GetPhaseState:Observe(function(newValue: any)
			isNight = newValue == "Night"
			setVisibilityLight(isNight)
		end)
	end

	local localPlayer = Players.LocalPlayer
	if localPlayer then
		if visibilityLightConnection then
			visibilityLightConnection:Disconnect()
		end
		visibilityLightConnection = localPlayer.CharacterAdded:Connect(function()
			setVisibilityLight(isNight)
		end)
		if localPlayer.Character then
			setVisibilityLight(isNight)
		end
	end

	-- Keep the SafeZoneChanged signal as a backup for immediate updates
	-- when the server explicitly broadcasts a safe zone change.
	if safeZoneChangedConnection then
		safeZoneChangedConnection:Disconnect()
	end
	safeZoneChangedConnection = campfireService.SafeZoneChanged:Connect(function(radius, isActive)
		isFireActive = isActive == true
		safeZoneRadius = if isActive then radius or 0 else 0
	end)

	local function onGameStarted()
		-- ServicePromises is enabled, so GetCampfirePosition returns a Promise.
		worldService:GetCampfirePosition():andThen(function(pos: Vector3?)
			if pos then
				campfirePosition = pos
			end
		end):catch(function() end)
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

end

return CampSafetyController
