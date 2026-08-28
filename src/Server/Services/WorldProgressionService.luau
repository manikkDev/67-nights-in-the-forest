local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Knit = require(ReplicatedStorage.Packages.Knit)
local WorldProgressionConfig = require(ReplicatedStorage.Shared.WorldProgressionConfig)

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
	if not baseMap or not campfireCFrame then
		return
	end
	local center = campfireCFrame.Position
	local maxRadius = accessRadius - 25
	local buildingNames = {
		["cabin"] = true,
		["modern-house"] = true,
		["Hunters Lodge"] = true,
		["Treehouse"] = true,
		["Tower"] = true,
		["Crashed Plane"] = true,
	}
	local moved = 0
	for _, desc in ipairs(baseMap:GetDescendants()) do
		if desc:IsA("Model") and buildingNames[desc.Name] then
			local pivot = desc:GetPivot()
			local flatDist = (Vector3.new(pivot.Position.X, 0, pivot.Position.Z) - Vector3.new(center.X, 0, center.Z)).Magnitude
			if flatDist > maxRadius then
				local direction = if flatDist > 0
					then Vector3.new(pivot.Position.X - center.X, 0, pivot.Position.Z - center.Z).Unit
					else Vector3.xAxis
				local newFlat = center + direction * (maxRadius - 10)
				local newY = pivot.Position.Y
				desc:PivotTo(CFrame.new(newFlat.X, newY, newFlat.Z) * pivot.Rotation)
				moved += 1
			end
		end
	end
	if moved > 0 then
		print(("[WorldProgressionService] Relocated %d buildings inside the boundary"):format(moved))
	end
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
