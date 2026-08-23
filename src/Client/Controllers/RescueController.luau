--[[
    @file    RescueController.luau
    @author  manik
    @date    2025

    @summary
    Missing-child waypoint, carry/drop controls, cave notifications,
    and rescue progress feedback across keyboard, touch, and gamepad.
]]

-- // VARIABLES // --

-- | Services | --
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ContextActionService = game:GetService("ContextActionService")

-- | Modules | --
local Knit = require(ReplicatedStorage.Packages.Knit)
local Janitor = require(ReplicatedStorage.Packages.Janitor)

-- | Objects | --
local RescueController = Knit.CreateController({
	Name = "RescueController",
})
local janitor = Janitor.new()

-- | Configuration | --
local DROP_ACTION = "DropRescuedChild"

-- | State Management | --
local rescueService: any = nil
local gui: ScreenGui? = nil
local waypointFrame: Frame? = nil
local arrowLabel: TextLabel? = nil
local waypointLabel: TextLabel? = nil
local progressLabel: TextLabel? = nil
local carryLabel: TextLabel? = nil
local bannerLabel: TextLabel? = nil
local targetPosition: Vector3? = nil
local targetName = ""
local carryingChild: string? = nil
local bannerHideAt = 0

-- // FUNCTIONS // --

--[[
    @summary  Build the rescue HUD once.
]]
local function buildUi()
	if gui then
		return
	end
	gui = Instance.new("ScreenGui")
	gui.Name = "RescueGui"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	waypointFrame = Instance.new("Frame")
	waypointFrame.AnchorPoint = Vector2.new(0.5, 0)
	waypointFrame.Position = UDim2.new(0.5, 0, 0, 86)
	waypointFrame.Size = UDim2.fromOffset(300, 62)
	waypointFrame.BackgroundColor3 = Color3.fromRGB(20, 20, 24)
	waypointFrame.BackgroundTransparency = 0.18
	waypointFrame.Visible = false
	waypointFrame.Parent = gui
	local waypointCorner = Instance.new("UICorner")
	waypointCorner.CornerRadius = UDim.new(0, 10)
	waypointCorner.Parent = waypointFrame

	arrowLabel = Instance.new("TextLabel")
	arrowLabel.Position = UDim2.fromOffset(10, 8)
	arrowLabel.Size = UDim2.fromOffset(44, 44)
	arrowLabel.BackgroundTransparency = 1
	arrowLabel.Font = Enum.Font.GothamBlack
	arrowLabel.Text = "▲"
	arrowLabel.TextColor3 = Color3.fromRGB(220, 70, 60)
	arrowLabel.TextSize = 34
	arrowLabel.Parent = waypointFrame

	waypointLabel = Instance.new("TextLabel")
	waypointLabel.Position = UDim2.fromOffset(58, 8)
	waypointLabel.Size = UDim2.new(1, -68, 1, -16)
	waypointLabel.BackgroundTransparency = 1
	waypointLabel.Font = Enum.Font.GothamBold
	waypointLabel.TextColor3 = Color3.fromRGB(240, 235, 220)
	waypointLabel.TextSize = 16
	waypointLabel.TextWrapped = true
	waypointLabel.TextXAlignment = Enum.TextXAlignment.Left
	waypointLabel.Parent = waypointFrame

	progressLabel = Instance.new("TextLabel")
	progressLabel.AnchorPoint = Vector2.new(1, 0)
	progressLabel.Position = UDim2.new(1, -18, 0, 86)
	progressLabel.Size = UDim2.fromOffset(170, 36)
	progressLabel.BackgroundColor3 = Color3.fromRGB(20, 20, 24)
	progressLabel.BackgroundTransparency = 0.2
	progressLabel.Font = Enum.Font.GothamBold
	progressLabel.Text = "CHILDREN  0 / 4"
	progressLabel.TextColor3 = Color3.fromRGB(235, 225, 195)
	progressLabel.TextSize = 15
	progressLabel.Parent = gui
	local progressCorner = Instance.new("UICorner")
	progressCorner.CornerRadius = UDim.new(0, 8)
	progressCorner.Parent = progressLabel

	carryLabel = Instance.new("TextLabel")
	carryLabel.AnchorPoint = Vector2.new(0.5, 1)
	carryLabel.Position = UDim2.new(0.5, 0, 1, -82)
	carryLabel.Size = UDim2.new(0.8, 0, 0, 46)
	carryLabel.BackgroundColor3 = Color3.fromRGB(35, 30, 25)
	carryLabel.BackgroundTransparency = 0.12
	carryLabel.Font = Enum.Font.GothamBold
	carryLabel.Text = "Carrying child  •  G / B to drop"
	carryLabel.TextColor3 = Color3.fromRGB(245, 230, 190)
	carryLabel.TextSize = 17
	carryLabel.Visible = false
	carryLabel.Parent = gui
	local carryConstraint = Instance.new("UISizeConstraint")
	carryConstraint.MaxSize = Vector2.new(480, 46)
	carryConstraint.Parent = carryLabel
	local carryCorner = Instance.new("UICorner")
	carryCorner.CornerRadius = UDim.new(0, 9)
	carryCorner.Parent = carryLabel

	bannerLabel = Instance.new("TextLabel")
	bannerLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	bannerLabel.Position = UDim2.fromScale(0.5, 0.28)
	bannerLabel.Size = UDim2.new(0.85, 0, 0, 72)
	bannerLabel.BackgroundTransparency = 1
	bannerLabel.Font = Enum.Font.GothamBlack
	bannerLabel.TextColor3 = Color3.fromRGB(245, 220, 135)
	bannerLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
	bannerLabel.TextStrokeTransparency = 0.25
	bannerLabel.TextScaled = true
	bannerLabel.Visible = false
	bannerLabel.Parent = gui
	local bannerConstraint = Instance.new("UITextSizeConstraint")
	bannerConstraint.MaxTextSize = 34
	bannerConstraint.MinTextSize = 18
	bannerConstraint.Parent = bannerLabel
