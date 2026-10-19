# Deer

Deer spawn at night starting Day 2 and serve as a primary source of meat.

## Stats

- HP: 60
- Damage: 15 per attack
- Movement: Runs when threatened, charges when close

## Behavior

- Wanders the forest during the night
- Flees when damaged by player attacks
- Charges at nearby players if cornered

## Flashlight Interaction

When a flashlight beam hits the deer's face:
- Movement stops completely (stunned)
- Animation sequence: `StunnedStart` → `StunnedLoop` → `StunnedEnd`
- Stun lasts until the animation sequence completes

## Loot

- Drops raw meat on death
- Cooked meat heals 15 HP (vs 3 HP raw)

## Strategy

- Use the flashlight to stun deer for easier kills
- Avoid melee combat during their charge phase
- Cook meat at the campfire for maximum healing value
