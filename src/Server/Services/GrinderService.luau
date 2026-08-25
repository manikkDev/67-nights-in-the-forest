--[[
    @file    GrinderService.luau
    @author  manik
    @date    2025

    @summary
    Server-authoritative junk-to-scrap grinder placed next to the crafting bench.

    @description
    Places a generated grinder model beside the crafting bench each run.
    Players interact via ProximityPrompt to open the grind UI, then
    select junk items to convert into Scrap. Validates proximity and
    run membership on every grind request.

    @exports
    - Knit Signal: OpenGrinder()          (server -> client, open UI)
    - Knit Signal: GrinderProcessed()     (server -> client, VFX)
    - Knit Remote: GrindItem(junkId)      (client -> server)
    - Knit Remote: GrindAll()             (client -> server)
]]

-- // VARIABLES // --

-- | Services | --
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- | Modules | --
local Knit = require(ReplicatedStorage.Packages.Knit)
local JunkItemConfig = require(ReplicatedStorage.Shared.JunkItemConfig)

-- | Objects | --
local GrinderService = Knit.CreateService({
	Name = "GrinderService",
	Client = {
		OpenGrinder = Knit.CreateSignal(),
		GrinderProcessed = Knit.CreateSignal(),
	},
})

-- | Configuration | --
local GRINDER_OFFSET = CFrame.new(-14, 0, 0)
local GRIND_RANGE = 10
local GRIND_COOLDOWN = 0.15

-- | State Management | --
local runStateService: any = nil
local inventoryService: any = nil
local craftingService: any = nil
local grinderModel: Model? = nil
local grinderPosition: Vector3? = nil
local cooldowns: { [Player]: number } = {}

-- // FUNCTIONS // --

-- | Private | --

--[[
    @summary  Build the grinder model from primitive parts.
    @returns  Model
]]
local function buildGrinderModel(): Model
	local model = Instance.new("Model")
	model.Name = "Grinder"

	-- Main body — a dark metal box
	local body = Instance.new("Part")
	body.Name = "Body"
	body.Size = Vector3.new(4, 3, 4)
	body.Color = Color3.fromRGB(45, 45, 50)
	body.Material = Enum.Material.Metal
	body.Anchored = true
	body.CanCollide = true
	body.CFrame = CFrame.new(0, 1.5, 0)
	body.Parent = model
	model.PrimaryPart = body

	-- Hopper opening — a lighter funnel on top
	local hopper = Instance.new("Part")
	hopper.Name = "Hopper"
	hopper.Size = Vector3.new(3, 1, 3)
	hopper.Color = Color3.fromRGB(60, 60, 65)
	hopper.Material = Enum.Material.Metal
	hopper.Anchored = true
	hopper.CanCollide = false
	hopper.CFrame = CFrame.new(0, 3.5, 0)
	hopper.Parent = model

	-- Spinning blade assembly (rotated by a HingeConstraint on the server)
	local bladePivot = Instance.new("Part")
	bladePivot.Name = "BladePivot"
	bladePivot.Size = Vector3.new(0.4, 0.4, 0.4)
	bladePivot.Color = Color3.fromRGB(60, 60, 65)
	bladePivot.Material = Enum.Material.Metal
	bladePivot.Anchored = true
	bladePivot.CanCollide = false
	bladePivot.CFrame = CFrame.new(0, 2.8, 0)
	bladePivot.Parent = model

	local blade = Instance.new("Part")
	blade.Name = "Blade"
	blade.Size = Vector3.new(2.5, 0.2, 0.3)
	blade.Color = Color3.fromRGB(180, 180, 185)
	blade.Material = Enum.Material.Metal
	blade.Anchored = false
	blade.CanCollide = false
	blade.CFrame = CFrame.new(0, 2.8, 0)
	blade.Parent = model

	local blade2 = Instance.new("Part")
	blade2.Name = "Blade2"
	blade2.Size = Vector3.new(2.5, 0.2, 0.3)
	blade2.Color = Color3.fromRGB(180, 180, 185)
	blade2.Material = Enum.Material.Metal
	blade2.Anchored = false
	blade2.CanCollide = false
	blade2.CFrame = CFrame.new(0, 2.8, 0) * CFrame.Angles(0, math.rad(90), 0)
	blade2.Parent = model

	-- Weld blades together so they rotate as one unit
	local bladeWeld = Instance.new("WeldConstraint")
	bladeWeld.Part0 = blade
	bladeWeld.Part1 = blade2
	bladeWeld.Parent = blade

	-- Attachments for the hinge
	local pivotAtt = Instance.new("Attachment")
	pivotAtt.Name = "PivotAtt"
	pivotAtt.Axis = Vector3.new(0, 1, 0)
	pivotAtt.SecondaryAxis = Vector3.new(0, 0, 1)
	pivotAtt.Parent = bladePivot

	local bladeAtt = Instance.new("Attachment")
	bladeAtt.Name = "BladeAtt"
	bladeAtt.Axis = Vector3.new(0, 1, 0)
	bladeAtt.SecondaryAxis = Vector3.new(0, 0, 1)
	bladeAtt.Parent = blade

	-- HingeConstraint to spin the blade
	local hinge = Instance.new("HingeConstraint")
	hinge.Name = "BladeHinge"
	hinge.Attachment0 = pivotAtt
	hinge.Attachment1 = bladeAtt
	hinge.ActuatorType = Enum.ActuatorType.Motor
	hinge.MotorMaxTorque = 100
	hinge.AngularVelocity = 8
	hinge.Parent = bladePivot

	-- Chute where scrap comes out
	local chute = Instance.new("Part")
	chute.Name = "Chute"
	chute.Size = Vector3.new(1.5, 0.5, 1)
	chute.Color = Color3.fromRGB(35, 35, 40)
	chute.Material = Enum.Material.Metal
	chute.Anchored = true
	chute.CanCollide = false
	chute.CFrame = CFrame.new(0, 0.5, 2.2)
	chute.Parent = model

	return model
