--[[
    @file    FlashlightService.luau
    @author  manik
    @date    2025

    @summary
    Server-validated flashlight beam check with battery drain.

    @description
    Tracks per-player flashlight battery, drains it while the beam is
    on, and recharges it slowly while off. When the battery reaches
    zero the beam is forced off. Independently computes the wielder s
    facing, range, and cone alignment against active stalkers before
    applying a stun, so the client cannot dictate the outcome.

    @exports
    - Knit Remote: SetBeamActive(isActive: boolean)  (client -> server)
    - Knit Remote: GetBatteryState() -> { percent: number, isOn: boolean }
    - Knit Signal: BatteryChanged(percent: number, isOn: boolean)
]]

-- // VARIABLES // --

-- | Services | --
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

-- | Modules | --
local Knit = require(ReplicatedStorage.Packages.Knit)
local RunConfig = require(ReplicatedStorage.Shared.RunConfig)
local CombatTargetRegistry = require(script.Parent.Parent.CombatTargetRegistry)

-- | Objects | --
local FlashlightService = Knit.CreateService({
	Name = "FlashlightService",
	Client = {
		BatteryChanged = Knit.CreateSignal(),
	},
})

-- | Configuration | --
local FLASHLIGHT_TOOL_NAME = "Flashlight"
local BEAM_RANGE = 35
local BEAM_HALF_ANGLE = math.rad(30)
local CHECK_INTERVAL = 0.15
local BATTERY_DRAIN_PER_SECOND = 5 -- 20 seconds of full use
local BATTERY_RECHARGE_PER_SECOND = 1.5 -- slow passive recharge
local STALKER_MODEL_NAMES = { "Deer", "Ram Monster", "Owl" }

-- | State Management | --
local deerService: any = nil
local owlService: any = nil
local beamActive: { [Player]: boolean } = {}
local battery: { [Player]: number } = {}
local lastBroadcastState: { [Player]: { percent: number, isOn: boolean } } = {}
local checkTimer = 0

-- // FUNCTIONS // --

--[[
    @summary  Return true if a player currently has the Flashlight
              tool equipped.
    @param    player  Player
    @returns  boolean
]]
local function hasFlashlightEquipped(player: Player): boolean
	local character = player.Character
	if not character then
		return false
	end
	local tool = character:FindFirstChild(FLASHLIGHT_TOOL_NAME)
	return tool ~= nil and tool:IsA("Tool")
end

--[[
    @summary  Check if the player's equipped flashlight SpotLight is
              actually enabled.  This bypasses the client-to-server
              remote entirely, reading the tool state directly on the
              server.
    @param    player  Player
    @returns  boolean
]]
local function isFlashlightBeamOn(player: Player): boolean
	local character = player.Character
	if not character then
		return false
	end
	local tool = character:FindFirstChild(FLASHLIGHT_TOOL_NAME)
	if not tool or not tool:IsA("Tool") then
		return false
	end
	local handle = tool:FindFirstChild("Handle")
	if not handle then
		return false
	end
	local spotLight = handle:FindFirstChildOfClass("SpotLight")
	return spotLight ~= nil and spotLight.Enabled
end

--[[
    @summary  Broadcast the current battery state to the owning player.
    @param    player  Player
]]
local function broadcastBattery(player: Player)
	local percent = math.floor(battery[player] or 100)
	local isOn = beamActive[player] == true

	local last = lastBroadcastState[player]
	if last and last.percent == percent and last.isOn == isOn then
		return
	end

	lastBroadcastState[player] = { percent = percent, isOn = isOn }
	FlashlightService.Client.BatteryChanged:Fire(player, percent, isOn)
end

--[[
    @summary  Initialise battery for a new player.
    @param    player  Player
]]
local function ensureBattery(player: Player)
	if battery[player] == nil then
		battery[player] = 100
	end
end

--[[
    @summary  Update battery for every player on each tick.
    @param    dt  number
]]
local function updateBatteries(dt: number)
	for player, isActive in pairs(beamActive) do
		ensureBattery(player)
		if not player.Parent then
			continue
		end

		local current = battery[player]
		if isActive and hasFlashlightEquipped(player) then
			current -= BATTERY_DRAIN_PER_SECOND * dt
			if current <= 0 then
				current = 0
				beamActive[player] = false
				-- Force the client to turn the visual beam off
				broadcastBattery(player)
			end
		else
			current += BATTERY_RECHARGE_PER_SECOND * dt
			if current > 100 then
				current = 100
			end
		end
		battery[player] = current
		broadcastBattery(player)
	end
end

