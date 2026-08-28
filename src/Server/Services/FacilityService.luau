--[[
    @file    FacilityService.luau
    @author  manik
    @date    2025

    @summary
    Scatters facilities (Playground, Restroom, Clinic) across the forest
    each run, each containing respawning junk items for the grinder.

    @description
    On RunStarted, places 4-5 Playgrounds (common), 2-3 Restrooms
    (uncommon), and 1-2 Clinics (rare) at random ground positions
    outside the camp radius. Each facility is a generated model built
    from primitive parts. Junk items spawn around/inside each facility
    from its loot table and respawn after RESPAWN_TIME seconds.

    @exports
    - Knit Signal: FacilitySpawned()  (server -> client, optional VFX)
]]

-- // VARIABLES // --

-- | Services | --
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")
local Workspace = game:GetService("Workspace")

-- | Modules | --
local Knit = require(ReplicatedStorage.Packages.Knit)
local WorldProgressionConfig = require(ReplicatedStorage.Shared.WorldProgressionConfig)
local WorldPlacement = require(script.Parent.Parent.WorldPlacement)
local JunkItemConfig = require(ReplicatedStorage.Shared.JunkItemConfig)

-- | Objects | --
local FacilityService = Knit.CreateService({
	Name = "FacilityService",
	Client = {
		FacilitySpawned = Knit.CreateSignal(),
	},
})

-- | Configuration | --
local CAMP_RADIUS = 80
local MIN_FACILITY_DISTANCE = 60
local MAX_FACILITY_DISTANCE = 950
local RESPAWN_TIME = 90
local JUNK_LIFETIME = 600
local GROUND_RAY_HEIGHT = 500

local FACILITY_COUNTS = {
	Playground = { min = 4, max = 6 },
	Restroom = { min = 2, max = 3 },
	Clinic = { min = 1, max = 2 },
}

-- Loot tables per facility type (sourced from the 99 Nights wiki)
-- Playground (common): Bolt, Sheet Metal, Old Radio, Broken Fan, Broken Microwave, Tyre
-- Restroom (uncommon): Old Radio, Bolt, Broken Fan
-- Clinic (rare): healing items, plus Bolt, Sheet Metal, Tyre, Old Radio,
--                 Broken Fan, Broken Microwave, Metal Chair
local FACILITY_LOOT = {
	Playground = { "Bolt", "SheetMetal", "OldRadio", "BrokenFan", "BrokenMicrowave", "Tyre" },
	Restroom = { "Bolt", "OldRadio", "BrokenFan" },
	Clinic = { "Bolt", "SheetMetal", "Tyre", "OldRadio", "BrokenFan", "BrokenMicrowave", "MetalChair" },
}

local JUNK_PER_FACILITY = { min = 1, max = 3 }

-- | State Management | --
local runStateService: any = nil
local worldService: any = nil
local inventoryService: any = nil
local facilities: { { model: Model, type: string, junkSpawns: { Vector3 } } } = {}
local junkModels: { Model } = {}
local groundBounds: { minX: number, maxX: number, minZ: number, maxZ: number }? = nil
local groundY: number = 0
local campfirePosition: Vector3? = nil

-- // FUNCTIONS // --

-- | Private | --

--[[
    @summary  Find a random ground position outside the camp radius.
    @returns  Vector3?
]]
local function randomFacilityPosition(model: Model, unlockLevel: number, seed: number): CFrame?
	if not groundBounds or not campfirePosition then
		return nil
	end
	local groundPart = worldService:GetGroundPart()
	if not groundPart then
		return nil
	end
	local previousRadius = if unlockLevel > 1 then WorldProgressionConfig.GetAccessRadius(unlockLevel - 1) else MIN_FACILITY_DISTANCE
	local currentRadius = WorldProgressionConfig.GetAccessRadius(unlockLevel)
	local extents = model:GetExtentsSize()
	local footprint = Vector3.new(math.max(extents.X + 12, 24), math.max(extents.Y + 4, 12), math.max(extents.Z + 12, 24))
	local clearanceRadius = math.max(footprint.X, footprint.Z) * 0.6
	return WorldPlacement.FindPosition({
		center = campfirePosition,
		groundPart = groundPart,
		bounds = groundBounds,
		minDistance = previousRadius + 15,
		maxDistance = currentRadius - 25,
		footprint = footprint,
		clearanceRadius = clearanceRadius,
		seed = seed,
		exclusions = { groundPart },
		maxRetries = 150,
		maxSlope = 10,
	}), clearanceRadius
end

