# Weapons

## Spear

The primary melee weapon. Not granted by default — it drops from the Dino cave chest (see `docs/loot.md`).

- `CombatService.buildSpearTool()` builds the Tool from the `ServerStorage.Assets` model
- `GetSpearTemplate()` exposes the cached template so `LootService` can clone it into chests

## Axe

Harvesting tool for chopping trees; doubles as a light weapon.

## Adding a new weapon

Follow the rules in `AGENTS.md` → "Weapon Tool Creation":

1. Inspect the source model in Studio — identify the real hand-grip part.
2. Use that part as the Tool `Handle`, not the blade/head.
3. Rename any other part named `Handle` (e.g. to `Shaft`) so Roblox doesn't grab it.
4. Weld remaining parts to the Handle with `WeldConstraint`.
5. Set `tool.Grip` as a CFrame, not the GripPos/GripForward/etc. fields.
6. Verify at runtime that the grip looks right before shipping.
