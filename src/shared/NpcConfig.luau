--[[
    @file    NpcConfig.luau
    @author  manik
    @date    2025

    @summary
    Per-species tuning table for every Phase 3 NPC.

    @description
    Central data module read by AnimalAIService, DeerService, and
    CombatService so species stats, animation strategy, and loot
    tables live in one place instead of scattered across services.
    RigStyle tells the animation layer which strategy a model's
    skeleton supports: "R15" and "R6" models reuse Roblox's public
    default Animate-script animation ids, "Procedural" models are
    driven frame-by-frame via Motor6D offsets.
]]

export type LootEntry = { Resource: string, Min: number, Max: number, Chance: number }

export type SpeciesConfig = {
	ModelName: string,
	Tier: "Passive" | "Predator" | "Solitary",
	RigStyle: "R15" | "R6" | "Procedural",
	WalkSpeed: number,
	RunSpeed: number,
	MaxHealth: number,
	AttackDamage: number,
	AttackRange: number,
	AttackCooldown: number,
	AggroRange: number,
	LoseAggroRange: number,
	FleeSpeedMultiplier: number?,
	PackSize: { Min: number, Max: number }?,
	TerritoryRadius: number?,
	ActiveDuring: "Night" | "Day" | "Always",
	Loot: { LootEntry },
	BakedAttackAnimName: string?,
	StatsKey: string?,
}

return {
	Bunny = {
		ModelName = "BunnyModel",
		Tier = "Passive",
		RigStyle = "Procedural",
		WalkSpeed = 8,
		RunSpeed = 18,
		MaxHealth = 20,
		AttackDamage = 0,
		AttackRange = 0,
		AttackCooldown = 0,
		AggroRange = 16,
		LoseAggroRange = 30,
		FleeSpeedMultiplier = 2.2,
		ActiveDuring = "Day",
		Loot = {
			{ Resource = "Berries", Min = 1, Max = 2, Chance = 0.6 },
			{ Resource = "RawMeat", Min = 1, Max = 1, Chance = 0.9 },
		},
	},
	Owl = {
		ModelName = "Owl",
		Tier = "Passive",
		RigStyle = "R15",
		WalkSpeed = 6,
		RunSpeed = 6,
		MaxHealth = 15,
		AttackDamage = 0,
		AttackRange = 0,
		AttackCooldown = 0,
		AggroRange = 0,
		LoseAggroRange = 0,
		ActiveDuring = "Day",
		Loot = {},
	},
	WolfModel = {
		ModelName = "WolfModel",
		Tier = "Predator",
		RigStyle = "Procedural",
		WalkSpeed = 10,
		RunSpeed = 24,
		MaxHealth = 60,
		AttackDamage = 12,
		AttackRange = 6,
		AttackCooldown = 1.4,
		AggroRange = 40,
		LoseAggroRange = 60,
		PackSize = { Min = 3, Max = 5 },
		ActiveDuring = "Night",
		StatsKey = "WolvesKilled",
		Loot = {
			{ Resource = "RawMeat", Min = 1, Max = 2, Chance = 1 },
		},
	},
	AlphaWolfModel = {
		ModelName = "AlphaWolfModel",
		Tier = "Predator",
		RigStyle = "Procedural",
		WalkSpeed = 11,
		RunSpeed = 26,
		MaxHealth = 130,
		AttackDamage = 20,
		AttackRange = 7,
		AttackCooldown = 1.2,
		AggroRange = 46,
		LoseAggroRange = 65,
		PackSize = { Min = 1, Max = 2 },
		ActiveDuring = "Night",
		StatsKey = "WolvesKilled",
		Loot = {
			{ Resource = "RawMeat", Min = 2, Max = 3, Chance = 1 },
		},
	},
	Bear = {
		ModelName = "Bear",
		Tier = "Solitary",
		RigStyle = "Procedural",
		WalkSpeed = 9,
		RunSpeed = 20,
		MaxHealth = 220,
		AttackDamage = 30,
		AttackRange = 8,
		AttackCooldown = 1.8,
		AggroRange = 26,
		LoseAggroRange = 42,
		TerritoryRadius = 45,
		ActiveDuring = "Always",
		BakedAttackAnimName = "Attack",
		Loot = {
			{ Resource = "RawMeat", Min = 3, Max = 4, Chance = 1 },
		},
	},
	Cultist = {
		ModelName = "Cultist",
		Tier = "Predator",
		RigStyle = "R6",
		WalkSpeed = 12,
		RunSpeed = 16,
		MaxHealth = 100,
		AttackDamage = 15,
		AttackRange = 7,
		AttackCooldown = 1.5,
		AggroRange = 50,
		LoseAggroRange = 70,
		ActiveDuring = "Always",
		BakedAttackAnimName = "Attack",
		Loot = {
			{ Resource = "Wood", Min = 1, Max = 2, Chance = 0.5 },
		},
	},
	Cultist2 = {
		ModelName = "Cultist2",
		Tier = "Predator",
		RigStyle = "R6",
		WalkSpeed = 12,
		RunSpeed = 16,
		MaxHealth = 110,
		AttackDamage = 15,
		AttackRange = 7,
		AttackCooldown = 1.5,
		AggroRange = 50,
		LoseAggroRange = 70,
		ActiveDuring = "Always",
		BakedAttackAnimName = "Attack",
		Loot = {
			{ Resource = "Wood", Min = 1, Max = 2, Chance = 0.5 },
		},
	},
	RamMonster = {
		ModelName = "Ram Monster",
		Tier = "Solitary",
		RigStyle = "R15",
		WalkSpeed = 10,
		RunSpeed = 22,
		MaxHealth = 0,
		AttackDamage = 35,
		AttackRange = 7,
		AttackCooldown = 2,
		AggroRange = 40,
		LoseAggroRange = 999999,
		ActiveDuring = "Night",
		Loot = {},
	},
}
