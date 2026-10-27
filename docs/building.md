# Building

Crafted structures are placed freely around the campfire to fortify the camp.

## Placement rules

- Grid snapping: `RunConfig.PlacementGrid` (2 studs)
- Rotation step: 15° per tap (Q/E on keyboard, bumpers on gamepad)
- Max placement range: 35 studs from the player
- Max slope: 25°
- Structures must fit inside the campfire build radius (110 studs)
- Per-run cap: 48 structures total

## Structure categories

Defined in `StructureConfig.luau`:

- **Beds** — each grants +1 score-multiplier day per night survived
- **Defenses** — walls and gates block raiders, traps damage them
- **Utility** — food production and storage improvements

## Validation

`BuildingService` re-checks every placement server-side: footprint overlap, slope, distance, reservation conflicts, and the run cap. The client ghost preview mirrors the same rules so green = the server will accept it.

## Health

Structures have `MaxHealth` and can be damaged by raiders during cultist attacks.
