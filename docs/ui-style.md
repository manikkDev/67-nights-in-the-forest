# UI Style Guide

Conventions for building interfaces that match the game's look.

## Fonts

- `Enum.Font.GothamBold` — body text, labels, buttons
- `Enum.Font.PermanentMarker` — titles, stamps, hand-written notes

## Text strokes

- Titles: stroke transparency 0.15–0.25
- Labels on light backgrounds: 0.5–0.6, light-colored stroke under dark text

## Status colors

| State     | Color                |
|-----------|----------------------|
| Locked    | red `(200, 60, 50)`  |
| Available | green `(40, 170, 60)`|
| Rescued   | green `(40, 180, 60)`|
| Carried   | yellow `(210,160,30)`|

## UI sounds

`UiSoundUtil` provides cached one-shots and named loops: `playClick`, `playSuccess`, `playLevelUp`, `playAlert`, `playSting(victory)`, `startLoop`/`stopLoop` — all parented to SoundService so they survive UI rebuilds.

## Screens

Major screens: title/story (intro), HUD (phase banner, day counter, meters), map, inventory, crafting, ending results.
