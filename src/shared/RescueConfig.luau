--[[
    @file    RescueConfig.luau
    @author  manik
    @date    2025

    @summary
    Immutable cave, guard, key, child, and rescue-tent progression data.
]]

export type RescueDefinition = {
	Id: string,
	DisplayName: string,
	RigTemplate: string,
	Variant: string?,
	CaveColor: Color3,
	RequiredCampfireLevel: number,
	GuardSpecies: string,
	GuardCount: number,
	KeyName: string,
}

local Rescues: { [string]: RescueDefinition } = {
	Dino = {
		Id = "Dino",
		DisplayName = "Dino Kid",
		RigTemplate = "Dino Kid",
		CaveColor = Color3.fromRGB(190, 55, 50),
		RequiredCampfireLevel = 2,
		GuardSpecies = "WolfModel",
		GuardCount = 5,
		KeyName = "Red Key",
	},
	Kraken = {
		Id = "Kraken",
		DisplayName = "Kraken Kid",
		RigTemplate = "Kraken Kid",
		CaveColor = Color3.fromRGB(55, 125, 210),
		RequiredCampfireLevel = 3,
		GuardSpecies = "AlphaWolfModel",
		GuardCount = 4,
		KeyName = "Blue Key",
	},
	Squid = {
		Id = "Squid",
		DisplayName = "Squid Kid",
		RigTemplate = "Dino Kid",
		Variant = "Squid",
		CaveColor = Color3.fromRGB(225, 190, 55),
		RequiredCampfireLevel = 4,
		GuardSpecies = "Bear",
		GuardCount = 2,
		KeyName = "Yellow Key",
	},
	Koala = {
		Id = "Koala",
		DisplayName = "Koala Kid",
		RigTemplate = "Kraken Kid",
		Variant = "Koala",
		CaveColor = Color3.fromRGB(120, 105, 135),
		RequiredCampfireLevel = 5,
		GuardSpecies = "Bear",
		GuardCount = 6,
		KeyName = "Gray Key",
	},
}

for _, rescue in pairs(Rescues) do
	table.freeze(rescue)
end

return table.freeze(Rescues)
