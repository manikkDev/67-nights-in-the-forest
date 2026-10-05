# Contributing

Thanks for helping with 67 Nights in the Forest. This file covers the
workflow and conventions used in the repo.

## Setup

1. Install the toolchain (Rojo, Wally) — easiest via
   [Rokit](https://github.com/rojo-rbx/rokit): `rokit install`
2. Install packages: `wally install`
3. Build the place file:

   ```bash
   rojo build default.project.json --output build.rbxl
   ```

4. Open `build.rbxl` in Roblox Studio, run `rojo serve`, and connect.

## Code Style

- Tabs for indentation, double-quoted strings (see `stylua.toml` /
  `.editorconfig`).
- Scripts use the three-section layout: `VARIABLES` / `FUNCTIONS` /
  `INITIALIZATION`.
- Every module starts with a header block (`@file`, `@author`,
  `@date`, `@summary`, `@description`, `@exports`).
- Public functions carry UDD doc comments (`@summary`, `@param`,
  `@returns`).
- Server is authoritative — never trust client state; all gameplay
  mutations go through a Knit service.

## Adding a Weapon Tool

Follow the rules in `AGENTS.md` — use the hand-grip part as the Tool
`Handle`, rename any other part already named `Handle`, weld the rest,
and set `tool.Grip` as a single `CFrame`.

## Commits & PRs

- Conventional commit messages: `feat:`, `fix:`, `docs:`, `chore:`,
  `style:`, `refactor:` — scoped where useful, e.g.
  `docs(rescue): ...`.
- Keep commits focused; one logical change per commit.
- Verify `rojo build` succeeds and smoke-test in Studio before
  opening a PR.
