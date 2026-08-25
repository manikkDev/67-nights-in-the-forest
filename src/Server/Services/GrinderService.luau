--[[
    @file    GrinderService.luau
    @author  manik
    @date    2025

    @summary
    Server-authoritative junk-to-scrap shredder placed next to the crafting bench.

    @description
    Clones the pre-placed "Shredder" model from ServerStorage Assets Items
    and positions it beside the crafting bench each run. Players interact
    via ProximityPrompt to open the grind UI, then select junk items to
    convert into Scrap. Validates proximity and run membership on every
    grind request. Preserves the asset's built-in animations, constraints,
    and sounds.

    @exports
    - Knit Signal: OpenGrinder()          (server -> client, open UI)
    - Knit Signal: GrinderProcessed()     (server -> client, VFX)
    - Knit Remote: GrindItem(junkId)      (client -> server)
    - Knit Remote: GrindAll()             (client -> server)
]]

-- // VARIABLES // --

-- | Services | --
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- | Modules | --
local Knit = require(ReplicatedStorage.Packages.Knit)
local Constants = require(ReplicatedStorage.Shared.Constants)
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
-- Place the shredder beside the crafting bench (bench is at +14, 0, 0).
local GRINDER_OFFSET = CFrame.new(14, 0, 8)
local GRIND_RANGE = 10
local GRIND_COOLDOWN = 0.15
local SHREDDER_ASSET_NAME = "Shredder"

-- | State Management | --
local runStateService: any = nil
local inventoryService: any = nil
local grinderModel: Model? = nil
local grinderPosition: Vector3? = nil
local grinderPrimaryPart: BasePart? = nil
local cooldowns: { [Player]: number } = {}

-- // FUNCTIONS // --

-- | Private | --

--[[
    @summary  Find the best part to use as PrimaryPart in the shredder model.
    @desc     Prefers an existing PrimaryPart, then the largest anchored
              part (usually the main body), then the first BasePart.
    @param    model  Model
    @returns  BasePart?
]]
local function findPrimaryPart(model: Model): BasePart?
	if model.PrimaryPart and model.PrimaryPart.Parent then
		return model.PrimaryPart
	end

	local best: BasePart? = nil
	local bestVolume = 0
	for _, desc in ipairs(model:GetDescendants()) do
		if desc:IsA("BasePart") then
			local volume = desc.Size.X * desc.Size.Y * desc.Size.Z
			if volume > bestVolume then
				bestVolume = volume
				best = desc
			end
		end
	end
	return best
end

--[[
    @summary  Clone and prepare the Shredder asset from ServerStorage.
    @desc     Clones the pre-placed Shredder model, disables any scripts
              it contains (to prevent conflicts), ensures a PrimaryPart
              is set, and anchors all non-constraint parts. Preserves
              constraints and motors so built-in animations still work.
    @returns  Model?
]]
local function buildShredderModel(): Model?
	local itemsPath = ServerStorage.Assets:FindFirstChild(Constants.ITEMS_PATH)
	if not itemsPath then
		warn("[GrinderService] Assets Items folder not found in ServerStorage")
		return nil
	end

	local source = itemsPath:FindFirstChild(SHREDDER_ASSET_NAME)
	if not source then
		warn(("[GrinderService] '%s' asset not found in Assets Items"):format(SHREDDER_ASSET_NAME))
		return nil
	end

	local model = source:Clone()
	model.Name = "Grinder"

	-- Disable any scripts the asset author included to prevent conflicts.
	for _, desc in ipairs(model:GetDescendants()) do
		if desc:IsA("Script") or desc:IsA("LocalScript") then
			desc.Disabled = true
		end
	end

	-- Ensure PrimaryPart is set.
	if not model.PrimaryPart then
		local primary = findPrimaryPart(model)
		if primary then
			model.PrimaryPart = primary
		end
	end

	return model
end

--[[
    @summary  Place the shredder next to the crafting bench.
    @desc     Called by CraftingService.placeBench() after the bench
              is positioned. The shredder goes beside the bench on
              the same side of the campfire.
    @param    campfireCFrame  CFrame  -- the campfire anchor
]]
function GrinderService:PlaceGrinder(campfireCFrame: CFrame)
	if grinderModel then
		grinderModel:Destroy()
		grinderModel = nil
	end

	local model = buildShredderModel()
	if not model then
		return
	end

	-- Position the shredder at the offset from the campfire.
	-- Measure the model's bounding box so it sits flush on the ground.
	local _, size = model:GetBoundingBox()
	local groundOffset = CFrame.new(0, size.Y * 0.5, 0)
	model:PivotTo(campfireCFrame * GRINDER_OFFSET * groundOffset)
	model.Parent = runStateService:GetRuntimeFolder()
	grinderModel = model
	grinderPosition = model:GetPivot().Position
	grinderPrimaryPart = model.PrimaryPart

	-- Add or reuse a ProximityPrompt on the primary part.
	local anchor = model.PrimaryPart
	if not anchor then
		anchor = model:FindFirstChildWhichIsA("BasePart", true)
	end
	if not anchor then
		warn("[GrinderService] Shredder model has no BasePart for ProximityPrompt")
		return
	end

	local existingPrompt = anchor:FindFirstChildWhichIsA("ProximityPrompt")
	local prompt = existingPrompt or Instance.new("ProximityPrompt")
	prompt.Name = "GrindPrompt"
	prompt.ActionText = "Grind"
	prompt.ObjectText = "Shredder"
	prompt.MaxActivationDistance = GRIND_RANGE
	prompt.HoldDuration = 0
	prompt.Parent = anchor
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

--[[
    @summary  Return the grinder's primary part (for client VFX attachment).
    @returns  BasePart?
]]
function GrinderService:GetGrinderPrimaryPart(): BasePart?
	return grinderPrimaryPart
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

	runStateService.RunCleaned:Connect(function()
		if grinderModel then
			grinderModel:Destroy()
			grinderModel = nil
		end
		grinderPosition = nil
		grinderPrimaryPart = nil
		cooldowns = {}
	end)

	local Players = game:GetService("Players")
	Players.PlayerRemoving:Connect(function(player)
		cooldowns[player] = nil
	end)
end

return GrinderService
