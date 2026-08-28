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

return UiSoundUtil
