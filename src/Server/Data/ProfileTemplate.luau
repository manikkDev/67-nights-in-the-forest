--[[
    @file    ProfileTemplate.luau
    @author  manik
    @date    2025

    @summary
    Default data template applied to every new player profile.

    @description
    Returned as a plain table. ProfileService deep-copies this template
    into a fresh profile via the `template` field of `ProfileStore`.
    All fields are server-authoritative; the client may never write
    to them directly.
]]

return {
	Resources = {
		Wood = 0,
		Stone = 0,
		Berries = 0,
		Mushrooms = 0,
		RawMeat = 0,
		RabbitMeat = 0,
		CookedMeat = 0,
	},
	Survival = {
		Health = 100,
		MaxHealth = 100,
		Hunger = 100,
		MaxHunger = 100,
		DeathCount = 0,
		HighestNightSurvived = 0,
	},
	Base = {
		BedCount = 0,
		DayMultiplier = 1,
		UnlockedStructures = {},
	},
	Inventory = {
		HasBag = true,
		PickupOrder = {},
	},
	Rescue = {
		ChildrenRescued = {},
		CavesUnlocked = {},
	},
	Stats = {
		TreesChopped = 0,
		WolvesKilled = 0,
		TotalPlaytime = 0,
	},
	Campfire = {
		Level = 1,
		Progress = 0,
		Fuel = 0,
	},
}
