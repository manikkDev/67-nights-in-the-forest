--[[
    @file    RescueService.luau
    @author  manik
    @date    2025

    @summary
    Four campfire-gated caves, guard packs, keys, gates, child carrying,
    safe-zone rescue completion, tents, poster targeting, and multiplier.

    @exports
    - RescueService:GetRescuedCount() -> number
    - RescueService:DropCarriedChild(player)
    - Knit Remote: RequestDropChild()
    - Knit Remote: RequestBoardTarget()
]]

-- // VARIABLES // --

-- | Services | --
local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- | Modules | --
local Knit = require(ReplicatedStorage.Packages.Knit)
local RescueConfig = require(ReplicatedStorage.Shared.RescueConfig)
local WorldProgressionConfig = require(ReplicatedStorage.Shared.WorldProgressionConfig)
local WorldPlacement = require(script.Parent.Parent.WorldPlacement)

-- | Objects | --
local RescueService = Knit.CreateService({
	Name = "RescueService",
	Client = {
		RescueChanged = Knit.CreateSignal(),
		WaypointChanged = Knit.CreateSignal(),
		ChildCarryChanged = Knit.CreateSignal(),
		CaveUnlocked = Knit.CreateSignal(),
		BoardOpened = Knit.CreateSignal(),
		PosterStateUpdated = Knit.CreateSignal(),
	},
})

-- | Configuration | --
local CAVE_ORDER = { "Dino", "Kraken", "Squid", "Koala" }
local TENT_COLORS = {
	Color3.fromRGB(185, 55, 50),
	Color3.fromRGB(55, 115, 195),
	Color3.fromRGB(225, 190, 55),
	Color3.fromRGB(135, 75, 160),
}
local PICKUP_RANGE = 10
local DROP_COOLDOWN = 0.35
local CARRY_WALK_SPEED = 10
local RESCUE_CHECK_INTERVAL = 0.2

-- | State Management | --
local runStateService: any = nil
local worldService: any = nil
local campfireService: any = nil
local animalAIService: any = nil
local playerLifeService: any = nil

local caveRecords: { [string]: any } = {}
local carriedBy: { [Player]: string } = {}
local keyOwners: { [Player]: { [string]: boolean } } = {}
local dropCooldowns: { [Player]: number } = {}
local rescuedCount = 0
local rescueOrder = 0
local rescueCheckTimer = 0
local cavesFolder: Folder? = nil
local tentsFolder: Folder? = nil
local posterBoard: Part? = nil
local posterSlots: { [string]: { frame: Frame, viewport: ViewportFrame, blackOverlay: Frame, foundStamp:TextLabel, nameLabel: TextLabel, model: Model? } } = {}
local exclamationPart: Part? = nil
local heartbeatConnection: RBXScriptConnection? = nil

-- // FUNCTIONS // --

-- | Private | --

--[[
    @summary  Broadcast one rescue-state delta to all run members.
    @param    signal   table
    @param    payload  table
]]
local function broadcast(signal, payload)
	for _, player in ipairs(runStateService:GetMembers()) do
		signal:Fire(player, payload)
	end
end

--[[
    @summary  Return ground-level position for a desired cave or tent.
    @desc     Uses the ground baseplate's top-surface Y from WorldService
              instead of raycasting, which could hit trees or houses and
              place the cave on top of them.
    @param    position  Vector3
    @returns  Vector3
]]
local function groundPosition(position: Vector3): Vector3
	local gy = worldService and worldService:GetGroundY()
	if gy then
		return Vector3.new(position.X, gy, position.Z)
	end
	-- Fallback: raycast against only the ground baseplate, not trees/houses.
	local baseMap = worldService and worldService:GetBaseMap()
	if not baseMap then
		return position
	end
	-- Find the ground part specifically to raycast against.
	local groundPart: BasePart? = nil
	for _, desc in ipairs(baseMap:GetDescendants()) do
		if desc:IsA("BasePart") and desc.Name == "Земля" then
			groundPart = desc
			break
		end
	end
	if groundPart then
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Include
		params.FilterDescendantsInstances = { groundPart }
		local result = workspace:Raycast(position + Vector3.new(0, 120, 0), Vector3.new(0, -240, 0), params)
		return if result then result.Position else Vector3.new(position.X, groundPart.Position.Y + groundPart.Size.Y / 2, position.Z)
	end
	return position
end

--[[
    @summary  Create one anchored cave enclosure and gate.
    @param    definition  table
    @param    center      Vector3
    @returns  Model, Part
]]
local function createCaveModel(definition, center: Vector3): (Model, Part)
	local cave = Instance.new("Model")
	cave.Name = definition.Id .. "Cave"
	cave:SetAttribute("CaveId", definition.Id)
	cave:SetAttribute("RequiredCampfireLevel", definition.RequiredCampfireLevel)
	cave:SetAttribute("State", "Locked")

	local floor = Instance.new("Part")
	floor.Name = "Floor"
	floor.Size = Vector3.new(34, 1, 32)
	floor.Position = center + Vector3.new(0, 0.5, 0)
	floor.Anchored = true
	floor.Material = Enum.Material.Slate
	floor.Color = Color3.fromRGB(62, 58, 55)
	floor.Parent = cave
	cave.PrimaryPart = floor

	local wallData = {
		{ Vector3.new(34, 12, 2), Vector3.new(0, 6, -15) },
		{ Vector3.new(12, 12, 2), Vector3.new(-11, 6, 15) },
		{ Vector3.new(12, 12, 2), Vector3.new(11, 6, 15) },
		{ Vector3.new(2, 12, 30), Vector3.new(-16, 6, 0) },
		{ Vector3.new(2, 12, 30), Vector3.new(16, 6, 0) },
	}
	for index, entry in ipairs(wallData) do
		local wall = Instance.new("Part")
		wall.Name = "CaveWall" .. index
		wall.Size = entry[1]
		wall.Position = center + entry[2]
		wall.Anchored = true
		wall.Material = Enum.Material.Rock
		wall.Color = Color3.fromRGB(55, 52, 50)
		wall.Parent = cave
	end

	local gate = Instance.new("Part")
	gate.Name = "Gate"
	gate.Size = Vector3.new(10, 10, 1)
	gate.Position = center + Vector3.new(0, 5, 14)
	gate.Anchored = true
	gate.Material = Enum.Material.Metal
	gate.Color = definition.CaveColor
	gate:SetAttribute("CaveId", definition.Id)
	gate:SetAttribute("Locked", true)
	gate.Parent = cave

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "UnlockGatePrompt"
	prompt.ActionText = "Unlock"
	prompt.ObjectText = definition.KeyName .. " Gate"
	prompt.MaxActivationDistance = PICKUP_RANGE
	prompt.RequiresLineOfSight = false
	prompt.Enabled = false
	prompt.Parent = gate
	prompt.Triggered:Connect(function(player)
		RescueService:TryUnlockGate(player, definition.Id)
	end)

	return cave, gate
