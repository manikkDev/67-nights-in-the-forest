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
local teamPanel: Frame? = nil
local eliminatedBanner: Frame? = nil
local selfState = "Lobby"
local memberStates: { [number]: string } = {}
memberStates = {}
local targetIndex = 1
local currentTarget: Player? = nil
local spectating = false
local memberNames: { [number]: string } = {}

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

-- Map life state to display label and color
local STATE_COLORS = {
	Alive    = Color3.fromRGB(78,  184, 99),
	Downed   = Color3.fromRGB(216, 165, 64),
	Eliminated = Color3.fromRGB(200, 60, 55),
	Lobby    = Color3.fromRGB(110, 115, 125),
}
local STATE_LABELS = { Alive = "Alive", Downed = "Down", Eliminated = "Gone", Lobby = "Lobby" }

local function updateTeamPanel()
	if not teamPanel then return end
	for _, row in ipairs(teamPanel:GetChildren()) do
		if row:IsA("Frame") then row:Destroy() end
	end
	local order = 0
	for _, p in ipairs(Players:GetPlayers()) do
		if p == localPlayer then continue end
		order += 1
		local state = memberStates[p.UserId] or "Lobby"
		local stateColor = STATE_COLORS[state] or STATE_COLORS.Lobby
		local stateLabel = STATE_LABELS[state] or state

		local row = Instance.new("Frame")
		row.Name = "TeamRow_" .. p.UserId
		row.Size = UDim2.new(1, 0, 0, 32)
		row.BackgroundColor3 = Color3.fromRGB(16, 19, 23)
		row.BackgroundTransparency = 0.1
		row.BorderSizePixel = 0
		row.LayoutOrder = order
		row.Parent = teamPanel
		local rc = Instance.new("UICorner")
		rc.CornerRadius = UDim.new(0, 7)
		rc.Parent = row

		local dot = Instance.new("Frame")
		dot.AnchorPoint = Vector2.new(0, 0.5)
		dot.Position = UDim2.fromOffset(8, 16)
		dot.Size = UDim2.fromOffset(8, 8)
		dot.BackgroundColor3 = stateColor
		dot.BorderSizePixel = 0
		dot.Parent = row
		local dc = Instance.new("UICorner")
		dc.CornerRadius = UDim.new(1, 0)
		dc.Parent = dot

		local nameLabel = Instance.new("TextLabel")
		nameLabel.AnchorPoint = Vector2.new(0, 0.5)
		nameLabel.Position = UDim2.fromOffset(22, 16)
		nameLabel.Size = UDim2.new(0.6, -22, 0, 22)
		nameLabel.BackgroundTransparency = 1
		nameLabel.Font = Enum.Font.GothamBold
		nameLabel.Text = p.DisplayName
		nameLabel.TextColor3 = Color3.fromRGB(220, 220, 218)
		nameLabel.TextSize = 12
		nameLabel.TextXAlignment = Enum.TextXAlignment.Left
		nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
		nameLabel.Parent = row

		local stateText = Instance.new("TextLabel")
		stateText.AnchorPoint = Vector2.new(1, 0.5)
		stateText.Position = UDim2.new(1, -6, 0.5, 0)
		stateText.Size = UDim2.fromOffset(44, 20)
		stateText.BackgroundTransparency = 1
		stateText.Font = Enum.Font.GothamBold
		stateText.Text = stateLabel
		stateText.TextColor3 = stateColor
		stateText.TextSize = 11
		stateText.TextXAlignment = Enum.TextXAlignment.Right
		stateText.Parent = row
	end
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

	-- === Full-width dark vignette strip at top (context label behind status) ===
	local topStrip = Instance.new("Frame")
	topStrip.Name = "TopStrip"
	topStrip.Size = UDim2.new(1, 0, 0, 100)
	topStrip.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	topStrip.BackgroundTransparency = 0.55
	topStrip.BorderSizePixel = 0
	topStrip.Parent = screenGui
	local stripGrad = Instance.new("UIGradient")
	stripGrad.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(0, 0, 0)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(0, 0, 0)),
	})
	stripGrad.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.3),
		NumberSequenceKeypoint.new(1, 1),
	})
	stripGrad.Rotation = 90
	stripGrad.Parent = topStrip

	-- === "ELIMINATED" cinematic banner (center, fades away) ===
	local banner = Instance.new("Frame")
	banner.Name = "EliminatedBanner"
	banner.AnchorPoint = Vector2.new(0.5, 0.5)
	banner.Position = UDim2.fromScale(0.5, 0.5)
	banner.Size = UDim2.new(0.7, 0, 0, 80)
	banner.BackgroundColor3 = Color3.fromRGB(10, 6, 6)
	banner.BackgroundTransparency = 1
	banner.BorderSizePixel = 0
	banner.Visible = false
	banner.Parent = screenGui
	local bannerConstraint = Instance.new("UISizeConstraint")
	bannerConstraint.MaxSize = Vector2.new(460, 80)
	bannerConstraint.Parent = banner
	local bannerCorner = Instance.new("UICorner")
	bannerCorner.CornerRadius = UDim.new(0, 14)
	bannerCorner.Parent = banner
	local bannerStroke = Instance.new("UIStroke")
	bannerStroke.Color = Color3.fromRGB(180, 42, 38)
	bannerStroke.Thickness = 2
	bannerStroke.Transparency = 1
	bannerStroke.Parent = banner
	local bannerLabel = Instance.new("TextLabel")
	bannerLabel.Size = UDim2.new(1, 0, 0.6, 0)
	bannerLabel.Position = UDim2.fromScale(0, 0.1)
	bannerLabel.BackgroundTransparency = 1
	bannerLabel.Font = Enum.Font.GothamBlack
	bannerLabel.Text = "YOU HAVE BEEN ELIMINATED"
	bannerLabel.TextColor3 = Color3.fromRGB(230, 55, 50)
	bannerLabel.TextSize = 26
	bannerLabel.TextTransparency = 1
	bannerLabel.Parent = banner
	local bannerSub = Instance.new("TextLabel")
	bannerSub.AnchorPoint = Vector2.new(0.5, 1)
	bannerSub.Position = UDim2.new(0.5, 0, 1, -10)
	bannerSub.Size = UDim2.new(1, 0, 0, 20)
	bannerSub.BackgroundTransparency = 1
	bannerSub.Font = Enum.Font.GothamBold
	bannerSub.Text = "Spectating teammates..."
	bannerSub.TextColor3 = Color3.fromRGB(185, 145, 140)
	bannerSub.TextSize = 14
	bannerSub.TextTransparency = 1
	bannerSub.Parent = banner
	eliminatedBanner = banner

	-- === Top-center status panel (who we're spectating + health) ===
	local status = Instance.new("Frame")
	status.AnchorPoint = Vector2.new(0.5, 0)
	status.Position = UDim2.new(0.5, 0, 0, 16)
	status.Size = UDim2.new(0.72, 0, 0, 90)
	status.BackgroundColor3 = Color3.fromRGB(14, 16, 21)
	status.BackgroundTransparency = 0.1
	status.BorderSizePixel = 0
	status.Parent = screenGui
	local statusConstraint = Instance.new("UISizeConstraint")
	statusConstraint.MaxSize = Vector2.new(420, 90)
	statusConstraint.MinSize = Vector2.new(260, 84)
	statusConstraint.Parent = status
	local statusCorner = Instance.new("UICorner")
	statusCorner.CornerRadius = UDim.new(0, 14)
	statusCorner.Parent = status
	local statusStroke = Instance.new("UIStroke")
	statusStroke.Color = Color3.fromRGB(60, 68, 80)
	statusStroke.Transparency = 0.15
	statusStroke.Parent = status

	local eyebrow = Instance.new("TextLabel")
	eyebrow.Position = UDim2.fromOffset(16, 10)
	eyebrow.Size = UDim2.new(1, -32, 0, 18)
	eyebrow.BackgroundTransparency = 1
	eyebrow.Font = Enum.Font.GothamBold
	eyebrow.Text = "SPECTATING"
	eyebrow.TextColor3 = Color3.fromRGB(140, 152, 170)
	eyebrow.TextSize = 11
	eyebrow.TextXAlignment = Enum.TextXAlignment.Left
	eyebrow.Parent = status

	local target = Instance.new("TextLabel")
	target.Position = UDim2.fromOffset(16, 27)
	target.Size = UDim2.new(1, -110, 0, 30)
	target.BackgroundTransparency = 1
	target.Font = Enum.Font.GothamBlack
	target.Text = "Finding teammate..."
	target.TextColor3 = Color3.fromRGB(245, 245, 240)
	target.TextSize = 22
	target.TextTruncate = Enum.TextTruncate.AtEnd
	target.TextXAlignment = Enum.TextXAlignment.Left
	target.Parent = status
	targetLabel = target

	local healthText = Instance.new("TextLabel")
	healthText.AnchorPoint = Vector2.new(1, 0)
	healthText.Position = UDim2.new(1, -14, 0, 30)
	healthText.Size = UDim2.fromOffset(88, 22)
	healthText.BackgroundTransparency = 1
	healthText.Font = Enum.Font.GothamBold
	healthText.Text = "-- / --"
	healthText.TextColor3 = Color3.fromRGB(100, 215, 110)
	healthText.TextSize = 14
	healthText.TextXAlignment = Enum.TextXAlignment.Right
	healthText.Parent = status
	healthLabel = healthText

	local healthBack = Instance.new("Frame")
	healthBack.Position = UDim2.fromOffset(16, 64)
	healthBack.Size = UDim2.new(1, -32, 0, 8)
	healthBack.BackgroundColor3 = Color3.fromRGB(40, 43, 50)
	healthBack.BorderSizePixel = 0
	healthBack.Parent = status
	local healthBackCorner = Instance.new("UICorner")
	healthBackCorner.CornerRadius = UDim.new(1, 0)
	healthBackCorner.Parent = healthBack
	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = Color3.fromRGB(80, 195, 95)
	fill.BorderSizePixel = 0
	fill.Parent = healthBack
	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(1, 0)
	fillCorner.Parent = fill
	healthFill = fill

	-- === "No one to spectate" message (centered) ===
	local empty = Instance.new("TextLabel")
	empty.AnchorPoint = Vector2.new(0.5, 0.5)
	empty.Position = UDim2.fromScale(0.5, 0.5)
	empty.Size = UDim2.new(0.8, 0, 0, 70)
	empty.BackgroundTransparency = 1
	empty.Font = Enum.Font.GothamBold
	empty.Text = "No alive teammates to spectate."
	empty.TextColor3 = Color3.fromRGB(210, 210, 208)
	empty.TextSize = 18
	empty.TextWrapped = true
	empty.Visible = false
	empty.Parent = screenGui
	emptyLabel = empty

	-- === Team status panel — bottom-right, compact ===
	local tp = Instance.new("Frame")
	tp.Name = "TeamPanel"
	tp.AnchorPoint = Vector2.new(1, 1)
	tp.Position = UDim2.new(1, -10, 1, -80)
	tp.Size = UDim2.fromOffset(165, 0)
	tp.AutomaticSize = Enum.AutomaticSize.Y
	tp.BackgroundColor3 = Color3.fromRGB(12, 14, 18)
	tp.BackgroundTransparency = 0.15
	tp.BorderSizePixel = 0
	tp.Parent = screenGui
	local tpCorner = Instance.new("UICorner")
	tpCorner.CornerRadius = UDim.new(0, 10)
	tpCorner.Parent = tp
	local tpStroke = Instance.new("UIStroke")
	tpStroke.Color = Color3.fromRGB(50, 56, 66)
	tpStroke.Transparency = 0.3
	tpStroke.Parent = tp
	local tpLayout = Instance.new("UIListLayout")
	tpLayout.Padding = UDim.new(0, 3)
	tpLayout.SortOrder = Enum.SortOrder.LayoutOrder
	tpLayout.Parent = tp
	local tpPad = Instance.new("UIPadding")
	tpPad.PaddingTop = UDim.new(0, 6)
	tpPad.PaddingBottom = UDim.new(0, 6)
	tpPad.PaddingLeft = UDim.new(0, 6)
	tpPad.PaddingRight = UDim.new(0, 6)
	tpPad.Parent = tp
	-- Team panel header
	local tpHeader = Instance.new("TextLabel")
	tpHeader.Size = UDim2.new(1, 0, 0, 18)
	tpHeader.BackgroundTransparency = 1
	tpHeader.Font = Enum.Font.GothamBold
	tpHeader.Text = "TEAMMATES"
	tpHeader.TextColor3 = Color3.fromRGB(130, 140, 158)
	tpHeader.TextSize = 10
	tpHeader.LayoutOrder = 0
	tpHeader.Parent = tp
	teamPanel = tp

	-- === Bottom navigation bar (Prev / info / Next) ===
	local navBar = Instance.new("Frame")
	navBar.Name = "NavBar"
	navBar.AnchorPoint = Vector2.new(0.5, 1)
	navBar.Position = UDim2.new(0.5, 0, 1, -12)
	navBar.Size = UDim2.new(0, 320, 0, 48)
	navBar.BackgroundColor3 = Color3.fromRGB(12, 14, 18)
	navBar.BackgroundTransparency = 0.1
	navBar.BorderSizePixel = 0
	navBar.Parent = screenGui
	local navConstraint = Instance.new("UISizeConstraint")
	navConstraint.MaxSize = Vector2.new(360, 48)
	navConstraint.Parent = navBar
	local navCorner = Instance.new("UICorner")
	navCorner.CornerRadius = UDim.new(0, 24)
	navCorner.Parent = navBar
	local navStroke = Instance.new("UIStroke")
	navStroke.Color = Color3.fromRGB(55, 62, 75)
	navStroke.Transparency = 0.2
	navStroke.Parent = navBar

	local prevBtn = makeButton(navBar, "Previous", "◄  Prev", UDim2.new(0.5, -80, 0.5, 0))
	prevBtn.AnchorPoint = Vector2.new(1, 0.5)
	prevBtn.Position = UDim2.new(0.5, -8, 0.5, 0)
	prevBtn.Size = UDim2.fromOffset(120, 36)

	local nextBtn = makeButton(navBar, "Next", "Next  ►", UDim2.new(0.5, 8, 0.5, 0))
	nextBtn.AnchorPoint = Vector2.new(0, 0.5)
	nextBtn.Size = UDim2.fromOffset(120, 36)

	prevBtn.Activated:Connect(function() SpectateController:Cycle(-1) end)
	nextBtn.Activated:Connect(function() SpectateController:Cycle(1) end)
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

local function startSpectating(isDowned: boolean?)
	buildUi()
	if spectating then
		-- Update eyebrow label if state changed (downed → eliminated or vice versa)
		local statusFrame = gui and gui:FindFirstChild("Frame") -- the top status panel isn't named
		-- Find eyebrow via traversal
		if gui then
			for _, child in ipairs(gui:GetChildren()) do
				if child:IsA("Frame") and child.Name ~= "EliminatedBanner" and child.Name ~= "NavBar" and child.Name ~= "TeamPanel" and child.Name ~= "TopStrip" then
					local ey = child:FindFirstChild("TextLabel")
					if ey and ey.Text:find("SPECTATING") then
						ey.Text = isDowned and "DOWNED — Watching Teammates" or "SPECTATING"
					end
				end
			end
		end
		updateTarget()
		return
	end

	-- Show "ELIMINATED" cinematic banner only for eliminated players (not downed)
	if not isDowned and eliminatedBanner then
		local TweenService = game:GetService("TweenService")
		eliminatedBanner.Visible = true
		eliminatedBanner.BackgroundTransparency = 1
		for _, desc in ipairs(eliminatedBanner:GetDescendants()) do
			if desc:IsA("TextLabel") then desc.TextTransparency = 1 end
			if desc:IsA("UIStroke") then desc.Transparency = 1 end
		end
		TweenService:Create(eliminatedBanner, TweenInfo.new(0.4, Enum.EasingStyle.Quad), { BackgroundTransparency = 0.12 }):Play()
		local stroke = eliminatedBanner:FindFirstChildOfClass("UIStroke")
		if stroke then TweenService:Create(stroke, TweenInfo.new(0.4), { Transparency = 0.15 }):Play() end
		for _, desc in ipairs(eliminatedBanner:GetDescendants()) do
			if desc:IsA("TextLabel") then
				TweenService:Create(desc, TweenInfo.new(0.5, Enum.EasingStyle.Quad), { TextTransparency = 0 }):Play()
			end
		end
		task.delay(2.5, function()
			if eliminatedBanner then
				TweenService:Create(eliminatedBanner, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { BackgroundTransparency = 1 }):Play()
				for _, desc in ipairs(eliminatedBanner:GetDescendants()) do
					if desc:IsA("TextLabel") then
						TweenService:Create(desc, TweenInfo.new(0.4), { TextTransparency = 1 }):Play()
					end
				end
				task.delay(0.55, function()
					if eliminatedBanner then eliminatedBanner.Visible = false end
				end)
			end
		end)
	end

	-- Update the eyebrow label based on downed vs eliminated state
	if gui then
		for _, child in ipairs(gui:GetChildren()) do
			if child:IsA("Frame") and child.Name ~= "EliminatedBanner" and child.Name ~= "NavBar" and child.Name ~= "TeamPanel" and child.Name ~= "TopStrip" then
				local eyebrowLabel = child:FindFirstChild("TextLabel")
				if eyebrowLabel then
					eyebrowLabel.Text = isDowned and "DOWNED — Watching Teammates" or "SPECTATING"
					eyebrowLabel.TextColor3 = if isDowned
						then Color3.fromRGB(230, 150, 60)
						else Color3.fromRGB(140, 152, 170)
				end
			end
		end
	end

	spectating = true
	targetIndex = 1
	if gui then gui.Enabled = true end
	ContextActionService:BindAction(NEXT_ACTION, onAction, false, Enum.KeyCode.E, Enum.KeyCode.ButtonR1, Enum.KeyCode.DPadRight)
	ContextActionService:BindAction(PREVIOUS_ACTION, onAction, false, Enum.KeyCode.Q, Enum.KeyCode.ButtonL1, Enum.KeyCode.DPadLeft)
	updateTarget()
	updateTeamPanel()
end

function SpectateController:Cycle(direction: number)
	if not spectating then return end
	targetIndex += direction
	updateTarget()
end

function SpectateController:KnitStart()
	if not ServerRole.IsGameServer() then return end
	lifeService = Knit.GetService("PlayerLifeService")
	local runStateService = Knit.GetService("RunStateService")
	buildUi()
	janitor:Add(lifeService.LifeStateChanged:Connect(function(payload)
		if typeof(payload) ~= "table" or typeof(payload.userId) ~= "number" then return end
		memberStates[payload.userId] = payload.state
		if payload.userId == localPlayer.UserId then
			selfState = payload.state
			if selfState == "Eliminated" then
				startSpectating(false)
			elseif selfState == "Downed" then
				startSpectating(true)
			else
				stopSpectating()
			end
		elseif spectating then
			updateTarget()
		end
		updateTeamPanel()
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
		if selfState == "Eliminated" then startSpectating(false)
		elseif selfState == "Downed" then startSpectating(true)
		end
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
