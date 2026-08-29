--[[
    @file    MapController.luau
    @author  manik
    @date    2026

    @summary
    Full-screen map UI with a professional two-column layout.

    Left: large circular minimap with compass ring (N/E/S/W), tick marks,
    access radius, player arrow, and icon-only markers to prevent overlap.

    Right: a dedicated information sidebar with a detailed legend, landmark
    counts, accessible area stats, and a hovered-marker info panel with
    distance from the player.

    @exports
    - MapController (Knit controller)
]]

-- // VARIABLES // --

-- | Services | --
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

-- | Modules | --
local Knit = require(ReplicatedStorage.Packages.Knit)
local ServerRole = require(ReplicatedStorage.Shared.ServerRole)

-- | Objects | --
local MapController = Knit.CreateController({
	Name = "MapController",
})

-- | Configuration | --
local PANEL_WIDTH = 980
local PANEL_HEIGHT = 660
local TITLE_BAR_HEIGHT = 52
local SIDEBAR_WIDTH = 340
local MINIMAP_SIZE = 520
local COMPASS_RING_SIZE = 560
local MARKER_SIZE_CAVE = 16
local MARKER_SIZE_BUILDING = 14
local MARKER_SIZE_FACILITY = 12
local MARKER_SIZE_CAMPFIRE = 20
local PLAYER_MARKER_SIZE = 12

-- Colors
local COLOR = {
	Panel = Color3.fromRGB(48, 42, 38),
	PanelStroke = Color3.fromRGB(30, 26, 24),
	TitleBar = Color3.fromRGB(70, 48, 28),
	MinimapBg = Color3.fromRGB(24, 32, 28),
	MinimapStroke = Color3.fromRGB(80, 90, 85),
	CompassRing = Color3.fromRGB(45, 50, 48),
	CompassText = Color3.fromRGB(200, 195, 185),
	Tick = Color3.fromRGB(120, 120, 120),
	Text = Color3.fromRGB(240, 235, 225),
	TextMuted = Color3.fromRGB(200, 195, 185),
	TextDim = Color3.fromRGB(170, 165, 155),
	TextDark = Color3.fromRGB(20, 15, 10),
	CloseBg = Color3.fromRGB(180, 55, 45),
	SidebarBg = Color3.fromRGB(38, 36, 42),
	SidebarStroke = Color3.fromRGB(60, 55, 65),
	SectionHeader = Color3.fromRGB(220, 190, 130),
	TooltipBg = Color3.fromRGB(28, 26, 30),
	TooltipStroke = Color3.fromRGB(80, 78, 85),
	-- Markers
	Campfire = Color3.fromRGB(255, 145, 45),
	Cave = Color3.fromRGB(230, 70, 60),
	CaveLocked = Color3.fromRGB(110, 110, 110),
	Playground = Color3.fromRGB(80, 155, 235),
	Restroom = Color3.fromRGB(90, 210, 115),
	Clinic = Color3.fromRGB(235, 90, 90),
	Building = Color3.fromRGB(175, 125, 70),
	CrashedPlane = Color3.fromRGB(190, 190, 190),
	Player = Color3.fromRGB(255, 255, 255),
	AccessRadius = Color3.fromRGB(110, 205, 125),
	MapBoundary = Color3.fromRGB(130, 130, 150),
	BarBg = Color3.fromRGB(55, 55, 60),
	BarFill = Color3.fromRGB(100, 205, 120),
}

-- | State Management | --
local mapService: any = nil
local gui: ScreenGui? = nil
local mapIconGui: ScreenGui? = nil
local mapIconButton: TextButton? = nil
local minimapFrame: Frame? = nil
local compassFrame: Frame? = nil
local playerMarker: Frame? = nil
local playerArrow: TextLabel? = nil
local sidebarFrame: Frame? = nil
local hoveredLabel: TextLabel? = nil
local hoveredSubLabel: TextLabel? = nil
local hoveredDistance: TextLabel? = nil
local levelLabel: TextLabel? = nil
local radiusLabel: TextLabel? = nil
local accessBarFill: Frame? = nil
local tooltipFrame: Frame? = nil
local tooltipTitle: TextLabel? = nil
local tooltipDesc: TextLabel? = nil
local panelScale: UIScale? = nil
local bgFrame: Frame? = nil
local boardMinimapFrame: Frame? = nil
local boardPlayerMarker: Frame? = nil
local boardPlayerArrow: TextLabel? = nil
local boardMarkerItems: { Frame } = {}
local mapOpen = false
local mapData: { [string]: any } = nil
local campfireWorldPos: Vector3? = nil
local mapRadius: number = 1000
local renderConnection: RBXScriptConnection? = nil
local currentPlayerPos: Vector3? = nil

local staticMarkers: { Frame } = {}
local markerGroups: { [string]: { Frame } } = {}
local highlightedGroup: string? = nil

-- // FUNCTIONS // --

-- Forward declarations to resolve circular references between UI build functions
local buildGui: () -> () = nil
local buildMapIcon: () -> () = nil
local setMapIconVisible: (visible: boolean) -> () = nil
local openMap: (data: { [string]: any }) -> () = nil
local closeMap: () -> () = nil

local function worldToMap(worldPos: Vector3): UDim2
	if not campfireWorldPos then
		return UDim2.fromScale(0.5, 0.5)
	end
	local dx = worldPos.X - campfireWorldPos.X
	local dz = worldPos.Z - campfireWorldPos.Z
	local scale = MINIMAP_SIZE / (2 * mapRadius)
	local px = dx * scale
	local py = dz * scale -- north (-Z) maps to up (negative Y) on the map
	local half = MINIMAP_SIZE * 0.5
	px = math.clamp(px, -half + 8, half - 8)
	py = math.clamp(py, -half + 8, half - 8)
	return UDim2.new(0.5, px, 0.5, py)
end

local function formatDistance(dist: number): string
	if dist < 50 then
		return "very close"
	elseif dist < 150 then
		return string.format("%.0f studs away", dist)
	else
		return string.format("%.0f studs", dist)
	end
end

