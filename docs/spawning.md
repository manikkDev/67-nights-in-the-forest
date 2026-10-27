# Spawning

`SpawnService` handles character placement on both sides of the two-place architecture.

## Lobby

On the lobby place, players spawn at the lobby spawn area and can wander between the party teleporter pads.

## Game

On the game place, players spawn near the campfire at the base map. Downed bodies and revives preserve position — only fresh spawns and eliminations move through the spawn flow.

## Respawn

- Dying without a revive → Eliminated → spectator, no respawn
- Beds placed in the camp act as preferred spawn anchors

## Studio

In Studio, `ServerRole` reports `IsGameServer() = true` so the full game path runs; the lobby character spawn is handled separately.
