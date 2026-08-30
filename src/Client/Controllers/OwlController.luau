--[[
    @file    OwlController.luau
    @author  manik
    @date    2025

    @summary
    Client-side UI for the Owl NPC — eye icon detection meter,
    "The Owl has woken up" banner, scream flash, and damage feedback.

    @description
    Builds its own ScreenGui with:
    - A centred banner for the Owl awakening announcement
    - Two eye icons that tint from white to red based on the detection meter
    - A red screen flash when the Owl screams (enters chase)
    - A damage flash when the Owl contacts the local player

    @exports
    - OwlController (Knit Controller)
]]

-- // VARIABLES // --

-- | Services | --
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")

-- | Modules | --
local Knit = require(ReplicatedStorage.Packages.Knit)
local ServerRole = require(ReplicatedStorage.Shared.ServerRole)

-- | Objects | --
local OwlController = Knit.CreateController({
	Name = "OwlController",
})

-- | Configuration | --
local BANNER_FADE_IN = 0.4
local BANNER_HOLD = 3.5
local BANNER_FADE_OUT = 0.8
local BANNER_COLOR = Color3.fromRGB(180, 200, 255)
local SCREAM_FLASH_DURATION = 0.4
local DAMAGE_FLASH_DURATION = 0.35
local EYE_BASE_COLOR = Color3.fromRGB(220, 220, 220)
local EYE_DANGER_COLOR = Color3.fromRGB(220, 40, 40)

-- | State Management | --
local screenGui: ScreenGui? = nil
local banner: TextLabel? = nil
local bannerThread: thread? = nil
local eyeLeft: ImageLabel? = nil
local eyeRight: ImageLabel? = nil
local eyeContainer: Frame? = nil
local screamCorrection: ColorCorrectionEffect? = nil
local damageCorrection: ColorCorrectionEffect? = nil

-- // FUNCTIONS // --

-- | Private | --

--[[
    @summary  Build the Owl UI ScreenGui once.
]]
local function ensureGui()
	if screenGui then
		return
	end
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

	local gui = Instance.new("ScreenGui")
	gui.Name = "OwlUI"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.Parent = playerGui

	-- Banner (top centre)
	local label = Instance.new("TextLabel")
	label.Name = "OwlBanner"
	label.AnchorPoint = Vector2.new(0.5, 0)
	label.Position = UDim2.new(0.5, 0, 0.08, 0)
	label.Size = UDim2.new(0, 620, 0, 60)
	label.BackgroundColor3 = Color3.fromRGB(10, 10, 20)
	label.BackgroundTransparency = 1
	label.TextColor3 = BANNER_COLOR
	label.Font = Enum.Font.GothamBlack
	label.TextSize = 26
	label.TextTransparency = 1
	label.Text = ""
	label.Parent = gui

	-- Eye icon container (top centre, below banner)
	local container = Instance.new("Frame")
	container.Name = "EyeContainer"
	container.AnchorPoint = Vector2.new(0.5, 0)
	container.Position = UDim2.new(0.5, 0, 0.18, 0)
	container.Size = UDim2.new(0, 200, 0, 80)
	container.BackgroundTransparency = 1
	container.Visible = false
	container.Parent = gui

	-- Left eye
	local leftEye = Instance.new("ImageLabel")
	leftEye.Name = "EyeLeft"
	leftEye.AnchorPoint = Vector2.new(1, 0.5)
	leftEye.Position = UDim2.new(0.45, 0, 0.5, 0)
	leftEye.Size = UDim2.new(0, 70, 0, 70)
	leftEye.BackgroundTransparency = 1
	leftEye.Image = "rbxassetid://277232280" -- generic eye/circle icon
	leftEye.ImageColor3 = EYE_BASE_COLOR
	leftEye.ScaleType = Enum.ScaleType.Fit
	leftEye.Parent = container

	-- Right eye
	local rightEye = Instance.new("ImageLabel")
	rightEye.Name = "EyeRight"
	rightEye.AnchorPoint = Vector2.new(0, 0.5)
	rightEye.Position = UDim2.new(0.55, 0, 0.5, 0)
	rightEye.Size = UDim2.new(0, 70, 0, 70)
	rightEye.BackgroundTransparency = 1
	rightEye.Image = "rbxassetid://277232280"
	rightEye.ImageColor3 = EYE_BASE_COLOR
	rightEye.ScaleType = Enum.ScaleType.Fit
	rightEye.Parent = container

	screenGui = gui
	banner = label
	eyeContainer = container
	eyeLeft = leftEye
	eyeRight = rightEye