local function showTooltip(pos: UDim2, title: string, description: string)
	if not tooltipFrame or not tooltipTitle or not tooltipDesc then
		return
	end
	tooltipTitle.Text = title
	tooltipDesc.Text = description
	local width = math.max(180, #title * 8.5 + 32)
	tooltipFrame.Size = UDim2.fromOffset(width, 56)
	-- Convert minimap-local position to panel-local position
	-- Minimap is centered in the left column which starts at (0, TITLE_BAR_HEIGHT)
	local leftColWidth = PANEL_WIDTH - SIDEBAR_WIDTH
	local minimapCenterX = leftColWidth * 0.5
	local minimapCenterY = TITLE_BAR_HEIGHT + (PANEL_HEIGHT - TITLE_BAR_HEIGHT) * 0.5
	local panelX = minimapCenterX + pos.X.Offset
	local panelY = minimapCenterY + pos.Y.Offset
	-- Position tooltip above the marker, clamped within the panel
	tooltipFrame.Position = UDim2.fromOffset(panelX, panelY - 64)
	tooltipFrame.Visible = true
end

local function hideTooltip()
	if tooltipFrame then
		tooltipFrame.Visible = false
	end
	if hoveredLabel then
		hoveredLabel.Text = "—"
		hoveredLabel.TextColor3 = COLOR.TextDim
	end
	if hoveredSubLabel then
		hoveredSubLabel.Text = "Hover over a marker for details"
		hoveredSubLabel.TextColor3 = COLOR.TextDim
	end
	if hoveredDistance then
		hoveredDistance.Text = ""
		hoveredDistance.TextColor3 = COLOR.TextDim
	end
end

local function setHoveredInfo(name: string, subText: string, distanceText: string)
	if hoveredLabel then
		hoveredLabel.Text = name
		hoveredLabel.TextColor3 = COLOR.Text
	end
	if hoveredSubLabel then
		hoveredSubLabel.Text = subText
		hoveredSubLabel.TextColor3 = COLOR.TextMuted
	end
	if hoveredDistance then
		hoveredDistance.Text = distanceText
		hoveredDistance.TextColor3 = COLOR.AccessRadius
	end
end

local function getDistanceText(worldPos: Vector3): string
	if not currentPlayerPos then
		return ""
	end
	local dist = (Vector3.new(worldPos.X, 0, worldPos.Z) - Vector3.new(currentPlayerPos.X, 0, currentPlayerPos.Z)).Magnitude
	return formatDistance(dist)
end

local function createMarker(parent: Instance, worldPos: Vector3, color: Color3, size: number, shape: string, name: string, subText: string, description: string, markerId: number, group: string?)
	local marker = Instance.new("Frame")
	marker.Name = "Marker" .. tostring(markerId)
	marker.AnchorPoint = Vector2.new(0.5, 0.5)
	marker.Position = worldToMap(worldPos)
	marker.Size = UDim2.fromOffset(size, size)
	marker.BackgroundColor3 = color
	marker.BackgroundTransparency = 0
	marker.BorderSizePixel = 0
	marker.ZIndex = 10
	marker.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = if shape == "square" then UDim.new(0, 3) else UDim.new(1, 0)
	corner.Parent = marker

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(255, 255, 255)
	stroke.Thickness = 1.5
	stroke.Transparency = 0.15
	stroke.Parent = marker

	if group then
		marker:SetAttribute("Group", group)
		markerGroups[group] = markerGroups[group] or {}
		table.insert(markerGroups[group], marker)
		marker:SetAttribute("BaseSize", size)
	end

	marker.MouseEnter:Connect(function()
		local distText = getDistanceText(worldPos)
		local fullSub = if distText ~= "" then subText .. " • " .. distText else subText
		setHoveredInfo(name, fullSub, distText)
		showTooltip(marker.Position, name, description)
		if not highlightedGroup then
			TweenService:Create(marker, TweenInfo.new(0.12), { Size = UDim2.fromOffset(size + 4, size + 4) }):Play()
		end
	end)
	marker.MouseLeave:Connect(function()
		hideTooltip()
		if not highlightedGroup then
			TweenService:Create(marker, TweenInfo.new(0.12), { Size = UDim2.fromOffset(size, size) }):Play()
		end
	end)

	return marker
end

local function buildRadiusCircles()
	if not minimapFrame or not mapData then
		return
	end

	local accessRadius = mapData.accessRadius or 200
	local scale = MINIMAP_SIZE / (2 * mapRadius)
	local accessPx = accessRadius * scale * 2
	local accessCircle = Instance.new("Frame")
	accessCircle.Name = "AccessRadius"
	accessCircle.AnchorPoint = Vector2.new(0.5, 0.5)
	accessCircle.Position = UDim2.fromScale(0.5, 0.5)
	accessCircle.Size = UDim2.fromOffset(accessPx, accessPx)
	accessCircle.BackgroundTransparency = 1
	accessCircle.BorderSizePixel = 0
	accessCircle.ZIndex = 5
	accessCircle.Parent = minimapFrame
	local accessCorner = Instance.new("UICorner")
	accessCorner.CornerRadius = UDim.new(1, 0)
	accessCorner.Parent = accessCircle
	local accessStroke = Instance.new("UIStroke")
	accessStroke.Color = COLOR.AccessRadius
	accessStroke.Thickness = 2
	accessStroke.Transparency = 0.35
	accessStroke.Parent = accessCircle
	table.insert(staticMarkers, accessCircle)

	local boundaryPx = MINIMAP_SIZE - 4
	local boundaryCircle = Instance.new("Frame")
	boundaryCircle.Name = "MapBoundary"
	boundaryCircle.AnchorPoint = Vector2.new(0.5, 0.5)
	boundaryCircle.Position = UDim2.fromScale(0.5, 0.5)
	boundaryCircle.Size = UDim2.fromOffset(boundaryPx, boundaryPx)
	boundaryCircle.BackgroundTransparency = 1
	boundaryCircle.BorderSizePixel = 0
	boundaryCircle.ZIndex = 5
	boundaryCircle.Parent = minimapFrame
	local boundaryCorner = Instance.new("UICorner")
	boundaryCorner.CornerRadius = UDim.new(1, 0)
	boundaryCorner.Parent = boundaryCircle
	local boundaryStroke = Instance.new("UIStroke")
	boundaryStroke.Color = COLOR.MapBoundary
	boundaryStroke.Thickness = 2
	boundaryStroke.Transparency = 0.55
	boundaryStroke.Parent = boundaryCircle
	table.insert(staticMarkers, boundaryCircle)
end

local function buildCompassRing()
	if not compassFrame then
		return
	end

	-- Clear any previous ring content
	for _, child in ipairs(compassFrame:GetChildren()) do
		child:Destroy()
	end

	local half = COMPASS_RING_SIZE * 0.5

	-- Cardinal direction labels
	local dirs = {
		{ name = "N", pos = UDim2.new(0.5, -8, 0, 4) },
		{ name = "E", pos = UDim2.new(1, -20, 0.5, -8) },
		{ name = "S", pos = UDim2.new(0.5, -8, 1, -20) },
		{ name = "W", pos = UDim2.new(0, 4, 0.5, -8) },
	}
	for _, dir in ipairs(dirs) do
		local label = Instance.new("TextLabel")
		label.Position = dir.pos
		label.Size = UDim2.fromOffset(18, 18)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.GothamBold
		label.Text = dir.name
		label.TextColor3 = COLOR.CompassText
		label.TextSize = 16
		label.TextXAlignment = Enum.TextXAlignment.Center
		label.TextYAlignment = Enum.TextYAlignment.Center
		label.Parent = compassFrame
	end

	-- Tick marks around the ring
	for i = 0, 35 do
		if i % 9 == 0 then
			continue -- skip cardinal positions
		end
		local angle = math.rad(i * 10)
		local radius = half - 8
		local isMajor = i % 3 == 0
		local tickLength = if isMajor then 8 else 4
		local tickThickness = if isMajor then 2 else 1
		local x = math.sin(angle) * radius
		local y = -math.cos(angle) * radius

		local tick = Instance.new("Frame")
		tick.AnchorPoint = Vector2.new(0.5, 0.5)
		tick.Position = UDim2.new(0.5, x, 0.5, y)
		tick.Size = UDim2.fromOffset(tickThickness, tickLength)
		tick.BackgroundColor3 = if isMajor then COLOR.CompassText else COLOR.Tick
		tick.BackgroundTransparency = 0.3
		tick.BorderSizePixel = 0
		tick.Rotation = math.deg(angle)
		tick.Parent = compassFrame
	end
end

local function buildMarkers()
	if not minimapFrame or not mapData then
		return
	end

	for _, marker in ipairs(staticMarkers) do
		marker:Destroy()
	end
	table.clear(staticMarkers)

	-- Reset group tracking
	for group in pairs(markerGroups) do
		markerGroups[group] = nil
	end
	for _, child in ipairs(minimapFrame:GetChildren()) do
		if child.Name ~= "PlayerMarker" and child.Name ~= "PlayerArrow" and child.Name ~= "Tooltip" then
			child:Destroy()
		end
	end

	local markerId = 0

	-- Campfire
	if mapData.campfirePosition then
		markerId += 1
		createMarker(minimapFrame, mapData.campfirePosition, COLOR.Campfire, MARKER_SIZE_CAMPFIRE, "circle",
			"Campfire", "Center of the safe zone", "Your main base and respawn point", markerId, "campfire")
	end

	-- Caves
	for _, cave in ipairs(mapData.caves or {}) do
		local isLocked = cave.state == "Locked"
		local isRescued = cave.state == "Rescued"
		local color = if isLocked then COLOR.CaveLocked else COLOR.Cave
		local stateText = if isLocked then "Locked" elseif isRescued then "Rescued" else "Available"
		local desc = if isLocked then "Requires a higher campfire level"
			elseif isRescued then "Child has been rescued"
			else "Rescue the missing child here"
		markerId += 1
		createMarker(minimapFrame, cave.position, color, MARKER_SIZE_CAVE, "circle",
			cave.displayName, stateText, desc, markerId, if isLocked then "caveLocked" else "cave")
	end

	-- Facilities
	for _, facility in ipairs(mapData.facilities or {}) do
		local color = COLOR.Playground
		local desc = "Loot source for scrap and junk"
		local group = "playground"
		if facility.type == "Restroom" then
			color = COLOR.Restroom
			desc = "Common loot and resources"
			group = "restroom"
		elseif facility.type == "Clinic" then
			color = COLOR.Clinic
			desc = "Healing items and medical supplies"
			group = "clinic"
		end
		markerId += 1
		createMarker(minimapFrame, facility.position, color, MARKER_SIZE_FACILITY, "square",
			facility.type, "Facility", desc, markerId, group)
	end

	-- Buildings
	for _, building in ipairs(mapData.buildings or {}) do
		local color = COLOR.Building
		local desc = "Shelter and loot location"
		local group = "building"
		if building.name == "Crashed Plane" then
			color = COLOR.CrashedPlane
			desc = "Wreckage with scavengable supplies"
			group = "crashedPlane"
		elseif building.name == "Hunters Lodge" then
			desc = "Hunting cabin with supplies"
		elseif building.name == "Treehouse" then
			desc = "Elevated shelter"
		elseif building.name == "Tower" then
			desc = "Lookout tower"
		end
		markerId += 1
		createMarker(minimapFrame, building.position, color, MARKER_SIZE_BUILDING, "square",
			building.name, "Building", desc, markerId, group)
	end

	buildRadiusCircles()
end

-- Legend entry with icon, title, and description
type LegendEntryDef = {
	color: Color3,
	symbol: string,
	title: string,
	desc: string,
	group: string?, -- matches marker group names
}

local function setMarkerGroupHighlight(group: string?, highlight: boolean)
	if highlightedGroup == group and highlight then
		return
	end
	if not highlight then
		highlightedGroup = nil
	else
		highlightedGroup = group
	end

	for g, markers in pairs(markerGroups) do
		local shouldDim = highlight and g ~= group
		local shouldGlow = highlight and g == group
		for _, marker in ipairs(markers) do
			local baseSize = marker:GetAttribute("BaseSize") or 12
			if shouldDim then
				TweenService:Create(marker, TweenInfo.new(0.18), {
					Size = UDim2.fromOffset(baseSize, baseSize),
					BackgroundTransparency = 0.7,
				}):Play()
			elseif shouldGlow then
				TweenService:Create(marker, TweenInfo.new(0.18), {
					Size = UDim2.fromOffset(baseSize + 6, baseSize + 6),
					BackgroundTransparency = 0,
				}):Play()
			else
				TweenService:Create(marker, TweenInfo.new(0.18), {
					Size = UDim2.fromOffset(baseSize, baseSize),
					BackgroundTransparency = 0,
				}):Play()
			end
		end
	end
end

local function createLegendEntry(parent: Instance, order: number, entry: LegendEntryDef, count: number?)
	local row = Instance.new("TextButton")
	row.Name = "Entry" .. tostring(order)
	row.LayoutOrder = order
	row.Size = UDim2.new(1, 0, 0, 46)
	row.BackgroundTransparency = 1
	row.Text = ""
	row.AutoButtonColor = false
	row.Parent = parent

	row.MouseEnter:Connect(function()
		if row:GetAttribute("Active") ~= true then
			TweenService:Create(row, TweenInfo.new(0.1), { BackgroundColor3 = Color3.fromRGB(55, 52, 60), BackgroundTransparency = 0.4 }):Play()
		end
	end)
	row.MouseLeave:Connect(function()
		if row:GetAttribute("Active") ~= true then
			TweenService:Create(row, TweenInfo.new(0.1), { BackgroundTransparency = 1 }):Play()
		end
	end)

	local isActive = false
	row.MouseButton1Click:Connect(function()
		isActive = not isActive
		row:SetAttribute("Active", isActive)
		if isActive then
			for _, child in ipairs(parent:GetChildren()) do
				if child:IsA("TextButton") and child ~= row then
					child:SetAttribute("Active", false)
					TweenService:Create(child, TweenInfo.new(0.1), { BackgroundTransparency = 1 }):Play()
				end
			end
			setMarkerGroupHighlight(entry.group, true)
			TweenService:Create(row, TweenInfo.new(0.1), { BackgroundColor3 = Color3.fromRGB(70, 65, 78), BackgroundTransparency = 0.25 }):Play()
		else
			setMarkerGroupHighlight(entry.group, false)
			TweenService:Create(row, TweenInfo.new(0.1), { BackgroundTransparency = 1 }):Play()
		end
	end)

	local icon = Instance.new("Frame")
	icon.AnchorPoint = Vector2.new(0, 0.5)
	icon.Position = UDim2.new(0, 2, 0.5, 0)
	icon.Size = UDim2.fromOffset(22, 22)
	icon.BackgroundColor3 = entry.color
	icon.BorderSizePixel = 0
	icon.Parent = row
	local iconCorner = Instance.new("UICorner")
	iconCorner.CornerRadius = if entry.symbol == "square" then UDim.new(0, 3) else UDim.new(1, 0)
	iconCorner.Parent = icon
	local iconStroke = Instance.new("UIStroke")
	iconStroke.Color = Color3.fromRGB(255, 255, 255)
	iconStroke.Thickness = 1.5
	iconStroke.Transparency = 0.2
	iconStroke.Parent = icon

	if entry.symbol == "player" then
		local sym = Instance.new("TextLabel")
		sym.Size = UDim2.fromScale(1, 1)
		sym.BackgroundTransparency = 1
		sym.Font = Enum.Font.GothamBold
		sym.Text = "●"
		sym.TextColor3 = Color3.fromRGB(40, 40, 45)
		sym.TextSize = 16
		sym.TextYAlignment = Enum.TextYAlignment.Center
		sym.Parent = icon
	end

	local title = Instance.new("TextLabel")
	title.Position = UDim2.new(0, 34, 0, 2)
	title.Size = UDim2.new(1, -34, 0, 18)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBold
	title.Text = entry.title .. if count and count > 0 then "  (" .. tostring(count) .. ")" else ""
	title.TextColor3 = COLOR.Text
	title.TextSize = 14
	title.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	title.TextStrokeTransparency = 0.4
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextYAlignment = Enum.TextYAlignment.Center
	title.Parent = row

	local desc = Instance.new("TextLabel")
	desc.Position = UDim2.new(0, 34, 0, 22)
	desc.Size = UDim2.new(1, -34, 0, 18)
	desc.BackgroundTransparency = 1
	desc.Font = Enum.Font.GothamBold
	desc.Text = entry.desc
	desc.TextColor3 = COLOR.TextDim
	desc.TextSize = 13
	desc.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	desc.TextStrokeTransparency = 0.5
	desc.TextXAlignment = Enum.TextXAlignment.Left
	desc.TextWrapped = true
	desc.Parent = row
end

local function createSectionHeader(parent: Instance, order: number, headerText: string)
	local header = Instance.new("TextLabel")
	header.Name = "Header" .. tostring(order)
	header.LayoutOrder = order
	header.Size = UDim2.new(1, 0, 0, 24)
	header.BackgroundTransparency = 1
	header.Font = Enum.Font.GothamBlack
	header.Text = headerText
	header.TextColor3 = COLOR.SectionHeader
	header.TextSize = 14
	header.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	header.TextStrokeTransparency = 0.4
	header.TextXAlignment = Enum.TextXAlignment.Left
	header.TextYAlignment = Enum.TextYAlignment.Bottom
	header.Parent = parent
end

local function buildSidebar(parent: Frame, counts: { [string]: number })
	if sidebarFrame then
		sidebarFrame:Destroy()
		sidebarFrame = nil
	end

	local sidebar = Instance.new("Frame")
	sidebar.Name = "Sidebar"
	sidebar.AnchorPoint = Vector2.new(1, 0)
	sidebar.Position = UDim2.new(1, 0, 0, TITLE_BAR_HEIGHT)
	sidebar.Size = UDim2.fromOffset(SIDEBAR_WIDTH, PANEL_HEIGHT - TITLE_BAR_HEIGHT)
	sidebar.BackgroundColor3 = COLOR.SidebarBg
	sidebar.BackgroundTransparency = 0.08
	sidebar.BorderSizePixel = 0
	sidebar.Parent = parent
	sidebarFrame = sidebar

	local sidebarCorner = Instance.new("UICorner")
	sidebarCorner.CornerRadius = UDim.new(0, 0)
	sidebarCorner.Parent = sidebar

	local sidebarStroke = Instance.new("UIStroke")
	sidebarStroke.Color = COLOR.SidebarStroke
	sidebarStroke.Thickness = 1
	sidebarStroke.Transparency = 0.45
	sidebarStroke.Parent = sidebar

	local content = Instance.new("ScrollingFrame")
	content.Name = "Content"
	content.Position = UDim2.fromOffset(20, 20)
	content.Size = UDim2.new(1, -40, 1, -40)
	content.BackgroundTransparency = 1
	content.ScrollBarThickness = 5
	content.ScrollBarImageColor3 = Color3.fromRGB(100, 95, 105)
	content.ScrollingDirection = Enum.ScrollingDirection.Y
	content.AutomaticCanvasSize = Enum.AutomaticSize.Y
	content.CanvasSize = UDim2.new()
	content.Parent = sidebar

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = content

	local order = 0
	local function nextOrder()
		order += 1
		return order
	end

	-- LEGEND
	createSectionHeader(content, nextOrder(), "LEGEND")
	createLegendEntry(content, nextOrder(), {
		color = COLOR.Campfire, symbol = "circle", title = "Campfire",
		desc = "Your safe zone and respawn point",
		group = "campfire",
	}, nil)
	createLegendEntry(content, nextOrder(), {
		color = COLOR.Cave, symbol = "circle", title = "Cave (Available)",
		desc = "Rescue the missing child here",
		group = "cave",
	}, counts.caveAvailable)
	createLegendEntry(content, nextOrder(), {
		color = COLOR.CaveLocked, symbol = "circle", title = "Cave (Locked)",
		desc = "Requires higher campfire level",
		group = "caveLocked",
	}, counts.caveLocked)
	createLegendEntry(content, nextOrder(), {
		color = COLOR.Building, symbol = "square", title = "Building",
		desc = "Shelters with loot and resources",
		group = "building",
	}, counts.building)
	createLegendEntry(content, nextOrder(), {
		color = COLOR.CrashedPlane, symbol = "square", title = "Crashed Plane",
		desc = "Wreckage with scavengable supplies",
		group = "crashedPlane",
	}, counts.crashedPlane)
	createLegendEntry(content, nextOrder(), {
		color = COLOR.Playground, symbol = "square", title = "Playground",
		desc = "Common junk and scrap loot",
		group = "playground",
	}, counts.playground)
	createLegendEntry(content, nextOrder(), {
		color = COLOR.Restroom, symbol = "square", title = "Restroom",
		desc = "Common loot and resources",
		group = "restroom",
	}, counts.restroom)
	createLegendEntry(content, nextOrder(), {
		color = COLOR.Clinic, symbol = "square", title = "Clinic",
		desc = "Healing items and medical supplies",
		group = "clinic",
	}, counts.clinic)
	createLegendEntry(content, nextOrder(), {
		color = COLOR.Player, symbol = "player", title = "You",
		desc = "Your current position and facing",
		group = nil,
	}, nil)

	-- Spacer
	local spacer1 = Instance.new("Frame")
	spacer1.LayoutOrder = nextOrder()
	spacer1.Size = UDim2.new(1, 0, 0, 14)
	spacer1.BackgroundTransparency = 1
	spacer1.Parent = content

	-- ACCESSIBLE AREA
	createSectionHeader(content, nextOrder(), "ACCESSIBLE AREA")

	levelLabel = Instance.new("TextLabel")
	assert(levelLabel, "levelLabel is nil")
	levelLabel.LayoutOrder = nextOrder()
	levelLabel.Size = UDim2.new(1, 0, 0, 22)
	levelLabel.BackgroundTransparency = 1
	levelLabel.Font = Enum.Font.GothamBold
	levelLabel.Text = "Level: —"
	levelLabel.TextColor3 = COLOR.TextMuted
	levelLabel.TextSize = 15
	levelLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	levelLabel.TextStrokeTransparency = 0.4
	levelLabel.TextXAlignment = Enum.TextXAlignment.Left
	levelLabel.Parent = content

	radiusLabel = Instance.new("TextLabel")
	assert(radiusLabel, "radiusLabel is nil")
	radiusLabel.LayoutOrder = nextOrder()
	radiusLabel.Size = UDim2.new(1, 0, 0, 22)
	radiusLabel.BackgroundTransparency = 1
	radiusLabel.Font = Enum.Font.GothamBold
	radiusLabel.Text = "Radius: — studs"
	radiusLabel.TextColor3 = COLOR.TextMuted
	radiusLabel.TextSize = 15
	radiusLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	radiusLabel.TextStrokeTransparency = 0.4
	radiusLabel.TextXAlignment = Enum.TextXAlignment.Left
	radiusLabel.Parent = content

	local barBg = Instance.new("Frame")
	barBg.LayoutOrder = nextOrder()
	barBg.Size = UDim2.new(1, 0, 0, 8)
	barBg.BackgroundColor3 = COLOR.BarBg
	barBg.BorderSizePixel = 0
	barBg.Parent = content
	local barCorner = Instance.new("UICorner")
	barCorner.CornerRadius = UDim.new(1, 0)
	barCorner.Parent = barBg

	accessBarFill = Instance.new("Frame")
	assert(accessBarFill, "accessBarFill is nil")
	accessBarFill.Size = UDim2.new(0.2, 0, 1, 0)
	accessBarFill.BackgroundColor3 = COLOR.BarFill
	accessBarFill.BorderSizePixel = 0
	accessBarFill.Parent = barBg
	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(1, 0)
	fillCorner.Parent = accessBarFill

	-- Spacer
	local spacer2 = Instance.new("Frame")
	spacer2.LayoutOrder = nextOrder()
	spacer2.Size = UDim2.new(1, 0, 0, 18)
	spacer2.BackgroundTransparency = 1
	spacer2.Parent = content

	-- HOVERED MARKER
	createSectionHeader(content, nextOrder(), "HOVERED MARKER")

	hoveredLabel = Instance.new("TextLabel")
	assert(hoveredLabel, "hoveredLabel is nil")
	hoveredLabel.LayoutOrder = nextOrder()
	hoveredLabel.Size = UDim2.new(1, 0, 0, 24)
	hoveredLabel.BackgroundTransparency = 1
	hoveredLabel.Font = Enum.Font.GothamBlack
	hoveredLabel.Text = "—"
	hoveredLabel.TextColor3 = COLOR.TextDim
	hoveredLabel.TextSize = 17
	hoveredLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	hoveredLabel.TextStrokeTransparency = 0.4
	hoveredLabel.TextXAlignment = Enum.TextXAlignment.Left
	hoveredLabel.Parent = content

	hoveredSubLabel = Instance.new("TextLabel")
	assert(hoveredSubLabel, "hoveredSubLabel is nil")
	hoveredSubLabel.LayoutOrder = nextOrder()
	hoveredSubLabel.Size = UDim2.new(1, 0, 0, 20)
	hoveredSubLabel.BackgroundTransparency = 1
	hoveredSubLabel.Font = Enum.Font.GothamBold
	hoveredSubLabel.Text = "Hover over a marker for details"
	hoveredSubLabel.TextColor3 = COLOR.TextDim
	hoveredSubLabel.TextSize = 14
	hoveredSubLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	hoveredSubLabel.TextStrokeTransparency = 0.5
	hoveredSubLabel.TextXAlignment = Enum.TextXAlignment.Left
	hoveredSubLabel.Parent = content

	hoveredDistance = Instance.new("TextLabel")
	assert(hoveredDistance, "hoveredDistance is nil")
	hoveredDistance.LayoutOrder = nextOrder()
	hoveredDistance.Size = UDim2.new(1, 0, 0, 20)
	hoveredDistance.BackgroundTransparency = 1
	hoveredDistance.Font = Enum.Font.GothamBold
	hoveredDistance.Text = ""
	hoveredDistance.TextColor3 = COLOR.AccessRadius
	hoveredDistance.TextSize = 14
	hoveredDistance.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	hoveredDistance.TextStrokeTransparency = 0.4
	hoveredDistance.TextXAlignment = Enum.TextXAlignment.Left
	hoveredDistance.Parent = content
end

local function buildTooltip(parent: Instance)
	local tooltip = Instance.new("Frame")
	tooltip.Name = "Tooltip"
	tooltip.AnchorPoint = Vector2.new(0.5, 1)
	tooltip.Size = UDim2.fromOffset(220, 56)
	tooltip.BackgroundColor3 = COLOR.TooltipBg
	tooltip.BackgroundTransparency = 0.02
	tooltip.BorderSizePixel = 0
	tooltip.Visible = false
	tooltip.ZIndex = 100
	tooltip.Parent = parent
	local tooltipCorner = Instance.new("UICorner")
	tooltipCorner.CornerRadius = UDim.new(0, 8)
	tooltipCorner.Parent = tooltip
	local tooltipStroke = Instance.new("UIStroke")
	tooltipStroke.Color = COLOR.TooltipStroke
	tooltipStroke.Thickness = 2
	tooltipStroke.Transparency = 0.1
	tooltipStroke.Parent = tooltip

	tooltipTitle = Instance.new("TextLabel")
	assert(tooltipTitle, "tooltipTitle is nil")
	tooltipTitle.Position = UDim2.new(0, 12, 0, 6)
	tooltipTitle.Size = UDim2.new(1, -24, 0, 22)
	tooltipTitle.BackgroundTransparency = 1
	tooltipTitle.Font = Enum.Font.GothamBold
	tooltipTitle.Text = ""
	tooltipTitle.TextColor3 = COLOR.Text
	tooltipTitle.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	tooltipTitle.TextStrokeTransparency = 0.3
	tooltipTitle.TextSize = 15
	tooltipTitle.ZIndex = 101
	tooltipTitle.TextXAlignment = Enum.TextXAlignment.Center
	tooltipTitle.TextYAlignment = Enum.TextYAlignment.Center
	tooltipTitle.Parent = tooltip

	tooltipDesc = Instance.new("TextLabel")
	assert(tooltipDesc, "tooltipDesc is nil")
	tooltipDesc.Position = UDim2.new(0, 12, 0, 28)
	tooltipDesc.Size = UDim2.new(1, -24, 0, 22)
	tooltipDesc.BackgroundTransparency = 1
	tooltipDesc.Font = Enum.Font.GothamBold
	tooltipDesc.Text = ""
	tooltipDesc.TextColor3 = COLOR.TextDim
	tooltipDesc.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	tooltipDesc.TextStrokeTransparency = 0.4
	tooltipDesc.TextSize = 13
	tooltipDesc.ZIndex = 101
	tooltipDesc.TextXAlignment = Enum.TextXAlignment.Center
	tooltipDesc.TextYAlignment = Enum.TextYAlignment.Center
	tooltipDesc.Parent = tooltip

	tooltipFrame = tooltip
end

function buildGui()
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

	local bg = Instance.new("Frame")
	bg.Name = "Background"
	bg.Size = UDim2.fromScale(1, 1)
	bg.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	bg.BackgroundTransparency = 0.55
	bg.BorderSizePixel = 0
	bg.Parent = screenGui
	bgFrame = bg

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromOffset(PANEL_WIDTH, PANEL_HEIGHT)
	panel.BackgroundColor3 = COLOR.Panel
	panel.BorderSizePixel = 0
	panel.Parent = bg
	local panelCorner = Instance.new("UICorner")
	panelCorner.CornerRadius = UDim.new(0, 12)
	panelCorner.Parent = panel
	local panelStroke = Instance.new("UIStroke")
	panelStroke.Color = COLOR.PanelStroke
	panelStroke.Thickness = 3
	panelStroke.Parent = panel

	-- Scale for smooth open/close animation
	local scale = Instance.new("UIScale")
	scale.Scale = 0.85
	scale.Parent = panel
	panelScale = scale

	-- Title bar
	local titleBar = Instance.new("Frame")
	titleBar.Name = "TitleBar"
	titleBar.Size = UDim2.new(1, 0, 0, TITLE_BAR_HEIGHT)
	titleBar.BackgroundColor3 = COLOR.TitleBar
	titleBar.BackgroundTransparency = 0.2
	titleBar.BorderSizePixel = 0
	titleBar.Parent = panel

	local title = Instance.new("TextLabel")
	title.Position = UDim2.new(0, 22, 0, 0)
	title.Size = UDim2.new(1, -70, 0, TITLE_BAR_HEIGHT)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.PermanentMarker
	title.Text = "MAP"
	title.TextColor3 = COLOR.Text
	title.TextStrokeColor3 = COLOR.TextDark
	title.TextStrokeTransparency = 0.25
	title.TextSize = 28
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextYAlignment = Enum.TextYAlignment.Center
	title.Parent = titleBar

	local closeBtn = Instance.new("TextButton")
	closeBtn.Name = "CloseButton"
	closeBtn.AnchorPoint = Vector2.new(1, 0.5)
	closeBtn.Position = UDim2.new(1, -14, 0.5, 0)
	closeBtn.Size = UDim2.fromOffset(34, 34)
	closeBtn.BackgroundColor3 = COLOR.CloseBg
	closeBtn.Font = Enum.Font.GothamBold
	closeBtn.Text = "X"
	closeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	closeBtn.TextSize = 18
	closeBtn.Parent = titleBar
	local closeCorner = Instance.new("UICorner")
	closeCorner.CornerRadius = UDim.new(1, 0)
	closeCorner.Parent = closeBtn
	closeBtn.MouseButton1Click:Connect(function()
		closeMap()
	end)

	-- Left column
	local leftColumn = Instance.new("Frame")
	leftColumn.Name = "LeftColumn"
	leftColumn.Position = UDim2.fromOffset(0, TITLE_BAR_HEIGHT)
	leftColumn.Size = UDim2.new(1, -SIDEBAR_WIDTH, 1, -TITLE_BAR_HEIGHT)
	leftColumn.BackgroundTransparency = 1
	leftColumn.BorderSizePixel = 0
	leftColumn.Parent = panel

	-- Compass ring (behind minimap)
	local compass = Instance.new("Frame")
	compass.Name = "CompassRing"
	compass.AnchorPoint = Vector2.new(0.5, 0.5)
	compass.Position = UDim2.fromScale(0.5, 0.5)
	compass.Size = UDim2.fromOffset(COMPASS_RING_SIZE, COMPASS_RING_SIZE)
	compass.BackgroundTransparency = 1
	compass.BorderSizePixel = 0
	compass.Parent = leftColumn
	compassFrame = compass

	-- Minimap canvas
	local minimap = Instance.new("Frame")
	minimap.Name = "Minimap"
	minimap.AnchorPoint = Vector2.new(0.5, 0.5)
	minimap.Position = UDim2.fromScale(0.5, 0.5)
	minimap.Size = UDim2.fromOffset(MINIMAP_SIZE, MINIMAP_SIZE)
	minimap.BackgroundColor3 = COLOR.MinimapBg
	minimap.BorderSizePixel = 0
	minimap.ClipsDescendants = true
	minimap.Parent = leftColumn
	local minimapCorner = Instance.new("UICorner")
	minimapCorner.CornerRadius = UDim.new(1, 0)
	minimapCorner.Parent = minimap
	local minimapStroke = Instance.new("UIStroke")
	minimapStroke.Color = COLOR.MinimapStroke
	minimapStroke.Thickness = 3
	minimapStroke.Parent = minimap
	minimapFrame = minimap

	-- Tooltip is parented to the panel (not the minimap) so it isn't clipped
	buildTooltip(panel)

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

	-- Player direction arrow (text triangle pointing in heading direction)
	local arrow = Instance.new("TextLabel")
	arrow.Name = "PlayerArrow"
	arrow.AnchorPoint = Vector2.new(0.5, 0.5)
	arrow.Position = UDim2.new(0.5, 0, 0.5, -PLAYER_MARKER_SIZE)
	arrow.Size = UDim2.fromOffset(18, 22)
	arrow.BackgroundTransparency = 1
	arrow.Font = Enum.Font.GothamBlack
	arrow.Text = "▲"
	arrow.TextColor3 = COLOR.Player
	arrow.TextSize = 18
	arrow.TextXAlignment = Enum.TextXAlignment.Center
	arrow.TextYAlignment = Enum.TextYAlignment.Center
	arrow.Rotation = 0
	arrow.ZIndex = 19
	arrow.Parent = minimap
	playerArrow = arrow

	-- Compass ring labels/ticks
	buildCompassRing()

	-- Click outside to close
	bg.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 and mapOpen then
			local mousePos = UserInputService:GetMouseLocation()
			local panelPos = panel.AbsolutePosition
			local panelSize = panel.AbsoluteSize
			if mousePos.X < panelPos.X or mousePos.X > panelPos.X + panelSize.X
				or mousePos.Y < panelPos.Y or mousePos.Y > panelPos.Y + panelSize.Y
			then
				closeMap()
			end
		end
	end)

	-- Map icon (persistent quick-access button)
	buildMapIcon()
