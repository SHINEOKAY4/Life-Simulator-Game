# Changelog

All notable changes to this project are documented in this file.

## [Unreleased]

### Added

- Daily Reward System with streak tracking, 7-day escalating reward cycle, and milestone bonuses:
  - `DailyRewardService` with 20-hour cooldown, 48-hour grace period, and notification integration
  - `DailyRewardDefinitions` with 7-day reward cycle and 3 milestone tiers (7, 14, 30 days)
  - `DailyRewardPackets` for client-server communication
  - `DailyRewardSpec` with 27 behavioral tests covering claims, cooldowns, streaks, resets, milestones, isolation, and edge cases
  - `DailyRewardState` added to player Profile schema
- GitHub issue templates for bug reports and feature requests.
- CI workflow with:
  - Lua test execution (`busted`)
  - Rojo build artifact publishing
  - Docusaurus docs build and GitHub Pages deployment on `main`
- Initial Lua test harness:
  - `run_tests.sh`
  - `Tests/Specs/ExampleSpec.lua`
  - `Tests/Specs/PlotSpec.lua`
  - `Tests/Specs/TenantSpec.lua`
- Dynamic documentation scaffold under `docs/` with generated architecture/API pages.

### Changed

- `.gitignore` now excludes Docusaurus build/dependency outputs in `docs/`.
- Docs generation script hardened to emit MDX-safe API docs.
