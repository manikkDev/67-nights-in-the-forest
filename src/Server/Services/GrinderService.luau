--[[
    @file    GrinderService.luau
    @author  manik
    @date    2025

    @summary
    Server-authoritative junk-to-scrap shredder placed next to the crafting bench.

    @description
    Uses a pre-placed "Shredder" model. A copy can live in
    ServerStorage.Assets["Assets Items"] for auto-placement, or the
    developer can drag a model named "Shredder" or "Grinder" directly
    into Workspace to position it by hand. Players interact via a
    ProximityPrompt to open the grind UI and convert junk into Scrap.

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
local RunService = game:GetService("RunService")

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
-- Default spot: well clear of the bench (bench is at +14, 0, 0 from campfire).
local GRINDER_OFFSET = CFrame.new(14, 0, 18)
local GRIND_RANGE = 10
local GRIND_COOLDOWN = 0.15
local SHREDDER_ASSET_NAME = "Shredder"

-- | State Management | --
local runStateService: any = nil
local inventoryService: any = nil
local grinderModel: Model? = nil
local grinderPosition: Vector3? = nil
local grinderPrimaryPart: BasePart? = nil
local isManualModel = false
local cooldowns: { [Player]: number } = {}

-- // FUNCTIONS // --

-- | Private | --

--[[
    @summary  Find the best part to use as PrimaryPart in a model.
    @desc     Prefers an existing PrimaryPart, then the largest part.
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
    @summary  Anchor every BasePart in a model and disable its scripts.
    @desc     Keeps constraints/motors intact (so built-in animations still
              work) but freezes the assembly in world space so it can't fall.
    @param    model  Model
]]
local function anchorAndSanitize(model: Model)
	for _, desc in ipairs(model:GetDescendants()) do
		if desc:IsA("Script") or desc:IsA("LocalScript") then
			desc.Disabled = true
		elseif desc:IsA("BasePart") then
			desc.Anchored = true
		end
	end
end

--[[
    @summary  Find a manually placed Shredder/Grinder in Workspace.
    @returns  Model?
]]
local function findManualShredder(): Model?
	local workspaceModel = workspace:FindFirstChild("Shredder")
		or workspace:FindFirstChild("Grinder")
	if workspaceModel and workspaceModel:IsA("Model") then
		return workspaceModel
	end
	return nil
end

--[[
    @summary  Clone and prepare the Shredder asset from ServerStorage.
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
	return model
end

--[[
    @summary  Attach a Grind ProximityPrompt to the shredder model.
    @param    model  Model
]]
local function attachPrompt(model: Model)
	local anchor = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
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
    @summary  Place the shredder next to the crafting bench.
    @desc     Called by CraftingService.placeBench() after the bench
              is positioned. A manually placed "Shredder"/"Grinder"
              in Workspace takes priority and is left exactly where the
              developer put it. Otherwise a copy is cloned from
              ServerStorage and placed at the configured offset.
    @param    campfireCFrame  CFrame  -- the campfire anchor
]]
function GrinderService:PlaceGrinder(campfireCFrame: CFrame)
	if grinderModel and not isManualModel then
		grinderModel:Destroy()
	end
	grinderModel = nil
	grinderPosition = nil
	grinderPrimaryPart = nil
	isManualModel = false

	local model = findManualShredder()
	if model then
		isManualModel = true
		-- Keep the model exactly where the developer placed it.
		model.Name = "Grinder"
	else
		model = buildShredderModel()
		if not model then
			return
		end

		-- Position the cloned shredder clearly clear of the bench.
		local pivot = model:GetPivot()
		local _, size = model:GetBoundingBox()
		local groundOffset = CFrame.new(0, size.Y * 0.5, 0)
		model:PivotTo(campfireCFrame * GRINDER_OFFSET * groundOffset * pivot.Rotation)
		model.Parent = runStateService:GetRuntimeFolder()
	end

	if not model then
		return
	end

	if not model.PrimaryPart then
		local primary = findPrimaryPart(model)
		if primary then
			model.PrimaryPart = primary
		end
	end

	anchorAndSanitize(model)
	attachPrompt(model)

	grinderModel = model
	grinderPosition = model:GetPivot().Position
	grinderPrimaryPart = model.PrimaryPart
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
		if grinderModel and not isManualModel then
			grinderModel:Destroy()
		end
		grinderModel = nil
		grinderPosition = nil
		grinderPrimaryPart = nil
		isManualModel = false
		cooldowns = {}
	end)

	local Players = game:GetService("Players")
	Players.PlayerRemoving:Connect(function(player)
		cooldowns[player] = nil
	end)
end

return GrinderService
