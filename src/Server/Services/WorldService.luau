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
local forestReady: boolean = false

-- | Constants | --
local ITEMS_PATH = ServerStorage.Assets["Assets Items"]
local CAMPFIRE_SIZE = Vector3.new(6, 3, 6)
local GROUND_RAY_HEIGHT = 500
local BONFIRE_SCALE = 2

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
	lobbyMap = findMap("lobby-map")
	baseMap = findMap("Base-map")

	if lobbyMap then
		ensurePrimaryPart(lobbyMap)
		disableBrokenScripts(lobbyMap)
	end

	if baseMap then
		ensurePrimaryPart(baseMap)
		-- Map is pre-populated in edit mode (structures, trees, ground all
		-- permanently placed). Only create campfire/bonfire at runtime:
		local ground = findGroundCFrame(baseMap)
		campfire = createCampfire(baseMap, ground)
		bonfire = placeBonfire(baseMap, ground)
		forestReady = true
		disableBrokenScripts(baseMap)
		print("[WorldService] Maps loaded")
	end
end

return WorldService
