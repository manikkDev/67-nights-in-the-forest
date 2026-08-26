--[[
    @file    JunkItemConfig.luau
    @author  manik
    @date    2025

    @summary
    Immutable catalog of junk items that can be ground into Scrap.

    @description
    Each junk item is found inside facilities (Playground, Restroom,
    Clinic) scattered across the forest. Players carry them to the
    Shredder next to the Crafting Bench and convert them into Scrap.
    BoltCount is the visual indicator (🔩) shown in the UI — more
    bolts mean a higher Scrap yield, mirroring the reference game.

    Scrap values sourced from the 99 Nights in the Forest wiki:
      🔩       = 1 Scrap   (Bolt, Sheet Metal)
      🔩🔩     = 2 Scrap   (Old Radio, Broken Fan)
      🔩🔩🔩   = 3 Scrap   (Broken Microwave, Tyre)
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
	SheetMetal = {
		Id = "SheetMetal",
		DisplayName = "Sheet Metal",
		ScrapYield = 1,
		BoltCount = 1,
		Color = Color3.fromRGB(170, 170, 175),
		Material = Enum.Material.Metal,
		Description = "A flat sheet of rusted metal. Grinds into 1 Scrap.",
	},
	OldRadio = {
		Id = "OldRadio",
		DisplayName = "Old Radio",
		ScrapYield = 2,
		BoltCount = 2,
		Color = Color3.fromRGB(80, 60, 45),
		Material = Enum.Material.WoodPlanks,
		Description = "A vintage radio. Grinds into 2 Scrap.",
	},
	BrokenFan = {
		Id = "BrokenFan",
		DisplayName = "Broken Fan",
		ScrapYield = 2,
		BoltCount = 2,
		Color = Color3.fromRGB(100, 100, 105),
		Material = Enum.Material.Metal,
		Description = "A fan with snapped blades. Grinds into 2 Scrap.",
	},
	BrokenMicrowave = {
		Id = "BrokenMicrowave",
		DisplayName = "Broken Microwave",
		ScrapYield = 3,
		BoltCount = 3,
		Color = Color3.fromRGB(220, 220, 215),
		Material = Enum.Material.SmoothPlastic,
		Description = "A dented microwave oven. Grinds into 3 Scrap.",
	},
	Tyre = {
		Id = "Tyre",
		DisplayName = "Tyre",
		ScrapYield = 3,
		BoltCount = 3,
		Color = Color3.fromRGB(30, 30, 30),
		Material = Enum.Material.Rubber,
		Description = "A worn rubber tyre. Grinds into 3 Scrap.",
	},
	MetalChair = {
		Id = "MetalChair",
		DisplayName = "Metal Chair",
		ScrapYield = 3,
		BoltCount = 3,
		Color = Color3.fromRGB(90, 95, 100),
		Material = Enum.Material.Metal,
		Description = "A rusted metal chair. Grinds into 3 Scrap.",
	},
}

for _, item in pairs(JunkItems) do
	table.freeze(item)
end

return table.freeze(JunkItems)
