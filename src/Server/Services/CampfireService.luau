--[[
    @file    CampfireService.luau
    @author  manik
    @date    2025

    @summary
    Server-authoritative campfire fuel level and dynamic fire visuals.

    @description
    Tracks a single shared Fuel value that drains over time.  Players
    can deposit their entire Wood inventory via a ProximityPrompt on
    the Campfire anchor, which is clamped server-side to their actual
    owned amount.  The Bonfire's built-in Fire effect and PointLight
    are scaled continuously to reflect the current fuel fraction, so
    the flame visibly shrinks toward embers as fuel depletes.

    @exports
    - CampfireService:GetFuel()           -> number
    - CampfireService:GetFuelFraction()   -> number
    - CampfireService:IsLit()             -> boolean
    - CampfireService:GetSafeZoneRadius() -> number
    - CampfireService:IsInSafeZone(pos)   -> boolean
    - Knit Signal: FuelChanged(fuel, fraction)              (server -> client)
    - Knit Signal: SafeZoneChanged(radius, isActive)        (server -> client)
    - Knit Remote: RequestFuelCampfire  -> void  (client -> server)
]]

-- // VARIABLES // --

-- | Services | --
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ProximityPromptService = game:GetService("ProximityPromptService")

-- | Modules | --
local Knit = require(ReplicatedStorage.Packages.Knit)

-- | Objects | --
local createSuccess, CampfireService = pcall(Knit.CreateService, {
	Name = "CampfireService",
	Client = {
		FuelChanged = Knit.CreateSignal(),
		SafeZoneChanged = Knit.CreateSignal(),
	},
})

if not createSuccess then
	-- Rojo hot-reload: grab the existing service and continue so the new code runs
	CampfireService = Knit.GetService("CampfireService") :: any
end

if not CampfireService.Client then
	CampfireService.Client = {}
end
if not CampfireService.Client.FuelChanged then
	CampfireService.Client.FuelChanged = Knit.CreateSignal()
end
if not CampfireService.Client.SafeZoneChanged then
	CampfireService.Client.SafeZoneChanged = Knit.CreateSignal()
end

-- | Configuration | --
local MAX_FUEL = 100
local FUEL_DRAIN_PER_SEC = 100 / 600
local WOOD_FUEL_VALUE = 20
local FEED_RANGE = 10
local FEED_COOLDOWN = 1
local FIRE_SIZE_MIN = 0.5
local FIRE_SIZE_MAX = 5
local FIRE_HEAT_MIN = 1
local FIRE_HEAT_MAX = 8
local LIGHT_RANGE_MIN = 6
local LIGHT_RANGE_MAX = 30
local LIGHT_BRIGHTNESS_MIN = 0.5
local LIGHT_BRIGHTNESS_MAX = 5
local FUEL_BROADCAST_INTERVAL = 1
local SAFE_ZONE_RADIUS_MIN = 12
local SAFE_ZONE_RADIUS_MAX = 35
local SAFE_ZONE_LINE_COUNT = 32
local SAFE_ZONE_LINE_THICKNESS = 0.2
local SAFE_ZONE_LINE_FILL = 0.8
local SAFE_ZONE_LINE_COLOR = Color3.fromRGB(255, 160, 40)
local SAFE_ZONE_LINE_MATERIAL = Enum.Material.Neon
local SAFE_ZONE_LINE_TRANSPARENCY = 0
local SAFE_ZONE_LINE_OFF_TRANSPARENCY = 1
local SAFE_ZONE_BROADCAST_THRESHOLD = 0.5

-- | State Management | --
local worldService: any? = nil
local playerDataService: any? = nil
local fuel = MAX_FUEL
local campfirePart: BasePart? = nil
local fireInstance: Fire? = nil
local pointLight: PointLight? = nil
local feedPrompt: ProximityPrompt? = nil
local feedCooldowns: { [Player]: number } = {}
local fuelBroadcastTimer = 0
local safeZoneDots: { Part }? = nil
local currentSafeZoneRadius = 0
local lastBroadcastRadius = 0