--[[
    @summary  Build a Playground facility from primitive parts.
    @returns  Model
]]
local function buildPlayground(): Model
	local model = Instance.new("Model")
	model.Name = "Playground"

	-- Slide: ramp + ladder
	local slide = Instance.new("Part")
	slide.Name = "Slide"
	slide.Size = Vector3.new(3, 0.3, 6)
	slide.Color = Color3.fromRGB(100, 150, 200)
	slide.Material = Enum.Material.SmoothPlastic
	slide.Anchored = true
	slide.CanCollide = true
	slide.CFrame = CFrame.new(0, 2, 0) * CFrame.Angles(math.rad(20), 0, 0)
	slide.Parent = model

	local ladder = Instance.new("Part")
	ladder.Name = "Ladder"
	ladder.Size = Vector3.new(1, 6, 0.3)
	ladder.Color = Color3.fromRGB(120, 120, 125)
	ladder.Material = Enum.Material.Metal
	ladder.Anchored = true
	ladder.CanCollide = true
	ladder.CFrame = CFrame.new(0, 3, -3)
	ladder.Parent = model

	-- Merry-go-round: cylinder
	local merry = Instance.new("Part")
	merry.Name = "MerryGoRound"
	merry.Size = Vector3.new(4, 0.5, 4)
	merry.Color = Color3.fromRGB(180, 100, 80)
	merry.Material = Enum.Material.Metal
	merry.Anchored = true
	merry.CanCollide = true
	merry.Shape = Enum.PartType.Cylinder
	merry.CFrame = CFrame.new(6, 0.25, 0) * CFrame.Angles(0, 0, 90)
	merry.Parent = model

	-- Swing set: A-frame with 2 seats
	local frameLeft = Instance.new("Part")
	frameLeft.Name = "FrameLeft"
	frameLeft.Size = Vector3.new(0.3, 6, 0.3)
	frameLeft.Color = Color3.fromRGB(100, 100, 105)
	frameLeft.Material = Enum.Material.Metal
	frameLeft.Anchored = true
	frameLeft.CanCollide = true
	frameLeft.CFrame = CFrame.new(-6, 3, 0) * CFrame.Angles(0, 0, math.rad(15))
	frameLeft.Parent = model

	local frameRight = Instance.new("Part")
	frameRight.Name = "FrameRight"
	frameRight.Size = Vector3.new(0.3, 6, 0.3)
	frameRight.Color = Color3.fromRGB(100, 100, 105)
	frameRight.Material = Enum.Material.Metal
	frameRight.Anchored = true
	frameRight.CanCollide = true
	frameRight.CFrame = CFrame.new(-4, 3, 0) * CFrame.Angles(0, 0, math.rad(-15))
	frameRight.Parent = model

	local swing1 = Instance.new("Part")
	swing1.Name = "Swing1"
	swing1.Size = Vector3.new(0.8, 0.2, 1.5)
	swing1.Color = Color3.fromRGB(60, 60, 60)
	swing1.Material = Enum.Material.SmoothPlastic
	swing1.Anchored = true
	swing1.CanCollide = true
	swing1.CFrame = CFrame.new(-5.3, 2, 0)
	swing1.Parent = model

	model.PrimaryPart = slide
	return model
end

--[[
    @summary  Build a Restroom facility from primitive parts.
    @returns  Model
]]
local function buildRestroom(): Model
	local model = Instance.new("Model")
	model.Name = "Restroom"

	-- Main building
	local body = Instance.new("Part")
	body.Name = "Body"
	body.Size = Vector3.new(8, 6, 6)
	body.Color = Color3.fromRGB(180, 175, 170)
	body.Material = Enum.Material.Concrete
	body.Anchored = true
	body.CanCollide = true
	body.CFrame = CFrame.new(0, 3, 0)
	body.Parent = model
	model.PrimaryPart = body

	-- Roof
	local roof = Instance.new("Part")
	roof.Name = "Roof"
	roof.Size = Vector3.new(9, 0.5, 7)
	roof.Color = Color3.fromRGB(120, 80, 60)
	roof.Material = Enum.Material.WoodPlanks
	roof.Anchored = true
	roof.CanCollide = true
	roof.CFrame = CFrame.new(0, 6.25, 0)
	roof.Parent = model

	-- Divider wall
	local divider = Instance.new("Part")
	divider.Name = "Divider"
	divider.Size = Vector3.new(0.3, 5.5, 6)
	divider.Color = Color3.fromRGB(160, 155, 150)
	divider.Material = Enum.Material.Concrete
	divider.Anchored = true
	divider.CanCollide = true
	divider.CFrame = CFrame.new(0, 2.75, 0)
	divider.Parent = model

	return model
end

