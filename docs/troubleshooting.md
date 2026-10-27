# Troubleshooting

Common issues when building or running the game.

## Rojo build fails

- Run from the repo root — `default.project.json` paths are relative
- Check for syntax errors in recently edited `.luau` files
- `wally install` if `Packages/` is missing (see `wally.toml`)

## Game boots but services fail

`Server.server.luau` aborts startup with a loud error listing failed services — check the Output window for the missing/failed module name.

## Studio assets missing

`ServerStorage.Assets` and the physical boards are NOT synced by Rojo — they live in the place file. Inspect them via Studio's Explorer or MCP tools, not the filesystem.

## Spear looks wrong in hand

See the "Weapon Tool Creation" section in `AGENTS.md` — the grip must be `Spear.handle.Grip`, and any other part named `Handle` must be renamed before parenting.

## ViewportFrame portraits are blank

Viewport contents don't replicate server→client. The client must clone the rig and create its own camera inside each ViewportFrame — `RescueController.loadBoardPortraits()` already retries until the board exists.
