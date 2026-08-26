--[[
    @file    CraftingService.luau
    @author  manik
    @date    2025

    @summary
    Server-authoritative crafting bench tiers, recipe transactions,
    recipe caps, unlocks, and one-use building placement tokens.

    @exports
    - CraftingService:GetBenchTier() -> number
    - CraftingService:GetPlacementToken(player, tokenId) -> table?
    - CraftingService:ConsumePlacementToken(player, tokenId) -> boolean
    - Knit Remote: GetBenchState()
    - Knit Remote: RequestCraft(recipeId)
]]

-- // VARIABLES // --

-- | Services | --
local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

-- | Modules | --
local Knit = require(ReplicatedStorage.Packages.Knit)
local RecipeConfig = require(ReplicatedStorage.Shared.RecipeConfig)

-- | Objects | --
local CraftingService = Knit.CreateService({
	Name = "CraftingService",
	Client = {
		OpenCrafting = Knit.CreateSignal(),
		CraftingStateChanged = Knit.CreateSignal(),
		CraftSucceeded = Knit.CreateSignal(),
	},
})

-- | Configuration | --
local BENCH_RANGE = 16
local CRAFT_COOLDOWN = 0.2
local BENCH_OFFSET = CFrame.new(14, 0, 0)

-- | State Management | --
local runStateService: any = nil
local playerDataService: any = nil
local inventoryService: any = nil
local worldService: any = nil
local grinderService: any = nil

local benchTier = 1
local benchModel: Model? = nil
local isManualBench = false
local recipeCounts: { [string]: number } = {}
local unlocks: { [string]: boolean } = {}
local placementTokens: { [Player]: { [string]: { structureId: string, runId: string } } } = {}
local craftCooldowns: { [Player]: number } = {}

-- // FUNCTIONS // --

-- | Private | --

--[[
    @summary  Return the world position used for crafting range checks.
    @returns  Vector3?
]]
local function getBenchPosition(): Vector3?
	if not benchModel or not benchModel.Parent then
		return nil
	end
	return benchModel:GetPivot().Position
end

--[[
    @summary  Return whether a player may interact with the live bench.
    @param    player  Player
    @returns  boolean
]]
local function isNearBench(player: Player): boolean
	local benchPosition = getBenchPosition()
	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not benchPosition or not rootPart or not rootPart:IsA("BasePart") then
		return false
	end
	if not humanoid or humanoid.Health <= 0 then
		return false
	end
	return (rootPart.Position - benchPosition).Magnitude <= BENCH_RANGE
end

--[[
    @summary  Return whether the player owns every cost in a recipe.
    @param    player  Player
    @param    cost    table
    @returns  boolean
]]
local function canAfford(player: Player, cost: { [string]: number }): boolean
	local data = playerDataService and playerDataService:GetData(player)
	if not data or not data.Resources then
		return false
	end
	for resourceName, amount in pairs(cost) do
		if (data.Resources[resourceName] or 0) < amount then
			return false
		end
	end
	return true
end

--[[
    @summary  Deduct a fully validated recipe cost without yielding.
    @param    player  Player
    @param    cost    table
]]
local function deductCost(player: Player, cost: { [string]: number })
	playerDataService:UpdateData(player, function(data)
		for resourceName, amount in pairs(cost) do
			data.Resources[resourceName] -= amount
			if data.Inventory and data.Inventory.PickupOrder then
				for _ = 1, amount do
					for index = #data.Inventory.PickupOrder, 1, -1 do
						if data.Inventory.PickupOrder[index] == resourceName then
							table.remove(data.Inventory.PickupOrder, index)
							break
						end
					end
				end
			end
		end
	end)
end

--[[
    @summary  Create and remember one opaque building placement token.
    @param    player       Player
    @param    structureId  string
    @returns  string
]]
local function grantPlacementToken(player: Player, structureId: string): string
	local tokenId = HttpService:GenerateGUID(false)
	placementTokens[player] = placementTokens[player] or {}
	placementTokens[player][tokenId] = {
		structureId = structureId,
		runId = runStateService:GetRunId(),
	}
	return tokenId
end

--[[
    @summary  Send a current crafting snapshot to all run members.
]]
local function broadcastState()
	local snapshot = {
		tier = benchTier,
		recipeCounts = table.clone(recipeCounts),
		unlocks = table.clone(unlocks),
	}
	for _, player in ipairs(runStateService:GetMembers()) do
		CraftingService.Client.CraftingStateChanged:Fire(player, snapshot)
	end
end

