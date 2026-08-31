local Config = {
	-- Map is 3200x3200 studs, center at (-75,-7).
	-- Distance from center to edge midpoint = 1600.
	MapRadius = 1600,
	-- Even distribution: 250 start, then ~270-stud steps to reach 1600
	AccessRadiusByLevel = { 250, 520, 790, 1060, 1330, 1600 },
	SafeZoneRadiusByLevel = { 30, 45, 60, 80, 100, 130 },
	-- Caves placed inside the wall at their unlock level
	-- Dino (Lv2, wall 520): ring 380-480
	-- Kraken (Lv3, wall 790): ring 620-720
	-- Squid (Lv4, wall 1060): ring 880-980
	-- Koala (Lv5, wall 1330): ring 1150-1250
	CaveRings = {
		Dino = { Min = 380, Max = 480 },
		Kraken = { Min = 620, Max = 720 },
		Squid = { Min = 880, Max = 980 },
		Koala = { Min = 1150, Max = 1250 },
	},
	Boundary = {
		Height = 220,
		ServerSegments = 64,
		DesktopSegments = 48,
		MobileSegments = 28,
		PushbackMargin = 8,
		CheckInterval = 0.15,
	},
	Placement = {
		MaxRetries = 250,
		CaveFootprint = Vector3.new(42, 14, 40),
		CaveSpacing = 90,
		MaxSlope = 10,
	},
}

function Config.GetAccessRadius(level: number): number
	local index = math.clamp(math.floor(level), 1, #Config.AccessRadiusByLevel)
	return Config.AccessRadiusByLevel[index]
end

function Config.GetSafeZoneRadius(level: number): number
	local index = math.clamp(math.floor(level), 1, #Config.SafeZoneRadiusByLevel)
	return Config.SafeZoneRadiusByLevel[index]
end

function Config.GetUnlockLevelForDistance(distance: number): number
	for level, radius in ipairs(Config.AccessRadiusByLevel) do
		if distance <= radius then
			return level
		end
	end
	return #Config.AccessRadiusByLevel
end

return table.freeze(Config)
