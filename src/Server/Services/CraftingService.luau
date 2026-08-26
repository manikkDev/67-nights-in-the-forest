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
    @summary  Find and DESTROY any manually placed crafting-table.
    @desc     The packaged "crafting-table" asset ships with nested
              PackageLink / TextureConfiguration modules that call
              require() on unowned asset IDs and load an unauthorized
              sound (6160151677).  These fire on Workspace load BEFORE
              any server script runs, and the package scripts keep
              creating new Sound instances throughout the session.
              Sanitization cannot stop this because the scripts already
              executed.  The only reliable fix is to destroy the entire
              model and replace it with a clean, code-built table.
]]
local function destroyManualBench()
	local manual = workspace:FindFirstChild("crafting-table")
		or workspace:FindFirstChild("CraftingBench")
	if manual and manual:IsA("Model") then
		manual.Name = "DestroyedBench"
		manual:Destroy()
		print("[CraftingService] Destroyed packaged crafting-table (PackageLink source)")
	end
end

--[[
    @summary  Build a clean crafting bench from primitive parts.
    @desc     No PackageLink, no TextureConfiguration, no unauthorized
              sounds — just a simple wooden table with a ProximityPrompt.
              This replaces the packaged asset entirely.
    @param    campfireCFrame  CFrame  -- anchor for positioning
    @returns  Model
]]
local function buildCleanBench(campfireCFrame: CFrame): Model
	local model = Instance.new("Model")
	model.Name = "CraftingBench"

	local top = Instance.new("Part")
	top.Name = "TableTop"
	top.Size = Vector3.new(4, 0.4, 3)
	top.Color = Color3.fromRGB(101, 67, 33)
	top.Material = Enum.Material.WoodPlanks
	top.Anchored = true
	top.CanCollide = true
	top.TopSurface = Enum.SurfaceType.Smooth
	top.BottomSurface = Enum.SurfaceType.Smooth
	top.Parent = model

	model.PrimaryPart = top

	-- Four legs
	local legPositions = {
		Vector3.new(1.7, -1.2, 1.2),
		Vector3.new(-1.7, -1.2, 1.2),
		Vector3.new(1.7, -1.2, -1.2),
		Vector3.new(-1.7, -1.2, -1.2),
	}
	for i, offset in ipairs(legPositions) do
		local leg = Instance.new("Part")
		leg.Name = "Leg" .. tostring(i)
		leg.Size = Vector3.new(0.3, 2.4, 0.3)
		leg.Color = Color3.fromRGB(80, 50, 25)
		leg.Material = Enum.Material.Wood
		leg.Anchored = true
		leg.CanCollide = true
		leg.Parent = model
		-- Position will be set by PivotTo on the model
	end

	-- Position the entire bench
	local groundY = campfireCFrame.Position.Y
	local benchCFrame = campfireCFrame * BENCH_OFFSET
	-- Top surface at ~1.5 studs high (legs go into ground)
	top.CFrame = benchCFrame * CFrame.new(0, 1.5, 0)
	for i, offset in ipairs(legPositions) do
		local leg = model:FindFirstChild("Leg" .. tostring(i))
		if leg then
			leg.CFrame = top.CFrame * CFrame.new(offset)
		end
	end

	-- ProximityPrompt on the tabletop
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "CraftingPrompt"
	prompt.ActionText = "Craft"
	prompt.ObjectText = "Crafting Bench"
	prompt.MaxActivationDistance = BENCH_RANGE
	prompt.HoldDuration = 0.25
	prompt.Parent = top
	prompt.Triggered:Connect(function(player)
		if runStateService:IsActive() and runStateService:IsMember(player) then
			CraftingService.Client.OpenCrafting:Fire(player)
		end
	end)

	return model
end

