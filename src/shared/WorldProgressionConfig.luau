local Config = {
	MapRadius = 1600,
	AccessRadiusByLevel = { 250, 400, 560, 750, 1000, 1300 },
	SafeZoneRadiusByLevel = { 50, 70, 95, 125, 160, 205 },
	CaveRings = {
		Dino = { Min = 150, Max = 210 },
		Kraken = { Min = 270, Max = 350 },
		Squid = { Min = 430, Max = 520 },
		Koala = { Min = 600, Max = 700 },
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
		MaxRetries = 120,
		CaveFootprint = Vector3.new(40, 14, 38),
		CaveSpacing = 70,
		MaxSlope = 12,
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
