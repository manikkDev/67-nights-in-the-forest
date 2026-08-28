--[[
    @file    MapController.luau
    @author  manik
    @date    2026

    @summary
    Full-screen map UI with top-down minimap. Opens when the player
    activates the map board's ProximityPrompt (if they have the Map
    unlock). Shows campfire, caves, facilities, buildings, access
    radius, and the player's real-time position.

    @exports
    - MapController (Knit controller)
]]

-- // VARIABLES // --

-- | Services | --
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

-- | Modules | --
local Knit = require(ReplicatedStorage.Packages.Knit)

-- | Objects | --
local MapController = Knit.CreateController({
	Name = "MapController",
})

-- | Configuration | --
local MAP_PANEL_SIZE = UDim2.fromOffset(620, 620)
local MINIMAP_SIZE = 540 -- pixels, square
local MARKER_SIZE = 14
local PLAYER_MARKER_SIZE = 12

-- Colors
local COLOR = {
	Panel = Color3.fromRGB(85, 58, 34),
	PanelStroke = Color3.fromRGB(50, 32, 18),
	MinimapBg = Color3.fromRGB(30, 35, 28),
	MinimapStroke = Color3.fromRGB(60, 70, 55),
	Text = Color3.fromRGB(240, 230, 200),
	TextDark = Color3.fromRGB(20, 10, 5),
	CloseBg = Color3.fromRGB(180, 50, 40),
	-- Markers
	Campfire = Color3.fromRGB(255, 140, 40),
	Cave = Color3.fromRGB(220, 60, 50),
	CaveLocked = Color3.fromRGB(100, 100, 100),
	Playground = Color3.fromRGB(70, 140, 220),
	Restroom = Color3.fromRGB(80, 200, 100),
	Clinic = Color3.fromRGB(220, 80, 80),
	Building = Color3.fromRGB(160, 110, 60),
	CrashedPlane = Color3.fromRGB(180, 180, 180),
	Player = Color3.fromRGB(255, 255, 255),
	AccessRadius = Color3.fromRGB(100, 200, 120),
	MapBoundary = Color3.fromRGB(120, 120, 140),
	LegendBg = Color3.fromRGB(20, 18, 26),
}

-- | State Management | --
local mapService: any = nil
local gui: ScreenGui? = nil
local minimapFrame: Frame? = nil
local playerMarker: Frame? = nil
local playerDirection: Frame? = nil
local legendFrame: Frame? = nil
local mapOpen = false
local mapData: { [string]: any } = nil
local campfireWorldPos: Vector3? = nil
local mapRadius: number = 1000
local renderConnection: RBXScriptConnection? = nil

-- Marker containers (cleared and rebuilt on each open)
local staticMarkers: { Frame } = {}

-- // FUNCTIONS // --

--[[
    @summary  Convert a world position to minimap UI coordinates.
              Campfire is at the center of the minimap.
              World X → minimap X, World Z → minimap Y (flipped).
    @param    worldPos   Vector3
    @returns  UDim2
]]
local function worldToMap(worldPos: Vector3): UDim2
	if not campfireWorldPos then
		return UDim2.fromScale(0.5, 0.5)
	end
	local dx = worldPos.X - campfireWorldPos.X
	local dz = worldPos.Z - campfireWorldPos.Z
	-- Scale: minimap spans 2*mapRadius across MINIMAP_SIZE pixels
	local scale = MINIMAP_SIZE / (2 * mapRadius)
	local px = dx * scale
	local py = -dz * scale -- flip Z so north is up
	-- Clamp to minimap bounds
	local half = MINIMAP_SIZE * 0.5
	px = math.clamp(px, -half + MARKER_SIZE, half - MARKER_SIZE)
	py = math.clamp(py, -half + MARKER_SIZE, half - MARKER_SIZE)
	return UDim2.new(0.5, px, 0.5, py)
end

