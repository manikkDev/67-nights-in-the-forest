--[[
    @file    WorldService.luau
    @author  manik
    @date    2025

    @summary
    Manages instantiation of game maps and the campfire anchor.

    @description
    Clones the lobby-map and base-map from ServerStorage.Assets into
    Workspace at server start.  Places the visual Bonfire model at the
    centre of the base-map and creates an invisible Campfire anchor part
    for SpawnService to reference.

    @exports
    - WorldService:GetLobbyMap()    -> Model
    - WorldService:GetBaseMap()     -> Model
    - WorldService:GetCampfire()    -> Part
    - WorldService:GetCampfireCFrame() -> CFrame
]]

-- // VARIABLES // --

-- | Services | --
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- | Modules | --
local Knit = require(ReplicatedStorage.Packages.Knit)

-- | Objects | --
local WorldService = Knit.CreateService({
	Name = "WorldService",
})

-- | State | --
local lobbyMap: Model? = nil
local baseMap: Model? = nil
local campfire: Part? = nil
local bonfire: Model? = nil

-- | Constants | --
local ASSETS_PATH = ServerStorage.Assets["Assets maps items"]
local ITEMS_PATH = ServerStorage.Assets["Assets Items"]
local CAMPFIRE_SIZE = Vector3.new(6, 3, 6)
local GROUND_RAY_HEIGHT = 500
local BONFIRE_SCALE = 2

-- | Forest Generation Constants | --
local TREE_CLEAR_RADIUS = 15
local HOUSE_CLEAR_RADIUS = 25
local EDGE_BUFFER = 20
local MIN_TREE_SPACING = 12
local SMALL_TREE_RATIO = 0.65
local NUM_CLUSTERS = 70
local TREES_PER_CLUSTER_MIN = 4
local TREES_PER_CLUSTER_MAX = 9
local CLUSTER_SPREAD = 50
local STRUCTURE_MIN_SPACING = 80
local SMALL_TREE_SCALE = 1.1
local BIG_TREE_SCALE = 0.7
local TREEHOUSE_SCALE = 0.5
local GROUND_TARGET_SIZE = 1536
local CAMPFIRE_CLUSTER_MIN_DIST = 30

local STRUCTURE_CONFIG = {
	{name = "cabin", count = 6, minDist = 150, maxDist = 500},
	{name = "Hunters Lodge", count = 4, minDist = 120, maxDist = 450},
	{name = "Tower", count = 4, minDist = 200, maxDist = 600},
	{name = "modern-house", count = 2, minDist = 250, maxDist = 600},
	{name = "mushroom-house", count = 2, minDist = 150, maxDist = 450},
	{name = "Treehouse", count = 2, minDist = 150, maxDist = 450},
	{name = "Crashed Plane", count = 2, minDist = 200, maxDist = 550},
}

-- // FUNCTIONS // --

--[[
    @summary  Return the lobby map model.
    @returns  Model?
]]
function WorldService:GetLobbyMap(): Model?
	return lobbyMap
end

--[[
    @summary  Return the base (game) map model.
    @returns  Model?
]]
function WorldService:GetBaseMap(): Model?
	return baseMap
end

--[[
    @summary  Return the Campfire anchor part.
    @returns  Part?
]]
function WorldService:GetCampfire(): Part?
	return campfire
end

--[[
    @summary  Return the visual Bonfire model.
    @returns  Model?
]]
function WorldService:GetBonfire(): Model?
	return bonfire
end

--[[
    @summary  Return the CFrame of the Campfire anchor.
    @returns  CFrame?
]]
function WorldService:GetCampfireCFrame(): CFrame?
	if not campfire then return nil end
	return campfire.CFrame
end

--[[
    @summary  Clone a map from ServerStorage into Workspace.
    @param    mapName  string  -- name of the model in ASSETS_PATH
    @returns  Model?           -- the cloned map, parented to Workspace
]]
local function cloneMap(mapName: string): Model?
	local source = ASSETS_PATH:FindFirstChild(mapName)
	if not source then
		warn(("[WorldService] Map '%s' not found in ServerStorage"):format(mapName))
		return nil
	end
	local clone = source:Clone()
	clone.Parent = workspace
	return clone
