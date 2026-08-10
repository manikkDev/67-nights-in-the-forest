--[[
    @file    CarryController.luau
    @author  manik
    @date    2025

    @summary
    Cursor-aimed E-key pickup for dropped items (wood, berries, mushrooms).

    @description
    Raycasts from the camera through the mouse/center of the screen. When
    the player presses E while pointing at a pickup-able item within range,
    it fires the appropriate server remote to add one unit to their bag
    and destroy the world item. The inventory UI is updated automatically
    by the server's ResourcesChanged signal.

    @exports
    - CarryController (Knit Controller)
]]

-- // VARIABLES // --

-- | Services | --
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- | Modules | --
local Knit = require(ReplicatedStorage.Packages.Knit)

-- | Objects | --
local CarryController = Knit.CreateController({
	Name = "CarryController",
})

-- | Configuration | --
local PICKUP_KEY = Enum.KeyCode.E
local PICKUP_RANGE = 6
local PICKUP_COOLDOWN = 0.2
local RAY_LENGTH = 32

-- | State Management | --
local harvestService: any? = nil
local forageService: any? = nil
local lastPickupTime = 0

-- // FUNCTIONS // --

--[[
    @summary  Walk up an instance's parent chain to find the pickup model.
    @returns  Model?, string?  -- the pickup model and the resource name
]]
local function findPickupModel(instance: Instance): (Model?, string?)
	local current = instance
	while current do
		if current:IsA("Model") then
			local wood = current:GetAttribute("PickupResource")
			local forage = current:GetAttribute("ForageResource")
			local resource = wood or forage
			if resource and typeof(resource) == "string" then
				return current, resource
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
    @summary  Try to pick up the item the player is looking at.
]]
local function tryPickup()
	local now = os.clock()
	if now - lastPickupTime < PICKUP_COOLDOWN then
		return
	end

	if UserInputService:GetFocusedTextBox() then
		return
	end

	local instance, _ = getMouseRay()
	if not instance then
		return
	end

	local model, resourceName = findPickupModel(instance)
	if not model or not resourceName then
		return
	end

	if not isInRange(model) then
		return
	end

	lastPickupTime = now

	if resourceName == "Wood" then
		if harvestService then
			harvestService:RequestPickup(model)
		end
	elseif resourceName == "Berries" or resourceName == "Mushrooms" then
		if forageService then
			forageService:RequestPickup(model)
		end
	end
end

--[[
    @summary  Handle keyboard input for the pickup key.
]]
local function onInputBegan(input: InputObject, gameProcessed: boolean)
	if gameProcessed then
		return
	end
	if input.KeyCode == PICKUP_KEY then
		tryPickup()
	end
end

-- // INITIALIZATION // --

function CarryController:KnitStart()
	harvestService = Knit.GetService("HarvestService")
	forageService = Knit.GetService("ForageService")

	UserInputService.InputBegan:Connect(onInputBegan)

	print("[CarryController] Initialised — cursor E-pickup active")
end

return CarryController