end

--[[
    @summary  Apply a distinct visual variant to a duplicated child rig.
    @param    model       Model
    @param    definition  table
]]
local function styleChildVariant(model: Model, definition)
	if not definition.Variant then
		return
	end
	local bodyColor = if definition.Variant == "Squid" then Color3.fromRGB(225, 190, 70) else Color3.fromRGB(85, 80, 90)
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") and descendant.Name ~= "HumanoidRootPart" then
			descendant.Color = descendant.Color:Lerp(bodyColor, 0.35)
		end
	end
	local head = model:FindFirstChild("Head")
	if not head or not head:IsA("BasePart") then
		return
	end
	local hat = Instance.new("Part")
	hat.Name = definition.Variant .. "Hat"
	hat.Shape = Enum.PartType.Ball
	hat.Size = if definition.Variant == "Squid" then Vector3.new(2.2, 1.3, 2.2) else Vector3.new(2.3, 1.1, 2.1)
	hat.Color = definition.CaveColor
	hat.Material = Enum.Material.SmoothPlastic
	hat.CanCollide = false
	hat.Massless = true
	hat.CFrame = head.CFrame * CFrame.new(0, 1, 0)
	hat.Parent = model
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = head
	weld.Part1 = hat
	weld.Parent = hat
end

--[[
    @summary  Clone and prepare one child inside its cave.
    @param    definition  table
    @param    center      Vector3
    @returns  Model?
]]
local function createChild(definition, caveCFrame: CFrame): Model?
	local npcAssets = ServerStorage.Assets:FindFirstChild("Assets Npcs")
	local source = npcAssets and npcAssets:FindFirstChild(definition.RigTemplate)
	if not source or not source:IsA("Model") then
		warn("[RescueService] Missing child rig", definition.RigTemplate)
		return nil
	end
	local child = source:Clone()
	child.Name = definition.DisplayName
	child:SetAttribute("ChildId", definition.Id)
	child:SetAttribute("RescueState", "Locked")
	for _, descendant in ipairs(child:GetDescendants()) do
		if descendant:IsA("BaseScript") or descendant:IsA("ModuleScript") then
			descendant:Destroy()
		elseif descendant:IsA("BasePart") then
			descendant.CanCollide = false
		end
	end
	styleChildVariant(child, definition)
	child.Parent = cavesFolder
	child:PivotTo(caveCFrame * CFrame.new(0, 3, -7))
	-- Search recursively for HumanoidRootPart (may not be a direct child)
	local rootPart = child:FindFirstChild("HumanoidRootPart")
	if not rootPart then
		rootPart = child:FindFirstChildWhichIsA("BasePart", true)
	end
	if rootPart and rootPart:IsA("BasePart") then
		rootPart.Anchored = true
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "RescueChildPrompt"
		prompt.ActionText = "Carry Child"
		prompt.ObjectText = definition.DisplayName
		prompt.MaxActivationDistance = PICKUP_RANGE
		prompt.RequiresLineOfSight = false
		prompt.Enabled = false
		prompt.Parent = rootPart
		prompt.Triggered:Connect(function(player)
			RescueService:TryCarryChild(player, definition.Id)
		end)
	else
		warn("[RescueService] Could not find root part for child", definition.DisplayName)
	end
	return child
end

--[[
    @summary  Remove map geometry (trees, structures) overlapping a cave
              site so the cave can sit cleanly on the ground.
    @desc     Only removes parts whose top-level model ancestor is inside
              the base map.  Never removes the ground, expanded ground,
              campfire, bonfire, or runtime folder contents.
    @param    cframe     CFrame   -- cave centre
    @param    footprint  Vector3  -- clearance box
]]
local function clearCaveObstacles(cframe: CFrame, footprint: Vector3)
	local baseMap = worldService:GetBaseMap()
	local runtimeFolder = runStateService:GetRuntimeFolder()
	local exclusions = {}
	-- Only exclude the ground part and other caves/tents
	local ground = worldService:GetGroundPart()
	if ground then
		table.insert(exclusions, ground)
	end
	if cavesFolder then
		table.insert(exclusions, cavesFolder)
	end
	if tentsFolder then
		table.insert(exclusions, tentsFolder)
	end

	-- Use a larger footprint for clearing (extra 10 studs on each side)
	local clearFootprint = Vector3.new(footprint.X + 10, footprint.Y + 4, footprint.Z + 10)
	local overlaps = WorldPlacement.GetFootprintOverlaps(cframe, clearFootprint, exclusions)
	for _, part in ipairs(overlaps) do
		-- Walk up to find the top-level model/folder to remove
		local toRemove = part
		local ancestor = part.Parent
		while ancestor and ancestor.Parent do
			if ancestor:IsA("Model") or ancestor:IsA("Folder") then
				if ancestor.Parent == workspace or ancestor.Parent == baseMap or ancestor == runtimeFolder then
					toRemove = ancestor
					break
				end
			end
			ancestor = ancestor.Parent
		end
		-- Never remove the ground
		if toRemove:IsA("BasePart") and (toRemove.Name == "Земля" or toRemove.Name == "Ground") then
			continue
		end
		-- Never remove the campfire/bonfire
		if toRemove.Name == "Bonfire" or toRemove.Name == "Campfire" then
			continue
		end
		-- Never remove caves, tents, or the runtime folder itself
		if toRemove == cavesFolder or toRemove == tentsFolder or toRemove == runtimeFolder then
			continue
		end
		-- Skip if it's another cave model
		if toRemove:IsA("Model") and toRemove:GetAttribute("CaveId") then
			continue
		end
		-- Skip the poster board model
		if toRemove:IsA("Model") and toRemove.Name == "MissingChildrenBoard" then
			continue
		end
		toRemove:Destroy()
	end
