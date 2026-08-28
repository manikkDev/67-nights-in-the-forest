--[[
    @file    ScrapScatterService.luau
    @author  manik
    @date    2025

    @summary
    Scatters scrap/junk items (Bolts, Radios, Sheet Metal, etc.)
    across the map from campfire level 2 onwards. Items are spread
    evenly, grounded, and upright — not grouped around facilities.

    @description
    On RunStarted (deferred so buildings/facilities are placed first),
    waits until the campfire reaches level 2, then scatters junk items
    across the accessible map area using WorldPlacement for proper
    ground alignment and non-overlapping placement. Items respawn
    after being collected. When the campfire levels up, more items
    are scattered in the newly accessible area.

    @exports
    - ScrapScatterService:GetScrapItems() -> { Model }
]]

-- // VARIABLES // --

-- | Services | --
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")

-- | Modules | --
local Knit = require(ReplicatedStorage.Packages.Knit)
local WorldProgressionConfig = require(ReplicatedStorage.Shared.WorldProgressionConfig)
local JunkItemConfig = require(ReplicatedStorage.Shared.JunkItemConfig)
local WorldPlacement = require(script.Parent.Parent.WorldPlacement)

-- | Objects | --
local ScrapScatterService = Knit.CreateService({
	Name = "ScrapScatterService",
	Client = {},
})

-- | Configuration | --
local ITEMS_PER_LEVEL = 12 -- number of scrap items per unlocked level
local RESPAWN_TIME = 60 -- seconds before scattered items respawn
local ITEM_FOOTPRINT = Vector3.new(3, 4, 3)
local ITEM_CLEARANCE = 40 -- large clearance so items are scattered far apart, not grouped
local MAX_SLOPE = 20
local MAX_RETRIES = 200
local ALL_JUNK_IDS = { "Bolt", "SheetMetal", "OldRadio", "BrokenFan", "BrokenMicrowave", "Tyre", "MetalChair" }

-- | State | --
local runStateService: any = nil
local worldService: any = nil
local inventoryService: any = nil
local worldProgressionService: any = nil
local campfireService: any = nil
local scatteredItems: { Model } = {}
local scatteredPositions: { Vector3 } = {}
local lastScatteredLevel = 1
local isRunning = false

-- // FUNCTIONS // --

--[[
    @summary  Get the current campfire level from the access radius.
    @returns  number
]]
local function getCurrentLevel(): number
	if not worldProgressionService then
		return 1
	end
	return WorldProgressionConfig.GetUnlockLevelForDistance(worldProgressionService:GetAccessRadius())
end

