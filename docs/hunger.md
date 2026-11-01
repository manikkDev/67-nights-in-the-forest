# Hunger & Health

Two meters drive survival pressure: Health and Hunger, both starting at 100.

## Hunger

- Decays continuously over time (`HungerService`)
- At zero hunger, health drains until you eat or die
- Eating restores hunger — see the food values table in `docs/cooking.md`

## Health

- Damaged by enemy attacks and starvation
- Regenerates slowly while fed
- At 0 HP the player becomes Downed (see `docs/carry-revive.md`)

## Eating

Use a food item from the inventory hotbar. `HungerService.RequestEat` validates the item server-side and applies the heal value from `RunConfig.ConsumableHeal`.

## HUD

`HungerController`/`HealthBarController` render the meters and flash them when low.

## See also

- [Cooking](cooking.md) — [Foraging](foraging.md) — [Downing & reviving](carry-revive.md)