--[[
    @summary  Build a Clinic facility from primitive parts.
    @returns  Model
]]
local function buildClinic(): Model
	local model = Instance.new("Model")
	model.Name = "Clinic"

	-- Main building
	local body = Instance.new("Part")
	body.Name = "Body"
	body.Size = Vector3.new(10, 7, 8)
	body.Color = Color3.fromRGB(230, 230, 235)
	body.Material = Enum.Material.SmoothPlastic
	body.Anchored = true
	body.CanCollide = true
	body.CFrame = CFrame.new(0, 3.5, 0)
	body.Parent = model
	model.PrimaryPart = body

	-- Roof
	local roof = Instance.new("Part")
	roof.Name = "Roof"
	roof.Size = Vector3.new(11, 0.5, 9)
	roof.Color = Color3.fromRGB(200, 200, 205)
	roof.Material = Enum.Material.Metal
	roof.Anchored = true
	roof.CanCollide = true
	roof.CFrame = CFrame.new(0, 7.25, 0)
	roof.Parent = model

	-- Red cross sign
	local crossV = Instance.new("Part")
	crossV.Name = "CrossVertical"
	crossV.Size = Vector3.new(0.5, 2, 0.3)
	crossV.Color = Color3.fromRGB(220, 40, 40)
	crossV.Material = Enum.Material.Neon
	crossV.Anchored = true
	crossV.CanCollide = false
	crossV.CFrame = CFrame.new(0, 5, 4.1)
	crossV.Parent = model

	local crossH = Instance.new("Part")
	crossH.Name = "CrossHorizontal"
	crossH.Size = Vector3.new(2, 0.5, 0.3)
	crossH.Color = Color3.fromRGB(220, 40, 40)
	crossH.Material = Enum.Material.Neon
	crossH.Anchored = true
	crossH.CanCollide = false
	crossH.CFrame = CFrame.new(0, 5, 4.1)
	crossH.Parent = model

	return model
end

--[[
    @summary  Build a facility model by type.
    @param    facilityType  string
    @returns  Model?
]]
local function buildFacility(facilityType: string): Model?
	if facilityType == "Playground" then
		return buildPlayground()
	elseif facilityType == "Restroom" then
		return buildRestroom()
	elseif facilityType == "Clinic" then
		return buildClinic()
	end
	return nil
end

--[[
    @summary  Spawn one junk item at a position near a facility.
    @param    facilityModel  Model
    @param    junkId         string
]]
local function spawnJunkItem(facilityModel: Model, junkId: string)
	if not inventoryService then
		return
	end
	local pivot = facilityModel:GetPivot().Position

	local baseMap = worldService:GetBaseMap()
	if not baseMap then
		return
	end

	local model = inventoryService:BuildDropModel(junkId)
	if not model then
		return
	end

	-- Scatter items widely around the facility — use a larger radius
	-- and golden-angle distribution so they don't clump together.
	local itemIndex = #junkModels + 1
	local golden = itemIndex * 2.3999632297
	local radius = 5 + math.sqrt(itemIndex) * 4
	local offsetX = math.cos(golden) * radius + (math.random() - 0.5) * 4
	local offsetZ = math.sin(golden) * radius + (math.random() - 0.5) * 4

	local spawnX = pivot.X + offsetX
	local spawnZ = pivot.Z + offsetZ

	-- Raycast to find the actual ground height at this position
	-- instead of using a flat groundY which causes floating on uneven terrain
	local groundPart = worldService:GetGroundPart()
	local actualGroundY = groundY
	if groundPart then
		local rayOrigin = Vector3.new(spawnX, groundY + 100, spawnZ)
		local rayDirection = Vector3.new(0, -200, 0)
		local raycastParams = RaycastParams.new()
		raycastParams.FilterType = Enum.RaycastFilterType.Include
		raycastParams.FilterDescendantsInstances = { groundPart }
		local result = Workspace:Raycast(rayOrigin, rayDirection, raycastParams)
		if result then
			actualGroundY = result.Position.Y
		end
	end

	-- Get the distance from the model's pivot to its lowest part
	local bottomOffset = inventoryService:GetModelBottomOffset(model)
	-- Place pivot so the lowest part sits 0.5 studs above the ground
	local spawnY = actualGroundY + bottomOffset + 0.5

	-- Do NOT apply random rotation — keep the model's authored orientation
	-- so it appears upright as designed.  Only apply a small random Y rotation.
	local yaw = (math.random() - 0.5) * math.rad(30)  -- +/- 15 degrees
	model:PivotTo(CFrame.new(spawnX, spawnY, spawnZ) * CFrame.Angles(0, yaw, 0))
	model.Parent = baseMap
	Debris:AddItem(model, JUNK_LIFETIME)
	table.insert(junkModels, model)
