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

-- Cached references to the two resource counter labels on the
-- crafting table (wood count and scrap/bolt count).
local woodCounter: TextLabel? = nil
local scrapCounter: TextLabel? = nil

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
    @summary  Strip package/script/sound content from a crafting bench.
    @desc     The packaged "crafting-table" asset ships with nested
              PackageLink / TextureConfiguration / ModuleScript content
              that calls require() on unowned asset IDs and loads an
              unauthorized sound (6160151677).  This removes those
              descendants but keeps the model's visuals.
    @param    model   Model
]]
local function sanitizeBench(model: Model)
	local doomed: { Instance } = {}
	for _, descendant in ipairs(model:GetDescendants()) do
		local className = descendant.ClassName
		if descendant:IsA("BaseScript")
			or descendant:IsA("ModuleScript")
			or descendant:IsA("PackageLink")
			or descendant:IsA("TextureConfiguration")
			or descendant:IsA("Sound")
			or className == "Package"
			or className == "Configuration"
			or (descendant:IsA("Sound") and descendant.SoundId == "rbxassetid://6160151677")
		then
			table.insert(doomed, descendant)
		end
	end
	for _, instance in ipairs(doomed) do
		instance:Destroy()
	end
end

--[[
    @summary  Destroy any Sound in the whole datamodel that references
              the unauthorized asset ID 6160151677.
    @desc     The crafting-table package may create sounds dynamically
              and parent them elsewhere.  Sweep every service to catch
              them, not just Workspace.
]]
local function destroyUnauthorizedSounds()
	local count = 0
	for _, service in ipairs(game:GetChildren()) do
		local success, descendants = pcall(service.GetDescendants, service)
		if not success or not descendants then
			continue
		end
		for _, descendant in ipairs(descendants) do
			if descendant:IsA("Sound") and descendant.SoundId == "rbxassetid://6160151677" then
				descendant:Destroy()
				count += 1
			end
		end
	end
	if count > 0 then
		print(("[CraftingService] Destroyed %d unauthorized sound(s)"):format(count))
	end
	return count
end

--[[
    @summary  Run an aggressive cleanup for the first ~30s of the session.
    @desc     PackageLink scripts execute on game load before Knit and can
              spawn background threads that keep creating sounds.  Sweep a
              few times after KnitStart to catch stragglers.
]]
local function runDelayedSoundSweep()
	task.delay(3, function()
		local sweeps = 0
		while sweeps < 6 do
			sweeps += 1
			destroyUnauthorizedSounds()
			task.wait(5)
		end
	end)
end

--[[
    @summary  Find the user-placed crafting table in Workspace.
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
    @summary  Clone and sanitize the user's crafting table.
    @desc     We clone the user's placed model, destroy the original
              (killing any PackageLink threads that are running), then
              sanitize and parent the clone.  This preserves the user's
              art/position while eliminating the package errors.
    @returns  Model?
]]
local function cleanManualBench(): Model?
	local original = findManualBench()
	if not original then
		return nil
	end

	-- Clone FIRST so we keep the visuals.
	local clone = original:Clone()
	clone.Name = "CraftingBench"
	clone:BreakJoints()

	-- Destroy the original to kill PackageLink threads that already
	-- started on game load.  Without the original, the package scripts
	-- cannot keep creating sounds.
	local originalCFrame = original:GetPivot()
	original:Destroy()

	-- Sanitize the clone BEFORE parenting it anywhere, so its own
	-- PackageLink (if any) cannot execute.
	sanitizeBench(clone)

	-- Parent the clean clone back to Workspace at the same position.
	-- A Model has no parent until first set, so it didn't execute yet.
	clone:PivotTo(originalCFrame)
	clone.Parent = workspace

	return clone
end

