# Facilities

Dilapidated buildings scattered through the forest contain the junk items that feed the Grinder.

## Types

Built by `FacilityService` via `WorldPlacement.FindPosition`:

- **Playground**
- **Restroom**
- **Clinic**

## Junk spawns

Each facility interior gets a set of junk items at seeded positions (`randomFacilityPosition`). Junk yield tiers are documented in `docs/grinder.md`.

## Placement

Facilities are placed during run setup inside the current access radius, away from reserved areas and with a clear footprint. Positions are seeded so regen stays deterministic when debugging.

## Registry

`FacilityService` keeps a facility registry and a junk registry for cleanup between runs, plus the campfire position used as the placement anchor.
