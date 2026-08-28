local Config = {
	MapRadius = 1000,
	-- Levels 1-2 small, level 3+ much bigger jumps to map edge
	AccessRadiusByLevel = { 200, 350, 600, 780, 900, 1000 },
	SafeZoneRadiusByLevel = { 30, 45, 60, 80, 100, 130 },
	-- Caves far from campfire, progressively harder to find by rescue order
	CaveRings = {
		Dino = { Min = 400, Max = 500 },
		Kraken = { Min = 550, Max = 650 },
		Squid = { Min = 700, Max = 800 },
		Koala = { Min = 850, Max = 950 },
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