end

--[[
    @summary  Place the grinder next to the crafting bench.
    @desc     Called by CraftingService.placeBench() after the bench
              is positioned. The grinder goes on the opposite side
              of the campfire from the bench.
    @param    campfireCFrame  CFrame  -- the campfire anchor
]]
function GrinderService:PlaceGrinder(campfireCFrame: CFrame)
	if grinderModel then
		grinderModel:Destroy()
		grinderModel = nil
	end

	local model = buildGrinderModel()
	-- Position the grinder at the campfire offset; the model's parts
	-- are authored around the origin so PivotTo moves them all together.
	model:PivotTo(campfireCFrame * GRINDER_OFFSET)
	model.Parent = runStateService:GetRuntimeFolder()
	grinderModel = model
	grinderPosition = model:GetPivot().Position

	-- Add ProximityPrompt on the body
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "GrindPrompt"
	prompt.ActionText = "Grind"
	prompt.ObjectText = "Grinder"
	prompt.MaxActivationDistance = GRIND_RANGE
	prompt.HoldDuration = 0
	prompt.Parent = model.PrimaryPart
	prompt.Triggered:Connect(function(player)
		if runStateService:IsActive() and runStateService:IsMember(player) then
			GrinderService.Client.OpenGrinder:Fire(player)
		end
	end)
end

--[[
    @summary  Return whether a player is close enough to grind.
    @param    player  Player
    @returns  boolean
]]
local function isNearGrinder(player: Player): boolean
	if not grinderPosition then
		return false
	end
	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	if not rootPart or not rootPart:IsA("BasePart") then
		return false
	end
	return (rootPart.Position - grinderPosition).Magnitude <= GRIND_RANGE
end

--[[
    @summary  Process a single grind request with cooldown.
    @param    player  Player
    @param    junkId  string
    @returns  number  -- scrap granted
]]
local function processGrind(player: Player, junkId: string): number
	if not runStateService:IsActive() or not runStateService:IsMember(player) then
		return 0
	end
	if not isNearGrinder(player) then
		return 0
	end
	local now = os.clock()
	if cooldowns[player] and now - cooldowns[player] < GRIND_COOLDOWN then
		return 0
	end
	cooldowns[player] = now

	local config = JunkItemConfig[junkId]
	if not config then
		return 0
	end

	local added = inventoryService:GrindJunk(player, junkId)
	if added > 0 then
		GrinderService.Client.GrinderProcessed:Fire(player, {
			position = grinderPosition,
			scrapAmount = added,
			junkId = junkId,
		})
	end
	return added
end

-- | Public | --

--[[
    @summary  Return the grinder's world position (for client VFX).
    @returns  Vector3?
]]
function GrinderService:GetGrinderPosition(): Vector3?
	return grinderPosition
end

-- | Client Remotes | --

--[[
    @summary  Client-to-server: grind one junk item.
    @param    player  Player  -- injected by Knit
    @param    junkId  string
    @returns  number          -- scrap granted
]]
function GrinderService.Client:GrindItem(player: Player, junkId: string): number
	if typeof(junkId) ~= "string" then
		return 0
	end
	return processGrind(player, junkId)
end

--[[
    @summary  Client-to-server: grind all carried junk items.
    @desc     Iterates every junk item the player carries and grinds
              each one, returning the total scrap granted.
    @param    player  Player  -- injected by Knit
    @returns  number          -- total scrap granted
]]
function GrinderService.Client:GrindAll(player: Player): number
	if not runStateService:IsActive() or not runStateService:IsMember(player) then
		return 0
	end
	if not isNearGrinder(player) then
		return 0
	end
	if not inventoryService then
		return 0
	end
	local total = 0
	for junkId, _ in pairs(JunkItemConfig) do
		local count = inventoryService:GetResourceCount(player, junkId)
		for _ = 1, count do
			local added = processGrind(player, junkId)
			total += added
		end
	end
	return total
end

-- // INITIALIZATION // --

function GrinderService:KnitStart()
	runStateService = Knit.GetService("RunStateService")
	inventoryService = Knit.GetService("InventoryService")
	craftingService = Knit.GetService("CraftingService")

	runStateService.RunCleaned:Connect(function()
		if grinderModel then
			grinderModel:Destroy()
			grinderModel = nil
		end
		grinderPosition = nil
		cooldowns = {}
	end)

	local Players = game:GetService("Players")
	Players.PlayerRemoving:Connect(function(player)
		cooldowns[player] = nil
	end)
end

return GrinderService
