local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Knit = require(ReplicatedStorage.Packages.Knit)
local ServerRole = require(ReplicatedStorage.Shared.ServerRole)
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
local accessRadius = WorldProgressionConfig.GetAccessRadius(1)
local checkTimer = 0

local function broadcastExpansion(level: number)
	WorldProgressionService.Client.AccessRadius:Set(accessRadius)
	if not runStateService or not runStateService:IsActive() then
		return
	end
	for _, player in ipairs(runStateService:GetMembers()) do
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
			groundPart = groundPart,
			bounds = bounds,
			minDistance = ringMin,
			maxDistance = ringMax,
			footprint = footprint,
			clearanceRadius = clearanceRadius,
			seed = seedBase + index * 7,
			exclusions = { groundPart },
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
			local groundCFrame = WorldPlacement.GetGroundCFrame(groundPart, pivot.Position, 0)
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
	for index = 1, WorldProgressionConfig.Boundary.ServerSegments do
		local part = Instance.new("Part")
		part.Name = "BoundaryCollider" .. index
		part.Anchored = true
		part.CanCollide = true
		part.CanTouch = false
		part.CanQuery = false
		-- Opaque dark wall so players cannot see anything beyond the boundary.
		part.Transparency = 0
		part.Material = Enum.Material.SmoothPlastic
		part.Color = Color3.fromRGB(18, 20, 24)
		part.CastShadow = false
		part.Reflectance = 0
		part.Parent = folder
		table.insert(boundaryParts, part)
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
	local segmentLength = 2 * math.pi * accessRadius / count + 12
	local height = WorldProgressionConfig.Boundary.Height
	for index, part in ipairs(boundaryParts) do
		local angle = (index - 1) * 2 * math.pi / count
		local radial = Vector3.new(math.cos(angle), 0, math.sin(angle))
		local position = campfireCFrame.Position + radial * accessRadius
		position = Vector3.new(position.X, groundY + height * 0.5, position.Z)
		part.Size = Vector3.new(segmentLength, height, 14)
		part.CFrame = CFrame.lookAt(position, position - radial)
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
		local delta = Vector3.new(root.Position.X - center.X, 0, root.Position.Z - center.Z)
		if delta.Magnitude <= accessRadius + 2 then
			continue
		end
		local direction = if delta.Magnitude > 0 then delta.Unit else Vector3.xAxis
		local safePosition = Vector3.new(center.X, root.Position.Y, center.Z) + direction * limit
		root.CFrame = CFrame.new(safePosition, safePosition - direction)
		local velocity = root.AssemblyLinearVelocity
		local outward = velocity:Dot(direction)
		if outward > 0 then
			root.AssemblyLinearVelocity = velocity - direction * outward
		end
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
	if ServerRole.IsLobby() then return end
	runStateService = Knit.GetService("RunStateService")
	worldService = Knit.GetService("WorldService")
	campfireService = Knit.GetService("CampfireService")

	runStateService.RunStarted:Connect(function()
		accessRadius = WorldProgressionConfig.GetAccessRadius(campfireService:GetLevel())
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
