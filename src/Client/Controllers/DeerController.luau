--[[
    @file    DeerController.luau
    @author  manik
    @date    2025

    @summary
    Client-side animation player for the Deer and Ram Monster.

    @description
    Motor6D.Transform does NOT replicate from server to clients in Roblox.
    The server-side DeerService uses a custom KeyframeSequence player that
    writes Motor6D.Transform, but those writes are only visible on the
    server. This controller runs the SAME custom KeyframeSequence player
    locally on each client so the animations are actually visible.

    The server fires AnimationStateChanged(stalkerKey, trackName) whenever
    the Deer's animation state changes. This controller receives the signal,
    finds the stalker model in workspace, and plays/stops the corresponding
    custom track locally.

    @exports
    - DeerController (Knit Controller)
]]

-- // VARIABLES // --

-- | Services | --
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

-- | Modules | --
local Knit = require(ReplicatedStorage.Packages.Knit)
local ServerRole = require(ReplicatedStorage.Shared.ServerRole)

-- | Objects | --
local DeerController = Knit.CreateController({
	Name = "DeerController",
})

-- | State Management | --
-- { [stalkerKey] = { model = Model, tracks = { [name] = track }, motorMap = {...} } }
local stalkerData: { [string]: any } = {}
local heartbeatConnection: RBXScriptConnection? = nil

-- // CUSTOM KEYFRAME SEQUENCE PLAYER (client-side) // --

--[[
    @summary  Recursively collect poses from a Keyframe, preserving
              the parent-child hierarchy.
    @param    parent  Instance (Keyframe or Pose)
    @param    out     table to populate
]]
local function collectPoses(parent, out)
	for _, child in ipairs(parent:GetChildren()) do
		if child:IsA("Pose") then
			out[child.Name] = child.CFrame
			collectPoses(child, out)
		end
	end
end

--[[
    @summary  Parse a KeyframeSequence into a sorted list of
              { time = number, poses = { [name] = CFrame } }
    @param    kfs  KeyframeSequence
    @returns  { { time: number, poses: { [string]: CFrame } } }
]]
local function parseKeyframeSequence(kfs)
	local keyframes = {}
	for _, kf in ipairs(kfs:GetChildren()) do
		if kf:IsA("Keyframe") then
			local poses = {}
			collectPoses(kf, poses)
			table.insert(keyframes, { time = kf.Time, poses = poses })
		end
	end
	table.sort(keyframes, function(a, b) return a.time < b.time end)
	return keyframes
end

--[[
    @summary  Build a map of Motor6D name -> Motor6D instance for a model.
              Uses Part1.Name as the key (matches Pose names in KeyframeSequences).
    @param    model  Model
    @returns  { [string]: Motor6D }
]]
local function buildMotorMap(model)
	local map = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("Motor6D") and d.Part1 then
			map[d.Part1.Name] = d
		end
	end
	return map
end

--[[
    @summary  Build custom animation tracks from KeyframeSequences on the model.
              Each track mimics the AnimationTrack interface (IsPlaying,
              Play, Stop) so the server's track state maps directly.
    @param    model  Model
    @returns  { [string]: table }  map of track name -> custom track
]]
local function buildCustomTracks(model)
	local kfFolder = model:FindFirstChild("KeyframeSequences")
	if not kfFolder then return {} end

	local motorMap = buildMotorMap(model)
	local tracks = {}

	local nonLooped = { Jumpscare = true, StunnedStart = true, StunnedEnd = true, Attack = true, Scared = true }

	for _, kfs in ipairs(kfFolder:GetChildren()) do
		if kfs:IsA("KeyframeSequence") then
			local keyframes = parseKeyframeSequence(kfs)
			if #keyframes > 0 then
				local ct = {
					name = kfs.Name,
					keyframes = keyframes,
					length = kfs.Length,
					Looped = not nonLooped[kfs.Name],
					playhead = 0,
					_isPlaying = false,
					motorMap = motorMap,
					isCustom = true,
				}

				function ct:GetPlaying()
					return self._isPlaying
				end
				function ct:Play(fadeTime)
					self._isPlaying = true
					self.playhead = 0
				end
				function ct:Stop(fadeTime)
					self._isPlaying = false
					self.playhead = 0
					-- Reset transforms for poses in this track
					if #self.keyframes > 0 then
						for poseName, _ in pairs(self.keyframes[1].poses) do
							local motor = self.motorMap[poseName]
							if motor then
								motor.Transform = CFrame.identity
							end
						end
					end
				end

				-- Metatable to make IsPlaying work as a property
				setmetatable(ct, {
					__index = function(t, k)
						if k == "IsPlaying" then return t._isPlaying end
						return rawget(t, k)
					end,
					__newindex = function(t, k, v)
						if k == "IsPlaying" then t._isPlaying = v else rawset(t, k, v) end
					end,
				})

				tracks[kfs.Name] = ct
			end
		end
	end

	return tracks
end

