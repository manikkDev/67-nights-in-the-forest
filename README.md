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
- **ZonePlus** — Zone detection library (available, currently unused)

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
│   │   ├── WorldPlacement.luau       # Collision-aware placement helper
│   │   ├── Data/
│   │   │   └── ProfileTemplate.luau  # Default player data schema
│   │   └── Services/                 # 32 Knit services (server authority)
│   ├── Client/
│   │   ├── Client.client.luau        # Knit client bootstrapper
│   │   └── Controllers/              # 28 Knit controllers (UI/input)
│   └── shared/                       # Shared config modules & utilities
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
rojo build default.project.json --output build.rbxl
```

3. Open `build.rbxl` in Roblox Studio.

4. Start the Rojo sync server:

```bash
rojo serve
```

5. Connect Roblox Studio to the Rojo server (one-time setup per session).

## Documentation

- `docs/controls.md` — player key bindings
- `docs/state-model.md` — FlowState / RunPhase / LifeState state machines
- `docs/networking.md` — full Knit remote/signal inventory
- `ARCHITECTURE.md` — Phase 1 planning doc (stale; see banner)
- `ROADMAP.md`, `TASKS.md`, `SETUP_MAC.md` — planning/setup notes

## Architecture

### Knit Services (Server)

One service per bounded context; every client-facing remote is validated server-side. Highlights:

| Service                                                              | Responsibility                                                                   |
| -------------------------------------------------------------------- | -------------------------------------------------------------------------------- |
| `RunStateService`                                                    | Authoritative run lifecycle (Lobby → Starting → Active → Ending → Ended)         |
| `MatchFlowService`                                                   | Party queue, session routing, countdown/story gating before `InGame`             |
| `PlayerDataService`                                                  | Session-locked ProfileService profiles; read-only data access for other services |
| `PlayerLifeService`                                                  | Life states (Alive/Downed/Eliminated), revive/drag/spectate flow                 |
| `TimeService`                                                        | Day/night clock, `DayStarted`/`NightStarted` signals, `Lighting` tweens          |
| `CampfireService`                                                    | Fuel decay, campfire levels, safe-zone radius                                    |
| `WorldService`/`WorldPlacement`                                      | Map lookup, bonfire placement, reservation-based scatter positioning             |
| `RescueService`                                                      | Missing-children caves, rescue unlocks (Dino Lv2 → Koala Lv5)                    |
| `AnimalAIService`/`DeerService`/`OwlService`                         | Species AI, hunts, flee/aggro behaviour                                          |
| `CombatService`/`FlashlightService`                                  | Weapon tools (Axe/Spear), flashlight stun                                        |
| `LootService`/`InventoryService`/`CraftingService`/`BuildingService` | Chests, carry bags, recipes, structure placement                                 |

### Knit Controllers (Client)

One controller per matching client concern — HUD/bars (`Hud`, `Hunger`, `HealthBar`, `Campfire`, `CampSafety`), interaction (`Harvest`, `Carry`, `Loot`, `Crafting`, `Building`, `Rescue`), presentation (`Intro`, `GameState`, `Spectate`, `Map`, `Ending`), and creature/VFX (`Deer`, `Owl`, `Combat`, `Flashlight`, `ProceduralAnim`, `Phase4Effects`, `RaidBanner`, `Time`, `Grinder`, `WorldBoundary`, `Inventory`, `LifeState`).

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

UDD-style doc-comments are used on every function. In-body comments are kept sparse and only explain non-obvious ordering or timing.

## License

MIT
