# Changelog

All notable changes to this project are documented in this file.

## [Unreleased]
### Merged PRs

- PR #17: Duo ([@Ritooo-kun](https://github.com/Ritooo-kun), 2026-03-03) ([link](https://github.com/SHINEOKAY4/Life-Simulator-Game/pull/17))
- PR #18: Optimization Sprint Iter 1-9 ([@Ritooo-kun](https://github.com/Ritooo-kun), 2026-03-15) ([link](https://github.com/SHINEOKAY4/Life-Simulator-Game/pull/18))


### Added

- Seasonal Event System with per-season challenges, buffs, milestones, and notification integration:
  - `SeasonalEventService` with season transitions, challenge tracking, buff multipliers, and milestone rewards
  - `SeasonalEventDefinitions` with 4 seasons (Spring/Summer/Autumn/Winter), 8 challenges, and 3 milestone tiers
  - `SeasonalEventPackets` for client-server communication
  - `SeasonalEventSpec` with 54 behavioral tests covering transitions, challenges, buffs, milestones, notifications, multi-player isolation, and edge cases
  - `SeasonalEventState` added to player Profile schema
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

- **Optimization Sprint Iter 1-9 (2026-03-03 to 2026-03-15)**: Systematic performance improvements:
  - Iter 1: Removed deprecated `MinimalPromptUI` module (no-op, zero references)
  - Iter 2: Removed unused `Shared/Modules` shims (`ActionBinder`, `ClickBinder`) — consolidated to `Shared/Utilities`
  - Iter 3: Replaced 30s polling loop in `WorldEventService` with next-expiry scheduling (eliminates fixed wakeups)
  - Iter 4: Optimized `Debounce.WaitUntilInactive` to avoid extra wakeups while preserving semantics
  - Iter 5: Added bounded backoff (`SEAT_CHECK_INTERVAL=0.05s`) to `ClientResidentMovement` seat acquisition (~3x fewer wakeups)
  - Iter 6: Cached `BuildService` action module resolution to eliminate repeated require overhead
  - Iter 7: Incremental `PlotState` snapshot diffing — avoids deep clone when no changes, added `removeKeyFromSnapshot`/`addItemToSnapshot` helpers
  - Iter 8: Single-pass mailbox pruning in `TenantService` (O(N) vs O(N²)) with deferred expired lease removal
  - Iter 9: Lint/format sweep — modernized 22 `UDim2.new` calls to `UDim2.fromOffset`/`UDim2.fromScale` (selene clean)
- `.gitignore` now excludes Docusaurus build/dependency outputs in `docs/`.
- Docs generation script hardened to emit MDX-safe API docs.
- Seasonal rewards documentation now includes claim flow, pending reward semantics, and batch rollback behavior (`docs/content/SeasonalEvents.md`).
- Seasonal rewards tests expanded with additional edge cases:
  - Milestone count normalization on claim input
  - Milestone-only batch distribution path
  - Pending milestone exclusion after claim
