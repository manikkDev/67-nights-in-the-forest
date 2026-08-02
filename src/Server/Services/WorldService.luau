--[[
    @file    WorldService.luau
    @author  manik
    @date    2025

    @summary
    Manages instantiation of game maps and the campfire anchor.

    @description
    Clones the lobby-map and base-map from ServerStorage.Assets into
    Workspace at server start.  Creates a Campfire part at the centre
    of the base-map to serve as the spawn anchor for SpawnService.

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

-- | Constants | --
local ASSETS_PATH = ServerStorage.Assets["Assets maps items"]
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

-- // INITIALIZATION // --

lobbyMap = cloneMap("lobby-map")
baseMap = cloneMap("base-map")

if baseMap then
	campfire = createCampfire(baseMap)
end
