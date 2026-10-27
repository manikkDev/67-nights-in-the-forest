# Ending & Results

A run ends in victory at Day 67, or in defeat when the whole team is eliminated.

## Results screen

`EndingService` finalizes results: days survived, kills, rescues, resources gathered, and the score multiplier — sent to clients via `ShowResults`/`HideResults` remotes. `EndingController` renders the stamp-style results panel.

- Results display for `RunConfig.ResultsDisplaySeconds` (18s)
- Then a replay vote window of `ReplayVoteSeconds` (30s)

## Replay votes

`RequestReplay` / `RequestEarlyReturn` remotes handle the vote — cooldowns are 1.5s each. A return acknowledgement signal (`ReturnAcknowledged`) confirms when the server accepts.

## Cleanup

`RunStateService` tears the run down: runtime folder cleared, run-scoped profile keys reset (Base, Rescue, Stats, Campfire), and `RunCleaned` fires before players are routed back to the lobby.

## Reserved signals

`RunEnded` exists on the client service surface but is currently unfired — reserved for a future post-results hook.
