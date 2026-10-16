# State Model

The run has three layered state machines. Types are defined in
`MatchFlowService`, `RunStateService`, and `PlayerLifeService`.

## `FlowState` — lobby-to-game flow (MatchFlowService)

```
Lobby -> Waiting -> Countdown -> Story -> Day1 -> InGame
```

- `Lobby` — no active session
- `Waiting` — party forming (members joinable)
- `Countdown` — launch timer running (`Countdown` signal ticks)
- `Story` — intro story panels playing
- `Day1` — "Day 1" reveal screen
- `InGame` — run is live in the forest

## `RunPhase` — authoritative run lifecycle (RunStateService)

```
Lobby -> Starting -> Active -> Ending -> Ended -> (back to Lobby)
```

Server-side signals: `RunStarted`, `RunEnding`, `RunCleaned` carry the
transitions; `PhaseChanged` mirrors them for other services.

## `LifeState` — per-player (PlayerLifeService)

```
Lobby -> Alive -> Downed -> Eliminated
```

- `Alive` — normal play
- `Downed` — bleed-out timer running; teammates can revive or drag the body
- `Eliminated` — spectate only

Related server signals: `PlayerDowned(player, source)`,
`PlayerRevived(reviver, target)`, `PlayerEliminated(player)`.
