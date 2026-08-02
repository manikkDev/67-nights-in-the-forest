# 67 Nights — Technical Architecture

## 1. Reference Indexing Summary

**Skills read:** `Skills/AI Roblox Game Development Guide.md`, `Skills/roblox-best-practices-skill-blob.md` (both fully ingested; no `references/*.md` sub-files exist in this repo, so the top-level blob is the complete ruleset — script section layout, UDD doc comments, server authority, memory/network rules all apply as written).

**Rojo tree** (`default.project.json`): `ReplicatedStorage.Shared` → `src/shared`, `ServerScriptService.Server` → `src/server`, `StarterPlayer.StarterPlayerScripts.Client` → `src/client`. All three currently hold only stub files (`Hello.luau`, `init.server.luau`, `init.client.luau`).

**Toolchain** (`rokit.toml`): only `rojo@7.6.1` pinned. Wally is not yet installed — Phase 1 adds `wally.toml` plus a `rokit add` entry for the Wally CLI itself before any package install.

**Live DataModel audit (via MCP `search_game_tree` / `execute_luau`):**

| Location | Contents |
|---|---|
| `ServerStorage.Assets.[Assets maps items]` | `Base-map` (3409 parts, spawn+stove+fridge+TV scripts already wired, no PrimaryPart set), `lobby-map` (2573 parts, teleporters/gates/lock/poster already present, no PrimaryPart set), `Tree`/`bigtree`/`Treehouse`, `cabin`, `mushroom-house`, `Log Wall`, `Ice Temple`, `Hunters Lodge`, `Crashed Plane`, `modern-house`, `Tower`, `crafting-table`, `basic-chest`/`Gold-chest` |
| `ServerStorage.Assets.[Assets Npcs]` | `WolfModel`, `AlphaWolfModel` (Humanoid, no baked anims — procedural gait required), `Bear` (1 Attack anim), `Deer` (7 anims: Idle/Jumpscare/Stunned x3/Walk/Run — has a charge-stun state machine built in), `Cultist`/`Cultist2` (1 Attack anim each), `BunnyModel`, `Owl`, `Ram Monster` (no baked anims), `Dino Kid`/`Kraken Kid` (child rescue NPCs, no anims) |
| `ServerStorage.Assets.[Assets Items]` | `Bonfire`, `Log` (wood pickup), `Carrot`, `rabbit-meat`, `wolf-meat` |
| `StarterGui` | `DayLabel`, `NightLabel`, `HealthBarFill` (pre-wired ScreenGuis to hook into), plus 4 blank `ScreenGui` spares |
| `Workspace` | Empty except `Baseplate`/`Terrain`/`Camera` — `base-map`/`lobby-map` are **not yet cloned into Workspace**, they live in `ServerStorage` only |

**Key finding:** the campfire the brief describes as "already burning in the base-map" is actually the standalone `ServerStorage.Assets.[Assets Items].Bonfire` model — it is not yet parented into `Base-map` or Workspace. Phase 1 must clone `Base-map`/`lobby-map` into `Workspace` and place/anchor the `Bonfire` at the camp origin as part of world bootstrap.

**Deer** model already ships a `Stunned` 3-phase animation set matching the "immune while charging, stunned when hit with fire/light" mechanic from the wiki — Phase 3 AI should read this as a signal the asset was prepped for that exact behavior.

---

## 2. Knit Architecture (Client Controllers / Server Services)

Networking library: **Knit** (via Wally). One Service per bounded context, one Controller per matching client concern. Every Service validates all Client-facing method args per Non-Negotiable Rule 1.

### Server Services (`src/server/Services/`)

