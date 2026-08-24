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

-- | Objects | --
local RescueService = Knit.CreateService({
	Name = "RescueService",
	Client = {
		RescueChanged = Knit.CreateSignal(),
		WaypointChanged = Knit.CreateSignal(),
		ChildCarryChanged = Knit.CreateSignal(),
		CaveUnlocked = Knit.CreateSignal(),
	},
})

-- | Configuration | --
local CAVE_OFFSETS = {
	Dino = Vector3.new(180, 0, 40),
	Kraken = Vector3.new(-220, 0, -35),
	Squid = Vector3.new(55, 0, 270),
	Koala = Vector3.new(-70, 0, -320),
}
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
    @summary  Return ground beneath a desired cave or tent position.
    @param    position  Vector3
    @returns  Vector3
]]
local function groundPosition(position: Vector3): Vector3
	local baseMap = worldService and worldService:GetBaseMap()
	if not baseMap then
		return position
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { baseMap }
	local result = workspace:Raycast(position + Vector3.new(0, 120, 0), Vector3.new(0, -240, 0), params)
	return if result then result.Position else position
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
local function createChild(definition, center: Vector3): Model?
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
	child:PivotTo(CFrame.new(center + Vector3.new(0, 3, -7)))
	local rootPart = child:FindFirstChild("HumanoidRootPart")
	if rootPart and rootPart:IsA("BasePart") then
		rootPart.Anchored = true
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "RescueChildPrompt"
		prompt.ActionText = "Carry Child"
		prompt.ObjectText = definition.DisplayName
		prompt.MaxActivationDistance = PICKUP_RANGE
		prompt.Enabled = false
		prompt.Parent = rootPart
		prompt.Triggered:Connect(function(player)
			RescueService:TryCarryChild(player, definition.Id)
		end)
	end
	return child
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
	if not campfireCFrame then
		return
	end
	for rescueId, definition in pairs(RescueConfig) do
		local center = groundPosition(campfireCFrame.Position + CAVE_OFFSETS[rescueId])
		local cave, gate = createCaveModel(definition, center)
		cave.Parent = cavesFolder
		local child = createChild(definition, center)
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
	key:PivotTo(CFrame.new(record.center + Vector3.new(0, 2, 8)))
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Take Key"
	prompt.ObjectText = record.definition.KeyName
	prompt.MaxActivationDistance = PICKUP_RANGE
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
    @summary  Create the camp poster board and interaction prompt.
]]
local function createPosterBoard()
	if posterBoard then
		posterBoard:Destroy()
	end
	local campfireCFrame = worldService:GetCampfireCFrame()
	if not campfireCFrame then
		return
	end
	local board = Instance.new("Part")
	board.Name = "MissingChildrenBoard"
	board.Size = Vector3.new(10, 7, 0.8)
	board.Anchored = true
	board.Material = Enum.Material.WoodPlanks
	board.Color = Color3.fromRGB(100, 67, 42)
	board.CFrame = campfireCFrame * CFrame.new(-13, 4, 0) * CFrame.Angles(0, math.rad(90), 0)
	board.Parent = runStateService:GetRuntimeFolder()
	posterBoard = board
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Track Child"
	prompt.ObjectText = "Missing Children"
	prompt.MaxActivationDistance = PICKUP_RANGE
	prompt.Parent = board
	prompt.Triggered:Connect(function(player)
		RescueService:SelectBoardTarget(player)
	end)
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
	local childRoot = record.child:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not playerRoot or not childRoot or not playerRoot:IsA("BasePart") or not childRoot:IsA("BasePart") or not humanoid then
		return false
	end
	if character:FindFirstChildOfClass("Tool") or (playerRoot.Position - childRoot.Position).Magnitude > PICKUP_RANGE then
		return false
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
		buildCaves()
		createPosterBoard()
		unlockForLevel(campfireService:GetLevel())
		if not heartbeatConnection then
			heartbeatConnection = RunService.Heartbeat:Connect(onHeartbeat)
		end
	end)
	campfireService.LevelChangedServer:Connect(function(level)
		unlockForLevel(level)
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
		posterBoard = nil
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
