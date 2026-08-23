# 67 Nights — 4-Phase Production Roadmap

This roadmap is the implementation contract for **67 Nights in the Forest**, a distinct Day-67 survival-horror game inspired by the core loop of Roblox's **99 Nights in the Forest**: daytime gathering, a campfire-centered safe zone, nighttime entities, escalating raids, base progression, and missing-child rescues.

Reference mechanics were cross-checked against the live game page and multiple community wikis in August 2026. Community sources disagree on some balance details, so every number below belongs in configuration data and must be playtested. The stable mechanics used here are: four guarded child rescues, four unique beds, one multiplier point per bed/child, a maximum 9x day multiplier, a six-level campfire, crafting progression, and recurring raids.

The project remains intentionally narrower than the reference game. Phase 4 finishes one polished forest run; it does not attempt to copy every class, biome, event, weapon, trader, or monetization system.

---

## Product Decisions Locked for Phase 4

| Decision          | Final choice                                                                              |
| ----------------- | ----------------------------------------------------------------------------------------- |
| Run goal          | Reach **Day 67**                                                                          |
| Children          | Four arcs: Dino, Kraken, Squid, Koala                                                     |
| Missing child art | Squid and Koala are re-outfitted variants of the existing R6 child rigs                   |
| Day multiplier    | `1 base + 4 unique beds + 4 rescued children = 9x maximum`                                |
| Run persistence   | Camp, resources, rescues, structures, day, and run stats reset every run                  |
| Persistent data   | Lifetime records, best run, settings, and future unlocks only                             |
| Death             | Downed state, teammate revive, bleed-out, then spectating; no active-run auto-respawn     |
| Phase 4 breadth   | Production core: loot, crafting, building, farms, rescue, endings, polish, QA             |
| Asset policy      | Existing assets first; otherwise official Roblox/free or clearly licensed CC0 assets only |
| Supported input   | Keyboard/mouse, touch, and gamepad for every required action                              |

---

## Current Implementation and Asset Audit

The audit below is based on the filesystem source and the live Studio place `84560195693908`, not only the older architecture notes.

### Completed Systems

| Area                     | Status | Current implementation                                                          |
| ------------------------ | ------ | ------------------------------------------------------------------------------- |
| Framework and networking | Done   | Rojo, Wally, Knit, ProfileService, Janitor, Signal, Promise, ZonePlus           |
| Lobby and match intro    | Done   | `MatchFlowService`, `SpawnService`, `IntroController`, `GameStateController`    |
| World bootstrapping      | Done   | Pre-placed `Base-map`/`lobby-map`, runtime campfire anchor and Bonfire wiring   |
| Day/night                | Done   | `TimeService`, Lighting transitions, HUD day/night labels                       |
| Hunger and food          | Done   | Hunger drain/starvation, forage, eating, dropped-meat cooking                   |
| Inventory and carrying   | Done   | Capacity, carry bag, pickup/drop/drag, inventory HUD                            |
| Harvesting               | Done   | Tree registry, axe, validated chopping, felling, log drops and respawn          |
| Campfire                 | Done   | Six levels, fuel/progress, drop-to-fuel, safe-zone radius and visuals           |
| Animals                  | Done   | Bunny, Wolf, Alpha Wolf, Bear populations and generic AI                        |
| Stalkers                 | Done   | Deer, Ram, Owl, flashlight stun and unique state machines                       |
| Combat                   | Done   | Axe/Spear, server range/facing/cooldown validation, target registry and loot    |
| Raids                    | Done   | Every-fourth-cycle Cultist raids, warnings, scaling and unresolved-raid penalty |
| Combat feedback          | Done   | Procedural gait/fallbacks, health bars, hit VFX, camera feedback, raid/Owl UI   |

### Phase 4 Fields That Exist but Are Unused

`ProfileTemplate.luau` already contains `Base.BedCount`, `Base.DayMultiplier`, `Base.UnlockedStructures`, `Rescue.ChildrenRescued`, `Rescue.CavesUnlocked`, `Survival.DeathCount`, and `Survival.HighestNightSurvived`. No current service owns these fields, and run-like state should not continue to persist in each player's long-term profile.

### Live Assets Available Now

| Category             | Existing content                                                                    | Phase 4 use                                                                  |
| -------------------- | ----------------------------------------------------------------------------------- | ---------------------------------------------------------------------------- |
| Crafting             | `ServerStorage.Assets.[Assets maps items].crafting-table`                           | Main camp bench; already has crafting interaction attributes                 |
| Beds                 | `ServerStorage.Assets.[Assets Items].Bed`; four bedrolls inside live Hunters Lodges | Source geometry for four unique bed variants                                 |
| Defenses             | `Log Wall`                                                                          | Placeable wall source; derive a matching gate from it                        |
| Children             | `Dino Kid`, `Kraken Kid`                                                            | Use directly; duplicate/re-outfit for Squid and Koala                        |
| Posters              | Lobby `Poster`; four lodge `Poster` parts in Base-map                               | Source part for the Missing Children board                                   |
| Loot                 | `basic-chest`, `Gold-chest`                                                         | One-open-per-run loot containers                                             |
| Locations            | Cabins, Hunters Lodges, Towers, Treehouses, Crashed Planes, modern houses           | Loot anchors and exploration landmarks                                       |
| Items                | Bonfire, Log, Axe, Spear, Coal, Mushroom, Carrot, meat, Flashlight, carry bag       | Reuse before importing any replacements                                      |
| NPC animation source | KeyframeSequences for Deer, Cultists, Wolf, Alpha Wolf, Bear, Bunny, Axe            | Publish/own production animation clips instead of discarding authored motion |
| Existing audio       | Bonfire loop, NPC damage sounds, Flashlight toggle, door sounds                     | Retain where licensed and functional                                         |
| Existing VFX         | Bonfire, tower emitters, grass emitters, Ice Temple sconces                         | Reuse selectively after performance review                                   |

### Missing or Incomplete Production Content

- No `BuildingService`, `CraftingService`, `RescueService`, run lifecycle owner, life-state owner, or ending owner.
- No functional caves, guard-pack gates, keys, guard collars, rescue tents, or child carry/rescue flow.
- Only two child appearances exist; neither child has authored cower/carry/sit animations.
- No reliable source of Scrap, Cultist Gems, Bandages, or structured chest loot.
- No placeable gate, trap, farm plot, storage prop, or four visually distinct multiplier beds.
- Intro image IDs and story panel images are empty; there is no authored ending/results presentation.
- There is no global forest ambience, cave ambience, craft/build sound set, rescue cue, revive cue, or ending cue.
- Essential carry input is still keyboard/mouse-oriented; building/rescue/downed UI does not exist for touch or gamepad.
- No automated tests are present in the repository.
- The Ice Temple is a 1,997-descendant snow-themed landmark; it is not an acceptable cave template for four forest rescues.

### Mandatory Production Cleanup Before Phase 4 Features