--[[
    @summary  Create a single marker on the minimap.
    @param    parent    Instance
    @param    worldPos  Vector3
    @param    color     Color3
    @param    size      number
    @param    label     string?
    @param    shape     string  -- "circle" or "square"
    @returns  Frame
]]
local function createMarker(parent: Instance, worldPos: Vector3, color: Color3, size: number, label: string?, shape: string?)
	local marker = Instance.new("Frame")
	marker.AnchorPoint = Vector2.new(0.5, 0.5)
	marker.Position = worldToMap(worldPos)
	marker.Size = UDim2.fromOffset(size, size)
	marker.BackgroundColor3 = color
	marker.BackgroundTransparency = 0
	marker.BorderSizePixel = 0
	marker.Parent = parent

	local corner = Instance.new("UICorner")
	if shape == "square" then
		corner.CornerRadius = UDim.new(0, 2)
	else
		corner.CornerRadius = UDim.new(1, 0)
	end
	corner.Parent = marker

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(0, 0, 0)
	stroke.Thickness = 1
	stroke.Transparency = 0.3
	stroke.Parent = marker

	if label then
		local textLabel = Instance.new("TextLabel")
		textLabel.AnchorPoint = Vector2.new(0.5, 0)
		textLabel.Position = UDim2.new(0.5, 0, 1, 2)
		textLabel.Size = UDim2.fromOffset(80, 14)
		textLabel.BackgroundTransparency = 1
		textLabel.Font = Enum.Font.Gotham
		textLabel.Text = label
		textLabel.TextColor3 = Color3.fromRGB(220, 220, 220)
		textLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
		textLabel.TextStrokeTransparency = 0.4
		textLabel.TextSize = 11
		textLabel.TextXAlignment = Enum.TextXAlignment.Center
		textLabel.Parent = marker
	end

	return marker
end

--[[
    @summary  Build the access radius and map boundary circles.
]]
local function buildRadiusCircles()
	if not minimapFrame or not mapData then
		return
	end

	-- Access radius circle
	local accessRadius = mapData.accessRadius or 200
	local scale = MINIMAP_SIZE / (2 * mapRadius)
	local accessPx = accessRadius * scale * 2
	local accessCircle = Instance.new("Frame")
	accessCircle.Name = "AccessRadius"
	accessCircle.AnchorPoint = Vector2.new(0.5, 0.5)
	accessCircle.Position = UDim2.fromScale(0.5, 0.5)
	accessCircle.Size = UDim2.fromOffset(accessPx, accessPx)
	accessCircle.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	accessCircle.BackgroundTransparency = 1
	accessCircle.BorderSizePixel = 0
	accessCircle.Parent = minimapFrame
	local accessCorner = Instance.new("UICorner")
	accessCorner.CornerRadius = UDim.new(1, 0)
	accessCorner.Parent = accessCircle
	local accessStroke = Instance.new("UIStroke")
	accessStroke.Color = COLOR.AccessRadius
	accessStroke.Thickness = 2
	accessStroke.Transparency = 0.4
	accessStroke.Parent = accessCircle
	table.insert(staticMarkers, accessCircle)

	-- Map boundary circle
	local boundaryPx = MINIMAP_SIZE - 4
	local boundaryCircle = Instance.new("Frame")
	boundaryCircle.Name = "MapBoundary"
	boundaryCircle.AnchorPoint = Vector2.new(0.5, 0.5)
	boundaryCircle.Position = UDim2.fromScale(0.5, 0.5)
	boundaryCircle.Size = UDim2.fromOffset(boundaryPx, boundaryPx)
	boundaryCircle.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	boundaryCircle.BackgroundTransparency = 1
	boundaryCircle.BorderSizePixel = 0
	boundaryCircle.Parent = minimapFrame
	local boundaryCorner = Instance.new("UICorner")
	boundaryCorner.CornerRadius = UDim.new(1, 0)
	boundaryCorner.Parent = boundaryCircle
	local boundaryStroke = Instance.new("UIStroke")
	boundaryStroke.Color = COLOR.MapBoundary
	boundaryStroke.Thickness = 2
	boundaryStroke.Transparency = 0.6
	boundaryStroke.Parent = boundaryCircle
	table.insert(staticMarkers, boundaryCircle)
end

--[[
    @summary  Build all static markers from mapData.
]]
local function buildMarkers()
	if not minimapFrame or not mapData then
		return
	end

	-- Clear old markers
	for _, marker in ipairs(staticMarkers) do
		marker:Destroy()
	end
	table.clear(staticMarkers)

	-- Campfire at center
	if mapData.campfirePosition then
		createMarker(minimapFrame, mapData.campfirePosition, COLOR.Campfire, 16, "Camp", "circle")
	end

	-- Caves
	for _, cave in ipairs(mapData.caves or {}) do
		local isLocked = cave.state == "Locked"
		local color = if isLocked then COLOR.CaveLocked else COLOR.Cave
		local label = if isLocked then "?" else cave.displayName
		createMarker(minimapFrame, cave.position, color, 14, label, "circle")
	end

	-- Facilities
	for _, facility in ipairs(mapData.facilities or {}) do
		local color = COLOR.Playground
		if facility.type == "Restroom" then
			color = COLOR.Restroom
		elseif facility.type == "Clinic" then
			color = COLOR.Clinic
		end
		createMarker(minimapFrame, facility.position, color, 10, nil, "square")
	end

	-- Buildings
	for _, building in ipairs(mapData.buildings or {}) do
		local color = COLOR.Building
		if building.name == "Crashed Plane" then
			color = COLOR.CrashedPlane
		end
		createMarker(minimapFrame, building.position, color, 12, building.name, "square")
	end

	-- Radius circles
	buildRadiusCircles()
