--[[
    @file    TorchController.luau
    @author  manik
    @date    2026

    @summary
    Client-side torch toggle with on-screen indicator.

    @description
    Toggles the equipped Torch's PointLight/Fire/Sound locally for
    instant feedback. Shows a small flame icon in the bottom-center
    hotbar area when the torch is lit. Click to ignite, click again
    to extinguish.

    @exports
    - TorchController (Knit Controller)
]]

-- // VARIABLES // --

-- | Services | --
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

-- | Modules | --
local Knit = require(ReplicatedStorage.Packages.Knit)
local Janitor = require(ReplicatedStorage.Packages.Janitor)

-- | Objects | --
local TorchController = Knit.CreateController({
	Name = "TorchController",
})

-- | Configuration | --
local TORCH_TOOL_NAME = "Torch"
local UI_ICON_SIZE = 44
local UI_ICON_MARGIN = 8

-- | State Management | --
local janitor = Janitor.new()
local toolJanitor = Janitor.new()
local charJanitor = Janitor.new()
local gameStateController: any = nil
local isLit = false
local indicatorGui: ScreenGui? = nil
local indicatorFrame: Frame? = nil
local indicatorIcon: TextLabel? = nil
local indicatorLabel: TextLabel? = nil

-- // FUNCTIONS // --

--[[
    @summary  Update the on-screen torch indicator.
    @param    lit  boolean
]]
local function updateIndicator(lit: boolean)
	isLit = lit
	if not indicatorFrame then
		return
	end

	if lit then
		indicatorFrame.BackgroundColor3 = Color3.fromRGB(255, 140, 40)
		indicatorIcon.Text = "🔥"
		indicatorLabel.Text = "LIT"
		indicatorLabel.TextColor3 = Color3.fromRGB(255, 220, 150)
		TweenService:Create(indicatorFrame, TweenInfo.new(0.2), {
			BackgroundTransparency = 0.1,
		}):Play()
	else
		indicatorFrame.BackgroundColor3 = Color3.fromRGB(50, 50, 55)
		indicatorIcon.Text = "🪵"
		indicatorLabel.Text = "OFF"
		indicatorLabel.TextColor3 = Color3.fromRGB(160, 160, 170)
		TweenService:Create(indicatorFrame, TweenInfo.new(0.2), {
			BackgroundTransparency = 0.2,
		}):Play()
	end
end

--[[
    @summary  Toggle the PointLight/Fire/Sound on an equipped Torch tool.
    @param    tool  Tool
]]
local function toggleTorch(tool: Tool)
	local torchHead = tool:FindFirstChild("TorchHead")
	if not torchHead then
		return
	end

	local pointLight = torchHead:FindFirstChild("TorchLight")
	local fire = torchHead:FindFirstChild("TorchFire")

	local newState = not isLit

	if pointLight then
		pointLight.Enabled = newState
	end
	if fire then
		fire.Enabled = newState
	end

	updateIndicator(newState)
end

--[[
    @summary  Wire Tool.Activated on the given Torch tool.
    @param    tool  Tool
]]
local function wireTool(tool: Tool)
	toolJanitor:Cleanup()
	toolJanitor:Add(tool.Activated:Connect(function()
		if not gameStateController or not gameStateController:IsInGame() then
			return
		end
		toggleTorch(tool)
	end), "Disconnect")
	toolJanitor:Add(tool.Unequipped:Connect(function()
		updateIndicator(false)
		-- Stop fire/light when unequipped
		local torchHead = tool:FindFirstChild("TorchHead")
		if torchHead then
			local pl = torchHead:FindFirstChild("TorchLight")
			local fr = torchHead:FindFirstChild("TorchFire")
			if pl then pl.Enabled = false end
			if fr then fr.Enabled = false end
		end
	end), "Disconnect")
end

