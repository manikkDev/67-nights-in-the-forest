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
local RescueConfig = require(ReplicatedStorage.Shared.RescueConfig)

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

-- Map UI state
local mapGui: ScreenGui? = nil
local mapFrame: Frame? = nil
local mapCards: { [string]: Frame } = {}
local mapOpen = false
local currentMapStates: { [string]: any } = {}

local CAVE_ORDER = { "Dino", "Kraken", "Squid", "Koala" }

-- // FUNCTIONS // --

--[[
    @summary  Build the "Missing Kid Locations" map UI (hidden by default).
]]
local function buildMapUi()
	if mapGui then
		return
	end
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "MissingKidLocationsGui"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true
	screenGui.Enabled = false
	screenGui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	mapGui = screenGui

	-- Dark background
	local bg = Instance.new("Frame")
	bg.Size = UDim2.fromScale(1, 1)
	bg.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	bg.BackgroundTransparency = 0.5
	bg.BorderSizePixel = 0
	bg.Parent = screenGui

	-- Main board frame
	local frame = Instance.new("Frame")
	frame.Name = "BoardFrame"
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromScale(0.5, 0.5)
	frame.Size = UDim2.fromOffset(860, 480)
	frame.BackgroundColor3 = Color3.fromRGB(85, 58, 34)
	frame.BorderSizePixel = 0
	frame.Parent = bg
	mapFrame = frame
	local frameCorner = Instance.new("UICorner")
	frameCorner.CornerRadius = UDim.new(0, 12)
	frameCorner.Parent = frame
	local frameStroke = Instance.new("UIStroke")
	frameStroke.Color = Color3.fromRGB(50, 32, 18)
	frameStroke.Thickness = 4
	frameStroke.Parent = frame

	-- Title
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Position = UDim2.fromOffset(0, 12)
	title.Size = UDim2.new(1, 0, 0, 48)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.PermanentMarker
	title.Text = "MISSING KID LOCATIONS"
	title.TextColor3 = Color3.fromRGB(240, 230, 200)
	title.TextStrokeColor3 = Color3.fromRGB(20, 10, 5)
	title.TextStrokeTransparency = 0.2
	title.TextSize = 32
	title.Parent = frame

	-- Close button
	local closeBtn = Instance.new("TextButton")
	closeBtn.Name = "CloseButton"
	closeBtn.AnchorPoint = Vector2.new(1, 0)
	closeBtn.Position = UDim2.new(1, -8, 0, 8)
	closeBtn.Size = UDim2.fromOffset(36, 36)
	closeBtn.BackgroundColor3 = Color3.fromRGB(180, 50, 40)
	closeBtn.Font = Enum.Font.GothamBold
	closeBtn.Text = "X"
	closeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	closeBtn.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	closeBtn.TextStrokeTransparency = 0.3
	closeBtn.TextSize = 20
	closeBtn.Parent = frame
	local closeCorner = Instance.new("UICorner")
	closeCorner.CornerRadius = UDim.new(1, 0)
	closeCorner.Parent = closeBtn
	closeBtn.MouseButton1Click:Connect(function()
		screenGui.Enabled = false
		mapOpen = false
	end)

	-- Cards container
	local cardsRow = Instance.new("Frame")
	cardsRow.Name = "CardsRow"
	cardsRow.Position = UDim2.fromOffset(20, 70)
	cardsRow.Size = UDim2.new(1, -40, 1, -90)
	cardsRow.BackgroundTransparency = 1
	cardsRow.Parent = frame

	-- Use UIListLayout for horizontal layout
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Top
	layout.Padding = UDim.new(0, 16)
	layout.Parent = cardsRow

	-- Create 4 cards
	mapCards = {}
	for _, rescueId in ipairs(CAVE_ORDER) do
		local definition = RescueConfig[rescueId]
		local displayName = definition and definition.DisplayName or rescueId

		local card = Instance.new("Frame")
		card.Name = rescueId .. "Card"
		card.Size = UDim2.fromOffset(180, 360)
		card.BackgroundColor3 = Color3.fromRGB(232, 224, 198)
		card.BorderSizePixel = 0
		card.Parent = cardsRow
		local cardCorner = Instance.new("UICorner")
		cardCorner.CornerRadius = UDim.new(0, 6)
		cardCorner.Parent = card
		local cardStroke = Instance.new("UIStroke")
		cardStroke.Color = Color3.fromRGB(80, 60, 40)
		cardStroke.Thickness = 2
		cardStroke.Parent = card

		-- MISSING label
		local missingLabel = Instance.new("TextLabel")
		missingLabel.Name = "MissingLabel"
		missingLabel.Position = UDim2.fromOffset(0, 6)
		missingLabel.Size = UDim2.new(1, 0, 0, 24)
		missingLabel.BackgroundTransparency = 1
		missingLabel.Font = Enum.Font.PermanentMarker
		missingLabel.Text = "MISSING"
		missingLabel.TextColor3 = Color3.fromRGB(180, 30, 30)
		missingLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
		missingLabel.TextStrokeTransparency = 0.3
		missingLabel.TextSize = 18
		missingLabel.Parent = card

		-- ViewportFrame for portrait
		local viewport = Instance.new("ViewportFrame")
		viewport.Name = "Portrait"
		viewport.Position = UDim2.fromOffset(8, 32)
		viewport.Size = UDim2.new(1, -16, 0, 220)
		viewport.BackgroundTransparency = 1
		viewport.Parent = card

		-- Black overlay
		local blackOverlay = Instance.new("Frame")
		blackOverlay.Name = "BlackOverlay"
		blackOverlay.Position = UDim2.fromOffset(8, 32)
		blackOverlay.Size = UDim2.new(1, -16, 0, 220)
		blackOverlay.BackgroundColor3 = Color3.fromRGB(15, 15, 15)
		blackOverlay.Visible = true
		blackOverlay.Parent = card
		local overlayQ = Instance.new("TextLabel")
		overlayQ.Size = UDim2.fromScale(1, 1)
		overlayQ.BackgroundTransparency = 1
		overlayQ.Font = Enum.Font.GothamBlack
		overlayQ.Text = "?"
		overlayQ.TextColor3 = Color3.fromRGB(60, 60, 60)
		overlayQ.TextSize = 60
		overlayQ.Parent = blackOverlay

		-- Name label
		local nameLabel = Instance.new("TextLabel")
		nameLabel.Name = "NameLabel"
		nameLabel.Position = UDim2.fromOffset(0, 256)
		nameLabel.Size = UDim2.new(1, 0, 0, 24)
		nameLabel.BackgroundTransparency = 1
		nameLabel.Font = Enum.Font.GothamBold
		nameLabel.Text = displayName
		nameLabel.TextColor3 = Color3.fromRGB(40, 30, 20)
		nameLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
		nameLabel.TextStrokeTransparency = 0.3
		nameLabel.TextSize = 16
		nameLabel.Parent = card

		-- Status label
		local statusLabel = Instance.new("TextLabel")
		statusLabel.Name = "StatusLabel"
		statusLabel.Position = UDim2.fromOffset(0, 280)
		statusLabel.Size = UDim2.new(1, 0, 0, 20)
		statusLabel.BackgroundTransparency = 1
		statusLabel.Font = Enum.Font.GothamBold
		statusLabel.Text = "Locked"
		statusLabel.TextColor3 = Color3.fromRGB(120, 120, 120)
		statusLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
		statusLabel.TextStrokeTransparency = 0.4
		statusLabel.TextSize = 14
		statusLabel.Parent = card

		-- Track button
		local trackBtn = Instance.new("TextButton")
		trackBtn.Name = "TrackButton"
		trackBtn.Position = UDim2.fromOffset(20, 310)
		trackBtn.Size = UDim2.new(1, -40, 0, 36)
		trackBtn.BackgroundColor3 = Color3.fromRGB(60, 130, 200)
		trackBtn.Font = Enum.Font.GothamBold
		trackBtn.Text = "Track"
		trackBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
		trackBtn.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
		trackBtn.TextStrokeTransparency = 0.3
		trackBtn.TextSize = 16
		trackBtn.Visible = false
		trackBtn.Parent = card
		local trackCorner = Instance.new("UICorner")
		trackCorner.CornerRadius = UDim.new(0, 6)
		trackCorner.Parent = trackBtn
		trackBtn.MouseButton1Click:Connect(function()
			if rescueService then
				rescueService:RequestSetWaypoint(rescueId)
			end
			screenGui.Enabled = false
			mapOpen = false
		end)

		-- FOUND stamp
		local foundStamp = Instance.new("TextLabel")
		foundStamp.Name = "FoundStamp"
		foundStamp.Position = UDim2.fromOffset(10, 80)
		foundStamp.Size = UDim2.fromOffset(160, 50)
		foundStamp.BackgroundTransparency = 1
		foundStamp.Font = Enum.Font.PermanentMarker
		foundStamp.Text = "FOUND!"
		foundStamp.TextColor3 = Color3.fromRGB(30, 160, 50)
		foundStamp.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
		foundStamp.TextStrokeTransparency = 0.3
		foundStamp.TextSize = 32
		foundStamp.Rotation = -12
		foundStamp.Visible = false
		foundStamp.ZIndex = 10
		foundStamp.Parent = card

		mapCards[rescueId] = card
	end
