--[[
    @file    WorldService.luau
    @author  manik
    @date    2025

    @summary
    Manages pre-placed game maps and the campfire anchor.

    @description
    Finds the lobby-map and base-map pre-placed in Workspace at server
    start.  Places the visual Bonfire model at the centre of the base-map
    and creates an invisible Campfire anchor part for SpawnService to
    reference.

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
local ServerRole = require(ReplicatedStorage.Shared.ServerRole)
local Constants = require(ReplicatedStorage.Shared.Constants)
local WorldProgressionConfig = require(ReplicatedStorage.Shared.WorldProgressionConfig)

-- | Objects | --
local WorldService = Knit.CreateService({
	Name = "WorldService",
	Client = {},
})

-- | Configuration | --
local ITEMS_PATH = ServerStorage.Assets[Constants.ITEMS_PATH]
local CAMPFIRE_SIZE = Vector3.new(6, 3, 6)
local GROUND_RAY_HEIGHT = 500
local BONFIRE_SCALE = 2

-- | State Management | --
local lobbyMap: Model? = nil
local baseMap: Model? = nil
local campfire: Part? = nil
local bonfire: Model? = nil
local forestReady: boolean = false
local groundPart: BasePart? = nil
local groundY: number? = nil

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
    @summary  Return whether forest generation has completed.
    @returns  boolean
]]
function WorldService:IsForestReady(): boolean
	return forestReady
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
    @summary  Return the top-surface Y of the ground baseplate.
    @desc     Finds the large ground part (named "Земля") in the base
              map and returns its top surface Y coordinate.  This is
              used by RescueService and FacilityService to place
              structures at ground level without raycasting into trees
              or buildings.
    @returns  number?
]]
function WorldService:GetGroundY(): number?
	local ground = self:GetGroundPart()
	if ground and not groundY then
		groundY = ground.Position.Y + ground.Size.Y * 0.5
	end
	return groundY
end

function WorldService:GetGroundPart(): BasePart?
	if groundPart and groundPart.Parent then
		return groundPart
	end
	if not baseMap then
		return nil
	end
	local candidate = baseMap:FindFirstChild("Земля", true)
	if candidate and candidate:IsA("BasePart") then
		groundPart = candidate
		return groundPart
	end
	return nil
end

function WorldService:GetGroundBounds(): { minX: number, maxX: number, minZ: number, maxZ: number }?
	local ground = self:GetGroundPart()
	if not ground then
		return nil
	end
	local radius = WorldProgressionConfig.MapRadius
	return {
		minX = ground.Position.X - radius,
		maxX = ground.Position.X + radius,
		minZ = ground.Position.Z - radius,
		maxZ = ground.Position.Z + radius,
	}
end

--[[
    @summary  Find a pre-placed map in Workspace.
    @desc     Maps are pre-placed in Workspace at edit time so they are
              visible in Studio and don't need to be cloned at runtime.
              Roblox reverts Workspace to its edit-time state when play
              stops, so the clean map is always restored.
    @param    mapName  string  -- name of the model in Workspace
    @returns  Model?           -- the map model found in Workspace
]]
local function findMap(mapName: string): Model?
	local map = workspace:FindFirstChild(mapName)
	if not map then
		warn(("[WorldService] Map '%s' not found in Workspace"):format(mapName))
		return nil
	end
	return map
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