end

--[[
    @summary  Build all four cave records for a fresh run.
]]
local function buildCaves()
	caveRecords = {}
	carriedBy = {}
	keyOwners = {}
	rescuedCount = 0
	rescueOrder = 0
	rescueCheckTimer = 0

	local caves = Instance.new("Folder")
	caves.Name = "Caves"
	caves.Parent = runStateService:GetRuntimeFolder()
	cavesFolder = caves
	local tents = Instance.new("Folder")
	tents.Name = "RescueTents"
	tents.Parent = runStateService:GetRuntimeFolder()
	tentsFolder = tents

	local campfireCFrame = worldService:GetCampfireCFrame()
	local groundPart = worldService:GetGroundPart()
	local bounds = worldService:GetGroundBounds()
	if not campfireCFrame or not groundPart or not bounds then
		return
	end
	local seedBase = WorldPlacement.Hash(runStateService:GetRunId())
	for index, rescueId in ipairs(CAVE_ORDER) do
		local definition = RescueConfig[rescueId]
		local ring = WorldProgressionConfig.CaveRings[rescueId]
		local caveCFrame, overlapCount = WorldPlacement.FindPosition({
			center = campfireCFrame.Position,
			groundPart = groundPart,
			bounds = bounds,
			minDistance = ring.Min,
			maxDistance = ring.Max,
			footprint = WorldProgressionConfig.Placement.CaveFootprint,
			clearanceRadius = WorldProgressionConfig.Placement.CaveSpacing,
			seed = seedBase + WorldPlacement.Hash(rescueId) + index,
			exclusions = { groundPart },
			maxRetries = WorldProgressionConfig.Placement.MaxRetries,
			maxSlope = WorldProgressionConfig.Placement.MaxSlope,
			faceCenter = true,
		})
		if not caveCFrame then
			warn("[RescueService] No cave position found for", rescueId)
			continue
		end
		local center = caveCFrame.Position
		-- Always clear obstacles (even if overlapCount is 0, the expanded
		-- clearing footprint may catch nearby objects)
		if overlapCount and overlapCount > 0 then
			print(("[RescueService] Clearing %d obstacles for %s cave"):format(overlapCount, rescueId))
		end
		clearCaveObstacles(
			caveCFrame * CFrame.new(0, WorldProgressionConfig.Placement.CaveFootprint.Y * 0.5, 0),
			WorldProgressionConfig.Placement.CaveFootprint
		)
		WorldPlacement.Reserve(center, WorldProgressionConfig.Placement.CaveSpacing, "Cave_" .. rescueId)
		local cave, gate = createCaveModel(definition, center)
		cave.Parent = cavesFolder
		cave:PivotTo(caveCFrame * CFrame.new(0, 0.5, 0))
		-- Clear obstacles again AFTER placing the cave (the cave itself is now in cavesFolder, which is excluded)
		clearCaveObstacles(
			caveCFrame * CFrame.new(0, WorldProgressionConfig.Placement.CaveFootprint.Y * 0.5, 0),
			WorldProgressionConfig.Placement.CaveFootprint
		)
		local child = createChild(definition, caveCFrame)
		caveRecords[rescueId] = {
			definition = definition,
			model = cave,
			gate = gate,
			child = child,
			center = center,
			state = "Locked",
			guards = {},
			keyModel = nil,
			carrier = nil,
			carryWeld = nil,
			originalWalkSpeed = nil,
		}
	end
end

--[[
    @summary  Spawn one cave's configured guard pack.
    @param    record  table
]]
local function spawnGuards(record)
	for index = 1, record.definition.GuardCount do
		local angle = index / record.definition.GuardCount * math.pi * 2
		local position = record.center + Vector3.new(math.cos(angle) * 24, 4, math.sin(angle) * 24)
		local guard = animalAIService:SpawnNpc(record.definition.GuardSpecies, CFrame.new(position))
		if guard then
			guard:SetAttribute("GuardCaveId", record.definition.Id)
			guard:SetAttribute("GuardIndex", index)
			guard:SetAttribute("GuardIcon", record.definition.Id)
			record.guards[guard] = true
		end
	end
end

--[[
    @summary  Activate all caves reached by the current campfire level.
    @param    campfireLevel  number
]]
local function unlockForLevel(campfireLevel: number)
	for rescueId, record in pairs(caveRecords) do
		if record.state == "Locked" and campfireLevel >= record.definition.RequiredCampfireLevel then
			record.state = "Available"
			record.model:SetAttribute("State", "Available")
			spawnGuards(record)
			broadcast(RescueService.Client.CaveUnlocked, {
				rescueId = rescueId,
				displayName = record.definition.DisplayName,
				position = record.center,
				requiredCampfireLevel = record.definition.RequiredCampfireLevel,
			})
		end
	end
end

--[[
    @summary  Spawn the matching key after a cave guard pack is cleared.
    @param    record  table
]]
local function spawnKey(record)
	if record.keyModel or (record.state ~= "Available" and record.state ~= "KeyDropped") then
		return
	end
	record.state = "KeyDropped"
	local key = Instance.new("Model")
	key.Name = record.definition.KeyName
	key:SetAttribute("CaveId", record.definition.Id)
	key:SetAttribute("RunId", runStateService:GetRunId())
	local part = Instance.new("Part")
	part.Name = "Key"
	part.Size = Vector3.new(0.5, 0.5, 2.3)
	part.Color = record.definition.CaveColor
	part.Material = Enum.Material.Neon
	part.Anchored = true
	part.CanCollide = false
	part.Parent = key
	key.PrimaryPart = part
	key.Parent = cavesFolder
	key:PivotTo(CFrame.new(record.center + Vector3.new(0, 2, 20)))
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Take Key"
	prompt.ObjectText = record.definition.KeyName
	prompt.MaxActivationDistance = PICKUP_RANGE
	prompt.RequiresLineOfSight = false
	prompt.Parent = part
	prompt.Triggered:Connect(function(player)
		RescueService:TryPickupKey(player, record.definition.Id)
	end)
	record.keyModel = key
	local gatePrompt = record.gate:FindFirstChildWhichIsA("ProximityPrompt")
	if gatePrompt then
		gatePrompt.Enabled = true
	end
