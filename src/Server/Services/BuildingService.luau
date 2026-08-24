--[[
    @file    BuildingService.luau
    @author  manik
    @date    2025

    @summary
    Server-authoritative structure placement, beds, gates, traps,
    farms, structure health, and run cleanup.

    @exports
    - BuildingService:DamageStructure(model, amount) -> boolean
    - BuildingService:GetStructures() -> table
    - Knit Remote: RequestPlace(tokenId, cframe)
    - Knit Remote: RequestToggleGate(structureId)
    - Knit Remote: RequestHarvest(structureId)
]]

-- // VARIABLES // --

-- | Services | --
local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")

-- | Modules | --
local Knit = require(ReplicatedStorage.Packages.Knit)
local RunConfig = require(ReplicatedStorage.Shared.RunConfig)
local StructureConfig = require(ReplicatedStorage.Shared.StructureConfig)
local CombatTargetRegistry = require(script.Parent.Parent.CombatTargetRegistry)

-- | Objects | --
local BuildingService = Knit.CreateService({
	Name = "BuildingService",
	Client = {
		StructurePlaced = Knit.CreateSignal(),
		StructureChanged = Knit.CreateSignal(),
		StructureDestroyed = Knit.CreateSignal(),
	},
})

-- | Configuration | --
local PLACE_COOLDOWN = 0.2
local INTERACT_RANGE = 12
local FARM_GROWTH_CYCLES = 2
local FARM_YIELD = 2
local TRAP_DAMAGE = 40
local STRUCTURE_TAG = "RunStructure"

-- | State Management | --
local runStateService: any = nil
local craftingService: any = nil
local worldService: any = nil
local inventoryService: any = nil
local timeService: any = nil

local structures: { [string]: { model: Model, definition: any, ownerUserId: number, placedCycle: number } } = {}
local placementCooldowns: { [Player]: number } = {}
local structuresFolder: Folder? = nil
local groundPart: BasePart? = nil

-- // FUNCTIONS // --

-- | Private | --

--[[
    @summary  Return whether every numeric CFrame component is finite.
    @param    cframe  CFrame
    @returns  boolean
]]
local function isFiniteCFrame(cframe: CFrame): boolean
	local components = { cframe:GetComponents() }
	for _, component in ipairs(components) do
		if component ~= component or component == math.huge or component == -math.huge then
			return false
		end
	end
	return true
end

--[[
    @summary  Return the Base-map ground part used by placement raycasts.
    @returns  BasePart?
]]
local function getGroundPart(): BasePart?
	if groundPart and groundPart.Parent then
		return groundPart
	end
	local baseMap = worldService and worldService:GetBaseMap()
	if not baseMap then
		return nil
	end
	groundPart = baseMap:FindFirstChild("Земля", true)
	if groundPart and not groundPart:IsA("BasePart") then
		groundPart = nil
	end
	return groundPart
end

--[[
    @summary  Build a simple server-owned model for a missing template.
    @param    structureId  string
    @returns  Model
]]
local function buildGeneratedTemplate(structureId: string): Model
	local model = Instance.new("Model")
	model.Name = structureId

	local main = Instance.new("Part")
	main.Name = "Main"
	main.Anchored = true
	main.Material = Enum.Material.WoodPlanks
	main.Color = Color3.fromRGB(105, 72, 42)
	main.Parent = model
	model.PrimaryPart = main

	if structureId == "FarmPlot" then
		main.Size = Vector3.new(10, 1, 8)
		main.Material = Enum.Material.Ground
		main.Color = Color3.fromRGB(82, 55, 35)
		for index = 1, 4 do
			local crop = Instance.new("Part")
			crop.Name = "Crop"
			crop.Shape = Enum.PartType.Ball
			crop.Size = Vector3.new(0.7, 0.7, 0.7)
			crop.Color = Color3.fromRGB(75, 150, 65)
			crop.Material = Enum.Material.Grass
			crop.Anchored = true
			crop.CanCollide = false
			local x = if index <= 2 then -2.5 else 2.5
			local z = if index % 2 == 0 then -2 else 2
			crop.CFrame = main.CFrame * CFrame.new(x, 0.8, z)
			crop.Parent = model
		end
	elseif structureId == "BearTrap" then
		main.Size = Vector3.new(5, 0.4, 5)
		main.Material = Enum.Material.Metal
		main.Color = Color3.fromRGB(90, 90, 95)
		main.Transparency = 0.15
	else
		main.Size = Vector3.new(6, 4, 5)
	end

	return model
