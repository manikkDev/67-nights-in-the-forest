--[[
    @file    CampfireService.luau
    @author  manik
    @date    2025

    @summary
    Server-authoritative campfire fuel, level-up, and dynamic fire visuals.

    @description
    Tracks a shared campfire Level (1-6) and a current Fuel value that
    drains over time. Players feed the fire by dropping Wood near the
    Campfire anchor; each log adds both current
    fuel and progress toward the next campfire level. Every level raises
    the campfire's max fuel, safe-zone radius, fire size/light range, and
    slows fuel drain. If Fuel reaches 0 the fire goes out, the safe zone
    disappears, and a warning is broadcast.

    @exports
    - CampfireService:GetFuel()            -> number
    - CampfireService:GetFuelLimit()       -> number
    - CampfireService:GetFuelFraction()    -> number
    - CampfireService:GetLevel()           -> number
    - CampfireService:GetLevelProgress()   -> number, number, number
    - CampfireService:IsLit()              -> boolean
    - CampfireService:GetSafeZoneRadius()  -> number
    - CampfireService:IsInSafeZone(pos)    -> boolean
    - Knit Signal: FuelChanged(fuel, maxFuel, fraction, isLit)
    - Knit Signal: LevelChanged(level, progress, requirement, levelFraction)
    - Knit Signal: SafeZoneChanged(radius, isActive)
    - Knit Remote: RequestFuelCampfire(amount)
    - Knit Remote: GetState() -> fuel, maxFuel, level, progress, requirement, isLit
]]

-- // VARIABLES // --

-- | Services | --
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")

-- | Modules | --
local Knit = require(ReplicatedStorage.Packages.Knit)
local ServerRole = require(ReplicatedStorage.Shared.ServerRole)
local Signal = require(ReplicatedStorage.Packages.Signal)
local WorldProgressionConfig = require(ReplicatedStorage.Shared.WorldProgressionConfig)

