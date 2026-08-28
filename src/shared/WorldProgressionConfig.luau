local Config = {
	MapRadius = 1600,
	AccessRadiusByLevel = { 350, 550, 800, 1080, 1350, 1600 },
	SafeZoneRadiusByLevel = { 55, 75, 100, 130, 165, 205 },
	CaveRings = {
		Dino = { Min = 390, Max = 500 },
		Kraken = { Min = 620, Max = 750 },
		Squid = { Min = 870, Max = 1020 },
		Koala = { Min = 1140, Max = 1280 },
	},
	Boundary = {
		Height = 150,
		ServerSegments = 48,
		DesktopSegments = 48,
		MobileSegments = 28,
		PushbackMargin = 10,
		CheckInterval = 0.15,
	},
	Placement = {
		MaxRetries = 80,
		CaveFootprint = Vector3.new(72, 20, 70),
		CaveSpacing = 90,
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
