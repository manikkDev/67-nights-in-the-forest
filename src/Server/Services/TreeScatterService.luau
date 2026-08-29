--[[
    @file    TreeScatterService.luau
    @author  manik
    @date    2025

    @summary
    Removes dummy/placeholder trees from the original map area and
    scatters real tree assets (Tree and bigtree) evenly across the
    expanded map in a natural distribution.

    @description
    On RunStarted (deferred so buildings are placed first), scans the
    Base-map for Tree and bigtree models. Removes trees that appear to
    be dummy/placeholder models (very few parts, simple geometry).
    Then clones the real tree templates and scatters them across the
    full expanded map area, avoiding buildings but allowing overlap
    with other trees. On RunCleaned, all scattered trees are destroyed.

    @exports
    - TreeScatterService:GetScatteredTrees() -> { Model }
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
local TreeScatterService = Knit.CreateService({
	Name = "TreeScatterService",
	Client = {},
})

-- | Configuration | --
local SCATTER_TREE_COUNT = 60 -- number of regular trees to scatter
local SCATTER_BIGTREE_COUNT = 20 -- number of bigtrees to scatter
local MIN_DISTANCE = 40 -- minimum distance from campfire
local TREE_FOOTPRINT = Vector3.new(6, 15, 6)
local BIGTREE_FOOTPRINT = Vector3.new(10, 20, 10)
local TREE_CLEARANCE = 8 -- trees can be close to each other
local BIGTREE_CLEARANCE = 12
local MAX_SLOPE = 15
local MAX_RETRIES = 200

-- | State | --
local runStateService: any = nil
local worldService: any = nil
local scatteredTrees: { Model } = {}

-- // FUNCTIONS // --

--[[
    @summary  Check if a tree model is a dummy/placeholder.
    @desc    Dummy trees typically have very few parts (1-2) and
              simple geometry. Real asset trees have multiple parts
              with meshes, textures, etc.
    @param    treeModel  Model
    @returns  boolean -- true if the tree appears to be a dummy
]]
local function isDummyTree(treeModel: Model): boolean
	local partCount = 0
	local hasMesh = false
	for _, desc in ipairs(treeModel:GetDescendants()) do
		if desc:IsA("BasePart") then
			partCount += 1
			if desc:IsA("MeshPart") and (desc.MeshId ~= "" or desc.TextureId ~= "") then
				hasMesh = true
			end
		end
	end
	-- Real trees have multiple parts and/or mesh geometry
	-- Dummy trees have 1-3 simple parts with no meshes
	if partCount <= 2 and not hasMesh then
		return true
	end
	return false
end

--[[
    @summary  Find one real Tree and one real bigtree template in the Base-map.
    @returns  Model?, Model? -- treeTemplate, bigtreeTemplate
]]
local function findTreeTemplates(): (Model?, Model?)
	local baseMap = worldService:GetBaseMap()
	if not baseMap then
		return nil, nil
	end
	local treeTemplate: Model? = nil
	local bigtreeTemplate: Model? = nil
	for _, desc in ipairs(baseMap:GetDescendants()) do
		if desc:IsA("Model") then
			if desc.Name == "Tree" and not treeTemplate and not isDummyTree(desc) then
				treeTemplate = desc
			elseif desc.Name == "bigtree" and not bigtreeTemplate and not isDummyTree(desc) then
				bigtreeTemplate = desc
			end
		end
	end
	return treeTemplate, bigtreeTemplate
end

--[[
    @summary  Remove all dummy trees from the Base-map.
    @returns  number -- count of removed dummy trees
]]
local function removeDummyTrees(): number
	local baseMap = worldService:GetBaseMap()
	if not baseMap then
		return 0
	end
	local removed = 0
	local toRemove = {}
	for _, desc in ipairs(baseMap:GetDescendants()) do
		if desc:IsA("Model") and (desc.Name == "Tree" or desc.Name == "bigtree") then
			if isDummyTree(desc) then
				table.insert(toRemove, desc)
			end
		end
	end
	for _, model in ipairs(toRemove) do
		model:Destroy()
		removed += 1
	end
	if removed > 0 then
		print(("[TreeScatterService] Removed %d dummy trees"):format(removed))
	end
	return removed
end

--[[
    @summary  Clone a tree template and place it at the given position.
    @param    template  Model    -- the tree template to clone
    @param    position  Vector3  -- ground position
    @returns  Model?
]]
local function cloneTreeAt(template: Model, placement: CFrame): Model?
	local clone = template:Clone()
	-- Remove scripts
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
	-- Calculate bottom offset so tree sits on the ground
	local bboxCFrame, bboxSize = clone:GetBoundingBox()
	local modelBottomY = bboxCFrame.Position.Y - bboxSize.Y * 0.5
	local pivotY = clone:GetPivot().Position.Y
	local bottomOffset = pivotY - modelBottomY
	if bottomOffset < 0 then
		bottomOffset = 0
	end
	local placeY = placement.Position.Y + bottomOffset
	clone:PivotTo(CFrame.new(placement.Position.X, placeY, placement.Position.Z))
	return clone
end

--[[
    @summary  Scatter trees across the expanded map area.
]]
local function scatterTrees()
	scatteredTrees = {}

	local baseMap = worldService:GetBaseMap()
	local campfireCFrame = worldService:GetCampfireCFrame()
	local groundPart = worldService:GetGroundPart()
	local bounds = worldService:GetGroundBounds()
	if not baseMap or not campfireCFrame or not groundPart or not bounds then
		warn("[TreeScatterService] Missing required world references")
		return
	end

	local center = campfireCFrame.Position
	local maxDistance = WorldProgressionConfig.MapRadius - 50
	local seedBase = WorldPlacement.Hash(runStateService:GetRunId()) + WorldPlacement.Hash("TreeScatter")

	-- Find real tree templates
	local treeTemplate, bigtreeTemplate = findTreeTemplates()
	if not treeTemplate and not bigtreeTemplate then
		warn("[TreeScatterService] No real tree templates found in Base-map")
		return
	end

	-- Collect all existing buildings to exclude from overlap checks
	local buildingExclusions = { groundPart }
	for _, desc in ipairs(baseMap:GetDescendants()) do
		if desc:IsA("Model") then
			local name = desc.Name
			if name == "cabin" or name == "modern-house" or name == "Hunters Lodge"
				or name == "Treehouse" or name == "Tower" or name == "Crashed Plane"
				or name == "Bonfire" or name == "MissingChildrenBoard" then
				table.insert(buildingExclusions, desc)
			end
		end
	end

	local spawned = 0

	-- Scatter regular Trees
	if treeTemplate then
		for index = 1, SCATTER_TREE_COUNT do
			local placement = WorldPlacement.FindPosition({
				center = center,
				groundPart = groundPart,
				bounds = bounds,
				minDistance = MIN_DISTANCE,
				maxDistance = maxDistance,
				footprint = TREE_FOOTPRINT,
				clearanceRadius = TREE_CLEARANCE,
				seed = seedBase + index * 7,
				exclusions = buildingExclusions,
				maxRetries = MAX_RETRIES,
				maxSlope = MAX_SLOPE,
			})

			if placement then
				local clone = cloneTreeAt(treeTemplate, placement)
				if clone then
					clone.Parent = baseMap
					WorldPlacement.Reserve(Vector3.new(placement.Position.X, 0, placement.Position.Z), TREE_CLEARANCE, "ScatteredTree")
					table.insert(scatteredTrees, clone)
					spawned += 1
				end
			end
		end
	end

	-- Scatter BigTrees
	if bigtreeTemplate then
		for index = 1, SCATTER_BIGTREE_COUNT do
			local placement = WorldPlacement.FindPosition({
				center = center,
				groundPart = groundPart,
				bounds = bounds,
				minDistance = MIN_DISTANCE + 50,
				maxDistance = maxDistance,
				footprint = BIGTREE_FOOTPRINT,
				clearanceRadius = BIGTREE_CLEARANCE,
				seed = seedBase + index * 11 + 999,
				exclusions = buildingExclusions,
				maxRetries = MAX_RETRIES,
				maxSlope = MAX_SLOPE,
			})

			if placement then
				local clone = cloneTreeAt(bigtreeTemplate, placement)
				if clone then
					clone.Parent = baseMap
					WorldPlacement.Reserve(Vector3.new(placement.Position.X, 0, placement.Position.Z), BIGTREE_CLEARANCE, "ScatteredBigTree")
					table.insert(scatteredTrees, clone)
					spawned += 1
				end
			end
		end
	end

	print(("[TreeScatterService] Scattered %d trees across the map"):format(spawned))

	-- Re-register trees so HarvestService can handle the new ones
	local harvestService = Knit.GetService("HarvestService")
	if harvestService and harvestService.RegisterNewTrees then
		harvestService:RegisterNewTrees()
	end
end

--[[
    @summary  Destroy all scattered trees.
]]
local function cleanupScatteredTrees()
	for _, tree in ipairs(scatteredTrees) do
		if tree and tree.Parent then
			tree:Destroy()
		end
	end
	scatteredTrees = {}
end

--[[
    @returns  { Model }  -- all scattered tree models
]]
function TreeScatterService:GetScatteredTrees(): { Model }
	return scatteredTrees
end

-- // INITIALIZATION // --

function TreeScatterService:KnitStart()
	if ServerRole.IsLobby() then return end
	runStateService = Knit.GetService("RunStateService")
	worldService = Knit.GetService("WorldService")

	runStateService.RunStarted:Connect(function()
		-- Wait for buildings and facilities to be placed first
		task.defer(function()
			task.wait(0.15)
			removeDummyTrees()
			scatterTrees()
		end)
	end)

	runStateService.RunCleaned:Connect(function()
		cleanupScatteredTrees()
	end)
end

return TreeScatterService
