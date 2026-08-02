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

-- | Constants | --
local ASSETS_PATH = ServerStorage.Assets["Assets maps items"]
local ITEMS_PATH = ServerStorage.Assets["Assets Items"]
local CAMPFIRE_OFFSET = Vector3.new(0, 3, 0)
local CAMPFIRE_SIZE = Vector3.new(2, 2, 2)

-- // FUNCTIONS // --

--[[
    @summary  Return the lobby map model.
    @returns  Model
]]
function WorldService:GetLobbyMap(): Model
	return lobbyMap
end

--[[
    @summary  Return the base (game) map model.
    @returns  Model
]]
function WorldService:GetBaseMap(): Model
	return baseMap
end

--[[
    @summary  Return the Campfire anchor part.
    @returns  Part
]]
function WorldService:GetCampfire(): Part
	return campfire
end

--[[
    @summary  Return the CFrame of the Campfire anchor.
    @returns  CFrame
]]
function WorldService:GetCampfireCFrame(): CFrame
	return campfire.CFrame
end

--[[
    @summary  Clone a map from ServerStorage into Workspace.
    @param    mapName  string  -- name of the model in ASSETS_PATH
    @returns  Model            -- the cloned map, parented to Workspace
]]
local function cloneMap(mapName: string): Model
	local source = ASSETS_PATH:FindFirstChild(mapName)
	if not source then
		warn(("[WorldService] Map '%s' not found in ServerStorage"):format(mapName))
		return nil
	end
	local clone = source:Clone()
	clone.Parent = workspace
	return clone
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
    @summary  Create a Campfire anchor part at the base-map centre.
    @desc     The part is invisible and anchored; it exists solely as
              a CFrame reference for SpawnService.
    @param    map  Model  -- the cloned base-map
    @returns  Part
]]
local function createCampfire(map: Model): Part
	local pivot = map:GetPivot()
	local part = Instance.new("Part")
	part.Name = "Campfire"
	part.Anchored = true
	part.CanCollide = false
	part.Transparency = 1
	part.Size = CAMPFIRE_SIZE
	part.CFrame = pivot + CAMPFIRE_OFFSET
	part.Parent = map
	return part
end

--[[
    @summary  Clone and place the visual Bonfire model at the campfire anchor.
    @desc     Clones the Bonfire model from Assets Items and positions it
              at the base-map's pivot point so players can see the fire.
    @param    map  Model  -- the cloned base-map
    @returns  Model
]]
local function placeBonfire(map: Model): Model
	local source = ITEMS_PATH:FindFirstChild("Bonfire")
	if not source then
		warn("[WorldService] Bonfire model not found in Assets Items")
		return nil
	end
	local clone = source:Clone()
	clone.Name = "Bonfire"
	clone:PivotTo(map:GetPivot() + CAMPFIRE_OFFSET)
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
	end
end

-- // INITIALIZATION // --

function WorldService:KnitStart()
	lobbyMap = cloneMap("lobby-map")
	baseMap = cloneMap("Base-map")

	if lobbyMap then
		ensurePrimaryPart(lobbyMap)
	end

	if baseMap then
		ensurePrimaryPart(baseMap)
		campfire = createCampfire(baseMap)
		bonfire = placeBonfire(baseMap)
		disableBrokenScripts(baseMap)
	end

	print("[WorldService] Maps loaded")
end

return WorldService
