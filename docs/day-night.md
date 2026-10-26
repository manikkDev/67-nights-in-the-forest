# Day/Night Cycle

Surviving all 67 days is the goal of a run. Each day alternates between a safe Day phase and a dangerous Night phase.

## Timing

| Phase | Duration | In-game clock |
|-------|----------|---------------|
| Day   | 180s     | 6:00 → 18:00  |
| Night | 90s      | 18:00 → 6:00  |

Values live in `src/shared/RunConfig.luau` (`DayDuration`, `NightDuration`, `DayStartClock`, `DayEndClock`). The `StudioTest` table can shorten them for local testing via the `FastClock` flag — production always uses the values above.

## What changes at night

- Hostile species (wolves, deer, owls, cultists) become active and hunt players.
- The campfire safe zone matters most — staying inside its radius avoids most threats.
- `TimeService` broadcasts `DayStarted` / `NightStarted` to every client; `TimeController` mirrors them locally for UI and ambient audio.

## Testing overrides

`RunConfig.StudioTest` flags (Studio only):

- `FastClock` — use `StudioTest.DayDuration` / `StudioTest.NightDuration`
- `ForceNight` — jump straight to the night phase