end

--[[
    @summary  Update the map UI cards to reflect current rescue states.
    @param    states  table  -- { [rescueId] = { state, displayName, position } }
]]
local function refreshMapUi(states: { [string]: any })
	for rescueId, card in pairs(mapCards) do
		local info = states and states[rescueId]
		if not info then
			continue
		end
		local state = info.state
		local viewport = card:FindFirstChild("Portrait")
		local blackOverlay = card:FindFirstChild("BlackOverlay")
		local statusLabel = card:FindFirstChild("StatusLabel")
		local trackBtn = card:FindFirstChild("TrackButton")
		local foundStamp = card:FindFirstChild("FoundStamp")

		if state == "Locked" then
			if blackOverlay then blackOverlay.Visible = true end
			if viewport then viewport.Visible = false end
			if statusLabel then statusLabel.Text = "Locked" statusLabel.TextColor3 = Color3.fromRGB(120, 120, 120) end
			if trackBtn then trackBtn.Visible = false end
			if foundStamp then foundStamp.Visible = false end
		elseif state == "Rescued" then
			if blackOverlay then blackOverlay.Visible = false end
			if viewport then viewport.Visible = true end
			if statusLabel then statusLabel.Text = "Rescued!" statusLabel.TextColor3 = Color3.fromRGB(30, 160, 50) end
			if trackBtn then trackBtn.Visible = false end
			if foundStamp then foundStamp.Visible = true end
		else
			-- Available, KeyDropped, Unlocked, Carried
			if blackOverlay then blackOverlay.Visible = false end
			if viewport then viewport.Visible = true end
			if statusLabel then
				if state == "Carried" then
					statusLabel.Text = "Being carried"
					statusLabel.TextColor3 = Color3.fromRGB(200, 160, 30)
				else
					statusLabel.Text = "Available"
					statusLabel.TextColor3 = Color3.fromRGB(200, 80, 30)
				end
			end
			if trackBtn then trackBtn.Visible = true end
			if foundStamp then foundStamp.Visible = false end
		end
	end