-- // FUNCTIONS // --

--[[
    @summary  Return the current fuel level.
    @returns  number  -- 0 to MAX_FUEL
]]
function CampfireService:GetFuel(): number
	return fuel
end

--[[
    @summary  Return the current fuel level as a 0-1 fraction.
    @returns  number
]]
function CampfireService:GetFuelFraction(): number
	return fuel / MAX_FUEL
end

--[[
    @summary  Return true if the campfire still has fuel remaining.
    @returns  boolean
]]
function CampfireService:IsLit(): boolean
	return fuel > 0
end

--[[
    @summary  Return the current safe zone radius in studs.
    @returns  number  -- 0 if fire is out, otherwise SAFE_ZONE_RADIUS_MIN..MAX
]]
function CampfireService:GetSafeZoneRadius(): number
	if fuel <= 0 then
		return 0
	end
	return currentSafeZoneRadius
end

--[[
    @summary  Check whether a world position is inside the safe zone.
    @param    position  Vector3  -- the position to test
    @returns  boolean
]]
function CampfireService:IsInSafeZone(position: Vector3): boolean
	if fuel <= 0 or not campfirePart then
		return false
	end
	local flatDist = (Vector3.new(position.X, 0, position.Z) - Vector3.new(campfirePart.Position.X, 0, campfirePart.Position.Z)).Magnitude
	return flatDist <= currentSafeZoneRadius
end

--[[
    @summary  Locate the Bonfire's Fire effect and PointLight, and
              wire the Feed ProximityPrompt onto the campfire anchor.
              Retries until WorldService has finished placing the
              campfire and bonfire.
]]
local function setupCampfire()
	if not worldService then
		task.defer(setupCampfire)
		return
	end

	local bonfire = worldService:GetBonfire()
	local anchor = worldService:GetCampfire()
	if not bonfire or not anchor then
		task.defer(setupCampfire)
		return
	end

	campfirePart = anchor :: BasePart
	if not campfirePart then
		return
	end

	local firePart = bonfire:FindFirstChild("Fire", true)
	if firePart then
		fireInstance = firePart:FindFirstChildOfClass("Fire")
	end

	for _, descendant in ipairs(bonfire:GetDescendants()) do
		if descendant:IsA("PointLight") then
			pointLight = descendant
			break
		end
	end

	-- Reuse an existing feed prompt if this is a hot reload
	local existingPrompt = campfirePart:FindFirstChild("FeedFirePrompt")
	if existingPrompt and existingPrompt:IsA("ProximityPrompt") then
		feedPrompt = existingPrompt
	else
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "FeedFirePrompt"
		prompt.ActionText = "Feed Fire"
		prompt.ObjectText = "Campfire"
		prompt.MaxActivationDistance = FEED_RANGE + 2
		prompt.HoldDuration = 0.3
		prompt.Parent = campfirePart
		feedPrompt = prompt
	end

	-- Remove any old safe zone visuals (disc or previous dots) before creating fresh dots
	local map = bonfire.Parent
	local oldFolder = map and map:FindFirstChild("SafeZoneDots")
	if oldFolder then
		oldFolder:Destroy()
	end
	local oldDisc = map and map:FindFirstChild("SafeZone")
	if oldDisc then
		oldDisc:Destroy()
	end

	-- Create the safe zone visual: a dashed ring of slim glowing lines around the campfire
	local dotFolder = Instance.new("Folder")
	dotFolder.Name = "SafeZoneDots"
	dotFolder.Parent = map

	local dots = {}
	for i = 1, SAFE_ZONE_LINE_COUNT do
		local dot = Instance.new("Part")
		dot.Name = "SafeZoneLine" .. i
		dot.Shape = Enum.PartType.Cylinder
		dot.Anchored = true
		dot.CanCollide = false
		dot.CanQuery = false
		dot.CanTouch = false
		dot.Material = SAFE_ZONE_LINE_MATERIAL
		dot.Color = SAFE_ZONE_LINE_COLOR
		dot.Transparency = SAFE_ZONE_LINE_OFF_TRANSPARENCY
		dot.Size = Vector3.new(SAFE_ZONE_LINE_THICKNESS, 1, SAFE_ZONE_LINE_THICKNESS)
		dot.CastShadow = false
		dot.Parent = dotFolder
		table.insert(dots, dot)
	end

	safeZoneDots = dots

	currentSafeZoneRadius = SAFE_ZONE_RADIUS_MIN

	print("[CampfireService] Campfire wired — fuel:", fuel)
