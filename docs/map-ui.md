# Map

Two ways to read the world: the physical map board near the campfire and the full-screen map UI.

## Map board

A wooden board model placed by `MapService` near the campfire (offset −28 studs from centre, opposite the rescue board). Walking up to it fires `MapOpened` and opens the map UI.

## Map UI (M key)

`MapController` renders:

- Camp, landmarks, caves, and rescue markers
- Teammate positions as live player markers
- Rescue waypoint tracking (Track button per child)
- Radius/compass rings showing the current boundary
- Sidebar listing landmarks and cave lock state

## Portrait viewports

Both the physical board and the UI use `ViewportFrame`s for child portraits — the client clones rigs and creates its own camera per viewport because viewport contents don't replicate.

## Minimap board

The physical board's SurfaceGui mirrors a simplified minimap built by `MapService.createMapBoard`.
