--[[
    @file    CarryController.luau
    @author  manik
    @date    2025

    @summary
    Cursor-aimed F-key pickup and drop for resource items.

    @description
    Raycasts from the camera through the mouse/center of the screen. When
    the player presses F while pointing at a pickup-able item within range,
    it fires the appropriate server remote to add one unit to their bag
    and destroy the world item. Pressing F while NOT looking at a valid
    target drops all carried items at the player's feet. The inventory UI
    is updated automatically by the server's ResourcesChanged signal.

    Hovering over a world item with the cursor highlights it and shows a
    floating label with the item name and the F-key prompt.

    @exports
    - CarryController (Knit Controller)
]]

-- // VARIABLES // --

-- | Services | --
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

-- | Modules | --
local Knit = require(ReplicatedStorage.Packages.Knit)

-- | Objects | --
local CarryController = Knit.CreateController({
	Name = "CarryController",
})

-- | Configuration | --
local PICKUP_KEY = Enum.KeyCode.F
local PICKUP_RANGE = 12
local PICKUP_COOLDOWN = 0.2
local RAY_LENGTH = 32
local HOVER_EMISSIVE = Color3.fromRGB(160, 220, 255)

-- | State Management | --
local localPlayer = Players.LocalPlayer
local gameStateController: any = nil
local harvestService: any = nil
local forageService: any = nil
local inventoryService: any = nil
local lastPickupTime = 0
local hoveredModel: Model? = nil
local hoverHighlight: Highlight? = nil
local hoverNameGui: BillboardGui? = nil

local draggingModel: Model? = nil
local draggingResourceName: string? = nil
local dragTarget: BasePart? = nil
local lastDragTargetSent = 0

-- // FUNCTIONS // --

--[[
    @summary  Walk up an instance's parent chain to find the pickup model.
    @returns  Model?, string?  -- the pickup model and the resource name
]]
local function findPickupModel(instance: Instance): (Model?, string?)
	local current = instance
	while current do
		if current:IsA("Model") then
			local resource = current:GetAttribute("Resource")
			local wood = current:GetAttribute("PickupResource")
			local forage = current:GetAttribute("ForageResource")
			local name = resource or wood or forage
			if name and typeof(name) == "string" then
				return current, name
			end
		end
		current = current.Parent
	end
	return nil, nil
end

--[[
    @summary  Get the current camera and build a ray from it through the mouse.
    @returns  BasePart?, Vector3?  -- hit part and world position
]]
local function getMouseRay(): (BasePart?, Vector3?)
	local camera = workspace.CurrentCamera
	if not camera then
		return nil
	end

	local localPlayer = Players.LocalPlayer
	local character = localPlayer and localPlayer.Character
	local mousePos = UserInputService:GetMouseLocation()
	local ray = camera:ViewportPointToRay(mousePos.X, mousePos.Y, 0)

	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	local filterList = {}
	if character then
		table.insert(filterList, character)
	end
	raycastParams.FilterDescendantsInstances = filterList

	local result = workspace:Raycast(ray.Origin, ray.Direction * RAY_LENGTH, raycastParams)
	if not result then
		return nil
	end
	return result.Instance, result.Position
end

--[[
    @summary  Check whether the mouse cursor is currently over any UI element.
    @returns  boolean
]]
local function isMouseOverGui(): boolean
	local mouse = UserInputService:GetMouseLocation()
	local playerGui = localPlayer:FindFirstChild("PlayerGui")
	if not playerGui then
		return false
	end
	local objects = playerGui:GetGuiObjectsAtPosition(mouse.X, mouse.Y)
	for _, gui in ipairs(objects) do
		if gui:IsA("GuiObject") and gui.Visible then
			return true
		end
	end
	return false
end

--[[
    @summary  Check whether the player is close enough to the pickup target.
    @returns  boolean
]]
local function isInRange(model: Model): boolean
	local localPlayer = Players.LocalPlayer
	local character = localPlayer and localPlayer.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	if not rootPart or not rootPart:IsA("BasePart") then
		return false
	end

	local targetPos = model:GetPivot().Position
	return (rootPart.Position - targetPos).Magnitude <= PICKUP_RANGE
end

--[[
    @summary  Find the best BasePart in a model to use as the hover anchor.
    @returns  BasePart?
]]
local function getModelAnchor(model: Model): BasePart?
	if model.PrimaryPart then
		return model.PrimaryPart
	end
	return model:FindFirstChildWhichIsA("BasePart", true)
end

--[[
    @summary  Remove the current hover highlight and label.
]]
local function clearHover()
	if hoverHighlight then
		hoverHighlight:Destroy()
		hoverHighlight = nil
	end
	if hoverNameGui then
		hoverNameGui:Destroy()
		hoverNameGui = nil
	end
	hoveredModel = nil
