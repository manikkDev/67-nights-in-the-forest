# 67 Nights in the Forest — Project Notes

## Build & Verify

- Build: `rojo build default.project.json --output build.rbxl`
- Run from the repo root: `D:\Roblox Studio Games\67 nights in the forest`
- Studio assets (ServerStorage.Assets) are NOT synced by Rojo — they live only in the .rbxl place file. Inspect them at runtime via the Roblox Studio MCP tools, not the filesystem.

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