end

-- Map quick-access icon that stays on screen when the full map is closed
function buildMapIcon()
	if mapIconGui then
		return
	end

	local iconGui = Instance.new("ScreenGui")
	iconGui.Name = "MapIconGui"
	iconGui.ResetOnSpawn = false
	iconGui.IgnoreGuiInset = true
	iconGui.Enabled = true
	iconGui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	mapIconGui = iconGui

	-- Container frame for the icon and a small label below it
	local container = Instance.new("Frame")
	container.Name = "MapIconContainer"
	container.AnchorPoint = Vector2.new(1, 1)
	container.Position = UDim2.new(1, -20, 1, -20) -- bottom-right corner
	container.Size = UDim2.fromOffset(64, 64)
	container.BackgroundTransparency = 1
	container.Parent = iconGui

	local iconBtn = Instance.new("TextButton")
	iconBtn.Name = "MapIcon"
	iconBtn.AnchorPoint = Vector2.new(0.5, 0.5)
	iconBtn.Position = UDim2.fromScale(0.5, 0.5)
	iconBtn.Size = UDim2.fromOffset(56, 56)
	iconBtn.BackgroundColor3 = Color3.fromRGB(50, 38, 28)
	iconBtn.BackgroundTransparency = 0.05
	iconBtn.Text = ""
	iconBtn.AutoButtonColor = false
	iconBtn.ZIndex = 10
	iconBtn.Parent = container
	local iconCorner = Instance.new("UICorner")
	iconCorner.CornerRadius = UDim.new(0, 14)
	iconCorner.Parent = iconBtn
	local iconStroke = Instance.new("UIStroke")
	iconStroke.Color = Color3.fromRGB(180, 150, 100)
	iconStroke.Thickness = 3
	iconStroke.Transparency = 0.1
	iconStroke.Parent = iconBtn

	-- Drop shadow for visibility against any background
	local shadow = Instance.new("ImageLabel")
	shadow.Name = "Shadow"
	shadow.AnchorPoint = Vector2.new(0.5, 0.5)
	shadow.Position = UDim2.new(0.5, 0, 0.5, 3)
	shadow.Size = UDim2.fromOffset(72, 72)
	shadow.BackgroundTransparency = 1
	shadow.Image = "rbxasset://textures/ui/GuiImagePlaceHolder.png"
	shadow.ImageColor3 = Color3.fromRGB(0, 0, 0)
	shadow.ImageTransparency = 0.6
	shadow.ZIndex = 9
	shadow.Parent = container

	local iconLabel = Instance.new("TextLabel")
	iconLabel.Size = UDim2.fromScale(1, 1)
	iconLabel.BackgroundTransparency = 1
	iconLabel.Font = Enum.Font.PermanentMarker
	iconLabel.Text = "M"
	iconLabel.TextColor3 = Color3.fromRGB(245, 230, 195)
	iconLabel.TextStrokeColor3 = Color3.fromRGB(20, 10, 5)
	iconLabel.TextStrokeTransparency = 0.3
	iconLabel.TextSize = 28
	iconLabel.ZIndex = 11
	iconLabel.TextYAlignment = Enum.TextYAlignment.Center
	iconLabel.Parent = iconBtn

	local miniCompass = Instance.new("TextLabel")
	miniCompass.AnchorPoint = Vector2.new(0.5, 0)
	miniCompass.Position = UDim2.new(0.5, 0, 0, 3)
	miniCompass.Size = UDim2.fromOffset(16, 12)
	miniCompass.BackgroundTransparency = 1
	miniCompass.Font = Enum.Font.GothamBold
	miniCompass.Text = "N"
	miniCompass.TextColor3 = Color3.fromRGB(220, 200, 160)
	miniCompass.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	miniCompass.TextStrokeTransparency = 0.4
	miniCompass.TextSize = 11
	miniCompass.ZIndex = 12
	miniCompass.TextXAlignment = Enum.TextXAlignment.Center
	miniCompass.Parent = iconBtn

	iconBtn.MouseEnter:Connect(function()
		TweenService:Create(iconBtn, TweenInfo.new(0.12), { BackgroundColor3 = Color3.fromRGB(75, 58, 42), Size = UDim2.fromOffset(60, 60) }):Play()
	end)
	iconBtn.MouseLeave:Connect(function()
		TweenService:Create(iconBtn, TweenInfo.new(0.12), { BackgroundColor3 = Color3.fromRGB(50, 38, 28), Size = UDim2.fromOffset(56, 56) }):Play()
	end)
	iconBtn.MouseButton1Click:Connect(function()
		if mapService then
			mapService:GetMapData():andThen(function(data)
				if typeof(data) == "table" then
					openMap(data)
				end
			end)
		end
	end)

	mapIconButton = iconBtn

	-- Animate in
	iconBtn.Size = UDim2.fromOffset(0, 0)
	TweenService:Create(iconBtn, TweenInfo.new(0.3, Enum.EasingStyle.Back), { Size = UDim2.fromOffset(56, 56) }):Play()
