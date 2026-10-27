# Combat

Melee combat uses equipped tools against NPCs and hostile animals.

## Weapons

- **Spear** — primary melee weapon, obtained from the Dino cave chest. Built by `CombatService.buildSpearTool()`.
- **Axe** — primarily a harvesting tool; also functions as a weak weapon.

## Attacking

Click/tap with a tool equipped. `CombatController` plays the swing animation, and `CombatService` validates the hit server-side (range, cooldown, target validity) before applying damage.

## Target registry

All damageable NPCs register in `CombatTargetRegistry` under the `CombatTarget` CollectionService tag. AnimalAI, Deer, and CultistRaid services each supply `{ ApplyDamage, IsImmune }` handlers, so CombatService never needs to know which service owns a target.

## Damage feedback

`AttackLanded(position, weaponName, wasImmune)` drives the hit spark and camera shake; `Damaged` flashes the screen via the damage ColorCorrection effect.

## Spear grip note

The spear's `Handle` part is `Spear.handle.Grip` (the red grip cylinder), not the head — see the Weapon Tool Creation section in `AGENTS.md` before adding new weapons.
