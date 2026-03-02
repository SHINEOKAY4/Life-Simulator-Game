# TODO - Life-Simulator-Game

See the docs https://shineokay4.github.io/Life-Simulator-Game/generated/api/

Last updated: 2026-03-02 (Iter 10)

## Agent Context

Before starting work, read these files to understand the codebase:

- **`CLAUDE.md`** (repo root) — commands (tests, lint, rojo), source-to-Roblox path mapping, architecture overview, and key conventions. Created 2026-03-01.
- **`.github/copilot-instructions.md`** — detailed architecture fundamentals, critical patterns (Packet system, service init, grid placement, custom packages), common workflows for adding features, and a reference file index. Read this for code examples and "avoid these mistakes" guidance.

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

- [x] Iteration 4 feature: complete PlotSelector input debounce wiring cleanup
  - Removed stale in-file TODO in `src/Client/Modules/PlotSelector.luau` now that `runDebounced` guards are in place for next/previous/select actions
  - Added `Tests/Specs/PlotSelectorDebounceSpec.lua` to enforce debounce wiring and prevent TODO regression
  - Validation: `./run_tests.sh` (739 successes, 0 failures)
- [x] Iteration 2 feature: wire BillboardRadialUI move action into full move flow
  - Updated `src/Client/UserInterface/BillboardRadialUI.luau` move action to capture the selected model, close the radial UI, and start `ObjectAction.Move` using the model pivot position
  - Removed stale in-file move-action TODO placeholder in radial UI input handler
  - Added `Tests/Specs/BillboardRadialUISpec.lua` regression coverage for TODO removal and hide-before-move behavior wiring
- [x] Iteration 6 feature: implement resident weather reaction animations (shiver + heat sway)
  - Updated `src/Client/Modules/ResidentReactions.luau` with TweenService-driven waist Motor6D animations
  - Cold (<55F): rapid shiver oscillation via CFrameValue proxy tween on waist joint (+-2deg Z, +-0.8deg X at 0.12s)
  - Hot (>85F): slow heat-exhaustion sway with forward droop (4deg X, 2.5deg Z at 1.2s)
  - Proper lifecycle: stops tweens + restores original C0 on mood neutralize or Unregister
  - Supports both R15 (UpperTorso.Waist) and R6 (Torso.Root Joint) rigs
  - Removed stale TODO in `src/Client/Modules/ObjectSelector.luau` (debounce already implemented)
  - Added `Tests/Specs/ResidentReactionsSpec.lua` with 25 structural tests
  - Validation: `./run_tests.sh` (674 successes, 0 failures)
- [x] Iteration 6 feature: add PlotExpansion purchase success/failure toast notifications
  - Updated `src/Client/Modules/PlotExpansion.luau` to show user-facing notifications for successful and failed expansion purchases
  - Replaced placeholder print and removed in-file TODO for expansion purchase toast handling
  - Validation: `./run_tests.sh` (649 successes, 0 failures)
- [x] Iteration 6 feature: add PlotSelector claim success/failure toast notifications
  - Updated `src/Client/Modules/PlotSelector.luau` to show `Notification` toasts for claim failures (missing plot, server rejection) and successful claims
  - Removed in-file TODO placeholders for success/failure toast handling in plot selection flow
  - Validation: `./run_tests.sh` (649 successes, 0 failures)
- [x] Iteration 5 review sweep: fix compounding bill notifier tween, collision group race condition, server iterator, StartupDiagnostics nil guard
  - Fixed MainHUD bill notifier tween capturing original size once instead of re-reading mid-animation (compounding growth bug)
  - Fixed client `SetCollisionGroup` to connect `CharacterAdded` for all other players even if they have no character at loop time
  - Fixed server `OnPlayerAdded` to use `ipairs` (not `pairs`) for `GetDescendants` array iteration
  - Added nil-callback assertion to `StartupDiagnostics:Boundary` before incrementing sequence counter
  - Added `Tests/Specs/Iter5ReviewSpec.lua` with 13 regression tests covering all fixes
  - Validation: `busted Tests/Specs/*.lua` (623 successes, 0 failures)
