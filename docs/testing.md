# Testing

## Build check

```
rojo build default.project.json --output build.rbxl
```

Run from the repo root. A clean build confirms Rojo mapping and syntax are valid.

## In-Studio playtesting

Open the built `.rbxl` (or sync via `rojo serve`) and press Play. `ServerRole` reports `IsGameServer()` in Studio, so the full game path runs without needing the lobby place.

## Debug flags

`RunConfig.StudioTest` (Studio only):

- `SkipLobby` — jump straight into the game flow
- `ForceGameMode` — force the game-place role
- `GrantResources` — starter resources for testing
- `FastClock` — short day/night durations
- `ForceNight` — jump to the night phase
- `InfiniteWood`, `VerboseFlashlight`, `VerboseStalkers` — focused debugging aids

Remember to revert temporary values before committing — `StudioTest.DayDuration` should not ship changed.

## Linting

`selene.toml` and `stylua.toml` configure the project's lint/format toolchain.