end

--[[
    @summary  Remove one guard from its cave and resolve pack completion.
    @param    model  Model
]]
local function onNpcDied(model: Model)
	local caveId = model:GetAttribute("GuardCaveId")
	local record = typeof(caveId) == "string" and caveRecords[caveId] or nil
	if not record or not record.guards[model] then
		return
	end
	record.guards[model] = nil
	for guard in pairs(record.guards) do
		if guard.Parent then
			return
		end
		record.guards[guard] = nil
	end
	spawnKey(record)
end

--[[
    @summary  Clone and pose a child model for display in a ViewportFrame.
    @param    rescueId  string
    @returns  Model?
]]
local function createPortraitModel(rescueId: string): Model?
	local definition = RescueConfig[rescueId]
	if not definition then
		warn("[RescueService] createPortraitModel: no definition for", rescueId)
		return nil
	end
	local npcAssets = ServerStorage.Assets:FindFirstChild("Assets Npcs")
	if not npcAssets then
		warn("[RescueService] createPortraitModel: 'Assets Npcs' folder not found in ServerStorage.Assets")
		return nil
	end
	local source = npcAssets:FindFirstChild(definition.RigTemplate)
	if not source then
		warn("[RescueService] createPortraitModel: rig template not found:", definition.RigTemplate)
		return nil
	end
	if not source:IsA("Model") then
		warn("[RescueService] createPortraitModel: rig template is not a Model:", definition.RigTemplate, source.ClassName)
		return nil
	end
	local model = source:Clone()
	model.Name = "Portrait_" .. rescueId
	-- Remove scripts so the portrait doesn't run AI
	for _, desc in ipairs(model:GetDescendants()) do
		if desc:IsA("BaseScript") or desc:IsA("ModuleScript") then
			desc:Destroy()
		end
	end
	-- Apply variant styling
	styleChildVariant(model, definition)
	return model
end

--[[
    @summary  Set up a ViewportFrame to display a child model portrait.
    @param    viewport  ViewportFrame
    @param    model     Model
]]
local function setupViewportPortrait(viewport: ViewportFrame, model: Model)
	viewport:ClearAllChildren()
	-- Parent model directly to ViewportFrame (more reliable than WorldModel for static portraits)
	model.Parent = viewport

	-- Reset model to origin
	model:PivotTo(CFrame.new(0, 0, 0))

	-- Compute bounding box to frame the camera properly
	local size = model:GetExtentsSize()
	local radius = math.max(size.X, size.Y, size.Z) / 2
	if radius <= 0 then
		radius = 3
	end
	-- Position camera in front of the model, looking at its center
	local distance = radius * 2.8
	local camera = Instance.new("Camera")
	camera.CFrame = CFrame.new(Vector3.new(0, size.Y * 0.3, distance), Vector3.new(0, 0, 0))
	camera.Parent = viewport
	viewport.CurrentCamera = camera
	viewport.BackgroundTransparency = 1
end

--[[
    @summary  Create one poster slot inside the SurfaceGui.
    @param    parent    Instance  -- parent Frame (the poster row)
    @param    index     number    -- 1-based slot index
    @param    rescueId  string
    @returns  table  -- slot references
]]
local function createPosterSlot(parent: Instance, index: number, rescueId: string)
	local definition = RescueConfig[rescueId]
	local displayName = definition and definition.DisplayName or rescueId
	local slotWidth = 230
	local slotHeight = 420
	local gap = 20
	local startX = 16 + (index - 1) * (slotWidth + gap)

	-- White paper background
	local paper = Instance.new("Frame")
	paper.Name = rescueId .. "Poster"
	paper.Position = UDim2.fromOffset(startX, 0)
	paper.Size = UDim2.fromOffset(slotWidth, slotHeight)
	paper.BackgroundColor3 = Color3.fromRGB(232, 224, 198)
	paper.BorderSizePixel = 0
	paper.Parent = parent
	local paperCorner = Instance.new("UICorner")
	paperCorner.CornerRadius = UDim.new(0, 4)
	paperCorner.Parent = paper
	local paperStroke = Instance.new("UIStroke")
	paperStroke.Color = Color3.fromRGB(80, 60, 40)
	paperStroke.Thickness = 3
	paperStroke.Parent = paper

	-- "MISSING" red label at top
	local missingLabel = Instance.new("TextLabel")
	missingLabel.Name = "MissingLabel"
	missingLabel.Position = UDim2.fromOffset(0, 6)
	missingLabel.Size = UDim2.new(1, 0, 0, 28)
	missingLabel.BackgroundTransparency = 1
	missingLabel.Font = Enum.Font.PermanentMarker
	missingLabel.Text = "MISSING"
	missingLabel.TextColor3 = Color3.fromRGB(180, 30, 30)
	missingLabel.TextSize = 22
	missingLabel.Parent = paper

	-- ViewportFrame for the child portrait
	local viewport = Instance.new("ViewportFrame")
	viewport.Name = "Portrait"
	viewport.Position = UDim2.fromOffset(10, 38)
	viewport.Size = UDim2.new(1, -20, 1, -80)
	viewport.BackgroundTransparency = 1
	viewport.Parent = paper

	-- Black overlay (shown when locked)
	local blackOverlay = Instance.new("Frame")
	blackOverlay.Name = "BlackOverlay"
	blackOverlay.Position = UDim2.fromOffset(10, 38)
	blackOverlay.Size = UDim2.new(1, -20, 1, -80)
	blackOverlay.BackgroundColor3 = Color3.fromRGB(10, 10, 10)
	blackOverlay.BackgroundTransparency = 0.05
	blackOverlay.Visible = true
	blackOverlay.Parent = paper
	local overlayCorner = Instance.new("UICorner")
	overlayCorner.CornerRadius = UDim.new(0, 4)
	overlayCorner.Parent = blackOverlay
	-- Scribble effect: a lock icon on the black overlay
	local questionLabel = Instance.new("TextLabel")
	questionLabel.Size = UDim2.fromScale(1, 1)
	questionLabel.BackgroundTransparency = 1
	questionLabel.Font = Enum.Font.GothamBlack
	questionLabel.Text = "🔒"
	questionLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
	questionLabel.TextSize = 60
	questionLabel.Parent = blackOverlay

	-- Name label at bottom
	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "NameLabel"
	nameLabel.Position = UDim2.fromOffset(0, slotHeight - 36)
	nameLabel.Size = UDim2.new(1, 0, 0, 30)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.Text = displayName
	nameLabel.TextColor3 = Color3.fromRGB(40, 30, 20)
	nameLabel.TextSize = 18
	nameLabel.Parent = paper

	-- FOUND stamp (shown when rescued)
	local foundStamp = Instance.new("TextLabel")
	foundStamp.Name = "FoundStamp"
	foundStamp.Position = UDim2.fromOffset(20, 80)
	foundStamp.Size = UDim2.fromOffset(190, 60)
	foundStamp.BackgroundTransparency = 1
	foundStamp.Font = Enum.Font.PermanentMarker
	foundStamp.Text = "FOUND!"
	foundStamp.TextColor3 = Color3.fromRGB(30, 160, 50)
	foundStamp.TextSize = 42
	foundStamp.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	foundStamp.TextStrokeTransparency = 0.3
	foundStamp.Rotation = -15
	foundStamp.Visible = false
	foundStamp.ZIndex = 10
	foundStamp.Parent = paper

	return {
		frame = paper,
		viewport = viewport,
		blackOverlay = blackOverlay,
		foundStamp = foundStamp,
		nameLabel = nameLabel,
		model = nil,
	}
