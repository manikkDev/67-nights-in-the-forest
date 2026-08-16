# 67 Nights in the Forest

A survival game where players must endure 67 nights in a hostile forest. Each night brings increasing danger, and players must manage hunger, scavenge resources, and survive until dawn.

## Tech Stack

- **Rojo 7.6.1** — File-system ↔ Roblox Studio synchronisation
- **Wally** — Package manager for Roblox Lua packages
- **Knit** — Networking framework (Services / Controllers)
- **ProfileService** — Session-locked DataStore wrapper
- **Janitor** — Resource cleanup
- **Signal** — Event handling
- **Promise** — Async operations

## Project Structure

```
67 nights in the forest/
├── default.project.json      # Rojo project configuration
├── wally.toml                # Wally package manifest
├── wally.lock                # Wally lock file
├── rokit.toml                # Rokit toolchain config
├── src/
│   ├── Server/
│   │   ├── Server.server.luau        # Knit server bootstrapper
│   │   ├── Data/
│   │   │   └── ProfileTemplate.luau  # Default player data schema
│   │   └── Services/
│   │       ├── PlayerDataService.luau  # Session-locked data (ProfileService)
│   │       ├── WorldService.luau       # Map cloning & campfire anchor
│   │       ├── SpawnService.luau       # Lobby-to-game teleportation
│   │       └── TimeService.luau        # Day/night cycle controller
│   ├── Client/
│   │   ├── Client.client.luau         # Knit client bootstrapper
│   │   └── Controllers/
│   │       └── TimeController.luau     # Client-side day/night listener
│   └── shared/                        # Shared modules (future)
├── Packages/                  # Wally shared packages (gitignored)
├── ServerPackages/            # Wally server-only packages (gitignored)
└── ServerStorage.Assets/      # Maps, NPCs, items (managed in Studio)
```

## Getting Started

### Prerequisites

- [Roblox Studio](https://www.roblox.com/create)
- [Rojo](https://rojo.space/docs) 7.6.1+
- [Wally](https://github.com/UpliftGames/wally)
- [Rokit](https://github.com/rojo-rbx/rokit) (optional, for toolchain management)

### Setup

1. Install Wally packages:

```bash
wally install
```

2. Build the place file:

```bash
rojo build -o "67 nights in the forest.rbxlx"
```

3. Open the `.rbxlx` file in Roblox Studio.

4. Start the Rojo sync server:

```bash
rojo serve
```

5. Connect Roblox Studio to the Rojo server (one-time setup per session).

## Architecture

### Knit Services (Server)

| Service             | Responsibility                                                                                                                            |
| ------------------- | ----------------------------------------------------------------------------------------------------------------------------------------- |
| `PlayerDataService` | Loads and releases player profiles via ProfileService with session-locking. Exposes read-only data access to clients.                     |
| `WorldService`      | Clones `lobby-map` and `base-map` from `ServerStorage.Assets` into `Workspace`. Creates a Campfire anchor part at the base-map centre.    |
| `SpawnService`      | Server-authoritative teleportation from lobby to game map. Players are placed at random positions around the Campfire.                    |
| `TimeService`       | Drives the day/night cycle via `RunService.Heartbeat`. Fires `DayStarted` / `NightStarted` Knit signals and tweens `Lighting` properties. |

### Knit Controllers (Client)

| Controller       | Responsibility                                                                                                    |
| ---------------- | ----------------------------------------------------------------------------------------------------------------- |
| `TimeController` | Subscribes to server `DayStarted` / `NightStarted` signals. Placeholder for UI indicators and ambient audio cues. |

### Player Data Schema

```lua
{
    NightsSurvived = 0,
    Hunger = 100,
    MaxHunger = 100,
    Inventory = {},
}
```

All data is server-authoritative. The client can read its own data via the `PlayerDataService:GetData` remote but cannot write to it.

## Development Roadmap

See `ROADMAP.md` for the detailed, up-to-date phase breakdown.

- **Phase 1** ✅: Core framework, data layer, day/night cycle, lobby-to-game transition
- **Phase 2** ✅: Survival mechanics (hunger, harvest, forage, eating, inventory UI, campfire safety)
- **Phase 3** ✅: NPC enemies, the Deer, combat, cultist raids, procedural animations, VFX
- **Phase 4** (current): Base building, rescue, day multiplier, win/loss, permadeath

## Code Style

All Luau scripts follow a strict 3-section layout:

```lua
-- // VARIABLES // --
-- // FUNCTIONS // --
-- // INITIALIZATION // --
```

UDD-style doc-comments are used on every function. No in-body comments.

## License

MIT
