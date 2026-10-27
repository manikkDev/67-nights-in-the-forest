# Foraging

Bushes and ground plants yield food resources — the primary way to keep hunger up between hunts.

## Resources

| Item      | Heal | Source |
|-----------|------|--------|
| Berries   | 5 HP | Berry bushes |
| Mushrooms | 6 HP | Forest floor |

## Gathering

Walk up to a forageable and use the proximity prompt (F). `ForageService` validates range and respawn state; `ForageController` shows the pickup feedback.

## Respawn

Picked forageables disappear and respawn after a cooldown, so routes can be revisited.

## When to forage

- Daytime is safest — hostile species are mostly inactive.
- Forage while heading between objectives rather than as a dedicated trip.
- Berries and mushrooms are small heals; cooked meat (15 HP) remains the best food.
