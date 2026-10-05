# Changelog

All notable changes to this project are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added

- Module documentation headers (`@description`, `@exports`) across all
  services, controllers, and shared modules
- `.gitattributes` for line-ending normalization and binary place files
- `.editorconfig`, `stylua.toml`, and `selene.toml` tooling configs
- Community files: `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md`,
  `SECURITY.md`, issue templates, and a PR template

### Changed

- `DayDuration` reduced from 300s to 180s (production tuning)

### Fixed

- Widened flashlight stun cone and fixed stat-card vertical centering
  in the ending screen
