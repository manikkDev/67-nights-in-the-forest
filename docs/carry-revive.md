# Downing, Reviving & Carrying

When a player's health hits zero they enter the Downed state — ragdolled and unable to act, but revivable by teammates.

## States

`LifeState`: `Alive` → `Downed` → `Eliminated`. Handled by `PlayerLifeService`.

## Downed

- 45-second bleed-out timer (`RunConfig.DownedDuration`)
- When it expires the player is Eliminated and becomes a spectator
- A heartbeat loop plays while downed

## Reviving

Hold the Revive proximity prompt for 5 seconds (`ReviveHoldDuration`) within 12 studs (`ReviveRange`). The revived player returns at 35 HP (`ReviveHealth`). A 3-second grace period (`ReviveGracePeriod`) protects them.

## Dragging bodies

Teammates can drag a downed body to safety instead of reviving in place:

- Start range: 12 studs, max drag distance: 28 studs
- Drag updates every 0.04s with a responsiveness factor of 35
- The DragBody prompt is separate from Revive — both live on the body

## Team wipe

If every member is downed or eliminated simultaneously, the run ends in defeat.
