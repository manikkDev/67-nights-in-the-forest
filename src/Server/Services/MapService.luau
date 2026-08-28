--[[
    @file    MapService.luau
    @author  manik
    @date    2026

    @summary
    Physical map board next to the missing-children board. Collects
    landmark positions (campfire, caves, facilities, buildings) and
    exposes them to clients who have crafted the Map unlock.

    @exports
    - MapService:GetMapData() -> table
    - Knit Remote: GetMapData()
    - Knit Signal: MapOpened (client)
]]

-- // VARIABLES // --

-- | Services | --
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- | Modules | --
local Knit = require(ReplicatedStorage.Packages.Knit)
local WorldProgressionConfig = require(ReplicatedStorage.Shared.WorldProgressionConfig)

-- | Objects | --
local MapService = Knit.CreateService({
	Name = "MapService",
	Client = {
		MapOpened = Knit.CreateSignal(),
	},
})

-- | Configuration | --
local PICKUP_RANGE = 10
local BOARD_OFFSET = -28 -- opposite side from the rescue board (which is at +28)

-- | State Management | --
local runStateService: any = nil
local worldService: any = nil
local rescueService: any = nil
local facilityService: any = nil
local worldProgressionService: any = nil
local campfireService: any = nil
local craftingService: any = nil
local mapBoard: Part? = nil
local mapData: { [string]: any } = {}

--[[
    @summary  Collect all landmark positions from the world.
]]
local function collectMapData()
	local campfireCFrame = worldService and worldService:GetCampfireCFrame()
	if not campfireCFrame then
		return
	end

	local caves = {}
	if rescueService then
		for _, cave in ipairs(rescueService:GetCavePositions()) do
			table.insert(caves, {
				id = cave.id,
				displayName = cave.displayName,
				position = cave.position,
				state = cave.state,
			})
		end
	end

	local facilities = {}
	if facilityService then
		for _, facility in ipairs(facilityService:GetFacilityPositions()) do
			table.insert(facilities, {
				type = facility.type,
				position = facility.position,
			})
		end
	end

	local buildings = {}
	if worldProgressionService then
		for _, building in ipairs(worldProgressionService:GetBuildingPositions()) do
			table.insert(buildings, {
				name = building.name,
				position = building.position,
			})
		end
	end

	mapData = {
		campfirePosition = campfireCFrame.Position,
		caves = caves,
		facilities = facilities,
		buildings = buildings,
		mapRadius = WorldProgressionConfig.MapRadius,
		accessRadius = worldProgressionService and worldProgressionService:GetAccessRadius() or WorldProgressionConfig.GetAccessRadius(1),
	}
end

