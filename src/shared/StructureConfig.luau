--[[
    @file    StructureConfig.luau
    @author  manik
    @date    2025

    @summary
    Immutable placement and gameplay data for every buildable structure.
]]

export type StructureDefinition = {
	Id: string,
	DisplayName: string,
	TemplateName: string,
	TemplateCategory: "Items" | "MapItems" | "Generated",
	Footprint: Vector3,
	MaxHealth: number,
	MaxSlope: number,
	MultiplierPoints: number?,
}

local Structures: { [string]: StructureDefinition } = {
	OldBed = {
		Id = "OldBed",
		DisplayName = "Old Bed",
		TemplateName = "Bed",
		TemplateCategory = "Items",
		Footprint = Vector3.new(8, 5, 5),
		MaxHealth = 500,
		MaxSlope = 8,
		MultiplierPoints = 1,
	},
	RegularBed = {
		Id = "RegularBed",
		DisplayName = "Regular Bed",
		TemplateName = "Bed",
		TemplateCategory = "Items",
		Footprint = Vector3.new(8, 5, 5),
		MaxHealth = 600,
		MaxSlope = 8,
		MultiplierPoints = 1,
	},
	GoodBed = {
		Id = "GoodBed",
		DisplayName = "Good Bed",
		TemplateName = "Bed",
		TemplateCategory = "Items",
		Footprint = Vector3.new(9, 6, 6),
		MaxHealth = 700,
		MaxSlope = 8,
		MultiplierPoints = 1,
	},
	GiantBed = {
		Id = "GiantBed",
		DisplayName = "Giant Bed",
		TemplateName = "Bed",
		TemplateCategory = "Items",
		Footprint = Vector3.new(12, 7, 8),
		MaxHealth = 900,
		MaxSlope = 8,
		MultiplierPoints = 1,
	},
	LogWall = {
		Id = "LogWall",
		DisplayName = "Log Wall",
		TemplateName = "Log Wall",
		TemplateCategory = "MapItems",
		Footprint = Vector3.new(14, 10, 3),
		MaxHealth = 250,
		MaxSlope = 15,
	},
	LogGate = {
		Id = "LogGate",
		DisplayName = "Log Gate",
		TemplateName = "Log Wall",
		TemplateCategory = "MapItems",
		Footprint = Vector3.new(14, 10, 4),
		MaxHealth = 220,
		MaxSlope = 15,
	},
	FarmPlot = {
		Id = "FarmPlot",
		DisplayName = "Farm Plot",
		TemplateName = "FarmPlot",
		TemplateCategory = "Generated",
		Footprint = Vector3.new(10, 2, 8),
		MaxHealth = 150,
		MaxSlope = 8,
	},
	BearTrap = {
		Id = "BearTrap",
		DisplayName = "Bear Trap",
		TemplateName = "BearTrap",
		TemplateCategory = "Generated",
		Footprint = Vector3.new(5, 2, 5),
		MaxHealth = 60,
		MaxSlope = 12,
	},
	StorageCrate = {
		Id = "StorageCrate",
		DisplayName = "Storage Crate",
		TemplateName = "basic-chest",
		TemplateCategory = "MapItems",
		Footprint = Vector3.new(6, 5, 5),
		MaxHealth = 200,
		MaxSlope = 10,
	},
}

for _, structure in pairs(Structures) do
	table.freeze(structure)
end

return table.freeze(Structures)
