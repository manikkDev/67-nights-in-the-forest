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
local ServerRole = require(ReplicatedStorage.Shared.ServerRole)
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

-- Cached references to the resource counter labels on the
-- crafting table (wooden sheet count, scrap/bolt count).
-- These show the SHARED run total of shredded output, not
-- individual player inventory.
local woodenSheetCounter: TextLabel? = nil
local scrapCounter: TextLabel? = nil

-- Shared run totals: how much WoodenSheet and Scrap have been
-- produced by ALL team members via the shredder this run.
local totalWoodenSheetShredded = 0
local totalScrapShredded = 0

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
    @desc     WoodenSheet is checked against the shared run total
              (totalWoodenSheetShredded), not the player's personal
              inventory, because WoodenSheet is a bench-only resource.
              All other resources are checked against personal inventory.
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
		if resourceName == "WoodenSheet" then
			if totalWoodenSheetShredded < amount then
				return false
			end
		else
			if (data.Resources[resourceName] or 0) < amount then
				return false
			end
		end
	end
	return true
end

--[[
    @summary  Deduct a fully validated recipe cost without yielding.
    @desc     WoodenSheet is deducted from the shared run total
              (totalWoodenSheetShredded). All other resources are
              deducted from the player's personal inventory.
    @param    player  Player
    @param    cost    table
]]
local function deductCost(player: Player, cost: { [string]: number })
	local benchDeduct = 0
	for resourceName, amount in pairs(cost) do
		if resourceName == "WoodenSheet" then
			benchDeduct += amount
		end
	end
	if benchDeduct > 0 then
		totalWoodenSheetShredded = math.max(0, totalWoodenSheetShredded - benchDeduct)
		updateTableCounters()
	end
	playerDataService:UpdateData(player, function(data)
		for resourceName, amount in pairs(cost) do
			if resourceName ~= "WoodenSheet" then
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
    @summary  Discover the wooden sheet and scrap counter labels.
    @desc     The crafting table has two SurfaceGui panels with counter
              TextLabels. The panel with an ImageLabel shows the
              WoodenSheet count. The panel with an emoji (🔩) shows
              the Scrap count.
    @returns  TextLabel? woodenSheetCounter, TextLabel? scrapCounter
]]
local function findTableCounters(model: Model): (TextLabel?, TextLabel?)
	local allLabels: { TextLabel } = {}
	for _, desc in ipairs(model:GetDescendants()) do
		if desc:IsA("TextLabel") then
			table.insert(allLabels, desc)
		end
	end

	local function getHostPart(label: TextLabel): BasePart?
		local current: Instance? = label
		while current do
			if current:IsA("BasePart") then
				return current :: BasePart
			end
			current = current.Parent
		end
		return nil
	end

	-- A count label shows a number (possibly with leading/trailing spaces).
	local function isNumericText(text: string): boolean
		return text and text:match("^%s*%-?%d+%s*$") ~= nil
	end

	-- Count labels have "ObjectParts" in their name OR show a number
	-- but are not emoji/icon labels. Icon labels show emoji or short
	-- text and have "Part|" (but not "ObjectParts") in their name.
	local function isCountLabel(label: TextLabel): boolean
		if label.Name:find("ObjectParts") then
			return true
		end
		-- Also accept "Part|xxxx" labels that show a number (like "     0")
		-- but only if they're not showing emoji.
		if isNumericText(label.Text) then
			return true
		end
		return false
	end

	local function isIconLabel(label: TextLabel): boolean
		if label.Name:find("ObjectParts") then
			return false
		end
		-- Icon labels show emoji or short non-numeric text
		if not isNumericText(label.Text) then
			return true
		end
		return false
	end

	-- Collect all count labels (numeric TextLabels).
	local countLabels: { TextLabel } = {}
	for _, label in ipairs(allLabels) do
		if isCountLabel(label) and not isIconLabel(label) then
			table.insert(countLabels, label)
		end
	end

	-- Helper: find the SurfaceGui ancestor of a label.
	local function getSurfaceGui(label: TextLabel): SurfaceGui?
		local current: Instance? = label
		while current do
			if current:IsA("SurfaceGui") then
				return current :: SurfaceGui
			end
			current = current.Parent
		end
		return nil
	end

	-- Helper: check if a label's SurfaceGui contains an ImageLabel.
	local function hasImageIcon(label: TextLabel): boolean
		local gui = getSurfaceGui(label)
		if not gui then
			return false
		end
		for _, desc in ipairs(gui:GetDescendants()) do
			if desc:IsA("ImageLabel") then
				return true
			end
		end
		return false
	end

	-- Assign counters by their panel type:
	-- - Label in a SurfaceGui with an ImageLabel = WoodenSheet counter
	-- - Label with "ObjectParts" in name = Scrap counter
	local woodenSheet: TextLabel? = nil
	local scrap: TextLabel? = nil

	for _, label in ipairs(countLabels) do
		if hasImageIcon(label) then
			woodenSheet = label
		elseif label.Name:find("ObjectParts") then
			scrap = label
		end
	end

	-- Fallback: if we have 2 labels but couldn't classify by icon,
	-- sort by position (left = wooden sheet, right = scrap).
	if not woodenSheet and not scrap and #countLabels == 2 then
		local pivot = model:GetPivot()
		table.sort(countLabels, function(a, b)
			local partA = getHostPart(a)
			local partB = getHostPart(b)
			if partA and partB then
				return pivot:PointToObjectSpace(partA.Position).X < pivot:PointToObjectSpace(partB.Position).X
			end
			return a.Name < b.Name
		end)
		woodenSheet = countLabels[1]
		scrap = countLabels[2]
	end

	-- Fallback: if we have 1 label, assign to scrap.
	if #countLabels == 1 and not scrap then
		scrap = countLabels[1]
	end

	return woodenSheet, scrap
