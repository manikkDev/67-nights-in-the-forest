--[[
    @file    BuildingController.luau
    @author  manik
    @date    2025

    @summary
    Cross-platform local placement preview and building controls.

    @description
    The client renders an exact semi-transparent clone of the structure
    template as a placement preview, with a directional arrow indicator
    and a footprint wireframe box. BuildingService recomputes ground,
    snap, zone, overlap, range, cap, token ownership, and the final
    authoritative CFrame.

    Rotation controls:
      - R : rotate clockwise
      - Q : rotate counter-clockwise
      - Mouse scroll wheel : rotate clockwise / counter-clockwise
      - Gamepad ButtonR1 / ButtonL1 : rotate clockwise / counter-clockwise
]]

-- // VARIABLES // --

-- | Services | --
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")

-- | Modules | --
local Knit = require(ReplicatedStorage.Packages.Knit)
local ServerRole = require(ReplicatedStorage.Shared.ServerRole)
local Janitor = require(ReplicatedStorage.Packages.Janitor)
local StructureConfig = require(ReplicatedStorage.Shared.StructureConfig)

-- | Objects | --
local BuildingController = Knit.CreateController({
	Name = "BuildingController",
})
local janitor = Janitor.new()
local placementJanitor = Janitor.new()

-- | Configuration | --
local ACTION_ROTATE_CW = "RotateStructureCW"
local ACTION_ROTATE_CCW = "RotateStructureCCW"
local ACTION_PLACE = "PlaceStructure"
local ACTION_CANCEL = "CancelStructure"
local ROTATION_STEP = math.rad(15)
local RAY_DISTANCE = 500
local VALID_COLOR = Color3.fromRGB(85, 210, 105)
local INVALID_COLOR = Color3.fromRGB(225, 70, 65)
local ARROW_COLOR = Color3.fromRGB(255, 220, 60)
local ARROW_LENGTH = 6
local ARROW_THICKNESS = 0.8
local GHOST_TRANSPARENCY = 0.5
local Y_SMOOTH_LERP = 0.25 -- smoothing factor for Y position
local Y_LIFT = 0.05 -- tiny lift so the model sits almost exactly on the ground

-- | State Management | --
local craftingService: any = nil
local buildingService: any = nil
local activeToken: string? = nil
local activeStructureId: string? = nil
local ghostModel: Model? = nil -- the actual template clone for visual preview
local ghostBox: Part? = nil -- wireframe footprint box
local ghostArrow: Part? = nil -- directional arrow
local ghostArrowTip: Part? = nil -- arrow tip ball
local currentCFrame: CFrame? = nil
local currentValid = false
local yaw = 0
local requestPending = false
local statusGui: ScreenGui? = nil
local statusLabel: TextLabel? = nil
local hintLabel: TextLabel? = nil
local smoothedY = nil -- for Y position smoothing

-- // FUNCTIONS // --

--[[
    @summary  Set placement status text and color.
    @param    text     string
    @param    isValid  boolean
]]
local function setStatus(text: string, isValid: boolean)
	if not statusLabel then
		return
	end
	statusLabel.Text = text
	statusLabel.TextColor3 = if isValid then VALID_COLOR else INVALID_COLOR
end

--[[
    @summary  Build the placement status overlay once.
]]
local function buildStatusUi()
	if statusGui then
		return
	end
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "BuildingPlacementGui"
	screenGui.ResetOnSpawn = false
	screenGui.Enabled = false
	screenGui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	statusGui = screenGui

	-- Main status label (bottom center)
	local label = Instance.new("TextLabel")
	label.AnchorPoint = Vector2.new(0.5, 1)
	label.Position = UDim2.new(0.5, 0, 1, -100)
	label.Size = UDim2.new(0.8, 0, 0, 58)
	label.BackgroundColor3 = Color3.fromRGB(18, 18, 22)
	label.BackgroundTransparency = 0.15
	label.Font = Enum.Font.GothamBold
	label.TextColor3 = VALID_COLOR
	label.TextSize = 17
	label.TextWrapped = true
	label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	label.TextStrokeTransparency = 0.3
	label.Parent = screenGui
	statusLabel = label
	local constraint = Instance.new("UISizeConstraint")
	constraint.MaxSize = Vector2.new(580, 58)
	constraint.Parent = label
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = label

	-- Persistent hint label (above the status, shows controls)
	local hint = Instance.new("TextLabel")
	hint.AnchorPoint = Vector2.new(0.5, 1)
	hint.Position = UDim2.new(0.5, 0, 1, -165)
	hint.Size = UDim2.new(0.8, 0, 0, 32)
	hint.BackgroundColor3 = Color3.fromRGB(18, 18, 22)
	hint.BackgroundTransparency = 0.4
	hint.Font = Enum.Font.GothamBold
	hint.TextColor3 = Color3.fromRGB(200, 200, 210)
	hint.TextSize = 14
	hint.TextWrapped = true
	hint.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	hint.TextStrokeTransparency = 0.4
	hint.Text = "Rotate: R / Q  •  Place: Click / Enter  •  Cancel: X"
	hint.Parent = screenGui
	hintLabel = hint
	local hintConstraint = Instance.new("UISizeConstraint")
	hintConstraint.MaxSize = Vector2.new(580, 32)
	hintConstraint.Parent = hint
	local hintCorner = Instance.new("UICorner")
	hintCorner.CornerRadius = UDim.new(0, 8)
	hintCorner.Parent = hint
