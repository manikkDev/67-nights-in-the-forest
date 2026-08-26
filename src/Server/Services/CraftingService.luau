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

-- | Configuration | --
local WOOD_SLOT_NAMES = { "WoodSlot", "Wood", "LogSlot", "Log", "Slot1", "Resource1" }
local SCRAP_SLOT_NAMES = { "ScrapSlot", "Scrap", "BoltSlot", "Bolt", "Slot2", "Resource2" }

--[[
    @summary  Locate the wood/scrap slot anchors on the bench model.
    @desc     Looks for named parts, SurfaceGui parents with wood/scrap
              images, and Decals.  Falls back to bounding-box left/right
              positions if none found.
    @returns  BasePart? woodSlot, BasePart? scrapSlot, BasePart? surface
]]
local function findStackAnchors(model: Model): (BasePart?, BasePart?, BasePart?)
	local woodSlot: BasePart? = nil
	local scrapSlot: BasePart? = nil

	local function partForName(name: string): BasePart?
		local part = model:FindFirstChild(name)
		if part and part:IsA("BasePart") then
			return part
		end
		for _, desc in ipairs(model:GetDescendants()) do
			if desc.Name == name and desc:IsA("BasePart") then
				return desc
			end
		end
		return nil
	end

	-- 1. Direct part names
	for _, name in ipairs(WOOD_SLOT_NAMES) do
		woodSlot = woodSlot or partForName(name)
	end
	for _, name in ipairs(SCRAP_SLOT_NAMES) do
		scrapSlot = scrapSlot or partForName(name)
	end

	-- 2. SurfaceGui/Decal parents: icon textures on the table surface
	local function hasWoodIcon(instance: Instance): boolean
		if instance:IsA("ImageLabel") or instance:IsA("ImageButton") or instance:IsA("Decal") then
			local id = instance.Image or instance.Texture
			local name = instance.Name:lower()
			if id and (name:find("wood") or name:find("log") or id:find("wood") or id:find("log")) then
				return true
			end
		end
		return false
	end

	local function hasScrapIcon(instance: Instance): boolean
		if instance:IsA("ImageLabel") or instance:IsA("ImageButton") or instance:IsA("Decal") then
			local id = instance.Image or instance.Texture
			local name = instance.Name:lower()
			if id and (name:find("scrap") or name:find("bolt") or id:find("scrap") or id:find("bolt")) then
				return true
			end
		end
		return false
	end

	for _, desc in ipairs(model:GetDescendants()) do
		if not woodSlot and hasWoodIcon(desc) and desc.Parent and desc.Parent:IsA("BasePart") then
			woodSlot = desc.Parent :: BasePart
		end
		if not scrapSlot and hasScrapIcon(desc) and desc.Parent and desc.Parent:IsA("BasePart") then
			scrapSlot = desc.Parent :: BasePart
		end
	end

	-- Surface for fallback is the primary part or largest top part
	local surface = model.PrimaryPart
	if not surface then
		local bestVolume = 0
		for _, desc in ipairs(model:GetDescendants()) do
			if desc:IsA("BasePart") then
				local volume = desc.Size.X * desc.Size.Y * desc.Size.Z
				if volume > bestVolume then
					bestVolume = volume
					surface = desc
				end
			end
		end
	end

	return woodSlot, scrapSlot, surface
end

--[[
    @summary  Update the 3D resource stacks on the crafting bench.
    @desc     Spawns wood logs on the wood slot and scrap metal sheets on
              the scrap slot, matching the reference game where resources
              physically pile up at the table's input slots (shown in the
              user's screenshot).
    @param    resources  table  -- { Wood = N, Scrap = N, ... }
]]
local stackFolder: Folder? = nil
local lastWoodStack: { Part } = {}
local lastScrapStack: { Part } = {}

local function clearStacks()
	if stackFolder and stackFolder.Parent then
		stackFolder:Destroy()
	end
	stackFolder = nil
	lastWoodStack = {}
	lastScrapStack = {}
end