end

function setMapIconVisible(visible: boolean)
	if not mapIconGui then
		buildMapIcon()
	end
	if mapIconGui then
		mapIconGui.Enabled = visible
	end
	if mapIconButton and visible then
		mapIconButton.Size = UDim2.fromOffset(0, 0)
		TweenService:Create(mapIconButton, TweenInfo.new(0.3, Enum.EasingStyle.Back), { Size = UDim2.fromOffset(56, 56) }):Play()
	end
end

local function computeSidebarCounts(): { [string]: number }
	local counts = {
		caveAvailable = 0,
		caveLocked = 0,
		building = 0,
		crashedPlane = 0,
		playground = 0,
		restroom = 0,
		clinic = 0,
	}
	for _, cave in ipairs(mapData and mapData.caves or {}) do
		if cave.state == "Locked" then
			counts.caveLocked += 1
		else
			counts.caveAvailable += 1
		end
	end
	for _, building in ipairs(mapData and mapData.buildings or {}) do
		counts.building += 1
		if building.name == "Crashed Plane" then
			counts.crashedPlane += 1
		end
	end
	for _, facility in ipairs(mapData and mapData.facilities or {}) do
		if facility.type == "Playground" then
			counts.playground += 1
		elseif facility.type == "Restroom" then
			counts.restroom += 1
		elseif facility.type == "Clinic" then
			counts.clinic += 1
		end
	end
	return counts
