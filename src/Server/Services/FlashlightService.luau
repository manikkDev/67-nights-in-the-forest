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
local ServerRole = require(ReplicatedStorage.Shared.ServerRole)
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
local BEAM_MIN_RANGE = 80
local BEAM_MAX_RANGE = 140
local BEAM_MIN_ANGLE = 80
local BEAM_MAX_ANGLE = 110
local AIM_TIMEOUT = 1.0
local AIM_UPDATE_MIN_INTERVAL = 0.05
local CHECK_INTERVAL = 0.15
local BATTERY_DRAIN_PER_SECOND = 2 -- 50 seconds of full use
local BATTERY_RECHARGE_PER_SECOND = 3 -- faster passive recharge
local STALKER_MODEL_NAMES = { "Deer", "Ram Monster", "Owl" }

-- | State Management | --
local deerService: any = nil
local owlService: any = nil
local beamActive: { [Player]: boolean } = {}
local battery: { [Player]: number } = {}
local aimDirections: { [Player]: Vector3 } = {}
local aimTimestamps: { [Player]: number } = {}
local aimRemoteTimestamps: { [Player]: number } = {}
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
	local tool = character and character:FindFirstChild(FLASHLIGHT_TOOL_NAME)
	local handle = tool and tool:FindFirstChild("Handle")
	if not handle or not handle:IsA("BasePart") then
		return false
	end
	local stalkerPart = stalker.PrimaryPart
		or stalker:FindFirstChild("HRP")
		or stalker:FindFirstChild("HumanoidRootPart")
		or stalker:FindFirstChildWhichIsA("BasePart", true)
	if not stalkerPart or not stalkerPart:IsA("BasePart") then
		return false
	end

	local toStalker = stalkerPart.Position - handle.Position
	local distance = toStalker.Magnitude
	local charge = math.clamp((battery[player] or 100) / 100, 0, 1)
	local range = BEAM_MIN_RANGE + (BEAM_MAX_RANGE - BEAM_MIN_RANGE) * charge
	-- Use a small minimum distance instead of 0 so very close targets still work
	if distance > range or distance < 0.1 then
		return false
	end
	-- When the deer is very close (within 5 studs), skip the angle check
	-- — the beam is essentially on top of the deer, so it should always stun
	if distance <= 5 then
		return true
	end
	local aim = aimDirections[player]
	if not aim or os.clock() - (aimTimestamps[player] or 0) > AIM_TIMEOUT then
		aim = handle.CFrame.LookVector
	end
	local fullAngle = BEAM_MIN_ANGLE + (BEAM_MAX_ANGLE - BEAM_MIN_ANGLE) * charge
	-- Widen the angle when the deer is close (within 15 studs) for more reliable stuns
	local angleBonus = if distance < 15 then math.rad(20) else 0
	local angle = math.acos(math.clamp(aim.Unit:Dot(toStalker.Unit), -1, 1))
	if angle > math.rad(fullAngle * 0.5) + angleBonus then
		return false
	end

	-- NOTE: No raycast obstruction check.  The flashlight beam is a cone
	-- of light, not a laser — it passes through trees and foliage just
	-- like in the reference game.

	return true
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
	if isActive and (battery[player] or 0) <= 0 then
		isActive = false
	end
	beamActive[player] = isActive
	if not isActive then
		aimDirections[player] = nil
		aimTimestamps[player] = nil
	end
	broadcastBattery(player)
end

function FlashlightService.Client:UpdateAim(player: Player, direction: Vector3)
	if typeof(direction) ~= "Vector3" or not beamActive[player] or not hasFlashlightEquipped(player) then
		return
	end
	if direction.X ~= direction.X or direction.Y ~= direction.Y or direction.Z ~= direction.Z or direction.Magnitude < 0.9 then
		return
	end
	local now = os.clock()
	if now - (aimRemoteTimestamps[player] or 0) < AIM_UPDATE_MIN_INTERVAL then
		return
	end
	aimRemoteTimestamps[player] = now
	aimDirections[player] = direction.Unit
	aimTimestamps[player] = now
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
	if not ServerRole.IsGameServer() then return end
	deerService = Knit.GetService("DeerService")
	owlService = Knit.GetService("OwlService")
	RunService.Heartbeat:Connect(onHeartbeat)
end

Players.PlayerRemoving:Connect(function(player)
	beamActive[player] = nil
	battery[player] = nil
	aimDirections[player] = nil
	aimTimestamps[player] = nil
	aimRemoteTimestamps[player] = nil
	lastBroadcastState[player] = nil
end)

return FlashlightService