end

--[[
    @summary  Build the legend in the bottom-right corner.
]]
local function buildLegend(parent: Frame)
	local legend = Instance.new("Frame")
	legend.Name = "Legend"
	legend.AnchorPoint = Vector2.new(1, 1)
	legend.Position = UDim2.new(1, -8, 1, -8)
	legend.Size = UDim2.fromOffset(150, 130)
	legend.BackgroundColor3 = COLOR.LegendBg
	legend.BackgroundTransparency = 0.2
	legend.BorderSizePixel = 0
	legend.Parent = parent
	local legendCorner = Instance.new("UICorner")
	legendCorner.CornerRadius = UDim.new(0, 8)
	legendCorner.Parent = legend

	local entries = {
		{ color = COLOR.Campfire, label = "Campfire", shape = "circle" },
		{ color = COLOR.Cave, label = "Cave", shape = "circle" },
		{ color = COLOR.CaveLocked, label = "Locked Cave", shape = "circle" },
		{ color = COLOR.Playground, label = "Playground", shape = "square" },
		{ color = COLOR.Restroom, label = "Restroom", shape = "square" },
		{ color = COLOR.Clinic, label = "Clinic", shape = "square" },
		{ color = COLOR.Building, label = "Building", shape = "square" },
		{ color = COLOR.Player, label = "You", shape = "circle" },
	}

	for i, entry in ipairs(entries) do
		local row = Instance.new("Frame")
		row.Name = "Entry" .. tostring(i)
		row.Position = UDim2.new(0, 8, 0, 8 + (i - 1) * 15)
		row.Size = UDim2.new(1, -16, 0, 14)
		row.BackgroundTransparency = 1
		row.Parent = legend

		local dot = Instance.new("Frame")
		dot.Position = UDim2.fromOffset(0, 2)
		dot.Size = UDim2.fromOffset(10, 10)
		dot.BackgroundColor3 = entry.color
		dot.BorderSizePixel = 0
		dot.Parent = row
		local dotCorner = Instance.new("UICorner")
		dotCorner.CornerRadius = if entry.shape == "circle" then UDim.new(1, 0) else UDim.new(0, 2)
		dotCorner.Parent = dot

		local text = Instance.new("TextLabel")
		text.Position = UDim2.fromOffset(16, 0)
		text.Size = UDim2.new(1, -16, 0, 14)
		text.BackgroundTransparency = 1
		text.Font = Enum.Font.Gotham
		text.Text = entry.label
		text.TextColor3 = Color3.fromRGB(220, 220, 220)
		text.TextSize = 11
		text.TextXAlignment = Enum.TextXAlignment.Left
		text.TextYAlignment = Enum.TextYAlignment.Center
		text.Parent = row
	end

	legendFrame = legend
end

