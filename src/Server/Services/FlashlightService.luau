--[[
    @file    FlashlightService.luau
    @author  manik
    @date    2025

    @summary
    Server-validated flashlight beam check that stuns pursuing Deer /
    Ram Monster stalkers and the Owl.

    @description
    Trusts only a low-stakes "beam is on" boolean from the client; the
    server independently computes the wielder's facing, range, and
    cone alignment against every active stalker before ever applying
    a stun, so the client cannot dictate the outcome.

    @exports
    - Knit Remote: SetBeamActive(isActive: boolean)  (client -> server)
]]

-- // VARIABLES // --

-- | Services | --
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

-- | Modules | --
local Knit = require(ReplicatedStorage.Packages.Knit)
local CombatTargetRegistry = require(script.Parent.Parent.CombatTargetRegistry)

-- | Objects | --
local FlashlightService = Knit.CreateService({
	Name = "FlashlightService",
	Client = {},
})

-- | Configuration | --
local FLASHLIGHT_TOOL_NAME = "Flashlight"
local BEAM_RANGE = 35
local BEAM_HALF_ANGLE = math.rad(25)
local CHECK_INTERVAL = 0.15
local STALKER_MODEL_NAMES = { "Deer", "Ram Monster", "Owl" }

-- | State Management | --
local deerService: any = nil
local owlService: any = nil
local beamActive: { [Player]: boolean } = {}
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
    @summary  Check whether a player's facing direction is aligned
              with and in range of a stalker's position.
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

	local stalkerPart = stalker.PrimaryPart or stalker:FindFirstChildWhichIsA("BasePart")
	if not stalkerPart then
		return false
	end

	local toStalker = stalkerPart.Position - rootPart.Position
	local distance = toStalker.Magnitude
	if distance > BEAM_RANGE or distance <= 0 then
		return false
	end

	local angle = math.acos(math.clamp(rootPart.CFrame.LookVector.Unit:Dot(toStalker.Unit), -1, 1))
	return angle <= BEAM_HALF_ANGLE
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
end

--[[
    @summary  Client-facing remote reporting whether the local player's
              flashlight beam is currently switched on.
    @param    player     Player   -- injected by Knit
    @param    isActive   boolean  -- the requested beam state
]]
function FlashlightService.Client:SetBeamActive(player: Player, isActive: boolean)
	if typeof(isActive) ~= "boolean" then
		return
	end
	beamActive[player] = isActive
end

--[[
    @summary  Heartbeat-driven, throttled beam alignment check for all players.
    @param    dt  number
]]
local function onHeartbeat(dt: number)
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
	print("[FlashlightService] Initialised — beam-stun validation active")
end

Players.PlayerRemoving:Connect(function(player)
	beamActive[player] = nil
end)

return FlashlightService