end

--[[
    @summary  Set a PrimaryPart on a cloned map if it doesn't have one.
    @desc     Picks the first BasePart in the model as PrimaryPart
              so that GetPivot() is deterministic.
    @param    map  Model  -- the cloned map
]]
local function ensurePrimaryPart(map: Model)
	if map.PrimaryPart then return end
	for _, descendant in ipairs(map:GetDescendants()) do
		if descendant:IsA("BasePart") then
			map.PrimaryPart = descendant
			return
		end
	end
end

--[[
    @summary  Find the ground-level CFrame at the map's centre.
    @desc     Locates the large ground baseplate (named "Земля") inside
              the map and returns a CFrame at its top surface centre.
              Falls back to raycasting from the map pivot if the
              ground part is not found.
    @param    map  Model  -- the cloned map
    @returns  CFrame       -- ground-level CFrame at map centre
]]
local function findGroundCFrame(map: Model): CFrame
	-- Strategy 1: find the ground baseplate by name
	for _, desc in ipairs(map:GetDescendants()) do
		if desc:IsA("BasePart") and desc.Name == "Земля" then
			local topY = desc.Position.Y + desc.Size.Y / 2
			return CFrame.new(desc.Position.X, topY, desc.Position.Z)
		end
	end

	-- Strategy 2: raycast from above the map pivot
	local pivot = map:GetPivot()
	local origin = CFrame.new(pivot.Position.X, GROUND_RAY_HEIGHT, pivot.Position.Z)
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Include
	rayParams.FilterDescendantsInstances = {map}
	local result = workspace:Raycast(origin.Position, Vector3.new(0, -GROUND_RAY_HEIGHT * 2, 0), rayParams)
	if result then
		return CFrame.new(result.Position.X, result.Position.Y, result.Position.Z)
	end

	-- Fallback: use the map pivot
	return pivot
end

--[[
    @summary  Create a Campfire anchor part at ground level on the base-map.
    @desc     The part is invisible and anchored; it exists solely as
              a CFrame reference for SpawnService.
    @param    map     Model   -- the cloned base-map
    @param    ground  CFrame  -- ground-level CFrame from findGroundCFrame
    @returns  Part
]]
local function createCampfire(map: Model, ground: CFrame): Part
	local part = Instance.new("Part")
	part.Name = "Campfire"
	part.Anchored = true
	part.CanCollide = false
	part.Transparency = 1
	part.Size = CAMPFIRE_SIZE
	part.CFrame = ground
	part.Parent = map
	return part
end

--[[
    @summary  Clone and place the visual Bonfire model at the campfire anchor.
    @desc     Clones the Bonfire model from Assets Items and positions it
              at the ground-level campfire position.  The bonfire's base
              is offset so it sits flush on the ground.
    @param    map     Model   -- the cloned base-map
    @param    ground  CFrame  -- ground-level CFrame from findGroundCFrame
    @returns  Model?
]]
local function placeBonfire(map: Model, ground: CFrame): Model?
	local source = ITEMS_PATH:FindFirstChild("Bonfire")
	if not source then
		warn("[WorldService] Bonfire model not found in Assets Items")
		return nil
	end
	local clone = source:Clone()
	clone.Name = "Bonfire"

	-- Scale up the bonfire model by applying ScaleTo on all parts
	clone:ScaleTo(BONFIRE_SCALE)

	-- The bonfire pivot is slightly above its base; place it so the
	-- base rests on the ground surface after scaling.
	local scaledPivot = clone:GetPivot()
	local minY = math.huge
	for _, desc in ipairs(clone:GetDescendants()) do
		if desc:IsA("BasePart") and desc.Position.Y < minY then
			minY = desc.Position.Y
		end
	end
	local bonfireBaseOffset = scaledPivot.Position.Y - minY
	clone:PivotTo(ground * CFrame.new(0, bonfireBaseOffset, 0))

	-- Add a PointLight for night-time visibility
	local lightPart = clone:FindFirstChildWhichIsA("BasePart", true)
	if lightPart then
		local pointLight = Instance.new("PointLight")
		pointLight.Name = "BonfireLight"
		pointLight.Color = Color3.fromRGB(255, 140, 50)
		pointLight.Range = 30
		pointLight.Brightness = 5
		pointLight.Parent = lightPart
	end

	-- Anchor all parts so the bonfire doesn't fall
	for _, desc in ipairs(clone:GetDescendants()) do
		if desc:IsA("BasePart") then
			desc.Anchored = true
		end
	end

	clone.Parent = map
	return clone
