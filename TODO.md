# TODO - Life-Simulator-Game

See the docs https://shineokay4.github.io/Life-Simulator-Game/generated/api/

Last updated: 2026-02-28

## Completed Infrastructure

- [x] Add GitHub issue templates
  - `.github/ISSUE_TEMPLATE/bug-report.yml`
  - `.github/ISSUE_TEMPLATE/feature-request.yml`
  - `.github/ISSUE_TEMPLATE/config.yml`
- [x] Add CI workflow for tests, Rojo build, and docs build/deploy
  - `.github/workflows/build.yml`
- [x] Add Lua test runner and initial spec suite
  - `run_tests.sh`
  - `Tests/Specs/ExampleSpec.lua`
  - `Tests/Specs/PlotSpec.lua`
  - `Tests/Specs/TenantSpec.lua`
- [x] Add Roblox-like CI smoke test lane via Lemur + TestEZ
  - `vendor/lemur` and `vendor/testez` submodules
  - `Tests/Lemur/lemur_runner.lua`
  - `Tests/Lemur/Specs/SourceTreeSmoke.spec.lua`
  - `.github/workflows/build.yml` updated to install Lemur deps and run smoke suite
- [x] Scaffold dynamic docs site and source-driven generation
  - `docs/` (Docusaurus + `docs/scripts/generate-docs.mjs`)
- [x] Add initial changelog scaffold
  - `CHANGELOG.md`

## Verified Locally

- [x] `./run_tests.sh` passes
- [x] `busted Tests/Specs/*.lua` passes
- [x] `lua5.1 Tests/Lemur/lemur_runner.lua` passes
- [x] `npm run build --prefix docs` passes

## Completed Features

- [x] Iteration 1 bugfix: resolve MainHUD startup crash when `DailyRewardsButton` is an `ImageButton` (GitHub issue #16)
  - Updated `src/Client/UserInterface/MainHUD.luau` button bindings to use `GuiButton` instead of assuming `TextButton`
  - Added safe button-label assignment so `.Text` is only written when supported
  - Reused existing HUD buttons regardless of `ImageButton`/`TextButton` class to prevent class-mismatch crashes
- [x] Iteration 7 bugfix: restore missing `ReplicatedStorage.Shared.Modules.PropConfig` compatibility (GitHub issue #14)
  - Added `src/Shared/Definitions/PropConfig.luau` as an aggregate over catalog definition modules
  - Added `src/Shared/Modules/PropConfig.luau` shim so legacy `Shared.Modules.PropConfig` requires resolve again
  - Added `Tests/Specs/LegacyModuleCompatSpec.lua` assertions for `PropConfig` compatibility paths
- [x] Iteration 3 bugfix: restore `ReplicatedStorage.Shared.Modules` compatibility for legacy DUO scripts (GitHub issue #12)
  - Added `src/Shared/Modules/` shim modules that re-export current `Shared/Utilities`, `Shared/Configurations`, `Shared/Definitions`, and `Shared/Services` modules
  - Added/kept Lemur source-tree smoke assertion for the `Shared/Modules` folder to prevent folder-level regressions
  - Validation: `./run_tests.sh` (601 successes, 0 failures)
- [x] Iteration 5 bugfix: restore missing `ReplicatedStorage.Shared.Modules.RNGUtil` compatibility (GitHub issue #13)
  - Added `src/Shared/Utilities/RNGUtil.luau` with deterministic helper APIs and legacy aliases
  - Added `src/Shared/Modules/RNGUtil.luau` shim so legacy `Shared.Modules.RNGUtil` requires resolve again
  - Added `Tests/Specs/LegacyModuleCompatSpec.lua` to prevent `RNGUtil` shim regressions
  - Validation: `./run_tests.sh` (603 successes, 0 failures)
- [x] Iteration 5 review fix: prevent zero-weight entries from being selected in weighted RNG picks
  - Updated `src/Shared/Utilities/RNGUtil.luau` weighted pick boundary condition to skip zero-weight entries
  - Added `Tests/Specs/RNGUtilSpec.lua` regression coverage for the weighted-boundary guard
  - Validation: `./run_tests.sh` (604 successes, 0 failures)
- [x] Iteration 7 issue triage: close GitHub issue #11 after validating startup warning fixes
  - Confirmed the reported stack-frame paths are now guarded (`ItemFinder`, `PlotSelector`) with bounded startup resolution
  - Posted fix summary/validation on issue #11 and closed it
- [x] Iteration 7 bugfix: suppress runtime infinite-yield warnings for required startup instances
  - `src/Shared/Utilities/ItemFinder.luau` now resolves `ReplicatedStorage.Assets`/`Catalog` with bounded waits and explicit errors
  - `src/Client/Modules/PlotSelector.luau` now resolves `MainHUD`/plot selector UI with bounded waits to avoid noisy `WaitForChild` warnings
- [x] Seasonal Event System (Iteration 1)
  - `src/Shared/Definitions/SeasonalEventDefinitions.luau` -- 4 seasons with challenges, buffs, milestones
  - `src/Server/Services/SeasonalEventService.luau` -- season transitions, challenge tracking, buff multipliers
  - `src/Network/SeasonalEventPackets.luau` -- client-server packets
  - `Tests/Specs/SeasonalEventSpec.lua` -- 54 behavioral tests
  - `Profile.luau` updated with `SeasonalEventState`
  - Integrates with WeatherConfig season cycle and notification system
- [x] Daily Reward System (Iteration 1)
  - `src/Shared/Definitions/DailyRewardDefinitions.luau` -- 7-day reward cycle with milestones
  - `src/Server/Services/DailyRewardService.luau` -- streak tracking, cooldown, claim logic
  - `src/Network/DailyRewardPackets.luau` -- client-server packets
  - `Tests/Specs/DailyRewardSpec.lua` -- 27 behavioral tests
  - `Profile.luau` updated with `DailyRewardState`
  - First real consumer of `NotificationService`

## Next Work (Product/Code Depth)

- [ ] Add startup diagnostics/logging standards for Roblox Studio issue triage (service/module load boundaries + key dependency resolution points)
- [x] Seasonal Event System follow-ups
  - [x] Wire SeasonalEventService into WeatherService for automatic season transitions
  - [x] Build client-side SeasonalEventUI (season banner, challenge tracker, buff display, milestone rewards, per-challenge/milestone reward claiming, MainHUD button)
  - [x] Add seasonal achievements to AchievementDefinitions
  - [x] Integrate seasonal buffs into ProgressionService (XP multiplier) and BillingService (cash multiplier)
- [x] Daily Reward System follow-ups
  - [x] Build client-side DailyRewardUI (claim button, streak calendar, countdown timer)
  - [x] Wire DailyRewardService into ProgressionService for XP grants
  - [x] Add Daily Reward achievements to AchievementDefinitions
  - [x] Add daily challenge variant (rotating objectives using QuestService)
- [x] Replace stub-heavy tests with behavior tests against production service logic
  - [x] Replace `TenantSpec` stubs with behavior tests for `TenantService/ValidationUtils` edge cases
  - Focus first on `PlotService` and `TenantService` edge cases
- [x] Integrate NotificationService into core economy/services
  - [x] AchievementService
  - [x] TradeService
  - [x] BillingService
- [x] Add CI lint step for Luau source (`selene`)
- [x] Expand public docs with gameplay/system overviews and contributor setup guidance
- [x] Enable release process that updates `CHANGELOG.md` from merged PR metadata
