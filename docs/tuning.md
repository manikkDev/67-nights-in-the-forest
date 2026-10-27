# Tuning

Most gameplay numbers live in `src/shared/RunConfig.luau` and the `*Config.luau` modules — change them there, not in service code.

## Where things live

| What                     | File |
|--------------------------|------|
| Day/night length, survival, downed/revive, placement limits, multiplier bounds, raid cadence, ending timing | `RunConfig.luau` |
| World radius per campfire level, cave rings, boundary wall, placement retry/footprint | `WorldProgressionConfig.luau` |
| NPC stats/aggro/loot      | `NpcConfig.luau` |
| Rescue unlock levels, guards, keys | `RescueConfig.luau` |
| Structure footprints/health/multiplier points | `StructureConfig.luau` |
| Recipe costs/tiers/caps   | `RecipeConfig.luau` |
| Junk scrap yields         | `JunkItemConfig.luau` |
| Party/teleport limits, place IDs, match timing | `Constants.luau` |
| Asset IDs                 | `AssetCatalog.luau`, `IntroAssets.luau` |

## Difficulty scaling

Enemy health and pack size scale with initial party size (`Config.ScaleEnemyHealth`/`ScaleEnemyCount`); enemy damage is deliberately flat.

## Studio test flags

`RunConfig.StudioTest` overrides apply only under `RunService:IsStudio()` — e.g. `FastClock`, `ForceNight`, `GrantResources`, `SkipLobby`.
