# Cooking

Raw meat from hunting is a weak heal (3 HP). Cooking it at the campfire triples-plus its value to 15 HP.

## How to cook

Hold raw meat near the campfire and use the prompt. `CookingService` converts the item server-side; `CookingController` plays the sizzle feedback.

## Values

`RunConfig.ConsumableHeal`:

| Food        | Restores |
|-------------|----------|
| Berries     | 5        |
| Mushrooms   | 6        |
| Raw Meat    | 3        |
| Cooked Meat | 15       |

## Tips

- Cook in batches at dawn before the night threat returns.
- Cooked meat is the most efficient food — prioritize it over foraged snacks when low on HP.