end

--[[
    @summary  Spawn all junk items for a facility and schedule respawns.
    @param    facility  table  -- { model, type }
]]
local function populateFacility(facility)
	local lootTable = FACILITY_LOOT[facility.type]
	if not lootTable then
		return
	end
	local count = math.random(JUNK_PER_FACILITY.min, JUNK_PER_FACILITY.max)
	for _ = 1, count do
		local junkId = lootTable[math.random(1, #lootTable)]
		spawnJunkItem(facility.model, junkId)
	end

	-- Schedule periodic respawns
	task.delay(RESPAWN_TIME, function()
		if not runStateService:IsActive() or not facility.model.Parent then
			return
		end
		local respawnCount = math.random(1, 3)
		for _ = 1, respawnCount do
			local junkId = lootTable[math.random(1, #lootTable)]
			spawnJunkItem(facility.model, junkId)
		end
		-- Re-schedule
		task.delay(RESPAWN_TIME, function()
			if runStateService:IsActive() and facility.model.Parent then
				populateFacility(facility)
			end
		end)
	end)
end

--[[
    @summary  Spawn all facilities for a new run.
]]
local function spawnFacilities()
	facilities = {}
	junkModels = {}

	-- Compute ground bounds and campfire position
	local baseMap = worldService:GetBaseMap()
	if not baseMap then
		warn("[FacilityService] Base map not found")
		return
	end
	print(("[FacilityService] Base map: %s, descendants: %d"):format(baseMap:GetFullName(), #baseMap:GetDescendants()))
	groundBounds = worldService:GetGroundBounds()
	groundY = worldService:GetGroundY() or 0
	if groundBounds then
		print(("[FacilityService] Ground bounds: minX=%.1f maxX=%.1f minZ=%.1f maxZ=%.1f topY=%.1f"):format(groundBounds.minX, groundBounds.maxX, groundBounds.minZ, groundBounds.maxZ, groundY))
	end
	campfirePosition = worldService:GetCampfireCFrame() and worldService:GetCampfireCFrame().Position or nil
	if not groundBounds or not campfirePosition then
		warn(("[FacilityService] groundBounds=%s campfirePosition=%s"):format(tostring(groundBounds), tostring(campfirePosition)))
		return
	end
	print(("[FacilityService] Campfire position: (%.1f, %.1f, %.1f)"):format(campfirePosition.X, campfirePosition.Y, campfirePosition.Z))

	local folder = Instance.new("Folder")
	folder.Name = "Facilities"
	folder.Parent = runStateService:GetRuntimeFolder()

	local totalSpawned = 0
	local seedBase = WorldPlacement.Hash(runStateService:GetRunId())
	local facilityTypes = { "Playground", "Restroom", "Clinic" }
	for typeIndex, facilityType in ipairs(facilityTypes) do
		local counts = FACILITY_COUNTS[facilityType]
		local count = math.random(counts.min, counts.max)
		print(("[FacilityService] Spawning %d %s"):format(count, facilityType))
		for index = 1, count do
			local model = buildFacility(facilityType)
			if not model then
				warn(("[FacilityService] buildFacility returned nil for %s"):format(facilityType))
				continue
			end
			local unlockLevel = ((index + typeIndex - 2) % #WorldProgressionConfig.AccessRadiusByLevel) + 1
			local placement, clearanceRadius = randomFacilityPosition(model, unlockLevel, seedBase + WorldPlacement.Hash(facilityType) + index)
			if not placement then
				warn(("[FacilityService] No collision-free position found for %s"):format(facilityType))
				model:Destroy()
				continue
			end
			-- Reserve the space BEFORE placing so subsequent facilities don't overlap
			WorldPlacement.Reserve(placement.Position, clearanceRadius, "Facility_" .. facilityType)
			model:SetAttribute("UnlockLevel", unlockLevel)
			model:PivotTo(placement)
			model.Parent = folder
			local facility = { model = model, type = facilityType }
			table.insert(facilities, facility)
			populateFacility(facility)
			totalSpawned += 1
		end
	end
	print(("[FacilityService] Total facilities spawned: %d, junk models: %d"):format(totalSpawned, #junkModels))
end

-- // INITIALIZATION // --

function FacilityService:KnitStart()
	runStateService = Knit.GetService("RunStateService")
	worldService = Knit.GetService("WorldService")
	inventoryService = Knit.GetService("InventoryService")

	runStateService.RunStarted:Connect(function()
		-- Wait one frame so buildings are relocated and reserved first
		task.defer(spawnFacilities)
	end)
	runStateService.RunCleaned:Connect(function()
		facilities = {}
		junkModels = {}
	end)
end

return FacilityService
