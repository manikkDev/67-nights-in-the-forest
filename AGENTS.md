# 67 Nights in the Forest — Project Notes

## Build & Verify

- **Compile-check lobby scripts**: `rojo build default.project.json --output build.rbxl`
- **Compile-check game scripts**: `rojo build game.project.json --output game.rbxl`
- Run from the repo root: `D:\Roblox Studio Games\67 nights in the forest`
- **NEVER publish the generated `build.rbxl` or `game.rbxl`.** The Rojo project files do not map the manually stored Workspace maps or `ServerStorage.Assets`, so generated builds contain scripts but omit essential place content.
- Publish only from the real lobby/game Studio documents after connecting each document to its matching Rojo project and syncing scripts into it.
- Studio assets (`ServerStorage.Assets`) and manually placed Workspace content are not synced by Rojo. Inspect and preserve them in the real place documents.

## Two-Place Architecture

### Overview

The experience uses two places under the same experience:

- **Lobby place** (start place, ID `84560195693908`): real Studio place document containing the lobby map, teleporters, and party formation UI. No game systems run here.
- **Game place** (ID `106278588126757`): real Studio place document containing the forest map, campfire, and Studio-only assets. Each party gets a reserved server of this place.

### ServerRole detection (`src/shared/ServerRole.luau`)

- `ServerRole.IsLobby()` → true on the lobby place
- `ServerRole.IsGameServer()` → true on a reserved game server
- Detection order: DataModel attribute `ServerRole` (set by `game.project.json`) → **PlaceId check** (production only: `game.PlaceId == Constants.GAME_PLACE_ID`) → Studio `ForceGameMode`/`SkipLobby` flags → production `PrivateServerId` check
- The PlaceId check is the most reliable detection in production — it doesn't depend on attributes or PrivateServerId behavior.
- A one-shot diagnostic log is printed on the first `IsGameServer()` call showing all detection values.

### Studio testing

- **Lobby Studio document**: playtest shows lobby UI, teleporters, and party formation. No fog or game UI.
- **Game Studio document**: playtest with `StudioTest.ForceGameMode = true` skips the lobby and starts the game directly.
- To test the game place, connect its Studio document to `game.project.json`, enable the required Studio flags temporarily, and playtest that document.
- Real teleport testing requires publishing both real Studio place documents.

### What's gated

- **28 game-only server services** return early from `KnitStart` on the lobby (WorldService, CampfireService, AnimalAIService, etc.)
- **25 game-only client controllers** return early from `KnitStart` on the lobby (HudController, InventoryController, WorldBoundaryController, etc.)
- **4 controllers** also gate `KnitInit` (HungerController, InventoryController, HudController, CampSafetyController) because they create UI there
- **Shared services** (MatchFlowService, SessionRoutingService, SpawnService, PlayerDataService) run on both places with conditional behavior
- **IntroController** only runs on the lobby place (inverse gate: returns early if NOT lobby)
- **GameStateController** auto-marks as in-game after 2s on the game place (not lobby). This unlocks all gameplay interactions (hover, drag, F-key, axe chopping, combat, flashlight, inventory). On the lobby, it waits for the IntroController to call `MarkIntroComplete()`.

### GameStateController — IsInGame() gate

Many controllers gate gameplay on `GameStateController:IsInGame()`:

- CarryController (hover, drag, F-key pickup/drop)
- HarvestController (axe tree chopping)
- CombatController (Spear attack)
- FlashlightController (flashlight toggle)
- InventoryController (bag panel show, wireInteractions)
- HudController (HUD labels)
- HungerController (hunger UI)
- CampSafetyController (camp safety)
- CampfireController (campfire UI)
- ProceduralAnimController (breathing animation)

On the lobby place, `IsInGame()` becomes true when `IntroController` calls `MarkIntroComplete()` after the Day 1 intro card fades.

On the game place, there is no intro screen. `GameStateController` auto-marks as in-game after 2 seconds as a safety net, in case the server's `FlowStateChanged = "InGame"` signal is missed during the teleport transition.

