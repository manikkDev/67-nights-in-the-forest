# Grinder (Shredder)

Junk items found inside facilities are fed into the Shredder next to the Crafting Bench to produce Scrap — the mid-tier crafting resource.

## Junk sources

Junk spawns inside facilities: Playground, Restroom, Clinic. Each item type has a fixed Scrap yield (`JunkItemConfig`):

| Yield | Items |
|-------|-------|
| 1 Scrap | Bolt, Sheet Metal |
| 2 Scrap | Old Radio, Broken Fan |
| 3 Scrap | Broken Microwave, Tyre, Metal Chair |

The bolt-count badge on the item icon mirrors the yield (1–3 🔩).

## Flow

1. Pick up a junk item (it occupies an inventory slot).
2. Carry it to the Shredder and use the proximity prompt.
3. The item grinds with a metal-groan sound; Scrap lands in your inventory.

## Notes

- Grinding is handled by `GrinderService` server-side; `GrinderController` plays the client animation and sound.
- Scrap gates Tier-2 bench upgrades and defenses — grind early and often.
