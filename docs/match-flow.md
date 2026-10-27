# Match Flow

From joining the lobby to spawning in the forest, the game runs through a fixed state machine.

## FlowStates

`Lobby` → `Waiting` → `Countdown` → `Story` → `Day1` → `InGame`

- **Lobby** — players hang in the start place and form parties at teleporters
- **Waiting** — party queued for a reserved server
- **Countdown** — 20s countdown (`Constants.MATCH_COUNTDOWN_SECONDS`), fast-forwards to 3s when everyone is ready
- **Story** — the four-panel story intro plays
- **Day1** — brief hold on the Day 1 reveal
- **InGame** — the run proper begins on the game place

## Server-side driver

`MatchFlowService` owns transitions, rate-limits party requests (`PARTY_REQUEST_COOLDOWN` = 0.35s), picks the host, and reserves the game server via `SessionRoutingService`.

## Client mirror

`GameStateController` mirrors `FlowState` locally; `IntroController` renders the countdown, story panels, and Day-1 reveal.