local function updateResourceStacks(resources: { [string]: number }?)
	if not benchModel or not benchModel.Parent then
		return
	end
	if not resources then
		return
	end

	clearStacks()
	stackFolder = Instance.new("Folder")
	stackFolder.Name = "ResourceStacks"
	stackFolder.Parent = benchModel

	local woodSlot, scrapSlot, surface = findStackAnchors(benchModel)
	if not surface then
		return
	end

	local cf = surface.CFrame
	local size = surface.Size
	local up = cf.UpVector

	local function slotPosition(slot: BasePart?, sideX: number, sideZ: number): (Vector3, Vector3)
		if slot then
			-- Use the named slot's top surface
			local slotUp = slot.CFrame.UpVector
			local pos = slot.Position + slotUp * (slot.Size.Y * 0.5)
			return pos, slotUp
		end
		-- Fallback: place on the main surface at the requested side
		local pos = cf.Position
			+ cf.RightVector * (size.X * 0.25 * sideX)
			+ cf.LookVector * (size.Z * 0.15 * sideZ)
			+ up * (size.Y * 0.5)
		return pos, up
	end

	local woodPos, woodUp = slotPosition(woodSlot, -1, 0)
	local scrapPos, scrapUp = slotPosition(scrapSlot, 1, 0)

	-- Wood logs: stack on the wood slot (left side in the screenshot).
	-- 1 log per wood, capped to keep part count sane.
	local woodCount = math.min(resources.Wood or 0, 25)
	for i = 1, woodCount do
		local log = Instance.new("Part")
		log.Name = "WoodLog" .. tostring(i)
		log.Shape = Enum.PartType.Cylinder
		log.Size = Vector3.new(0.35, 1.1, 0.35)
		log.Color = Color3.fromRGB(120, 80, 40)
		log.Material = Enum.Material.Wood
		log.Anchored = true
		log.CanCollide = false
		log.CastShadow = false

		-- Cylinder: length is along Y axis, so we rotate 90 deg around X
		-- to make it lie horizontal, then again around the surface up vector
		local layer = math.floor((i - 1) / 3)
		local col = (i - 1) % 3
		local row = math.floor((i - 1) / 3)
		local x = (col - 1) * 0.5
		local z = (row % 2) * 0.25
		local y = 0.2 + (layer * 0.28)
		local baseCFrame = CFrame.new(woodPos + woodUp * y)
		log.CFrame = baseCFrame * CFrame.new(x, 0, z) * CFrame.Angles(math.rad(90), 0, math.random(-15, 15))
		log.Parent = stackFolder
		table.insert(lastWoodStack, log)
	end

	-- Scrap metal sheets: stack on the scrap slot (right side in the screenshot).
	-- 1 sheet per scrap, capped to keep part count sane.
	local scrapCount = math.min(resources.Scrap or 0, 20)
	for i = 1, scrapCount do
		local sheet = Instance.new("Part")
		sheet.Name = "ScrapSheet" .. tostring(i)
		sheet.Size = Vector3.new(0.9, 0.05, 0.7)
		sheet.Color = Color3.fromRGB(140, 140, 150)
		sheet.Material = Enum.Material.Metal
		sheet.Anchored = true
		sheet.CanCollide = false
		sheet.CastShadow = false

		local col = (i - 1) % 2
		local layer = math.floor((i - 1) / 2)
		local x = (col - 0.5) * 0.4
		local z = 0
		local y = 0.15 + (i * 0.06)
		local angle = i * 18
		local baseCFrame = CFrame.new(scrapPos + scrapUp * y)
		sheet.CFrame = baseCFrame * CFrame.new(x, 0, z) * CFrame.Angles(0, math.rad(angle), 0)
		sheet.Parent = stackFolder
		table.insert(lastScrapStack, sheet)
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
	clearStacks()

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
			clone = source:Clone()
			clone.Name = "CraftingBench"
			sanitizeBench(clone)
			local _, size = clone:GetBoundingBox()
			local pivot = clone:GetPivot()
			clone:PivotTo(campfireCFrame * BENCH_OFFSET * CFrame.new(0, size.Y * 0.5, 0) * pivot.Rotation)
			clone.Parent = runStateService:GetRuntimeFolder()
		else
			warn("[CraftingService] crafting-table asset is missing")
			return
		end
	end

	if not clone then
		return
	end

	if not clone.PrimaryPart then
		local primary = clone:FindFirstChildWhichIsA("BasePart", true)
		if primary then
			clone.PrimaryPart = primary
		end
	end

	benchModel = clone

	-- Make sure the user can see it in Studio when not playtesting.
	if isManualBench then
		benchModel:SetAttribute("DevinManualBench", true)
	end

	attachPrompt(benchModel)

	-- Initial resource stacks
	local members = runStateService:GetMembers()
	if #members > 0 and playerDataService then
		local data = playerDataService:GetData(members[1])
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
		clearStacks()
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
