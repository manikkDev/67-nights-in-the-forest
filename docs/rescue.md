# Rescue System

Four missing children are held in guarded caves across the forest. Rescuing all four is a major objective alongside surviving 67 days.

## Order and Unlocks

| Child  | Campfire level required | Guard     | Key       |
|--------|-------------------------|-----------|-----------|
| Dino   | 2                       | Wolf ×5   | Red Key   |
| Kraken | 3                       | AlphaWolf ×4 | Blue Key |
| Squid  | 4                       | Bear ×2   | Yellow Key |
| Koala  | 5                       | Bear ×6   | Gray Key  |

Caves spawn in fixed rings around the campfire so they always land inside the boundary at their unlock level.

## Flow

1. Find the cave (marked on the map board and map UI once in range).
2. Kill the guards outside the cave.
3. Collect the key they drop and unlock the cage.
4. Carry the child back to the rescue tent near the campfire.

## Tracking

Use the map UI's Track button (or `RequestSetWaypoint`) to mark a rescue target — an on-screen waypoint points you to the cave. `RequestClearWaypoint` clears it.

## Portrait Board

The Missing Children board near the campfire shows one portrait per child: red when locked, green when available or rescued, yellow while carried. Portraits render in `ViewportFrame`s — the client rebuilds them locally because ViewportFrame contents do not replicate.