end

--[[
    @summary  Position/orient the slim glowing line segments as a dashed ring
              around the campfire with the given radius and active state.
    @param    radius   number   -- ring radius in studs
    @param    active   boolean  -- whether the ring is visible
]]
local function updateSafeZoneVisuals(radius: number, active: boolean)
	if not safeZoneDots or not campfirePart then
		return
	end

	local groundY = campfirePart.Position.Y + 0.05
	local transparency = active and SAFE_ZONE_LINE_TRANSPARENCY or SAFE_ZONE_LINE_OFF_TRANSPARENCY
	local circumference = 2 * math.pi * radius
	local lineLength = (circumference / SAFE_ZONE_LINE_COUNT) * SAFE_ZONE_LINE_FILL

	for i, dot in ipairs(safeZoneDots) do
		local angle = (i - 1) * (2 * math.pi / SAFE_ZONE_LINE_COUNT)
		local normal = Vector3.new(math.cos(angle), 0, math.sin(angle))
		local tangent = Vector3.new(-math.sin(angle), 0, math.cos(angle))
		local binormal = Vector3.new(0, 1, 0):Cross(tangent).Unit
		local position = Vector3.new(
			campfirePart.Position.X + normal.X * radius,
			groundY,
			campfirePart.Position.Z + normal.Z * radius
		)

		dot.CFrame = CFrame.fromMatrix(position, binormal, tangent)
		dot.Size = Vector3.new(SAFE_ZONE_LINE_THICKNESS, lineLength, SAFE_ZONE_LINE_THICKNESS)
		dot.Transparency = transparency
	end
end

--[[
    @summary  Validate and process a feed request, depositing all of
              the player owned Wood into the campfire's fuel.
    @param    player  Player  -- the feeding player
]]
local function feedCampfire(player: Player)
	if not campfirePart then
		return
	end

	local now = os.clock()
	if feedCooldowns[player] and (now - feedCooldowns[player]) < FEED_COOLDOWN then
		return
	end

	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	if not rootPart or not rootPart:IsA("BasePart") then
		return
	end

	if (rootPart.Position - campfirePart.Position).Magnitude > FEED_RANGE then
		return
	end

	local dataService = playerDataService :: any
	local data = dataService:GetData(player)
	if not data or data.Resources.Wood <= 0 then
		return
	end

	feedCooldowns[player] = now
	local wood = data.Resources.Wood

	dataService:UpdateData(player, function(playerData)
		playerData.Resources.Wood = 0
	end)

	fuel = math.clamp(fuel + wood * WOOD_FUEL_VALUE, 0, MAX_FUEL)
	local fraction = fuel / MAX_FUEL

	-- Immediately update safe zone and broadcast
	local newRadius = SAFE_ZONE_RADIUS_MIN + (SAFE_ZONE_RADIUS_MAX - SAFE_ZONE_RADIUS_MIN) * fraction
	currentSafeZoneRadius = newRadius

	updateSafeZoneVisuals(newRadius, fuel > 0)

	print("[CampfireService]", player.Name, "fed", wood, "wood — fuel now", fuel)
end

