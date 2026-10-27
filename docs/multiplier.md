# Score Multiplier

The run score is a base value times a multiplier built up during the run.

## Sources

`RunStateService` tracks a `multiplierSources` ledger — every contributing system registers a named entry:

- **Beds** — each placed bed adds +1 multiplier day per night survived (`StructureConfig.MultiplierPoints`)
- Other systems can add named sources at runtime

## Bounds

`RunConfig`: `BaseMultiplier = 1`, `MaxMultiplier = 9`.

## Party scaling

Difficulty multipliers are derived from initial party size and clamped to `Difficulty.MaxPartySize` (5):

- `HealthPerAdditionalPlayer` = 0.12 — enemy HP scaling
- `CountPerAdditionalPlayer` = 0.15 — enemy pack-size scaling

Enemy damage is intentionally not scaled.
