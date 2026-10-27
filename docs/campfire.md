# Campfire

The campfire is the heart of the run — feeding it fuel raises its level, which expands the playable area and unlocks rescues.

## Fueling

Throw wood into the fire (F near the flame). `CampfireService` tracks fuel and converts it to level progress automatically.

## Levels

Six levels total. Each level:

- Expands the world boundary (see `docs/progression.md`)
- Expands the campfire safe zone where enemies cannot enter
- Unlocks the next rescue cave at levels 2–5

## Safe zone

Inside the safe-zone radius, hostile NPCs will not path to or damage players. Radius grows from 30 studs at level 1 to 130 at level 6 (`WorldProgressionConfig.SafeZoneRadiusByLevel`).

## Cooking

Hold raw meat near the fire to cook it — Cooked Meat heals 15 HP vs 3 HP raw (`CookingService`).

## Signals

`CampfireService` exposes `LevelChanged`, `FuelAdded`, and `CampfireExtinguished`/`CampfireRelit` remotes that drive the HUD gauge and client effects.
