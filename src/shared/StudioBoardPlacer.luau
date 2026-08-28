--[[
    @file    StudioBoardPlacer.luau
    @author  manik
    @date    2026

    @summary
    Run this snippet in the Roblox Studio Command Bar to create the
    MissingChildrenBoard and MapBoard in the open place. The boards
    are placed in a Workspace.Boards folder, so they persist when you
    save the place. You can then move/resize them in Studio.

    @usage
    1. Open the place in Studio (build.rbxl or 67nights-phase4-final.rbxlx).
    2. Make sure the Base-map (with the Bonfire / campfire) is loaded.
    3. Go to View -> Command Bar.
    4. Copy the entire contents of this file.
    5. Paste into the Command Bar and press Enter.
    6. A Workspace.Boards folder with MapBoard and MissingChildrenBoard appears.
    7. Move the boards wherever you want, then press Ctrl+S to save.

    @note
    Do NOT use this file in a running game. It is only for the Studio
    Command Bar (edit mode).
]]

local workspace = game:GetService("Workspace")

local function findCampfireCenter(): Vector3?
	-- Try to find the campfire anchor created by the game
	local campfire = workspace:FindFirstChild("Campfire")
	if campfire and campfire:IsA("BasePart") then
		return campfire.Position
	end
	-- Try to find a part named "Campfire" inside Base-map
	local baseMap = workspace:FindFirstChild("Base-map")
	if baseMap then
		local part = baseMap:FindFirstChild("Campfire", true)
		if part and part:IsA("BasePart") then
			return part.Position
		end
		local bonfire = baseMap:FindFirstChild("Bonfire", true)
		if bonfire then
			local firePart = bonfire:FindFirstChildWhichIsA("BasePart", true)
			if firePart then
				return firePart.Position
			end
		end
	end
	-- Fallback: origin
	return Vector3.new(0, 0, 0)
end

local function createBoardPart(name: string, size: Vector3, color: Color3, cframe: CFrame, parent: Instance): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Anchored = true
	part.Material = Enum.Material.WoodPlanks
	part.Color = color
	part.CFrame = cframe
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

local function createPosterBoardModel(center: Vector3): Model
	local model = Instance.new("Model")
	model.Name = "MissingChildrenBoard"

	local boardCFrame = CFrame.new(center + Vector3.new(28, 7, 0)) * CFrame.Angles(0, math.rad(90), 0)

	local board = createBoardPart(
		"BoardPanel",
		Vector3.new(18, 9, 0.6),
		Color3.fromRGB(95, 65, 38),
		boardCFrame,
		model
	)

	createBoardPart(
		"LeftPost",
		Vector3.new(0.8, 16, 0.8),
		Color3.fromRGB(75, 50, 28),
		boardCFrame * CFrame.new(-9, -3.5, 0),
		model
	)

	createBoardPart(
		"RightPost",
		Vector3.new(0.8, 16, 0.8),
		Color3.fromRGB(75, 50, 28),
		boardCFrame * CFrame.new(9, -3.5, 0),
		model
	)

	createBoardPart(
		"TopBar",
		Vector3.new(19, 1, 0.9),
		Color3.fromRGB(75, 50, 28),
		boardCFrame * CFrame.new(0, 5.2, 0),
		model
	)

	model.PrimaryPart = board
	return model
end

local function createMapBoardModel(center: Vector3): Model
	local model = Instance.new("Model")
	model.Name = "MapBoard"

	local boardCFrame = CFrame.new(center + Vector3.new(-28, 7, 0)) * CFrame.Angles(0, math.rad(-90), 0)

	local board = createBoardPart(
		"BoardPanel",
		Vector3.new(14, 9, 0.6),
		Color3.fromRGB(95, 65, 38),
		boardCFrame,
		model
	)

	createBoardPart(
		"LeftPost",
		Vector3.new(0.8, 16, 0.8),
		Color3.fromRGB(75, 50, 28),
		boardCFrame * CFrame.new(-7, -3.5, 0),
		model
	)

	createBoardPart(
		"RightPost",
		Vector3.new(0.8, 16, 0.8),
		Color3.fromRGB(75, 50, 28),
		boardCFrame * CFrame.new(7, -3.5, 0),
		model
	)

	createBoardPart(
		"TopBar",
		Vector3.new(15, 1, 0.9),
		Color3.fromRGB(75, 50, 28),
		boardCFrame * CFrame.new(0, 5.2, 0),
		model
	)

	model.PrimaryPart = board
	return model
end

-- Main
local boardsFolder = workspace:FindFirstChild("Boards")
if not boardsFolder then
	boardsFolder = Instance.new("Folder")
	boardsFolder.Name = "Boards"
	boardsFolder.Parent = workspace
end

local existingPoster = boardsFolder:FindFirstChild("MissingChildrenBoard")
if existingPoster then
	existingPoster:Destroy()
end

local existingMap = boardsFolder:FindFirstChild("MapBoard")
if existingMap then
	existingMap:Destroy()
end

local campfireCenter = findCampfireCenter()
createPosterBoardModel(campfireCenter).Parent = boardsFolder
createMapBoardModel(campfireCenter).Parent = boardsFolder

print("Boards placed! Move them in Workspace.Boards, then save the place (Ctrl+S).")