--[[
    @summary  Update the visual resource stacks on the crafting bench.
    @desc     Shows piled wood logs and metal sheets on the tabletop,
              matching the reference game where you can see collected
              resources stacked on the bench.
    @param    resources  table  -- { Wood = N, Scrap = N, ... }
]]
local stackFolder: Folder? = nil
local function updateResourceStacks(resources: { [string]: number }?)
	if not benchModel or not benchModel.Parent then
		return
	end
	if not stackFolder or not stackFolder.Parent then
		stackFolder = Instance.new("Folder")
		stackFolder.Name = "ResourceStacks"
		stackFolder.Parent = benchModel
	end
	-- Clear existing stacks
	for _, child in ipairs(stackFolder:GetChildren()) do
		child:Destroy()
	end
	if not resources then
		return
	end

	local topPart = benchModel:FindFirstChild("TableTop")
	if not topPart then
		return
	end
	local topPos = topPart.Position + Vector3.new(0, 0.25, 0) -- just above surface

	-- Wood logs: stack small brown cylinders on the left side
	local woodCount = math.min(resources.Wood or 0, 20) -- cap visual at 20
	for i = 1, woodCount do
		local log = Instance.new("Part")
		log.Name = "WoodLog" .. tostring(i)
		log.Size = Vector3.new(0.3, 0.3, 1.2)
		log.Color = Color3.fromRGB(120, 80, 40)
		log.Material = Enum.Material.Wood
		log.Anchored = true
		log.CanCollide = false
		-- Stack in a pyramid pattern on the left
		local row = math.floor((i - 1) / 4)
		local col = (i - 1) % 4
		local x = -1.2 + col * 0.35
		local z = -0.4 + (row % 2) * 0.3
		local y = 0.2 + math.floor(row / 2) * 0.3
		log.CFrame = topPart.CFrame * CFrame.new(x, y, z) * CFrame.Angles(0, math.rad(90), 0)
		log.Parent = stackFolder
	end

	-- Scrap metal sheets: stack thin gray plates on the right side
	local scrapCount = math.min(resources.Scrap or 0, 15)
	for i = 1, scrapCount do
		local sheet = Instance.new("Part")
		sheet.Name = "ScrapSheet" .. tostring(i)
		sheet.Size = Vector3.new(0.8, 0.05, 0.6)
		sheet.Color = Color3.fromRGB(140, 140, 150)
		sheet.Material = Enum.Material.Metal
		sheet.Anchored = true
		sheet.CanCollide = false
		-- Stack on the right side, each slightly higher
		local y = 0.25 + (i - 1) * 0.06
		sheet.CFrame = topPart.CFrame * CFrame.new(1.0, y, 0) * CFrame.Angles(0, math.rad(i * 15), 0)
		sheet.Parent = stackFolder
	end
end

--[[
    @summary  Place a clean crafting table beside the campfire.
    @desc     The packaged asset is destroyed on KnitStart to eliminate
              PackageLink errors.  A simple code-built table replaces it.
]]
local function placeBench()
	if benchModel then
		benchModel:Destroy()
	end
	benchModel = nil
	isManualBench = false
	stackFolder = nil

	local campfireCFrame = worldService and worldService:GetCampfireCFrame()
	if not campfireCFrame then
		warn("[CraftingService] campfire is missing")
		return
	end

	local bench = buildCleanBench(campfireCFrame)
	bench.Parent = runStateService:GetRuntimeFolder()
	benchModel = bench

	-- Update visual stacks from current resources
	local firstMember = runStateService:GetMembers()[1]
	if firstMember and playerDataService then
		local data = playerDataService:GetData(firstMember)
		if data and data.Resources then
			updateResourceStacks(data.Resources)
		end
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

	-- Immediately destroy any manually-placed crafting-table.
	-- The packaged asset ships with nested PackageLink /
	-- TextureConfiguration modules that call require() on unowned
	-- asset IDs and load an unauthorized sound (6160151677).  These
	-- fire on game load before Knit starts and the package scripts
	-- keep creating new Sound instances throughout the session.
	-- Sanitization cannot stop this — the only fix is to destroy the
	-- entire model and replace it with a clean, code-built table.
	destroyManualBench()

	runStateService.RunStarted:Connect(resetForRun)
	runStateService.RunCleaned:Connect(function()
		if benchModel then
			benchModel:Destroy()
		end
		benchModel = nil
		isManualBench = false
		stackFolder = nil
		placementTokens = {}
		craftCooldowns = {}
	end)

	-- Update visual resource stacks on the bench whenever resources
	-- change (pickup, grind, craft, drop, etc.)
	inventoryService.ServerResourcesChanged:Connect(function(player, resources)
		if runStateService:IsActive() and runStateService:IsMember(player) then
			updateResourceStacks(resources)
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		placementTokens[player] = nil
		craftCooldowns[player] = nil
	end)
end

return CraftingService