Phase 3 is feature-complete but the current branch is still configured for testing. Phase 4 cannot pass its first gate until all of the following are disabled or centralized behind a Studio-only test configuration:

- `SpawnService.TEST_SKIP_LOBBY = true`
- `SpawnService.TEST_GIVE_RESOURCES = true`
- `InventoryService.TEST_INFINITE_WOOD = true`
- `ProfileTemplate.Survival.Health/MaxHealth = 300`
- `TimeService.DAY_DURATION = 15`
- Forced nighttime lighting in the direct-spawn test path
- Per-scan flashlight alignment logging and Deer stun debug logging
- Production behavior hidden behind scattered local test booleans

---

## Phase 1 — Networking, Data, Lobby, Spawn, Day/Night ✅ DONE

**Built:** Wally packages; Knit server/client bootstraps; ProfileService session locking; pre-placed world discovery; lobby teleporter and party intro; server-authoritative spawn; paused lobby clock; day/night lighting; day/night HUD.

**Playable milestone:** Join in the lobby, enter a teleporter, complete the intro, spawn around the campfire, and observe an authoritative day/night cycle.

---

## Phase 2 — Complete Survival Loop ✅ DONE

**Built:** Hunger/starvation; inventory capacity; wearable carry bag; world pickup/drop/drag; tree chopping and logs; six-level fuelled campfire; forage; eating; drop-to-cook meat; inventory HUD; campfire UI; safe-zone warning.

**Playable milestone:** Gather wood and food, keep the fire alive, cook/eat, manage capacity, and understand when the player is safe or exposed.

---

## Phase 3 — Living Forest, Combat, Stalkers, Raids ✅ DONE

**Built:** Generic animal AI; Bunny/Wolf/Alpha/Bear populations; Deer/Ram stalkers; Owl event; flashlight battery and server-validated stun; Axe/Spear combat; NPC health/loot; Cultist raids; procedural and baked animation strategies; combat, raid, and horror feedback.

**Playable milestone:** Hunt and fight by day, survive predators and stalkers at night, repel scheduled raids, and receive readable combat/horror feedback.

**Phase 3 handoff condition:** Feature work is complete. Phase 4 starts with the production cleanup gate above and must regression-test every Phase 1–3 path after run-state refactoring.

---

# Phase 4 — Production Core, Four Rescues, and the Day 67 Ending

Phase 4 converts the existing survival sandbox into a complete run with preparation, progression, objectives, failure, victory, replay, and release-quality presentation.

## Phase 4 Definition of Done

A new player must be able to complete this exact path without admin commands or test flags:

1. Spawn in the lobby and start a fresh run.
2. Gather Wood and food, loot Scrap, maintain the campfire, and survive existing threats.
3. Upgrade the crafting bench and craft structures, farms, defenses, Bandages, and four unique beds.
4. Place and use structures with valid keyboard/mouse, touch, and gamepad controls.
5. Upgrade the campfire to reveal four progressively harder rescue caves.
6. Defeat each cave's guard pack, recover its key, carry the child home, and see the board/tent update.
7. Reach the 9x maximum multiplier after all four beds and children.
8. Be downed, get revived by a teammate, or bleed out and spectate without auto-respawning.
9. Reach Day 67 once, view the ending/results, save lifetime records once, and return to the lobby.
10. Start another run with no previous resources, caves, children, structures, timers, NPCs, or connections left over.

---

## 4.0 — Production Stabilization Gate

### 4.0.1 Central Production Configuration

Create a shared `RunConfig.luau` and remove scattered production/test switches from services.

```lua
return table.freeze({
    GoalDay = 67,
    DayDuration = 180,
    NightDuration = 90,
    StartingHealth = 100,
    StartingHunger = 100,
    MaxMultiplier = 9,
    RaidCycleInterval = 4,
    DownedDuration = 45,
    ReviveHoldDuration = 5,
    ReviveHealth = 35,
    PlacementGrid = 2,
    PlacementRotationDegrees = 15,
    StudioTest = table.freeze({
        SkipLobby = false,
        GrantResources = false,
        InfiniteWood = false,
        FastClock = false,
        ForceNight = false,
        VerboseFlashlight = false,
    }),
})
```

Test overrides may activate only when `RunService:IsStudio()` and must print one startup summary. A published server must ignore them even if a developer accidentally leaves a flag enabled.

### 4.0.2 Required Cleanup

- Restore Health/MaxHealth to 100 in the profile migration/defaults.
- Remove automatic Wood grants and infinite Wood consumption bypass.
- Restore the lobby flow and stop forcing nighttime after spawn.
- Use 180-second days and 90-second nights as the initial production target; rebalance only through `RunConfig`.
- Remove high-frequency debug output from flashlight scans and stalker state decisions.
- Replace `pcall(require)` behavior that silently leaves core services absent with a startup health report. A required service failure must block run creation and show a safe lobby error.
- Record every Heartbeat/RenderStepped/event connection in Janitor or an explicit teardown owner.

### 4.0.3 Exit Test

A solo run and a two-client local server must complete lobby → Day 1 → night → raid warning/raid → food/campfire/combat without test resources, forced lighting, duplicate UI, or related console errors.

---

## 4.1 — Run State, Persistence Boundary, and Character Lifecycle

### 4.1.1 New Authoritative Run Owner

Add `RunStateService.luau`. It owns one server run and exposes immutable snapshots; other services request mutations through its server API.

```lua
export type RunPhase = "Lobby" | "Starting" | "Active" | "Ending" | "Ended"

export type RunState = {
    RunId: string,
    Phase: RunPhase,
    CycleIndex: number,
    DisplayedDay: number,
    StartedAt: number,
    Members: { [Player]: PlayerRunState },
    Campfire: CampfireRunState,
    Structures: { [string]: StructureRecord },
    Rescues: { [string]: RescueRecord },
    BenchTier: number,
}
```

`RunId` is a GUID or monotonically changing token. Every delayed callback captures it and rechecks it after yielding. A callback from an old run must not mutate a new run.

### 4.1.2 Separate Real Cycles from Displayed Progress

- `CycleIndex` starts at 1 and increments by exactly one after every survived night.
- Existing raid cadence, Owl/Ram unlock cadence, spawn scaling, and other scheduled events use `CycleIndex`.
- `DisplayedDay` starts at 1 and advances by the current multiplier at dawn.
- UI and the Day 67 ending use `DisplayedDay`.
- This split prevents a 9x multiplier from skipping raids or incorrectly spawning nine cycles of enemies at once.
- Services must stop reading one ambiguous `TimeService:GetDayNumber()` for both jobs. Add explicit `GetCycleIndex()` and `GetDisplayedDay()` methods/signals.

### 4.1.3 Runtime State Must Reset Per Run

Move these out of persistent profile ownership:

- Wood/Scrap/food/Bandages/keys and pickup order
- Hunger/health/downed/eliminated state
- Campfire fuel, level, and progress
- Bench tier and recipe caps
- Placed structures/crops/traps
- Children/caves/keys/tents/waypoint
- Displayed day, CycleIndex, raid state, and run statistics

