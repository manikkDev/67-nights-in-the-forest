# Cultists

Cultists attack the camp in scheduled raids — the game's escalation mechanic.

## Raid cadence

A raid fires every `RunConfig.RaidCycleInterval` days (4 by default). `CultistRaidService` runs the phase machine: warning banner → spawn → assault → clear → cooldown.

## Stats

| Cultist  | HP  | Damage | Notes |
|----------|-----|--------|-------|
| Cultist  | 100 | 15     | R6 rig, baked attack anim |
| Cultist2 | 110 | 15     | Tougher variant |

Both drop a guaranteed `CultistGem` plus a chance of wood.

## Behavior

- Predator tier: aggro at 50 studs, chase up to 70
- Path toward the campfire and engage players and structures
- Raid difficulty scales with party size via the difficulty multiplier

## Defense tips

- Walls and gates from the building catalog absorb cultist hits.
- The raid banner gives a few seconds to fall back inside defenses.
- Cultist gems are the raid reward — don't skip them.