| Service | Owns | Key Client-exposed methods |
|---|---|---|
| `DataService` | ProfileService session-locked profile load/save/release | none (internal only, other Services read `DataService:GetProfile(player)`) |
| `WorldService` | Clones `Base-map`/`lobby-map` from ServerStorage into Workspace at boot, anchors Bonfire, terrain safe-zone setup (ZonePlus camp radius) | none |
| `DayNightService` | Authoritative day/night clock, `CurrentPhase`/`DayNumber` state, drives `Lighting` tween, fires `PhaseChanged` signal | `GetPhaseState()` |
| `CampfireService` | Fuel level (0-100), decay tick, fog-of-war radius tied to fuel tier | `RequestFuelCampfire(logCount)` |
| `HungerService` | Per-player hunger/health decay ticks, starvation damage | `RequestEat(itemId)` |
| `HarvestService` | Tree chop validation (proximity + tool + cooldown), spawns wood pickup, tree respawn timer | `RequestChopTree(treeInstance)` |
| `CombatService` | Wolf/Cultist/Deer/Ram hit validation (ZonePlus hitbox + range + cooldown), damage application, loot drop (meat) | `RequestAttack(targetInstance)` |
| `AnimalAIService` | Spawns/despawns Bunny/Deer/Wolf/AlphaWolf/Bear/RamMonster/Cultist per day-night population rules, drives PathfindingService state machines | none |
| `BuildingService` | Bed/wall/structure placement validation (grid snap, ZonePlus camp bounds, resource cost), day-multiplier bed count | `RequestPlaceStructure(id, cframe)` |
| `RescueService` | Missing Poster Board interaction, cave unlock (wolf-kill gate), rescued-children count, multiplier grant | `RequestOpenPosterBoard()` |
| `TeleportService` (wrapper) | Lobby → base-map server assignment via `TeleportService` API | `RequestJoinGame()` |

### Client Controllers (`src/client/Controllers/`)

| Controller | Owns |
|---|---|
| `HudController` | Binds `DayLabel`/`NightLabel`/`HealthBarFill`/Hunger bar/Inventory GUIs to Service signals — no UI created from scratch |
| `InteractionController` | ProximityPrompt / raycast-based interact requests (tree, campfire, poster board, structures) → fires request to matching Service |
| `CombatController` | Local swing input, client-side swing animation trigger (procedural, see §5), fires `CombatService:RequestAttack` |
| `CameraController` | Night-time visibility falloff, fog-of-war radius shader/Lighting tie-in |
| `ProceduralAnimController` | Drives CFrame/Motor6D procedural idle/walk/attack for the local character's tool-swing and any client-rendered NPC flourishes |
| `AudioController` | Ambient day/night audio, campfire crackle, hit SFX triggers |

---

## 3. DataStore Structure (ProfileService/ProfileTemplate)

```lua
-- ProfileTemplate (src/server/Data/ProfileTemplate.luau)
{
    Resources = {
        Wood = 0,
        Stone = 0,
        Berries = 0,
        Mushrooms = 0,
        RawMeat = 0,
        CookedMeat = 0,
    },
    Survival = {
        Health = 100,
        Hunger = 100,
        DeathCount = 0,
        HighestNightSurvived = 0,
    },
    Base = {
        BedCount = 0,
        DayMultiplier = 1,
        UnlockedStructures = {}, -- {structureId: true}
    },
    Rescue = {
        ChildrenRescued = {}, -- {childId: true}
        CavesUnlocked = {},   -- {caveId: true}
    },
    Stats = {
        TreesChopped = 0,
        WolvesKilled = 0,
        TotalPlaytime = 0,
    },
}
```

- Keyed per-player by `UserId`, one profile per player (`ProfileStore/"PlayerData"`).
- Session-locked via ProfileService `:LoadProfileAsync`, released on `PlayerRemoving`.
- `UpdateAsync` semantics inherited from ProfileService; no raw `SetAsync` anywhere.
- Save triggers: periodic autosave (interval, e.g. every 2 minutes — scheduled, not polled), `PlayerRemoving`, `game:BindToClose()`.
- Camp-shared state (campfire fuel, day number, structure placements) is **not** per-profile — it lives in a separate `CampProfile` keyed by server/place instance if persistence across sessions is wanted, or purely in-memory (`DayNightService`/`CampfireService` state) if the base resets every server. **Decision needed from user in Phase 1**: should base progress persist across server restarts, or reset per session (matches 99 Nights' per-run structure)?

---

## 4. RemoteEvent Security Validation Matrix

All remotes are Knit `Service:Client` methods (RemoteFunction/RemoteEvent under the hood), never raw `RemoteEvent` instances placed by hand.

| Action | Server-side validation |
|---|---|
| **Tree chopping** (`HarvestService:RequestChopTree`) | 1) `treeInstance` is a live descendant of the current tree registry (not player-supplied arbitrary path — pass a registered id/ref, verify `CollectionService:HasTag`). 2) Distance check: player's `HumanoidRootPart` within chop range of tree CFrame. 3) Cooldown per player (debounce table, server-owned). 4) Player has required tool equipped (check `Character:FindFirstChildOfClass("Tool")`) if tools are required. 5) Tree not already depleted/on respawn timer. On pass: decrement tree health, grant `Wood` via `DataService`, spawn hit VFX (server-authoritative Instance creation, replicated). |
| **Campfire fueling** (`CampfireService:RequestFuelCampfire`) | 1) `logCount` is a positive integer, capped at inventory's actual `Wood` count (server reads profile, never trusts client-sent amount as truth — clamps to `min(requested, owned)`). 2) Distance check: player within camp/campfire ZonePlus zone. 3) Rate limit (debounce) to prevent spam-fueling exploits. On pass: deduct `Wood` from profile, increment fuel level (capped at max), extend fog-of-war radius per fuel tier. |
| **Combat / attack** (`CombatService:RequestAttack`) | 1) `targetInstance` resolves to a registered live NPC/Humanoid (tag-checked, not arbitrary Instance). 2) Range check between attacker `HumanoidRootPart` and target root, plus a max-angle/facing check to prevent behind-wall hits. 3) Attack cooldown per player (weapon-specific rate, server-tracked). 4) Target not already dead/despawned (re-validate after any yield). On pass: apply damage server-side to `Humanoid.Health`, apply knockback, spawn hit VFX/loot drop. Client never sends a damage number — server owns the damage table keyed by weapon/tool id. |
| **Building placement** (`BuildingService:RequestPlaceStructure`) | 1) `structureId` in an allow-list, `cframe` within camp ZonePlus bounds and grid-snapped server-side (recompute snap, don't trust client's CFrame precision). 2) Resource cost check against profile (`Wood`/`Stone`), deduct only on success. 3) Overlap check against existing placed structures. |
| **Poster board / rescue** (`RescueService:RequestOpenPosterBoard`) | 1) Distance check to the poster board Instance. 2) Server picks the next unrescued cave/child from server-owned state, never accepts a client-chosen target id. |

