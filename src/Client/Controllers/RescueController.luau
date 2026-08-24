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
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "RescueGui"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = false
	screenGui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	gui = screenGui

	local waypoint = Instance.new("Frame")
	waypoint.AnchorPoint = Vector2.new(0.5, 0)
	waypoint.Position = UDim2.new(0.5, 0, 0, 86)
	waypoint.Size = UDim2.fromOffset(300, 62)
	waypoint.BackgroundColor3 = Color3.fromRGB(20, 20, 24)
	waypoint.BackgroundTransparency = 0.18
	waypoint.Visible = false
	waypoint.Parent = screenGui
	waypointFrame = waypoint
	local waypointCorner = Instance.new("UICorner")
	waypointCorner.CornerRadius = UDim.new(0, 10)
	waypointCorner.Parent = waypoint

	local arrow = Instance.new("TextLabel")
	arrow.Position = UDim2.fromOffset(10, 8)
	arrow.Size = UDim2.fromOffset(44, 44)
	arrow.BackgroundTransparency = 1
	arrow.Font = Enum.Font.GothamBlack
	arrow.Text = "▲"
	arrow.TextColor3 = Color3.fromRGB(220, 70, 60)
	arrow.TextSize = 34
	arrow.Parent = waypoint
	arrowLabel = arrow

	local waypointText = Instance.new("TextLabel")
	waypointText.Position = UDim2.fromOffset(58, 8)
	waypointText.Size = UDim2.new(1, -68, 1, -16)
	waypointText.BackgroundTransparency = 1
	waypointText.Font = Enum.Font.GothamBold
	waypointText.TextColor3 = Color3.fromRGB(240, 235, 220)
	waypointText.TextSize = 16
	waypointText.TextWrapped = true
	waypointText.TextXAlignment = Enum.TextXAlignment.Left
	waypointText.Parent = waypoint
	waypointLabel = waypointText

	local progress = Instance.new("TextLabel")
	progress.AnchorPoint = Vector2.new(1, 0)
	progress.Position = UDim2.new(1, -18, 0, 86)
	progress.Size = UDim2.fromOffset(170, 36)
	progress.BackgroundColor3 = Color3.fromRGB(20, 20, 24)
	progress.BackgroundTransparency = 0.2
	progress.Font = Enum.Font.GothamBold
	progress.Text = "CHILDREN  0 / 4"
	progress.TextColor3 = Color3.fromRGB(235, 225, 195)
	progress.TextSize = 15
	progress.Parent = screenGui
	progressLabel = progress
	local progressCorner = Instance.new("UICorner")
	progressCorner.CornerRadius = UDim.new(0, 8)
	progressCorner.Parent = progress

	local carry = Instance.new("TextLabel")
	carry.AnchorPoint = Vector2.new(0.5, 1)
	carry.Position = UDim2.new(0.5, 0, 1, -82)
	carry.Size = UDim2.new(0.8, 0, 0, 46)
	carry.BackgroundColor3 = Color3.fromRGB(35, 30, 25)
	carry.BackgroundTransparency = 0.12
	carry.Font = Enum.Font.GothamBold
	carry.Text = "Carrying child  •  G / B to drop"
	carry.TextColor3 = Color3.fromRGB(245, 230, 190)
	carry.TextSize = 17
	carry.Visible = false
	carry.Parent = screenGui
	carryLabel = carry
	local carryConstraint = Instance.new("UISizeConstraint")
	carryConstraint.MaxSize = Vector2.new(480, 46)
	carryConstraint.Parent = carry
	local carryCorner = Instance.new("UICorner")
	carryCorner.CornerRadius = UDim.new(0, 9)
	carryCorner.Parent = carry

	local banner = Instance.new("TextLabel")
	banner.AnchorPoint = Vector2.new(0.5, 0.5)
	banner.Position = UDim2.fromScale(0.5, 0.28)
	banner.Size = UDim2.new(0.85, 0, 0, 72)
	banner.BackgroundTransparency = 1
	banner.Font = Enum.Font.GothamBlack
	banner.TextColor3 = Color3.fromRGB(245, 220, 135)
	banner.TextStrokeColor3 = Color3.new(0, 0, 0)
	banner.TextStrokeTransparency = 0.25
	banner.TextScaled = true
	banner.Visible = false
	banner.Parent = screenGui
	bannerLabel = banner
	local bannerConstraint = Instance.new("UITextSizeConstraint")
	bannerConstraint.MaxTextSize = 34
	bannerConstraint.MinTextSize = 18
	bannerConstraint.Parent = banner
end

--[[
    @summary  Show a temporary rescue-system announcement.
    @param    text  string
]]
local function showBanner(text: string)
	if not bannerLabel then
		return
	end
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
	if carryLabel then
		carryLabel.Visible = childId ~= nil
	end
	ContextActionService:UnbindAction(DROP_ACTION)
	if childId then
		if carryLabel then
			carryLabel.Text = "Carrying " .. childId .. " Kid  •  G / B to drop"
		end
		ContextActionService:BindAction(DROP_ACTION, onDropAction, true, Enum.KeyCode.G, Enum.KeyCode.ButtonB)
		ContextActionService:SetTitle(DROP_ACTION, "Drop Child")
		ContextActionService:SetPosition(DROP_ACTION, UDim2.new(1, -105, 1, -100))
	end
end

--[[
    @summary  Update the waypoint direction and distance every rendered frame.
]]
local function updateWaypoint()
	if bannerLabel and bannerLabel.Visible and os.clock() >= bannerHideAt then
		bannerLabel.Visible = false
	end
	if not targetPosition then
		if waypointFrame then
			waypointFrame.Visible = false
		end
		return
	end
	local rootPart = Players.LocalPlayer.Character and Players.LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
	local camera = workspace.CurrentCamera
	if not rootPart or not rootPart:IsA("BasePart") or not camera then
		if waypointFrame then
			waypointFrame.Visible = false
		end
		return
	end
	if not waypointFrame or not arrowLabel or not waypointLabel then
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
	if gui then
		gui.Enabled = false
	end

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
			if progressLabel then
				progressLabel.Text = string.format("CHILDREN  %d / 4", payload.rescuedCount or 0)
			end
			showBanner((payload.displayName or "Child") .. " RESCUED  •  " .. tostring(payload.multiplier or 1) .. "x DAYS")
			if targetName == payload.displayName then
				targetPosition = nil
			end
		end
	end), "Disconnect")

	rescueService:GetSnapshot():andThen(function(snapshot)
		if typeof(snapshot) == "table" then
			if progressLabel then
				progressLabel.Text = string.format("CHILDREN  %d / 4", snapshot.rescuedCount or 0)
			end
			setCarrying(snapshot.carrying)
		end
	end)

	janitor:Add(runStateService.RunPhaseChanged:Connect(function(payload)
		if typeof(payload) ~= "table" then
			return
		end
		if payload.phase == "Active" then
			if gui then
				gui.Enabled = true
			end
		elseif payload.phase == "Lobby" then
			if gui then
				gui.Enabled = false
			end
			targetPosition = nil
			setCarrying(nil)
			if progressLabel then
				progressLabel.Text = "CHILDREN  0 / 4"
			end
		end
	end), "Disconnect")

	janitor:Add(RunService.RenderStepped:Connect(updateWaypoint), "Disconnect")
end

return RescueController