local function ensureExpandedGround(map: Model, ground: BasePart)
	if map:FindFirstChild("ExpandedGround") then
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = "ExpandedGround"
	folder:SetAttribute("ExpansionGenerated", true)
	folder.Parent = map
	local targetSize = WorldProgressionConfig.MapRadius * 2
	local centerSize = math.min(ground.Size.X, 1536)
	local sideWidth = (targetSize - centerSize) * 0.5
	local sideX = centerSize * 0.5 + sideWidth * 0.5
	local function createTile(name: string, size: Vector3, offset: Vector3)
		local tile = ground:Clone()
		tile.Name = name
		tile.Size = size
		tile.Position = ground.Position + offset
		tile:SetAttribute("ExpansionGenerated", true)
		tile.Parent = folder
	end
	createTile("WestNorth", Vector3.new(sideWidth, ground.Size.Y, targetSize * 0.5), Vector3.new(-sideX, 0, -targetSize * 0.25))
	createTile("WestSouth", Vector3.new(sideWidth, ground.Size.Y, targetSize * 0.5), Vector3.new(-sideX, 0, targetSize * 0.25))
	createTile("EastNorth", Vector3.new(sideWidth, ground.Size.Y, targetSize * 0.5), Vector3.new(sideX, 0, -targetSize * 0.25))
	createTile("EastSouth", Vector3.new(sideWidth, ground.Size.Y, targetSize * 0.5), Vector3.new(sideX, 0, targetSize * 0.25))
	local stripZ = centerSize * 0.5 + sideWidth * 0.5
	createTile("North", Vector3.new(centerSize, ground.Size.Y, sideWidth), Vector3.new(0, 0, -stripZ))
	createTile("South", Vector3.new(centerSize, ground.Size.Y, sideWidth), Vector3.new(0, 0, stripZ))
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
    @summary  Place the visual Bonfire model at the campfire anchor.
    @desc     If a Bonfire model was pre-placed in the map at edit time,
              reuses it (positioning, lighting, anchoring).  Otherwise
              clones one from Assets Items.  The bonfire's base is
              offset so it sits flush on the ground.
    @param    map     Model   -- the base-map
    @param    ground  CFrame  -- ground-level CFrame from findGroundCFrame
    @returns  Model?
]]
local function placeBonfire(map: Model, ground: CFrame): Model?
	-- Reuse an existing Bonfire if one was pre-placed in the map at edit time
	local existing = map:FindFirstChild("Bonfire")
	if existing and existing:IsA("Model") then
		-- Position it at ground level (in case the map was moved)
		local scaledPivot = existing:GetPivot()
		local minY = math.huge
		for _, desc in ipairs(existing:GetDescendants()) do
			if desc:IsA("BasePart") and desc.Position.Y < minY then
				minY = desc.Position.Y
			end
		end
		local bonfireBaseOffset = scaledPivot.Position.Y - minY
		existing:PivotTo(ground * CFrame.new(0, bonfireBaseOffset, 0))

		-- Add a PointLight for night-time visibility if not already present
		local lightPart = existing:FindFirstChildWhichIsA("BasePart", true)
		if lightPart and not lightPart:FindFirstChild("BonfireLight") then
			local pointLight = Instance.new("PointLight")
			pointLight.Name = "BonfireLight"
			pointLight.Color = Color3.fromRGB(255, 100, 40)
			pointLight.Range = 12
			pointLight.Brightness = 1
			pointLight.Parent = lightPart
		end

		-- Ensure all parts are anchored
		for _, desc in ipairs(existing:GetDescendants()) do
			if desc:IsA("BasePart") then
				desc.Anchored = true
			end
		end

		-- Create a large, nearly-invisible anchor so campfire prompts have a
		-- properly-sized BasePart parent (the tiny Fire part is too small).
		local firePart = existing:FindFirstChild("Fire")
		if firePart and firePart:IsA("BasePart") and not existing:FindFirstChild("PromptAnchor") then
			local promptAnchor = Instance.new("Part")
			promptAnchor.Name = "PromptAnchor"
			promptAnchor.CFrame = firePart.CFrame
			promptAnchor.Size = Vector3.new(2, 2, 2)
			promptAnchor.Transparency = 0.99
			promptAnchor.Color = Color3.fromRGB(100, 100, 100)
			promptAnchor.Material = Enum.Material.SmoothPlastic
			promptAnchor.Anchored = true
			promptAnchor.CanCollide = false
			promptAnchor.CanTouch = false
			promptAnchor.CanQuery = false
			promptAnchor.CastShadow = false
			promptAnchor.Parent = existing
		end

		return existing
	end

	-- No pre-placed Bonfire — clone one from Assets Items
	local source = ITEMS_PATH:FindFirstChild("Bonfire")
	if not source then
		warn("[WorldService] Bonfire model not found in Assets Items")
		return nil
	end
	local clone = source:Clone()
	clone.Name = "Bonfire"

	clone:ScaleTo(BONFIRE_SCALE)

	local scaledPivot = clone:GetPivot()
	local minY = math.huge
	for _, desc in ipairs(clone:GetDescendants()) do
		if desc:IsA("BasePart") and desc.Position.Y < minY then
			minY = desc.Position.Y
		end
	end
	local bonfireBaseOffset = scaledPivot.Position.Y - minY
	clone:PivotTo(ground * CFrame.new(0, bonfireBaseOffset, 0))

	local lightPart = clone:FindFirstChildWhichIsA("BasePart", true)
	if lightPart then
		local pointLight = Instance.new("PointLight")
		pointLight.Name = "BonfireLight"
		pointLight.Color = Color3.fromRGB(255, 100, 40)
		pointLight.Range = 12
		pointLight.Brightness = 1
		pointLight.Parent = lightPart
	end

	for _, desc in ipairs(clone:GetDescendants()) do
		if desc:IsA("BasePart") then
			desc.Anchored = true
		end
	end

	-- Create a large, nearly-invisible anchor so campfire prompts have a
	-- properly-sized BasePart parent (the tiny Fire part is too small).
	local firePart = clone:FindFirstChild("Fire")
	if firePart and firePart:IsA("BasePart") and not clone:FindFirstChild("PromptAnchor") then
		local promptAnchor = Instance.new("Part")
		promptAnchor.Name = "PromptAnchor"
		promptAnchor.CFrame = firePart.CFrame
		promptAnchor.Size = Vector3.new(2, 2, 2)
		promptAnchor.Transparency = 0.99
		promptAnchor.Color = Color3.fromRGB(100, 100, 100)
		promptAnchor.Material = Enum.Material.SmoothPlastic
		promptAnchor.Anchored = true
		promptAnchor.CanCollide = false
		promptAnchor.CanTouch = false
		promptAnchor.CanQuery = false
		promptAnchor.CastShadow = false
		promptAnchor.Parent = clone
	end

	clone.Parent = map
	return clone