--[[
    @summary  Find a manually placed crafting table in Workspace.
    @returns  Model?
]]
local function findManualBench(): Model?
	local manual = workspace:FindFirstChild("crafting-table")
		or workspace:FindFirstChild("CraftingBench")
	if manual and manual:IsA("Model") then
		return manual
	end
	return nil
end

--[[
    @summary  Strip package/script/sound content that errors at runtime.
    @desc     The crafting-table asset ships with nested PackageLink and
              TextureConfiguration modules that call require() on asset
              IDs this place doesn't own, plus a Sound referencing the
              unauthorized asset 6160151677.  Both spam the Output window
              on every run.  Collect first, then destroy, so we never
              mutate the tree we are iterating.
    @param    model   Model
    @param    anchor  boolean  -- anchor BaseParts (clones only)
]]
local function sanitizeBench(model: Model, anchor: boolean)
	local doomed: { Instance } = {}
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BaseScript")
			or descendant:IsA("ModuleScript")
			or descendant:IsA("PackageLink")
			or descendant:IsA("TextureConfiguration")
			or descendant:IsA("Sound")
		then
			table.insert(doomed, descendant)
		elseif anchor and descendant:IsA("BasePart") then
			descendant.Anchored = true
		end
	end
	for _, instance in ipairs(doomed) do
		instance:Destroy()
	end
end

--[[
    @summary  Place the existing crafting table beside the campfire.
    @desc     A manually placed "crafting-table" or "CraftingBench" in
              Workspace is used exactly where the developer put it and
              survives run cleanup so it stays visible in Studio.
]]
local function placeBench()
	if benchModel and not isManualBench then
		benchModel:Destroy()
	end
	benchModel = nil
	isManualBench = false

	local manual = findManualBench()
	local campfireCFrame = worldService and worldService:GetCampfireCFrame()
	if not campfireCFrame then
		warn("[CraftingService] campfire is missing")
		return
	end

	local clone: Model?
	if manual then
		isManualBench = true
		manual.Name = "CraftingBench"
		clone = manual
	else
		local mapsItems = ServerStorage.Assets:FindFirstChild("Assets maps items")
		local source = mapsItems and mapsItems:FindFirstChild("crafting-table")
		if not source or not source:IsA("Model") then
			warn("[CraftingService] crafting-table asset is missing")
			return
		end

		clone = source:Clone()
		clone.Name = "CraftingBench"

		local pivot = clone:GetPivot()
		local _, size = clone:GetBoundingBox()
		clone:PivotTo(campfireCFrame * BENCH_OFFSET * CFrame.new(0, size.Y * 0.5, 0) * pivot.Rotation)
		clone.Parent = runStateService:GetRuntimeFolder()
	end

	if not clone then
		return
	end

	-- Sanitize BOTH the manual and cloned bench.  The manual
	-- "crafting-table" in Workspace ships with PackageLink /
	-- TextureConfiguration content that tries to require unowned asset
	-- IDs and load an unauthorized sound, spamming the Output window.
	sanitizeBench(clone, not isManualBench)

	benchModel = clone

	-- Reuse the prompt the model author placed (keeps its original
	-- attachment offset/position). Fall back to the primary part if none.
	local prompt = clone:FindFirstChildWhichIsA("ProximityPrompt", true)
	if not prompt then
		local anchor = clone.PrimaryPart or clone:FindFirstChildWhichIsA("BasePart", true)
		if anchor then
			prompt = Instance.new("ProximityPrompt")
			prompt.Parent = anchor
		end
	end

	if prompt then
		prompt.Name = "CraftingPrompt"
		prompt.ActionText = "Craft"
		prompt.ObjectText = "Crafting Bench"
		prompt.MaxActivationDistance = BENCH_RANGE
		prompt.HoldDuration = 0.25
		prompt.Triggered:Connect(function(player)
			if runStateService:IsActive() and runStateService:IsMember(player) then
				CraftingService.Client.OpenCrafting:Fire(player)
			end
		end)
	end

	-- Place the shredder next to the bench (same side of campfire)
	if grinderService then
		grinderService:PlaceGrinder(campfireCFrame)
	end
end

--[[
    @summary  Clear all crafting progress and place a fresh bench.
]]
local function resetForRun()
	benchTier = 1
	recipeCounts = {}
	unlocks = {}
	placementTokens = {}
	craftCooldowns = {}
	placeBench()
	broadcastState()
end

-- | Public | --

--[[
    @summary  Return the current shared crafting bench tier.
    @returns  number
]]
function CraftingService:GetBenchTier(): number
	return benchTier
end

--[[
    @summary  Return whether a navigation utility has been crafted.
    @param    unlockId  string
    @returns  boolean
]]
function CraftingService:HasUnlock(unlockId: string): boolean
	return unlocks[unlockId] == true
