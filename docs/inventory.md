# Inventory

Each player carries a bag of resources and items that persists across runs and rejoins (stored in the ProfileService profile, not reset per run).

## Item kinds

- **Resources** — Wood, Stone, Scrap, Berries, Mushrooms, Raw/Cooked Meat
- **Tools** — Spear, Axe, Flashlight
- **Junk** — facility pickups waiting to be ground into Scrap
- **Keys** — rescue-cave keys (auto-consumed at the cage)

## Inventory UI

`InventoryController` renders the hotbar and bag grid, handles hover tweens, and watches the profile for live updates. Counts appear on each slot; tools show an equip affordance.

## Dragging (bodies)

`InventoryService` also owns the "carried model" registry — dragged bodies and junk items count against carry capacity and show in the HUD while held.

## Persistence

Inventory lives under the player's profile (`Resources` + `Inventory` keys) and is deliberately excluded from the run-scoped reset list in `RunStateService`.
