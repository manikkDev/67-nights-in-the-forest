# Data Persistence

Player data is stored with ProfileService through `PlayerDataService`.

## Profile shape

`ProfileTemplate.luau` defines the default tables: `Base`, `Rescue`, `Stats`, `Campfire` (run-scoped) plus `Resources` and `Inventory` (persistent).

## Run scoping

When a run ends, `RunStateService` resets only the run-scoped keys — `Base`, `Rescue`, `Stats`, `Campfire`. Resources and inventory deliberately persist across runs and rejoins, matching the reference game.

## Signals

- `ProfileLoaded` fires server-side when a player's profile is ready; services should wait for it before touching data
- Load failures are logged and the player is handled safely

## Stats

Kill counts and survival stats accumulate under `Stats` (e.g. `WolvesKilled` via `NpcConfig.StatsKey`) and feed the ending results screen.