Long-term profiles retain only:

```lua
{
    DataVersion = 2,
    Records = {
        HighestDay = 0,
        FastestDay67Seconds = nil,
        Wins = 0,
        ChildrenRescued = 0,
        TreesChopped = 0,
        WolvesKilled = 0,
        CultistsKilled = 0,
        Revives = 0,
        TotalPlaytime = 0,
    },
    Unlocks = {},
    Settings = {
        ReducedMotion = false,
        MusicVolume = 0.7,
        SfxVolume = 1,
    },
    Internal = {
        LastAppliedRunId = nil,
    },
}
```

Migration must preserve legitimate lifetime values, discard old saved run resources/base/rescue/campfire state, set `DataVersion = 2`, and never reward a player for stale test Wood or 300 Health.

### 4.1.4 Exact Respawn Rules

Set `Players.CharacterAutoLoads = false` on the server.

| Situation              | Character behavior                                            |
| ---------------------- | ------------------------------------------------------------- |
| Player joins           | `LoadCharacterAsync()` once, then place in lobby              |
| Run begins             | Reload once to clear lobby tools/UI state, then spawn at camp |
| Player is downed       | Keep the same character; no engine respawn                    |
| Player is revived      | Restore the same character and 35 Health                      |
| Player bleeds out      | Remove active control and enter teammate spectating           |
| Run ends               | `LoadCharacterAsync()` once and return to lobby               |
| Player starts next run | Reload once and spawn at the clean camp                       |

Do not issue another reload until `CharacterAppearanceLoaded` has fired for the previous one. Remember that `LoadCharacterAsync()` clears Backpack and PlayerGui; tools and runtime UI must rebuild from authoritative state after character creation.

### 4.1.5 Edge Cases

- A late joiner remains in the lobby and can join only the next run.
- A disconnect removes the carrier from a child and drops the child safely.
- A disconnected downed player cannot block the all-team-loss check.
- Host departure does not end a run while other members are active.
- Run cleanup destroys `Workspace.Runtime`, cancels all run timers, unregisters combat targets/tags, clears per-player cooldowns, and releases all Janitors.

---

## 4.2 — Loot, Resources, and Crafting Bench

### 4.2.1 Data Modules

Add frozen, pure-data modules under `src/shared/`:

- `RunConfig.luau`: timing, lifecycle, multiplier, life-state, and global caps.
- `RecipeConfig.luau`: recipe costs, tier, cap, output kind, and output ID.
- `StructureConfig.luau`: model path, footprint, placement rules, health, and behavior.
- `RescueConfig.luau`: cave/child/guard/key/tent definitions.
- `AssetCatalog.luau`: owned animation/audio/image/model references and fallbacks.

Services read these modules. Controllers may read only client-safe display fields; the server independently calculates costs, caps, and outcomes.

### 4.2.2 Minimum Run Economy

| Resource               | Source                               | Purpose                                       |
| ---------------------- | ------------------------------------ | --------------------------------------------- |
| Wood                   | Existing tree/log loop               | Fuel and wood structures                      |
| Scrap                  | One-open-per-run chests at landmarks | Bench upgrades, utility, traps, Bandages      |
| Berries/Mushrooms/Meat | Existing forage/hunting/cooking      | Hunger and farm output                        |
| Coal                   | Chest loot using existing Coal asset | Efficient campfire fuel                       |
| Cultist Gem            | Last Cultist in a fully cleared raid | Final bed and late recipe                     |
| Bandage                | Crafted; stored as an item count     | Teammate revive                               |
| Cave Key               | Final living guard of one cave       | Unlocks only its configured cave; never saved |

`Stone` should be removed from active recipe requirements unless Phase 4 also gives it a real source. Do not keep a resource field that cannot be earned.

### 4.2.3 Landmark Chests

Add `LootService.luau` and tag chest anchors with `RunChest` plus `LootTier`.

- Reuse `basic-chest` and `Gold-chest` models.
- Place basic chests in cabins/lodges/towers and gold chests at high-risk landmarks.
- Each chest opens once per run, not once per player.
- The server picks loot from weighted tables, spawns carryable drops, sets the opened state, and broadcasts VFX/audio.
- Validate chest identity, `RunId`, distance ≤ 12 studs, alive state, unopened state, and a per-player cooldown.
- Never accept a client-provided loot table, rarity, amount, or destination.

Initial loot targets:

| Chest | Guaranteed | Weighted extras                                           |
| ----- | ---------- | --------------------------------------------------------- |
| Basic | 1–3 Scrap  | Coal, Berries, Mushroom, Raw Meat                         |
| Gold  | 4–7 Scrap  | Bandage, Coal bundle, Cooked Meat, rare Spear replacement |

### 4.2.4 Bench Interaction and Recipes

Reuse `ServerStorage.Assets.[Assets maps items].crafting-table` and place one at the main camp. Add `CraftingService` and `CraftingController`.

#### Remote Contract

- `GetBenchState() -> { tier, resources, recipeCounts }`
- `RequestCraft(recipeId: string) -> { ok, code, placementToken?, itemId? }`
- `CraftingStateChanged(snapshotDelta)`
- `CraftSucceeded(recipeId, outputKind)`

Failure codes: `INVALID_RECIPE`, `WRONG_TIER`, `CAP_REACHED`, `INSUFFICIENT_RESOURCES`, `NOT_NEAR_BENCH`, `NOT_ACTIVE`, `DOWNED`, `RATE_LIMITED`, `RUN_CHANGED`.

#### Initial Recipe Table

| Tier | Recipe        | Cost                               | Per-run cap | Output/behavior                            |
| ---- | ------------- | ---------------------------------- | ----------- | ------------------------------------------ |
| 1    | Map           | 3 Wood                             | 1           | Opens camp/map overview                    |
| 1    | Old Bed       | 20 Wood                            | 1           | Placement token; +1 multiplier once placed |
| 1    | Farm Plot     | 10 Wood                            | 8           | Placement token; grows food                |
| 1    | Log Wall      | 12 Wood                            | 24          | Placement token; raid defense              |
| 1    | Bench Tier 2  | 5 Wood + 1 Scrap                   | 1           | Upgrades bench atomically                  |
| 2    | Compass       | 3 Scrap                            | 1           | Persistent rescue/camp direction HUD       |
| 2    | Regular Bed   | 5 Scrap                            | 1           | Placement token; +1 multiplier once placed |
| 2    | Log Gate      | 10 Wood + 2 Scrap                  | 4           | Placement token; toggled camp entrance     |
| 2    | Bear Trap     | 3 Scrap                            | 10          | Placement token; one successful trigger    |
| 2    | Storage Crate | 5 Wood + 2 Scrap                   | 4           | Placement token; shared run storage        |
| 2    | Bandage       | 2 Scrap                            | Unlimited   | Adds one revive item                       |
| 2    | Bench Tier 3  | 15 Wood + 15 Scrap                 | 1           | Upgrades bench atomically                  |
| 3    | Good Bed      | 20 Wood + 10 Scrap                 | 1           | Placement token; +1 multiplier once placed |
| 3    | Giant Bed     | 30 Wood + 20 Scrap + 1 Cultist Gem | 1           | Placement token; +1 multiplier once placed |

