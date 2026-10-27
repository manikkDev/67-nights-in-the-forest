# World Boundary

The playable area is bounded by a circular wall centred on the campfire. It expands outward each campfire level.

## Radius

`WorldProgressionConfig.AccessRadiusByLevel`: 250 → 520 → 790 → 1060 → 1330 → 1600 studs across levels 1–6.

## Wall construction

The wall is segmented; segment count varies by platform (64 server-side, 48 desktop, 28 mobile). Height 500 studs. `Boundary.PushbackMargin` (8 studs) keeps players from resting against the wall face.

## Warning effect

Approaching the boundary triggers the `WorldBoundaryController` proximity HUD plus a ColorCorrection vignette — the old particle fog wall was removed. Crossing too far pushes the player back inside.

## Placement reservation

`WorldPlacement.ReserveRing()` reserves the band where the wall will expand to, so caves and structures never spawn in its path.

## Containment check

The boundary service re-validates player positions every `CheckInterval` (0.15s).