end

--[[
    @summary  Show a soft blue outline and a floating name label on a model.
    @param    model        Model    -- the model to highlight
    @param    resourceName string   -- the display name
]]
local function setHover(model: Model, resourceName: string, promptText: string?)
	promptText = promptText or "[F] Pickup"

	if hoveredModel == model and hoverNameGui then
		local background = hoverNameGui:FindFirstChild("LabelBackground")
		if background then
			local prompt = background:FindFirstChild("PromptLabel")
			if prompt and prompt:IsA("TextLabel") then
				prompt.Text = promptText
			end
		end
		return
	end
	clearHover()
	hoveredModel = model

	local highlight = Instance.new("Highlight") :: Highlight
	highlight.Name = "CarryHoverHighlight"
	highlight.Adornee = model
	highlight.FillColor = HOVER_EMISSIVE
	highlight.OutlineColor = HOVER_EMISSIVE
	highlight.FillTransparency = 0.85
	highlight.OutlineTransparency = 0.3
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.Parent = model
	hoverHighlight = highlight

	local anchor = getModelAnchor(model)
	if not anchor then
		return
	end

	local nameGui = Instance.new("BillboardGui") :: BillboardGui
	nameGui.Name = "CarryHoverLabel"
	nameGui.Adornee = anchor
	nameGui.Size = UDim2.new(0, 220, 0, 52)
	nameGui.SizeOffset = Vector2.new(0, 0.5)
	nameGui.StudsOffset = Vector3.new(0, 2.2, 0)
	nameGui.AlwaysOnTop = true
	nameGui.ClipsDescendants = false
	nameGui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	hoverNameGui = nameGui

	local background = Instance.new("Frame")
	background.Name = "LabelBackground"
	background.Size = UDim2.new(1, 0, 1, 0)
	background.BackgroundColor3 = Color3.fromRGB(32, 34, 40)
	background.BackgroundTransparency = 0.15
	background.BorderSizePixel = 0
	background.Parent = nameGui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = background

	local stroke = Instance.new("UIStroke")
	stroke.Color = HOVER_EMISSIVE
	stroke.Thickness = 1.5
	stroke.Parent = background

	local label = Instance.new("TextLabel")
	label.Name = "NameLabel"
	label.Size = UDim2.new(1, -8, 0.55, 0)
	label.Position = UDim2.new(0, 4, 0, 4)
	label.BackgroundTransparency = 1
	label.Text = resourceName
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.Font = Enum.Font.GothamBold
	label.TextSize = 18
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.Parent = background

	local prompt = Instance.new("TextLabel")
	prompt.Name = "PromptLabel"
	prompt.Size = UDim2.new(1, -8, 0.4, 0)
	prompt.Position = UDim2.new(0, 4, 0.55, 0)
	prompt.BackgroundTransparency = 1
	prompt.Text = promptText
	prompt.TextColor3 = Color3.fromRGB(180, 220, 255)
	prompt.Font = Enum.Font.GothamBold
	prompt.TextSize = 14
	prompt.TextXAlignment = Enum.TextXAlignment.Center
	prompt.TextYAlignment = Enum.TextYAlignment.Center
	prompt.Parent = background
end

--[[
    @summary  Release the currently dragged item.
]]
local function stopDrag()
	if inventoryService then
		inventoryService:RequestDragStop()
	end
	draggingModel = nil
	draggingResourceName = nil
	dragTarget = nil
end

--[[
    @summary  Move the invisible drag target to the current mouse position in 3D space.
]]
local function updateDragTarget()
	if not dragTarget or not dragTarget.Parent then
		return
	end

	local camera = workspace.CurrentCamera
	if not camera then
		return
	end

	local mousePos = UserInputService:GetMouseLocation()
	local ray = camera:ViewportPointToRay(mousePos.X, mousePos.Y, 0)

	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	local filterList: {Instance} = {}
	if dragTarget then
		table.insert(filterList, dragTarget)
	end
	if draggingModel then
		table.insert(filterList, draggingModel)
	end
	local character = localPlayer.Character
	if character then
		table.insert(filterList, character)
	end
	raycastParams.FilterDescendantsInstances = filterList

	local result = workspace:Raycast(ray.Origin, ray.Direction * RAY_LENGTH, raycastParams)
	local targetPos = result and result.Position or (ray.Origin + ray.Direction * RAY_LENGTH)

	local now = os.clock()
	if now - lastDragTargetSent < 0.03 then
		return
	end
	lastDragTargetSent = now

	if inventoryService then
		inventoryService.DragTargetMoved:Fire(targetPos)
	end
end