Crafting is atomic: validate live run and recipe, recompute owned resources, enforce the cap, deduct exactly once, create the server placement token/item, then broadcast deltas. A failed transaction deducts nothing.

### 4.2.5 Navigation and Shared Storage

**Map:** `MapController` renders a lightweight 2D panel rather than cloning the 8,000-part world into a ViewportFrame. Convert configured landmark/cave/camp world X/Z coordinates into normalized positions using the Base-map ground bounds. Undiscovered cave markers stay hidden; revealed caves, camp, selected waypoint, and living/downed teammates use icons plus text/tooltips. Keyboard uses `M`, gamepad uses a bound action, and touch uses a persistent map button.

**Compass:** Show a top-center cardinal strip calculated locally from camera yaw. The server supplies only authorized camp/selected-cave marker positions. The strip displays camp direction at all times and the selected rescue direction after the Compass recipe is crafted.

**Storage Crate:** Store shared run resource counts, not arbitrary Instances or tools. Capacity is 200 total units. Add `GetStorageSnapshot()`, `RequestDeposit(resourceName, amount)`, and `RequestWithdraw(resourceName, amount)`. Validate allow-listed resource, positive integer amount, distance, alive state, personal ownership/capacity, crate RunId, and rate limit; mutate personal and shared counts atomically. Cave keys and placement tokens cannot be stored.

---

## 4.3 — Server-Validated Building and Placement

### 4.3.1 Architecture

Add:

- `BuildingService.luau`: placement tokens, authoritative placement, structures, health, gates, traps, crops, cleanup.
- `BuildingController.luau`: local preview, input, accessible controls, and feedback.
- `Workspace.Runtime.Structures`: all live authoritative structures for the current run.

A crafted placeable grants a random one-use placement token stored only on the server. The client receives its opaque token ID and structure display data.

### 4.3.2 Client Preview

- Clone a non-colliding local ghost from a client-safe preview model.
- Raycast from pointer/camera to valid ground.
- Snap X/Z to a 2-stud grid and yaw to 15-degree increments.
- Render green when the local fast check passes and red when it fails.
- Show the footprint, structure name, rotate control, place control, and cancel/refund warning.
- Keyboard/mouse: move with pointer, `R/Q` rotate, left-click place, right-click/Escape cancel.
- Gamepad: reticle placement, shoulder buttons rotate, confirm/cancel face buttons.
- Touch: reticle or tap position plus visible Rotate, Place, and Cancel buttons outside safe-area insets.

Local validity is feedback only. It cannot place or spend resources.

### 4.3.3 Authoritative Placement Request

`RequestPlace(tokenId: string, requestedCFrame: CFrame)` must validate:

1. `tokenId` is a live unspent token owned by the requesting player and current `RunId`.
2. `requestedCFrame` is a CFrame with finite components.
3. Player is alive, active, and within 35 studs of the requested pivot.
4. Server recomputes 2-stud grid snap and 15-degree yaw; it never accepts client precision.
5. Pivot and full configured footprint are inside the camp build zone.
6. A server ray finds valid ground and slope is within the structure's limit.
7. `Workspace:GetPartBoundsInBox()` with an overlap filter finds no blocked geometry, players, campfire, cave, or existing structure.
8. Per-structure and total structure caps are not exceeded.
9. Rate limit and run token remain valid.

Only then clone the authoritative template, set attributes, parent to `Workspace.Runtime.Structures`, consume the token, and broadcast placement VFX. A rejected request keeps the token so the player can reposition.

### 4.3.4 Structure Records

Every structure receives:

- `StructureId`: GUID
- `StructureType`: recipe output ID
- `OwnerUserId`
- `RunId`
- `MaxHealth` and current `Health`
- `PlacedCycle`
- behavior-specific attributes such as `Armed`, `Open`, or `ReadyCycle`

### 4.3.5 Functional Behaviors

| Structure     | Required behavior                                                                                          |
| ------------- | ---------------------------------------------------------------------------------------------------------- |
| Log Wall      | Blocks NPC pathing; raid attacks damage it; destroyed at 0 Health                                          |
| Log Gate      | Same defense; nearby alive player can toggle; tweened but server collision state is authoritative          |
| Bear Trap     | Arms after placement, triggers once on a registered hostile, applies configured stun/damage, then destroys |
| Farm Plot     | Produces two Berries every two real `CycleIndex` dawns; ready state is visible and server-collected        |
| Storage Crate | Shared run storage with server-owned slots; rejects over-capacity or stale transfers                       |
| Beds          | Indestructible by normal animals; each unique bed contributes once while validly placed                    |

NPC services must treat structures as obstacles/targets without letting a client choose damage. Raid cultists may attack the nearest blocking defense before continuing to camp.

---

## 4.4 — Beds and the 1x–9x Day Multiplier

The current roadmap's “interact with a bed to skip” behavior is replaced. In the reference loop, built beds and rescued children continuously increase how many displayed days pass after each survived night.

### 4.4.1 Four Bed Variants

Create templates under `ServerStorage.Assets.[Assets Items].Beds`:

| Bed         | Source                           | Visual distinction                                   |
| ----------- | -------------------------------- | ---------------------------------------------------- |
| Old Bed     | Existing `Bed`                   | Rough wood, thin neutral bedding                     |
| Regular Bed | Existing lodge bedroll + frame   | Cleaner frame, green/blue bedding                    |
| Good Bed    | Existing `Bed` variant           | Taller frame, blanket/pillow, warm material          |
| Giant Bed   | Scaled/rebuilt existing geometry | Wider silhouette, reinforced posts, late-tier accent |

Do not use random Creator Store bed models. All variants must have normalized pivots, one `PlacementFootprint` attribute/config, anchored static parts, no scripts, and a consistent low-poly style.

### 4.4.2 Multiplier Formula

```text
multiplier = clamp(1 + uniquePlacedBeds + rescuedChildren, 1, 9)
```

- Duplicate/replaced copies never stack beyond each recipe's one-per-run cap.
- A bed contributes after successful authoritative placement.
- A child contributes after entering the lit safe zone and finalizing rescue.
- At dawn: `DisplayedDay = min(67, DisplayedDay + multiplier)` and `CycleIndex += 1`.
- Broadcast one `DawnAdvanced` payload: previous day, new day, multiplier, bed count, child count, crossed milestones.
- If the result reaches 67, transition to `Ending` before another AI/raid cycle starts.
- The Day 67 reward and result save use an idempotency key of `RunId + endingType`.

### 4.4.3 HUD

The day HUD must show both readable progression and cause:

- `DAY 28 / 67`
- `+6 at dawn`
- Expandable breakdown: `Base +1`, `Beds +2`, `Children +3`
- A short dawn animation from old day to new day; Reduced Motion replaces it with an instant text update.

