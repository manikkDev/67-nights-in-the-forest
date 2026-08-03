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
    - CampfireService:GetFuel()         -> number
    - CampfireService:GetFuelFraction() -> number
    - CampfireService:IsLit()           -> boolean
    - Knit Signal: FuelChanged(fuel: number, fraction: number)  (server -> client)
    - Knit Remote: RequestFuelCampfire  -> void  (client -> server)
]]

-- // VARIABLES // --

-- | Services | --
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ProximityPromptService = game:GetService("ProximityPromptService")

-- | Modules | --
local Knit = require(ReplicatedStorage.Packages.Knit)

-- | Constants | --
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

-- | Objects | --
local CampfireService = Knit.CreateService({
	Name = "CampfireService",
	Client = {
		FuelChanged = Knit.CreateSignal(),
	},
})

-- | State | --
local worldService: any? = nil
local playerDataService: any? = nil
local fuel = MAX_FUEL
local campfirePart: BasePart? = nil
local fireInstance: Fire? = nil
local pointLight: PointLight? = nil
local feedPrompt: ProximityPrompt? = nil
local feedCooldowns: { [Player]: number } = {}
local fuelBroadcastTimer = 0

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

	campfirePart = anchor

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

	feedPrompt = Instance.new("ProximityPrompt")
	feedPrompt.Name = "FeedFirePrompt"
	feedPrompt.ActionText = "Feed Fire"
	feedPrompt.ObjectText = "Campfire"
	feedPrompt.MaxActivationDistance = FEED_RANGE + 2
	feedPrompt.HoldDuration = 0.3
	feedPrompt.Parent = campfirePart

	print("[CampfireService] Campfire wired — fuel:", fuel)
end

--[[
    @summary  Validate and process a feed request, depositing all of
              the player's owned Wood into the campfire's fuel.
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

	local data = playerDataService:GetData(player)
	if not data or data.Resources.Wood <= 0 then
		return
	end

	feedCooldowns[player] = now
	local wood = data.Resources.Wood

	playerDataService:UpdateData(player, function(playerData)
		playerData.Resources.Wood = 0
	end)

	fuel = math.clamp(fuel + wood * WOOD_FUEL_VALUE, 0, MAX_FUEL)
	CampfireService.Client.FuelChanged:FireAll(fuel, fuel / MAX_FUEL)
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

	fuelBroadcastTimer += dt
	if fuelBroadcastTimer >= FUEL_BROADCAST_INTERVAL then
		fuelBroadcastTimer = 0
		CampfireService.Client.FuelChanged:FireAll(fuel, fraction)
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
	RunService.Heartbeat:Connect(onHeartbeat)
	ProximityPromptService.PromptTriggered:Connect(onPromptTriggered)

	print("[CampfireService] Initialised — fuel drain active")
end

return CampfireService
