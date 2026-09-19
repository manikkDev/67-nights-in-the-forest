--[[
    @file    WorldSoundUtil.luau
    @author  manik
    @date    2025

    @summary
    Helpers for playing short one-shot sounds in 3D space.

    @description
    `playAt` parents a Sound to a temporary anchored part at a world
    position so every nearby client hears it spatially (server-created
    parts replicate normally). `playOn` parents the sound to an existing
    BasePart so it moves with the instance. Both clean up via Debris.
    Pitch jitter keeps repeated one-shots from sounding identical.
]]

local Debris = game:GetService("Debris")

export type PlayOptions = {
	volume: number?,
	minDistance: number?,
	maxDistance: number?,
	pitchJitter: number?,
	maxLifetime: number?,
}

local WorldSoundUtil = {}

local DEFAULT_MIN_DISTANCE = 6
local DEFAULT_MAX_DISTANCE = 80

local function configure(sound: Sound, soundId: string, opts: PlayOptions?)
	sound.SoundId = soundId
	sound.Volume = (opts and opts.volume) or 0.5
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = (opts and opts.minDistance) or DEFAULT_MIN_DISTANCE
	sound.RollOffMaxDistance = (opts and opts.maxDistance) or DEFAULT_MAX_DISTANCE
	local jitter = (opts and opts.pitchJitter) or 0
	if jitter > 0 then
		sound.PlaybackSpeed = 1 + (math.random() * 2 - 1) * jitter
	end
end

--[[
    @summary  Play a one-shot at a world position via a temp anchored part.
    @param    soundId   string
    @param    position  Vector3
    @param    opts      PlayOptions?
    @returns  Sound
]]
function WorldSoundUtil.playAt(soundId: string, position: Vector3, opts: PlayOptions?): Sound
	local anchor = Instance.new("Part")
	anchor.Name = "WorldSoundAnchor"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.Position = position

	local sound = Instance.new("Sound")
	configure(sound, soundId, opts)
	sound.Parent = anchor
	anchor.Parent = workspace
	sound:Play()

	Debris:AddItem(anchor, (opts and opts.maxLifetime) or 8)
	return sound
end

--[[
    @summary  Play a one-shot attached to an existing part/model so the
              sound follows it. Caller decides the cleanup window.
    @param    parent    Instance   -- BasePart or Model (uses its pivot part)
    @param    soundId   string
    @param    opts      PlayOptions?
    @returns  Sound?
]]
function WorldSoundUtil.playOn(parent: Instance, soundId: string, opts: PlayOptions?): Sound?
	local host: Instance? = parent
	if parent:IsA("Model") then
		host = parent:FindFirstChild("HumanoidRootPart") or parent.PrimaryPart or parent:FindFirstChildWhichIsA("BasePart", true)
	end
	if not host or not host:IsA("BasePart") then
		return nil
	end
	local sound = Instance.new("Sound")
	configure(sound, soundId, opts)
	sound.Parent = host
	sound:Play()
	Debris:AddItem(sound, (opts and opts.maxLifetime) or 8)
	return sound
end

return WorldSoundUtil
