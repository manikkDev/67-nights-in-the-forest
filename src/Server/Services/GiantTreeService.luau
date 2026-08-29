--[[
    @file    GiantTreeService.luau
    @author  manik
    @date    2025

    @summary
    Spawns GiantTree models (2x scaled bigtree) across the map each run.
    GiantTrees avoid buildings but can overlap regular tree branches.
    They function like normal trees: choppable, drop more wood, fall
    animation, and respawn.

    @description
    On RunStarted (deferred so buildings/facilities are placed first),
    clones the bigtree model from the Base-map, scales it 2x, and
    scatters 40-50 instances across the map. On RunCleaned, all
    spawned GiantTrees are destroyed.

    @exports
    - GiantTreeService:GetGiantTrees() -> { Model }
]]

-- // VARIABLES // --

-- | Services | --
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- | Modules | --
local Knit = require(ReplicatedStorage.Packages.Knit)
local ServerRole = require(ReplicatedStorage.Shared.ServerRole)
local WorldProgressionConfig = require(ReplicatedStorage.Shared.WorldProgressionConfig)
local WorldPlacement = require(script.Parent.Parent.WorldPlacement)

-- | Objects | --
local GiantTreeService = Knit.CreateService({
	Name = "GiantTreeService",
	Client = {},
})

-- | Configuration | --
local GIANT_TREE_COUNT = 20
local GIANT_TREE_SCALE = 2
local MIN_DISTANCE = 100
local TRUNK_FOOTPRINT = Vector3.new(14, 15, 14)
local CLEARANCE_RADIUS = 18
local MAX_SLOPE = 15
local MAX_RETRIES = 400

-- | State | --
local runStateService: any = nil
local worldService: any = nil
local giantTrees: { Model } = {}

-- // FUNCTIONS // --

--[[
    @summary  Find a bigtree model in the Base-map to use as a template.
    @returns  Model?
]]
local function findBigTreeTemplate(): Model?
	local baseMap = worldService:GetBaseMap()
	if not baseMap then
		return nil
	end
	for _, desc in ipairs(baseMap:GetDescendants()) do
		if desc:IsA("Model") and desc.Name == "bigtree" then
			return desc
		end
	end
	return nil
end

--[[
    @summary  Clone and scale a bigtree into a GiantTree.
    @param    template  Model  -- the source bigtree model
    @returns  Model?
]]
local function createGiantTree(template: Model): Model?
	local clone = template:Clone()
	clone.Name = "GiantTree"
	clone:SetAttribute("IsGiantTree", true)

	-- Scale the model 2x by resizing every part
	-- ScaleTo may not be available in all Roblox versions, so do it manually
	for _, desc in ipairs(clone:GetDescendants()) do
		if desc:IsA("BasePart") then
			desc.Size = desc.Size * GIANT_TREE_SCALE
		end
	end

	-- Remove any scripts that might cause issues
	for _, desc in ipairs(clone:GetDescendants()) do
		if desc:IsA("BaseScript") or desc:IsA("ModuleScript") then
			desc:Destroy()
		end
	end

	-- Anchor all parts
	for _, desc in ipairs(clone:GetDescendants()) do
		if desc:IsA("BasePart") then
			desc.Anchored = true
		end
	end

	return clone
end

