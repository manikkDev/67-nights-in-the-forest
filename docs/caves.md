# Caves

Rescue caves are fixed content placed at run start by `RescueService.buildCaves()`.

## Structure

Each cave contains:

- A colored cave shell (`CaveColor` per rescue: red, blue, yellow, gray)
- A guard pack at the entrance (species and count per `RescueConfig`)
- A cage holding the missing child, unlocked by the guard-dropped key
- A chest inside with per-player loot (see `docs/loot.md`)

## Spawn rings

Caves land in fixed annular rings (`WorldProgressionConfig.CaveRings`) so each one is inside the boundary at its campfire unlock level:

| Cave   | Ring (studs) | Unlock |
|--------|--------------|--------|
| Dino   | 380–480      | Lv2    |
| Kraken | 620–720      | Lv3    |
| Squid  | 880–980      | Lv4    |
| Koala  | 1150–1250    | Lv5    |

`GetCaveCenter(caveId)` exposes the cave centre for chest placement.