end

--[[
    @summary  Return the map bounds from the Земля ground part.
    @returns  minX, maxX, minZ, maxZ, groundY
]]
local function getMapBounds(map: Model)
	for _, desc in ipairs(map:GetDescendants()) do
		if desc:IsA("BasePart") and desc.Name == "Земля" then
			local pos = desc.Position
			local size = desc.Size
			return pos.X - size.X / 2, pos.X + size.X / 2, pos.Z - size.Z / 2, pos.Z + size.Z / 2, pos.Y + size.Y / 2
		end
	end
	local pivot = map:GetPivot()
	return pivot.Position.X - 250, pivot.Position.X + 250, pivot.Position.Z - 250, pivot.Position.Z + 250, pivot.Position.Y
end

--[[
    @summary  Find ground-level Y at a position by raycasting down.
    @desc     Raycasts from Y=500 downward at the given X,Z to find the
              highest surface hit within the map.  Falls back to 1.
]]
local function findGroundY(x: number, z: number, map: Model): number
	-- Only raycast against the ground part (Земля) to avoid hitting trees/bushes
	local groundPart = nil
	for _, desc in ipairs(map:GetDescendants()) do
		if desc:IsA("BasePart") and desc.Name == "Земля" then
			groundPart = desc
			break
		end
	end
	if groundPart then
		local rayParams = RaycastParams.new()
		rayParams.FilterType = Enum.RaycastFilterType.Include
		rayParams.FilterDescendantsInstances = {groundPart}
		local result = workspace:Raycast(Vector3.new(x, 500, z), Vector3.new(0, -1000, 0), rayParams)
		if result then
			return result.Position.Y
		end
	end
	-- Fallback: use the ground CFrame Y from findGroundCFrame
	return 1
end

--[[
    @summary  Remove all existing Tree and bigtree models from the map.
]]
local function removeExistingTrees(map: Model)
	local removed = 0
	for _, desc in ipairs(map:GetDescendants()) do
		if desc:IsA("Model") and (desc.Name == "Tree" or desc.Name == "bigtree" or desc.Name == "Дерево") then
			desc:Destroy()
			removed += 1
		elseif desc:IsA("BasePart") and desc.Name == "Leaves" then
			desc:Destroy()
			removed += 1
		end
	end
	print(("[WorldService] Removed %d existing trees from base map"):format(removed))
end

--[[
    @summary  Remove road-like parts from the map.
]]
local function removeRoads(map: Model)
	local removed = 0
	for _, child in ipairs(map:GetChildren()) do
		if child:IsA("Model") then
			local name = child.Name
			-- Remove Russian-named road and decorative models
			if name == "Дорога" or name == "дом" or name:find("ОпорыЭлектропередач") then
				child:Destroy()
				removed += 1
			end
		elseif child:IsA("BasePart") then
			local name = child.Name:lower()
			if name:find("road") or name:find("path") or name:find("street") or name:find("bridge") or name:find("sidewalk") then
				child:Destroy()
				removed += 1
			elseif child.Name == "Grass" then
				child:Destroy()
				removed += 1
			end
		end
	end
	print(("[WorldService] Removed %d road/decorative parts from base map"):format(removed))
end

-- Bush and hedge templates for regeneration
local bushTemplate: BasePart? = nil
local hedgeTemplate: BasePart? = nil