end

--[[
    @summary  Create the 3D camp poster board with SurfaceGui and
              four poster slots showing child portraits.
]]
local function createPosterBoard()
	posterSlots = {}
	if exclamationPart then
		exclamationPart = nil
	end

	local campfireCFrame = worldService:GetCampfireCFrame()
	if not campfireCFrame then
		return
	end

	-- Use a persistent Workspace folder so the board survives runs and
	-- remains visible/editable in Studio.
	local boardsFolder = workspace:FindFirstChild("Boards")
	if not boardsFolder then
		boardsFolder = Instance.new("Folder")
		boardsFolder.Name = "Boards"
		boardsFolder.Parent = workspace
	end

	-- Reuse an existing board model if the user placed one in Studio.
	local boardModel = boardsFolder:FindFirstChild("MissingChildrenBoard") :: Model?
	local boardCFrame
	if boardModel then
		local existingBoard = boardModel:FindFirstChild("BoardPanel") :: BasePart?
		if existingBoard then
			boardCFrame = existingBoard.CFrame
		end
	end

	-- If no existing board, create one at the default campfire-relative position.
	if not boardModel then
		boardModel = Instance.new("Model")
		boardModel.Name = "MissingChildrenBoard"
		boardCFrame = campfireCFrame * CFrame.new(28, 7, 0) * CFrame.Angles(0, math.rad(90), 0)

		-- Backing board
		local board = Instance.new("Part")
		board.Name = "BoardPanel"
		board.Size = Vector3.new(18, 9, 0.6)
		board.Anchored = true
		board.Material = Enum.Material.WoodPlanks
		board.Color = Color3.fromRGB(95, 65, 38)
		board.CFrame = boardCFrame
		board.Parent = boardModel
		boardModel.PrimaryPart = board

		-- Left post (taller)
		local leftPost = Instance.new("Part")
		leftPost.Name = "LeftPost"
		leftPost.Size = Vector3.new(0.8, 16, 0.8)
		leftPost.Anchored = true
		leftPost.Material = Enum.Material.WoodPlanks
		leftPost.Color = Color3.fromRGB(75, 50, 28)
		leftPost.CFrame = boardCFrame * CFrame.new(-9, -3.5, 0)
		leftPost.Parent = boardModel

		-- Right post (taller)
		local rightPost = Instance.new("Part")
		rightPost.Name = "RightPost"
		rightPost.Size = Vector3.new(0.8, 16, 0.8)
		rightPost.Anchored = true
		rightPost.Material = Enum.Material.WoodPlanks
		rightPost.Color = Color3.fromRGB(75, 50, 28)
		rightPost.CFrame = boardCFrame * CFrame.new(9, -3.5, 0)
		rightPost.Parent = boardModel

		-- Top crossbar
		local topBar = Instance.new("Part")
		topBar.Name = "TopBar"
		topBar.Size = Vector3.new(19, 1, 0.9)
		topBar.Anchored = true
		topBar.Material = Enum.Material.WoodPlanks
		topBar.Color = Color3.fromRGB(75, 50, 28)
		topBar.CFrame = boardCFrame * CFrame.new(0, 5.2, 0)
		topBar.Parent = boardModel

		boardModel.Parent = boardsFolder
	else
		-- Clear any dynamic children from a previous run (SurfaceGui, prompts, etc.)
		for _, child in ipairs(boardModel:GetChildren()) do
			if child.Name == "BoardGui" or child.Name == "ExclamationIcon" or child:IsA("ProximityPrompt") then
				child:Destroy()
			end
		end
	end

	local board = boardModel:FindFirstChild("BoardPanel") :: BasePart?
	if not board then
		return
	end
	posterBoard = board

	-- Exclamation mark icon above the board (BillboardGui for reliability)
	local exclaim = Instance.new("Part")
	exclaim.Name = "ExclamationIcon"
	exclaim.Shape = Enum.PartType.Ball
	exclaim.Size = Vector3.new(1.2, 1.2, 1.2)
	exclaim.Anchored = true
	exclaim.CanCollide = false
	exclaim.Material = Enum.Material.SmoothPlastic
	exclaim.Color = Color3.fromRGB(220, 50, 40)
	exclaim.CFrame = boardCFrame * CFrame.new(0, 6.5, 0.4)
	exclaim.Parent = boardModel
	exclamationPart = exclaim
	local exclaimGui = Instance.new("BillboardGui")
	exclaimGui.Size = UDim2.fromOffset(80, 80)
	exclaimGui.StudsOffset = Vector3.new(0, 0, 0)
	exclaimGui.AlwaysOnTop = true
	exclaimGui.Parent = exclaim
	local exclaimLabel = Instance.new("TextLabel")
	exclaimLabel.Size = UDim2.fromScale(1, 1)
	exclaimLabel.BackgroundTransparency = 1
	exclaimLabel.Font = Enum.Font.GothamBlack
	exclaimLabel.Text = "!"
	exclaimLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	exclaimLabel.TextSize = 60
	exclaimLabel.Parent = exclaimGui
	-- Initially hidden until a cave is available
	exclaim.Transparency = 1

	-- SurfaceGui on the board front face
	local surfaceGui = Instance.new("SurfaceGui")
	surfaceGui.Name = "BoardGui"
	surfaceGui.Face = Enum.NormalId.Front
	surfaceGui.CanvasSize = Vector2.new(1024, 512)
	surfaceGui.Parent = board

	-- Title label (parented directly to SurfaceGui)
	local titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "Title"
	titleLabel.Position = UDim2.fromOffset(0, 8)
	titleLabel.Size = UDim2.new(1, 0, 0, 52)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Font = Enum.Font.PermanentMarker
	titleLabel.Text = "MISSING KID LOCATIONS"
	titleLabel.TextColor3 = Color3.fromRGB(240, 230, 200)
	titleLabel.TextStrokeColor3 = Color3.fromRGB(20, 10, 5)
	titleLabel.TextStrokeTransparency = 0.2
	titleLabel.TextSize = 38
	titleLabel.Parent = surfaceGui

	-- Poster row container (parented directly to SurfaceGui)
	local posterRow = Instance.new("Frame")
	posterRow.Name = "PosterRow"
	posterRow.Position = UDim2.fromOffset(0, 68)
	posterRow.Size = UDim2.new(1, 0, 1, -76)
	posterRow.BackgroundTransparency = 1
	posterRow.Parent = surfaceGui

	-- Create 4 poster slots
	for index, rescueId in ipairs(CAVE_ORDER) do
		local slot = createPosterSlot(posterRow, index, rescueId)
		posterSlots[rescueId] = slot
		-- Immediately create and show the portrait model
		local model = createPortraitModel(rescueId)
		if model then
			slot.model = model
			setupViewportPortrait(slot.viewport, model)
			slot.blackOverlay.Visible = false
		else
			warn("[RescueService] Failed to create portrait for", rescueId)
		end
	end

	-- ProximityPrompt
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "View Locations"
	prompt.ObjectText = "Missing Kid Locations"
	prompt.MaxActivationDistance = PICKUP_RANGE
	prompt.Parent = board
	prompt.Triggered:Connect(function(player)
		RescueService:SelectBoardTarget(player)
		-- Also send the board snapshot to open the map UI
		local snapshot = RescueService.Client:GetSnapshot(player)
		RescueService.Client.BoardOpened:Fire(player, snapshot)
	end)
