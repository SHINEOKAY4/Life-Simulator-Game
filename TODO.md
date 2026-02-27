# TODO - Life-Simulator-Game

See the docs https://shineokay4.github.io/Life-Simulator-Game/generated/api/

Last updated: 2026-02-18

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
- [x] Scaffold dynamic docs site and source-driven generation
  - `docs/` (Docusaurus + `docs/scripts/generate-docs.mjs`)
- [x] Add initial changelog scaffold
  - `CHANGELOG.md`

## Verified Locally

- [x] `./run_tests.sh` passes
- [x] `busted Tests/Specs/*.lua` passes
- [x] `npm run build --prefix docs` passes

## Completed Features

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

- [x] Seasonal Event System follow-ups
  - [x] Wire SeasonalEventService into WeatherService for automatic season transitions
  - [x] Build client-side SeasonalEventUI (season banner, challenge tracker, buff display, milestone rewards, per-challenge/milestone reward claiming, MainHUD button)
  - [x] Add seasonal achievements to AchievementDefinitions
  - [x] Integrate seasonal buffs into ProgressionService (XP multiplier) and BillingService (cash multiplier)
- [ ] Daily Reward System follow-ups
  - [x] Build client-side DailyRewardUI (claim button, streak calendar, countdown timer)
  - [x] Wire DailyRewardService into ProgressionService for XP grants
  - [x] Add Daily Reward achievements to AchievementDefinitions
  - [ ] Add daily challenge variant (rotating objectives using QuestService)
- [ ] Replace stub-heavy tests with behavior tests against production service logic
  - Focus first on `PlotService` and `TenantService` edge cases
- [x] Integrate NotificationService into core economy/services
  - [x] AchievementService
  - [x] TradeService
  - [x] BillingService
- [x] Add CI lint step for Luau source (`selene`)
- [ ] Expand public docs with gameplay/system overviews and contributor setup guidance
- [ ] Enable release process that updates `CHANGELOG.md` from merged PR metadata