---

## 4.5 — Four Guarded Caves and Child Rescues

### 4.5.1 Rescue Configuration

Use a single frozen table; services must not contain per-child branches.

| Child ID | Rig source                          | Cave theme  | Required campfire | Guard pack     | Key    | Tent accent        |
| -------- | ----------------------------------- | ----------- | ----------------: | -------------- | ------ | ------------------ |
| `Dino`   | Existing Dino Kid                   | Red         |                 2 | 5 Wolves       | Red    | Rescue-order color |
| `Kraken` | Existing Kraken Kid                 | Blue        |                 3 | 4 Alpha Wolves | Blue   | Rescue-order color |
| `Squid`  | Re-outfitted Dino/Kraken R6 variant | Yellow      |                 4 | 2 Bears        | Yellow | Rescue-order color |
| `Koala`  | Re-outfitted Dino/Kraken R6 variant | Gray/purple |                 5 | 6 Bears        | Gray   | Rescue-order color |

Tent colors are assigned by rescue order: red, blue, yellow, purple. Child identity and tent order are stored separately.

### 4.5.2 Cave Construction

- Import the **Kenney Modular Cave Kit** and build four compact caves from shared modules.
- Use one entrance, short tunnel, guarded clearing, colored gate, and child room per cave.
- Keep cave art forest-compatible; do not use the snow-themed Ice Temple.
- Author fixed cave transforms in Studio outside the maximum camp safe-zone radius.
- Add `CaveId`, `RequiredCampfireLevel`, `GuardSpawn` markers, `KeySpawn`, `Gate`, `ChildSpawn`, and `Exit` attributes/parts.
- Disable collision on decorative rocks; use Box/Hull collision for walkable modules; anchor static geometry.
- Test all caves with StreamingEnabled and pathfinding from entrance to guard arena.

### 4.5.3 Cave Availability

- A cave remains hidden/locked until the shared campfire reaches its configured level.
- On unlock, reveal its distant marker/region and update the poster board.
- Unlock is idempotent and run-owned; a reconnecting client receives the current cave snapshot.
- Campfire level loss/fuel outage does not re-lock an already revealed cave, but the board waypoint requires the campfire to be lit.

### 4.5.4 Guard Packs and Keys

`RescueService` requests guards from `AnimalAIService` with `GuardCaveId` and a bounded territory.

- Guards spawn once when the cave activates or first becomes relevant.
- They cannot join normal population counts or despawn at dawn.
- They leash to the cave arena and prioritize nearby active players.
- The service tracks registered guard instances, not names or client reports.
- Only when every registered guard is confirmed dead does the final death spawn one server-owned key.
- Key carries `CaveId`, `RunId`, and `KeyColor`; it unlocks only the matching live gate.
- Gate unlock validates key ownership/carry state, range, cave state, and run token; it consumes the key once and tween-opens the gate.

### 4.5.5 Child Variants

- Use Dino and Kraken as the topology/rig standard; all four remain compatible R6 rigs.
- Strip scripts and unneeded effects from duplicated rigs.
- Squid: yellow/blue clothing palette and a simple Studio-authored rounded tentacle-cap silhouette.
- Koala: charcoal/purple palette and a simple rounded-ear cap silhouette.
- Do not copy wiki images, clothing textures, or third-party branded accessories.
- Give each child a unique face treatment, name, cave palette, and tent nameplate so the variants are readable even without color.

### 4.5.6 Child State Machine

```text
Locked → Available → Carried ↔ Dropped → Rescued
```

Rules:

- The server chooses the child record from the interacted instance; the client never sends an arbitrary child reward.
- Pickup requires gate unlocked, player alive, not downed, empty hands, within 10 studs, no current carrier, and a cooldown.
- Carry uses a server-created attachment/weld or constrained follow position that does not grant network authority over rescue state.
- Carrier cannot equip Axe/Spear, drag other items, build, or sprint at full speed.
- Manual drop places the child on validated nearby ground.
- Downing, elimination, disconnect, teleport, or leaving the run drops the child and clears carrier state.
- Another player may pick up a dropped child.
- Entering the **lit** camp safe zone finalizes rescue once. An unlit campfire does not complete rescue.

### 4.5.7 Rescue Completion

On first valid safe-zone entry:

1. Transition the child to `Rescued` atomically.
2. Clear carrier state and disable future pickup.
3. Increment child multiplier contribution.
4. Allocate the next rescue-order tent color.
5. Place the child/tent at a free camp-perimeter slot outside structure footprints.
6. Play rescue VFX/audio and a short result banner.
7. Update board poster state from `Missing` to `Rescued`.
8. Clear/reselect waypoints for all players.
9. Increment run rescues; defer lifetime record mutation until results save.

### 4.5.8 Poster Board and Waypoint

Reuse a Base-map Hunters Lodge `Poster` part or mirror the lobby `Poster` at camp.

- A SurfaceGui shows four generated portrait ViewportFrames, names, cave color icon, and Missing/Located/Rescued status.
- Interacting asks the server for the nearest currently available unrescued child.
- If Compass is not crafted, show a temporary cardinal-direction clue.
- If Compass is crafted, show a persistent screen-edge arrow and distance until target changes, rescue completes, or campfire goes out.
- Server returns a configured cave marker, not the child's live exact CFrame.
- Touch/gamepad users get the same board interaction and an accessible waypoint dismiss/reselect action.

---

## 4.6 — Downed, Revive, Elimination, Spectating, and Loss

### 4.6.1 Central Damage Boundary

Add `PlayerLifeService.luau`. All player damage sources must route through:

```lua
PlayerLifeService:ApplyDamage(player, amount, source): DamageResult
```

Refactor animal attacks, Deer/Ram/Owl contact, starvation, and future hazards to use it. Direct `Humanoid:TakeDamage()` outside this boundary would bypass downing and is not allowed.

### 4.6.2 Life State Machine

```text
Alive → Downed → Alive (revived)
                 ↘ Eliminated → Lobby (after run)
```

`Alive → Downed` occurs when validated damage would reduce Health to zero.

On down:

- Keep Health at a protected minimum and set authoritative `LifeState = Downed`.
- Set `Humanoid.BreakJointsOnDeath = false` before combat begins.
- Disable weapon, carry, pickup, build, craft, and child interactions.
- Drop a carried child/item.
- Reduce movement to crawl or immobilize based on the final animation.
- Show a 45-second server-synchronized bleed-out timer.
- Create a revive prompt visible to living teammates.
- Fire a team alert with the downed player's position.

### 4.6.3 Revive

- Reviver must be Alive, in the same current run, within prompt range, and own at least one Bandage.
- Use a five-second hold. Movement out of range, reviver damage/down, target elimination, or run change cancels it.
- Revalidate every condition after the hold/yield.
- Consume one Bandage only on successful completion.
- Clear Downed restrictions, restore 35 Health, grant a short configurable damage grace period, increment run revives, and play feedback.
- A player cannot revive themselves.
- Multiple simultaneous attempts resolve once; losing attempts consume nothing.