end

--[[
    @summary  Show a temporary rescue-system announcement.
    @param    text  string
]]
local function showBanner(text: string)
	bannerLabel.Text = text
	bannerLabel.Visible = true
	bannerHideAt = os.clock() + 4
end

--[[
    @summary  Request dropping the currently carried child.
]]
local function dropChild()
	if not carryingChild then
		return
	end
	rescueService:RequestDropChild()
end

--[[
    @summary  Handle the bound cross-platform drop action.
    @param    _actionName  string
    @param    inputState   UserInputState
    @returns  ContextActionResult
]]
local function onDropAction(_actionName: string, inputState: Enum.UserInputState): Enum.ContextActionResult
	if inputState == Enum.UserInputState.Begin then
		dropChild()
	end
	return Enum.ContextActionResult.Sink
end

--[[
    @summary  Enable or disable carry presentation and controls.
    @param    childId  string?
]]
local function setCarrying(childId: string?)
	carryingChild = childId
	carryLabel.Visible = childId ~= nil
	ContextActionService:UnbindAction(DROP_ACTION)
	if childId then
		carryLabel.Text = "Carrying " .. childId .. " Kid  •  G / B to drop"
		ContextActionService:BindAction(DROP_ACTION, onDropAction, true, Enum.KeyCode.G, Enum.KeyCode.ButtonB)
		ContextActionService:SetTitle(DROP_ACTION, "Drop Child")
		ContextActionService:SetPosition(DROP_ACTION, UDim2.new(1, -105, 1, -100))
	end
end

--[[
    @summary  Update the waypoint direction and distance every rendered frame.
]]
local function updateWaypoint()
	if bannerLabel.Visible and os.clock() >= bannerHideAt then
		bannerLabel.Visible = false
	end
	if not targetPosition then
		waypointFrame.Visible = false
		return
	end
	local rootPart = Players.LocalPlayer.Character and Players.LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
	local camera = workspace.CurrentCamera
	if not rootPart or not rootPart:IsA("BasePart") or not camera then
		waypointFrame.Visible = false
		return
	end
	waypointFrame.Visible = true
	local toTarget = targetPosition - rootPart.Position
	local flatTarget = Vector3.new(toTarget.X, 0, toTarget.Z)
	local flatLook = Vector3.new(camera.CFrame.LookVector.X, 0, camera.CFrame.LookVector.Z)
	if flatTarget.Magnitude > 0 and flatLook.Magnitude > 0 then
		local angle = math.atan2(flatLook:Cross(flatTarget).Y, flatLook:Dot(flatTarget))
		arrowLabel.Rotation = -math.deg(angle)
	end
	waypointLabel.Text = string.format("%s\n%.0f studs", targetName, toTarget.Magnitude)
end

-- // INITIALIZATION // --

function RescueController:KnitStart()
	rescueService = Knit.GetService("RescueService")
	local runStateService = Knit.GetService("RunStateService")
	buildUi()
	gui.Enabled = false

	janitor:Add(rescueService.WaypointChanged:Connect(function(payload)
		if typeof(payload) ~= "table" or payload.cleared == true then
			targetPosition = nil
			targetName = ""
			return
		end
		targetPosition = payload.position
		targetName = payload.displayName or "Missing Child"
	end), "Disconnect")

	janitor:Add(rescueService.CaveUnlocked:Connect(function(payload)
		if typeof(payload) == "table" then
			showBanner((payload.displayName or "A child") .. " can now be found")
		end
	end), "Disconnect")

	janitor:Add(rescueService.ChildCarryChanged:Connect(function(payload)
		if typeof(payload) == "table" and payload.userId == Players.LocalPlayer.UserId then
			setCarrying(if payload.carrying then payload.childId else nil)
		end
	end), "Disconnect")

	janitor:Add(rescueService.RescueChanged:Connect(function(payload)
		if typeof(payload) == "table" then
			progressLabel.Text = string.format("CHILDREN  %d / 4", payload.rescuedCount or 0)
			showBanner((payload.displayName or "Child") .. " RESCUED  •  " .. tostring(payload.multiplier or 1) .. "x DAYS")
			if targetName == payload.displayName then
				targetPosition = nil
			end
		end
	end), "Disconnect")

	rescueService:GetSnapshot():andThen(function(snapshot)
		if typeof(snapshot) == "table" then
			progressLabel.Text = string.format("CHILDREN  %d / 4", snapshot.rescuedCount or 0)
			setCarrying(snapshot.carrying)
		end
	end)

	janitor:Add(runStateService.RunPhaseChanged:Connect(function(payload)
		if typeof(payload) ~= "table" then
			return
		end
		if payload.phase == "Active" then
			gui.Enabled = true
		elseif payload.phase == "Lobby" then
			gui.Enabled = false
			targetPosition = nil
			setCarrying(nil)
			progressLabel.Text = "CHILDREN  0 / 4"
		end
	end), "Disconnect")

	janitor:Add(RunService.RenderStepped:Connect(updateWaypoint), "Disconnect")
end

return RescueController