--[[
    @summary  Pick a random junk item ID from the catalog.
    @returns  string
]]
local function randomJunkId(): string
	return ALL_JUNK_IDS[math.random(1, #ALL_JUNK_IDS)]
end

--[[
    @summary  Spawn a single scrap item at a placement position.
    @param    junkId      string  -- item type to spawn
    @param    placement   CFrame  -- ground placement from FindPosition
    @returns  Model?
]]
local function spawnScrapItem(junkId: string, placement: CFrame): Model?
	if not inventoryService then
		return nil
	end

	local model = inventoryService:BuildDropModel(junkId)
	if not model then
		return nil
	end

	-- Calculate bottom offset so the item sits ON the ground, not floating
	local bboxCFrame, bboxSize = model:GetBoundingBox()
	local modelBottomY = bboxCFrame.Position.Y - bboxSize.Y * 0.5
	local pivotY = model:GetPivot().Position.Y
	local bottomOffset = pivotY - modelBottomY
	if bottomOffset < 0 then
		bottomOffset = 0
	end

	-- Place upright with only yaw rotation — no tilt
	local placeY = placement.Position.Y + bottomOffset + 0.5
	local yaw = (math.random() - 0.5) * math.rad(60) -- random yaw for natural look
	model:PivotTo(CFrame.new(placement.Position.X, placeY, placement.Position.Z) * CFrame.Angles(0, yaw, 0))

	return model
end

--[[
    @summary  Scatter scrap items across the accessible map area for the given level.
    @param    level  number  -- campfire level to scatter items for
]]
local function scatterForLevel(level: number)
	if level < 2 then
		return
	end

	local baseMap = worldService:GetBaseMap()
	local campfireCFrame = worldService:GetCampfireCFrame()
	local groundPart = worldService:GetGroundPart()
	local bounds = worldService:GetGroundBounds()
	if not baseMap or not campfireCFrame or not groundPart or not bounds then
		return
	end

	local center = campfireCFrame.Position
	local currentRadius = WorldProgressionConfig.GetAccessRadius(level)
	local previousRadius = if level > 1 then WorldProgressionConfig.GetAccessRadius(level - 1) else 0
	local seedBase = WorldPlacement.Hash(runStateService:GetRunId()) + WorldPlacement.Hash("ScrapScatter") + level * 31

	-- Scatter items in the ring between previousRadius and currentRadius
	local minDist = previousRadius + 20
	local maxDist = currentRadius - 30
	if maxDist <= minDist then
		return
	end

	local spawned = 0
	for index = 1, ITEMS_PER_LEVEL do
		local junkId = randomJunkId()
		local placement = WorldPlacement.FindPosition({
			center = center,
			groundPart = groundPart,
			bounds = bounds,
			minDistance = minDist,
			maxDistance = maxDist,
			footprint = ITEM_FOOTPRINT,
			clearanceRadius = ITEM_CLEARANCE,
			seed = seedBase + index * 17,
			exclusions = { groundPart },
			maxRetries = MAX_RETRIES,
			maxSlope = MAX_SLOPE,
		})

		if placement then
			local model = spawnScrapItem(junkId, placement)
			if model then
				model.Parent = baseMap
				Debris:AddItem(model, 600) -- cleanup after 10 minutes
				table.insert(scatteredItems, model)
				table.insert(scatteredPositions, placement.Position)
				WorldPlacement.Reserve(Vector3.new(placement.Position.X, 0, placement.Position.Z), ITEM_CLEARANCE, "ScrapItem")
				spawned += 1
			end
		end
	end

	if spawned > 0 then
		print(("[ScrapScatterService] Scattered %d scrap items for level %d (ring %d-%d)"):format(spawned, level, minDist, maxDist))
	end
end

--[[
    @summary  Scatter items for all unlocked levels from 2 to current.
]]
local function scatterAllUnlocked()
	local currentLevel = getCurrentLevel()
	for level = 2, currentLevel do
		if level > lastScatteredLevel then
			scatterForLevel(level)
		end
	end
	lastScatteredLevel = currentLevel
end

--[[
    @summary  Respawn scattered items that have been collected.
]]
local function checkRespawn()
	if not isRunning then
		return
	end

	-- Remove collected items from tracking
	local stillAlive = {}
	for _, item in ipairs(scatteredItems) do
		if item and item.Parent then
			table.insert(stillAlive, item)
		end
	end
	scatteredItems = stillAlive

	-- Count how many are missing and respawn them
	local currentLevel = getCurrentLevel()
	local expectedCount = (currentLevel - 1) * ITEMS_PER_LEVEL
	local missing = expectedCount - #scatteredItems
	if missing <= 0 then
		return
	end

	-- Respawn missing items across the accessible area
	local baseMap = worldService:GetBaseMap()
	local campfireCFrame = worldService:GetCampfireCFrame()
	local groundPart = worldService:GetGroundPart()
	local bounds = worldService:GetGroundBounds()
	if not baseMap or not campfireCFrame or not groundPart or not bounds then
		return
	end

	local center = campfireCFrame.Position
	local maxDist = worldProgressionService:GetAccessRadius() - 30
	local minDist = WorldProgressionConfig.GetAccessRadius(2) + 20
	if maxDist <= minDist then
		return
	end

	local seedBase = WorldPlacement.Hash(runStateService:GetRunId()) + WorldPlacement.Hash("ScrapRespawn")
	local respawned = 0
	for index = 1, math.min(missing, ITEMS_PER_LEVEL) do
		local junkId = randomJunkId()
		local placement = WorldPlacement.FindPosition({
			center = center,
			groundPart = groundPart,
			bounds = bounds,
			minDistance = minDist,
			maxDistance = maxDist,
			footprint = ITEM_FOOTPRINT,
			clearanceRadius = ITEM_CLEARANCE,
			seed = seedBase + index * 23 + os.clock(),
			exclusions = { groundPart },
			maxRetries = 50,
			maxSlope = MAX_SLOPE,
		})

		if placement then
			local model = spawnScrapItem(junkId, placement)
			if model then
				model.Parent = baseMap
				Debris:AddItem(model, 600)
				WorldPlacement.Reserve(Vector3.new(placement.Position.X, 0, placement.Position.Z), ITEM_CLEARANCE, "ScrapItem")
				table.insert(scatteredItems, model)
				respawned += 1
			end
		end
	end

	if respawned > 0 then
		print(("[ScrapScatterService] Respawned %d scrap items"):format(respawned))
	end
end

--[[
    @summary  Clean up all scattered items.
]]
local function cleanup()
	for _, item in ipairs(scatteredItems) do
		if item and item.Parent then
			item:Destroy()
		end
	end
	scatteredItems = {}
	scatteredPositions = {}
	lastScatteredLevel = 1
	isRunning = false
end

--[[
    @returns  { Model }  -- all active scattered scrap items
]]
function ScrapScatterService:GetScrapItems(): { Model }
	return scatteredItems
end

-- // INITIALIZATION // --

function ScrapScatterService:KnitStart()
	runStateService = Knit.GetService("RunStateService")
	worldService = Knit.GetService("WorldService")
	inventoryService = Knit.GetService("InventoryService")
	worldProgressionService = Knit.GetService("WorldProgressionService")
	campfireService = Knit.GetService("CampfireService")

	runStateService.RunStarted:Connect(function()
		cleanup()
		isRunning = true
		lastScatteredLevel = 1

		-- Wait for buildings/facilities to be placed first
		task.defer(function()
			task.wait(0.25)
			-- Scatter items for any levels already unlocked
			scatterAllUnlocked()
		end)

		-- Start respawn loop
		task.spawn(function()
			while isRunning do
				task.wait(RESPAWN_TIME)
				checkRespawn()
			end
		end)
	end)

	runStateService.RunCleaned:Connect(function()
		cleanup()
	end)

	-- When campfire levels up, scatter items in the newly accessible area
	if campfireService and campfireService.LevelChangedServer then
		campfireService.LevelChangedServer:Connect(function(level: number)
			if not isRunning then
				return
			end
			if level >= 2 and level > lastScatteredLevel then
				task.defer(function()
					task.wait(0.1)
					scatterForLevel(level)
					lastScatteredLevel = level
				end)
			end
		end)
	end
end

return ScrapScatterService