--[[
    @summary  Route a global ProximityPrompt trigger to the feed
              handler if it matches the campfire's prompt.
    @param    prompt  ProximityPrompt  -- the triggered prompt
    @param    player  Player           -- the triggering player
]]
local function onPromptTriggered(prompt: ProximityPrompt, player: Player)
	if prompt == feedPrompt then
		feedCampfire(player)
	end
end


--[[
    @summary  Heartbeat-driven fuel drain and visual scaling.
    @param    dt  number  -- delta time in seconds
]]
local function onHeartbeat(dt: number)
	fuel = math.clamp(fuel - FUEL_DRAIN_PER_SEC * dt, 0, MAX_FUEL)
	local fraction = fuel / MAX_FUEL

	if fireInstance then
		fireInstance.Size = FIRE_SIZE_MIN + (FIRE_SIZE_MAX - FIRE_SIZE_MIN) * fraction
		fireInstance.Heat = FIRE_HEAT_MIN + (FIRE_HEAT_MAX - FIRE_HEAT_MIN) * fraction
	end

	if pointLight then
		pointLight.Range = LIGHT_RANGE_MIN + (LIGHT_RANGE_MAX - LIGHT_RANGE_MIN) * fraction
		pointLight.Brightness = LIGHT_BRIGHTNESS_MIN + (LIGHT_BRIGHTNESS_MAX - LIGHT_BRIGHTNESS_MIN) * fraction
	end

	-- Update safe zone radius and visual
	local newRadius = SAFE_ZONE_RADIUS_MIN + (SAFE_ZONE_RADIUS_MAX - SAFE_ZONE_RADIUS_MIN) * fraction
	currentSafeZoneRadius = newRadius

	updateSafeZoneVisuals(newRadius, fuel > 0)

	fuelBroadcastTimer += dt
	if fuelBroadcastTimer >= FUEL_BROADCAST_INTERVAL then
		fuelBroadcastTimer = 0

		-- Broadcast safe zone changes when radius shifts by >= threshold
		if math.abs(newRadius - lastBroadcastRadius) >= SAFE_ZONE_BROADCAST_THRESHOLD then
			lastBroadcastRadius = newRadius
		end
	end
end

--[[
    @summary  Client-facing remote requesting the campfire be fed.
    @param    player  Player  -- injected by Knit
]]
function CampfireService.Client:RequestFuelCampfire(player: Player)
	self.Server:_FeedCampfire(player)
end

--[[
    @summary  Internal server-only wrapper so both the Knit remote and
              the ProximityPrompt handler share one code path.
    @param    player  Player  -- the feeding player
]]
function CampfireService:_FeedCampfire(player: Player)
	feedCampfire(player)
end

-- // INITIALIZATION // --

function CampfireService:KnitStart()
	worldService = Knit.GetService("WorldService")
	playerDataService = Knit.GetService("PlayerDataService")

	setupCampfire()
	CampfireService._HeartbeatConnection = RunService.Heartbeat:Connect(onHeartbeat)
	CampfireService._PromptConnection = ProximityPromptService.PromptTriggered:Connect(onPromptTriggered)

	print("[CampfireService] Initialised — fuel drain active")
end

-- Rojo hot-reload path: if the service already existed, the new module's KnitStart
-- won't be called by Knit, so run setup and wire events directly.
if not createSuccess then
	worldService = Knit.GetService("WorldService")
	playerDataService = Knit.GetService("PlayerDataService")

	if CampfireService._HeartbeatConnection then
		CampfireService._HeartbeatConnection:Disconnect()
	end
	if CampfireService._PromptConnection then
		CampfireService._PromptConnection:Disconnect()
	end

	setupCampfire()
	CampfireService._HeartbeatConnection = RunService.Heartbeat:Connect(onHeartbeat)
	CampfireService._PromptConnection = ProximityPromptService.PromptTriggered:Connect(onPromptTriggered)

	print("[CampfireService] Hot-reloaded — dotted safe zone wired")
end

Players.PlayerRemoving:Connect(function(player)
	feedCooldowns[player] = nil
end)

return CampfireService