### 4.6.4 Elimination and Spectating

When bleed-out reaches zero:

- Set `LifeState = Eliminated` once.
- Remove the character from active combat/pathfinding targets and stop all owned interactions.
- Do **not** call `LoadCharacterAsync()`.
- Move the client camera to a living teammate with next/previous controls.
- If no living teammate exists, show the run-loss transition.
- Eliminated players remain spectators until the run ends.

### 4.6.5 Team Loss

End the run when no member can continue:

- All members are Eliminated; or
- All remaining members are Downed and their bleed-out resolution leaves no valid reviver.

Loss payload:

```lua
{
    reason = "ALL_PLAYERS_LOST" | "CAMP_FAILURE" | "SERVER_ABORT",
    displayedDay = number,
    cycleIndex = number,
    elapsedSeconds = number,
    childrenRescued = number,
    structuresBuilt = number,
    kills = table,
    revives = number,
    downs = number,
}
```

A dark results screen must distinguish an ordinary defeat from a technical abort. Do not award best-run/win records for a server abort.

---

## 4.7 — Day 67 Win, Ending, Results, and Replay

### 4.7.1 Ending Trigger

When dawn progression reaches 67:

1. `RunStateService` atomically changes `Active → Ending`.
2. Reject new attack/craft/place/pickup/rescue requests with `RUN_ENDING`.
3. Pause `TimeService`, AI decisions, campfire drain, hunger drain, raids, and new spawns.
4. Resolve/park active NPCs without awarding duplicate loot.
5. Capture final statistics before cleanup.
6. Play the ending once for all members.

### 4.7.2 Ending Presentation

- Fade from the final dawn to a controlled camera around the camp.
- Show rescued children/tents and player-built defenses where they actually stand.
- Position the Deer at a distant tree line, play an owned retreat/scared animation, and have it disappear into fog. The Deer is never killed.
- Display `DAY 67 SURVIVED` and elapsed run time.
- Reduced Motion uses fades and fixed cameras instead of moving camera paths.
- Players may skip only after the title reveal; one player cannot skip other players' results.

### 4.7.3 Results

Show:

- Result: Victory/Defeat
- Displayed Day and real cycles survived
- Total run time
- Final multiplier and bed/child breakdown
- Children rescued with order/tent colors
- Structures built and defenses lost
- Trees chopped
- Wolves, Alpha Wolves, Bears, Cultists killed
- Revives and downs
- Personal best indicators

### 4.7.4 Idempotent Record Save

Use one results transaction per player keyed by `RunId` in server memory. Update:

- Highest Day
- Wins
- Fastest Day 67 time when lower
- Lifetime children rescued
- Lifetime trees/kills/revives/playtime

A retry may repeat the ProfileService mutation only if the same `RunId` has not already been applied. Never save structures, keys, resources, children, cave state, bench tier, or campfire state.

### 4.7.5 Return to Lobby and Replay

- After results acknowledgement/timeout, transition `Ending → Ended`.
- Destroy all run-owned instances and cleanup owners.
- Clear runtime tables and verify combat/CollectionService registries contain no old run instances.
- Call `LoadCharacterAsync()` once per connected member and place them in the lobby.
- Re-enable lobby UI only after client controllers bind to the new character.
- A new party starts with Day 1, 1x, Level 1 campfire, Tier 1 bench, no rescues, no structures, and empty run inventory.

---

## 4.8 — Animation, VFX, Audio, UI, and Accessibility

### 4.8.1 Animation Inventory and Ownership

The place contains useful source KeyframeSequences for Deer, Cultists, Wolf, Alpha Wolf, Bear, Bunny, and Axe. Phase 4 must stop treating all custom animals as if no authored motion exists.

Required process:

1. Preview every existing sequence on its actual rig.
2. Repair root movement, loop seams, priorities, and markers in Roblox Animation Editor.
3. Publish final clips under the user/group that owns place `84560195693908`.
4. Record IDs in `AssetCatalog.luau` with rig and purpose.
5. Verify in a published private server; Studio-only registered hashes are not sufficient release proof.
6. Keep procedural gait only as a tested fallback when an owned clip fails.

Additional clips required:

| Rig        | Clip                | Priority/markers                |
| ---------- | ------------------- | ------------------------------- |
| Child R6   | Cower/cry idle      | Looped Idle                     |
| Child R6   | Carried/follow pose | Looped Movement/Action          |
| Child R6   | Tent sit            | Looped Idle                     |
| Player R15 | Hammer/place        | Action; `PlaceImpact` marker    |
| Player R15 | Downed/crawl        | Looped Action                   |
| Player R15 | Revive assist       | Action; `ReviveComplete` marker |
| Deer rig   | Ending retreat      | Action/Movement                 |

Do not depend on newly discovered public animation IDs without ownership/permission verification.

### 4.8.2 Code-Driven VFX

Use built-in particle textures, Beam, Trail, Highlight, TweenService, and Debris/Janitor. Every temporary emitter has Rate 0 and uses `:Emit()`; every anchor has a fixed lifetime.

| Event             | VFX                                                             |
| ----------------- | --------------------------------------------------------------- |
| Craft success     | Small sawdust/spark burst at bench; recipe icon pop             |
| Valid placement   | Ground dust ring and fast materialize tween                     |
| Invalid placement | Red footprint pulse; no world effect                            |
| Gate unlock       | Key-color flash, lock fracture particles, gate dust             |
| Cave available    | Distant colored beacon visible through fog briefly              |
| Child pickup      | Soft outline and carry icon                                     |
| Rescue completion | Safe-zone light pulse, tent-color ribbon particles, board stamp |
| Downed            | Local desaturation/vignette and teammate marker                 |
| Revive            | Warm radial pulse and health-color particles                    |
| Day 67            | Dawn fog/light transition and restrained camp embers            |

Reduced Motion removes camera shake, large screen pulses, and moving UI while retaining readable color/icon feedback.

### 4.8.3 Curated Free Audio Candidates

These candidates were found in the current Creator Store and must be previewed before use:

| Use                 | Asset                     | Creator/source                                                        |
| ------------------- | ------------------------- | --------------------------------------------------------------------- |
| Night insects       | `rbxassetid://9112810051` | ProSoundEffects, “Jungle Insects 2 (SFX)”                             |
| Horror forest layer | `rbxassetid://9114244841` | ProSoundEffects, “Electric Forest Airy Washy Shrieky 3 (SFX)”         |
| Cave drip loop      | `rbxassetid://9120505513` | ProSoundEffects, “Water Cave Trickle Very Thin 3 (SFX)”               |
| Night/ending whoosh | `rbxassetid://9120698420` | ProSoundEffects, “Whoosh By Howling Wind Light Rumbling 10 (SFX)”     |
| Craft/build impact  | `rbxassetid://9120188626` | ProSoundEffects, “Toolbox Impact Wood Metal Hits Fall Crash 11 (SFX)” |