end

--[[
    @summary  Return the pointer or screen-center ground ray.
    @returns  Ray
]]
local function viewportRay(): Ray
	local camera = workspace.CurrentCamera
	local location = UserInputService:GetMouseLocation()
	if UserInputService.GamepadEnabled and not UserInputService.MouseEnabled then
		location = camera.ViewportSize * 0.5
	end
	return camera:ViewportPointToRay(location.X, location.Y)
end

--[[
    @summary  Format the current yaw as a human-readable angle string.
    @returns  string
]]
local function formatYaw(): string
	local deg = math.deg(yaw) % 360
	return string.format("%.0f°", deg)
end

--[[
    @summary  Apply transparency and color to all parts in the ghost model.
    @param    model   Model
    @param    color   Color3
]]
local function tintGhostModel(model: Model, color: Color3)
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Transparency = GHOST_TRANSPARENCY
			descendant.Color = color
			descendant.Material = Enum.Material.ForceField
		end
	end
end

--[[
    @summary  Update the local placement ghost from the current view ray.
]]
local function updateGhost()
	if not activeStructureId or not ghostBox then
		return
	end
	local definition = StructureConfig[activeStructureId]
	if not definition then
		return
	end

	local ray = viewportRay()
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local exclusions = { ghostBox }
	if ghostModel then
		table.insert(exclusions, ghostModel)
	end
	if ghostArrow then
		table.insert(exclusions, ghostArrow)
	end
	if ghostArrowTip then
		table.insert(exclusions, ghostArrowTip)
	end
	if Players.LocalPlayer.Character then
		table.insert(exclusions, Players.LocalPlayer.Character)
	end
	params.FilterDescendantsInstances = exclusions
	local result = workspace:Raycast(ray.Origin, ray.Direction * RAY_DISTANCE, params)
	if not result then
		currentValid = false
		ghostBox.Color = INVALID_COLOR
		if ghostModel then
			tintGhostModel(ghostModel, INVALID_COLOR)
		end
		if ghostArrow then
			ghostArrow.Color = INVALID_COLOR
		end
		if ghostArrowTip then
			ghostArrowTip.Color = INVALID_COLOR
		end
		setStatus("No valid ground  •  Facing: " .. formatYaw(), false)
		return
	end

	-- Compute the target Y position: ground + half model height + small lift.
	-- If the preview model has loaded, use its actual bounding box so the
	-- ghost preview matches where the server will place the model.
	local groundY = result.Position.Y
	local halfHeight: number
	local aabbCenterOffset: Vector3
	if ghostModel then
		local aabbCF, aabbSize = ghostModel:GetBoundingBox()
		local modelPivot = ghostModel:GetPivot()
		halfHeight = aabbSize.Y * 0.5
		aabbCenterOffset = aabbCF.Position - modelPivot.Position
	else
		halfHeight = definition.Footprint.Y * 0.5
		aabbCenterOffset = Vector3.new(0, 0, 0)
	end
	local targetY = groundY + halfHeight + Y_LIFT

	-- Smooth the Y position to prevent jitter from uneven terrain
	if smoothedY == nil then
		smoothedY = targetY
	else
		smoothedY = smoothedY + (targetY - smoothedY) * Y_SMOOTH_LERP
	end

	local desiredAabbCenter = Vector3.new(result.Position.X, smoothedY, result.Position.Z)
	local baseCFrame = CFrame.new(desiredAabbCenter) * CFrame.Angles(0, yaw, 0)
	local placedCFrame = CFrame.new(desiredAabbCenter - baseCFrame.Rotation * aabbCenterOffset) * baseCFrame.Rotation
	currentCFrame = placedCFrame

	-- Update the footprint wireframe box
	ghostBox.CFrame = placedCFrame

	-- Update the actual model preview
	if ghostModel then
		ghostModel:PivotTo(placedCFrame)
	end

	-- Position the arrow indicator in front of the ghost (pointing in the -Z direction)
	if ghostArrow then
		local arrowOffset = Vector3.new(0, 0, -(definition.Footprint.Z * 0.5 + ARROW_LENGTH * 0.5))
		ghostArrow.CFrame = placedCFrame * CFrame.new(arrowOffset)
	end

	-- Position the arrow tip (ball) at the very front
	if ghostArrowTip then
		local tipOffset = Vector3.new(0, 0, -(definition.Footprint.Z * 0.5 + ARROW_LENGTH))
		ghostArrowTip.CFrame = placedCFrame * CFrame.new(tipOffset)
	end

	-- Validate placement
	local rootPart = Players.LocalPlayer.Character and Players.LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
	currentValid = rootPart ~= nil and (rootPart.Position - result.Position).Magnitude <= 35

	local ghostColor = if currentValid then VALID_COLOR else INVALID_COLOR
	ghostBox.Color = ghostColor
	if ghostModel then
		tintGhostModel(ghostModel, ghostColor)
	end
	if ghostArrow then
		ghostArrow.Color = if currentValid then ARROW_COLOR else INVALID_COLOR
	end
	if ghostArrowTip then
		ghostArrowTip.Color = if currentValid then ARROW_COLOR else INVALID_COLOR
	end

	local statusText = if currentValid then "  •  Place: click / A" else "  •  Move closer to place"
	setStatus(definition.DisplayName .. "  •  Facing: " .. formatYaw() .. statusText, currentValid)
