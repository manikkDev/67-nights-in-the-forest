# 67 Nights — 4-Phase Execution Roadmap

Each phase ends with a playable, observable milestone. "What you'll see" describes actual in-Studio/in-play behavior, not code internals.

---

## Phase 1 — Networking, Data, Teleport/Spawn, Day/Night Clock

**Build:**
- Install Wally CLI via Rokit; add `wally.toml` with Knit, ProfileService (or ProfileStore, pending your confirmation), ZonePlus, Janitor.
- `WorldService`: clone `Base-map` and `lobby-map` from `ServerStorage` into `Workspace`, set `PrimaryPart` on both (currently unset), anchor the `Bonfire` model at camp origin.
- `DataService` + `ProfileTemplate` (per `ARCHITECTURE.md` §3), load on `PlayerAdded`, save on `PlayerRemoving`/`BindToClose`.
- `DayNightService`: authoritative clock, day counter, `Lighting` tween between day/night presets, broadcasts phase to clients.
- Lobby → base teleport flow using the existing `lobby-map` teleporter parts (`Teleporter1/2/3` already present) and spawn points.
- `HudController` binds `DayLabel`/`NightLabel` to the live clock (no new UI built).

**What you'll see when you play:**
- Spawning in the `lobby-map` (visually the same pre-made lobby you already have).
- Standing on a teleporter part moves you into the `base-map`, which is now actually populated in Workspace (currently it only exists in ServerStorage).
- `DayLabel`/`NightLabel` in the corner update automatically as time passes; lighting visibly shifts from bright day to dark night on a timer.
- Nothing to fight, eat, or build yet — this phase is plumbing, not gameplay content.

---

## Phase 2 — Hunger, Tree Chopping, Campfire Fueling, UI Sync

**Build:**
- `HungerService`: decay tick, starvation damage, hooks into `HealthBarFill`/hunger GUI.
- `HarvestService`: chop the existing `Tree`/`bigtree` models (426+ trees already placed in `Base-map`), server-validated range+cooldown, drops `Wood`.
- `CampfireService`: fuel decay tick, `RequestFuelCampfire` remote, fog-of-war radius tied to fuel tier, fire visibly dies (particle/light shrink) if unfed.
- `InteractionController`: ProximityPrompt-driven chop/feed interactions.
- Inventory GUI wired to `Resources` (Wood/Berries/etc.) from the profile.

**What you'll see when you play:**
- A hunger bar that drains over time; eating berries/mushrooms (picked up as world items) refills it, and ignoring it damages you.
- Walking up to any of the hundreds of pre-placed trees and interacting chops it down with a wood-chip VFX burst, granting Wood in your inventory HUD.
- Bringing Wood to the Bonfire and feeding it visibly raises the flame/light radius; letting it starve of fuel dims the fire and darkness creeps toward camp.
- Your inventory GUI now shows real counts instead of being static.

---

## Phase 3 — Procedural Animal AI, Procedural Animation, Combat

**Build:**
- `AnimalAIService`: spawn/despawn logic for `BunnyModel`/`Owl` (passive, wander) and `WolfModel`/`AlphaWolfModel`/`Bear`/`Ram Monster`/`Cultist`/`Cultist2` (hostile, `PathfindingService`-driven pack/patrol/chase states), population scaled by day/night phase.
- Procedural gait/idle for models without baked animations (Wolves, Bunny, Owl, Ram) per `ARCHITECTURE.md` §5; `Deer`/`Cultist`/`Bear` reuse their existing baked `Animation` assets (Deer's Idle/Walk/Run/Stunned x3/Jumpscare set, Cultist's Attack, Bear's Attack).
- `CombatService` + ZonePlus hitboxes for melee swings and NPC attacks; loot drops (`wolf-meat`, `rabbit-meat`, `Carrot`) on kill.
- `ProceduralAnimController`/`CombatController`: player tool-swing arcs, hit-spark/blood VFX.

**What you'll see when you play:**
- Bunnies hopping passively around the map by day; at night, wolves in packs and cultists start pathing toward camp, visibly hunting players.
- Your character's axe/weapon swings with a real motion arc when you attack (no more static T-pose swing) — procedurally generated, not from an animation file.
- Hitting a wolf produces a spark/impact VFX and knockback; killing it drops raw meat you can pick up.
- The Deer, when encountered, idles/walks/runs using its existing animation set and enters its built-in stunned sequence when you interrupt its charge with fire/light — the Ram Monster behaves as an equivalent heavy-charge threat.
- Combat is snappy but server-validated: no client can lie about a kill.

---

## Phase 4 — Base Building, Missing Children, Win/Loss

**Build:**
- `BuildingService`: place beds (existing `bed`/`bedframe1`/`bedframe2` models in `Base-map`) and structures within a ZonePlus-bounded camp zone, grid-snapped, resource-gated.
- Day multiplier scaling with bed count; "sleep" action skips ahead multiple nights per the 99-Nights mechanic.
- `RescueService`: hook the existing `Poster[Part]` (found in `lobby-map`; needs an equivalent placed in `Base-map` if not already there) as the Missing Poster Board, directional-arrow guidance to locked caves, wolf-kill gate to unlock, rescue of `Dino Kid`/`Kraken Kid`-style child NPCs, survival-bonus grant.
- Win/loss states: permadeath handling, night-67 survival win condition, death/respawn flow tied to `DataService` stats.

**What you'll see when you play:**
- Building a bed at camp using stored Wood/Stone; once placed, sleeping in it fast-forwards several nights at once (e.g. Night 2 → Night 5) instead of surviving them one at a time.
- Interacting with the Missing Poster Board spawns a directional arrow pointing toward a locked cave guarded by wolves; clearing the wolves unlocks it and rescuing the child inside grants a visible survival bonus/multiplier.
- Dying is permanent for that run (permadeath) — a death screen with your stats (nights survived, wolves killed) appears, matching the "brutal" tone of the reference game.
- Reaching Night 67 (our stress-test analogue of the original's Night 99) triggers a win state and summary screen.

---

## Notes

- **Asset reuse discipline**: every NPC/structure/item already in `ServerStorage.Assets` is mapped to a specific phase and mechanic in `ARCHITECTURE.md` §1 — no placeholder models will be created where a matching asset already exists.
- **Map edits**: `Base-map`/`lobby-map` geometry stays as pre-built; only functional markers (spawn points, camp-zone bounds, cave locks) are added via script/attribute unless you request specific structural changes.
- **Open decisions from `ARCHITECTURE.md` §7** (base persistence across restarts, ProfileService vs ProfileStore) should be resolved before or during Phase 1.