Audio acceptance:

- Confirm Creator Store permission in the published experience.
- Normalize relative volume; ambience must not mask Deer/Owl/raid warnings.
- Crossfade day/night layers instead of starting duplicates.
- Cave audio is spatial and streams only near each cave.
- Store all IDs/fallbacks in `AssetCatalog`; no ID is scattered across controllers.
- If an ID fails moderation/permission, replace it with another official ProSoundEffects/APMOfficial asset, not an unknown reupload.

### 4.8.4 UI Deliverables

- Crafting menu: tier tabs, resource costs, caps, locked reason, input hints.
- Placement HUD: item name, validity reason, rotate/place/cancel controls.
- Day/multiplier HUD: Day X/67, dawn gain, breakdown.
- Missing board: four ViewportFrame portraits and statuses.
- Waypoint: cardinal arrow/distance with accessible text alternative.
- Child carry HUD: child name and Drop action.
- Downed HUD: bleed-out timer, teammate distances, revive progress.
- Spectator HUD: observed player, next/previous, run status.
- Ending/results: victory/defeat summary and return/replay state.

Requirements:

- Respect topbar/safe-area insets and use scale/constraints for phones/tablets.
- Use `GuiService.SelectedObject` navigation and visible focus states for gamepad.
- Do not make hover, right-click, `F`, or precise pointer movement the only required path.
- Text remains readable at Roblox text scaling; status is never communicated by color alone.
- Disable gameplay controls while crafting/results menus own focus.
- All runtime connections and created ScreenGuis belong to a controller Janitor.

### 4.8.5 Intro and Poster Art

`IntroAssets` currently has empty title/story image slots.

Preferred no-upload fallback:

- Keep the procedural Deer silhouette for title/waiting screens.
- Render child/poster visuals with ViewportFrames using the owned rigs.
- Render police tape/gate/player story panels as original Studio scenes captured by the owner.

Optional owner-supplied original images may replace these slots. Do not copy screenshots, wiki art, game thumbnails, or the reference game's exact UI.

---

## 4.9 — Asset Acquisition, Import, and Sanitization

### 4.9.1 Approved Free/CC0 Sources

| Source                    | URL                                                 | Intended use                                                                      |
| ------------------------- | --------------------------------------------------- | --------------------------------------------------------------------------------- |
| Kenney Survival Kit (CC0) | `https://poly.pizza/bundle/Survival-Kit-yGnSPFp2lH` | Small survival props and visual reference if current assets cannot cover a recipe |
| Kenney Modular Cave Kit   | `https://kenney.nl/assets/modular-cave-kit`         | Four cave entrances/interiors                                                     |
| Kenney Tent (CC0)         | `https://poly.pizza/m/LrTs3hVGXv`                   | Rescue tents if a Studio-built tent is not sufficient                             |
| Wood Tent 2 (CC0)         | `https://poly.pizza/m/QQ9MNNWvpf`                   | Alternate tent only after style/performance review                                |
| Roblox Creator Store      | Audio IDs in §4.8.3                                 | Ambience and interaction sound                                                    |

Keep the license/readme from every downloaded pack in the local asset source archive. Confirm the license at download time; a search-result summary alone is not a permanent license record.

### 4.9.2 Import Checklist

For each FBX/OBJ/GLTF asset:

1. Download from the approved source and archive its license/readme.
2. Import through Studio's 3D Importer into a temporary inspection folder.
3. Inspect triangle/vertex/texture counts and split or decimate oversized meshes before production use.
4. Reduce textures to the smallest resolution that preserves the low-poly art direction.
5. Normalize scale, orientation, pivot, names, and PrimaryPart.
6. Anchor static cave/tent geometry.
7. Use Box collision for decorative props and Hull/Precise only where player navigation requires it.
8. Disable shadows on tiny decorations and interior pieces with no visible shadow contribution.
9. Delete every Script, LocalScript, ModuleScript, RemoteEvent, RemoteFunction, Bindable, unwanted Sound, and hidden package link.
10. Inspect constraints, attachments, attributes, collision groups, and network ownership assumptions.
11. Place the sanitized template under the correct `ServerStorage.Assets` catalog folder.
12. Test edit mode, solo runtime, two clients, and StreamingEnabled before using it in configuration.

### 4.9.3 Rejected Asset Strategy

Do not use generic Creator Store “99 Nights kit,” child NPC, dungeon, or bed models as production dependencies merely because they are free or recently uploaded. Search results are heavily keyword-spammed, often contain scripts, have inconsistent provenance, and produce a visibly copied/low-quality game. Existing place assets plus reputable CC0 geometry are safer, more coherent, and easier to maintain.

---

## 4.10 — Exact Inputs Needed from the Owner

Phase 4 coding can proceed with procedural placeholders, but final release requires these owner actions because assets live in the `.rbxlx` and cloud ownership cannot be solved by filesystem Luau alone.

### Required

- [ ] Approve the final Squid and Koala clothing palettes and simple accessory silhouettes.
- [ ] Download/import the selected Kenney cave kit and preserve its license file.
- [ ] Approve whether rescue tents use the Kenney Tent or a Studio-built primitive tent.
- [ ] Publish repaired/new animations under the same user/group that owns the experience and record the IDs.
- [ ] Preview and approve the five audio candidates in §4.8.3; confirm they play in a published private server.
- [ ] Save and transfer the updated `.rbxlx` whenever assets change; Rojo does not version `ServerStorage.Assets` or map geometry.

### Optional but Recommended for the Best Presentation

- [ ] Four original story images: Deer sighting, four missing children, locked forest/police tape, survivors entering the forest.
- [ ] One original game icon and two thumbnails using this game's own Day-67 identity.
- [ ] Final logo/title treatment and font direction.
- [ ] A target low-end phone/tablet model and minimum acceptable frame rate for release profiling.

If original images are not supplied, use the procedural silhouette and Studio ViewportFrames. The implementation must not block on external art.

---

## 4.11 — Security, Performance, and Cleanup Contract

### 4.11.1 Remote Validation Matrix

| Request         | Server validation                                                                         |
| --------------- | ----------------------------------------------------------------------------------------- |
| Open chest      | Live tagged chest, current RunId, unopened, distance, alive, cooldown                     |
| Craft           | Recipe allow-list, bench tier, near bench, alive, resources, cap, cooldown, atomic deduct |
| Place           | Owned live token, finite CFrame, server snap, range, zone, slope, overlap, cap, cooldown  |
| Toggle gate     | Tagged current-run gate, distance, alive, cooldown                                        |
| Collect crop    | Ready current-run plot, distance, alive, capacity, one atomic harvest                     |
| Open board      | Correct board, distance, active run, campfire lit, cooldown                               |
| Pick/drop child | Configured child, valid state, distance, empty hands/carrier ownership, alive, cooldown   |
| Unlock cave     | Matching server key/cave, gate locked, distance, current run, consume once                |
| Revive          | Same-run downed target, living reviver, Bandage, range before/after hold, one resolution  |
| Return/replay   | Run in allowed phase, member identity, one transition                                     |

