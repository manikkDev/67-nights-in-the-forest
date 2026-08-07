--[[
    @file    HungerController.luau
    @author  manik
    @date    2025

    @summary
    Binds the Health and Hunger bars inside HealthBarFill to live data.

    @description
    Creates background/fill Frames inside the pre-existing HealthBarFill
    ScreenGui in StarterGui, then tweens the fill Frames in response to
    the local Humanoid's HealthChanged event and the server's
    HungerService.HungerChanged signal.

    @exports
    - HungerController (Knit Controller)
]]

-- // VARIABLES // --

-- | Services | --
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

-- | Modules | --
local Knit = require(ReplicatedStorage.Packages.Knit)

-- | Objects | --
local HungerController = Knit.CreateController({
	Name = "HungerController",
})

-- | Configuration | --
local BAR_TWEEN_INFO = TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

-- | State Management | --
local healthFill: Frame? = nil
local hungerFill: Frame? = nil

-- // FUNCTIONS // --

--[[
    @summary  Create a background/fill bar pair inside a ScreenGui.
    @param    gui       ScreenGui  -- the parent ScreenGui
    @param    yOffset   number     -- vertical pixel offset from the top
    @param    barColor  Color3     -- fill bar colour
    @param    barName   string     -- unique name prefix for the bar
    @returns  Frame                -- the fill Frame to be resized
]]
local function createBar(gui: ScreenGui, yOffset: number, barColor: Color3, barName: string): Frame
	local background = Instance.new("Frame")
	background.Name = barName .. "Background"
	background.Size = UDim2.new(0, 200, 0, 24)
	background.Position = UDim2.new(0, 20, 0, yOffset)
	background.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
	background.BackgroundTransparency = 0.2
	background.BorderSizePixel = 0
	background.Parent = gui

	local fill = Instance.new("Frame")
	fill.Name = barName .. "Fill"
	fill.Size = UDim2.new(1, 0, 1, 0)
	fill.BackgroundColor3 = barColor
	fill.BorderSizePixel = 0
	fill.Parent = background

	return fill
end

--[[
    @summary  Tween a fill Frame's width to represent a 0-1 ratio.
    @param    fill   Frame?  -- the fill Frame to resize
    @param    ratio  number  -- value between 0 and 1
]]
local function setFillRatio(fill: Frame?, ratio: number)
	if not fill then
		return
	end
	local clamped = math.clamp(ratio, 0, 1)
	TweenService:Create(fill, BAR_TWEEN_INFO, {
		Size = UDim2.new(clamped, 0, 1, 0),
	}):Play()
end

--[[
    @summary  Bind the Health bar to a character's Humanoid.
    @param    character  Model  -- the local player's character
]]
local function bindHumanoid(character: Model)
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	setFillRatio(healthFill, humanoid.Health / humanoid.MaxHealth)
	humanoid.HealthChanged:Connect(function(health)
		setFillRatio(healthFill, health / humanoid.MaxHealth)
	end)
end

-- // INITIALIZATION // --

function HungerController:KnitInit()
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")
	local gui = playerGui:WaitForChild("HealthBarFill") :: ScreenGui

	healthFill = createBar(gui, 70, Color3.fromRGB(200, 40, 40), "Health")
	hungerFill = createBar(gui, 100, Color3.fromRGB(210, 160, 40), "Hunger")

	-- Set initial fill to full so bars don't flash empty before first server update
	setFillRatio(hungerFill, 1)
	setFillRatio(healthFill, 1)

	if player.Character then
		bindHumanoid(player.Character)
	end
	player.CharacterAdded:Connect(bindHumanoid)
end

function HungerController:KnitStart()
	local hungerService = Knit.GetService("HungerService")
	hungerService.HungerChanged:Connect(function(hunger, maxHunger)
		setFillRatio(hungerFill, hunger / maxHunger)
	end)

	print("[HungerController] Initialised — bound to Health/Hunger")
end

return HungerController
