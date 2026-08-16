# 67 Nights — 4-Phase Execution Roadmap

Each phase ends with a playable, observable milestone. "What you'll see" describes actual in-Studio/in-play behavior, not code internals. Reference source for authenticity: the original **99 Nights in the Forest** (Grandma's Favorite Games) — fandom wiki, official site, and PCGamer tips guide, cross-checked against our own asset inventory so nothing below asks for content we don't have (no biomes, no 23-class shop, no snow/volcano — those are out of scope; see Notes).

---

## Progress Audit (as of this revision)

Live check of `src/server/Services`, `src/Client/Controllers`, and `ProfileTemplate.luau` against the old roadmap:

| Old phase item                                                                                   | Status          | Evidence                                                                                                                                                                |
| ------------------------------------------------------------------------------------------------ | --------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Wally packages, `WorldService` map placement, `PlayerDataService`, `TimeService`, `SpawnService` | **Done**        | Services exist and are wired into `Server.server.luau`; `Base-map`/`lobby-map` are live in `Workspace`                                                                  |
| `HudController` day/night labels                                                                 | **Done**        | `src/Client/Controllers/HudController.luau`                                                                                                                             |
| `HungerService` (decay + starvation)                                                             | **Done**        | `src/server/Services/HungerService.luau` — Heartbeat drain, sprint multiplier, starvation damage, throttled broadcast                                                   |
| `HarvestService` (tree chopping)                                                                 | **Done**        | `src/server/Services/HarvestService.luau` — ProximityPrompt chop, tree health/respawn/fell tween, Log pickups                                                           |
| `CampfireService` (fuel + fire visuals)                                                          | **Done**        | `src/server/Services/CampfireService.luau` — fuel decay, `RequestFuelCampfire`, fire/light scaling, safe-zone radius                                                    |
| `HarvestController`/`HungerController` client sync                                               | **Done**        | Both exist in `src/Client/Controllers`                                                                                                                                  |
| **Eating** (Berries/Mushrooms restoring Hunger)                                                  | **Done**        | `ForageService.RequestEat` consumes resources and restores Hunger via `HungerService:RestoreHunger`; `InventoryController` shows edible rows with click-to-eat buttons. |
| Inventory GUI showing real resource counts                                                       | **Done**        | `InventoryController` exists and builds a right-side carry-bag panel with live counts and Eat/Drop actions.                                                             |
| Animal/NPC AI (any kind)                                                                         | **Done**        | `AnimalAIService` (Bunny/Owl/Wolf/AlphaWolf/Bear), `DeerService` (Deer/Ram Monster stalkers) — see Phase 3                                                              |
| Combat, loot drops, procedural animation                                                         | **Done**        | `CombatService`, `CombatTargetRegistry`, `AnimalAIService` procedural gait, `ProceduralAnimController` — see Phase 3                                                    |
| Base building, beds, day multiplier                                                              | **Not started** | `ProfileTemplate.Base` fields exist but unused; no `BuildingService`                                                                                                    |
| Missing children rescue, caves, poster board                                                     | **Not started** | `ProfileTemplate.Rescue` fields exist but unused; no `RescueService`                                                                                                    |
| Win/loss, permadeath                                                                             | **Not started** | No such logic anywhere                                                                                                                                                  |

**Conclusion:** the old Phase 1 **and** most of the old Phase 2 (hunger, chopping, campfire) are already built and working. What remains is: closing the loop on **eating/inventory UI**, then everything from **NPC AI/combat** through **building/rescue/win-loss**. This revision folds the leftover Phase-2 sliver into the new **Phase 2** and restructures Phases 3–4 with the full depth of the reference game's core loop, scoped to our actual asset set.

---

## Phase 1 — Networking, Data, Teleport/Spawn, Day/Night Clock ✅ DONE

**Build:** Wally packages (Knit, ProfileService, ZonePlus, Janitor); `WorldService` places `Base-map`/`lobby-map` and anchors `Bonfire`; `PlayerDataService` + `ProfileTemplate`; `TimeService` day/night clock with `Lighting` tween; `SpawnService` lobby→base teleport; `HudController` day/night labels.

**What you see:** Spawn in the lobby, cross a teleporter into the populated base map, watch `DayLabel`/`NightLabel` and lighting shift on a timer. No survival mechanics yet.

---

## Phase 2 — Close the Survival Loop: Eating, Inventory UI, Camp Safety Feedback ✅ DONE

The only unfinished slice of "core survival." Everything else in this phase is UI/feedback polish on top of the already-working hunger/harvest/campfire services, plus the missing food loop that the reference game treats as a first-class resource (Berries, Mushrooms, cooked meat via campfire).

**Built:**

- `InventoryService`: centralised resource capacity system (base 40 + carry-bag bonus 40 = 80 total), `AddResource`/`ConsumeResource` API used by all other services, `ResourcesChanged` signal to client, `GetSnapshot` remote. Welds the pre-placed `carry-bag` mesh onto every player's back as a visible backpack via Motor6D (works on R15 rigs).
- `ForageService`: scatters 35 Berries (reusing `Carrot` mesh) and 25 Mushrooms near trees across the base-map, each with physical collision and picked up via the `CarryController` hover/pickup system (F key), which routes through `InventoryService:AddResource`/`ForageService:RequestPickup`. `RequestEat` remote consumes a resource and restores Hunger via `HungerService:RestoreHunger` (Berries=12, Mushrooms=10, RawMeat=15, CookedMeat=30). Respawns on a 60s timer.
- `CookingService` / `CampfireService` drop-only auto-cook: raw meat is cooked automatically when dropped onto a lit campfire. `CampfireService.scanForLogFuel` detects `RawMeat` models inside the fire radius and swaps them for CookedMeat, mirroring the reference game's drop-to-cook rule and removing the manual prompt.
- `InventoryController`: live inventory HUD panel (bottom-right) showing all 6 resources with colour-coded rows, carry-capacity readout ("Carrying X / 80"), and click-to-eat buttons on edible rows.
- `CampSafetyController`: throttled Heartbeat distance check; darkens screen via `ColorCorrectionEffect` and shows a red "You are far from the firelight..." warning when outside the safe zone at night, tweens back to normal when inside or during day.
- **Bug fixes along the way:** `CampfireService.SafeZoneChanged` signal was never actually fired (computed `lastBroadcastRadius` but never called `:Fire`) — fixed; `HungerService` gained a `RestoreHunger` method for eating; `HarvestService` wood pickup now routes through `InventoryService` for capacity enforcement instead of writing the profile directly; `WorldService` gained a `GetCampfirePosition` client remote; both server and client bootstrappers now use `pcall` per-require so one failing module can't halt the rest; `init.server.luau` debug prints cleaned up.

**What you'll see when you play:**

- A visible backpack on your character's back (the `carry-bag` mesh, welded via Motor6D).
- Berries and mushrooms scattered near trees across the map that you can pick up by hovering and pressing F (CarryController), then eat from the inventory panel (click the row) to visibly refill your hunger bar.
- Dropping raw meat onto the lit Bonfire auto-cooks it into cooked meat that restores more hunger when eaten.
- A real inventory panel in the bottom-right showing live counts of Wood/Stone/Berries/Mushrooms/RawMeat/CookedMeat with a "Carrying X / 80" capacity readout.
- Standing outside the campfire's light at night darkens your screen and shows a red warning; stepping back into the light clears it.

---

### Phase 2 — Production Readiness Notes

- **Drop-only interactions are now the default.** Both wood fueling and raw-meat cooking happen by dropping the item on/near the fire; the previous ProximityPrompt-based `Cook Meat` and forage pickup have been removed in favour of `CarryController`'s F-key hover pickup.
- **Client connection lifecycle.** Several controllers (`CampfireController`, `CampSafetyController`, `CarryController`, `InventoryService`) create `Heartbeat`/`RenderStepped` connections in `KnitStart` without storing/disconnecting them. This is fine for a single run, but Rojo hot-reloads or re-initialisation can stack duplicates. Wrap these in a `Janitor` or save the connection handle before reconnecting.
- **Scene analysis.** A runtime `SceneAnalysisService` composition check shows a healthy 17,528 total instances, 12 unparented instances (all Roblox default modules), and a small 143 KB animation cache. The `ScriptMemory` query is gated by the Roblox `STUDIOPLAT37936` fast flag and could not be read; use the MicroProfiler for per-script memory if needed before Phase 3.
- **Gate to Phase 3 is open.** All Phase 2 systems (forage, eating, inventory UI, campfire feedback, camp safety) are wired and reachable through the Knit service/controller tree. Phase 3 can start as soon as the above clean-up items are triaged.

## Phase 3 — The Forest Comes Alive: Animal AI, The Deer, Cultists, Combat ✅ DONE

The horror-survival heart of the reference game — pack predators by night, an unkillable stalking Deer that the campfire and light repel, Cultist raids on a timer, and real combat with loot.

**Built:**

- `AnimalAIService` — one generic patrol/chase/attack/flee state machine (driven by the shared `NpcConfig` data module) reused by every non-unique species: `BunnyModel` (passive, flees on proximity, drops `Berries`/`RawMeat`), `Owl` (passive, day-idle, R15-rig default idle animation, no aggro), `WolfModel`/`AlphaWolfModel` (predator packs, `PathfindingService` patrol→chase, pack size and Alpha presence scale with `TimeService:GetDayNumber()`), and `Bear` (solitary, territory-clamped, reuses its baked `Attack` animation). A persistent-population respawn check keeps Bunny/Owl/Bear headcounts topped up over long sessions; wolves/alphas spawn on Night start and despawn at dawn.
- `CombatTargetRegistry` — shared server module so `CombatService` can damage any spawned NPC (animal, stalker, or raider) generically via `CollectionService` tagging, without knowing which service owns it.
- `DeerService` — the signature threat, plus `Ram Monster` sharing the same unkillable-stalker state machine: **Dormant** by day (parked off-map), **Patrol** near the camp perimeter at night, **Pursuing** the nearest player outside the Bonfire's safe zone in a straight line with speed that ramps the longer the chase runs, **Stunned** by a flashlight beam (duration shrinks per consecutive use, recovers after a cooldown), and **Retreating** once the target reaches the safe zone. Deer uses its existing `Idle`/`Walk`/`Run`/`Stunned`-x3 animation set; Ram Monster (no baked anims) falls back to the default R15 walk/idle set since its skeleton matches R15 exactly.
- `FlashlightService` + `FlashlightController` — the user-provided Creator Store `Flashlight` tool's insecure client-only toggle script was rebuilt: the client only reports a low-stakes "beam on/off" boolean, and the server independently computes range/facing-cone alignment against every active stalker before ever applying a stun.
- `CultistRaidService` — every 4th in-game day/night pair, a wave of `Cultist`/`Cultist2` (size scaling with day number, capped at 8) spawns in a ring around the camp and is driven by `AnimalAIService`'s same generic AI (no duplicate logic); a banner warns at dawn of the raid day and again when the raid starts, and an unresolved raid still active at the next dawn drains campfire fuel faster in proportion to survivor count via a new `CampfireService:ApplyExternalDrain` hook.
- `CombatService` — one click-to-attack remote drives both `Axe` and `Spear` (a new Spear `Tool` built and granted here); server validates range/facing-angle/cooldown and damages the nearest registered `CombatTargetRegistry` target, falling back to `HarvestService`'s tree-chop path for the Axe when nothing is in range. `AttackLanded`/`NpcAttacked`/`StalkerContact` signals drive client hit-spark VFX, camera shake, and a red damage flash.
- Animation strategy actually used per species (best-effort real animation, procedural fallback never left unanimated, per the free-assets-only decision): Deer keeps its own full baked set; Owl and Ram Monster share Roblox's public default R15 walk/idle animation ids since their skeletons are genuine R15 rigs; Cultist/Cultist2 use the R6 equivalents plus their existing baked `Attack`; Wolf/AlphaWolf/Bear/Bunny have non-standard custom skeletons, so they get a procedural `math.sin`-phased Motor6D leg/arm swing instead (amplitude scaled by move speed, blended back to rest when idle).
- `ProceduralAnimController` — subtle idle-breathing camera offset for the local player when standing still, so idle never reads as a frozen pose.

**What you'll see when you play:**

- Bunnies hopping and fleeing by day; owls perched quietly, both replenishing over time if hunted out.
- After dusk, wolf packs actively hunting — patrolling, then breaking into a chase the moment they spot you, with alpha wolves leading tougher packs on later nights.
- A lone bear guarding its patch of forest — leave it alone and it leaves you alone, get close and it charges.
- The Deer: silent until night, then unmistakably hunting you in a straight line, getting faster the longer it chases — shining your flashlight on it freezes it in a visible stun animation, buying an escape window that shrinks every time you reuse the trick; reaching the firelight makes it break off and retreat.
- Every 4th night, a warning banner plays and a wave of cultists marches on your camp — fight them off with your axe/spear before dawn, or the fire burns down faster as punishment; clearing the raid shows a "repelled" banner.
- Combat feels alive: swings have real range/facing checks, hits spark and shake the camera, kills drop meat/resources you can carry home — all server-validated so nothing can be faked from the client.

---

### Phase 3 — Production Readiness Notes

- **Free-assets-only decision.** No paid Creator Store/Sketchfab animation packs were sourced; where a species' skeleton doesn't match a public default rig (Wolf/AlphaWolf/Bear/Bunny), it is animated procedurally instead of shipping unanimated or blocking on a purchase.
- **Day-scaling and raid cadence are tunable.** `AnimalAIService`'s `WOLF_BASE_COUNT`/`WOLF_DAY_SCALING`/`ALPHA_START_DAY` and `CultistRaidService`'s `RAID_INTERVAL_DAYS`/`BASE_RAID_SIZE` are simple local constants — safe to retune after the first playtest without touching logic.
- **Gate to Phase 4 is open.** Every Phase 3 system registers through the same Knit service/controller tree and `CombatTargetRegistry`, so Phase 4's rescue/building work can add new interactables without touching combat or AI.

---

## Phase 4 — Base Building, Missing Children Rescue, Day Multiplier, Win/Loss

The endgame progression loop: build up camp defenses and sleep efficiency, rescue the four missing children to accelerate toward the survival goal, and land on a real win or permadeath ending.

**Build:**

- `BuildingService`: place the existing `bed`/`bedframe1`/`bedframe2` models (and any other placeable `Base-map` furniture) inside a ZonePlus-bounded camp zone, server-recomputed grid-snap, resource-gated (Wood/Stone from `Resources`), overlap-checked against existing placements.
- **Sleep & Day Multiplier**: interacting with a placed bed at night skips ahead multiple nights at once (mirrors the wiki's "one sleep can equal several nights"); `Base.DayMultiplier` increases with bed count and stacks additively with each rescued child's bonus (per wiki: every rescue adds to the multiplier too).
- `RescueService` — Missing Poster Board:
  - Places/uses the existing `Poster[Part]` as an interactable board at camp (already present in `lobby-map`; mirrored into `Base-map` if no equivalent exists there).
  - Interacting shows a directional hint/arrow toward the nearest un-rescued child's cave (server picks the target — client never chooses), reusing the wiki's "always points to the closest remaining child" rule so any rescue order works.
  - Two child rescues are directly supported by existing assets: `Dino Kid` (guarded cave — gate by a small `WolfModel` pack, mirrors the wiki's red-key/wolf-guard cave) and `Kraken Kid` (guarded by `AlphaWolfModel`s, mirrors the wiki's tougher second rescue). Each cave is a locked gate (`CollectionService`-tagged) that only opens once every guard NPC in its pack is confirmed dead server-side.
  - Rescuing a child: pick them up (carry state, empty-handed requirement mirrors the wiki), walk them back into the Bonfire's safe zone, and they visibly settle at the edge of the firelight (a small tent/sit animation) — this is a one-time, permanent `Rescue.ChildrenRescued` flag plus an immediate `Base.DayMultiplier` bump.
  - Poster board visually updates per child from "Missing" to "Rescued" state.
- **Win/loss states**: permadeath on death (character can't respawn into the same run; a stats-summary death screen shows nights survived, wolves/cultists killed, children rescued, pulled from `Stats`/`Survival`/`Rescue`); reaching Night 67 (our scaled analogue of the original's Night 99) with the multiplier applied triggers a win screen and summary.

**What you'll see when you play:**

- Crafting/placing a bed at camp with stored Wood; sleeping in it at night fast-forwards several nights in one action instead of surviving them one at a time, and each extra bed makes that jump bigger.
- Interacting with the Missing Poster Board at camp: a directional arrow points you toward a wolf-guarded cave. Clearing every wolf drops the key/unlocks the gate; carrying the child home makes them visibly settle into a tent at the edge of the firelight and permanently boosts your day multiplier — do this again for the tougher alpha-wolf-guarded second child.
- The poster board itself updates to show which children are found versus still missing.
- Dying is final for that run — a death screen summarizing nights survived, kills, and rescues appears, matching the reference game's brutal tone.
- Surviving to Night 67 (accelerated by beds and rescues, exactly like the original's Night 99) triggers a win screen with your final run stats.

---

## What You'll See — The Finished Game, End to End

- **Lobby → Base:** spawn in the lobby, step on a teleporter, land in a fully populated forest base camp lit by a central Bonfire.
- **Day cycle:** a visible day/night clock and lighting shift; hunger drains over time and sprinting accelerates it, fixed by eating foraged berries/mushrooms or campfire-cooked meat, tracked on a real inventory HUD.
- **Resource loop:** chop any of the hundreds of pre-placed trees for Wood, feed the Bonfire to keep its light radius (and your safety) alive, forage for food, hunt animals for meat and pelts.
- **Night threat:** wolf packs (regular and alpha) hunt in the dark, a lone bear guards its territory, and the Deer — the game's signature horror — silently stalks whoever strays from the firelight, stunnable only by flashlight or the campfire's own glow, getting harder to stun the more you rely on the trick. Every few nights, cultists raid the camp and must be fought off with server-validated melee combat that drops real loot.
- **Base progression:** build beds to fast-forward through nights at an accelerating multiplier, growing your camp's resource security over the run.
- **Rescue objective:** use the Missing Poster Board to track down and rescue the two guarded children, each a genuine combat-gated mini-objective that boosts your survival pace.
- **Stakes:** death is permanent and shows a full run summary; surviving to Night 67 is a real, earned win screen — the complete arc of a 99-Nights-style run, scoped to this project's asset set.

---

## Notes

- **Asset reuse discipline**: every NPC/structure/item already in `ServerStorage.Assets` is mapped to a specific phase and mechanic above and in `ARCHITECTURE.md` §1 — no placeholder models are created where a matching asset exists.
- **Scope boundary vs. the original game**: the reference 99 Nights in the Forest has biomes (snow/volcano/jungle), a 20+ class shop, a Pelt Trader, crafting-bench tiers, taming, and dozens of entities. This project's asset library covers one biome's worth of content (Deer/Wolf/AlphaWolf/Bear/Ram/Owl/Bunny/Cultist x2, two rescuable children). The roadmap above adapts the _mechanics_ (Deer stun-chase, wolf-guarded caves, day-multiplier beds, poster-board rescue, cultist raids) to that asset set rather than inventing content we have no models for. If more NPCs/biomes are added to `ServerStorage.Assets` later, Phase 3/4 services are structured (data-driven spawn tables, generic guard-pack gate logic) to extend without a rewrite.
- **Map edits**: `Base-map`/`lobby-map` geometry stays pre-built; only functional markers (spawn points, camp-zone bounds, cave locks, bed placement grid) are added via script/attribute unless structural changes are explicitly requested.
- **Open decisions from `ARCHITECTURE.md` §7** (base persistence across restarts, ProfileService vs ProfileStore) remain to be finalized before Phase 4's building/rescue state is made persistent.
