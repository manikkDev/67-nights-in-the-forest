--[[
    @file    RecipeConfig.luau
    @author  manik
    @date    2025

    @summary
    Immutable recipe catalog for every Phase 4 crafting output.

    @description
    Costs, tier requirements, caps, and output kinds are server-read data.
    The client may use display fields, but CraftingService independently
    validates every transaction against this catalog.
]]

export type Recipe = {
	Id: string,
	DisplayName: string,
	Tier: number,
	Cost: { [string]: number },
	RunCap: number?,
	OutputKind: "Unlock" | "Placement" | "Item" | "BenchUpgrade",
	OutputId: string,
	Description: string,
}

local Recipes: { [string]: Recipe } = {
	Map = {
		Id = "Map",
		DisplayName = "Map",
		Tier = 1,
		Cost = { Wood = 3 },
		RunCap = 1,
		OutputKind = "Unlock",
		OutputId = "Map",
		Description = "Shows the camp, landmarks, caves, and teammates.",
	},
	OldBed = {
		Id = "OldBed",
		DisplayName = "Old Bed",
		Tier = 1,
		Cost = { Wood = 20 },
		RunCap = 1,
		OutputKind = "Placement",
		OutputId = "OldBed",
		Description = "Adds one day to every survived night.",
	},
	FarmPlot = {
		Id = "FarmPlot",
		DisplayName = "Farm Plot",
		Tier = 1,
		Cost = { Wood = 10 },
		RunCap = 8,
		OutputKind = "Placement",
		OutputId = "FarmPlot",
		Description = "Grows food every two real dawn cycles.",
	},
	LogWall = {
		Id = "LogWall",
		DisplayName = "Log Wall",
		Tier = 1,
		Cost = { Wood = 12 },
		RunCap = 24,
		OutputKind = "Placement",
		OutputId = "LogWall",
		Description = "Blocks and absorbs attacks from raiders.",
	},
	BenchTier2 = {
		Id = "BenchTier2",
		DisplayName = "Crafting Bench II",
		Tier = 1,
		Cost = { Wood = 5, Scrap = 1 },
		RunCap = 1,
		OutputKind = "BenchUpgrade",
		OutputId = "2",
		Description = "Unlocks utility, healing, and stronger defenses.",
	},
	Compass = {
		Id = "Compass",
		DisplayName = "Compass",
		Tier = 2,
		Cost = { Scrap = 3 },
		RunCap = 1,
		OutputKind = "Unlock",
		OutputId = "Compass",
		Description = "Shows camp and selected rescue directions.",
	},
	RegularBed = {
		Id = "RegularBed",
		DisplayName = "Regular Bed",
		Tier = 2,
		Cost = { Scrap = 5 },
		RunCap = 1,
		OutputKind = "Placement",
		OutputId = "RegularBed",
		Description = "Adds one day to every survived night.",
	},
	LogGate = {
		Id = "LogGate",
		DisplayName = "Log Gate",
		Tier = 2,
		Cost = { Wood = 10, Scrap = 2 },
		RunCap = 4,
		OutputKind = "Placement",
		OutputId = "LogGate",
		Description = "A player-operated entrance for the camp wall.",
	},
	BearTrap = {
		Id = "BearTrap",
		DisplayName = "Bear Trap",
		Tier = 2,
		Cost = { Scrap = 3 },
		RunCap = 10,
		OutputKind = "Placement",
		OutputId = "BearTrap",
		Description = "Damages and briefly stops one hostile creature.",
	},
	StorageCrate = {
		Id = "StorageCrate",
		DisplayName = "Storage Crate",
		Tier = 2,
		Cost = { Wood = 5, Scrap = 2 },
		RunCap = 4,
		OutputKind = "Placement",
		OutputId = "StorageCrate",
		Description = "Stores shared run resources at the camp.",
	},
	Bandage = {
		Id = "Bandage",
		DisplayName = "Bandage",
		Tier = 2,
		Cost = { Scrap = 2 },
		OutputKind = "Item",
		OutputId = "Bandage",
		Description = "Revives one downed teammate.",
	},
	BenchTier3 = {
		Id = "BenchTier3",
		DisplayName = "Crafting Bench III",
		Tier = 2,
		Cost = { Wood = 15, Scrap = 15 },
		RunCap = 1,
		OutputKind = "BenchUpgrade",
		OutputId = "3",
		Description = "Unlocks the final two beds.",
	},
	GoodBed = {
		Id = "GoodBed",
		DisplayName = "Good Bed",
		Tier = 3,
		Cost = { Wood = 20, Scrap = 10 },
		RunCap = 1,
		OutputKind = "Placement",
		OutputId = "GoodBed",
		Description = "Adds one day to every survived night.",
	},
	GiantBed = {
		Id = "GiantBed",
		DisplayName = "Giant Bed",
		Tier = 3,
		Cost = { Wood = 30, Scrap = 20, CultistGem = 1 },
		RunCap = 1,
		OutputKind = "Placement",
		OutputId = "GiantBed",
		Description = "The final bed and one day of multiplier progress.",
	},
}

for _, recipe in pairs(Recipes) do
	table.freeze(recipe.Cost)
	table.freeze(recipe)
end

return table.freeze(Recipes)