--[[
    @summary  Build the full map GUI once.
]]
local function buildGui()
	if gui then
		return
	end

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "MapGui"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true
	screenGui.Enabled = false
	screenGui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	gui = screenGui

	-- Dark overlay background
	local bg = Instance.new("Frame")
	bg.Name = "Background"
	bg.Size = UDim2.fromScale(1, 1)
	bg.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	bg.BackgroundTransparency = 0.5
	bg.BorderSizePixel = 0
	bg.Parent = screenGui

	-- Main panel (wooden style)
	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = MAP_PANEL_SIZE
	panel.BackgroundColor3 = COLOR.Panel
	panel.BorderSizePixel = 0
	panel.Parent = bg
	local panelCorner = Instance.new("UICorner")
	panelCorner.CornerRadius = UDim.new(0, 12)
	panelCorner.Parent = panel
	local panelStroke = Instance.new("UIStroke")
	panelStroke.Color = COLOR.PanelStroke
	panelStroke.Thickness = 4
	panelStroke.Parent = panel

	-- Title
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Position = UDim2.fromOffset(0, 12)
	title.Size = UDim2.new(1, 0, 0, 40)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.PermanentMarker
	title.Text = "MAP"
	title.TextColor3 = COLOR.Text
	title.TextStrokeColor3 = COLOR.TextDark
	title.TextStrokeTransparency = 0.2
	title.TextSize = 30
	title.Parent = panel

	-- Close button
	local closeBtn = Instance.new("TextButton")
	closeBtn.Name = "CloseButton"
	closeBtn.AnchorPoint = Vector2.new(1, 0)
	closeBtn.Position = UDim2.new(1, -8, 0, 8)
	closeBtn.Size = UDim2.fromOffset(36, 36)
	closeBtn.BackgroundColor3 = COLOR.CloseBg
	closeBtn.Font = Enum.Font.GothamBold
	closeBtn.Text = "X"
	closeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	closeBtn.TextSize = 20
	closeBtn.Parent = panel
	local closeCorner = Instance.new("UICorner")
	closeCorner.CornerRadius = UDim.new(1, 0)
	closeCorner.Parent = closeBtn
	closeBtn.MouseButton1Click:Connect(function()
		screenGui.Enabled = false
		mapOpen = false
	end)

	-- Minimap canvas
	local minimap = Instance.new("Frame")
	minimap.Name = "Minimap"
	minimap.AnchorPoint = Vector2.new(0.5, 0.5)
	minimap.Position = UDim2.fromScale(0.5, 0.55)
	minimap.Size = UDim2.fromOffset(MINIMAP_SIZE, MINIMAP_SIZE)
	minimap.BackgroundColor3 = COLOR.MinimapBg
	minimap.BorderSizePixel = 0
	minimap.ClipsDescendants = true
	minimap.Parent = panel
	local minimapCorner = Instance.new("UICorner")
	minimapCorner.CornerRadius = UDim.new(1, 0)
	minimapCorner.Parent = minimap
	local minimapStroke = Instance.new("UIStroke")
	minimapStroke.Color = COLOR.MinimapStroke
	minimapStroke.Thickness = 3
	minimapStroke.Parent = minimap
	minimapFrame = minimap

	-- Player marker (white dot)
	local pMarker = Instance.new("Frame")
	pMarker.Name = "PlayerMarker"
	pMarker.AnchorPoint = Vector2.new(0.5, 0.5)
	pMarker.Position = UDim2.fromScale(0.5, 0.5)
	pMarker.Size = UDim2.fromOffset(PLAYER_MARKER_SIZE, PLAYER_MARKER_SIZE)
	pMarker.BackgroundColor3 = COLOR.Player
	pMarker.BorderSizePixel = 0
	pMarker.ZIndex = 20
	pMarker.Parent = minimap
	local pMarkerCorner = Instance.new("UICorner")
	pMarkerCorner.CornerRadius = UDim.new(1, 0)
	pMarkerCorner.Parent = pMarker
	local pMarkerStroke = Instance.new("UIStroke")
	pMarkerStroke.Color = Color3.fromRGB(0, 0, 0)
	pMarkerStroke.Thickness = 2
	pMarkerStroke.Parent = pMarker
	playerMarker = pMarker

	-- Player direction indicator (small triangle pointing in look direction)
	local dirArrow = Instance.new("Frame")
	dirArrow.Name = "PlayerDirection"
	dirArrow.AnchorPoint = Vector2.new(0.5, 0.5)
	dirArrow.Position = UDim2.new(0.5, 0, 0.5, -PLAYER_MARKER_SIZE)
	dirArrow.Size = UDim2.fromOffset(6, 6)
	dirArrow.BackgroundColor3 = COLOR.Player
	dirArrow.BorderSizePixel = 0
	dirArrow.ZIndex = 19
	dirArrow.Parent = minimap
	local dirCorner = Instance.new("UICorner")
	dirCorner.CornerRadius = UDim.new(1, 0)
	dirCorner.Parent = dirArrow
	playerDirection = dirArrow

	-- Legend
	buildLegend(panel)

	-- Click outside to close
	bg.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			-- Only close if clicking the background, not the panel
			local mousePos = UserInputService:GetMouseLocation()
			local panelPos = panel.AbsolutePosition
			local panelSize = panel.AbsoluteSize
			if mousePos.X < panelPos.X or mousePos.X > panelPos.X + panelSize.X
				or mousePos.Y < panelPos.Y or mousePos.Y > panelPos.Y + panelSize.Y
			then
				screenGui.Enabled = false
				mapOpen = false
			end
		end
	end)
end