end

--[[
    @summary  End local placement and remove all temporary controls.
]]
local function stopPlacement()
	placementJanitor:Cleanup()
	ContextActionService:UnbindAction(ACTION_ROTATE_CW)
	ContextActionService:UnbindAction(ACTION_ROTATE_CCW)
	ContextActionService:UnbindAction(ACTION_PLACE)
	ContextActionService:UnbindAction(ACTION_CANCEL)
	activeToken = nil
	activeStructureId = nil
	ghostModel = nil
	ghostBox = nil
	ghostArrow = nil
	ghostArrowTip = nil
	currentCFrame = nil
	currentValid = false
	requestPending = false
	smoothedY = nil
	if statusGui then
		statusGui.Enabled = false
	end
end

--[[
    @summary  Send the current token and preview transform for validation.
]]
local function requestPlacement()
	if requestPending or not activeToken or not currentCFrame or not currentValid then
		return
	end
	requestPending = true
	setStatus("Placing...", true)
	buildingService:RequestPlace(activeToken, currentCFrame):andThen(function(result)
		requestPending = false
		if typeof(result) == "table" and result.ok == true then
			stopPlacement()
		else
			local code = if typeof(result) == "table" then result.code else "REJECTED"
			setStatus("Cannot place: " .. tostring(code), false)
		end
	end):catch(function()
		requestPending = false
		setStatus("Placement request failed", false)
	end)
end

--[[
    @summary  Handle bound rotate, place, and cancel actions.
    @param    actionName  string
    @param    inputState  UserInputState
    @returns  ContextActionResult
]]
local function onPlacementAction(actionName: string, inputState: Enum.UserInputState): Enum.ContextActionResult
	if inputState ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Sink
	end
	if actionName == ACTION_ROTATE_CW then
		yaw += ROTATION_STEP
	elseif actionName == ACTION_ROTATE_CCW then
		yaw -= ROTATION_STEP
	elseif actionName == ACTION_PLACE then
		requestPlacement()
	elseif actionName == ACTION_CANCEL then
		stopPlacement()
	end
	return Enum.ContextActionResult.Sink
end

