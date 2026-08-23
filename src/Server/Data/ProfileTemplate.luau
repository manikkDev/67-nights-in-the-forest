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

    Two ownership tiers live here.  `Records`, `Unlocks`, `Settings`,
    and `Internal` survive between sessions.  Every other table is
    run-scoped: RunStateService clears it when a run starts and again
    when a run ends, so a finished camp never carries into a new run.
]]

return {
	DataVersion = 2,

	Records = {
		HighestDay = 0,
		FastestDay67Seconds = 0,
		Wins = 0,
		ChildrenRescued = 0,
		TreesChopped = 0,
		WolvesKilled = 0,
		CultistsKilled = 0,
		Revives = 0,
		Deaths = 0,
		TotalPlaytime = 0,
	},

	Unlocks = {},

	Settings = {
		ReducedMotion = false,
		MusicVolume = 0.7,
		SfxVolume = 1,
	},

	Internal = {
		LastAppliedRunId = "",
	},

	Resources = {
		Wood = 0,
		Scrap = 0,
		Coal = 0,
		Berries = 0,
		Mushrooms = 0,
		RawMeat = 0,
		RabbitMeat = 0,
		CookedMeat = 0,
		OwlFeather = 0,
		CultistGem = 0,
		Bandage = 0,
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
		CultistsKilled = 0,
		StructuresBuilt = 0,
		ChildrenRescued = 0,
		Revives = 0,
		Downs = 0,
		TotalPlaytime = 0,
	},

	Campfire = {
		Level = 1,
		Progress = 0,
		Fuel = 0,
	},
}
