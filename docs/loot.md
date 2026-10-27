# Loot & Chests

Two chest types exist, handled by `LootService`:

## Landmark chests

- Spawn near map landmarks (cabin, tower, etc.)
- One open per run, shared globally — first player gets it
- Grant resources only (wood, stone, scrap)

## Cave chests

- Spawn inside rescue caves
- Per-player: every party member can open their own copy (`openedCaveChests[player][chestId]`)
- Can grant tools — the Spear comes from the Dino cave chest

## Opening

A proximity prompt on the chest triggers the open: bounce/scale tween, gold particle burst, point-light flash, and the wooden-chest sound. `ChestOpened` fires only to the opener.

## Loot UI

`LootController` shows a results panel with icons, names, quantities, and descriptions. It auto-dismisses after 8 seconds or on Close.

## Placement timing

Cave chests spawn deferred (`task.defer` + short wait) because `RescueService.buildCaves()` also defers on `RunStarted` — caves must exist before chest placement runs.
