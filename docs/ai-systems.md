# AI Systems

The game features three enemy types, each with its own service and behavior model.

## Deer

- Spawns: Via `DeerService` at night starting Day 2
- HP: 60
- Damage: 15 per attack
- Behavior: Wanders, flees when damaged, charges when close
- Flashlight interaction: Stunned (stops movement) when flashlight beam hits face
- Stun animations: `StunnedStart` → `StunnedLoop` → `StunnedEnd`

## Owl

- Spawns: Via `OwlService` during the night
- HP: 80
- Damage: 20 per attack
- Behavior: Circles campfire, swoops at players
- Flashlight interaction: Freezes temporarily when flashlight beam hits face
- Eye meter: HUD shows owl proximity via a meter that fills as it approaches

## Cultists

- Spawns: Via `CultistRaidService` during raids
- Raid cycle: Every 4 days (configurable via `RunConfig.RaidCycleInterval`)
- Behavior: Patrol toward campfire, attack players on sight
- Raid phases: Warning banner → Cultist spawn → Combat → Clear → Cooldown

## Shared Mechanics

- All NPCs register with `CombatTargetRegistry` for damage handling
- Pathfinding: Uses `PathfindingService` for navigation
- Targeting: Prefer nearest player, respect downed state
- Loot: Deer/Owl drop meat; Cultists drop nothing (raid-only threat)