end

local function updateAccessibleAreaInfo()
	if not mapData then
		return
	end
	local accessRadius = mapData.accessRadius or 200
	local accessRadii = { 200, 350, 600, 780, 900, 1000 }
	local level = 1
	for i, r in ipairs(accessRadii) do
		if accessRadius <= r then
			level = i
			break
		end
	end
	if levelLabel then
		levelLabel.Text = "Level: " .. tostring(level)
	end
	if radiusLabel then
		radiusLabel.Text = "Radius: " .. tostring(accessRadius) .. " studs"
	end
	if accessBarFill then
		local fraction = math.clamp(accessRadius / mapRadius, 0, 1)
		accessBarFill.Size = UDim2.new(fraction, 0, 1, 0)
	end
end

local function boardWorldToMap(worldPos: Vector3, boardSize: number): UDim2
	if not campfireWorldPos then
		return UDim2.fromScale(0.5, 0.5)
	end
	local dx = worldPos.X - campfireWorldPos.X
	local dz = worldPos.Z - campfireWorldPos.Z
	local scale = boardSize / (2 * mapRadius)
	-- Back face mirrors the X axis, so negate px to keep east on the right
	local px = -dx * scale
	local py = dz * scale -- north (-Z) maps to up (negative Y) on the map
	local half = boardSize * 0.5
	px = math.clamp(px, -half + 6, half - 6)
	py = math.clamp(py, -half + 6, half - 6)
	return UDim2.new(0.5, px, 0.5, py)