local function removeBushesAndHedges(map: Model)
	local removed = 0
	for _, desc in ipairs(map:GetDescendants()) do
		if desc:IsA("BasePart") and (desc.Name == "Bush2" or desc.Name == "Кусты" or desc.Name:find("Куст")) then
			desc:Destroy()
			removed += 1
		elseif desc:IsA("Model") and desc.Name:find("Куст") then
			desc:Destroy()
			removed += 1
		end
	end
	for _, desc in ipairs(map:GetDescendants()) do
		if desc:IsA("BasePart") and desc.Name == "Hedge1" then
			if not hedgeTemplate then
				hedgeTemplate = desc:Clone()
			end
			desc:Destroy()
			removed += 1
		end
	end
	print(("[WorldService] Removed %d bushes/hedges"):format(removed))
end

local function removeExistingStructures(map: Model)
	local structureNames = { "cabin", "Hunters Lodge", "Tower", "modern-house", "mushroom-house", "Treehouse", "Crashed Plane" }
	local removed = 0
	for _, child in ipairs(map:GetChildren()) do
		if child:IsA("Model") and table.find(structureNames, child.Name) then
			child:Destroy()
			removed += 1
		end
	end
	print(("[WorldService] Removed %d existing structures from base map"):format(removed))
end

local function removeBorderParts(map: Model)
	local removed = 0
	for _, desc in ipairs(map:GetDescendants()) do
		if desc:IsA("BasePart") and desc.Name:find("Border") then
			desc:Destroy()
			removed += 1
		end
	end
	print(("[WorldService] Removed %d border parts"):format(removed))
end

local function resizeGroundPlate(map: Model)
	for _, desc in ipairs(map:GetDescendants()) do
		if desc:IsA("BasePart") and desc.Name == "Земля" then
			desc.Size = Vector3.new(GROUND_TARGET_SIZE, desc.Size.Y, GROUND_TARGET_SIZE)
			print(("[WorldService] Resized ground plate to %dx%d"):format(GROUND_TARGET_SIZE, GROUND_TARGET_SIZE))
			return
		end
	end
	warn("[WorldService] Ground plate 'Земля' not found for resize")
end

--[[
    @summary  Clone a model and place it at a position with base on ground.
    @desc     Finds the model's lowest part Y, offsets the pivot so the
              base sits at the target Y, applies a random Y rotation,
              anchors all parts, and parents to the given parent.
    @param    source        Model   -- the asset to clone
    @param    position      Vector3 -- target ground position (X, groundY, Z)
    @param    rotation      number  -- Y rotation in degrees
    @param    parent        Instance -- parent for the clone
    @param    removeScripts boolean -- if true, destroy all scripts in clone
    @returns  Model                 -- the placed clone
]]
local function placeModel(source: Model, position: Vector3, rotation: number, parent: Instance, removeScripts: boolean?, scale: number?): Model
	local clone = source:Clone()
	if removeScripts then
		for _, desc in ipairs(clone:GetDescendants()) do
			if desc:IsA("Script") or desc:IsA("LocalScript") then
				desc:Destroy()
			end
		end
	end
	-- Remove any border parts labeled "Border (REMOVE!)" or similar
	for _, desc in ipairs(clone:GetDescendants()) do
		if desc:IsA("BasePart") and desc.Name:find("Border") then
			desc:Destroy()
		end
	end
	if scale and scale ~= 1 then
		clone:ScaleTo(scale)
	end
	local pivot = clone:GetPivot()
	local minBottomY = math.huge
	for _, desc in ipairs(clone:GetDescendants()) do
		if desc:IsA("BasePart") then
			local bottomY = desc.Position.Y - desc.Size.Y / 2
			if bottomY < minBottomY then
				minBottomY = bottomY
			end
		end
	end
	local baseOffset = pivot.Position.Y - minBottomY
	clone:PivotTo(CFrame.new(position.X, position.Y + baseOffset, position.Z) * CFrame.Angles(0, math.rad(rotation), 0))
	for _, desc in ipairs(clone:GetDescendants()) do
		if desc:IsA("BasePart") then
			desc.Anchored = true
		end
	end
	clone.Parent = parent
	return clone
