local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Knit = require(ReplicatedStorage.Packages.Knit)
local WorldProgressionConfig = require(ReplicatedStorage.Shared.WorldProgressionConfig)
local WorldPlacement = require(script.Parent.Parent.WorldPlacement)

local WorldProgressionService = Knit.CreateService({
	Name = "WorldProgressionService",
	Client = {
		BoundaryExpanded = Knit.CreateSignal(),
		AccessRadius = Knit.CreateProperty(WorldProgressionConfig.GetAccessRadius(1)),
	},
})

local runStateService: any = nil
local worldService: any = nil
local campfireService: any = nil
local boundaryFolder: Folder? = nil
local boundaryParts: { Part } = {}
local boundaryTrims: { Part } = {}
local accessRadius = WorldProgressionConfig.GetAccessRadius(1)
local checkTimer = 0

local function broadcastExpansion(level: number)
	WorldProgressionService.Client.AccessRadius:Set(accessRadius)
	for _, player in ipairs(Players:GetPlayers()) do
		WorldProgressionService.Client.BoundaryExpanded:Fire(player, level, accessRadius)
	end
end

--[[
    @summary  Move base-map buildings that sit outside the starting
              access radius inward so they are reachable.
    @desc    Scans the pre-placed Base-map for known structure models
              (cabins, houses, towers, lodges, treehouses, plane) and
              repositions any whose flat distance from the campfire
              exceeds the current radius minus a margin.  The building
              is pulled radially inward to just inside the boundary.
]]
local function relocateBuildings()
	local baseMap = worldService:GetBaseMap()
	local campfireCFrame = worldService:GetCampfireCFrame()
	local groundPart = worldService:GetGroundPart()
	if not baseMap or not campfireCFrame or not groundPart then
		return
	end
	local center = campfireCFrame.Position
	local bounds = worldService:GetGroundBounds()
	if not bounds then
		return
	end
	-- Use all ground parts (original + ExpandedGround tiles) so buildings
	-- can be placed across the full expanded map, not just the original terrain.
	local allGroundParts = worldService:GetAllGroundParts()
	local buildingNames = {
		["cabin"] = true,
		["modern-house"] = true,
		["Hunters Lodge"] = true,
		["Treehouse"] = true,
		["Tower"] = true,
		["Crashed Plane"] = true,
	}
	-- Collect ALL buildings from the base map
	local buildings = {}
	for _, desc in ipairs(baseMap:GetDescendants()) do
		if desc:IsA("Model") and buildingNames[desc.Name] then
			table.insert(buildings, desc)
		end
	end
	if #buildings == 0 then
		return
	end
	-- Distribute buildings across the map:
	-- No buildings near campfire. 2 buildings in level 1 area but far from campfire.
	-- Rest spread from level 2 to map edge.
	local level1Radius = WorldProgressionConfig.GetAccessRadius(1)
	local maxRadius = WorldProgressionConfig.MapRadius - 40
	local seedBase = WorldPlacement.Hash("BuildingDistribution")
	local moved = 0
	for index, building in ipairs(buildings) do
		local ringMin, ringMax
		if index <= 2 then
			-- First 2 buildings: far edge of level 1 area (not near campfire)
			ringMin = level1Radius - 60
			ringMax = level1Radius - 20
		else
			-- Remaining buildings: spread evenly from level 2 radius to map edge
			local remaining = #buildings - 2
			local remainingIndex = index - 2
			local level2Radius = WorldProgressionConfig.GetAccessRadius(2)
			local span = maxRadius - level2Radius
			local fraction = (remainingIndex - 1) / math.max(1, remaining - 1)
			ringMin = level2Radius + fraction * span - 40
			ringMax = level2Radius + fraction * span + 40
			ringMin = math.max(level2Radius, ringMin)
			ringMax = math.min(maxRadius, ringMax)
			if ringMax <= ringMin then
				ringMin = level2Radius
				ringMax = maxRadius
			end
		end
		local extents = building:GetExtentsSize()
		local footprint = Vector3.new(extents.X + 15, extents.Y + 6, extents.Z + 15)
		local clearanceRadius = math.max(extents.X, extents.Z) * 0.5 + 12
		-- Ensure all parts are anchored so they don't fall after placement
		for _, desc in ipairs(building:GetDescendants()) do
			if desc:IsA("BasePart") then
				desc.Anchored = true
			end
		end
		local placement = WorldPlacement.FindPosition({
			center = center,
			groundPart = allGroundParts,
			bounds = bounds,
			minDistance = ringMin,
			maxDistance = ringMax,
			footprint = footprint,
			clearanceRadius = clearanceRadius,
			seed = seedBase + index * 7,
			exclusions = allGroundParts,
			maxRetries = 200,
			maxSlope = 8,
			faceCenter = true,
		})
		if placement then
			-- First, move the building to the target position with yaw-only orientation
			-- at a temporary Y, then find the actual lowest part to get an accurate bottom offset.
			local yaw = select(2, placement:ToEulerAnglesYXZ())
			building:PivotTo(CFrame.new(placement.Position.X, placement.Position.Y + 500, placement.Position.Z) * CFrame.Angles(0, yaw, 0))
			-- Find the actual lowest part by iterating through all parts
			-- This is more reliable than GetBoundingBox for models with unusual pivots
			local pivotY = building:GetPivot().Position.Y
			local lowestY = math.huge
			for _, desc in ipairs(building:GetDescendants()) do
				if desc:IsA("BasePart") then
					if desc.Position.Y < lowestY then
						lowestY = desc.Position.Y
					end
				end
			end
			local bottomOffset = if lowestY ~= math.huge then pivotY - lowestY else 0
			if bottomOffset < 0 then
				bottomOffset = 0
			end
			-- Now place at the correct Y so the bottom sits on the ground
			local placeY = placement.Position.Y + bottomOffset
			building:PivotTo(CFrame.new(placement.Position.X, placeY, placement.Position.Z) * CFrame.Angles(0, yaw, 0))
			WorldPlacement.Reserve(Vector3.new(placement.Position.X, 0, placement.Position.Z), clearanceRadius, "Building_" .. building.Name)
			moved += 1
		else
			-- Fallback: keep original position but fix ground alignment with yaw-only
			local pivot = building:GetPivot()
			local yaw = select(2, pivot:ToEulerAnglesYXZ())
			local groundCFrame = WorldPlacement.GetGroundCFrame(allGroundParts, pivot.Position, 0)
			if groundCFrame then
				-- Move to temp position with yaw-only, then find lowest part
				building:PivotTo(CFrame.new(groundCFrame.Position.X, groundCFrame.Position.Y + 500, groundCFrame.Position.Z) * CFrame.Angles(0, yaw, 0))
				local pivotY = building:GetPivot().Position.Y
				local lowestY = math.huge
				for _, desc in ipairs(building:GetDescendants()) do
					if desc:IsA("BasePart") then
						if desc.Position.Y < lowestY then
							lowestY = desc.Position.Y
						end
					end
				end
				local bottomOffset = if lowestY ~= math.huge then pivotY - lowestY else 0
				if bottomOffset < 0 then
					bottomOffset = 0
				end
				local placeY = groundCFrame.Position.Y + bottomOffset
				building:PivotTo(CFrame.new(groundCFrame.Position.X, placeY, groundCFrame.Position.Z) * CFrame.Angles(0, yaw, 0))
			end
		end
	end
	print(("[WorldProgressionService] Redistributed %d/%d buildings across the map"):format(moved, #buildings))
end

local function ensureBoundary()
	if boundaryFolder and boundaryFolder.Parent then
		return
	end
	local runtime = runStateService:GetRuntimeFolder()
	local folder = Instance.new("Folder")
	folder.Name = "WorldBoundary"
	folder.Parent = runtime
	boundaryFolder = folder
	table.clear(boundaryParts)
	table.clear(boundaryTrims)
	for index = 1, WorldProgressionConfig.Boundary.ServerSegments do
		-- Main wall part — tall and opaque to block view and movement
		local part = Instance.new("Part")
		part.Name = "BoundaryCollider" .. index
		part.Anchored = true
		part.CanCollide = true
		part.CanTouch = false
		part.CanQuery = false
		part.Transparency = 0
		part.Material = Enum.Material.SmoothPlastic
		part.Color = Color3.fromRGB(35, 40, 50)
		part.CastShadow = false
		part.Reflectance = 0
		part.Parent = folder
		table.insert(boundaryParts, part)
		-- Neon trim at the top — makes the wall visible from far away
		-- even at night and through atmospheric fog
		local trim = Instance.new("Part")
		trim.Name = "BoundaryTrim" .. index
		trim.Anchored = true
		trim.CanCollide = false
		trim.CanTouch = false
		trim.CanQuery = false
		trim.Transparency = 0
		trim.Material = Enum.Material.Neon
		trim.Color = Color3.fromRGB(90, 100, 130)
		trim.CastShadow = false
		trim.Parent = folder
		table.insert(boundaryTrims, trim)
	end
end

local function updateBoundary()
	ensureBoundary()
	local campfireCFrame = worldService:GetCampfireCFrame()
	local groundY = worldService:GetGroundY()
	if not campfireCFrame or not groundY then
		return
	end
	local count = #boundaryParts
	local height = WorldProgressionConfig.Boundary.Height
	local center = campfireCFrame.Position
	-- Square boundary: place segments along the 4 edges of a square
	-- centered on the campfire with half-width = accessRadius.
	-- This fully encloses the playable area including corners.
	local halfWidth = accessRadius
	local segmentsPerSide = math.floor(count / 4)
	local segmentLength = (halfWidth * 2) / segmentsPerSide + 12
	local sideOrder = { "East", "South", "West", "North" }
	for index, part in ipairs(boundaryParts) do
		local sideIndex = math.floor((index - 1) / segmentsPerSide)
		local indexInSide = (index - 1) % segmentsPerSide
		local t = (indexInSide + 0.5) / segmentsPerSide  -- 0..1 along the side
		local posAlongSide = -halfWidth + t * halfWidth * 2
		local position: Vector3
		local facing: Vector3
		if sideIndex == 0 then
			-- East side (positive X): runs from -halfWidth to +halfWidth in Z
			position = center + Vector3.new(halfWidth, 0, posAlongSide)
			facing = Vector3.new(-1, 0, 0)
		elseif sideIndex == 1 then
			-- South side (positive Z): runs from +halfWidth to -halfWidth in X
			position = center + Vector3.new(posAlongSide, 0, halfWidth)
			facing = Vector3.new(0, 0, -1)
		elseif sideIndex == 2 then
			-- West side (negative X): runs from +halfWidth to -halfWidth in Z
			position = center + Vector3.new(-halfWidth, 0, posAlongSide)
			facing = Vector3.new(1, 0, 0)
		else
			-- North side (negative Z): runs from -halfWidth to +halfWidth in X
			position = center + Vector3.new(posAlongSide, 0, -halfWidth)
			facing = Vector3.new(0, 0, 1)
		end
		position = Vector3.new(position.X, groundY + height * 0.5, position.Z)
		part.Size = Vector3.new(segmentLength, height, 14)
		part.CFrame = CFrame.lookAt(position, position + facing)
		-- Position the neon trim at the top of the wall
		local trim = boundaryTrims[index]
		if trim then
			local trimY = groundY + height - 3
			local trimPos = Vector3.new(position.X, trimY, position.Z)
			trim.Size = Vector3.new(segmentLength, 8, 16)
			trim.CFrame = CFrame.lookAt(trimPos, trimPos + facing)
		end
	end
end

local function setLevel(level: number)
	local nextRadius = WorldProgressionConfig.GetAccessRadius(level)
	if nextRadius <= accessRadius then
		return
	end
	accessRadius = nextRadius
	updateBoundary()
	broadcastExpansion(level)
end

local function constrainPlayers(dt: number)
	checkTimer += dt
	if checkTimer < WorldProgressionConfig.Boundary.CheckInterval then
		return
	end
	checkTimer = 0
	if not runStateService:IsActive() then
		return
	end
	local campfireCFrame = worldService:GetCampfireCFrame()
	if not campfireCFrame then
		return
	end
	local center = campfireCFrame.Position
	local limit = accessRadius - WorldProgressionConfig.Boundary.PushbackMargin
	for _, player in ipairs(runStateService:GetMembers()) do
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then
			continue
		end
		-- Square boundary check: clamp X and Z independently
		local dx = root.Position.X - center.X
		local dz = root.Position.Z - center.Z
		if math.abs(dx) <= accessRadius + 2 and math.abs(dz) <= accessRadius + 2 then
			continue
		end
		-- Push player back to the nearest edge of the square
		local clampedX = math.clamp(dx, -limit, limit)
		local clampedZ = math.clamp(dz, -limit, limit)
		local safePosition = Vector3.new(center.X + clampedX, root.Position.Y, center.Z + clampedZ)
		root.CFrame = CFrame.new(safePosition)
		-- Kill outward velocity along the violated axis
		local velocity = root.AssemblyLinearVelocity
		if math.abs(dx) > limit then
			local sign = dx > 0 and 1 or -1
			local outward = velocity.X * sign
			if outward > 0 then
				velocity = Vector3.new(velocity.X - sign * outward, velocity.Y, velocity.Z)
			end
		end
		if math.abs(dz) > limit then
			local sign = dz > 0 and 1 or -1
			local outward = velocity.Z * sign
			if outward > 0 then
				velocity = Vector3.new(velocity.X, velocity.Y, velocity.Z - sign * outward)
			end
		end
		root.AssemblyLinearVelocity = velocity
	end
end

function WorldProgressionService:GetAccessRadius(): number
	return accessRadius
end

--[[
    @summary  Return read-only building positions for the map board.
              Scans the base map for known building models.
    @returns  { { name: string, position: Vector3 } }
]]
function WorldProgressionService:GetBuildingPositions()
	local result = {}
	local baseMap = worldService and worldService:GetBaseMap()
	if not baseMap then
		return result
	end
	local buildingNames = {
		["cabin"] = true,
		["modern-house"] = true,
		["Hunters Lodge"] = true,
		["Treehouse"] = true,
		["Tower"] = true,
		["Crashed Plane"] = true,
	}
	for _, desc in ipairs(baseMap:GetDescendants()) do
		if desc:IsA("Model") and buildingNames[desc.Name] then
			table.insert(result, {
				name = desc.Name,
				position = desc:GetPivot().Position,
			})
		end
	end
	return result
end

function WorldProgressionService:IsPositionAccessible(position: Vector3, margin: number?): boolean
	local campfireCFrame = worldService and worldService:GetCampfireCFrame()
	if not campfireCFrame then
		return false
	end
	local center = campfireCFrame.Position
	local distance = (Vector3.new(position.X, 0, position.Z) - Vector3.new(center.X, 0, center.Z)).Magnitude
	return distance <= accessRadius - (margin or 0)
end

function WorldProgressionService.Client:GetState(_player: Player): { level: number, radius: number, maxRadius: number }
	return {
		level = campfireService and campfireService:GetLevel() or 1,
		radius = accessRadius,
		maxRadius = WorldProgressionConfig.MapRadius,
	}
end

function WorldProgressionService:KnitStart()
	runStateService = Knit.GetService("RunStateService")
	worldService = Knit.GetService("WorldService")
	campfireService = Knit.GetService("CampfireService")

	runStateService.RunStarted:Connect(function()
		accessRadius = WorldProgressionConfig.GetAccessRadius(campfireService:GetLevel())
		-- Reserve wall rings at every level so buildings/facilities/caves
		-- are never placed where the boundary wall will expand to.
		WorldPlacement.Reset()
		local campfireCFrame = worldService:GetCampfireCFrame()
		if campfireCFrame then
			for _, radius in ipairs(WorldProgressionConfig.AccessRadiusByLevel) do
				WorldPlacement.ReserveRing(campfireCFrame.Position, radius, 16, "WallRing")
			end
		end
		-- Relocate buildings FIRST so their reservations are in place
		-- before facilities and caves are placed
		relocateBuildings()
		boundaryFolder = nil
		table.clear(boundaryParts)
		updateBoundary()
		broadcastExpansion(campfireService:GetLevel())
	end)
	campfireService.LevelChangedServer:Connect(function(level: number)
		setLevel(level)
	end)
	RunService.Heartbeat:Connect(constrainPlayers)
end

return WorldProgressionService
