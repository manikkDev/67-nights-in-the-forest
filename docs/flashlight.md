# Flashlight

The flashlight is a defensive tool — its beam stuns face-aware enemies.

## Battery

- The battery drains while the light is on and recharges while off
- `FlashlightService` tracks per-player beam/battery/aim state with rate-limited remote updates
- The HUD battery bar lives in `FlashlightController`

## Stun mechanics

Enemies that react to light (deer, owl) enter their stun sequence when the beam crosses their face cone:

- **Deer** — full freeze: `StunnedStart` → `StunnedLoop` → `StunnedEnd`
- **Owl** — temporary freeze mid-flight

The stun cone parameters were widened during tuning — see the deer task in `TASKS.md` for the intended full animation sequence.

## Controls

Equip from the hotbar, hold to aim. The beam direction follows the camera/mouse.