--[[
    @summary  Discover the wood and scrap counter labels on the bench.
    @desc     The crafting table has two TextLabels showing the current
              wood and scrap counts.  We find them by name and by their
              sibling icon (ImageLabel/Decal with wood or bolt imagery).
    @returns  TextLabel? woodCounter, TextLabel? scrapCounter
]]
local function findTableCounters(model: Model): (TextLabel?, TextLabel?)
	local counters: { TextLabel } = {}
	for _, desc in ipairs(model:GetDescendants()) do
		if desc:IsA("TextLabel") then
			table.insert(counters, desc)
		end
	end

	local function isWoodName(name: string): boolean
		local lower = name:lower()
		return lower:find("wood") ~= nil
			or lower:find("log") ~= nil
			or lower:find("tree") ~= nil
			or name == "Slot1"
			or name == "Resource1"
	end

	local function isScrapName(name: string): boolean
		local lower = name:lower()
		return lower:find("scrap") ~= nil
			or lower:find("bolt") ~= nil
			or lower:find("metal") ~= nil
			or lower:find("sheet") ~= nil
			or name == "Slot2"
			or name == "Resource2"
	end

	local function hasWoodIcon(parent: Instance): boolean
		for _, child in ipairs(parent:GetChildren()) do
			if child:IsA("ImageLabel") or child:IsA("ImageButton") or child:IsA("Decal") then
				local id = (child :: any).Image or (child :: any).Texture
				local name = child.Name:lower()
				if (id and (id:find("wood") or id:find("log"))) or isWoodName(name) then
					return true
				end
			end
		end
		return false
	end

	local function hasScrapIcon(parent: Instance): boolean
		for _, child in ipairs(parent:GetChildren()) do
			if child:IsA("ImageLabel") or child:IsA("ImageButton") or child:IsA("Decal") then
				local id = (child :: any).Image or (child :: any).Texture
				local name = child.Name:lower()
				if (id and (id:find("scrap") or id:find("bolt") or id:find("metal"))) or isScrapName(name) then
					return true
				end
			end
		end
		return false
	end

	-- Score each TextLabel: exact name match > sibling icon > text "0" > any
	local woodBest: TextLabel? = nil
	local woodScore = 0
	local scrapBest: TextLabel? = nil
	local scrapScore = 0

	for _, label in ipairs(counters) do
		local name = label.Name
		local parent = label.Parent
		local text = label.Text

		-- Wood scoring
		local wScore = 0
		if isWoodName(name) then
			wScore = 100
		elseif parent and isWoodName(parent.Name) then
			wScore = 90
		elseif parent and hasWoodIcon(parent) then
			wScore = 80
		elseif parent and parent.Parent and isWoodName(parent.Parent.Name) then
			wScore = 70
		elseif parent and parent.Parent and hasWoodIcon(parent.Parent) then
			wScore = 60
		elseif text == "0" then
			wScore = 10
		end
		if wScore > woodScore and label ~= scrapBest then
			woodBest = label
			woodScore = wScore
		end

		-- Scrap scoring
		local sScore = 0
		if isScrapName(name) then
			sScore = 100
		elseif parent and isScrapName(parent.Name) then
			sScore = 90
		elseif parent and hasScrapIcon(parent) then
			sScore = 80
		elseif parent and parent.Parent and isScrapName(parent.Parent.Name) then
			sScore = 70
		elseif parent and parent.Parent and hasScrapIcon(parent.Parent) then
			sScore = 60
		elseif text == "0" then
			sScore = 10
		end
		if sScore > scrapScore and label ~= woodBest then
			scrapBest = label
			scrapScore = sScore
		end
	end

	-- Fallback: if no strong match, pick the two leftmost/rightmost
	-- TextLabels whose parents are SurfaceGuis on the table.  This handles
	-- packages that use generic names like "TextLabel" for both counters.
	if not woodBest or not scrapBest then
		local zeroLabels: { TextLabel } = {}
		for _, label in ipairs(counters) do
			if label.Text == "0" then
				table.insert(zeroLabels, label)
			end
		end
		if #zeroLabels >= 2 then
			-- Try to get a 3D position for each label by tracing up to a BasePart.
			local function getPartPosition(label: TextLabel): (Vector3?, BasePart?)
				local current: Instance? = label
				while current do
					if current:IsA("BasePart") then
						return (current :: BasePart).Position, current :: BasePart
					end
					current = current.Parent
				end
				return nil, nil
			end

			local function leftToRight(a: TextLabel, b: TextLabel): boolean
				local posA = getPartPosition(a)
				local posB = getPartPosition(b)
				if posA and posB then
					return posA.X < posB.X
				end
				return a.Name < b.Name
			end

			table.sort(zeroLabels, leftToRight)

			if not woodBest then
				woodBest = zeroLabels[1]
			end
			if not scrapBest then
				scrapBest = zeroLabels[2]
			end
		end
	end

	if not woodBest and not scrapBest then
		warn("[CraftingService] Could not find wood/scrap counter labels on the crafting table")
	end

	return woodBest, scrapBest
end

--[[
    @summary  Update the wood and scrap counter TextLabels on the table.
    @param    resources  table  -- { Wood = N, Scrap = N, ... }
]]
local function updateTableCounters(resources: { [string]: number }?)
	if not resources then
		return
	end
	if woodCounter and woodCounter.Parent then
		woodCounter.Text = tostring(resources.Wood or 0)
	end
	if scrapCounter and scrapCounter.Parent then
		scrapCounter.Text = tostring(resources.Scrap or 0)
	end