- [x] Iteration 5b review sweep: fix SearchCatalog case mismatch, notifier tween Offset drop
  - Fixed `ItemFinder.SearchCatalog` to lowercase the query before `string.find` against the already-lowered `SearchBlob`; previously the token index was case-insensitive but the blob verification was case-sensitive, causing mixed-case queries to silently return zero results
  - Fixed `MainHUD` bill notifier tween target to use `UDim2.new()` instead of `UDim2.fromScale()`, preserving Offset components so Offset-based NotifierSymbol sizing doesn't collapse to zero
  - Added `Tests/Specs/Iter5bReviewSpec.lua` with 26 regression tests covering both fixes plus edge cases for StartupDiagnostics, client startup ordering, server player lifecycle, ItemFinder model fallback, cash delta handling, and income NaN guard
  - Validation: `busted Tests/Specs/*.lua` (649 successes, 0 failures)
- [x] Iteration 4 feature: add startup diagnostics/logging standards for startup triage
  - Added `src/Shared/Utilities/StartupDiagnostics.luau` with standardized startup boundary timing + dependency resolution logging
  - Instrumented `src/Server/Main.server.luau` and `src/Client/Main.client.luau` startup steps with explicit `Init`/`Start` boundaries
  - Added bounded+logged dependency resolution for `ReplicatedStorage.Network` (client) and `ReplicatedStorage.Assets.Catalog` path checks via `ItemFinder`
  - Added `Tests/Specs/StartupDiagnosticsSpec.lua` coverage for diagnostics wiring