-- | Objects | --
local createSuccess, CampfireService = pcall(Knit.CreateService, {
	Name = "CampfireService",
	Client = {
		FuelChanged = Knit.CreateSignal(),
		LevelChanged = Knit.CreateSignal(),
		SafeZoneChanged = Knit.CreateSignal(),
		LevelUp = Knit.CreateSignal(),
		SafeZoneRadius = Knit.CreateProperty(0),
		IsLit = Knit.CreateProperty(false),
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
if not CampfireService.Client.LevelChanged then
	CampfireService.Client.LevelChanged = Knit.CreateSignal()
end
if not CampfireService.Client.SafeZoneChanged then
	CampfireService.Client.SafeZoneChanged = Knit.CreateSignal()
end
if not CampfireService.Client.LevelUp then
	CampfireService.Client.LevelUp = Knit.CreateSignal()
end
if not CampfireService.Client.SafeZoneRadius then
	CampfireService.Client.SafeZoneRadius = Knit.CreateProperty(0)
end
if not CampfireService.Client.IsLit then
	CampfireService.Client.IsLit = Knit.CreateProperty(false)
end

CampfireService.LevelChangedServer = CampfireService.LevelChangedServer or Signal.new()

-- | Configuration | --
local FEED_RANGE = 10
local FEED_COOLDOWN = 1
local WOOD_FUEL_VALUE = 25
local WOOD_LEVEL_VALUE_BASE = 10

local MAX_FUEL_BY_LEVEL = { 100, 140, 190, 250, 320, 400 }
local SAFE_ZONE_RADIUS_BY_LEVEL = WorldProgressionConfig.SafeZoneRadiusByLevel
local FUEL_DRAIN_BASE = 100 / 600
local FUEL_DRAIN_MULTIPLIER_BY_LEVEL = { 1.0, 0.9, 0.82, 0.75, 0.68, 0.6 }
local LEVEL_REQUIREMENTS = { 50, 100, 180, 300, 450, 450 }

local FIRE_SIZE_MIN = 0.5
local FIRE_SIZE_MAX = 12
local FIRE_SIZE_LEVEL_MULTIPLIER = { 0.85, 1.0, 1.08, 1.16, 1.24, 1.4 }
local FIRE_HEAT_MIN = 1
local FIRE_HEAT_MAX = 10
local LIGHT_RANGE_MIN = 6
local LIGHT_RANGE_MAX = 120
local LIGHT_RANGE_LEVEL_MULTIPLIER = { 0.85, 1.0, 1.08, 1.16, 1.24, 1.4 }
local LIGHT_BRIGHTNESS_MIN = 0.8
local LIGHT_BRIGHTNESS_MAX = 2
local FUEL_BROADCAST_INTERVAL = 1
local SAFE_ZONE_LINE_COUNT = 40
local SAFE_ZONE_LINE_THICKNESS = 0.8
local SAFE_ZONE_LINE_HEIGHT = 0.05
local SAFE_ZONE_LINE_FILL = 0.65
local SAFE_ZONE_LINE_COLOR = Color3.fromRGB(220, 255, 220)
local SAFE_ZONE_LINE_MATERIAL = Enum.Material.Neon
local SAFE_ZONE_LINE_TRANSPARENCY = 0
local SAFE_ZONE_LINE_OFF_TRANSPARENCY = 1
local SAFE_ZONE_BROADCAST_THRESHOLD = 0.5
local LOG_SCAN_INTERVAL = 0.2
local LOG_SCAN_RADIUS = 14

-- | State Management | --
local worldService: any = nil
local inventoryService: any = nil
local spawnService: any = nil
local runStateService: any = nil
local playerLifeService: any = nil
local level = 1
local levelProgress = 0
local maxFuel = MAX_FUEL_BY_LEVEL[1]
local fuel = 0
local isLit = false
local campfirePart: BasePart? = nil
local fireCenter: BasePart? = nil
local groundPart: BasePart? = nil
local fireInstance: Fire? = nil
local pointLight: PointLight? = nil
local feedCooldowns: { [Player]: number } = {}
local fuelBroadcastTimer = 0
local logScanTimer = 0
local safeZoneDots: { Part }? = nil
local currentSafeZoneRadius = 0
local lastBroadcastRadius = 0

-- // FUNCTIONS // --

--[[
    @summary  Return the current fuel level.
    @returns  number
]]
function CampfireService:GetFuel(): number
	return fuel
end

--[[
    @summary  Return the current maximum fuel (fuel limit).
    @returns  number
]]
function CampfireService:GetFuelLimit(): number
	return maxFuel
end

--[[
    @summary  Return the current fuel as a 0-1 fraction of the limit.
    @returns  number
]]
function CampfireService:GetFuelFraction(): number
	if maxFuel <= 0 then
		return 0
	end
	return fuel / maxFuel
end

--[[
    @summary  Return the current campfire level (1-6).
    @returns  number
]]
function CampfireService:GetLevel(): number
	return level
end

--[[
    @summary  Return the current level progress.
    @returns  number, number, number  -- progress, requirement, fraction
]]
function CampfireService:GetLevelProgress(): (number, number, number)
	local requirement = LEVEL_REQUIREMENTS[level] or LEVEL_REQUIREMENTS[#LEVEL_REQUIREMENTS]
	local fraction = if requirement > 0 then math.clamp(levelProgress / requirement, 0, 1) else 1
	return levelProgress, requirement, fraction
end

--[[
    @summary  Return true if the campfire still has fuel remaining.
    @returns  boolean
]]
function CampfireService:IsLit(): boolean
	return isLit
end

--[[
    @summary  Return the current safe zone radius in studs.
    @returns  number  -- 0 if fire is out
]]
function CampfireService:GetSafeZoneRadius(): number
	if not isLit then
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
	if not isLit or not fireCenter then
		return false
	end
	local flatDist = (Vector3.new(position.X, 0, position.Z) - Vector3.new(fireCenter.Position.X, 0, fireCenter.Position.Z)).Magnitude
	return flatDist <= currentSafeZoneRadius
end

--[[
    @summary  Apply extra fuel drain from an external penalty source
              (e.g. an unresolved Cultist raid at dawn).
    @param    amount  number
]]
function CampfireService:ApplyExternalDrain(amount: number)
	if not runStateService or not runStateService:IsActive() or amount <= 0 or not isLit then
		return
	end
	fuel = math.clamp(fuel - amount, 0, maxFuel)
	if fuel <= 0 then
		isLit = false
	end
end

--[[
    @summary  Restore the campfire to its fresh-run state.
]]
function CampfireService:ResetForRun()
	level = 1
	levelProgress = 0
	maxFuel = MAX_FUEL_BY_LEVEL[1]
	fuel = 0
	isLit = false
	feedCooldowns = {}
	currentSafeZoneRadius = 0
	lastBroadcastRadius = 0
	CampfireService.LevelChangedServer:Fire(level, 0)
end

--[[
    @summary  Compute the level-progress value of one log at the current level.
    @returns  number
]]
local function getWoodLevelValue(): number
	return WOOD_LEVEL_VALUE_BASE
end

--[[
    @summary  Process level-ups when the level bar overflows.
]]
local function processLevelUps()
	while level < #MAX_FUEL_BY_LEVEL and levelProgress >= (LEVEL_REQUIREMENTS[level] or math.huge) do
		local requirement = LEVEL_REQUIREMENTS[level] :: number
		levelProgress -= requirement
		level += 1
		maxFuel = MAX_FUEL_BY_LEVEL[level]
		fuel = math.clamp(fuel, 0, maxFuel)
		currentSafeZoneRadius = if isLit then SAFE_ZONE_RADIUS_BY_LEVEL[level] else 0
		for _, player in ipairs(runStateService:GetMembers()) do
			CampfireService.Client.LevelUp:Fire(player, level, level - 1, currentSafeZoneRadius, maxFuel)
		end
		CampfireService.LevelChangedServer:Fire(level, level - 1)
	end

	-- Cap progress at the final level's requirement so the bar sits at 100%.
	if level == #MAX_FUEL_BY_LEVEL then
		local cap = LEVEL_REQUIREMENTS[level] or 0
		if levelProgress > cap then
			levelProgress = cap
		end
	end
end

--[[
    @summary  Update the Fire effect and PointLight to match current fuel and level.
]]
local function updateFireVisuals()
	if not fireInstance and not pointLight then
		return
	end

	local fraction = if maxFuel > 0 then fuel / maxFuel else 0
	local sizeMax = FIRE_SIZE_MAX * FIRE_SIZE_LEVEL_MULTIPLIER[level]
	local heatMax = FIRE_HEAT_MAX * FIRE_SIZE_LEVEL_MULTIPLIER[level]
	local lightMax = LIGHT_RANGE_MAX * LIGHT_RANGE_LEVEL_MULTIPLIER[level]

	if fireInstance then
		fireInstance.Enabled = isLit and fuel > 0
		fireInstance.Size = FIRE_SIZE_MIN + (sizeMax - FIRE_SIZE_MIN) * fraction
		fireInstance.Heat = FIRE_HEAT_MIN + (heatMax - FIRE_HEAT_MIN) * fraction
	end

	if pointLight then
		pointLight.Enabled = isLit
		pointLight.Color = Color3.fromRGB(255, 130, 60)
		pointLight.Shadows = false
		local targetRange = math.clamp(currentSafeZoneRadius * 1.2, LIGHT_RANGE_MIN, lightMax)
		pointLight.Range = if isLit then targetRange else 0
		pointLight.Brightness = if isLit then LIGHT_BRIGHTNESS_MIN + (LIGHT_BRIGHTNESS_MAX - LIGHT_BRIGHTNESS_MIN) * fraction + 0.5 else 0
	end
end

--[[
    @summary  Position/orient the slim glowing line segments as a dashed ring
              around the campfire with the given radius and active state.
    @param    radius   number   -- ring radius in studs
    @param    active   boolean  -- whether the ring is visible
]]
local function updateSafeZoneVisuals(radius: number, active: boolean)
	if not safeZoneDots or not fireCenter or not campfirePart then
		return
	end

	local groundY: number
	if not groundPart then
		local dotFolder = safeZoneDots[1].Parent
		local dotMap = dotFolder and dotFolder.Parent
		if dotMap then
			groundPart = dotMap:FindFirstChild("Земля") :: BasePart?
			if not groundPart then
				for _, d in ipairs(dotMap:GetDescendants()) do
					if d:IsA("BasePart") and d.Size.Y < 50 and d.Size.X > 500 and d.Size.Z > 500 then
						groundPart = d :: BasePart
						break
					end
				end
			end
		end
	end
	if groundPart then
		groundY = groundPart.Position.Y + groundPart.Size.Y * 0.5 + SAFE_ZONE_LINE_HEIGHT
	else
		groundY = fireCenter.Position.Y + SAFE_ZONE_LINE_HEIGHT
	end
	local transparency = active and SAFE_ZONE_LINE_TRANSPARENCY or SAFE_ZONE_LINE_OFF_TRANSPARENCY
	local circumference = 2 * math.pi * radius
	local lineLength = (circumference / SAFE_ZONE_LINE_COUNT) * SAFE_ZONE_LINE_FILL

	for i, dot in ipairs(safeZoneDots) do
		local angle = (i - 1) * (2 * math.pi / SAFE_ZONE_LINE_COUNT)
		local normal = Vector3.new(math.cos(angle), 0, math.sin(angle))
		local position = Vector3.new(
			fireCenter.Position.X + normal.X * radius,
			groundY,
			fireCenter.Position.Z + normal.Z * radius
		)

		dot.CFrame = CFrame.fromMatrix(position, normal, Vector3.new(0, 1, 0))
		dot.Size = Vector3.new(SAFE_ZONE_LINE_THICKNESS, SAFE_ZONE_LINE_HEIGHT, lineLength)
		dot.Transparency = transparency
	end
end

--[[
    @summary  Recompute safe zone radius and refresh the visual ring.
]]
local function updateSafeZone()
	currentSafeZoneRadius = if isLit then SAFE_ZONE_RADIUS_BY_LEVEL[level] else 0
	updateSafeZoneVisuals(currentSafeZoneRadius, isLit)
end

--[[
    @summary  Broadcast the current fuel state to a player (or all players if omitted).
    @param    target  Player?  -- nil to broadcast to all
]]
local function isPlayerInGame(player: Player): boolean
	return runStateService ~= nil
		and runStateService:IsActive()
		and runStateService:IsMember(player)
		and spawnService ~= nil
		and spawnService:IsPlayerSpawned(player)
end

local function canInteract(player: Player): boolean
	return isPlayerInGame(player)
		and playerLifeService ~= nil
		and playerLifeService:IsAlive(player)
end

local function broadcastFuel(target: Player?)
	local fraction = if maxFuel > 0 then fuel / maxFuel else 0
	if target then
		if isPlayerInGame(target) then
			CampfireService.Client.FuelChanged:Fire(target, fuel, maxFuel, fraction, isLit)
		end
		return
	end
	for _, player in ipairs(runStateService:GetMembers()) do
		if isPlayerInGame(player) then
			CampfireService.Client.FuelChanged:Fire(player, fuel, maxFuel, fraction, isLit)
		end
	end
end

--[[
    @summary  Broadcast the current level state to a player (or all players if omitted).
    @param    target  Player?  -- nil to broadcast to all
]]
local function broadcastLevel(target: Player?)
	local requirement = LEVEL_REQUIREMENTS[level] or LEVEL_REQUIREMENTS[#LEVEL_REQUIREMENTS]
	local levelFraction = if requirement > 0 then math.clamp(levelProgress / requirement, 0, 1) else 1
	if target then
		if isPlayerInGame(target) then
			CampfireService.Client.LevelChanged:Fire(target, level, levelProgress, requirement, levelFraction)
		end
		return
	end
	for _, player in ipairs(runStateService:GetMembers()) do
		if isPlayerInGame(player) then
			CampfireService.Client.LevelChanged:Fire(player, level, levelProgress, requirement, levelFraction)
		end
	end
end

--[[
    @summary  Broadcast the current safe zone to a player (or all players if omitted).
    @param    target  Player?  -- nil to broadcast to all
    @param    force   boolean? -- true to bypass the radius-change throttle
]]
local function broadcastSafeZone(target: Player?, force: boolean?)
	updateSafeZone()

	local shouldBroadcast = force
		or math.abs(currentSafeZoneRadius - lastBroadcastRadius) >= SAFE_ZONE_BROADCAST_THRESHOLD
		or (isLit and lastBroadcastRadius <= 0)
		or (not isLit and lastBroadcastRadius > 0)

	if not shouldBroadcast then
		return
	end

	lastBroadcastRadius = currentSafeZoneRadius
	if target then
		if isPlayerInGame(target) then
			CampfireService.Client.SafeZoneChanged:Fire(target, currentSafeZoneRadius, isLit)
		end
		return
	end
	for _, player in ipairs(runStateService:GetMembers()) do
		if isPlayerInGame(player) then
			CampfireService.Client.SafeZoneChanged:Fire(player, currentSafeZoneRadius, isLit)
		end
	end
end

--[[
    @summary  Add fuel and level progress from a given number of logs.
    @param    woodAmount  number
]]
local function addFuel(woodAmount: number)
	if woodAmount <= 0 then
		return
	end

	local wasLit = isLit
	local previousLevel = level

	isLit = true
	fuel += woodAmount * WOOD_FUEL_VALUE
	fuel = math.clamp(fuel, 0, maxFuel)

	levelProgress += woodAmount * getWoodLevelValue()
	processLevelUps()
	updateSafeZone()

	-- If this was the spark that lit the fire and no real level-up happened,
	-- show the Campfire Level banner for the current level so the player
	-- gets clear feedback the campfire is now burning.
	if not wasLit and level == previousLevel then
		for _, player in ipairs(runStateService:GetMembers()) do
			CampfireService.Client.LevelUp:Fire(player, level, level - 1, currentSafeZoneRadius, maxFuel)
		end
	end

	updateFireVisuals()
	broadcastSafeZone(nil, true)
	broadcastFuel()
	broadcastLevel()
end

--[[
    @summary  Validate and process a feed request, consuming Wood and
              adding both current fuel and level progress.
    @param    player  Player  -- the feeding player
    @param    amount  number  -- logs to feed (default 1)
]]
local function feedCampfire(player: Player, amount: number)
	if not canInteract(player) or not campfirePart or not inventoryService then
		return
	end

	if amount <= 0 then
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

	if not inventoryService:ConsumeResource(player, "Wood", amount) then
		return
	end

	feedCooldowns[player] = now
	addFuel(amount)
end


--[[
    @summary  Convert a dropped RawMeat model into CookedMeat, either adding
              it to the original owner's inventory or spawning a pickup.
]]
local function getEligibleDropOwner(model: Model): Player?
	local ownerId = model:GetAttribute("DroppedBy")
	if typeof(ownerId) ~= "number" then
		return nil
	end
	for _, player in ipairs(runStateService:GetMembers()) do
		if player.UserId == ownerId and canInteract(player) then
			return player
		end
	end
	return nil
end

local function cookRawMeat(model: Model)
	if not isLit or fuel <= 0 or not inventoryService then
		return
	end

	-- Try to give the cooked meat directly to the original owner's inventory.
	local owner = getEligibleDropOwner(model)
	if owner then
		local added = inventoryService:AddResource(owner, "CookedMeat", 1)
		if added > 0 then
			model:Destroy()
			return
		end
	end

	-- No owner or inventory full — spawn a cooked meat drop in the world.
	local cooked = inventoryService:BuildDropModel("CookedMeat")
	if cooked then
		cooked:PivotTo(model:GetPivot())
		cooked.Parent = model.Parent
		Debris:AddItem(cooked, 300)
	end
	model:Destroy()
end

--[[
    @summary  Scan the area around the campfire for loose Log models and
              consume them as fuel, or cook RawMeat drops.
]]
local function scanForLogFuel()
	if not campfirePart or not inventoryService or not worldService then
		return
	end

	local baseMap = worldService:GetBaseMap()
	if not baseMap then
		return
	end

	local params = OverlapParams.new()
	params.FilterDescendantsInstances = { baseMap }
	params.FilterType = Enum.RaycastFilterType.Include

	local parts = workspace:GetPartBoundsInRadius(campfirePart.Position, LOG_SCAN_RADIUS, params)
	local consumedThisScan = {}
	for _, part in ipairs(parts) do
		if not part:IsA("BasePart") then
			continue
		end

		local model = part:FindFirstAncestorOfClass("Model")
		if not model then
			continue
		end
		if consumedThisScan[model] then
			continue
		end

		local resourceName = model:GetAttribute("Resource")
			or model:GetAttribute("PickupResource")
			or model:GetAttribute("ForageResource")
		if not resourceName or typeof(resourceName) ~= "string" then
			continue
		end
		if inventoryService:IsModelDragged(model) then
			continue
		end
		-- Wood/Coal require a valid owner (player dropped it). RawMeat
		-- can be cooked regardless of who dropped it (e.g. animal loot).
		if resourceName ~= "RawMeat" and not getEligibleDropOwner(model) then
			continue
		end

		if resourceName == "Wood" or resourceName == "Coal" then
			consumedThisScan[model] = true
			addFuel(if resourceName == "Coal" then 3 else 1)
			model:Destroy()
		elseif resourceName == "RawMeat" then
			consumedThisScan[model] = true
			cookRawMeat(model)
		end
	end
end

--[[
    @summary  Heartbeat-driven fuel drain and visual scaling.
    @param    dt  number  -- delta time in seconds
]]
local function onHeartbeat(dt: number)
	if not runStateService or not runStateService:IsActive() then
		return
	end
	if isLit then
		local drain = FUEL_DRAIN_BASE * (FUEL_DRAIN_MULTIPLIER_BY_LEVEL[level] or 1) * dt
		fuel = math.clamp(fuel - drain, 0, maxFuel)
		if fuel <= 0 then
			isLit = false
		end
	end

	updateFireVisuals()
	updateSafeZone()
	broadcastSafeZone()

	logScanTimer += dt
	if logScanTimer >= LOG_SCAN_INTERVAL then
		logScanTimer = 0
		scanForLogFuel()
	end

	fuelBroadcastTimer += dt
	if fuelBroadcastTimer >= FUEL_BROADCAST_INTERVAL then
		fuelBroadcastTimer = 0
		broadcastFuel()
		broadcastLevel()
	end
end

--[[
    @summary  Locate the Bonfire's Fire effect and PointLight, and
              prepare the campfire anchor for drop-only fueling.
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
	local map = bonfire and bonfire.Parent
	if not bonfire or not anchor then
		task.defer(setupCampfire)
		return
	end

	campfirePart = anchor :: BasePart
	if not campfirePart then
		return
	end

	-- Use the anchor as the safe-zone centre so it matches the spawn point.
	fireCenter = campfirePart

	local firePart = bonfire:FindFirstChild("Fire")
	if firePart and firePart:IsA("BasePart") then
		fireInstance = firePart:FindFirstChildOfClass("Fire")
	end

	for _, descendant in ipairs(bonfire:GetDescendants()) do
		if descendant:IsA("PointLight") then
			pointLight = descendant
			break
		end
	end

	if not pointLight and fireCenter then
		local newPointLight: PointLight = Instance.new("PointLight")
		newPointLight.Name = "CampfirePointLight"
		newPointLight.Parent = fireCenter
		pointLight = newPointLight
	end

	if pointLight then
		pointLight.Color = Color3.fromRGB(255, 130, 60)
		pointLight.Shadows = false
	end

	if map then
		for _, descendant in ipairs(map:GetDescendants()) do
			if
				descendant:IsA("BasePart")
				and descendant.Size.Y < 50
				and descendant.Size.X > 500
				and descendant.Size.Z > 500
			then
				groundPart = descendant
				break
			end
		end
	end

	local feedPrompt = campfirePart:FindFirstChild("FeedCampfirePrompt")
	if feedPrompt then
		feedPrompt:Destroy()
	end

	-- Remove any old safe zone visuals (disc or previous dots) before creating fresh dots
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
		dot.Shape = Enum.PartType.Block
		dot.Anchored = true
		dot.CanCollide = false
		dot.CanQuery = false
		dot.CanTouch = false
		dot.Material = SAFE_ZONE_LINE_MATERIAL
		dot.Color = SAFE_ZONE_LINE_COLOR
		dot.Transparency = SAFE_ZONE_LINE_OFF_TRANSPARENCY
		dot.Size = Vector3.new(SAFE_ZONE_LINE_THICKNESS, SAFE_ZONE_LINE_HEIGHT, 1)
		dot.CastShadow = false
		dot.Parent = dotFolder
		table.insert(dots, dot)
	end

	safeZoneDots = dots

	maxFuel = MAX_FUEL_BY_LEVEL[level]
	fuel = math.clamp(fuel, 0, maxFuel)
	isLit = fuel > 0

	updateFireVisuals()
	updateSafeZone()
	broadcastSafeZone(nil, true)

end

--[[
    @summary  Client-facing remote requesting the campfire be fed.
    @param    player  Player  -- injected by Knit
    @param    amount  number? -- logs to feed (default 1)
]]
function CampfireService.Client:RequestFuelCampfire(player: Player, amount: number?)
	local requested: number = if amount and typeof(amount) == "number" and amount >= 1 then amount else 1
	requested = math.floor(requested)
	self.Server:_FeedCampfire(player, requested)
end

--[[
    @summary  Internal server-only wrapper so both the Knit remote and
              the ProximityPrompt handler share one code path.
    @param    player  Player  -- the feeding player
    @param    amount  number
]]
function CampfireService:_FeedCampfire(player: Player, amount: number)
	feedCampfire(player, amount)
end

--[[
    @summary  Client-facing remote to fetch the full campfire state.
    @param    player  Player  -- injected by Knit
    @returns  number, number, number, number, number, boolean
]]
function CampfireService.Client:GetState(player: Player): (number, number, number, number, number, boolean)
	if not runStateService:IsActive() or not runStateService:IsMember(player) then
		return 0, MAX_FUEL_BY_LEVEL[1], 1, 0, LEVEL_REQUIREMENTS[1], false
	end
	local requirement = LEVEL_REQUIREMENTS[level] or LEVEL_REQUIREMENTS[#LEVEL_REQUIREMENTS]
	return fuel, maxFuel, level, levelProgress, requirement, isLit
end

--[[
    @summary  Client-facing remote returning the current safe-zone radius
              and whether the fire is lit, so the client can initialise
              its state even if it missed the SafeZoneChanged signal.
    @returns  number, boolean  -- radius, isLit
]]
function CampfireService.Client:GetSafeZoneInfo(player: Player): (number, boolean)
	if not runStateService:IsActive() or not runStateService:IsMember(player) then
		return 0, false
	end
	updateSafeZone()
	return currentSafeZoneRadius, isLit
end

-- // INITIALIZATION // --

function CampfireService:KnitStart()
	if not ServerRole.IsGameServer() then return end
	worldService = Knit.GetService("WorldService")
	inventoryService = Knit.GetService("InventoryService")
	spawnService = Knit.GetService("SpawnService")
	runStateService = Knit.GetService("RunStateService")
	playerLifeService = Knit.GetService("PlayerLifeService")

	-- Campfire progress is authoritative in-memory run state. Player profiles
	-- are deliberately never loaded or saved as the source for this shared state.
	runStateService.RunStarted:Connect(function()
		CampfireService:ResetForRun()
		updateFireVisuals()
		updateSafeZone()
	end)
	runStateService.RunCleaned:Connect(function()
		CampfireService:ResetForRun()
		updateFireVisuals()
		updateSafeZone()
	end)

	setupCampfire()
	CampfireService._HeartbeatConnection = RunService.Heartbeat:Connect(onHeartbeat)
end

-- Rojo hot-reload path: if the service already existed, the new module's KnitStart
-- won't be called by Knit, so run setup and wire events directly.
if not createSuccess then
	worldService = Knit.GetService("WorldService")
	inventoryService = Knit.GetService("InventoryService")

	if not CampfireService.Client then
		CampfireService.Client = {}
	end
	if not CampfireService.Client.FuelChanged then
		CampfireService.Client.FuelChanged = Knit.CreateSignal()
	end
	if not CampfireService.Client.LevelChanged then
		CampfireService.Client.LevelChanged = Knit.CreateSignal()
	end
	if not CampfireService.Client.SafeZoneChanged then
		CampfireService.Client.SafeZoneChanged = Knit.CreateSignal()
	end
	if not CampfireService.Client.LevelUp then
		CampfireService.Client.LevelUp = Knit.CreateSignal()
	end
	if not CampfireService.Client.SafeZoneRadius then
		CampfireService.Client.SafeZoneRadius = Knit.CreateProperty(0)
	end
	if not CampfireService.Client.IsLit then
		CampfireService.Client.IsLit = Knit.CreateProperty(false)
	end

	if CampfireService._HeartbeatConnection then
		CampfireService._HeartbeatConnection:Disconnect()
	end

	setupCampfire()
	CampfireService._HeartbeatConnection = RunService.Heartbeat:Connect(onHeartbeat)

end

Players.PlayerRemoving:Connect(function(player)
	feedCooldowns[player] = nil
end)

return CampfireService