end

--[[
    @summary  Show the banner with fade in/hold/fade out.
    @param    text   string
    @param    color  Color3
]]
local function showBanner(text: string, color: Color3)
	ensureGui()
	if not banner then
		return
	end

	if bannerThread then
		task.cancel(bannerThread)
	end

	bannerThread = task.spawn(function()
		banner.Text = text
		banner.TextColor3 = color
		TweenService:Create(banner, TweenInfo.new(BANNER_FADE_IN), {
			TextTransparency = 0,
			BackgroundTransparency = 0.25,
		}):Play()
		task.wait(BANNER_FADE_IN + BANNER_HOLD)
		TweenService:Create(banner, TweenInfo.new(BANNER_FADE_OUT), {
			TextTransparency = 1,
			BackgroundTransparency = 1,
		}):Play()
		bannerThread = nil
	end)
end

--[[
    @summary  Update the eye icon colour based on detection meter (0-1).
    @param    meter  number
]]
local function updateEyeMeter(meter: number)
	ensureGui()
	if not eyeLeft or not eyeRight or not eyeContainer then
		return
	end

	if meter <= 0 then
		eyeContainer.Visible = false
		return
	end

	eyeContainer.Visible = true
	local color = EYE_BASE_COLOR:Lerp(EYE_DANGER_COLOR, meter)
	eyeLeft.ImageColor3 = color
	eyeRight.ImageColor3 = color
end

--[[
    @summary  Flash the screen red briefly (Owl scream).
]]
local function flashScream()
	local correction: ColorCorrectionEffect
	if not screamCorrection then
		local newCorrection = Instance.new("ColorCorrectionEffect") :: ColorCorrectionEffect
		newCorrection.Name = "OwlScreamFlash"
		newCorrection.Parent = Lighting
		screamCorrection = newCorrection
	end
	if not screamCorrection then
		return
	end
	correction = screamCorrection :: ColorCorrectionEffect
	correction.TintColor = Color3.fromRGB(255, 200, 200)
	correction.Brightness = 0.1
	correction.Contrast = 0.2

	task.spawn(function()
		TweenService:Create(correction, TweenInfo.new(SCREAM_FLASH_DURATION), {
			TintColor = Color3.fromRGB(255, 255, 255),
			Brightness = 0,
			Contrast = 0,
		}):Play()
	end)
end

--[[
    @summary  Flash the screen red when the local player takes Owl damage.
]]
local function flashDamage()
	local correction: ColorCorrectionEffect
	if not damageCorrection then
		local newCorrection = Instance.new("ColorCorrectionEffect") :: ColorCorrectionEffect
		newCorrection.Name = "OwlDamageFlash"
		newCorrection.Parent = Lighting
		damageCorrection = newCorrection
	end
	if not damageCorrection then
		return
	end
	correction = damageCorrection :: ColorCorrectionEffect
	correction.TintColor = Color3.fromRGB(160, 0, 0)
	correction.Brightness = 0

	task.spawn(function()
		TweenService:Create(correction, TweenInfo.new(DAMAGE_FLASH_DURATION), {
			TintColor = Color3.fromRGB(255, 255, 255),
		}):Play()
	end)
end

-- // INITIALIZATION // --

function OwlController:KnitStart()
	if not ServerRole.IsGameServer() then return end
	local owlService = Knit.GetService("OwlService")

	owlService.OwlActive:Connect(function()
		showBanner("The Owl has woken up...", BANNER_COLOR)
	end)

	owlService.OwlDetection:Connect(function(meter: number)
		updateEyeMeter(meter)
	end)

	owlService.OwlScream:Connect(function(_position: Vector3)
		flashScream()
		showBanner("The Owl is hunting you!", EYE_DANGER_COLOR)
	end)

	owlService.OwlContact:Connect(function(_position: Vector3)
		flashDamage()
	end)

	owlService.OwlStunned:Connect(function(_position: Vector3, _duration: number)
		showBanner("The Owl is stunned!", Color3.fromRGB(150, 200, 255))
	end)

	owlService.OwlRetreated:Connect(function()
		updateEyeMeter(0)
		showBanner("The Owl has flown away.", Color3.fromRGB(150, 200, 150))
	end)

end

return OwlController