### Creator Dashboard setup (required for production)

1. Create or restore the game sub-place under the experience.
2. Confirm the Place IDs in `src/shared/Constants.luau`.
3. Open the real game place in Studio, connect `game.project.json`, sync scripts, verify `Base-map` and `ServerStorage.Assets` still exist, then publish that Studio document.
4. Set the sub-place access so players enter through lobby teleportation.
5. Open the real lobby place in Studio, connect `default.project.json`, sync scripts, verify `lobby-map` still exists, then publish that Studio document.
6. Never use Rojo-generated compile-check files as publish sources.

## Weapon Tool Creation (Spear / Axe / future weapons)

### Root cause of the Spear grip bug (fixed)

The Spear model in `ServerStorage.Assets["Assets Items"].Spear` has this hierarchy:

```
Spear (Model)
  ├── Union          (spear head, small 0.2×1.4×1.4)
  ├── SpearTip       (MeshPart, the metal tip)
  └── handle (Model)
       ├── Handle    (brown cylindrical shaft, long axis along X)
       ├── Grip      (small red cylinder, where the hand should hold)
       └── rope (Model)
            └── rope (×2, decorative wrappings)
```

**The bug:** `buildSpearTool()` was using `Spear.Union` (the spear head) as the Tool's `Handle` part instead of `Spear.handle.Grip` (the actual hand grip). This made every `Grip*` rotation pivot around the spear head, leaving the long shaft displaced horizontally through the character.

**The fix (3 changes in `CombatService.buildSpearTool()`):**

1. Use `Spear.handle.Grip` as the Tool Handle (not `Spear.Union`).
2. Rename the original brown `Spear.handle.Handle` to `Shaft` before parenting — Roblox attaches the hand to the **first** part named `Handle` it finds, so having two parts named `Handle` causes it to grab the wrong one.
3. Set `tool.Grip = CFrame.Angles(0, 0, math.rad(90))` — the shaft's long axis runs along world X (rotated 90° on Y), so a +90° Z rotation in the Tool grip orients the spear vertically with the tip pointing up.

### Rules for adding any new weapon Tool

1. **Inspect the source model in Studio** (via MCP `inspect_instance` / `search_game_tree`) before writing the build function. Identify which part is the actual hand grip.
2. **Use the hand-grip part as the Tool `Handle`**, not the blade/head/tip.
3. **Rename any other part already named `Handle`** to something else (e.g. `Shaft`, `Blade`) before parenting — Roblox uses the first `Handle` child for the RightGrip weld.
4. **Weld all other parts to the Handle** with `WeldConstraint` so they follow.
5. **Set `tool.Grip`** (a CFrame) rather than the individual `GripPos`/`GripForward`/`GripUp`/`GripRight` properties — it's a single transform and easier to reason about.
6. **Test at runtime** by equipping the tool and reading part positions via `execute_luau` to confirm the tip is above the hand and the shaft is vertical before shipping.

## Day/Night Cycle

- `src/Shared/RunConfig.luau` → `DayDuration` (currently 300s for testing; revert to 180 when done).
- `NightDuration` = 90s.

## Chest / Loot System

- `LootService` handles two types of chests:
  1. **Landmark chests** — placed near landmarks (cabin, tower, etc.). One-open-per-run (global). Grants resources only.
  2. **Cave chests** — placed inside caves (e.g. Dino cave). Per-player open (each member gets their own loot). Can grant Tools (e.g. Spear) + resources.
- Cave chests use `IsCaveChest = true` attribute and per-player tracking via `openedCaveChests[player][chestId]`.
- The `ChestOpened` signal fires **only to the opener** (not all members).
- Cave chest spawning is deferred (`task.defer + task.wait(0.1)`) because `RescueService.buildCaves()` also defers on `RunStarted` — caves must exist before chests can be placed.
- Chest assets (`basic-chest`, `Gold-chest`) are single-mesh parts with no separate lid. Open animation = bounce/scale tween + golden particle burst + point light flash + wooden chest sound (`rbxassetid://9120873624`).
- `LootController` (client) shows a loot UI panel with item icons, names, quantities, and descriptions. Auto-dismisses after 8s or on Close click.
- The Spear is NOT granted by default. It's only obtainable from the Dino cave chest.
- `CombatService:GetSpearTemplate()` exposes the cached spear tool template for LootService to clone.
- `RescueService:GetCaveCenter(caveId)` exposes cave center positions for LootService chest placement.