end

--[[
    @summary  Clone the configured source for a structure.
    @param    definition  table
    @returns  Model?
]]
local function cloneTemplate(definition): Model?
	if definition.TemplateCategory == "Generated" then
		return buildGeneratedTemplate(definition.Id)
	end

	local categoryName = if definition.TemplateCategory == "Items" then "Assets Items" else "Assets maps items"
	local category = ServerStorage.Assets:FindFirstChild(categoryName)
	local source = category and category:FindFirstChild(definition.TemplateName)
	if not source then
		return nil
	end

	local model: Model
	if source:IsA("Model") then
		model = source:Clone()
	elseif source:IsA("BasePart") then
		model = Instance.new("Model")
		local part = source:Clone()
		part.Parent = model
		model.PrimaryPart = part
	else
		return nil
	end

	if not model.PrimaryPart then
		model.PrimaryPart = model:FindFirstChildWhichIsA("BasePart", true)
	end
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BaseScript") or descendant:IsA("ModuleScript") then
			descendant:Destroy()
		elseif descendant:IsA("BasePart") then
			descendant.Anchored = true
		end
	end
	return model
end

--[[
    @summary  Apply visual differences to each bed tier.
    @param    model        Model
    @param    structureId  string
]]
local function styleBed(model: Model, structureId: string)
	local colors = {
		OldBed = Color3.fromRGB(105, 85, 65),
		RegularBed = Color3.fromRGB(70, 120, 95),
		GoodBed = Color3.fromRGB(145, 95, 55),
		GiantBed = Color3.fromRGB(120, 75, 150),
	}
	local targetColor = colors[structureId]
	if not targetColor then
		return
	end
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") and descendant.Material ~= Enum.Material.Wood then
			descendant.Color = targetColor
		end
	end
	if structureId == "GiantBed" then
		model:ScaleTo(1.35)
	elseif structureId == "GoodBed" then
		model:ScaleTo(1.12)
	end
end

--[[
    @summary  Snap a requested placement to authoritative ground and rotation.
    @param    requested   CFrame
    @param    definition  table
    @returns  CFrame?
]]
local function authoritativeCFrame(requested: CFrame, definition): CFrame?
	local grid = RunConfig.PlacementGrid
	local snappedX = math.round(requested.Position.X / grid) * grid
	local snappedZ = math.round(requested.Position.Z / grid) * grid
	local _, yaw = requested:ToEulerAnglesYXZ()
	local rotationStep = math.rad(RunConfig.PlacementRotationDegrees)
	local snappedYaw = math.round(yaw / rotationStep) * rotationStep

	local origin = Vector3.new(snappedX, requested.Position.Y + 80, snappedZ)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	local baseMap = worldService and worldService:GetBaseMap()
	if not baseMap then
		return nil
	end
	params.FilterDescendantsInstances = { baseMap }
	local result = workspace:Raycast(origin, Vector3.new(0, -180, 0), params)
	if not result then
		return nil
	end
	local upDot = result.Normal:Dot(Vector3.yAxis)
	local slope = math.deg(math.acos(math.clamp(upDot, -1, 1)))
	if slope > math.min(definition.MaxSlope, RunConfig.PlacementMaxSlope) then
		return nil
	end

	local y = result.Position.Y + definition.Footprint.Y * 0.5
	return CFrame.new(snappedX, y, snappedZ) * CFrame.Angles(0, snappedYaw, 0)
end

