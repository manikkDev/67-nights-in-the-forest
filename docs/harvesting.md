# Harvesting

Chopping trees with the axe is the primary wood source.

## Chopping

Equip the axe and click on a tree. `HarvestController` wires the tool, plays the swing animation, and shows hit feedback (camera shake); `HarvestService` validates hits server-side and spawns the wood drops.

## Giant trees

`GiantTreeService` handles oversized trees separately — they take more hits and drop larger wood yields.

## Tree scatter

`TreeScatterService` populates the forest at run start using seeded `WorldPlacement` positions; felled trees respawn over time so the wood supply doesn't run dry.

## Wood uses

- Campfire fuel (the constant demand)
- Tier-1 structures and the Crafting Bench II upgrade