General rules applied to every remote: type-check every argument, re-validate liveness after any yield (per Rule 7), rate-limit via debounce tables, and never let the client dictate an outcome (damage, resource amount, position precision) that the server can compute itself.

---

## 5. Procedural Animation & VFX Plan (no FBX/Mixamo assets)

- **Player tool-swing**: `ProceduralAnimController` tweens the equipped Tool's Motor6D/`Grip` CFrame through a swing arc using `TweenService` with an `Elastic`/`Quad` easing, driven by `RunService.Heartbeat` for the wind-up + `TweenService` for the release; cleaned up on tool unequip.
- **Idle breathing**: small-amplitude `math.sin(os.clock() * freq) * amplitude` offset applied to `Humanoid.CameraOffset`/torso Motor6D per Heartbeat, disconnected on character removal.
- **Wolf/Bear/Ram gait**: leg-analog parts (or single lower-body CFrame) driven by `math.sin`/`math.cos` phase-offset per limb, amplitude scaled by `Humanoid.MoveDirection:Magnitude`; Deer/Cultist reuse their **existing baked `Animation` assets** instead (do not procedurally override models that already ship anims).
- **Hit VFX**: `ParticleEmitter`/`Highlight`/`Trail` instantiated via code on hit event, `TweenService` for flash/scale-down, `Debris:AddItem` for guaranteed cleanup — never left to GC alone.
- **Wood-chip burst / blood splatter**: one-shot `ParticleEmitter:Emit(n)` on a temporary anchored `Attachment`, parented under `Debris` lifetime, matches the Deer's existing `Stunned` animation set for charge-interrupt feedback.

---

## 6. Package Plan (Wally)

```toml
[dependencies]
Knit = "sleitnick/knit@1.7.0"
ProfileService = "madstudioroblox/profileservice@1.4.2" # or ProfileStore per skill's community-libraries guidance
ZonePlus = "1foreverhd/zoneplus@3.6.0"
Janitor = "howmanysmall/janitor@1.15.0"
```
(exact versions pinned in Phase 1's `wally.toml`, verified against current Wally registry availability before install)

---

## 7. Open Decisions Requiring User Input Before/During Phase 1

1. **Base persistence**: does camp progress (bed count, structures, campfire fuel, day number) persist across server restarts, or reset per server instance? Affects DataStore schema (§3).
2. **ProfileService vs ProfileStore**: skill's community-libraries guidance prefers checking current recommendation — confirm which is acceptable before pinning in `wally.toml`.
3. **Base-map/lobby-map edits**: both models are pre-built and asset-rich; recommend leaving geometry as-is and only adding functional markers (spawn points, camp zone boundary parts, cave lock volumes) via script/attribute rather than manual remodeling, unless the user wants specific 99-Nights-style additions (missing poster board already exists in `lobby-map`, no equivalent found yet in `Base-map` — needs placement).