--[[
    @summary  Return whether a footprint is free of blocking geometry.
    @param    player       Player
    @param    cframe       CFrame
    @param    definition   table
    @returns  boolean
]]
local function isFootprintFree(player: Player, cframe: CFrame, definition): boolean
	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Exclude
	local exclusions = { player.Character, getGroundPart() }
	local filtered = {}
	for _, instance in ipairs(exclusions) do
		if instance then
			table.insert(filtered, instance)
		end
	end
	overlap.FilterDescendantsInstances = filtered

	local size = Vector3.new(
		math.max(0.1, definition.Footprint.X - 0.2),
		math.max(0.1, definition.Footprint.Y - 0.2),
		math.max(0.1, definition.Footprint.Z - 0.2)
	)
	for _, part in ipairs(workspace:GetPartBoundsInBox(cframe, size, overlap)) do
		if part.CanCollide and part.Transparency < 0.95 then
			return false
		end
	end
	return true
end

--[[
    @summary  Return whether a position lies within the camp build radius.
    @param    position  Vector3
    @returns  boolean
]]
local function isInsideBuildZone(position: Vector3): boolean
	local campfireCFrame = worldService and worldService:GetCampfireCFrame()
	if not campfireCFrame then
		return false
	end
	local offset = Vector3.new(position.X, 0, position.Z) - Vector3.new(campfireCFrame.Position.X, 0, campfireCFrame.Position.Z)
	return offset.Magnitude <= RunConfig.CampBuildRadius
end

--[[
    @summary  Return how many authoritative structures currently exist.
    @returns  number
]]
local function structureCount(): number
	local count = 0
	for _ in pairs(structures) do
		count += 1
	end
	return count
end

--[[
    @summary  Broadcast one structure delta to every run member.
    @param    signal  table
    @param    payload table
]]
local function broadcast(signal, payload)
	for _, player in ipairs(runStateService:GetMembers()) do
		signal:Fire(player, payload)
	end
end

--[[
    @summary  Add interactions and behavior specific to one structure type.
    @param    record  table
]]
local function wireStructure(record)
	local model = record.model
	local structureId = record.definition.Id
	local anchor = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
	if not anchor then
		return
	end

	if structureId == "LogGate" then
		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "Toggle Gate"
		prompt.ObjectText = "Log Gate"
		prompt.MaxActivationDistance = INTERACT_RANGE
		prompt.Parent = anchor
		prompt.Triggered:Connect(function(player)
			BuildingService.Client:RequestToggleGate(player, model:GetAttribute("StructureId"))
		end)
	elseif structureId == "FarmPlot" then
		model:SetAttribute("ReadyCycle", timeService:GetCycleIndex() + FARM_GROWTH_CYCLES)
		model:SetAttribute("Ready", false)
		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "Harvest"
		prompt.ObjectText = "Farm Plot"
		prompt.MaxActivationDistance = INTERACT_RANGE
		prompt.Enabled = false
		prompt.Parent = anchor
		prompt.Triggered:Connect(function(player)
			BuildingService.Client:RequestHarvest(player, model:GetAttribute("StructureId"))
		end)
	elseif structureId == "BearTrap" then
		model:SetAttribute("Armed", true)
		anchor.Touched:Connect(function(hit)
			if model:GetAttribute("Armed") ~= true then
				return
			end
			local target = hit:FindFirstAncestorOfClass("Model")
			if not target or not CollectionService:HasTag(target, CombatTargetRegistry.TagName) then
				return
			end
			local handlers = CombatTargetRegistry.Get(target)
			if not handlers then
				return
			end
			model:SetAttribute("Armed", false)
			handlers.ApplyDamage(TRAP_DAMAGE, nil)
			BuildingService:DamageStructure(model, record.definition.MaxHealth)
		end)
	end
end

--[[
    @summary  Mark ready farm plots at dawn.
    @param    payload  table
]]
local function onDawn(payload)
	for _, record in pairs(structures) do
		if record.definition.Id == "FarmPlot" and record.model.Parent then
			local readyCycle = record.model:GetAttribute("ReadyCycle")
			if typeof(readyCycle) == "number" and payload.cycleIndex >= readyCycle then
				record.model:SetAttribute("Ready", true)
				local prompt = record.model:FindFirstChildWhichIsA("ProximityPrompt", true)
				if prompt then
					prompt.Enabled = true
				end
			end
		end
	end
end

-- | Public | --

--[[
    @summary  Return a shallow copy of all live structure records.
    @returns  table
]]
function BuildingService:GetStructures(): { [string]: any }
	return table.clone(structures)