General rules:

- Type-check every argument and reject NaN/infinite numbers.
- Recheck player/instance/run liveness after every yield.
- Never accept client damage, resource amount, recipe cost, loot roll, rescue reward, multiplier, or result.
- Rate-limit per action/player and clear cooldowns on run cleanup/player departure.
- Return stable failure codes, not internal stack traces.

### 4.11.2 Performance Budgets

- Maximum 48 placed defenses/furniture, 8 farms, 10 active traps, 4 caves, and configured NPC caps per run.
- No four-copy Ice Temple or similarly dense cave model.
- AI decisions remain throttled and stop for dormant/streamed-out entities.
- Use CollectionService/tag signals, not recurring full DataModel scans.
- No table/closure/string allocation in per-frame loops when state can be reused.
- Send state deltas for inventory, structures, rescue, and multiplier; use snapshots only on join/reconnect.
- Pool or short-lifetime cleanup VFX; do not replicate cosmetic client-only particles from the server when unnecessary.
- Static imported parts remain anchored; decorative collision and shadows are disabled.

### 4.11.3 Cleanup Ownership

Every run-created object belongs to one of:

- Run Janitor
- Per-player run Janitor
- Per-structure Janitor
- Per-cave/rescue Janitor
- Per-controller character/UI Janitor

A second run must not increase baseline active connections, tagged old instances, repeating tasks, or ambience loops.

---

## 4.12 — Ordered Acceptance Gates

Do not mark Phase 4 complete because files exist. Complete each gate through observable playtests.

### Gate A — Phase 1–3 Production Regression

- All test flags are off in published behavior.
- Health is 100; Wood is finite; lobby/intro is reachable.
- Day/night, hunger, campfire, forage, cooking, inventory, animals, stalkers, combat, and raids work in solo and two-client tests.
- No high-frequency debug spam or related console errors.

### Gate B — Clean Run Lifecycle

- Start Run A, change resources/camp/structures, end it, and start Run B.
- Run B begins at Day 1, Cycle 1, 1x, Tier 1, empty run inventory, no structures/rescues/keys.
- No old timers, NPCs, tags, UI, audio, or connections affect Run B.
- Downed/eliminated players never auto-respawn into the forest.

### Gate C — Economy, Crafting, and Placement

- Every loot source opens once and drops only server-selected valid items.
- Every recipe succeeds with exact resources and fails atomically without them.
- Bench upgrades unlock only their tier.
- Placement accepts valid ground and rejects outside-zone, too-far, overlapping, steep, NaN, stale-token, duplicate-token, and over-cap requests.
- Wall, gate, trap, farm, storage, and all beds perform their configured behavior.

### Gate D — Four Rescue Arcs

For each cave:

- It appears only at the configured campfire level.
- Correct guard count/type spawns once and remains cave-bound.
- Gate cannot open before all guards die and matching key is present.
- Last guard produces one key; duplicate death callbacks produce none.
- Child can be carried/dropped/transferred and drops safely on down/disconnect.
- Lit safe-zone entry rescues once; unlit camp entry does not.
- Tent/order, board, waypoint, multiplier, and result stats update correctly.

### Gate E — Multiplier and Event Cadence

Test every contribution from 1x through 9x.

- Four unique beds add exactly four total.
- Four children add exactly four total.
- Duplicate placement/rescue/reconnect signals do not stack.
- Displayed Day advances by multiplier and clamps at 67.
- CycleIndex advances by one.
- Raids still occur every four real cycles and are never skipped by displayed-day jumps.
- Day 67 ending fires once even if the final increment crosses beyond 67.

### Gate F — Downed and Revive

- Lethal NPC, stalker, raid, and starvation damage all enter Downed.
- Down disables forbidden actions and drops carried child/item.
- Valid teammate Bandage revive succeeds after five seconds and restores 35 Health.
- Cancelled/competing/invalid attempts consume nothing.
- Bleed-out eliminates and starts spectating without character reload.
- Solo loss and all-team loss trigger exactly once.

### Gate G — Ending, Save, and Replay

- Day 67 locks gameplay, pauses threats, plays the ending, and shows complete results.
- Records update exactly once per RunId.
- Rejoining does not restore run resources/camp/rescues.
- Return-to-lobby character reload occurs once and all UI/tools rebuild.
- Replay starts clean and can reach gameplay again.

### Gate H — Platform, Network, and Long-Session QA

- Keyboard/mouse, touch emulator, and gamepad can complete every essential interaction.
- Test solo, two clients, and five clients where available.
- Test high latency, client disconnect while carrying/downed/reviving/placing, and late join.
- Attempt forged recipe IDs, costs, CFrames, child IDs, keys, revive targets, damage, and multiplier payloads; all fail safely.
- Test StreamingEnabled at every cave, landmark, camp edge, and spectator target.
- Run at least three complete accelerated test runs in one server and compare instance/connection/audio/animation memory baselines.
- Capture MicroProfiler/SceneAnalysis data at camp during a raid and at the six-bear cave.

### Release Criteria

- Zero Phase 4-related errors in a full multiplayer run.
- No permission failures for owned animations or approved audio in a published private server.
- No duplicate UI, input, ambience, timer, or remote listener after replay.
- No stale run instance remains tagged/registered after cleanup.
- Stable memory/instance counts across repeated runs.
- Acceptable frame time on the owner-selected low-end target device.
- All required owner asset actions in §4.10 are complete or replaced by the documented procedural fallback.

---

## Finished Game — What Players Experience

- Enter a deliberate lobby/party flow and begin a completely fresh Day-67 expedition.
- Spend daylight gathering, hunting, looting landmarks, upgrading the fire, and crafting a defensible camp.
- Build walls, gates, traps, farms, storage, and four progressively valuable beds with tactile cross-platform placement.
- Survive predators, the Deer/Ram/Owl, and recurring Cultist raids without test advantages.
- Reveal four colored caves through campfire progression, defeat distinct guard packs, recover matching keys, and carry Dino, Kraken, Squid, and Koala home.
- Watch the Missing board and camp fill with rescued children/tents while the day multiplier grows from 1x to 9x.
- Rescue downed teammates with Bandages; eliminated players spectate instead of silently respawning.
- Reach Day 67, watch the Deer retreat at dawn, review meaningful run statistics, and return to the lobby with lifetime records but no carried-over camp advantage.

---

## Future Expansion After Phase 4

The architecture should remain data-driven enough to add these later without rewriting the production run:

- Classes and permanent unlock economy
- Pelt Trader and animal pelts
- Firearms/ammunition and advanced healing
- Additional crafting tiers and processors
- Weather and campfire weather resistance
- Snow, volcanic, jungle, or event biomes
- More entities and bosses
- Endless post-67 mode, modifiers, badges, and monetization

None of these are Phase 4 completion dependencies.