end

local function buildBoardMinimap(data: { [string]: any })
	local boards = workspace:FindFirstChild("Boards")
	if not boards then
		return
	end
	local mapBoard = boards:FindFirstChild("MapBoard")
	if not mapBoard then
		return
	end
	local boardPanel = mapBoard:FindFirstChild("BoardPanel") :: BasePart?
	if not boardPanel then
		return
	end
	local boardGui = boardPanel:FindFirstChild("BoardGui") :: SurfaceGui?
	if not boardGui then
		return
	end

	-- Hide the locked subtitle if present
	local subtitle = boardGui:FindFirstChild("Subtitle") :: TextLabel?
	if subtitle then
		subtitle.Visible = false
	end

	-- Build or clear the live minimap container
	-- Canvas is 1024x660 (matches board 14:9 aspect). Use a square minimap that fits vertically.
	local liveMap = boardGui:FindFirstChild("LiveMap") :: Frame?
	if not liveMap then
		liveMap = Instance.new("Frame")
		liveMap.Name = "LiveMap"
		liveMap.AnchorPoint = Vector2.new(0.5, 0.5)
		liveMap.Position = UDim2.new(0.5, 0, 0.5, 10)
		liveMap.Size = UDim2.fromOffset(440, 440)
		liveMap.BackgroundColor3 = COLOR.MinimapBg
		liveMap.BorderSizePixel = 0
		liveMap.ClipsDescendants = true
		liveMap.Parent = boardGui
		local liveCorner = Instance.new("UICorner")
		liveCorner.CornerRadius = UDim.new(1, 0)
		liveCorner.Parent = liveMap
		local liveStroke = Instance.new("UIStroke")
		liveStroke.Color = COLOR.MinimapStroke
		liveStroke.Thickness = 4
		liveStroke.Parent = liveMap
	end
	assert(liveMap, "liveMap is nil")
	liveMap = liveMap :: Frame
	boardMinimapFrame = liveMap
	for _, child in ipairs(liveMap:GetChildren()) do
		child:Destroy()
	end

	table.clear(boardMarkerItems)

	local boardSize = 420
	local innerMinimap = Instance.new("Frame")
	innerMinimap.Name = "InnerMinimap"
	innerMinimap.AnchorPoint = Vector2.new(0.5, 0.5)
	innerMinimap.Position = UDim2.fromScale(0.5, 0.5)
	innerMinimap.Size = UDim2.fromOffset(boardSize, boardSize)
	innerMinimap.BackgroundTransparency = 1
	innerMinimap.BorderSizePixel = 0
	innerMinimap.ClipsDescendants = true
	innerMinimap.Parent = liveMap
	local innerCorner = Instance.new("UICorner")
	innerCorner.CornerRadius = UDim.new(1, 0)
	innerCorner.Parent = innerMinimap

	local accessRadius = data.accessRadius or 200
	local scale = boardSize / (2 * mapRadius)
	local accessPx = accessRadius * scale * 2
	if accessPx > 0 then
		local accessCircle = Instance.new("Frame")
		accessCircle.Name = "AccessRadius"
		accessCircle.AnchorPoint = Vector2.new(0.5, 0.5)
		accessCircle.Position = UDim2.fromScale(0.5, 0.5)
		accessCircle.Size = UDim2.fromOffset(accessPx, accessPx)
		accessCircle.BackgroundTransparency = 1
		accessCircle.BorderSizePixel = 0
		accessCircle.ZIndex = 3
		accessCircle.Parent = innerMinimap
		local accCorner = Instance.new("UICorner")
		accCorner.CornerRadius = UDim.new(1, 0)
		accCorner.Parent = accessCircle
		local accStroke = Instance.new("UIStroke")
		accStroke.Color = COLOR.AccessRadius
		accStroke.Thickness = 2
		accStroke.Transparency = 0.35
		accStroke.Parent = accessCircle
		table.insert(boardMarkerItems, accessCircle)
	end

	local boundaryPx = boardSize - 4
	local boundaryCircle = Instance.new("Frame")
	boundaryCircle.Name = "MapBoundary"
	boundaryCircle.AnchorPoint = Vector2.new(0.5, 0.5)
	boundaryCircle.Position = UDim2.fromScale(0.5, 0.5)
	boundaryCircle.Size = UDim2.fromOffset(boundaryPx, boundaryPx)
	boundaryCircle.BackgroundTransparency = 1
	boundaryCircle.BorderSizePixel = 0
	boundaryCircle.ZIndex = 3
	boundaryCircle.Parent = innerMinimap
	local bndCorner = Instance.new("UICorner")
	bndCorner.CornerRadius = UDim.new(1, 0)
	bndCorner.Parent = boundaryCircle
	local bndStroke = Instance.new("UIStroke")
	bndStroke.Color = COLOR.MapBoundary
	bndStroke.Thickness = 2
	bndStroke.Transparency = 0.55
	bndStroke.Parent = boundaryCircle
	table.insert(boardMarkerItems, boundaryCircle)

	local function addBoardMarker(worldPos: Vector3, color: Color3, size: number, shape: string)
		local marker = Instance.new("Frame")
		marker.AnchorPoint = Vector2.new(0.5, 0.5)
		marker.Position = boardWorldToMap(worldPos, boardSize)
		marker.Size = UDim2.fromOffset(size, size)
		marker.BackgroundColor3 = color
		marker.BackgroundTransparency = 0
		marker.BorderSizePixel = 0
		marker.ZIndex = 8
		marker.Parent = innerMinimap
		local corner = Instance.new("UICorner")
		corner.CornerRadius = if shape == "square" then UDim.new(0, 2) else UDim.new(1, 0)
		corner.Parent = marker
		local stroke = Instance.new("UIStroke")
		stroke.Color = Color3.fromRGB(255, 255, 255)
		stroke.Thickness = 1.5
		stroke.Transparency = 0.2
		stroke.Parent = marker
		table.insert(boardMarkerItems, marker)
		return marker
	end

	if data.campfirePosition then
		addBoardMarker(data.campfirePosition, COLOR.Campfire, 16, "circle")
	end

	for _, cave in ipairs(data.caves or {}) do
		local color = if cave.state == "Locked" then COLOR.CaveLocked else COLOR.Cave
		addBoardMarker(cave.position, color, 14, "circle")
	end

	for _, facility in ipairs(data.facilities or {}) do
		local color = COLOR.Playground
		if facility.type == "Restroom" then
			color = COLOR.Restroom
		elseif facility.type == "Clinic" then
			color = COLOR.Clinic
		end
		addBoardMarker(facility.position, color, 10, "square")
	end

	for _, building in ipairs(data.buildings or {}) do
		local color = COLOR.Building
		if building.name == "Crashed Plane" then
			color = COLOR.CrashedPlane
		end
		addBoardMarker(building.position, color, 12, "square")
	end

	-- Player marker on board
	local pMarker = Instance.new("Frame")
	pMarker.Name = "BoardPlayerMarker"
	pMarker.AnchorPoint = Vector2.new(0.5, 0.5)
	pMarker.Position = UDim2.fromScale(0.5, 0.5)
	pMarker.Size = UDim2.fromOffset(10, 10)
	pMarker.BackgroundColor3 = COLOR.Player
	pMarker.BorderSizePixel = 0
	pMarker.ZIndex = 15
	pMarker.Parent = innerMinimap
	local pMarkerCorner = Instance.new("UICorner")
	pMarkerCorner.CornerRadius = UDim.new(1, 0)
	pMarkerCorner.Parent = pMarker
	local pMarkerStroke = Instance.new("UIStroke")
	pMarkerStroke.Color = Color3.fromRGB(0, 0, 0)
	pMarkerStroke.Thickness = 1.5
	pMarkerStroke.Parent = pMarker
	boardPlayerMarker = pMarker

	local arrow = Instance.new("TextLabel")
	arrow.Name = "BoardPlayerArrow"
	arrow.AnchorPoint = Vector2.new(0.5, 0.5)
	arrow.Position = UDim2.new(0.5, 0, 0.5, -10)
	arrow.Size = UDim2.fromOffset(14, 18)
	arrow.BackgroundTransparency = 1
	arrow.Font = Enum.Font.GothamBlack
	arrow.Text = "▲"
	arrow.TextColor3 = COLOR.Player
	arrow.TextSize = 14
	arrow.TextXAlignment = Enum.TextXAlignment.Center
	arrow.TextYAlignment = Enum.TextYAlignment.Center
	arrow.Rotation = 0
	arrow.ZIndex = 14
	arrow.Parent = innerMinimap
	boardPlayerArrow = arrow

	-- Small compass labels on the board (E/W swapped because back face mirrors X)
	local labels = { { n = "N", x = 0.5, y = 0.02 }, { n = "W", x = 0.96, y = 0.5 }, { n = "S", x = 0.5, y = 0.94 }, { n = "E", x = 0.02, y = 0.5 } }
	for _, l in ipairs(labels) do
		local label = Instance.new("TextLabel")
		label.AnchorPoint = Vector2.new(0.5, 0.5)
		label.Position = UDim2.new(l.x, 0, l.y, 0)
		label.Size = UDim2.fromOffset(20, 20)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.GothamBold
		label.Text = l.n
		label.TextColor3 = COLOR.CompassText
		label.TextSize = 14
		label.ZIndex = 2
		label.Parent = innerMinimap
	end