end

--[[
    @summary  Damage and destroy a registered structure when depleted.
    @param    model   Model
    @param    amount  number
    @returns  boolean  -- true when the structure was destroyed
]]
function BuildingService:DamageStructure(model: Model, amount: number): boolean
	if typeof(amount) ~= "number" or amount <= 0 then
		return false
	end
	local structureId = model:GetAttribute("StructureId")
	local record = typeof(structureId) == "string" and structures[structureId] or nil
	if not record then
		return false
	end
	local health = math.max(0, (model:GetAttribute("Health") or record.definition.MaxHealth) - amount)
	model:SetAttribute("Health", health)
	broadcast(BuildingService.Client.StructureChanged, { structureId = structureId, health = health })
	if health > 0 then
		return false
	end

	structures[structureId] = nil
	CollectionService:RemoveTag(model, STRUCTURE_TAG)
	broadcast(BuildingService.Client.StructureDestroyed, { structureId = structureId, position = model:GetPivot().Position })
	model:Destroy()
	return true
end

--[[
    @summary  Validate and place one crafted structure.
    @param    player           Player  -- injected by Knit
    @param    tokenId          string
    @param    requestedCFrame  CFrame
    @returns  table
]]
function BuildingService.Client:RequestPlace(player: Player, tokenId: string, requestedCFrame: CFrame): { [string]: any }
	if typeof(tokenId) ~= "string" or typeof(requestedCFrame) ~= "CFrame" or not isFiniteCFrame(requestedCFrame) then
		return { ok = false, code = "INVALID_REQUEST" }
	end
	if not runStateService:IsActive() or not runStateService:IsMember(player) then
		return { ok = false, code = "NOT_ACTIVE" }
	end
	if structureCount() >= RunConfig.MaxStructures then
		return { ok = false, code = "TOTAL_CAP_REACHED" }
	end

	local token = craftingService:GetPlacementToken(player, tokenId)
	if not token or token.runId ~= runStateService:GetRunId() then
		return { ok = false, code = "INVALID_TOKEN" }
	end
	local definition = StructureConfig[token.structureId]
	if not definition then
		return { ok = false, code = "INVALID_STRUCTURE" }
	end

	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not rootPart or not rootPart:IsA("BasePart") or not humanoid or humanoid.Health <= 0 then
		return { ok = false, code = "INVALID_PLAYER" }
	end
	if (rootPart.Position - requestedCFrame.Position).Magnitude > RunConfig.PlacementMaxRange then
		return { ok = false, code = "TOO_FAR" }
	end
	if not isInsideBuildZone(requestedCFrame.Position) then
		return { ok = false, code = "OUTSIDE_BUILD_ZONE" }
	end

	local now = os.clock()
	if placementCooldowns[player] and now - placementCooldowns[player] < PLACE_COOLDOWN then
		return { ok = false, code = "RATE_LIMITED" }
	end
	placementCooldowns[player] = now

	local finalCFrame = authoritativeCFrame(requestedCFrame, definition)
	if not finalCFrame then
		return { ok = false, code = "INVALID_GROUND" }
	end
	if not isFootprintFree(player, finalCFrame, definition) then
		return { ok = false, code = "OVERLAP" }
	end

	local model = cloneTemplate(definition)
	if not model then
		return { ok = false, code = "MISSING_TEMPLATE" }
	end
	styleBed(model, definition.Id)
	local capturedRunId = runStateService:GetRunId()
	local structureId = HttpService:GenerateGUID(false)
	model.Name = definition.Id
	model:SetAttribute("StructureId", structureId)
	model:SetAttribute("StructureType", definition.Id)
	model:SetAttribute("OwnerUserId", player.UserId)
	model:SetAttribute("RunId", capturedRunId)
	model:SetAttribute("MaxHealth", definition.MaxHealth)
	model:SetAttribute("Health", definition.MaxHealth)
	model:SetAttribute("PlacedCycle", timeService:GetCycleIndex())
	model.Parent = structuresFolder
	model:PivotTo(finalCFrame)
	CollectionService:AddTag(model, STRUCTURE_TAG)

	if not craftingService:ConsumePlacementToken(player, tokenId) or not runStateService:IsCurrentRun(capturedRunId) then
		model:Destroy()
		return { ok = false, code = "RUN_CHANGED" }
	end

	local record = {
		model = model,
		definition = definition,
		ownerUserId = player.UserId,
		placedCycle = timeService:GetCycleIndex(),
	}
	structures[structureId] = record
	wireStructure(record)
	runStateService:IncrementStat(player, "StructuresBuilt", 1)

	if definition.MultiplierPoints then
		runStateService:AddMultiplierSource("Bed:" .. definition.Id, definition.MultiplierPoints)
	end

	local payload = {
		structureId = structureId,
		structureType = definition.Id,
		ownerUserId = player.UserId,
		cframe = finalCFrame,
		health = definition.MaxHealth,
	}
	broadcast(BuildingService.Client.StructurePlaced, payload)
	return { ok = true, code = "OK", structure = payload }
