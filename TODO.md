# TODO - Life-Simulator-Game

Sprint Roadmap (Iter 1-10)
Status: Iter 1 drafting reset (2026-03-03)

Guiding Principles
- Preserve current shipped behavior; prioritize reliability, clarity, and test coverage.
- Plan-first: each iteration delivers measurable stability, tooling, or UX improvements.
- Acceptance checks are required for completion sign-off.

1) Iter 1 - Sprint Baseline + Observability
Goal: establish a clean baseline, system visibility, and clear boundaries for feature work.
Acceptance Checks:
- Repo health is documented (tests, lint, docs build commands verified in README/docs).
- Startup ordering and dependency graph are captured in TODO context for future tasks.
- Key system contracts (Plot/Build/Tenant/Quest/Reward/Network) are summarized in TODO.

2) Iter 2 - Plot/Build Runtime Stability
Goal: reduce plot/build runtime drift and improve snapshot correctness.
Acceptance Checks:
- Placement delta flow is verified end-to-end (server send -> client apply -> UI refresh).
- PlotState room sync behavior is documented and validated with tests.
- No stale TODOs related to placement/plot remain in code.

3) Iter 3 - Tenant Loop Reliability
Goal: harden tenant offers, room assignment, mailbox balance, and lease transitions.
Acceptance Checks:
- Room readiness and assignment paths have explicit tests for eviction/reassign edge cases.
- Mailbox income summary and collection flows have deterministic test coverage.
- Tenant UI shows accurate occupancy and diagnostics under all room states.

4) Iter 4 - Reward Systems Consistency
Goal: ensure daily rewards, seasonal events, and achievements share consistent reward semantics.
Acceptance Checks:
- Reward claim flows (daily + seasonal + achievements) are idempotent and tested.
- Reward summary/preview UI matches server payload shape.
- Reward packets have explicit schema validation in specs.

5) Iter 5 - Quest System UX + Sync
Goal: improve quest UI clarity and correctness under live updates.
Acceptance Checks:
- Quest detail drawer reflects server updates without reopening.
- Quest snapshots remain consistent across login/session refresh.
- Quest UI specs cover selection, update, and completion states.

6) Iter 6 - Notification/Inbox Expansion
Goal: unify notification delivery, inbox filtering, and read/unread states.
Acceptance Checks:
- Notification queue/history/mark-read are reflected in inbox UI.
- Inbox shows correct unread counts after batch changes.
- Notification packet payloads validated by tests.

7) Iter 7 - Economy/Billing Clarity
Goal: stabilize billing/currency updates and surface clear player feedback.
Acceptance Checks:
- Billing cycle transitions are tested for timing boundaries.
- Currency deltas track sources consistently across services.
- Billing UI shows accurate state after reconnect.

8) Iter 8 - Performance + Memory Hygiene
Goal: reduce hot-path allocations and runtime churn without feature removal.
Acceptance Checks:
- High-frequency loops have targeted optimizations (profiling-backed or measured).
- Client caches invalidate correctly without excessive churn.
- No new lint warnings; tests remain green.

9) Iter 9 - Test Coverage + Regression Sweep
Goal: fill gaps across core loops and prevent regressions in key systems.
Acceptance Checks:
- New specs cover edge cases for plot/build/tenant/reward/quest systems.
- Regression tests added for any recurring issues.
- Tests pass with no flaky cases.

10) Iter 10 - Release Readiness + Cleanup
Goal: consolidate documentation, deprecations, and final QA readiness.
Acceptance Checks:
- Docs updated for any public API/system changes.
- Deprecated or dead code removed only if fully verified.
- Final smoke passes for core UX flows (plot claim, build, tenant, rewards, quests).