end

--[[
    @summary  Return a copy of a live placement token owned by a player.
    @param    player   Player
    @param    tokenId  string
    @returns  table?
]]
function CraftingService:GetPlacementToken(player: Player, tokenId: string): { [string]: string }?
	local token = placementTokens[player] and placementTokens[player][tokenId]
	if not token then
		return nil
	end
	return table.clone(token)
end

--[[
    @summary  Consume one live placement token after successful placement.
    @param    player   Player
    @param    tokenId  string
    @returns  boolean
]]
function CraftingService:ConsumePlacementToken(player: Player, tokenId: string): boolean
	local token = placementTokens[player] and placementTokens[player][tokenId]
	if not token or token.runId ~= runStateService:GetRunId() then
		return false
	end
	placementTokens[player][tokenId] = nil
	return true
end

--[[
    @summary  Return the caller's current crafting state.
    @param    player  Player  -- injected by Knit
    @returns  table
]]
function CraftingService.Client:GetBenchState(player: Player): { [string]: any }
	local data = playerDataService and playerDataService:GetData(player)
	return {
		tier = benchTier,
		resources = if data then table.clone(data.Resources) else {},
		recipeCounts = table.clone(recipeCounts),
		unlocks = table.clone(unlocks),
		isNearBench = isNearBench(player),
	}
end

--[[
    @summary  Validate and perform one crafting transaction.
    @param    player    Player  -- injected by Knit
    @param    recipeId  string
    @returns  table
]]
function CraftingService.Client:RequestCraft(player: Player, recipeId: string): { [string]: any }
	if typeof(recipeId) ~= "string" then
		return { ok = false, code = "INVALID_RECIPE" }
	end
	if not runStateService:IsActive() or not runStateService:IsMember(player) then
		return { ok = false, code = "NOT_ACTIVE" }
	end

	local recipe = RecipeConfig[recipeId]
	if not recipe then
		return { ok = false, code = "INVALID_RECIPE" }
	end
	if recipe.Tier > benchTier then
		return { ok = false, code = "WRONG_TIER" }
	end
	if recipe.RunCap and (recipeCounts[recipeId] or 0) >= recipe.RunCap then
		return { ok = false, code = "CAP_REACHED" }
	end
	if not isNearBench(player) then
		return { ok = false, code = "NOT_NEAR_BENCH" }
	end

	local now = os.clock()
	if craftCooldowns[player] and now - craftCooldowns[player] < CRAFT_COOLDOWN then
		return { ok = false, code = "RATE_LIMITED" }
	end
	if not canAfford(player, recipe.Cost) then
		return { ok = false, code = "INSUFFICIENT_RESOURCES" }
	end

	craftCooldowns[player] = now
	local capturedRunId = runStateService:GetRunId()
	deductCost(player, recipe.Cost)
	if not runStateService:IsCurrentRun(capturedRunId) then
		return { ok = false, code = "RUN_CHANGED" }
	end

	recipeCounts[recipeId] = (recipeCounts[recipeId] or 0) + 1
	local response = { ok = true, code = "OK", outputKind = recipe.OutputKind, outputId = recipe.OutputId }

	if recipe.OutputKind == "Placement" then
		response.placementToken = grantPlacementToken(player, recipe.OutputId)
	elseif recipe.OutputKind == "Item" then
		inventoryService:AddResource(player, recipe.OutputId, 1)
	elseif recipe.OutputKind == "Unlock" then
		unlocks[recipe.OutputId] = true
	elseif recipe.OutputKind == "BenchUpgrade" then
		benchTier = math.max(benchTier, tonumber(recipe.OutputId) or benchTier)
	end

	inventoryService:Refresh(player)
	broadcastState()
	CraftingService.Client.CraftSucceeded:Fire(player, recipeId, response)
	return response
end

-- // INITIALIZATION // --

function CraftingService:KnitStart()
	runStateService = Knit.GetService("RunStateService")
	playerDataService = Knit.GetService("PlayerDataService")
	inventoryService = Knit.GetService("InventoryService")
	worldService = Knit.GetService("WorldService")
	grinderService = Knit.GetService("GrinderService")

	runStateService.RunStarted:Connect(resetForRun)
	runStateService.RunCleaned:Connect(function()
		if benchModel and not isManualBench then
			benchModel:Destroy()
		end
		benchModel = nil
		isManualBench = false
		placementTokens = {}
		craftCooldowns = {}
	end)

	Players.PlayerRemoving:Connect(function(player)
		placementTokens[player] = nil
		craftCooldowns[player] = nil
	end)
end

return CraftingService