--[[
    @summary  Check whether a player s facing direction is aligned
              with and in range of a stalker s position.
    @param    player   Player
    @param    stalker  Model
    @returns  boolean
]]
local function isBeamAlignedWithStalker(player: Player, stalker: Model): boolean
	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	if not rootPart or not rootPart:IsA("BasePart") then
		return false
	end

	local stalkerPart = stalker.PrimaryPart
		or stalker:FindFirstChild("HRP")
		or stalker:FindFirstChild("HumanoidRootPart")
		or stalker:FindFirstChildWhichIsA("BasePart", true)
	if not stalkerPart then
		return false
	end

	local toStalker = stalkerPart.Position - rootPart.Position
	local distance = toStalker.Magnitude
	if distance > BEAM_RANGE or distance <= 0 then
		return false
	end

	-- Use horizontal-only angle so height differences between player and
	-- stalker don't cause the beam alignment to fail.
	local flatToStalker = Vector3.new(toStalker.X, 0, toStalker.Z)
	local flatLook = Vector3.new(rootPart.CFrame.LookVector.X, 0, rootPart.CFrame.LookVector.Z)
	if flatLook.Magnitude <= 0 or flatToStalker.Magnitude <= 0 then
		return false
	end
	local angle = math.acos(math.clamp(flatLook.Unit:Dot(flatToStalker.Unit), -1, 1))
	local aligned = angle <= BEAM_HALF_ANGLE

	if aligned and RunConfig.IsTestEnabled("VerboseFlashlight") then
		print(string.format("[FlashlightService] beam aligned with %s at %.1f studs", stalker.Name, distance))
	end

	return aligned
end

--[[
    @summary  For every player currently holding their beam on, check
              alignment against active stalkers and apply a stun.
]]
local function checkAllBeams()
	if not deerService and not owlService then
		return
	end

	local candidates = CollectionService:GetTagged(CombatTargetRegistry.TagName)
	local stalkerModels = {}
	for _, model in ipairs(candidates) do
		if model:IsA("Model") and table.find(STALKER_MODEL_NAMES, model.Name) then
			table.insert(stalkerModels, model)
		end
	end
	if #stalkerModels == 0 then
		return
	end

	for player, isActive in pairs(beamActive) do
		if not isActive or not player.Parent or not hasFlashlightEquipped(player) then
			continue
		end
		for _, stalkerModel in ipairs(stalkerModels) do
			if isBeamAlignedWithStalker(player, stalkerModel) then
				if stalkerModel.Name == "Owl" and owlService then
					owlService:ApplyFlashlightStun(stalkerModel, player)
				elseif deerService then
					deerService:ApplyFlashlightStun(stalkerModel, player)
				end
			end
		end
	end

	-- Also check players who have the flashlight equipped and SpotLight
	-- enabled, even if the client never reported beam state via remote.
	for _, player in ipairs(Players:GetPlayers()) do
		if beamActive[player] then
			continue -- already checked above
		end
		if not player.Parent or not isFlashlightBeamOn(player) then
			continue
		end
		for _, stalkerModel in ipairs(stalkerModels) do
			if isBeamAlignedWithStalker(player, stalkerModel) then
				if stalkerModel.Name == "Owl" and owlService then
					owlService:ApplyFlashlightStun(stalkerModel, player)
				elseif deerService then
					deerService:ApplyFlashlightStun(stalkerModel, player)
				end
			end
		end
	end
end

--[[
    @summary  Client-facing remote reporting whether the local player s
              flashlight beam is currently switched on.
    @param    player     Player   -- injected by Knit
    @param    isActive   boolean  -- the requested beam state
]]
function FlashlightService.Client:SetBeamActive(player: Player, isActive: boolean)
	if typeof(isActive) ~= "boolean" then
		return
	end
	ensureBattery(player)
	-- Don t allow turning on if the battery is empty
	if isActive and (battery[player] or 0) <= 0 then
		isActive = false
	end
	beamActive[player] = isActive
	broadcastBattery(player)
end

--[[
    @summary  Client-facing remote returning the current battery state.
    @param    player  Player
    @returns  { percent: number, isOn: boolean }
]]
function FlashlightService.Client:GetBatteryState(player: Player): { percent: number, isOn: boolean }
	ensureBattery(player)
	return {
		percent = math.floor(battery[player] :: number),
		isOn = beamActive[player] == true,
	}
end

--[[
    @summary  Heartbeat-driven update: drain/recharge battery and
              throttled beam alignment check.
    @param    dt  number
]]
local function onHeartbeat(dt: number)
	updateBatteries(dt)

	checkTimer += dt
	if checkTimer < CHECK_INTERVAL then
		return
	end
	checkTimer = 0
	checkAllBeams()
end

-- // INITIALIZATION // --

function FlashlightService:KnitStart()
	deerService = Knit.GetService("DeerService")
	owlService = Knit.GetService("OwlService")
	RunService.Heartbeat:Connect(onHeartbeat)
end

Players.PlayerRemoving:Connect(function(player)
	beamActive[player] = nil
	battery[player] = nil
	lastBroadcastState[player] = nil
end)

return FlashlightService
