local Config = {
	MapRadius = 1000,
	-- Even distribution: 200 start, then 160-stud steps to reach 1000
	AccessRadiusByLevel = { 200, 360, 520, 680, 840, 1000 },
	SafeZoneRadiusByLevel = { 30, 45, 60, 80, 100, 130 },
	-- Caves placed inside the wall at their unlock level
	-- Dino (Lv2, wall 360): ring 280-340
	-- Kraken (Lv3, wall 520): ring 430-500
	-- Squid (Lv4, wall 680): ring 580-650
	-- Koala (Lv5, wall 840): ring 730-800
	CaveRings = {
		Dino = { Min = 280, Max = 340 },
		Kraken = { Min = 430, Max = 500 },
		Squid = { Min = 580, Max = 650 },
		Koala = { Min = 730, Max = 800 },
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