## Rescue System

- Order: Dino → Kraken → Squid → Koala (matches the real 99 Nights game).
- Unlock thresholds: Dino Lv2, Kraken Lv3, Squid Lv4, Koala Lv5.
- Portrait templates are built once in `RescueService:KnitStart()` and parented to `ReplicatedStorage.Portraits`. Both the physical board and the client map UI clone from there.
- `ViewportFrame` contents do NOT replicate from server to client. The client must create its own camera + model clone inside every ViewportFrame (both the physical board's SurfaceGui and the map UI).
- Physical board portraits: client `loadBoardPortraits()` in `RescueController` populates them with a retry loop (board may not exist yet at KnitStart time).
- Track/Untrack: `RequestSetWaypoint` / `RequestClearWaypoint` server methods. Client tracks `trackedRescueId` and toggles button text. Board prompt no longer auto-tracks.

## Fog Wall

- Removed. `WorldBoundaryController` now only handles the proximity warning HUD + ColorCorrection effect. No particle emitters or panels.

## UI Readability

- Use `Enum.Font.GothamBold` for body text, `Enum.Font.PermanentMarker` for titles/stamps.
- Text stroke transparency 0.15–0.25 for titles, 0.5–0.6 for labels on light backgrounds (use light stroke color on dark text).
- Status colors: Locked = red `(200, 60, 50)`, Available = green `(40, 170, 60)`, Rescued = green `(40, 180, 60)`, Carried = yellow `(210, 160, 30)`.

## Multiplayer & Life-State Architecture

### Reserved-server isolation

- Each party gets its own reserved server via `TeleportService:ReserveServer`.
- `SessionRoutingService` attaches server-authored party metadata (partyId, hostUserId, initialPartySize, expectedUserIds, issuedAt).
- Destination validates every arrival against expected user IDs and rejects mismatched/expired entries.
- Studio skips teleport and uses the local party directly.
- Reconnect tickets stored in MemoryStore (`ForestRunReconnectTicketsV1`) with a 120s TTL.

### Party formation (MatchFlowService)

- 3 teleporter queues: Teleporter1, Teleporter2, Teleporter3.
- Party capacity 1–5. Only the host can start or change capacity.
- Host migration is deterministic (next member by join order).
- Client requests are rate-limited (`PARTY_REQUEST_COOLDOWN = 0.35`).

### Run membership (RunStateService)

- `GetMembers()` returns only active run members.
- `IsMember(player)` checks the live member set.
- `RemoveMember(player)` removes one player without ending the run (used by individual lobby return).
- `AddMember(player)` requires a pre-existing member record (prevents injection).
- All gameplay broadcasts use `GetMembers()`, not `Players:GetPlayers()`.

### Life states (PlayerLifeService)

- States: Lobby → Alive → Downed → Eliminated → Alive (revive) or Lobby (cleanup).
- Downed players stay in-world with a revive prompt. Bleed-out after `DownedDuration` (45s) → Eliminated.
- Eliminated bodies remain visible and revivable indefinitely.
- Revive requires: alive reviver, downed/eliminated target, within `ReviveRange` (12), Bandage consumed atomically, revive lock prevents duplicate concurrent requests.
- Campfire revive moves the body near the campfire via `SpawnService:ReviveAtCampfire`.
- Team loss triggers when no connected Alive members remain.

### Body dragging

- Alive teammates can drag downed/eliminated bodies.
- Server-owned AlignPosition constraint. Drag target updates rate-limited (`BodyDragUpdateInterval = 0.04`).
- Max drag distance `BodyDragMaxDistance` (28). Cleanup on stop, death, revive, disconnect, run end, or invalid distance.

### Difficulty scaling

- Fixed from `initialPartySize` for the entire run (does not decrease when players leave).
- `RunConfig.ScaleEnemyCount(base, partySize)` and `ScaleEnemyHealth(base, partySize)`.
- Health: +12% per additional player. Count: +15% per additional player. Damage unchanged.

### Ending flow (EndingService)

- Victory: Day 67 reached. Defeat: all members downed/eliminated.
- Results display shows for `ResultsDisplaySeconds` (12s) on victory, extended by `ReplayVoteSeconds` (30s) on defeat.
- **Individual return**: `RequestEarlyReturn` returns only the calling player to the lobby. The run continues for remaining members. Rate-limited (`EarlyReturnCooldown = 1.5s`).
- **Replay voting** (defeat only): `RequestReplayVote` casts a yes vote. Run restarts only when all remaining members vote yes. Host can cancel via `RequestReplayCancel`. Vote window is `ReplayVoteSeconds` (30s). Rate-limited (`ReplayRequestCooldown = 1.5s`).
- Replay preserves party metadata (partyId, host, initial size) via `MatchFlowService:StartRunForReplay`.

### UI layering (DisplayOrder)

- LifeStateGui: 45 (downed card)
- SpectateGui: 46 (spectator panel)
- EndingGui: 100 (results overlay)
- Downed/spectator UI auto-hides on Ending/Ended/Lobby phase changes.

## Multiplayer Test Checklist

### Studio (local, no teleport)

- [ ] 1-player party: queue, start, spawn, play, reach defeat/victory
- [ ] 2–5-player party: all members spawn together, shared campfire/crafting
- [ ] Party capacity buttons only editable by host
- [ ] Non-host members see "Waiting for Host"
- [ ] Host migration when host leaves (next member becomes host)

### Reserved-server (published place, requires real Roblox multiplayer)

- [ ] Party teleports to reserved server successfully
- [ ] Non-party players cannot join the reserved server
- [ ] Reconnect ticket works within 120s window
- [ ] Teleport failure recovery (partial party)

### Life state & revive

- [ ] Player downs when HP reaches 0 (stays in-world, not below map)
- [ ] Downed card shows countdown timer
- [ ] Teammate can revive with Bandage (proximity prompt, hold 5s)
- [ ] Revived player spawns near campfire with 35 HP
- [ ] Eliminated player remains visible and revivable
- [ ] Revive from Eliminated state works with Bandage
- [ ] Team loss triggers when all members are downed/eliminated

### Body dragging

- [ ] Alive teammate can lift and drag downed/eliminated body
- [ ] Drag stops when distance exceeds 28 studs
- [ ] Drag stops on reviver death, disconnect, or run end
- [ ] Only one dragger per body
- [ ] Cannot drag yourself

### Spectating

- [ ] Eliminated player sees spectator panel
- [ ] Q/E or L1/R1 cycles teammates
- [ ] Health bar updates live
- [ ] Camera restores on revive or run end
- [ ] Spectator UI hides during ending screen

### Ending & replay

- [ ] Victory screen shows "DAY 67 SURVIVED" with stats
- [ ] Defeat screen shows "THE FOREST CLAIMED THE TEAM" with stats
- [ ] Individual return button returns only the clicking player
- [ ] Replay vote button appears only on defeat
- [ ] Vote requires ALL remaining members to vote yes
- [ ] Host can cancel replay vote
- [ ] Vote times out after 30s
- [ ] Replay restarts the run with same party metadata
- [ ] Downed/spectator UI does not overlap ending screen

### Shared co-op systems

- [ ] Crafting bench shows shared shredded totals (not personal inventory)
- [ ] Campfire level/fuel is shared across all members
- [ ] Landmark chests: one-open-per-run (global)
- [ ] Cave chests: per-player open (each member gets loot)
- [ ] Difficulty scales with initial party size (more enemies in larger parties)