end

local function updateBoardPlayerMarker()
	if not boardMinimapFrame or not boardPlayerMarker or not boardPlayerArrow or not campfireWorldPos then
		return
	end
	local character = Players.LocalPlayer.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	if not rootPart or not rootPart:IsA("BasePart") then
		return
	end
	local boardSize = 420
	local mapPos = boardWorldToMap(rootPart.Position, boardSize)
	boardPlayerMarker.Position = mapPos

	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local camera = workspace.CurrentCamera
	local heading: Vector3?
	if humanoid then
		local move = humanoid.MoveDirection
		if move and move.Magnitude > 0.05 then
			heading = Vector3.new(move.X, 0, move.Z).Unit
		end
	end
	if not heading and camera then
		local look = camera.CFrame.LookVector
		if look.Magnitude > 0 then
			heading = Vector3.new(look.X, 0, look.Z).Unit
		end
	end

	if heading then
		-- Back face mirrors X, so negate the X component of the heading angle
		local angleRad = math.atan2(-heading.X, -heading.Z)
		local angleDeg = math.deg(angleRad)
		boardPlayerArrow.Rotation = angleDeg
		local offset = 12
		local dx = math.sin(angleRad) * offset
		local dy = -math.cos(angleRad) * offset
		boardPlayerArrow.Position = UDim2.new(mapPos.X.Scale, mapPos.X.Offset + dx, mapPos.Y.Scale, mapPos.Y.Offset + dy)
	end
