--[[
    @file    JunkItemConfig.luau
    @author  manik
    @date    2025

    @summary
    Immutable catalog of junk items that can be ground into Scrap.

    @description
    Each junk item is found inside facilities (Playground, Restroom,
    Clinic) scattered across the forest. Players carry them to the
    Grinder next to the Crafting Bench and convert them into Scrap.
    BoltCount is the visual indicator (🔩) shown in the UI — more
    bolts mean a higher Scrap yield, mirroring the reference game.
]]

export type JunkItem = {
	Id: string,
	DisplayName: string,
	ScrapYield: number,
	BoltCount: number,
	Color: Color3,
	Material: Enum.Material,
	Description: string,
}

local JunkItems: { [string]: JunkItem } = {
	Bolt = {
		Id = "Bolt",
		DisplayName = "Bolt",
		ScrapYield = 1,
		BoltCount = 1,
		Color = Color3.fromRGB(140, 140, 145),
		Material = Enum.Material.Metal,
		Description = "A single metal bolt. Grinds into 1 Scrap.",
	},
	OldRadio = {
		Id = "OldRadio",
		DisplayName = "Old Radio",
		ScrapYield = 2,
		BoltCount = 1,
		Color = Color3.fromRGB(80, 60, 45),
		Material = Enum.Material.WoodPlanks,
		Description = "A vintage radio. Grinds into 2 Scrap.",
	},
	SheetMetal = {
		Id = "SheetMetal",
		DisplayName = "Sheet Metal",
		ScrapYield = 2,
		BoltCount = 1,
		Color = Color3.fromRGB(170, 170, 175),
		Material = Enum.Material.Metal,
		Description = "A flat sheet of rusted metal. Grinds into 2 Scrap.",
	},
	Tyre = {
		Id = "Tyre",
		DisplayName = "Tyre",
		ScrapYield = 2,
		BoltCount = 1,
		Color = Color3.fromRGB(30, 30, 30),
		Material = Enum.Material.Rubber,
		Description = "A worn rubber tyre. Grinds into 2 Scrap.",
	},
	BrokenFan = {
		Id = "BrokenFan",
		DisplayName = "Broken Fan",
		ScrapYield = 3,
		BoltCount = 2,
		Color = Color3.fromRGB(100, 100, 105),
		Material = Enum.Material.Metal,
		Description = "A fan with snapped blades. Grinds into 3 Scrap.",
	},
	BrokenMicrowave = {
		Id = "BrokenMicrowave",
		DisplayName = "Broken Microwave",
		ScrapYield = 4,
		BoltCount = 2,
		Color = Color3.fromRGB(220, 220, 215),
		Material = Enum.Material.SmoothPlastic,
		Description = "A dented microwave oven. Grinds into 4 Scrap.",
	},
}

for _, item in pairs(JunkItems) do
	table.freeze(item)
end

return table.freeze(JunkItems)