end

--[[
    @summary  Open the map UI with a snapshot of rescue states.
    @param    snapshot  table
]]
local function openMapUi(snapshot: { [string]: any })
	if not mapGui then
		buildMapUi()
	end
	if not mapGui then
		return
	end
	mapGui.Enabled = true
	mapOpen = true
	if snapshot and snapshot.records then
		refreshMapUi(snapshot.records)
	end
end

--[[
    @summary  Close the map UI.
]]
local function closeMapUi()
	if mapGui then
		mapGui.Enabled = false
	end
	mapOpen = false
end

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
	arrow.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	arrow.TextStrokeTransparency = 0.3
	arrow.TextSize = 34
	arrow.Parent = waypoint
	arrowLabel = arrow

	local waypointText = Instance.new("TextLabel")
	waypointText.Position = UDim2.fromOffset(58, 8)
	waypointText.Size = UDim2.new(1, -68, 1, -16)
	waypointText.BackgroundTransparency = 1
	waypointText.Font = Enum.Font.GothamBold
	waypointText.TextColor3 = Color3.fromRGB(240, 235, 220)
	waypointText.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	waypointText.TextStrokeTransparency = 0.3
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
	progress.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	progress.TextStrokeTransparency = 0.3
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
	carry.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	carry.TextStrokeTransparency = 0.3
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
	buildMapUi()
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

	-- Board opened signal: open the map UI
	janitor:Add(rescueService.BoardOpened:Connect(function(snapshot)
		if typeof(snapshot) == "table" then
			openMapUi(snapshot)
		end
	end), "Disconnect")

	-- Poster state updated: refresh map UI if open
	janitor:Add(rescueService.PosterStateUpdated:Connect(function(payload)
		if typeof(payload) == "table" and payload.states then
			currentMapStates = payload.states
			if mapOpen then
				refreshMapUi(payload.states)
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
			closeMapUi()
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
