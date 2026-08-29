--[[
    @file    Phase4EffectsController.luau
    @author  manik
    @date    2025

    @summary
    Client-only ambience and short-lived feedback for crafting, building,
    cave reveals, child rescues, revives, and the final ending.
]]

-- // VARIABLES // --

-- | Services | --
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

-- | Modules | --
local Knit = require(ReplicatedStorage.Packages.Knit)
local ServerRole = require(ReplicatedStorage.Shared.ServerRole)
local Janitor = require(ReplicatedStorage.Packages.Janitor)
local AssetCatalog = require(ReplicatedStorage.Shared.AssetCatalog)

-- | Objects | --
local Phase4EffectsController = Knit.CreateController({
	Name = "Phase4EffectsController",
})
local janitor = Janitor.new()

-- | Configuration | --
local AUDIO_FADE = TweenInfo.new(2.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
local DAY_NIGHT_VOLUME = 0.24
local HORROR_VOLUME = 0.11

-- | State Management | --
local nightInsects: Sound? = nil
local horrorLayer: Sound? = nil
local impactSound: Sound? = nil
local transitionSound: Sound? = nil

-- // FUNCTIONS // --

--[[
    @summary  Create one managed Sound under SoundService.
    @param    name       string
    @param    soundId    string
    @param    looped     boolean
    @param    volume     number
    @returns  Sound
]]
local function createSound(name: string, soundId: string, looped: boolean, volume: number): Sound
	local sound = Instance.new("Sound")
	sound.Name = name
	sound.SoundId = soundId
	sound.Looped = looped
	sound.Volume = volume
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.Parent = SoundService
	janitor:Add(sound)
	return sound
end

--[[
    @summary  Crossfade the forest layers for the current phase.
    @param    isNight  boolean
]]
local function setNight(isNight: boolean)
	if not nightInsects or not horrorLayer then
		return
	end
	if not nightInsects.IsPlaying then
		nightInsects:Play()
	end
	if not horrorLayer.IsPlaying then
		horrorLayer:Play()
	end
	TweenService:Create(nightInsects, AUDIO_FADE, { Volume = if isNight then DAY_NIGHT_VOLUME else 0 }):Play()
	TweenService:Create(horrorLayer, AUDIO_FADE, { Volume = if isNight then HORROR_VOLUME else 0 }):Play()
end

--[[
    @summary  Emit a cleaned burst at one world position.
    @param    position  Vector3
    @param    color     Color3
    @param    count     number
]]
local function burst(position: Vector3, color: Color3, count: number)
	local anchor = Instance.new("Part")
	anchor.Name = "Phase4Effect"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.Position = position
	anchor.Parent = workspace

	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	emitter.Color = ColorSequence.new(color)
	emitter.LightEmission = 0.6
	emitter.Lifetime = NumberRange.new(0.45, 0.9)
	emitter.Speed = NumberRange.new(5, 11)
	emitter.SpreadAngle = Vector2.new(70, 70)
	emitter.Drag = 3
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.35),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Rate = 0
	emitter.Parent = anchor
	emitter:Emit(count)
	Debris:AddItem(anchor, 2)
end

--[[
    @summary  Play the shared impact sound from the listener.
]]
local function playImpact()
	if impactSound then
		impactSound.TimePosition = 0
		impactSound:Play()
	end
end

-- // INITIALIZATION // --

function Phase4EffectsController:KnitStart()
	if ServerRole.IsLobby() then return end
	local timeService = Knit.GetService("TimeService")
	local craftingService = Knit.GetService("CraftingService")
	local buildingService = Knit.GetService("BuildingService")
	local rescueService = Knit.GetService("RescueService")
	local lifeService = Knit.GetService("PlayerLifeService")
	local endingService = Knit.GetService("EndingService")
	local runStateService = Knit.GetService("RunStateService")

	nightInsects = createSound("NightInsects", AssetCatalog.Audio.NightInsects, true, 0)
	horrorLayer = createSound("HorrorForest", AssetCatalog.Audio.HorrorForest, true, 0)
	impactSound = createSound("BuildImpact", AssetCatalog.Audio.BuildImpact, false, 0.3)
	transitionSound = createSound("EndingWhoosh", AssetCatalog.Audio.TransitionWhoosh, false, 0.4)

	janitor:Add(timeService.NightStarted:Connect(function()
		setNight(true)
	end), "Disconnect")
	janitor:Add(timeService.DayStarted:Connect(function()
		setNight(false)
	end), "Disconnect")

	janitor:Add(craftingService.CraftSucceeded:Connect(function()
		playImpact()
	end), "Disconnect")
	janitor:Add(buildingService.StructurePlaced:Connect(function(payload)
		if typeof(payload) == "table" and typeof(payload.cframe) == "CFrame" then
			burst(payload.cframe.Position, Color3.fromRGB(205, 155, 90), 18)
			playImpact()
		end
	end), "Disconnect")
	janitor:Add(rescueService.CaveUnlocked:Connect(function(payload)
		if typeof(payload) == "table" and typeof(payload.position) == "Vector3" then
			burst(payload.position + Vector3.new(0, 7, 0), Color3.fromRGB(215, 80, 65), 28)
		end
	end), "Disconnect")
	janitor:Add(rescueService.RescueChanged:Connect(function()
		local campfire = workspace:FindFirstChild("Campfire", true)
		if campfire and campfire:IsA("BasePart") then
			burst(campfire.Position + Vector3.new(0, 4, 0), Color3.fromRGB(245, 215, 105), 40)
		end
	end), "Disconnect")
	janitor:Add(lifeService.ReviveCompleted:Connect(function(targetUserId)
		local target = game:GetService("Players"):GetPlayerByUserId(targetUserId)
		local rootPart = target and target.Character and target.Character:FindFirstChild("HumanoidRootPart")
		if rootPart and rootPart:IsA("BasePart") then
			burst(rootPart.Position, Color3.fromRGB(110, 225, 145), 24)
		end
	end), "Disconnect")
	janitor:Add(endingService.EndingStarted:Connect(function()
		setNight(false)
		if transitionSound then
			transitionSound:Play()
		end
	end), "Disconnect")
	janitor:Add(runStateService.RunPhaseChanged:Connect(function(payload)
		if typeof(payload) == "table" and payload.phase == "Lobby" then
			setNight(false)
		end
	end), "Disconnect")
end

return Phase4EffectsController