--[[
    @summary  Create the physical map board near the campfire.
]]
local function createMapBoard()
	mapBoard = nil

	local campfireCFrame = worldService and worldService:GetCampfireCFrame()
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
	local boardModel = boardsFolder:FindFirstChild("MapBoard") :: Model?
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
		boardModel.Name = "MapBoard"
		boardCFrame = campfireCFrame * CFrame.new(BOARD_OFFSET, 7, 0) * CFrame.Angles(0, math.rad(-90), 0)

		-- Backing board
		local board = Instance.new("Part")
		board.Name = "BoardPanel"
		board.Size = Vector3.new(14, 9, 0.6)
		board.Anchored = true
		board.Material = Enum.Material.WoodPlanks
		board.Color = Color3.fromRGB(95, 65, 38)
		board.CFrame = boardCFrame
		board.Parent = boardModel
		boardModel.PrimaryPart = board

		-- Left post
		local leftPost = Instance.new("Part")
		leftPost.Name = "LeftPost"
		leftPost.Size = Vector3.new(0.8, 16, 0.8)
		leftPost.Anchored = true
		leftPost.Material = Enum.Material.WoodPlanks
		leftPost.Color = Color3.fromRGB(75, 50, 28)
		leftPost.CFrame = boardCFrame * CFrame.new(-7, -3.5, 0)
		leftPost.Parent = boardModel

		-- Right post
		local rightPost = Instance.new("Part")
		rightPost.Name = "RightPost"
		rightPost.Size = Vector3.new(0.8, 16, 0.8)
		rightPost.Anchored = true
		rightPost.Material = Enum.Material.WoodPlanks
		rightPost.Color = Color3.fromRGB(75, 50, 28)
		rightPost.CFrame = boardCFrame * CFrame.new(7, -3.5, 0)
		rightPost.Parent = boardModel

		-- Top crossbar
		local topBar = Instance.new("Part")
		topBar.Name = "TopBar"
		topBar.Size = Vector3.new(15, 1, 0.9)
		topBar.Anchored = true
		topBar.Material = Enum.Material.WoodPlanks
		topBar.Color = Color3.fromRGB(75, 50, 28)
		topBar.CFrame = boardCFrame * CFrame.new(0, 5.2, 0)
		topBar.Parent = boardModel

		boardModel.Parent = boardsFolder
	else
		-- Clear any dynamic children from a previous run (SurfaceGui, prompts, etc.)
		for _, child in ipairs(boardModel:GetChildren()) do
			if child.Name == "BoardGui" or child:IsA("ProximityPrompt") then
				child:Destroy()
			end
		end
	end

	local board = boardModel:FindFirstChild("BoardPanel") :: BasePart?
	if not board then
		return
	end
	mapBoard = board

	-- SurfaceGui on the board front face
	local surfaceGui = Instance.new("SurfaceGui")
	surfaceGui.Name = "BoardGui"
	surfaceGui.Face = Enum.NormalId.Front
	surfaceGui.CanvasSize = Vector2.new(1024, 512)
	surfaceGui.Parent = board

	-- Title label
	local titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "Title"
	titleLabel.Position = UDim2.fromOffset(0, 8)
	titleLabel.Size = UDim2.new(1, 0, 0, 52)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Font = Enum.Font.PermanentMarker
	titleLabel.Text = "MAP"
	titleLabel.TextColor3 = Color3.fromRGB(240, 230, 200)
	titleLabel.TextStrokeColor3 = Color3.fromRGB(20, 10, 5)
	titleLabel.TextStrokeTransparency = 0.2
	titleLabel.TextSize = 38
	titleLabel.Parent = surfaceGui

	-- Subtitle / hint
	local subtitleLabel = Instance.new("TextLabel")
	subtitleLabel.Name = "Subtitle"
	subtitleLabel.Position = UDim2.new(0, 0, 1, -40)
	subtitleLabel.Size = UDim2.new(1, 0, 0, 28)
	subtitleLabel.BackgroundTransparency = 1
	subtitleLabel.Font = Enum.Font.Gotham
	subtitleLabel.Text = "Craft the Map to view landmarks"
	subtitleLabel.TextColor3 = Color3.fromRGB(200, 190, 170)
	subtitleLabel.TextStrokeColor3 = Color3.fromRGB(20, 10, 5)
	subtitleLabel.TextStrokeTransparency = 0.4
	subtitleLabel.TextSize = 18
	subtitleLabel.Parent = surfaceGui

	-- ProximityPrompt
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "View Map"
	prompt.ObjectText = "Map Board"
	prompt.MaxActivationDistance = PICKUP_RANGE
	prompt.Parent = board
	prompt.Triggered:Connect(function(player)
		if not craftingService or not craftingService:HasUnlock("Map") then
			-- Show a hint via the signal with a "locked" payload
			MapService.Client.MapOpened:Fire(player, { locked = true })
			return
		end
		collectMapData()
		MapService.Client.MapOpened:Fire(player, { locked = false })
	end)
end

-- | Public | --

--[[
    @summary  Return the current map data snapshot.
    @returns  table
]]
function MapService:GetMapData()
	return mapData
end

-- | Client | --

--[[
    @summary  Client-facing remote returning the full map dataset.
              Only returns data if the player has the Map unlock.
    @param    player  Player
    @returns  table?
]]
function MapService.Client:GetMapData(player: Player)
	if not craftingService or not craftingService:HasUnlock("Map") then
		return nil
	end
	return mapData
end

-- // INITIALIZATION // --

function MapService:KnitStart()
	runStateService = Knit.GetService("RunStateService")
	worldService = Knit.GetService("WorldService")
	rescueService = Knit.GetService("RescueService")
	facilityService = Knit.GetService("FacilityService")
	worldProgressionService = Knit.GetService("WorldProgressionService")
	campfireService = Knit.GetService("CampfireService")
	craftingService = Knit.GetService("CraftingService")

	runStateService.RunStarted:Connect(function()
		-- Wait for caves, facilities, and buildings to be placed first
		task.defer(function()
			task.wait(1)
			collectMapData()
			createMapBoard()
		end)
	end)

	runStateService.RunCleaned:Connect(function()
		-- Don't destroy the board model — it lives in Workspace.Boards
		-- so the user can reposition it in Studio. Just nil references.
		mapBoard = nil
		mapData = {}
	end)

	-- Re-collect data when campfire level changes (access radius grows)
	if campfireService then
		campfireService.LevelChangedServer:Connect(function(_level)
			collectMapData()
		end)
	end
end

return MapService