end

--[[
    @summary  Place structures (houses, landmarks) across the map.
    @desc     Places structures at random angles and distances from the
              campfire, ensuring minimum spacing between structures
              and that they stay within map bounds.
    @param    map          Model   -- the cloned base-map
    @param    campfirePos  Vector3 -- campfire center position
    @returns  {Vector3}            -- list of placed structure positions
]]
local function placeStructures(map: Model, campfirePos: Vector3): {Vector3}
	local minX, maxX, minZ, maxZ = getMapBounds(map)
	local placedPositions = {}

	for _, config in ipairs(STRUCTURE_CONFIG) do
		local source = ASSETS_PATH:FindFirstChild(config.name)
		if not source then
			warn(("[WorldService] Structure '%s' not found in assets"):format(config.name))
			continue
		end

		for _ = 1, config.count do
			local sx, sz
			local attempts = 0
			local valid = false
			repeat
				local angle = math.random() * math.pi * 2
				local dist = config.minDist + math.random() * (config.maxDist - config.minDist)
				sx = campfirePos.X + math.cos(angle) * dist
				sz = campfirePos.Z + math.sin(angle) * dist
				if sx >= minX + EDGE_BUFFER and sx <= maxX - EDGE_BUFFER
					and sz >= minZ + EDGE_BUFFER and sz <= maxZ - EDGE_BUFFER then
					local tooClose = false
					for _, spos in ipairs(placedPositions) do
						if (Vector3.new(sx, 0, sz) - Vector3.new(spos.X, 0, spos.Z)).Magnitude < STRUCTURE_MIN_SPACING then
							tooClose = true
							break
						end
					end
					if not tooClose then
						valid = true
					end
				end
				attempts += 1
			until valid or attempts > 30

			if valid then
				local gy = findGroundY(sx, sz, map)
				local rot = math.random(0, 359)
				local structureScale = (config.name == "Treehouse") and TREEHOUSE_SCALE or nil
				placeModel(source, Vector3.new(sx, gy, sz), rot, map, true, structureScale)
				table.insert(placedPositions, Vector3.new(sx, gy, sz))
			end
		end
	end

	print(("[WorldService] Placed %d structures"):format(#placedPositions))
	return placedPositions
end

--[[
    @summary  Generate a natural forest by placing trees in clusters.
    @desc     Creates NUM_CLUSTERS cluster centers across the map, then
              places 25-45 trees around each center in a gaussian-like
              distribution.  Trees are excluded from the campfire radius,
              near structures, near map edges, and too close to each other.
              Uses both small Tree and bigtree assets with random rotation.
    @param    map                 Model       -- the cloned base-map
    @param    campfirePos         Vector3     -- campfire center position
    @param    structurePositions  {Vector3}   -- positions to avoid
]]
local function generateForest(map: Model, campfirePos: Vector3, structurePositions: {Vector3})
	local minX, maxX, minZ, maxZ = getMapBounds(map)
	local treeSource = ASSETS_PATH:FindFirstChild("Tree")
	local bigTreeSource = ASSETS_PATH:FindFirstChild("bigtree")
	if not treeSource or not bigTreeSource then
		warn("[WorldService] Tree or bigtree asset not found")
		return
	end

	local placedPositions = {}
	local totalPlaced = 0

	for _ = 1, NUM_CLUSTERS do
		local cx, cz
		local attempts = 0
		repeat
			cx = minX + EDGE_BUFFER + math.random() * (maxX - minX - 2 * EDGE_BUFFER)
			cz = minZ + EDGE_BUFFER + math.random() * (maxZ - minZ - 2 * EDGE_BUFFER)
			attempts += 1
		until (Vector3.new(cx, 0, cz) - Vector3.new(campfirePos.X, 0, campfirePos.Z)).Magnitude > CAMPFIRE_CLUSTER_MIN_DIST or attempts > 20

		local treeCount = math.random(TREES_PER_CLUSTER_MIN, TREES_PER_CLUSTER_MAX)
		for _ = 1, treeCount do
			local angle = math.random() * math.pi * 2
			local dist = math.random() * CLUSTER_SPREAD + (math.random() - 0.5) * 20
			local tx = cx + math.cos(angle) * dist
			local tz = cz + math.sin(angle) * dist

			if tx < minX + EDGE_BUFFER or tx > maxX - EDGE_BUFFER then continue end
			if tz < minZ + EDGE_BUFFER or tz > maxZ - EDGE_BUFFER then continue end

			local flatCampfire = Vector3.new(campfirePos.X, 0, campfirePos.Z)
			if (Vector3.new(tx, 0, tz) - flatCampfire).Magnitude < TREE_CLEAR_RADIUS then continue end

			local tooCloseToStructure = false
			for _, spos in ipairs(structurePositions) do
				if (Vector3.new(tx, 0, tz) - Vector3.new(spos.X, 0, spos.Z)).Magnitude < HOUSE_CLEAR_RADIUS then
					tooCloseToStructure = true
					break
				end
			end
			if tooCloseToStructure then continue end

			local tooCloseToTree = false
			for _, ppos in ipairs(placedPositions) do
				if (Vector3.new(tx, 0, tz) - Vector3.new(ppos.X, 0, ppos.Z)).Magnitude < MIN_TREE_SPACING then
					tooCloseToTree = true
					break
				end
			end
			if tooCloseToTree then continue end

			local gy = findGroundY(tx, tz, map)
			local isSmall = math.random() < SMALL_TREE_RATIO
			local source = isSmall and treeSource or bigTreeSource
			local treeScale = isSmall and SMALL_TREE_SCALE or BIG_TREE_SCALE
			local rot = math.random(0, 359)

			placeModel(source, Vector3.new(tx, gy, tz), rot, map, true, treeScale)
			table.insert(placedPositions, Vector3.new(tx, gy, tz))
			totalPlaced += 1
		end
	end

	print(("[WorldService] Generated %d trees in %d clusters"):format(totalPlaced, NUM_CLUSTERS))
end

--[[
    @summary  Disable known broken pre-existing scripts in cloned maps.
    @desc     Some asset models contain Scripts that reference workspace
              paths (e.g. workspace.Map, workspace.MusicPlayer) that don't
              exist in our setup.  This disables them to prevent runtime errors.
    @param    map  Model  -- the cloned map
]]
local function disableBrokenScripts(map: Model)
	for _, descendant in ipairs(map:GetDescendants()) do
		if descendant:IsA("Script") or descendant:IsA("LocalScript") then
			local name = descendant.Name
			if name == "FireSystem" or name == "FridgeRightDoorScript" or name == "FridgeLeftDoorScript" or name == "Script" then
				descendant.Disabled = true
			end
		end
		-- Anchor all parts to prevent physics lag from decorative props
		if descendant:IsA("BasePart") and not descendant.Anchored then
			descendant.Anchored = true
		end
	end
end

-- // INITIALIZATION // --

function WorldService:KnitStart()
	lobbyMap = cloneMap("lobby-map")
	baseMap = cloneMap("Base-map")

	if lobbyMap then
		ensurePrimaryPart(lobbyMap)
		disableBrokenScripts(lobbyMap)
	end

	if baseMap then
		ensurePrimaryPart(baseMap)
		removeBushesAndHedges(baseMap)
		removeExistingTrees(baseMap)
		removeExistingStructures(baseMap)
		removeRoads(baseMap)
		resizeGroundPlate(baseMap)
		removeBorderParts(baseMap)
		local ground = findGroundCFrame(baseMap)
		campfire = createCampfire(baseMap, ground)
		bonfire = placeBonfire(baseMap, ground)
		local structurePositions = placeStructures(baseMap, ground.Position)
		generateForest(baseMap, ground.Position, structurePositions)
		disableBrokenScripts(baseMap)
	end

	print("[WorldService] Maps loaded")
end

return WorldService