end

--[[
    @summary  Attach a crafting ProximityPrompt to the bench.
    @param    model  Model
]]
local function attachPrompt(model: Model)
	local anchor = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
	if not anchor then
		return
	end

	local existing = anchor:FindFirstChild("CraftingPrompt")
	if existing and existing:IsA("ProximityPrompt") then
		existing:Destroy()
	end

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "CraftingPrompt"
	prompt.ActionText = "Craft"
	prompt.ObjectText = "Crafting Bench"
	prompt.MaxActivationDistance = BENCH_RANGE
	prompt.HoldDuration = 0.25
	prompt.Parent = anchor
	prompt.Triggered:Connect(function(player)
		if runStateService:IsActive() and runStateService:IsMember(player) then
			CraftingService.Client.OpenCrafting:Fire(player)
		end
	end)
end

--[[
    @summary  Place the user's crafting table (or a clean copy) and set
              up the shredder beside it.
]]
local function placeBench()
	if benchModel then
		benchModel:Destroy()
	end
	benchModel = nil
	isManualBench = false
	woodCounter = nil
	scrapCounter = nil

	local campfireCFrame = worldService and worldService:GetCampfireCFrame()
	if not campfireCFrame then
		warn("[CraftingService] campfire is missing")
		return
	end

	local manualBench = cleanManualBench()
	local clone: Model?

	if manualBench then
		clone = manualBench
		isManualBench = true
		print("[CraftingService] Using sanitized user crafting-table")
	else
		-- No manual bench: try the ServerStorage source.
		local mapsItems = ServerStorage.Assets:FindFirstChild("Assets maps items")
		local source = mapsItems and mapsItems:FindFirstChild("crafting-table")
		if source and source:IsA("Model") then
			local sourceModel = source :: Model
			local benchClone = sourceModel:Clone() :: Model
			benchClone.Name = "CraftingBench"
			sanitizeBench(benchClone)
			local _, size = benchClone:GetBoundingBox()
			local pivot = benchClone:GetPivot()
			benchClone:PivotTo(campfireCFrame * BENCH_OFFSET * CFrame.new(0, size.Y * 0.5, 0) * pivot.Rotation)
			benchClone.Parent = runStateService:GetRuntimeFolder()
			clone = benchClone
		else
			warn("[CraftingService] crafting-table asset is missing")
			return
		end
	end

	assert(clone, "[CraftingService] bench clone is nil")
	local bench = clone :: Model

	if not bench.PrimaryPart then
		local primary = bench:FindFirstChildWhichIsA("BasePart", true)
		if primary then
			bench.PrimaryPart = primary
		end
	end

	benchModel = bench
	woodCounter, scrapCounter = findTableCounters(bench)

	-- Make sure the user can see it in Studio when not playtesting.
	if isManualBench then
		bench:SetAttribute("DevinManualBench", true)
	end

	attachPrompt(bench)

	-- Initial counter values
	local members = runStateService:GetMembers()
	if #members > 0 and playerDataService then
		local data = playerDataService:GetData(members[1])
		if data and data.Resources then
			updateTableCounters(data.Resources)
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

	-- The packaged asset fires PackageLink / TextureConfiguration on
	-- game load before Knit starts.  We can't prevent the initial
	-- burst, but we can catch stragglers with periodic sound sweeps.
	-- The actual manual bench is preserved and sanitized on RunStarted
	-- via cleanManualBench().
	destroyUnauthorizedSounds()
	runDelayedSoundSweep()

	runStateService.RunStarted:Connect(resetForRun)
	runStateService.RunCleaned:Connect(function()
		-- Keep the user's manual bench visible in Studio between runs.
		if benchModel and not isManualBench then
			benchModel:Destroy()
		end
		if not isManualBench then
			benchModel = nil
		end
		woodCounter = nil
		scrapCounter = nil
		placementTokens = {}
		craftCooldowns = {}
	end)

	-- Update the table's wood/scrap counters whenever resources change
	-- (pickup, grind, craft, drop, etc.)
	inventoryService.ServerResourcesChanged:Connect(function(player, resources)
		if runStateService:IsActive() and runStateService:IsMember(player) then
			updateTableCounters(resources)
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		placementTokens[player] = nil
		craftCooldowns[player] = nil
	end)
end

return CraftingService