end

--[[
    @summary  Update all poster slots to reflect current cave states.
              Called after any rescue state change.
]]
local function updatePosterStates()
	local anyAvailable = false
	for rescueId, slot in pairs(posterSlots) do
		local record = caveRecords[rescueId]
		if not record then
			continue
		end
		local state = record.state
		if state ~= "Locked" then
			anyAvailable = true
		end
		-- Show a semi-transparent lock overlay when locked, but keep portrait visible
		if state == "Locked" then
			slot.blackOverlay.BackgroundTransparency = 0.4
			slot.blackOverlay.Visible = true
		else
			slot.blackOverlay.Visible = false
		end
		-- Show FOUND stamp when rescued
		if state == "Rescued" then
			slot.foundStamp.Visible = true
		else
			slot.foundStamp.Visible = false
		end
	end
	-- Show/hide exclamation mark
	if exclamationPart then
		exclamationPart.Transparency = if anyAvailable then 0 else 1
	end
	-- Broadcast state update to clients for their map UI
	local states = {}
	for rescueId, record in pairs(caveRecords) do
		states[rescueId] = {
			state = record.state,
			displayName = record.definition.DisplayName,
			position = record.center,
		}
	end
	broadcast(RescueService.Client.PosterStateUpdated, { states = states, rescuedCount = rescuedCount })
end