--[[
    @summary  Spawn GiantTrees across the map using simple random placement.
              Falls back to direct random placement if FindPosition fails too often.
]]
local function spawnGiantTrees()
	giantTrees = {}

	local baseMap = worldService:GetBaseMap()
	local campfireCFrame = worldService:GetCampfireCFrame()
	local groundPart = worldService:GetGroundPart()
	local bounds = worldService:GetGroundBounds()
	if not baseMap or not campfireCFrame or not groundPart or not bounds then
		warn("[GiantTreeService] Missing required world references")
		return
	end

	local template = findBigTreeTemplate()
	if not template then
		warn("[GiantTreeService] No bigtree template found in Base-map")
		return
	end

	local center = campfireCFrame.Position
	local maxDistance = WorldProgressionConfig.MapRadius - 100
	local seedBase = WorldPlacement.Hash(runStateService:GetRunId()) + WorldPlacement.Hash("GiantTree")
	local random = Random.new(seedBase)
	local spawned = 0

	-- Collect all existing Tree/bigtree models to exclude from overlap checks
	local treeExclusions = { groundPart }
	for _, desc in ipairs(baseMap:GetDescendants()) do
		if desc:IsA("Model") and (desc.Name == "Tree" or desc.Name == "bigtree") then
			table.insert(treeExclusions, desc)
		end
	end

	for index = 1, GIANT_TREE_COUNT do
		local giantTree = createGiantTree(template)
		if not giantTree then
			continue
		end

		-- Try FindPosition first (collision-free placement)
		local placement = WorldPlacement.FindPosition({
			center = center,
			groundPart = groundPart,
			bounds = bounds,
			minDistance = MIN_DISTANCE,
			maxDistance = maxDistance,
			footprint = TRUNK_FOOTPRINT,
			clearanceRadius = CLEARANCE_RADIUS,
			seed = seedBase + index * 13,
			exclusions = treeExclusions,
			maxRetries = MAX_RETRIES,
			maxSlope = MAX_SLOPE,
		})

		if not placement then
			-- Fallback: direct random placement without collision check
			-- This ensures we always get trees on the map even if FindPosition is too strict
			local angle = random:NextNumber(0, math.pi * 2)
			local distance = random:NextNumber(MIN_DISTANCE, maxDistance)
			local testPos = center + Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)
			-- Check bounds
			local halfX = TRUNK_FOOTPRINT.X * 0.5
			local halfZ = TRUNK_FOOTPRINT.Z * 0.5
			if testPos.X - halfX < bounds.minX or testPos.X + halfX > bounds.maxX
				or testPos.Z - halfZ < bounds.minZ or testPos.Z + halfZ > bounds.maxZ then
				giantTree:Destroy()
				continue
			end
			placement = WorldPlacement.GetGroundCFrame(groundPart, testPos, 0)
			if not placement then
				giantTree:Destroy()
				continue
			end
		end

		if placement then
			-- Calculate bottom offset using GetBoundingBox correctly
			local bboxCFrame, bboxSize = giantTree:GetBoundingBox()
			local modelBottomY = bboxCFrame.Position.Y - bboxSize.Y * 0.5
			local pivotY = giantTree:GetPivot().Position.Y
			local bottomOffset = pivotY - modelBottomY
			if bottomOffset < 0 then
				bottomOffset = 0
			end
			local placeY = placement.Position.Y + bottomOffset
			giantTree:PivotTo(CFrame.new(placement.Position.X, placeY, placement.Position.Z))
			giantTree.Parent = baseMap
			WorldPlacement.Reserve(Vector3.new(placement.Position.X, 0, placement.Position.Z), CLEARANCE_RADIUS, "GiantTree")
			table.insert(giantTrees, giantTree)
			spawned += 1
		else
			giantTree:Destroy()
		end
	end

	print(("[GiantTreeService] Spawned %d/%d GiantTrees"):format(spawned, GIANT_TREE_COUNT))

	-- Re-register trees so HarvestService can handle the new GiantTrees
	local harvestService = Knit.GetService("HarvestService")
	if harvestService and harvestService.RegisterNewTrees then
		harvestService:RegisterNewTrees()
	end
end

--[[
    @summary  Destroy all spawned GiantTrees.
]]
local function cleanupGiantTrees()
	for _, tree in ipairs(giantTrees) do
		if tree and tree.Parent then
			tree:Destroy()
		end
	end
	giantTrees = {}
end

--[[
    @returns  { Model }  -- all active GiantTree models
]]
function GiantTreeService:GetGiantTrees(): { Model }
	return giantTrees
end

-- // INITIALIZATION // --

function GiantTreeService:KnitStart()
	if not ServerRole.IsGameServer() then return end
	runStateService = Knit.GetService("RunStateService")
	worldService = Knit.GetService("WorldService")

	runStateService.RunStarted:Connect(function()
		-- Wait for buildings, facilities, caves, and scattered trees to be placed first
		task.defer(function()
			task.wait(0.2)
			spawnGiantTrees()
		end)
	end)

	runStateService.RunCleaned:Connect(function()
		cleanupGiantTrees()
	end)
end

return GiantTreeService
