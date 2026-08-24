--[[
    @file    BuildingController.luau
    @author  manik
    @date    2025

    @summary
    Cross-platform local placement preview and building controls.

    @description
    The client renders only a footprint ghost and requests placement.
    BuildingService recomputes ground, snap, zone, overlap, range, cap,
    token ownership, and the final authoritative CFrame.
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
local Janitor = require(ReplicatedStorage.Packages.Janitor)
local StructureConfig = require(ReplicatedStorage.Shared.StructureConfig)

-- | Objects | --
local BuildingController = Knit.CreateController({
	Name = "BuildingController",
})
local janitor = Janitor.new()
local placementJanitor = Janitor.new()

-- | Configuration | --
local ACTION_ROTATE = "RotateStructure"
local ACTION_PLACE = "PlaceStructure"
local ACTION_CANCEL = "CancelStructure"
local ROTATION_STEP = math.rad(15)
local RAY_DISTANCE = 500
local VALID_COLOR = Color3.fromRGB(85, 210, 105)
local INVALID_COLOR = Color3.fromRGB(225, 70, 65)

-- | State Management | --
local craftingService: any = nil
local buildingService: any = nil
local activeToken: string? = nil
local activeStructureId: string? = nil
local ghost: Part? = nil
local currentCFrame: CFrame? = nil
local currentValid = false
local yaw = 0
local requestPending = false
local statusGui: ScreenGui? = nil
local statusLabel: TextLabel? = nil

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
	label.Parent = screenGui
	statusLabel = label
	local constraint = Instance.new("UISizeConstraint")
	constraint.MaxSize = Vector2.new(580, 58)
	constraint.Parent = label
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = label
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
    @summary  Update the local placement ghost from the current view ray.
]]
local function updateGhost()
	if not ghost or not activeStructureId then
		return
	end
	local ray = viewportRay()
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local exclusions = { ghost }
	if Players.LocalPlayer.Character then
		table.insert(exclusions, Players.LocalPlayer.Character)
	end
	params.FilterDescendantsInstances = exclusions
	local result = workspace:Raycast(ray.Origin, ray.Direction * RAY_DISTANCE, params)
	if not result then
		currentValid = false
		ghost.Color = INVALID_COLOR
		setStatus("No valid ground  •  Rotate: R / shoulder  •  Cancel: Esc / B", false)
		return
	end

	local definition = StructureConfig[activeStructureId]
	local y = result.Position.Y + definition.Footprint.Y * 0.5
	currentCFrame = CFrame.new(result.Position.X, y, result.Position.Z) * CFrame.Angles(0, yaw, 0)
	ghost.CFrame = currentCFrame
	local rootPart = Players.LocalPlayer.Character and Players.LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
	currentValid = rootPart ~= nil and (rootPart.Position - result.Position).Magnitude <= 35
	ghost.Color = if currentValid then VALID_COLOR else INVALID_COLOR
	local statusText = if currentValid then "  •  Place: click / A" else "  •  Move closer to place"
	setStatus(definition.DisplayName .. statusText, currentValid)
end

--[[
    @summary  End local placement and remove all temporary controls.
]]
local function stopPlacement()
	placementJanitor:Cleanup()
	ContextActionService:UnbindAction(ACTION_ROTATE)
	ContextActionService:UnbindAction(ACTION_PLACE)
	ContextActionService:UnbindAction(ACTION_CANCEL)
	activeToken = nil
	activeStructureId = nil
	ghost = nil
	currentCFrame = nil
	currentValid = false
	requestPending = false
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
	if actionName == ACTION_ROTATE then
		yaw += ROTATION_STEP
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

	ghost = Instance.new("Part")
	ghost.Name = "PlacementGhost"
	ghost.Size = definition.Footprint
	ghost.Anchored = true
	ghost.CanCollide = false
	ghost.CanQuery = false
	ghost.CanTouch = false
	ghost.Material = Enum.Material.ForceField
	ghost.Transparency = 0.55
	ghost.Color = INVALID_COLOR
	ghost.Parent = workspace
	placementJanitor:Add(ghost)
	placementJanitor:Add(RunService.RenderStepped:Connect(updateGhost), "Disconnect")

	ContextActionService:BindAction(ACTION_ROTATE, onPlacementAction, true, Enum.KeyCode.R, Enum.KeyCode.Q, Enum.KeyCode.ButtonR1)
	ContextActionService:BindAction(ACTION_PLACE, onPlacementAction, true, Enum.KeyCode.Return, Enum.KeyCode.ButtonA)
	ContextActionService:BindAction(ACTION_CANCEL, onPlacementAction, true, Enum.KeyCode.Escape, Enum.KeyCode.ButtonB)
	ContextActionService:SetTitle(ACTION_ROTATE, "Rotate")
	ContextActionService:SetTitle(ACTION_PLACE, "Place")
	ContextActionService:SetTitle(ACTION_CANCEL, "Cancel")
	ContextActionService:SetPosition(ACTION_ROTATE, UDim2.new(1, -180, 1, -170))
	ContextActionService:SetPosition(ACTION_PLACE, UDim2.new(1, -95, 1, -170))
	ContextActionService:SetPosition(ACTION_CANCEL, UDim2.new(1, -95, 1, -95))

	statusGui.Enabled = true
	setStatus(definition.DisplayName .. "  •  Select valid ground", false)
end

-- // INITIALIZATION // --

function BuildingController:KnitStart()
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