--[[
    @summary  Begin previewing one crafted structure token.
    @param    tokenId      string
    @param    structureId  string
]]
local function startPlacement(tokenId: string, structureId: string)
	local definition = StructureConfig[structureId]
	if not definition then
		return
	end
	stopPlacement()
	buildStatusUi()
	activeToken = tokenId
	activeStructureId = structureId
	yaw = 0
	smoothedY = nil

	-- Create the footprint wireframe box (shows the placement bounds)
	local box = Instance.new("Part")
	box.Name = "PlacementGhostBox"
	box.Size = definition.Footprint
	box.Anchored = true
	box.CanCollide = false
	box.CanQuery = false
	box.CanTouch = false
	box.Material = Enum.Material.ForceField
	box.Transparency = 0.7
	box.Color = INVALID_COLOR
	box.Parent = workspace
	ghostBox = box
	placementJanitor:Add(box)

	-- Request the actual template model from the server for visual preview
	buildingService:GetPreviewModel(structureId):andThen(function(model)
		if not activeToken or typeof(model) ~= "Instance" or not model:IsA("Model") then
			return
		end
		-- The server parents it to the player; move it to workspace
		model.Parent = workspace
		ghostModel = model
		placementJanitor:Add(model)
		-- Apply initial tint
		tintGhostModel(model, INVALID_COLOR)
	end):catch(function()
		-- If the server call fails, we still have the wireframe box
	end)

	-- Create the directional arrow indicator
	local arrow = Instance.new("Part")
	arrow.Name = "PlacementArrow"
	arrow.Size = Vector3.new(ARROW_THICKNESS, ARROW_THICKNESS, ARROW_LENGTH)
	arrow.Anchored = true
	arrow.CanCollide = false
	arrow.CanQuery = false
	arrow.CanTouch = false
	arrow.Material = Enum.Material.Neon
	arrow.Transparency = 0.2
	arrow.Color = ARROW_COLOR
	arrow.Parent = workspace
	ghostArrow = arrow
	placementJanitor:Add(arrow)

	-- Create the arrow tip (ball)
	local arrowTip = Instance.new("Part")
	arrowTip.Name = "PlacementArrowTip"
	arrowTip.Shape = Enum.PartType.Ball
	arrowTip.Size = Vector3.new(ARROW_THICKNESS * 2.5, ARROW_THICKNESS * 2.5, ARROW_THICKNESS * 2.5)
	arrowTip.Anchored = true
	arrowTip.CanCollide = false
	arrowTip.CanQuery = false
	arrowTip.CanTouch = false
	arrowTip.Material = Enum.Material.Neon
	arrowTip.Transparency = 0.2
	arrowTip.Color = ARROW_COLOR
	arrowTip.Parent = workspace
	ghostArrowTip = arrowTip
	placementJanitor:Add(arrowTip)

	placementJanitor:Add(RunService.RenderStepped:Connect(updateGhost), "Disconnect")

	-- Bind rotation actions — CW and CCW separately
	ContextActionService:BindAction(ACTION_ROTATE_CW, onPlacementAction, true, Enum.KeyCode.R, Enum.KeyCode.ButtonR1)
	ContextActionService:BindAction(ACTION_ROTATE_CCW, onPlacementAction, true, Enum.KeyCode.Q, Enum.KeyCode.ButtonL1)
	ContextActionService:BindAction(ACTION_PLACE, onPlacementAction, true, Enum.KeyCode.Return, Enum.KeyCode.ButtonA)
	ContextActionService:BindAction(ACTION_CANCEL, onPlacementAction, true, Enum.KeyCode.X, Enum.KeyCode.ButtonB)
	ContextActionService:SetTitle(ACTION_ROTATE_CW, "Rotate →")
	ContextActionService:SetTitle(ACTION_ROTATE_CCW, "Rotate ←")
	ContextActionService:SetTitle(ACTION_PLACE, "Place")
	ContextActionService:SetTitle(ACTION_CANCEL, "Cancel")
	ContextActionService:SetPosition(ACTION_ROTATE_CW, UDim2.new(1, -260, 1, -170))
	ContextActionService:SetPosition(ACTION_ROTATE_CCW, UDim2.new(1, -180, 1, -170))
	ContextActionService:SetPosition(ACTION_PLACE, UDim2.new(1, -95, 1, -170))
	ContextActionService:SetPosition(ACTION_CANCEL, UDim2.new(1, -95, 1, -95))

	if statusGui then
		statusGui.Enabled = true
	end
	setStatus(definition.DisplayName .. "  •  Facing: " .. formatYaw() .. "  •  Rotate: R / Q", false)
end

-- // INITIALIZATION // --

function BuildingController:KnitStart()
	if ServerRole.IsLobby() then return end
	craftingService = Knit.GetService("CraftingService")
	buildingService = Knit.GetService("BuildingService")
	buildStatusUi()

	janitor:Add(craftingService.CraftSucceeded:Connect(function(_recipeId, result)
		if typeof(result) == "table"
			and result.outputKind == "Placement"
			and typeof(result.placementToken) == "string"
			and typeof(result.outputId) == "string"
		then
			startPlacement(result.placementToken, result.outputId)
		end
	end), "Disconnect")

	-- Mouse click to place
	janitor:Add(UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed or not activeToken then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			requestPlacement()
		end
	end), "Disconnect")
end

return BuildingController
