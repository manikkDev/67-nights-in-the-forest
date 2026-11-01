# Data Persistence

Player data is stored with ProfileService through `PlayerDataService`.

## Profile shape

`ProfileTemplate.luau` defines the new-profile shape (`DataVersion = 2`):

- `Records` — lifetime bests (HighestDay, Wins, ChildrenRescued, kill counts, playtime)
- `Unlocks` — permanent unlocks
- `Settings` — ReducedMotion, MusicVolume, SfxVolume
- `Internal` — bookkeeping like `LastAppliedRunId`
- `Resources` — Wood, Scrap, Coal, food, and junk item counts
- `Survival` — Health/Hunger meters plus DeathCount and HighestNightSurvived
- `Base` — BedCount, DayMultiplier, UnlockedStructures
- `Inventory` — HasBag flag and PickupOrder
- `Rescue` — ChildrenRescued and CavesUnlocked per run
- `Stats` — per-run counters (TreesChopped, StructuresBuilt, Downs, …)
- `Campfire` — Level, Progress, Fuel

## What resets per run

`RunStateService.RUN_SCOPED_PROFILE_KEYS` = `{ "Base", "Rescue", "Stats", "Campfire" }` — these tables are replaced with fresh templates when a run starts and ends.

`Survival` is NOT fully wiped: only `Health`, `MaxHealth`, `Hunger`, and `MaxHunger` are reset to the `RunConfig` starting values — `DeathCount` and `HighestNightSurvived` survive.

`Resources` and `Inventory` are deliberately excluded — bag contents persist across runs and rejoins, matching the reference game. `Records`, `Unlocks`, `Settings`, and `Internal` are always persistent.

## Signals

- `ProfileLoaded` fires server-side when a player's profile is ready; services should wait for it before touching data
- Load failures are logged and the player is handled safely
