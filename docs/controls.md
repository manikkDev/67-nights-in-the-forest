# Controls

Keyboard/gamepad bindings, sourced from the controller `ContextActionService`
and `UserInputService` handlers plus server `ProximityPrompt` key codes.

## World

| Action | Keyboard | Gamepad | Source |
| ------ | -------- | ------- | ------ |
| Pick up item / wood | `F` | — | `CarryController` |
| Feed campfire | `E` | `ButtonY` | `CampfireService` prompt |
| Revive teammate | `E` | `ButtonX` | `PlayerLifeService` prompt |
| Open map | `M` | — | `MapController` |
| Close map / UI | `Escape` | — | `MapController` |

## Building placement

Bound via `ContextActionService` while a placement is active:

| Action | Keyboard | Gamepad |
| ------ | -------- | ------- |
| Rotate clockwise | `R` | `ButtonR1` |
| Rotate counter-clockwise | `Q` | `ButtonL1` |
| Confirm placement | `Return` | `ButtonA` |
| Cancel placement | `X` | `ButtonB` |

## Carrying a rescued child

| Action | Keyboard | Gamepad |
| ------ | -------- | ------- |
| Drop carried child | `G` | `ButtonB` |

## Spectating (downed/eliminated)

| Action | Keyboard | Gamepad |
| ------ | -------- | ------- |
| Next target | `E` | `ButtonR1` / `DPadRight` |
| Previous target | `Q` | `ButtonL1` / `DPadLeft` |
