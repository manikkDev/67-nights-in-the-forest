# Networking Surface

Knit remotes and signals per service. `signal` = server→client broadcast or
fire; `remote` = client→server request (validated server-side);
`property` = replicated value for late joiners.

## Lobby / match flow

| Name | Kind | Payload |
| ---- | ---- | ------- |
| `MatchFlow.RequestStart` | remote | `()` queue/launch a run |
| `MatchFlow.RequestLeave` | remote | `()` leave session |
| `MatchFlow.RequestSetCapacity` | remote | `(capacity)` host sets party cap |
| `MatchFlow.FlowStateChanged` | signal | `(state)` |
| `MatchFlow.Countdown` | signal | `(payload)` countdown tick |
| `MatchFlow.RosterChanged` | signal | `(roster)` member list |
| `MatchFlow.SessionChanged` | signal | `(snapshot)` per-player view |
| `RunState.RunPhaseChanged` | signal | `(phase, data)` |
| `RunState.MultiplierChanged` | signal | `({multiplier, sources})` |
| `Spawn.RequestSpawn` | remote | `()` lobby → base map teleport |
| `Spawn.PlayerSpawned` | signal | `()` |

## Survival

| Name | Kind | Payload |
| ---- | ---- | ------- |
| `Campfire.FuelChanged` | signal | `(fuel, maxFuel, fraction, isLit)` |
| `Campfire.LevelChanged` | signal | `(level, progress, requirement, levelFraction)` |
| `Campfire.SafeZoneChanged` | signal | `(radius, isActive)` |
| `Campfire.LevelUp` | signal | `(level, previousLevel, radius, maxFuel)` |
| `Campfire.SafeZoneRadius` / `IsLit` | property | replicated state |
| `Hunger.HungerChanged` | signal | `(hunger, maxHunger)` |
| `Inventory.ResourcesChanged` | signal | `(resources, capacity)` |
| `Inventory.DragTargetMoved` | remote | `(targetPos)` drag streaming |
| `Time.DayStarted` / `NightStarted` | signal | `(cycleIndex)` |
| `Time.DawnAdvanced` | signal | `(payload)` day counter |
| `Time.GetPhaseState` | property | `"Day" \| "Night"` |

## Creatures & combat

| Name | Kind | Payload |
| ---- | ---- | ------- |
| `AnimalAI.NpcAttacked` | signal | `(model, position)` |
| `AnimalAI.NpcDied` | signal | `(model, position, speciesKey)` |
| `AnimalAI.NpcHealthChanged` | signal | `(model, healthRatio, amount, position, speciesKey)` |
| `Deer.StalkerStunned` | signal | `(position, key, duration, stunnerUserId)` |
| `Deer.StalkerContact` / `StalkerActive` | signal | `(position, key)` / `(key)` |
| `Deer.AnimationStateChanged` | signal | `(key, animName)` |
| `Owl.OwlActive` / `OwlRetreated` | signal | `()` |
| `Owl.OwlDetection` | signal | `(meter)` |
| `Owl.OwlScream` / `OwlContact` | signal | `(position)` |
| `Owl.OwlStunned` | signal | `(position, duration)` |
| `Combat.AttackLanded` | signal | `(position, weaponName, wasImmune)` |
| `Flashlight.BatteryChanged` | signal | `(percent, isOn)` |
| `CultistRaid.RaidWarning` | signal | `(dayNumber, phase)` |
| `CultistRaid.RaidStarted` | signal | `(dayNumber, cultistCount)` |
| `CultistRaid.RaidCleared` / `RaidFailed` | signal | `(raidDayNumber [, survivors])` |
| `CultistRaid.RaidStatusUpdate` | signal | `(alive, total, fraction)` |

## Building / loot / rescue / ending

| Name | Kind | Payload |
| ---- | ---- | ------- |
| `Building.StructurePlaced` | signal | `(structureRecord)` |
| `Building.StructureChanged` | signal | `(structureId + changed fields)` |
| `Building.StructureDestroyed` | signal | `({structureId, position})` |
| `Crafting.OpenCrafting` | signal | `()` open the bench UI |
| `Crafting.CraftingStateChanged` | signal | `(snapshot)` |
| `Crafting.CraftSucceeded` | signal | `(recipeId, response)` |
| `Grinder.OpenGrinder` | signal | `()` |
| `Grinder.GrinderProcessed` | signal | `({position, scrapAmount, junkId})` |
| `Loot.ChestOpened` | signal | `(position, tier, granted, userId)` opener only |
| `Map.MapOpened` | signal | `({locked})` |
| `Rescue.RescueChanged` | signal | `(state payload)` |
| `Rescue.WaypointChanged` | signal | `({cleared|position...})` |
| `Rescue.ChildCarryChanged` | signal | `({userId, childId, carrying})` |
| `Rescue.CaveUnlocked` | signal | `(payload)` |
| `Rescue.BoardOpened` / `PosterStateUpdated` | signal | `(snapshot)` / `({states, rescuedCount})` |
| `Ending.EndingStarted` | signal | `(presentation)` |
| `Ending.ResultsReady` | signal | `(result)` final stats |
| `Ending.RequestEarlyReturn` | remote | `()` skip the ending |
| `PlayerLife.LifeStateChanged` | signal | `(state payload)` |
| `PlayerLife.TeammateDowned` | signal | `(userId, bleedOutAt)` |
| `PlayerLife.ReviveCompleted` | signal | `(targetUserId, reviverUserId)` |
| `PlayerLife.BodyDragTargetMoved` | remote | `(position)` body-drag streaming |
| `PlayerLife.RequestBodyDragStart` | remote | `(target Player)` |
| `WorldProgression.BoundaryExpanded` | signal | `(level, accessRadius)` |
| `WorldProgression.AccessRadius` | property | current radius |

## Server-side only signals

`AnimalAIService.NpcDiedServer`, `CampfireService.LevelChangedServer`,
`PlayerDataService.ProfileLoaded`, `PlayerLifeService.PlayerDowned /
PlayerRevived / PlayerEliminated`, `RunStateService.PhaseChanged /
RunStarted / RunEnding / RunCleaned`, `SessionRoutingService.LocalPartyReady /
DestinationReady / PartyTeleportFailed`, `SpawnService.PlayerSpawned`.