--[[
    @summary  Per-frame hover check so items highlight as the cursor moves.
]]
local function updateHover()
	if not gameStateController or not gameStateController:IsInGame() then
		clearHover()
		return
	end

	if draggingModel and draggingResourceName then
		if not draggingModel.Parent then
			stopDrag()
			clearHover()
			return
		end
		setHover(draggingModel, draggingResourceName, "Release [LMB]")
		updateDragTarget()
		return
	end

	if isMouseOverGui() then
		clearHover()
		return
	end

	local instance = getMouseRay()
	if not instance then
		clearHover()
		return
	end

	local model, resourceName = findPickupModel(instance)
	if model and resourceName then
		setHover(model, resourceName, "[LMB] Drag | [F] Pickup")
	else
		clearHover()
	end
end

--[[
    @summary  Try to pick up the item the player is looking at.
    @param    model         Model   -- the hovered pickup model
    @param    resourceName  string  -- resource type on the model
    @returns  boolean  -- true if a remote was fired
]]
local function tryPickup(model: Model, resourceName: string): boolean
	local now = os.clock()
	if now - lastPickupTime < PICKUP_COOLDOWN then
		return false
	end

	if UserInputService:GetFocusedTextBox() then
		return false
	end

	if not isInRange(model) then
		return false
	end

	lastPickupTime = now

	if resourceName == "Wood" and harvestService then
		harvestService:RequestPickup(model)
	elseif resourceName == "Berries" or resourceName == "Mushrooms" then
		if forageService then
			forageService:RequestPickup(model)
		end
	elseif inventoryService then
		inventoryService:RequestPickup(model)
	end

	return true
end

--[[
    @summary  Drop the oldest item the player is currently carrying.
]]
local function dropOne()
	local now = os.clock()
	if now - lastPickupTime < PICKUP_COOLDOWN then
		return
	end
	lastPickupTime = now

	if inventoryService then
		inventoryService:RequestDropOne()
	end
end

--[[
    @summary  Start dragging a world item with LMB.
    @param    model         Model
    @param    resourceName  string
    @returns  boolean
]]
local function startDrag(model: Model, resourceName: string): boolean
	if not isInRange(model) or not inventoryService then
		return false
	end

	local ok = inventoryService:RequestDragStart(model)
	if not ok then
		return false
	end

	draggingModel = model
	draggingResourceName = resourceName

	local targetName = "DragTarget_" .. tostring(localPlayer.UserId)
	local target = workspace:WaitForChild(targetName, 2)
	if target and target:IsA("BasePart") then
		dragTarget = target
		updateDragTarget()
	else
		stopDrag()
		return false
	end
	return true
end

--[[
    @summary  Handle keyboard input for the pickup/drop key.
]]
local function onInputBegan(input: InputObject, gameProcessed: boolean)
	if gameProcessed then
		return
	end
	if not gameStateController or not gameStateController:IsInGame() then
		return
	end

	-- LMB drag start.
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		if isMouseOverGui() then
			return
		end
		if draggingModel then
			return
		end
		if UserInputService:GetFocusedTextBox() then
			return
		end

		local instance = getMouseRay()
		if not instance then
			return
		end

		local model, resourceName = findPickupModel(instance)
		if model and resourceName then
			startDrag(model, resourceName)
		end
		return
	end

	-- F key pickup/drop-one.
	if input.KeyCode ~= PICKUP_KEY then
		return
	end
	if draggingModel then
		return
	end
	if isMouseOverGui() then
		return
	end

	local instance = getMouseRay()
	if not instance then
		dropOne()
		return
	end

	local model, resourceName = findPickupModel(instance)
	if not model or not resourceName then
		dropOne()
		return
	end

	local pickedUp = tryPickup(model, resourceName)
	if not pickedUp then
		-- A valid item is under the cursor but it could be out of range,
		-- on cooldown, or the remote failed.  Do not drop in those cases.
	end
end

--[[
    @summary  Release LMB drag.
]]
local function onInputEnded(input: InputObject)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		if draggingModel then
			stopDrag()
		end
	end
end

-- // INITIALIZATION // --

function CarryController:KnitStart()
	harvestService = Knit.GetService("HarvestService")
	forageService = Knit.GetService("ForageService")
	inventoryService = Knit.GetService("InventoryService")
	gameStateController = Knit.GetController("GameStateController")

	UserInputService.InputBegan:Connect(onInputBegan)
	UserInputService.InputEnded:Connect(onInputEnded)
	RunService.RenderStepped:Connect(updateHover)

	print("[CarryController] Initialised — cursor F-pickup/drop active")
end

--[[
    @summary  Expose drag/hover state so other controllers can be context-aware.
]]
function CarryController.IsDragging(): boolean
	return draggingModel ~= nil
end

function CarryController.GetHoveredModel(): Model?
	return hoveredModel
end

return CarryController
