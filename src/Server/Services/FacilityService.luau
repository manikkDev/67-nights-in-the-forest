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

-- | Modules | --
local Knit = require(ReplicatedStorage.Packages.Knit)
local JunkItemConfig = require(ReplicatedStorage.Shared.JunkItemConfig)

-- | Objects | --
local FacilityService = Knit.CreateService({
	Name = "FacilityService",
	Client = {
		FacilitySpawned = Knit.CreateSignal(),
	},
})

-- | Configuration | --
local CAMP_RADIUS = 110
local MIN_FACILITY_DISTANCE = 130
local MAX_FACILITY_DISTANCE = 400
local RESPAWN_TIME = 90
local JUNK_LIFETIME = 600
local GROUND_RAY_HEIGHT = 500

local FACILITY_COUNTS = {
	Playground = { min = 4, max = 5 },
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

local JUNK_PER_FACILITY = { min = 3, max = 6 }

-- | State Management | --
local runStateService: any = nil
local worldService: any = nil
local inventoryService: any = nil
local facilities: { { model: Model, type: string, junkSpawns: { Vector3 } } } = {}
local junkModels: { Model } = {}
local groundBounds: { minX: number, maxX: number, minZ: number, maxZ: number }? = nil
local campfirePosition: Vector3? = nil

-- // FUNCTIONS // --

-- | Private | --

--[[
    @summary  Find a random ground position outside the camp radius.
    @returns  Vector3?
]]
local function randomFacilityPosition(): Vector3?
	if not groundBounds or not campfirePosition then
		return nil
	end
	for _ = 1, 30 do
		local x = math.random() * (groundBounds.maxX - groundBounds.minX) + groundBounds.minX
		local z = math.random() * (groundBounds.maxZ - groundBounds.minZ) + groundBounds.minZ
		local candidate = Vector3.new(x, 0, z)
		local distFromCamp = (Vector3.new(x, 0, z) - Vector3.new(campfirePosition.X, 0, campfirePosition.Z)).Magnitude
		if distFromCamp >= MIN_FACILITY_DISTANCE and distFromCamp <= MAX_FACILITY_DISTANCE then
			-- Raycast to find ground height
			local baseMap = worldService:GetBaseMap()
			if baseMap then
				local params = RaycastParams.new()
				params.FilterType = Enum.RaycastFilterType.Include
				params.FilterDescendantsInstances = { baseMap }
				local result = workspace:Raycast(Vector3.new(x, GROUND_RAY_HEIGHT, z), Vector3.new(0, -GROUND_RAY_HEIGHT * 2, 0), params)
				if result then
					return result.Position
				end
			end
		end
	end
	return nil
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
		warn("[FacilityService] No inventoryService")
		return
	end
	local pivot = facilityModel:GetPivot().Position
	local angle = math.random() * math.pi * 2
	local radius = 3 + math.random() * 6
	local offsetX = math.cos(angle) * radius
	local offsetZ = math.sin(angle) * radius

	-- Raycast to find ground
	local baseMap = worldService:GetBaseMap()
	if not baseMap then
		warn("[FacilityService] No baseMap for junk spawn")
		return
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { baseMap }
	local origin = Vector3.new(pivot.X + offsetX, GROUND_RAY_HEIGHT, pivot.Z + offsetZ)
	local result = workspace:Raycast(origin, Vector3.new(0, -GROUND_RAY_HEIGHT * 2, 0), params)
	if not result then
		warn(("[FacilityService] Ground ray missed at (%.1f, %.1f) for %s"):format(origin.X, origin.Z, junkId))
		return
	end

	local model = inventoryService:BuildDropModel(junkId)
	if not model then
		warn(("[FacilityService] BuildDropModel returned nil for %s"):format(junkId))
		return
	end

	-- Calculate the model's bounding box so it sits ON the ground, not in it.
	local _, size = model:GetBoundingBox()
	local halfHeight = size.Y / 2
	local spawnY = result.Position.Y + halfHeight + 0.1

	model:PivotTo(CFrame.new(result.Position.X, spawnY, result.Position.Z) * CFrame.Angles(0, math.random() * math.pi * 2, 0))
	model.Parent = baseMap
	Debris:AddItem(model, JUNK_LIFETIME)
	table.insert(junkModels, model)
	print(("[FacilityService] Spawned %s at (%.1f, %.1f, %.1f) parent=%s"):format(junkId, result.Position.X, spawnY, result.Position.Z, baseMap.Name))
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
	for _, descendant in ipairs(baseMap:GetDescendants()) do
		if descendant:IsA("BasePart") and descendant.Name == "\u{417}\u{435}\u{43C}\u{43B}\u{44F}" then
			local halfSize = descendant.Size / 2
			groundBounds = {
				minX = descendant.Position.X - halfSize.X,
				maxX = descendant.Position.X + halfSize.X,
				minZ = descendant.Position.Z - halfSize.Z,
				maxZ = descendant.Position.Z + halfSize.Z,
			}
			print(("[FacilityService] Ground bounds: minX=%.1f maxX=%.1f minZ=%.1f maxZ=%.1f"):format(groundBounds.minX, groundBounds.maxX, groundBounds.minZ, groundBounds.maxZ))
			break
		end
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
	for facilityType, counts in pairs(FACILITY_COUNTS) do
		local count = math.random(counts.min, counts.max)
		print(("[FacilityService] Spawning %d %s"):format(count, facilityType))
		for _ = 1, count do
			local position = randomFacilityPosition()
			if not position then
				warn(("[FacilityService] No position found for %s"):format(facilityType))
				continue
			end
			local model = buildFacility(facilityType)
			if not model then
				warn(("[FacilityService] buildFacility returned nil for %s"):format(facilityType))
				continue
			end
			model:PivotTo(CFrame.new(position) * CFrame.Angles(0, math.random() * math.pi * 2, 0))
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

	runStateService.RunStarted:Connect(spawnFacilities)
	runStateService.RunCleaned:Connect(function()
		facilities = {}
		junkModels = {}
	end)
end

return FacilityService
