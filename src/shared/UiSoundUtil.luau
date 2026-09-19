--[[
    @file    UiSoundUtil.luau
    @author  manik
    @date    2026

    @summary
    Reusable client-side UI sound player. Any controller can require
    this module and call playClick / playSuccess / playLevelUp to
    play standard UI feedback sounds.

    Sounds are created lazily, cached, and parented to SoundService
    so they persist across UI rebuilds.
]]

-- | Services | --
local SoundService = game:GetService("SoundService")

-- | Modules | --
local AssetCatalog = require(script.Parent.AssetCatalog)

-- | State | --
local sounds: { [string]: Sound } = {}

--[[
    @summary  Get or create a cached Sound instance for a given asset.
    @param    key     string  -- cache key
    @param    soundId string  -- rbxassetid://...
    @param    volume  number  -- 0..1
    @returns  Sound
]]
local function getSound(key: string, soundId: string, volume: number): Sound
	if sounds[key] and sounds[key].Parent then
		return sounds[key]
	end
	local sound = Instance.new("Sound")
	sound.Name = "Ui_" .. key
	sound.SoundId = soundId
	sound.Volume = volume
	sound.Parent = SoundService
	sounds[key] = sound
	return sound
end

--[[
    @summary  Play a sound from the beginning.
    @param    sound  Sound
]]
local function playFromStart(sound: Sound)
	sound:Stop()
	sound:Play()
end

-- // PUBLIC API // --

local UiSoundUtil = {}

--[[
    @summary  Play a short UI button click sound.
]]
function UiSoundUtil.playClick()
	local sound = getSound("Click", AssetCatalog.Audio.UIClick, 0.4)
	playFromStart(sound)
end

--[[
    @summary  Play a success sound (satisfying thunk on craft success).
]]
function UiSoundUtil.playSuccess()
	local sound = getSound("Success", AssetCatalog.Audio.UISuccess, 0.5)
	playFromStart(sound)
end

--[[
    @summary  Play a level-up whoosh sound (bench tier upgrade).
]]
function UiSoundUtil.playLevelUp()
	local sound = getSound("LevelUp", AssetCatalog.Audio.UILevelUp, 0.6)
	playFromStart(sound)
end

--[[
    @summary  Play a short dramatic sting for urgent alerts
              (teammate downed, warnings).
]]
function UiSoundUtil.playAlert()
	local sound = getSound("Alert", AssetCatalog.Audio.AlertSting, 0.45)
	playFromStart(sound)
end

--[[
    @summary  Play a result sting for endings.
    @param    victory  boolean
]]
function UiSoundUtil.playSting(victory: boolean)
	local id = if victory then AssetCatalog.Audio.VictorySting else AssetCatalog.Audio.DefeatSting
	local sound = getSound(if victory then "VictorySting" else "DefeatSting", id, 0.55)
	playFromStart(sound)
end

--[[
    @summary  Start a looping ambience (e.g. heartbeat while downed).
              No-op if the named loop is already playing.
    @param    name     string  -- unique loop key
    @param    soundId  string
    @param    volume   number
]]
function UiSoundUtil.startLoop(name: string, soundId: string, volume: number)
	local sound = getSound("Loop_" .. name, soundId, volume)
	sound.Looped = true
	if not sound.IsPlaying then
		sound:Play()
	end
end

--[[
    @summary  Stop a named loop started by startLoop.
    @param    name  string
]]
function UiSoundUtil.stopLoop(name: string)
	local sound = sounds["Loop_" .. name]
	if sound then
		sound:Stop()
	end
end

return UiSoundUtil