--[[
    @summary  Watch the player's Backpack and Character for the
              Torch tool being equipped.
    @param    player  Player
]]
local function watchForTorch(player: Player)
	local function checkCharacter(character: Model)
		toolJanitor:Cleanup()
		charJanitor:Cleanup()
		updateIndicator(false)

		local tool = character:FindFirstChild(TORCH_TOOL_NAME)
		if tool and tool:IsA("Tool") then
			wireTool(tool)
		end

		charJanitor:Add(character.ChildAdded:Connect(function(child)
			if child:IsA("Tool") and child.Name == TORCH_TOOL_NAME then
				wireTool(child)
			end
		end), "Disconnect")
	end

	janitor:Cleanup()
	janitor:Add(player.CharacterAdded:Connect(checkCharacter), "Disconnect")
	janitor:Add(player.CharacterRemoving:Connect(function()
		updateIndicator(false)
	end), "Disconnect")

	if player.Character then
		checkCharacter(player.Character)
	end
end

--[[
    @summary  Build the on-screen torch indicator UI.
]]
local function buildIndicator()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

	local gui = Instance.new("ScreenGui")
	gui.Name = "TorchIndicator"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false
	gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets

	local frame = Instance.new("Frame")
	frame.Name = "TorchFrame"
	frame.AnchorPoint = Vector2.new(0.5, 1)
	frame.Position = UDim2.new(0.5, 0, 1, -80)
	frame.Size = UDim2.new(0, UI_ICON_SIZE + UI_ICON_MARGIN * 2, 0, UI_ICON_SIZE + UI_ICON_MARGIN * 2 + 18)
	frame.BackgroundColor3 = Color3.fromRGB(50, 50, 55)
	frame.BackgroundTransparency = 0.2
	frame.BorderSizePixel = 0
	frame.Visible = false
	frame.Parent = gui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = frame

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(80, 80, 90)
	stroke.Thickness = 1.5
	stroke.Transparency = 0.4
	stroke.Parent = frame

	local icon = Instance.new("TextLabel")
	icon.Name = "Icon"
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.new(0.5, 0, 0.5, -9)
	icon.Size = UDim2.new(0, UI_ICON_SIZE, 0, UI_ICON_SIZE)
	icon.BackgroundTransparency = 1
	icon.Text = "🪵"
	icon.TextSize = 28
	icon.Font = Enum.Font.GothamBold
	icon.Parent = frame

	local label = Instance.new("TextLabel")
	label.Name = "StatusLabel"
	label.AnchorPoint = Vector2.new(0.5, 0)
	label.Position = UDim2.new(0.5, 0, 1, -16)
	label.Size = UDim2.new(0, 60, 0, 14)
	label.BackgroundTransparency = 1
	label.Text = "OFF"
	label.TextColor3 = Color3.fromRGB(160, 160, 170)
	label.Font = Enum.Font.GothamBold
	label.TextSize = 11
	label.Parent = frame

	indicatorGui = gui
	indicatorFrame = frame
	indicatorIcon = icon
	indicatorLabel = label

	gui.Parent = playerGui
end

--[[
    @summary  Show or hide the indicator based on whether the
              torch is in the player's inventory.
]]
local function refreshIndicatorVisibility()
	if not indicatorFrame then
		return
	end

	local character = Players.LocalPlayer.Character
	local backpack = Players.LocalPlayer:FindFirstChild("Backpack")

	local hasTorch = false
	if character and character:FindFirstChild(TORCH_TOOL_NAME) then
		hasTorch = true
	elseif backpack and backpack:FindFirstChild(TORCH_TOOL_NAME) then
		hasTorch = true
	end

	indicatorFrame.Visible = hasTorch
end

-- // INITIALIZATION // --

function TorchController:KnitStart()
	gameStateController = Knit.GetController("GameStateController")

	local player = Players.LocalPlayer

	buildIndicator()

	local function onGameStarted()
		watchForTorch(player)
		-- Check periodically if the torch is in inventory
		task.spawn(function()
			while true do
				refreshIndicatorVisibility()
				task.wait(1)
			end
		end)
	end

	if gameStateController and gameStateController:IsInGame() then
		onGameStarted()
	else
		if gameStateController then
			gameStateController.GameStarted:Connect(onGameStarted)
		end
	end

	print("[TorchController] Initialised — torch toggle/indicator active")
end

return TorchController