end

--[[
    @summary  Update the wooden sheet and scrap counter TextLabels
              on the table to show the shared run shredded totals.
]]
local function updateTableCounters()
	if woodenSheetCounter and woodenSheetCounter.Parent then
		woodenSheetCounter.Text = tostring(totalWoodenSheetShredded)
	end
	if scrapCounter and scrapCounter.Parent then
		scrapCounter.Text = tostring(totalScrapShredded)
	end
end

--[[
    @summary  Attach a crafting ProximityPrompt to the bench.
    @param    model  Model
]]
local function attachPrompt(model: Model)
	-- The package's crafting table already ships with a ProximityPrompt
	-- (named "Interact") positioned correctly on the bench.  We hook into
	-- that existing prompt instead of creating our own, so we don't end
	-- up with two prompts at different positions.

	-- First, remove any prompt we previously added.
	for _, desc in ipairs(model:GetDescendants()) do
		if desc:IsA("ProximityPrompt") and desc.Name == "CraftingPrompt" then
			desc:Destroy()
		end
	end

	-- Find the package's original prompt.
	local prompt: ProximityPrompt? = nil
	for _, desc in ipairs(model:GetDescendants()) do
		if desc:IsA("ProximityPrompt") and desc.Name ~= "CraftingPrompt" then
			prompt = desc
			break
		end
	end

	if not prompt then
		-- No existing prompt found — fall back to creating one on the
		-- largest part (closest to the table surface).
		local bestPart: BasePart? = nil
		local bestVolume = 0
		for _, desc in ipairs(model:GetDescendants()) do
			if desc:IsA("BasePart") then
				local vol = desc.Size.X * desc.Size.Y * desc.Size.Z
				if vol > bestVolume then
					bestVolume = vol
					bestPart = desc
				end
			end
		end
		if not bestPart then
			warn("[CraftingService] attachPrompt: no prompt and no part found in bench model")
			return
		end
		local newPrompt = Instance.new("ProximityPrompt")
		newPrompt.Name = "CraftingPrompt"
		newPrompt.ActionText = "Craft"
		newPrompt.ObjectText = "Crafting Bench"
		newPrompt.MaxActivationDistance = 10
		newPrompt.HoldDuration = 0.25
		newPrompt.RequiresLineOfSight = false
		newPrompt.Parent = bestPart
		prompt = newPrompt
	else
		-- Configure the existing prompt for crafting.
		prompt.ActionText = "Craft"
		prompt.ObjectText = "Crafting Bench"
		prompt.HoldDuration = 0.25
		prompt.RequiresLineOfSight = false

		-- The package's prompt may be on an Attachment that is offset
		-- far from the table surface.  Reposition it to the **front
		-- edge of the table top** so the "E Craft" prompt appears
		-- right on top of the crafting table, like before.
		local parent = prompt.Parent
		if parent and parent:IsA("Attachment") and parent.Parent and parent.Parent:IsA("BasePart") then
			local hostPart = parent.Parent :: BasePart
			local benchCFrame = model:GetPivot()

			-- Find the table top: the highest flat part with
			-- significant X/Z size (a flat surface).
			local topPart: BasePart? = nil
			local topY = -math.huge
			for _, desc in ipairs(model:GetDescendants()) do
				if desc:IsA("BasePart") then
					local p = desc :: BasePart
					if p.Size.X > 2 and p.Size.Z > 2 and p.Size.Y < p.Size.X and p.Size.Y < p.Size.Z then
						local localPos = benchCFrame:PointToObjectSpace(p.Position)
						if localPos.Y > topY then
							topY = localPos.Y
							topPart = p
						end
					end
				end
			end

			if topPart then
				-- Target: front edge of the table top, centered in Z,
				-- and raised slightly above the surface so the prompt
				-- appears on top of the table.
				local halfWidth = topPart.Size.X * 0.5
				local frontEdgeWorldCFrame = topPart.CFrame * CFrame.new(-halfWidth, 0, 0)
				local frontEdgeWorldPos = frontEdgeWorldCFrame.Position
				-- Raise 1.5 studs above the table top.
				frontEdgeWorldPos += Vector3.new(0, 1.5, 0)

				parent.Position = hostPart.CFrame:PointToObjectSpace(frontEdgeWorldPos)
			else
				-- Fallback: center the attachment on the host part.
				parent.Position = Vector3.new(0, 0, 0)
			end
		end
	end

	assert(prompt, "[CraftingService] attachPrompt: prompt is nil after setup")
	local activePrompt = prompt :: ProximityPrompt
	activePrompt.Triggered:Connect(function(player)
		if runStateService:IsActive() and runStateService:IsMember(player) and isNearBench(player) then
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
	woodenSheetCounter = nil
	scrapCounter = nil
	totalWoodenSheetShredded = 0
	totalScrapShredded = 0

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
	woodenSheetCounter, scrapCounter = findTableCounters(bench)

	-- Reset all numeric TextLabels from package defaults (e.g. "9999")
	-- to "0" since no shredding has happened yet this run.
	for _, desc in ipairs(bench:GetDescendants()) do
		if desc:IsA("TextLabel") and desc.Text:match("^%s*%d+%s*$") then
			desc.Text = "0"
		end
	end

	-- Make sure the user can see it in Studio when not playtesting.
	if isManualBench then
		bench:SetAttribute("DevinManualBench", true)
	end

	attachPrompt(bench)

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
    @summary  Increment the shared run shredded total and update
              the crafting bench counter labels.
    @desc     Called by GrinderService when a player shreds wood
              into WoodenSheet or junk into Scrap.  The counter
              on the bench shows the total for all team members.
    @param    resource  string  -- "WoodenSheet" or "Scrap"
    @param    amount    number  -- how much was produced
]]
function CraftingService:AddShreddedTotal(resource: string, amount: number)
	if not runStateService:IsActive() or amount <= 0 then
		return
	end
	if resource == "WoodenSheet" then
		totalWoodenSheetShredded += amount
	elseif resource == "Scrap" then
		totalScrapShredded += amount
	else
		return
	end
	updateTableCounters()
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
	if not runStateService:IsActive() or not runStateService:IsMember(player) then
		return { tier = 1, resources = {}, recipeCounts = {}, unlocks = {}, isNearBench = false }
	end
	local data = playerDataService and playerDataService:GetData(player)
	local resources = if data then table.clone(data.Resources) else {}
	-- Override WoodenSheet with the shared run total so the crafting
	-- UI shows the team's shredded amount, not a personal inventory value.
	resources.WoodenSheet = totalWoodenSheetShredded
	return {
		tier = benchTier,
		resources = resources,
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
	if not ServerRole.IsGameServer() then return end
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
		woodenSheetCounter = nil
		scrapCounter = nil
		totalWoodenSheetShredded = 0
		totalScrapShredded = 0
		placementTokens = {}
		craftCooldowns = {}
	end)

	Players.PlayerRemoving:Connect(function(player)
		placementTokens[player] = nil
		craftCooldowns[player] = nil
	end)
end

return CraftingService
