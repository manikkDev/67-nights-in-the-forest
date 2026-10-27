# Spectating

Eliminated players become spectators — a free camera that can cycle through living teammates.

## Controls

- **E / next**: cycle to the next living player (wraps around via modulo)
- The spectate bar at the bottom of the screen shows who you're watching

## Camera

`SpectateController` detaches the camera from the dead character and follows the target's HumanoidRootPart. Switching targets is instant.

## Entry

Spectate mode activates automatically when `LifeState` becomes `Eliminated` — there is no manual spectate toggle for living players.

## Exit

Spectating ends only when the run ends (results screen) or the player leaves.
