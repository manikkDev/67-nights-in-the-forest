# 67 Nights — 4-Phase Execution Roadmap

Each phase ends with a playable, observable milestone. "What you'll see" describes actual in-Studio/in-play behavior, not code internals. Reference source for authenticity: the original **99 Nights in the Forest** (Grandma's Favorite Games) — fandom wiki, official site, and PCGamer tips guide, cross-checked against our own asset inventory so nothing below asks for content we don't have (no biomes, no 23-class shop, no snow/volcano — those are out of scope; see Notes).

---

## Progress Audit (as of this revision)

Live check of `src/server/Services`, `src/Client/Controllers`, and `ProfileTemplate.luau` against the old roadmap:

| Old phase item                                                                                   | Status          | Evidence                                                                                                              |
| ------------------------------------------------------------------------------------------------ | --------------- | --------------------------------------------------------------------------------------------------------------------- |
| Wally packages, `WorldService` map placement, `PlayerDataService`, `TimeService`, `SpawnService` | **Done**        | Services exist and are wired into `Server.server.luau`; `Base-map`/`lobby-map` are live in `Workspace`                |
| `HudController` day/night labels                                                                 | **Done**        | `src/Client/Controllers/HudController.luau`                                                                           |
| `HungerService` (decay + starvation)                                                             | **Done**        | `src/server/Services/HungerService.luau` — Heartbeat drain, sprint multiplier, starvation damage, throttled broadcast |
| `HarvestService` (tree chopping)                                                                 | **Done**        | `src/server/Services/HarvestService.luau` — ProximityPrompt chop, tree health/respawn/fell tween, Log pickups         |
| `CampfireService` (fuel + fire visuals)                                                          | **Done**        | `src/server/Services/CampfireService.luau` — fuel decay, `RequestFuelCampfire`, fire/light scaling, safe-zone radius  |
| `HarvestController`/`HungerController` client sync                                               | **Done**        | Both exist in `src/Client/Controllers`                                                                                |
| **Eating** (Berries/Mushrooms restoring Hunger)                                                  | **Not started** | `ProfileTemplate.Resources` has `Berries`/`Mushrooms` fields but no service produces, picks up, or consumes them      |
| Inventory GUI showing real resource counts                                                       | **Not started** | No inventory controller/GUI script found                                                                              |
| Animal/NPC AI (any kind)                                                                         | **Not started** | No `AnimalAIService`/combat service exists; NPC models sit inert in `ServerStorage.Assets.Assets Npcs`                |
| Combat, loot drops, procedural animation                                                         | **Not started** | No combat service/controller                                                                                          |
| Base building, beds, day multiplier                                                              | **Not started** | `ProfileTemplate.Base` fields exist but unused; no `BuildingService`                                                  |
| Missing children rescue, caves, poster board                                                     | **Not started** | `ProfileTemplate.Rescue` fields exist but unused; no `RescueService`                                                  |
| Win/loss, permadeath                                                                             | **Not started** | No such logic anywhere                                                                                                |

**Conclusion:** the old Phase 1 **and** most of the old Phase 2 (hunger, chopping, campfire) are already built and working. What remains is: closing the loop on **eating/inventory UI**, then everything from **NPC AI/combat** through **building/rescue/win-loss**. This revision folds the leftover Phase-2 sliver into the new **Phase 2** and restructures Phases 3–4 with the full depth of the reference game's core loop, scoped to our actual asset set.

---

## Phase 1 — Networking, Data, Teleport/Spawn, Day/Night Clock ✅ DONE

**Build:** Wally packages (Knit, ProfileService, ZonePlus, Janitor); `WorldService` places `Base-map`/`lobby-map` and anchors `Bonfire`; `PlayerDataService` + `ProfileTemplate`; `TimeService` day/night clock with `Lighting` tween; `SpawnService` lobby→base teleport; `HudController` day/night labels.

**What you see:** Spawn in the lobby, cross a teleporter into the populated base map, watch `DayLabel`/`NightLabel` and lighting shift on a timer. No survival mechanics yet.

---

## Phase 2 — Close the Survival Loop: Eating, Inventory UI, Camp Safety Feedback

The only unfinished slice of "core survival." Everything else in this phase is UI/feedback polish on top of the already-working hunger/harvest/campfire services, plus the missing food loop that the reference game treats as a first-class resource (Berries, Mushrooms, cooked meat via campfire).

**Build:**

- `ForageService`: spawns pickup-able `Berries`/`Mushrooms` world items around the base map at intervals (bush/mushroom-cluster spawn points, respawn timer mirroring `HarvestService`'s tree pattern), `RequestPickup`/`RequestEat` remotes that validate proximity + ownership and restore `Survival.Hunger` server-side.
- `CookingService` (minimal): dropping raw meat (`rabbit-meat`, `wolf-meat`) on the lit Bonfire converts it to `Resources.CookedMeat` after a timer, mirroring the wiki's "campfire cooks food" rule; cooked meat restores more Hunger than raw pickups.
- `InventoryController` + a real inventory/HUD panel: live-bound to `Resources` (Wood, Berries, Mushrooms, RawMeat, CookedMeat) via a `PlayerDataService` signal, replacing the current static placeholder GUIs.
- `CampSafetyController`: visual/audio cue (screen vignette darken + ambient sting) when the player is outside `CampfireService:GetSafeZoneRadius()` at night, foreshadowing Phase 3 threat.

**What you'll see when you play:**

- Berries and mushrooms scattered near camp that you can walk up to and pick up; eating them (via prompt or hotbar) visibly refills your hunger bar.
- Cooking raw meat you're carrying by tossing it into the lit Bonfire — it turns into cooked meat that heals more hunger than eating it raw.
- A real inventory panel on-screen showing live counts of Wood/Berries/Mushrooms/Meat instead of the current static/blank GUI.
- Standing outside the campfire's light at night visibly darkens your screen edges as a warning — nothing attacks you yet, but the game is telling you it's about to.

---

## Phase 3 — The Forest Comes Alive: Animal AI, The Deer, Cultists, Combat

This is the horror-survival heart of the reference game — pack predators by night, an unkillable stalking Deer that the campfire and light repel, Cultist raids on a timer, and real combat with loot.

**Build:**

- `AnimalAIService` — passive tier: `BunnyModel` wanders and flees on proximity (drops toward `Carrot`/pelt loot on death); `Owl` idles in trees by day.
- `AnimalAIService` — predator tier: `WolfModel` (regular, pack of 3-5, `PathfindingService` patrol→chase state machine) and `AlphaWolfModel` (pack leader, higher HP/damage, spawns in smaller elite packs) roam at night and path toward the campfire's noise/light source; population count scales with `TimeService.DayNumber` (more wolves, further out, as nights pass — mirrors the wiki's difficulty ramp).
- `Bear` — solitary, higher HP, guards a territory radius around its spawn point (reuses its existing baked `Attack` animation); aggros if approached, does not chase far outside its territory.
- `DeerService` (the signature threat) — one server-wide unkillable `Deer` instance:
  - **Day:** dormant/hidden.
  - **Night:** pathfinds in a straight line toward the nearest player outside the Bonfire's safe zone, using its existing `Walk`/`Run` animations; speed increases the longer it pursues a single target (matches wiki behavior).
  - **Stun:** a flashlight/torch beam or standing in the Bonfire's light radius interrupts its charge and plays its existing 3-phase `Stunned` animation set; the stun window shortens each time it's used on the same Deer instance (recovers faster per stun, per wiki).
  - **Retreat:** the Deer disengages and returns to dormant if the target reaches the safe zone or if all nearby threats (e.g. an active Cultist raid) are cleared.
  - `Ram Monster` reuses the same "unkillable stalker with a chargeable/stunnable attack" state machine as a second heavy threat (per the wiki, Ram/Owl/Deer share one behavioral family — we implement it once and parametrize).
- `CultistRaidService` — every N in-game days (configurable, mirrors the wiki's "raids roughly every 4 nights"), spawns a wave of `Cultist`/`Cultist2` that path toward the Bonfire and attack it/players directly (their existing `Attack` animation); a raid banner/warning appears before it starts; failing to clear cultists by dawn speeds up campfire fuel decay (per wiki penalty).
- `CombatService` + ZonePlus melee hitboxes: `Axe`/`Spear` swings validated server-side (range, cooldown, facing angle); NPC attacks validated the same way in reverse. Loot table on kill: Wolf → `wolf-meat` (+ pelt item), Bunny → `Carrot`/`rabbit-meat`, Bear → `wolf-meat`-tier drop (reuse existing meat items; no new mesh needed).
- `ProceduralAnimController`: TweenService-driven swing arc for the player's equipped tool (per `ARCHITECTURE.md` §5) plus idle breathing; procedural gait for Wolf/Bear/Ram (no baked walk anim) driven by `math.sin`/`math.cos` phase per limb.
- Hit VFX: spark/flash `ParticleEmitter` + `Highlight` on hit, wood-chip/blood burst on kill, `Debris`-cleaned, `CameraShaker`-style impact shake on the attacking client.

**What you'll see when you play:**

- Bunnies hopping and fleeing by day; owls perched quietly.
- After dusk, wolf packs actively hunting — patrolling in loose formation, then breaking into a chase the moment they spot you, with alpha wolves leading tougher packs on later nights.
- A lone bear guarding its patch of forest — leave it alone and it leaves you alone, get close and it charges.
- The Deer: silent until night, then unmistakably hunting you in a straight line, getting faster the longer it chases — shining your flashlight on it (or reaching the campfire's light) freezes it in its tracks in a visible stun animation, buying you an escape window that shrinks every time you reuse the trick.
- Every few nights, a warning plays and a pack of cultists marches on your camp — you fight them off with your axe/spear before dawn, or the fire burns down faster as punishment.
- Combat feels alive: your weapon swings through a real arc, hits spark and knock enemies back, and kills drop meat/loot you can carry home — all fully server-validated so nothing can be faked from the client.

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