--[[
    @summary  Build a colored tent and settle a rescued child at camp.
    @param    record  table
]]
local function settleAtCamp(record)
	rescueOrder += 1
	local color = TENT_COLORS[math.clamp(rescueOrder, 1, #TENT_COLORS)]
	local campfireCFrame = worldService:GetCampfireCFrame()
	local angle = rescueOrder / 4 * math.pi * 2
	local campPosition = groundPosition(campfireCFrame.Position + Vector3.new(math.cos(angle) * 24, 0, math.sin(angle) * 24))

	local tent = Instance.new("Model")
	tent.Name = record.definition.Id .. "Tent"
	local floor = Instance.new("Part")
	floor.Name = "TentFloor"
	floor.Size = Vector3.new(8, 0.5, 6)
	floor.Position = campPosition + Vector3.new(0, 0.25, 0)
	floor.Anchored = true
	floor.Material = Enum.Material.Fabric
	floor.Color = color
	floor.Parent = tent
	tent.PrimaryPart = floor
	local roof = Instance.new("WedgePart")
	roof.Name = "TentRoof"
	roof.Size = Vector3.new(8, 4, 6)
	roof.Position = campPosition + Vector3.new(0, 2.25, 0)
	roof.Anchored = true
	roof.CanCollide = false
	roof.Material = Enum.Material.Fabric
	roof.Color = color
	roof.Parent = tent
	tent:SetAttribute("ChildId", record.definition.Id)
	tent:SetAttribute("RescueOrder", rescueOrder)
	tent.Parent = tentsFolder

	local child = record.child
	if child then
		local rootPart = child:FindFirstChild("HumanoidRootPart")
		if rootPart and rootPart:IsA("BasePart") then
			rootPart.Anchored = true
		end
		child:PivotTo(CFrame.new(campPosition + Vector3.new(0, 3, -5)))
		child:SetAttribute("RescueState", "Rescued")
	end
end

--[[
    @summary  Complete one carried child's rescue in the lit safe zone.
    @param    player  Player
    @param    record  table
]]
local function completeRescue(player: Player, record)
	if record.state ~= "Carried" or record.carrier ~= player then
		return
	end
	if record.carryWeld then
		record.carryWeld:Destroy()
		record.carryWeld = nil
	end
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if humanoid and record.originalWalkSpeed then
		humanoid.WalkSpeed = record.originalWalkSpeed
	end
	if player.Character then
		player.Character:SetAttribute("CarryingChild", nil)
	end
	carriedBy[player] = nil
	record.carrier = nil
	record.state = "Rescued"
	rescuedCount += 1
	settleAtCamp(record)
	runStateService:AddMultiplierSource("Child:" .. record.definition.Id, 1)
	runStateService:IncrementStat(player, "ChildrenRescued", 1)
	broadcast(RescueService.Client.ChildCarryChanged, { userId = player.UserId, childId = record.definition.Id, carrying = false })
	broadcast(RescueService.Client.RescueChanged, {
		childId = record.definition.Id,
		displayName = record.definition.DisplayName,
		rescuedCount = rescuedCount,
		rescueOrder = rescueOrder,
		multiplier = runStateService:GetMultiplier(),
	})
	updatePosterStates()
end

--[[
    @summary  Check carried children for arrival inside the lit safe zone.
    @param    dt  number
]]
local function onHeartbeat(dt: number)
	rescueCheckTimer += dt
	if rescueCheckTimer < RESCUE_CHECK_INTERVAL then
		return
	end
	rescueCheckTimer = 0
	if not runStateService:IsActive() or not campfireService:IsLit() then
		return
	end
	for player, childId in pairs(carriedBy) do
		local rootPart = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		local record = caveRecords[childId]
		if rootPart and rootPart:IsA("BasePart") and record and campfireService:IsInSafeZone(rootPart.Position) then
			completeRescue(player, record)
		end
	end
end

-- | Public | --

--[[
    @summary  Return how many children have reached camp this run.
    @returns  number
]]
function RescueService:GetRescuedCount(): number
	return rescuedCount
end

--[[
    @summary  Return read-only cave positions for the map board.
    @returns  { { id: string, displayName: string, position: Vector3, state: string } }
]]
function RescueService:GetCavePositions()
	local result = {}
	for rescueId, record in pairs(caveRecords) do
		table.insert(result, {
			id = rescueId,
			displayName = record.definition.DisplayName,
			position = record.center,
			state = record.state,
		})
	end
	return result
end

--[[
    @summary  Give a matching cleared-cave key to a nearby player.
    @param    player   Player
    @param    caveId   string
    @returns  boolean
]]
function RescueService:TryPickupKey(player: Player, caveId: string): boolean
	local record = caveRecords[caveId]
	if not record or record.state ~= "KeyDropped" or not record.keyModel then
		return false
	end
	if not playerLifeService:IsAlive(player) or not runStateService:IsMember(player) then
		return false
	end
	local rootPart = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not rootPart or not rootPart:IsA("BasePart") or (rootPart.Position - record.keyModel:GetPivot().Position).Magnitude > PICKUP_RANGE then
		return false
	end
	keyOwners[player] = keyOwners[player] or {}
	keyOwners[player][caveId] = true
	record.keyModel:Destroy()
	record.keyModel = nil
	return true
end

--[[
    @summary  Open a cleared cave using its matching carried key.
    @param    player  Player
    @param    caveId  string
    @returns  boolean
]]
function RescueService:TryUnlockGate(player: Player, caveId: string): boolean
	local record = caveRecords[caveId]
	if not record or record.state ~= "KeyDropped" or not keyOwners[player] or not keyOwners[player][caveId] then
		return false
	end
	local rootPart = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not rootPart or not rootPart:IsA("BasePart") or (rootPart.Position - record.gate.Position).Magnitude > PICKUP_RANGE then
		return false
	end
	keyOwners[player][caveId] = nil
	record.state = "Unlocked"
	record.gate:SetAttribute("Locked", false)
	record.gate.CanCollide = false
	record.gate.Transparency = 0.7
	local gatePrompt = record.gate:FindFirstChildWhichIsA("ProximityPrompt")
	if gatePrompt then
		gatePrompt.Enabled = false
	end
	local childPrompt = record.child and record.child:FindFirstChild("RescueChildPrompt", true)
	if childPrompt then
		childPrompt.Enabled = true
	end
	if record.child then
		record.child:SetAttribute("RescueState", "Available")
	end
	return true
end

--[[
    @summary  Attach one available child to an eligible player.
    @param    player  Player
    @param    caveId  string
    @returns  boolean
]]
function RescueService:TryCarryChild(player: Player, caveId: string): boolean
	local record = caveRecords[caveId]
	if not record or record.state ~= "Unlocked" or not record.child or carriedBy[player] then
		return false
	end
	if not playerLifeService:IsAlive(player) or record.carrier then
		return false
	end
	local character = player.Character
	local playerRoot = character and character:FindFirstChild("HumanoidRootPart")
	-- Search recursively for the child's root part
	local childRoot = record.child:FindFirstChild("HumanoidRootPart")
	if not childRoot then
		childRoot = record.child:FindFirstChildWhichIsA("BasePart", true)
	end
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not playerRoot or not childRoot or not playerRoot:IsA("BasePart") or not childRoot:IsA("BasePart") or not humanoid then
		return false
	end
	if (playerRoot.Position - childRoot.Position).Magnitude > PICKUP_RANGE then
		return false
	end

	-- Unequip any held tool so the child can be carried
	local heldTool = character:FindFirstChildOfClass("Tool")
	if heldTool then
		heldTool.Parent = player:FindFirstChild("Backpack") or character
	end

	childRoot.Anchored = false
	record.child:PivotTo(playerRoot.CFrame * CFrame.new(0, 0, 2.4))
	local weld = Instance.new("WeldConstraint")
	weld.Name = "ChildCarryWeld"
	weld.Part0 = playerRoot
	weld.Part1 = childRoot
	weld.Parent = childRoot
	record.carryWeld = weld
	record.carrier = player
	record.originalWalkSpeed = humanoid.WalkSpeed
	record.state = "Carried"
	carriedBy[player] = caveId
	humanoid.WalkSpeed = math.min(humanoid.WalkSpeed, CARRY_WALK_SPEED)
	character:SetAttribute("CarryingChild", caveId)
	record.child:SetAttribute("RescueState", "Carried")
	local prompt = record.child:FindFirstChild("RescueChildPrompt", true)
	if prompt then
		prompt.Enabled = false
	end
	broadcast(RescueService.Client.ChildCarryChanged, { userId = player.UserId, childId = caveId, carrying = true })
	updatePosterStates()
	return true
end

--[[
    @summary  Drop a player's carried child onto nearby ground.
    @param    player  Player
]]
function RescueService:DropCarriedChild(player: Player)
	local caveId = carriedBy[player]
	local record = caveId and caveRecords[caveId] or nil
	if not record or record.carrier ~= player then
		return
	end
	if record.carryWeld then
		record.carryWeld:Destroy()
		record.carryWeld = nil
	end
	local character = player.Character
	local playerRoot = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local childRoot = record.child and record.child:FindFirstChild("HumanoidRootPart")
	if humanoid and record.originalWalkSpeed then
		humanoid.WalkSpeed = record.originalWalkSpeed
	end
	if character then
		character:SetAttribute("CarryingChild", nil)
	end
	if childRoot and childRoot:IsA("BasePart") then
		childRoot.Anchored = true
		local dropPosition = groundPosition((playerRoot and playerRoot.Position or record.center) + Vector3.new(3, 0, 0))
		record.child:PivotTo(CFrame.new(dropPosition + Vector3.new(0, 3, 0)))
	end
	carriedBy[player] = nil
	record.carrier = nil
	record.state = "Unlocked"
	record.child:SetAttribute("RescueState", "Available")
	local prompt = record.child:FindFirstChild("RescueChildPrompt", true)
	if prompt then
		prompt.Enabled = true
	end
	broadcast(RescueService.Client.ChildCarryChanged, { userId = player.UserId, childId = caveId, carrying = false })
	updatePosterStates()
end

--[[
    @summary  Select the nearest available child cave for one player.
    @param    player  Player
]]
function RescueService:SelectBoardTarget(player: Player)
	if not campfireService:IsLit() then
		return
	end
	local rootPart = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not rootPart or not rootPart:IsA("BasePart") or not posterBoard or (rootPart.Position - posterBoard.Position).Magnitude > PICKUP_RANGE then
		return
	end
	local nearestRecord = nil
	local nearestDistance = math.huge
	for _, record in pairs(caveRecords) do
		if record.state ~= "Locked" and record.state ~= "Rescued" then
			local distance = (record.center - rootPart.Position).Magnitude
			if distance < nearestDistance then
				nearestDistance = distance
				nearestRecord = record
			end
		end
	end
	if nearestRecord then
		RescueService.Client.WaypointChanged:Fire(player, {
			childId = nearestRecord.definition.Id,
			displayName = nearestRecord.definition.DisplayName,
			position = nearestRecord.center,
		})
	else
		RescueService.Client.WaypointChanged:Fire(player, { cleared = true })
	end
end

--[[
    @summary  Client request to drop the caller's carried child.
    @param    player  Player  -- injected by Knit
    @returns  boolean
]]
function RescueService.Client:RequestDropChild(player: Player): boolean
	local now = os.clock()
	if dropCooldowns[player] and now - dropCooldowns[player] < DROP_COOLDOWN then
		return false
	end
	dropCooldowns[player] = now
	if not carriedBy[player] then
		return false
	end
	RescueService:DropCarriedChild(player)
	return true
end

--[[
    @summary  Client request to select a child from the camp board.
    @param    player  Player  -- injected by Knit
]]
function RescueService.Client:RequestBoardTarget(player: Player)
	RescueService:SelectBoardTarget(player)
end

--[[
    @summary  Client request to set a waypoint to a specific child cave.
    @param    player    Player  -- injected by Knit
    @param    rescueId  string  -- the child to track
]]
function RescueService.Client:RequestSetWaypoint(player: Player, rescueId: string)
	if typeof(rescueId) ~= "string" then
		return
	end
	local record = caveRecords[rescueId]
	if not record then
		return
	end
	if record.state == "Locked" or record.state == "Rescued" then
		return
	end
	RescueService.Client.WaypointChanged:Fire(player, {
		childId = rescueId,
		displayName = record.definition.DisplayName,
		position = record.center,
	})
end

--[[
    @summary  Return a client-safe rescue snapshot.
    @param    player  Player  -- injected by Knit
    @returns  table
]]
function RescueService.Client:GetSnapshot(player: Player): { [string]: any }
	local records = {}
	for rescueId, record in pairs(caveRecords) do
		records[rescueId] = {
			state = record.state,
			displayName = record.definition.DisplayName,
			position = record.center,
			requiredCampfireLevel = record.definition.RequiredCampfireLevel,
		}
	end
	return { records = records, rescuedCount = rescuedCount, carrying = carriedBy[player] }
end

-- // INITIALIZATION // --

function RescueService:KnitStart()
	runStateService = Knit.GetService("RunStateService")
	worldService = Knit.GetService("WorldService")
	campfireService = Knit.GetService("CampfireService")
	animalAIService = Knit.GetService("AnimalAIService")
	playerLifeService = Knit.GetService("PlayerLifeService")

	runStateService.RunStarted:Connect(function()
		-- Wait one frame so buildings and facilities are placed and reserved first
		task.defer(function()
			buildCaves()
			createPosterBoard()
			unlockForLevel(campfireService:GetLevel())
			updatePosterStates()
			if not heartbeatConnection then
				heartbeatConnection = RunService.Heartbeat:Connect(onHeartbeat)
			end
		end)
	end)
	campfireService.LevelChangedServer:Connect(function(level)
		unlockForLevel(level)
		updatePosterStates()
	end)
	animalAIService.NpcDiedServer:Connect(onNpcDied)
	playerLifeService.PlayerDowned:Connect(function(player)
		RescueService:DropCarriedChild(player)
		for caveId in pairs(keyOwners[player] or {}) do
			local record = caveRecords[caveId]
			if record then
				spawnKey(record)
			end
		end
		keyOwners[player] = nil
	end)
	runStateService.RunCleaned:Connect(function()
		caveRecords = {}
		carriedBy = {}
		keyOwners = {}
		-- Don't destroy the board model — it lives in Workspace.Boards
		-- so the user can reposition it in Studio. Just nil references.
		posterBoard = nil
		posterSlots = {}
		exclamationPart = nil
		cavesFolder = nil
		tentsFolder = nil
		if heartbeatConnection then
			heartbeatConnection:Disconnect()
			heartbeatConnection = nil
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		RescueService:DropCarriedChild(player)
		for caveId in pairs(keyOwners[player] or {}) do
			local record = caveRecords[caveId]
			if record then
				spawnKey(record)
			end
		end
		keyOwners[player] = nil
		dropCooldowns[player] = nil
	end)
end

return RescueService