--[[
    @summary  Advance a custom track's playhead and apply interpolated
              Motor6D.Transform values. Only applies to motors that exist
              in the model.
    @param    track  table (custom track)
    @param    dt     number
]]
local function tickCustomTrack(track, dt)
	if not track._isPlaying or #track.keyframes == 0 then return end

	track.playhead = track.playhead + dt

	-- Handle end of track
	if track.playhead >= track.length then
		if track.Looped then
			track.playhead = track.playhead % track.length
		else
			track.playhead = track.length
			track._isPlaying = false
			-- Reset transforms for this track's poses
			local lastKf = track.keyframes[#track.keyframes]
			for poseName, _ in pairs(lastKf.poses) do
				local motor = track.motorMap[poseName]
				if motor then
					motor.Transform = CFrame.identity
				end
			end
			return
		end
	end

	-- Find surrounding keyframes
	local kfs = track.keyframes
	local prevKf = kfs[1]
	local nextKf = kfs[#kfs]
	for i = 1, #kfs - 1 do
		if kfs[i].time <= track.playhead and kfs[i + 1].time > track.playhead then
			prevKf = kfs[i]
			nextKf = kfs[i + 1]
			break
		end
	end

	-- Interpolate and apply
	local span = nextKf.time - prevKf.time
	local alpha = if span > 0 then (track.playhead - prevKf.time) / span else 0
	alpha = math.clamp(alpha, 0, 1)

	for poseName, prevCf in pairs(prevKf.poses) do
		local nextCf = nextKf.poses[poseName] or prevCf
		local motor = track.motorMap[poseName]
		if motor then
			motor.Transform = prevCf:Lerp(nextCf, alpha)
		end
	end
end

--[[
    @summary  Find a stalker model in workspace by its key name.
              The model name matches the stalker key (e.g. "Deer", "Ram Monster").
    @param    stalkerKey  string
    @returns  Model?
]]
local function findStalkerModel(stalkerKey: string)
	-- The DeerService clones the template and names it the same as the
	-- template model. The stalker key maps to a model name via NpcConfig.
	-- We search workspace for a model whose name matches common patterns.
	for _, model in ipairs(Workspace:GetChildren()) do
		if model:IsA("Model") then
			local humanoid = model:FindFirstChildOfClass("Humanoid")
			if humanoid and model:FindFirstChild("KeyframeSequences") then
				-- Check if this model matches the stalker key
				if stalkerKey == "Deer" and model.Name == "Deer" then
					return model
				elseif stalkerKey == "RamMonster" and model.Name == "Ram Monster" then
					return model
				end
			end
		end
	end
	return nil
end

--[[
    @summary  Ensure we have custom tracks built for a stalker.
    @param    stalkerKey  string
    @returns  table?  stalker data or nil if model not found
]]
local function ensureStalkerTracks(stalkerKey: string)
	if stalkerData[stalkerKey] and stalkerData[stalkerKey].model.Parent then
		return stalkerData[stalkerKey]
	end

	local model = findStalkerModel(stalkerKey)
	if not model then
		return nil
	end

	local tracks = buildCustomTracks(model)
	if not next(tracks) then
		return nil
	end

	local data = {
		model = model,
		tracks = tracks,
	}
	stalkerData[stalkerKey] = data
	return data
end

--[[
    @summary  Handle an animation state change from the server.
    @param    stalkerKey  string  -- "Deer" or "RamMonster"
    @param    trackName   string  -- "Walk", "Run", "Idle", "Attack", "StunnedStart", etc.
                                   -- "StopAll" = stop all tracks
                                   -- "StopAttack" = stop only the Attack track
]]
local function onAnimationStateChanged(stalkerKey: string, trackName: string)
	local data = ensureStalkerTracks(stalkerKey)
	if not data then
		return
	end

	if trackName == "StopAll" then
		for _, track in pairs(data.tracks) do
			if track._isPlaying then
				track:Stop(0)
			end
		end
		return
	end

	if trackName == "StopAttack" then
		local attackTrack = data.tracks["Attack"]
		if attackTrack and attackTrack._isPlaying then
			attackTrack:Stop(0)
		end
		return
	end

	local track = data.tracks[trackName]
	if not track then
		return
	end

	-- Don't restart if already playing
	if track._isPlaying then return end

	-- Stop locomotion tracks when switching to a non-locomotion track
	local locomotionTracks = { Walk = true, Run = true, Idle = true }
	if not locomotionTracks[trackName] then
		for name, t in pairs(data.tracks) do
			if t._isPlaying and locomotionTracks[name] then
				t:Stop(0.15)
			end
		end
	else
		-- Stop other locomotion tracks
		for name, t in pairs(data.tracks) do
			if t._isPlaying and locomotionTracks[name] and name ~= trackName then
				t:Stop(0.15)
			end
		end
	end

	track:Play(0.15)
end

-- // INITIALIZATION // --

function DeerController:KnitStart()
	if not ServerRole.IsGameServer() then return end

	local deerService = Knit.GetService("DeerService")

	deerService.AnimationStateChanged:Connect(function(stalkerKey: string, trackName: string)
		onAnimationStateChanged(stalkerKey, trackName)
	end)

	-- Tick all custom tracks on Heartbeat (client-side Motor6D.Transform writes)
	heartbeatConnection = RunService.Heartbeat:Connect(function(dt)
		for _, data in pairs(stalkerData) do
			if data.model.Parent then
				for _, track in pairs(data.tracks) do
					if track.isCustom and track._isPlaying then
						tickCustomTrack(track, dt)
					end
				end
			else
				-- Model was destroyed, clean up
				stalkerData[data] = nil
			end
		end
	end)
end

return DeerController