end

--[[
    @summary  Disable known broken pre-existing scripts in map models.
    @desc     Some asset models contain Scripts that reference workspace
              paths that don't exist in our setup.  This disables them to
              prevent runtime errors.
    @param    map  Model  -- the map to clean
]]
local function disableBrokenScripts(map: Model)
	for _, descendant in ipairs(map:GetDescendants()) do
		if descendant:IsA("Script") or descendant:IsA("LocalScript") then
			local name = descendant.Name
			if name == "FireSystem" or name == "FridgeRightDoorScript" or name == "FridgeLeftDoorScript" or name == "Script" then
				descendant.Disabled = true
			end
		end
	end
end

-- // CLIENT REMOTES // --

--[[
    @summary  Client-facing remote returning the campfire's world position,
              so clients can compute distance locally instead of polling
              the server every frame.  Returns the invisible Campfire
              anchor, which is the same centre used by the safe-zone
              logic on the server and the player spawn point.
    @returns  Vector3?
]]
function WorldService.Client:GetCampfirePosition(): Vector3?
	if not campfire then
		return nil
	end
	return campfire.Position
end

-- // INITIALIZATION // --

function WorldService:KnitStart()
	lobbyMap = findMap("lobby-map")
	if lobbyMap then
		ensurePrimaryPart(lobbyMap)
		disableBrokenScripts(lobbyMap)
	end

	-- Game-only setup: base map, campfire, bonfire.
	if not ServerRole.IsGameServer() then return end
	baseMap = findMap("Base-map")

	if baseMap then
		ensurePrimaryPart(baseMap)
		local groundPartInstance = baseMap:FindFirstChild("Земля", true)
		if groundPartInstance and groundPartInstance:IsA("BasePart") then
			groundPart = groundPartInstance
			ensureExpandedGround(baseMap, groundPartInstance)
		end
		-- Map is pre-populated in edit mode (structures, trees, ground all
		-- permanently placed). Only create campfire/bonfire at runtime:
		local ground = findGroundCFrame(baseMap)
		campfire = createCampfire(baseMap, ground)
		bonfire = placeBonfire(baseMap, ground)
		forestReady = true
		disableBrokenScripts(baseMap)
	end
end

return WorldService