- [x] Iteration 1 bugfix: resolve MainHUD startup crash when `DailyRewardsButton` is an `ImageButton` (GitHub issue #16)
  - Updated `src/Client/UserInterface/MainHUD.luau` button bindings to use `GuiButton` instead of assuming `TextButton`
  - Added safe button-label assignment so `.Text` is only written when supported
  - Reused existing HUD buttons regardless of `ImageButton`/`TextButton` class to prevent class-mismatch crashes
- [x] Iteration 1 bugfix: remove deprecated `lemur` and `testez` submodule dependencies (GitHub issue #15)
  - Removed `.gitmodules` entries and deleted `vendor/lemur` + `vendor/testez` git submodules
  - Removed `Tests/Lemur/` smoke runner/spec and eliminated Lemur lane from `run_tests.sh`
  - Updated CI checkout in `.github/workflows/build.yml` to stop fetching submodules
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

- [x] Add startup diagnostics/logging standards for Roblox Studio issue triage (service/module load boundaries + key dependency resolution points)
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
- [x] Expand WorldEventService with diverse event pool, random rotation, and buff system
  - Added `src/Shared/Definitions/WorldEventDefinitions.luau` with 6 events (Community Festival, Builder's Bazaar, Tenant Appreciation Week, Craft Fair, Property Showcase, Neighborhood Cleanup) across 6 distinct kinds
  - Each event has gameplay buffs: XPMultiplier, CashMultiplier, CraftSpeedMultiplier, ChoreRewardMultiplier, TipMultiplier
  - Rewrote `src/Server/Services/WorldEventService.luau` with random event selection, no-repeat logic (avoids back-to-back same event), injectable clock/RNG for testing, and buff query API (`GetBuffMultiplier`, `GetActiveBuffs`, `GetActiveEvent`)
  - Updated `src/Network/WorldEventPackets.luau` to include buff payload in state snapshots
  - Updated `src/Client/Modules/WorldEventController.luau` with `GetBuffMultiplier`, `GetActiveBuffs`, `GetActiveEvent` for client-side buff display
  - Added `Tests/Specs/WorldEventSpec.lua` with 39 behavioral + structural tests
  - Validation: `./run_tests.sh` (713 successes, 0 failures)
- [x] Iteration 10 review sweep: fix WorldEventService active-event mutation leak
  - Fixed `src/Server/Services/WorldEventService.luau` so `GetActiveEvent()` returns a defensive copy instead of internal mutable state
  - Added regression test in `Tests/Specs/WorldEventSpec.lua` to verify callers cannot mutate live buff multipliers via returned event table
  - Validation: `./run_tests.sh` (714 successes, 0 failures)
- [x] Iteration 7 feature: build client-side QuestUI (quest panel with filter bar, objective progress, start/claim actions)
  - Added `src/Client/UserInterface/QuestUI.luau` — scrollable quest panel with All/Active/Available/Done filter tabs, quest cards showing state-coloured accent bars, objective progress bars (for in_progress), reward summaries, and Start/Claim action buttons
  - Connects to `QuestPackets.QuestSnapshotUpdated` (server push) and `QuestPackets.QuestCompleted` (completion toast); fetches snapshot via `GetQuestSnapshot` on open
  - Wired `QuestsButton` into `MainHUD.luau` (same cloned-button pattern as Achievements/DailyRewards/Seasons)
  - Registered `QuestUI.Init()` in `Main.client.luau` startup sequence after `DailyRewardUI`
  - Added `Tests/Specs/QuestUISpec.lua` with 32 structural + behavioral tests; updated `SeasonalEventUISpec.lua` configureButtonVisuals assertion to accommodate the expanded button list
  - Validation: `./run_tests.sh` (771 successes, 0 failures)
- [x] Iteration 9 feature: build client-side WorldEventUI (event panel, buff display, countdown, MainHUD wiring)
  - Added `src/Client/UserInterface/WorldEventUI.luau` — scrollable overlay showing active event name/kind/description, buff rows (label + percentage), and a live countdown
  - Subscribes to `WorldEventController.StateChanged` for real-time updates without polling
  - Wired `WorldEventsButton` into `MainHUD.luau` (cloned-button pattern, added to configureButtonVisuals loop)
  - Registered `WorldEventUI.Init()` in `Main.client.luau` startup sequence after QuestUI
  - Added `Tests/Specs/WorldEventUISpec.lua` with 39 structural + behavioral tests covering API shape, MainHUD wiring, Main.client init ordering, and controller structural assertions
  - Validation: `./run_tests.sh` (810 successes, 0 failures)
- [x] Iteration 3 feature: wire QuestService into the game with network packets and server init
  - Added `src/Network/QuestPackets.luau` with 5 packets: `GetQuestSnapshot`, `StartQuest`, `ClaimQuest`, `QuestSnapshotUpdated` (push), `QuestCompleted` (push)
  - Updated `src/Server/Services/QuestService.luau` Init() to register packet handlers (`OnServerInvoke` for snapshot/start/claim), push snapshot updates to client after progress, and notify client on quest completion
  - Added `QuestService.Init()` and `DailyRewardService.Init()` to `src/Server/Main.server.luau` startup sequence (QuestService before DailyRewardService since DailyRewardService consumes it for daily challenges)
  - Added `Tests/Specs/QuestServiceWiringSpec.lua` with 21 structural + behavioral tests covering packet definitions, service wiring, server init ordering, and full quest lifecycle regression
  - Validation: `./run_tests.sh` (737 successes, 0 failures)

- [x] Iteration 10 review sweep: QuestService snapshot/UI/WorldEventUI fixes
  - Fixed QuestService to provide UI-friendly snapshots containing quest names, objectives, and rewards via `GetQuestSnapshot` and server pushes
  - Fixed QuestUI to parse packet response signatures correctly and re-enable action buttons after async calls
  - Throttled WorldEventUI countdown updates to once per second and cleared ticker on close
  - Added regression coverage for quest snapshot metadata + countdown throttle