end

local function updatePlayerMarker()
	if mapOpen and playerMarker and playerArrow and campfireWorldPos then
		local character = Players.LocalPlayer.Character
		local rootPart = character and character:FindFirstChild("HumanoidRootPart")
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local camera = workspace.CurrentCamera
		if rootPart and rootPart:IsA("BasePart") then
			currentPlayerPos = rootPart.Position
			local mapPos = worldToMap(rootPart.Position)
			playerMarker.Position = mapPos

			local heading: Vector3?
			if humanoid then
				local move = humanoid.MoveDirection
				if move and move.Magnitude > 0.05 then
					heading = Vector3.new(move.X, 0, move.Z).Unit
				end
			end
			if not heading and camera then
				local look = camera.CFrame.LookVector
				if look.Magnitude > 0 then
					heading = Vector3.new(look.X, 0, look.Z).Unit
				end
			end

			if heading then
				local angleRad = math.atan2(heading.X, -heading.Z)
				local angleDeg = math.deg(angleRad)
				playerArrow.Rotation = angleDeg
				local offset = 18
				local dx = math.sin(angleRad) * offset
				local dy = -math.cos(angleRad) * offset
				playerArrow.Position = UDim2.new(mapPos.X.Scale, mapPos.X.Offset + dx, mapPos.Y.Scale, mapPos.Y.Offset + dy)
			end
		end
	end

	-- Always update the board minimap if it exists
	updateBoardPlayerMarker()
end

function openMap(data: { [string]: any })
	buildGui()
	buildMapIcon()
	if not gui or not bgFrame or not panelScale then
		return
	end
	mapData = data
	campfireWorldPos = data.campfirePosition
	mapRadius = data.mapRadius or 1000
	buildMarkers()

	local counts = computeSidebarCounts()
	local bg = gui:FindFirstChild("Background") :: Frame
	buildSidebar(bg:FindFirstChild("Panel") :: Frame, counts)
	updateAccessibleAreaInfo()
	hideTooltip()

	-- Build the live minimap on the physical map board
	buildBoardMinimap(data)

	-- Hide the map icon while the full map is open
	if mapIconGui then
		mapIconGui.Enabled = false
	end

	-- Smooth open animation
	gui.Enabled = true
	mapOpen = true
	panelScale.Scale = 0.85
	bgFrame.BackgroundTransparency = 1
	TweenService:Create(panelScale, TweenInfo.new(0.22, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	TweenService:Create(bgFrame, TweenInfo.new(0.22, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), { BackgroundTransparency = 0.55 }):Play()

	-- Keep the render connection active so the board minimap stays live even when the full map is closed
	if not renderConnection then
		renderConnection = RunService.RenderStepped:Connect(updatePlayerMarker)
	end
end

function closeMap()
	if not gui or not bgFrame or not panelScale then
		if gui then
			gui.Enabled = false
		end
		mapOpen = false
		return
	end

	-- Smooth close animation
	local closeTween = TweenService:Create(panelScale, TweenInfo.new(0.18, Enum.EasingStyle.Quart, Enum.EasingDirection.In), { Scale = 0.85 })
	local fadeTween = TweenService:Create(bgFrame, TweenInfo.new(0.18, Enum.EasingStyle.Quart, Enum.EasingDirection.In), { BackgroundTransparency = 1 })
	closeTween:Play()
	fadeTween:Play()

	mapOpen = false
	-- Do NOT disconnect renderConnection here; the board minimap should stay live

	closeTween.Completed:Connect(function()
		if not mapOpen then
			gui.Enabled = false
			-- Show the map icon again
			setMapIconVisible(true)
		end
	end)
end

local function showLockedMessage()
	buildGui()
	buildMapIcon()
	if not gui then
		return
	end

	local bg = gui:FindFirstChild("Background") :: Frame
	local panel = bg:FindFirstChild("Panel") :: Frame
	if not panel then
		return
	end

	local existing = panel:FindFirstChild("LockedMessage")
	if existing then
		existing:Destroy()
	end

	local msg = Instance.new("TextLabel")
	msg.Name = "LockedMessage"
	msg.AnchorPoint = Vector2.new(0.5, 0.5)
	msg.Position = UDim2.fromScale(0.5, 0.5)
	msg.Size = UDim2.fromOffset(360, 80)
	msg.BackgroundColor3 = Color3.fromRGB(40, 32, 26)
	msg.BackgroundTransparency = 0.08
	msg.Font = Enum.Font.GothamBold
	msg.Text = "You need to craft the Map first!\nVisit the Crafting Bench."
	msg.TextColor3 = Color3.fromRGB(240, 230, 200)
	msg.TextSize = 18
	msg.TextWrapped = true
	msg.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	msg.TextStrokeTransparency = 0.3
	msg.ZIndex = 50
	msg.Parent = panel
	local msgCorner = Instance.new("UICorner")
	msgCorner.CornerRadius = UDim.new(0, 10)
	msgCorner.Parent = msg
	local msgStroke = Instance.new("UIStroke")
	msgStroke.Color = Color3.fromRGB(180, 100, 60)
	msgStroke.Thickness = 2
	msgStroke.Parent = msg

	if mapIconGui then
		mapIconGui.Enabled = false
	end
	gui.Enabled = true
	mapOpen = true
	task.delay(2.5, function()
		if gui and gui.Enabled and mapOpen then
			closeMap()
		end
		msg:Destroy()
	end)
end

-- // INITIALIZATION // --

function MapController:KnitStart()
	if not ServerRole.IsGameServer() then return end
	mapService = Knit.GetService("MapService")
	local runStateService = Knit.GetService("RunStateService")

	buildGui()
	buildMapIcon()
	if gui then
		gui.Enabled = false
	end
	setMapIconVisible(false)

	-- Try to build the live board minimap if map data is already available
	mapService:GetMapData():andThen(function(data)
		if typeof(data) == "table" then
			buildBoardMinimap(data)
			if not renderConnection then
				renderConnection = RunService.RenderStepped:Connect(updatePlayerMarker)
			end
		end
	end)

	mapService.MapOpened:Connect(function(payload)
		if typeof(payload) ~= "table" then
			return
		end
		if payload.locked == true then
			showLockedMessage()
			return
		end
		mapService:GetMapData():andThen(function(data)
			if typeof(data) == "table" then
				openMap(data)
			end
		end):catch(function()
			if mapData then
				openMap(mapData)
			end
		end)
	end)

	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then
			return
		end
		if input.KeyCode == Enum.KeyCode.Escape and mapOpen then
			closeMap()
		elseif input.KeyCode == Enum.KeyCode.M then
			if mapOpen then
				closeMap()
			elseif mapService then
				mapService:GetMapData():andThen(function(data)
					if typeof(data) == "table" then
						openMap(data)
					end
				end)
			end
		end
	end)

	runStateService.RunPhaseChanged:Connect(function(payload)
		if typeof(payload) == "table" and payload.phase == "Lobby" then
			closeMap()
			if renderConnection then
				renderConnection:Disconnect()
				renderConnection = nil
			end
			if boardMinimapFrame then
				boardMinimapFrame:Destroy()
				boardMinimapFrame = nil
				boardPlayerMarker = nil
				boardPlayerArrow = nil
					table.clear(boardMarkerItems)
			end
			if mapIconGui then
				mapIconGui.Enabled = false
			end
		end
	end)
end

return MapController
