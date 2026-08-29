--[[
    @file    SpectateController.luau
    @author  manik
    @date    2025

    @summary
    Responsive eliminated-player spectator camera with keyboard, gamepad,
    and touch controls. All camera and input state is restored on exit.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContextActionService = game:GetService("ContextActionService")
local RunService = game:GetService("RunService")

local Knit = require(ReplicatedStorage.Packages.Knit)
local ServerRole = require(ReplicatedStorage.Shared.ServerRole)
local Janitor = require(ReplicatedStorage.Packages.Janitor)

local SpectateController = Knit.CreateController({ Name = "SpectateController" })
local janitor = Janitor.new()
local localPlayer = Players.LocalPlayer
local NEXT_ACTION = "LifeSpectateNext"
local PREVIOUS_ACTION = "LifeSpectatePrevious"

local lifeService: any = nil
local gui: ScreenGui? = nil
local targetLabel: TextLabel? = nil
local healthLabel: TextLabel? = nil
local healthFill: Frame? = nil
local emptyLabel: TextLabel? = nil
local selfState = "Lobby"
local memberStates: { [number]: string } = {}
local targetIndex = 1
local currentTarget: Player? = nil
local spectating = false

local function makeButton(parent: Instance, name: string, text: string, position: UDim2): TextButton
	local button = Instance.new("TextButton")
	button.Name = name
	button.AnchorPoint = Vector2.new(0.5, 1)
	button.Position = position
	button.Size = UDim2.fromOffset(132, 46)
	button.BackgroundColor3 = Color3.fromRGB(20, 23, 28)
	button.BackgroundTransparency = 0.08
	button.BorderSizePixel = 0
	button.Font = Enum.Font.GothamBold
	button.Text = text
	button.TextColor3 = Color3.fromRGB(235, 235, 232)
	button.TextSize = 15
	button.AutoButtonColor = true
	button.Parent = parent
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = button
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(78, 83, 92)
	stroke.Transparency = 0.25
	stroke.Parent = button
	return button
end

local function buildUi()
	if gui then return end
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "SpectateGui"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = false
	screenGui.DisplayOrder = 46
	screenGui.Enabled = false
	screenGui.Parent = localPlayer:WaitForChild("PlayerGui")
	gui = screenGui

	local status = Instance.new("Frame")
	status.AnchorPoint = Vector2.new(0.5, 0)
	status.Position = UDim2.new(0.5, 0, 0, 22)
	status.Size = UDim2.new(0.82, 0, 0, 96)
	status.BackgroundColor3 = Color3.fromRGB(16, 19, 23)
	status.BackgroundTransparency = 0.08
	status.BorderSizePixel = 0
	status.Parent = screenGui
	local size = Instance.new("UISizeConstraint")
	size.MaxSize = Vector2.new(460, 96)
	size.MinSize = Vector2.new(290, 90)
	size.Parent = status
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = status
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(70, 76, 86)
	stroke.Transparency = 0.2
	stroke.Parent = status

	local eyebrow = Instance.new("TextLabel")
	eyebrow.Position = UDim2.fromOffset(18, 10)
	eyebrow.Size = UDim2.new(1, -36, 0, 18)
	eyebrow.BackgroundTransparency = 1
	eyebrow.Font = Enum.Font.GothamBold
	eyebrow.Text = "SPECTATING"
	eyebrow.TextColor3 = Color3.fromRGB(150, 157, 168)
	eyebrow.TextSize = 12
	eyebrow.TextXAlignment = Enum.TextXAlignment.Left
	eyebrow.Parent = status

	local target = Instance.new("TextLabel")
	target.Position = UDim2.fromOffset(18, 29)
	target.Size = UDim2.new(1, -120, 0, 29)
	target.BackgroundTransparency = 1
	target.Font = Enum.Font.GothamBold
	target.Text = "Finding teammate..."
	target.TextColor3 = Color3.fromRGB(242, 242, 238)
	target.TextSize = 21
	target.TextTruncate = Enum.TextTruncate.AtEnd
	target.TextXAlignment = Enum.TextXAlignment.Left
	target.Parent = status
	targetLabel = target

	local health = Instance.new("TextLabel")
	health.AnchorPoint = Vector2.new(1, 0)
	health.Position = UDim2.new(1, -18, 0, 33)
	health.Size = UDim2.fromOffset(92, 22)
	health.BackgroundTransparency = 1
	health.Font = Enum.Font.GothamBold
	health.Text = "-- / --"
	health.TextColor3 = Color3.fromRGB(178, 220, 177)
	health.TextSize = 14
	health.TextXAlignment = Enum.TextXAlignment.Right
	health.Parent = status
	healthLabel = health

	local healthBack = Instance.new("Frame")
	healthBack.Position = UDim2.fromOffset(18, 68)
	healthBack.Size = UDim2.new(1, -36, 0, 8)
	healthBack.BackgroundColor3 = Color3.fromRGB(48, 51, 57)
	healthBack.BorderSizePixel = 0
	healthBack.Parent = status
	local healthCorner = Instance.new("UICorner")
	healthCorner.CornerRadius = UDim.new(1, 0)
	healthCorner.Parent = healthBack
	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = Color3.fromRGB(78, 184, 99)
	fill.BorderSizePixel = 0
	fill.Parent = healthBack
	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(1, 0)
	fillCorner.Parent = fill
	healthFill = fill

	local empty = Instance.new("TextLabel")
	empty.AnchorPoint = Vector2.new(0.5, 0.5)
	empty.Position = UDim2.fromScale(0.5, 0.5)
	empty.Size = UDim2.new(0.8, 0, 0, 60)
	empty.BackgroundTransparency = 1
	empty.Font = Enum.Font.GothamBold
	empty.Text = "Waiting for an alive teammate..."
	empty.TextColor3 = Color3.fromRGB(220, 220, 218)
	empty.TextSize = 18
	empty.TextWrapped = true
	empty.Visible = false
	empty.Parent = screenGui
	emptyLabel = empty

	local previous = makeButton(screenGui, "Previous", "Q / L1  Previous", UDim2.new(0.5, -76, 1, -28))
	local nextButton = makeButton(screenGui, "Next", "Next  E / R1", UDim2.new(0.5, 76, 1, -28))
	previous.Activated:Connect(function() SpectateController:Cycle(-1) end)
	nextButton.Activated:Connect(function() SpectateController:Cycle(1) end)
end

local function targets(): { Player }
	local result = {}
	for _, player in ipairs(Players:GetPlayers()) do
		if player ~= localPlayer and memberStates[player.UserId] == "Alive" and player.Character then
			local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
			if humanoid and humanoid.Health > 0 then table.insert(result, player) end
		end
	end
	table.sort(result, function(a, b) return a.UserId < b.UserId end)
	return result
end

local function restoreCamera()
	local camera = workspace.CurrentCamera
	local humanoid = localPlayer.Character and localPlayer.Character:FindFirstChildOfClass("Humanoid")
	if camera then
		camera.CameraType = Enum.CameraType.Custom
		if humanoid then camera.CameraSubject = humanoid end
	end
end

local function updateTarget()
	local list = targets()
	if #list == 0 then
		currentTarget = nil
		if emptyLabel then emptyLabel.Visible = spectating end
		if targetLabel then targetLabel.Text = "No teammate available" end
		if healthLabel then healthLabel.Text = "-- / --" end
		if healthFill then healthFill.Size = UDim2.fromScale(0, 1) end
		return
	end
	if emptyLabel then emptyLabel.Visible = false end
	targetIndex = ((targetIndex - 1) % #list) + 1
	currentTarget = list[targetIndex]
	local humanoid = currentTarget.Character and currentTarget.Character:FindFirstChildOfClass("Humanoid")
	local camera = workspace.CurrentCamera
	if humanoid and camera then
		camera.CameraType = Enum.CameraType.Custom
		camera.CameraSubject = humanoid
	end
	if targetLabel then targetLabel.Text = currentTarget.DisplayName end
end

local function onAction(actionName: string, inputState: Enum.UserInputState): Enum.ContextActionResult
	if inputState == Enum.UserInputState.Begin then
		SpectateController:Cycle(if actionName == NEXT_ACTION then 1 else -1)
	end
	return Enum.ContextActionResult.Sink
end

local function stopSpectating()
	if not spectating then
		if gui then gui.Enabled = false end
		return
	end
	spectating = false
	currentTarget = nil
	ContextActionService:UnbindAction(NEXT_ACTION)
	ContextActionService:UnbindAction(PREVIOUS_ACTION)
	if gui then gui.Enabled = false end
	restoreCamera()
end

local function startSpectating()
	buildUi()
	if spectating then updateTarget() return end
	spectating = true
	targetIndex = 1
	if gui then gui.Enabled = true end
	ContextActionService:BindAction(NEXT_ACTION, onAction, false, Enum.KeyCode.E, Enum.KeyCode.ButtonR1, Enum.KeyCode.DPadRight)
	ContextActionService:BindAction(PREVIOUS_ACTION, onAction, false, Enum.KeyCode.Q, Enum.KeyCode.ButtonL1, Enum.KeyCode.DPadLeft)
	updateTarget()
end

function SpectateController:Cycle(direction: number)
	if not spectating then return end
	targetIndex += direction
	updateTarget()
end

function SpectateController:KnitStart()
	if ServerRole.IsLobby() then return end
	lifeService = Knit.GetService("PlayerLifeService")
	local runStateService = Knit.GetService("RunStateService")
	buildUi()
	janitor:Add(lifeService.LifeStateChanged:Connect(function(payload)
		if typeof(payload) ~= "table" or typeof(payload.userId) ~= "number" then return end
		memberStates[payload.userId] = payload.state
		if payload.userId == localPlayer.UserId then
			selfState = payload.state
			if selfState == "Eliminated" then startSpectating() else stopSpectating() end
		elseif spectating then
			updateTarget()
		end
	end), "Disconnect")
	janitor:Add(runStateService.RunPhaseChanged:Connect(function(payload)
		if typeof(payload) == "table" and (payload.phase == "Ending" or payload.phase == "Ended" or payload.phase == "Lobby") then
			stopSpectating()
			if payload.phase == "Lobby" then
				selfState = "Lobby"
				table.clear(memberStates)
			end
		end
	end), "Disconnect")
	lifeService:GetSnapshot():andThen(function(snapshot)
		if typeof(snapshot) ~= "table" then return end
		for userId, state in pairs(snapshot.states or {}) do
			local numericId = tonumber(userId)
			if numericId then memberStates[numericId] = state end
		end
		selfState = snapshot.selfState or "Lobby"
		if selfState == "Eliminated" then startSpectating() end
	end)
	janitor:Add(localPlayer.CharacterAdded:Connect(function()
		if not spectating then task.defer(restoreCamera) end
	end), "Disconnect")
	janitor:Add(RunService.RenderStepped:Connect(function()
		if not spectating then return end
		local target = currentTarget
		local humanoid = target and target.Character and target.Character:FindFirstChildOfClass("Humanoid")
		if not target or memberStates[target.UserId] ~= "Alive" or not humanoid or humanoid.Health <= 0 then
			updateTarget()
			return
		end
		local maximum = math.max(1, humanoid.MaxHealth)
		local ratio = math.clamp(humanoid.Health / maximum, 0, 1)
		if healthLabel then healthLabel.Text = string.format("%d / %d", math.ceil(humanoid.Health), math.ceil(maximum)) end
		if healthFill then
			healthFill.Size = UDim2.fromScale(ratio, 1)
			healthFill.BackgroundColor3 = if ratio > 0.5 then Color3.fromRGB(78, 184, 99) elseif ratio > 0.25 then Color3.fromRGB(216, 165, 64) else Color3.fromRGB(205, 70, 62)
		end
	end), "Disconnect")
end

return SpectateController