--[[
    @summary  Update the player marker position and direction every frame.
]]
local function updatePlayerMarker()
	if not mapOpen or not playerMarker or not playerDirection or not campfireWorldPos then
		return
	end
	local character = Players.LocalPlayer.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	local camera = workspace.CurrentCamera
	if not rootPart or not rootPart:IsA("BasePart") then
		return
	end

	-- Update position
	playerMarker.Position = worldToMap(rootPart.Position)

	-- Update direction indicator based on camera look direction
	if camera then
		local look = camera.CFrame.LookVector
		local flatLook = Vector3.new(look.X, 0, look.Z)
		if flatLook.Magnitude > 0 then
			local angle = math.atan2(flatLook.X, -flatLook.Z)
			-- Position the direction dot ahead of the player marker
			local offset = 14
			local dx = math.sin(angle) * offset
			local dy = -math.cos(angle) * offset
			playerDirection.Position = UDim2.new(0.5, dx, 0.5, dy)
		end
	end
end

--[[
    @summary  Open the map UI with the current map data.
    @param    data  table
]]
local function openMap(data: { [string]: any })
	buildGui()
	if not gui then
		return
	end
	mapData = data
	campfireWorldPos = data.campfirePosition
	mapRadius = data.mapRadius or 1000
	buildMarkers()
	gui.Enabled = true
	mapOpen = true

	-- Start real-time player position updates
	if renderConnection then
		renderConnection:Disconnect()
	end
	renderConnection = RunService.RenderStepped:Connect(updatePlayerMarker)
end

--[[
    @summary  Close the map UI.
]]
local function closeMap()
	if gui then
		gui.Enabled = false
	end
	mapOpen = false
	if renderConnection then
		renderConnection:Disconnect()
		renderConnection = nil
	end
end

--[[
    @summary  Show a "locked" message when the player doesn't have the Map.
]]
local function showLockedMessage()
	buildGui()
	if not gui then
		return
	end

	-- Reuse the panel but show a locked message
	local panel = gui:FindFirstChild("Background"):FindFirstChild("Panel")
	if not panel then
		return
	end

	-- Check if a locked message already exists
	local existing = panel:FindFirstChild("LockedMessage")
	if existing then
		existing:Destroy()
	end

	local msg = Instance.new("TextLabel")
	msg.Name = "LockedMessage"
	msg.AnchorPoint = Vector2.new(0.5, 0.5)
	msg.Position = UDim2.fromScale(0.5, 0.5)
	msg.Size = UDim2.fromOffset(360, 80)
	msg.BackgroundColor3 = Color3.fromRGB(40, 30, 25)
	msg.BackgroundTransparency = 0.1
	msg.Font = Enum.Font.GothamBold
	msg.Text = "You need to craft the Map first!\nVisit the Crafting Bench."
	msg.TextColor3 = Color3.fromRGB(240, 230, 200)
	msg.TextSize = 16
	msg.TextWrapped = true
	msg.Parent = panel
	local msgCorner = Instance.new("UICorner")
	msgCorner.CornerRadius = UDim.new(0, 10)
	msgCorner.Parent = msg
	local msgStroke = Instance.new("UIStroke")
	msgStroke.Color = Color3.fromRGB(180, 100, 60)
	msgStroke.Thickness = 2
	msgStroke.Parent = msg

	gui.Enabled = true
	task.delay(2.5, function()
		if gui and gui.Enabled then
			gui.Enabled = false
		end
		msg:Destroy()
	end)
end

-- // INITIALIZATION // --

function MapController:KnitStart()
	mapService = Knit.GetService("MapService")
	local runStateService = Knit.GetService("RunStateService")

	buildGui()
	if gui then
		gui.Enabled = false
	end

	mapService.MapOpened:Connect(function(payload)
		if typeof(payload) ~= "table" then
			return
		end
		if payload.locked == true then
			showLockedMessage()
			return
		end
		-- Fetch fresh map data from the server
		mapService:GetMapData():andThen(function(data)
			if typeof(data) == "table" then
				openMap(data)
			end
		end):catch(function()
			-- If the remote fails, try opening with cached data
			if mapData then
				openMap(mapData)
			end
		end)
	end)

	-- Close on Escape
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then
			return
		end
		if input.KeyCode == Enum.KeyCode.Escape and mapOpen then
			closeMap()
		end
	end)

	-- Close on lobby phase
	runStateService.RunPhaseChanged:Connect(function(payload)
		if typeof(payload) == "table" and payload.phase == "Lobby" then
			closeMap()
		end
	end)
end

return MapController