end

--[[
    @summary  Toggle a nearby live gate between blocking and open states.
    @param    player       Player  -- injected by Knit
    @param    structureId  string
    @returns  boolean
]]
function BuildingService.Client:RequestToggleGate(player: Player, structureId: string): boolean
	if typeof(structureId) ~= "string" then
		return false
	end
	local record = structures[structureId]
	if not record or record.definition.Id ~= "LogGate" then
		return false
	end
	local rootPart = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not rootPart or not rootPart:IsA("BasePart") or (rootPart.Position - record.model:GetPivot().Position).Magnitude > INTERACT_RANGE then
		return false
	end
	local isOpen = record.model:GetAttribute("Open") == true
	record.model:SetAttribute("Open", not isOpen)
	for _, descendant in ipairs(record.model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.CanCollide = isOpen
			descendant.Transparency = if isOpen then math.max(0, descendant.Transparency - 0.35) else math.min(0.65, descendant.Transparency + 0.35)
		end
	end
	broadcast(BuildingService.Client.StructureChanged, { structureId = structureId, open = not isOpen })
	return true
end

--[[
    @summary  Collect a ready farm and begin its next growth cycle.
    @param    player       Player  -- injected by Knit
    @param    structureId  string
    @returns  boolean
]]
function BuildingService.Client:RequestHarvest(player: Player, structureId: string): boolean
	if typeof(structureId) ~= "string" then
		return false
	end
	local record = structures[structureId]
	if not record or record.definition.Id ~= "FarmPlot" or record.model:GetAttribute("Ready") ~= true then
		return false
	end
	local rootPart = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not rootPart or not rootPart:IsA("BasePart") or (rootPart.Position - record.model:GetPivot().Position).Magnitude > INTERACT_RANGE then
		return false
	end
	local added = inventoryService:AddResource(player, "Berries", FARM_YIELD)
	if added <= 0 then
		return false
	end
	record.model:SetAttribute("Ready", false)
	record.model:SetAttribute("ReadyCycle", timeService:GetCycleIndex() + FARM_GROWTH_CYCLES)
	local prompt = record.model:FindFirstChildWhichIsA("ProximityPrompt", true)
	if prompt then
		prompt.Enabled = false
	end
	broadcast(BuildingService.Client.StructureChanged, { structureId = structureId, ready = false })
	return true
end

-- // INITIALIZATION // --

function BuildingService:KnitStart()
	runStateService = Knit.GetService("RunStateService")
	craftingService = Knit.GetService("CraftingService")
	worldService = Knit.GetService("WorldService")
	inventoryService = Knit.GetService("InventoryService")
	timeService = Knit.GetService("TimeService")

	runStateService.RunStarted:Connect(function()
		structures = {}
		placementCooldowns = {}
		groundPart = nil
		local folder = Instance.new("Folder")
		folder.Name = "Structures"
		folder.Parent = runStateService:GetRuntimeFolder()
		structuresFolder = folder
	end)
	runStateService.RunCleaned:Connect(function()
		structures = {}
		structuresFolder = nil
		placementCooldowns = {}
	end)
	timeService:OnDawn(onDawn)

	Players.PlayerRemoving:Connect(function(player)
		placementCooldowns[player] = nil
	end)
end

return BuildingService
