# TODO - Life-Simulator-Game

Optimization Sprint Roadmap (Iter 1–10, refreshed 2026-03-03)
Status: Iter 3 complete — WorldEventService next-expiry scheduling; tests and selene green.

Guiding Principles
- Preserve all shipped behavior; no feature removal.
- Optimization work must be backed by measurable checks.
- Acceptance checks and regression checks are required before marking a goal done.

Hotspot Findings (Verified)
- src/Client/Modules/MinimalPromptUI.luau is a deprecated no-op and unused.
- src/Shared/Modules/* are compatibility shims that duplicate Shared/Utilities.
- src/Server/Services/WorldEventService.luau uses a 30s polling loop.
- src/Shared/Utilities/Debounce.luau uses wait loops that can stack.
- src/Client/Modules/ClientResidentMovement.luau uses heartbeat polling loops.

---

1) [x] Iter 1 Goal - Remove Unused MinimalPromptUI
Goal: remove verified unused deprecated no-op client module with no references.
Acceptance Checks:
- src/Client/Modules/MinimalPromptUI.luau removed.
- Grep confirms no references remain.
- ./run_tests.sh passes.
- selene src/ reports 0 errors, 0 warnings.
Regression Checks:
- Client startup requires remain unchanged (no missing module errors).

2) [x] Iter 2 Goal - Audit and Consolidate Dead Shims
Goal: verify and reduce redundant Shared/Modules shims where no callers exist.
Acceptance Checks:
- Identify shim modules with zero references.
- Remove at least one verified-unused shim.
- Grep confirms removed shims have no references.
- ./run_tests.sh passes; selene clean.
Regression Checks:
- Rojo tree still builds with Shared/Utilities as canonical.

3) [x] Iter 3 Goal - WorldEventService Scheduling Efficiency
Goal: replace fixed 30s polling loop with next-expiry scheduling logic.
Acceptance Checks:
- WorldEvent rotation schedule computed from next expiry timestamp.
- No change to event cadence or randomness.
- Add spec or inline test for schedule math (no Roblox deps).
- ./run_tests.sh passes; selene clean.
Regression Checks:
- World events still rotate in same order and timing windows.

4) [x] Iter 4 Goal - Debounce Loop Backoff Review
Goal: reduce Debounce wait loop wakeups without changing behavior.
Acceptance Checks:
- Debounce wait loop uses a single wait when possible.
- Zero behavioral changes in debounce semantics.
- Add spec for debounce timing math (no Roblox deps).
- ./run_tests.sh passes; selene clean.
Regression Checks:
- Existing debounce call sites continue to resolve.

5) [x] Iter 5 Goal - ClientResidentMovement Seat Loop Backoff
Goal: reduce per-frame polling by adding bounded retries/backoff.
Acceptance Checks:
- Seat acquisition loop caps heartbeat retries or backs off.
- No change to final seating outcome.
- Add structural test or inline assert for retry bounds.
- ./run_tests.sh passes; selene clean.
Regression Checks:
- NPC seating still succeeds under normal conditions.

6) [x] Iter 6 Goal - BuildService Action Dispatch Cache
Goal: reduce repeated action lookup overhead by caching action modules.
Acceptance Checks:
- Action module lookup cached after first require.
- No behavior changes in placement outcomes.
- Add spec covering action resolution (structural).
- ./run_tests.sh passes; selene clean.
Regression Checks:
- Build actions still resolve for all known action types.

7) [x] Iter 7 Goal - PlotState Snapshot Diff Optimization
Goal: reduce redundant snapshot allocations in PlotState.
Acceptance Checks:
- Snapshot diffing avoids deep clone when no changes.
- Behavior matches previous snapshot outputs.
- Add spec covering unchanged snapshot path.
- ./run_tests.sh passes; selene clean.
Regression Checks:
- Client PlotStateStore remains in sync.

8) [ ] Iter 8 Goal - TenantService Mailbox Prune Efficiency
Goal: tighten mailbox pruning loops and avoid double iteration.
Acceptance Checks:
- Pruning uses single-pass filter.
- Mailbox contents unchanged after prune.
- Add spec to validate prune equivalence.
- ./run_tests.sh passes; selene clean.
Regression Checks:
- Mailbox data still replicates correctly.

9) [ ] Iter 9 Goal - Lint/Format Hotspot Sweep
Goal: resolve any new selene warnings and clean hot files.
Acceptance Checks:
- selene src/ returns 0 errors, 0 warnings.
- Targeted files remain behavior-identical.
- ./run_tests.sh passes.
Regression Checks:
- No runtime warnings from changed files.

10) [ ] Iter 10 Goal - Full Sweep: Tests + Docs + Changelog
Goal: run complete test suite and selene, update docs and changelog.
Acceptance Checks:
- ./run_tests.sh exits 0 with no failures.
- selene src/ exits 0 with 0 errors and 0 warnings.
- docs/content/ updated with optimization sprint notes.
- CHANGELOG.md entry added for Iter 1–9 deliverables.

Review Log
- Iter 1: origin/main already up to date; removed deprecated MinimalPromptUI;
  ./run_tests.sh 1332 successes; selene 0 errors, 0 warnings.
- Iter 2: removed unused Shared/Modules ActionBinder + ClickBinder shims;
  ./run_tests.sh clean; selene 0 errors, 0 warnings.
- Iter 3: replaced fixed 30s poll with next-expiry scheduling in WorldEventService.Init();
  added _GetNextWaitSeconds helper + 4 schedule-math specs + 1 structural test;
  ./run_tests.sh 1337 successes; selene 0 errors, 0 warnings.
- Iter 4: optimized Debounce.WaitUntilInactive to avoid extra wakeups while preserving semantics;
  added DebounceSpec structural timing checks;
  ./run_tests.sh (see latest run); selene 0 errors, 0 warnings.
- Iter 5: added SEAT_CHECK_INTERVAL=0.05 to ClientResidentMovement; replaced Heartbeat:Wait() with
  task.wait(SEAT_CHECK_INTERVAL) in waitForSeatAvailability and attemptSeat (~3x fewer wakeups);
  added SeatAcquisitionSpec (5 structural checks); ./run_tests.sh 1344 successes; selene 0 errors, 0 warnings.
- Iter 6: cached BuildService action module resolution with dispatch helpers; added BuildServiceActionCacheSpec
  structural checks for cached resolution; ./run_tests.sh (see latest run); selene 0 errors, 0 warnings.
- Iter 7: incremental PlotState snapshot diff in PlacementDelta handler; added removeKeyFromSnapshot +
  addItemToSnapshot helpers and LevelSnapshotBuilder.ApplyItemDelta; PacketProcessor returns oldRecord as
  3rd value; added LevelSnapshotIncrementalSpec (13 structural checks); selene 0 errors on changed files.
