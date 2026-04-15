# Optimization Sprint (Iter 1–10)

A systematic performance improvement initiative targeting verified hotspots in the Life Simulator codebase.

## Guiding Principles

- **Preserve behavior**: All optimizations maintain existing shipped behavior; no feature removal.
- **Measurable checks**: Every optimization includes acceptance checks and regression tests.
- **Test-backed**: All changes verified via `./run_tests.sh` and `selene` linting.

## Hotspot Findings

| File | Issue | Status |
|------|-------|--------|
| `src/Client/Modules/MinimalPromptUI.luau` | Deprecated no-op module | ✅ Removed (Iter 1) |
| `src/Shared/Modules/*` | Redundant compatibility shims | ✅ Removed (Iter 2) |
| `src/Server/Services/WorldEventService.luau` | 30s polling loop | ✅ Next-expiry scheduling (Iter 3) |
| `src/Shared/Utilities/Debounce.luau` | Stackable wait loops | ✅ Single-wait optimization (Iter 4) |
| `src/Client/Modules/ClientResidentMovement.luau` | Per-frame heartbeat polling | ✅ Bounded backoff 0.05s (Iter 5) |
| `src/Server/Services/BuildService.luau` | Repeated action module lookup | ✅ Cached dispatch (Iter 6) |
| `src/Shared/Modules/PlotState.luau` | Redundant snapshot allocations | ✅ Incremental diffing (Iter 7) |
| `src/Server/Services/TenantService.luau` | Double iteration in mailbox prune | ✅ Single-pass O(N) (Iter 8) |
| Various UI files | Outdated `UDim2.new` patterns | ✅ Modernized (Iter 9) |

## Iteration Details

### Iter 1: Remove Unused MinimalPromptUI
**Goal**: Remove verified unused deprecated client module.

**Changes**:
- Deleted `src/Client/Modules/MinimalPromptUI.luau`
- Verified zero references via grep

**Verification**: `./run_tests.sh` (1332 successes), `selene` (0 errors, 0 warnings)

---

### Iter 2: Audit and Consolidate Dead Shims
**Goal**: Remove redundant `Shared/Modules` shims duplicating `Shared/Utilities`.

**Changes**:
- Removed `ActionBinder` shim
- Removed `ClickBinder` shim
- Consolidated to canonical `Shared/Utilities` implementations

**Verification**: Rojo tree builds successfully; tests pass.

---

### Iter 3: WorldEventService Scheduling Efficiency
**Goal**: Replace fixed 30s polling loop with next-expiry scheduling.

**Changes**:
- Added `_GetNextWaitSeconds` helper computing exact wait time to next event expiry
- Eliminated fixed `task.wait(30)` loops
- Added 4 schedule-math specs + 1 structural test

**Impact**: Eliminates unnecessary wakeups; server only wakes when events actually change.

**Verification**: 1337 successes; behavior-identical event cadence.

---

### Iter 4: Debounce Loop Backoff Review
**Goal**: Reduce Debounce wait loop wakeups without changing behavior.

**Changes**:
- Optimized `Debounce.WaitUntilInactive` to avoid extra wakeups
- Preserved exact debounce semantics
- Added `DebounceSpec` structural timing checks

**Verification**: All existing debounce call sites continue to resolve correctly.

---

### Iter 5: ClientResidentMovement Seat Loop Backoff
**Goal**: Reduce per-frame polling by adding bounded retries.

**Changes**:
- Added `SEAT_CHECK_INTERVAL = 0.05` constant
- Replaced `Heartbeat:Wait()` with `task.wait(SEAT_CHECK_INTERVAL)`
- Applied to `waitForSeatAvailability` and `attemptSeat` functions
- Added `SeatAcquisitionSpec` (5 structural checks)

**Impact**: ~3x fewer wakeups (from ~60/sec to 20/sec).

**Verification**: 1344 successes; NPC seating still succeeds under normal conditions.

---

### Iter 6: BuildService Action Dispatch Cache
**Goal**: Reduce repeated action lookup overhead.

**Changes**:
- Cached action module resolution after first `require`
- Added dispatch helpers for cached lookups
- Added `BuildServiceActionCacheSpec` structural checks

**Verification**: No behavior changes in placement outcomes.

---

### Iter 7: PlotState Snapshot Diff Optimization
**Goal**: Reduce redundant snapshot allocations.

**Changes**:
- Incremental diffing in `PlacementDelta` handler
- Added `removeKeyFromSnapshot` and `addItemToSnapshot` helpers
- Added `LevelSnapshotBuilder.ApplyItemDelta`
- `PacketProcessor` returns `oldRecord` as 3rd value for change detection
- Added `LevelSnapshotIncrementalSpec` (13 structural checks)

**Impact**: Avoids deep clone when no changes; significantly reduces GC pressure.

**Verification**: Client `PlotStateStore` remains in sync.

---

### Iter 8: TenantService Mailbox Prune Efficiency
**Goal**: Tighten mailbox pruning loops and avoid double iteration.

**Changes**:
- Single-pass filter accumulating `totalIncome` and collecting `expiredIds`
- Reduced complexity from O(N²) to O(N)
- Deferred expired lease removal to avoid table mutation during `pairs()`
- Added `MailboxPruneSpec` (14 checks: structural + income equivalence + partition + end-to-end)

**Impact**: Linear-time pruning for large mailbox sizes.

**Verification**: Mailbox data still replicates correctly.

---

### Iter 9: Lint/Format Hotspot Sweep
**Goal**: Resolve selene warnings and modernize code style.

**Changes**:
- Converted 22 `UDim2.new(...)` calls to `UDim2.fromOffset()` or `UDim2.fromScale()`
- Files cleaned: `BillUI`, `CraftingSkillPanel`, `DailyRewardUI`, `EmoteUI`, `NotificationInboxUI`, `SeasonalEventUI`, `StorageInventoryUI`, `WorldEventUI`

**Verification**: `selene src/` returns 0 errors, 0 warnings.

---

### Iter 10: Full Sweep (In Progress)
**Goal**: Complete test suite, docs, and changelog.

**Status**:
- ✅ `./run_tests.sh` exits 0 (1375 successes)
- ✅ `selene src/` exits 0 (0 errors, 0 warnings)
- ✅ `CHANGELOG.md` updated with Iter 1–9 deliverables
- ✅ This documentation page created
- ⏳ Pending: Final review and PR submission

## Test Results

```
1375 successes / 0 failures / 0 errors / 0 pending : 0.276861 seconds
```

## Regression Checks Passed

- Client startup requires unchanged
- Rojo tree builds successfully
- World events rotate in same order/timing
- Debounce semantics preserved
- NPC seating succeeds under normal conditions
- Build actions resolve for all known types
- Client PlotStateStore sync maintained
- Mailbox data replicates correctly
- No runtime warnings from changed files

## Next Steps

Iter 10 completion: Submit PR with full optimization sprint changelog and documentation.

---

*Last updated: 2026-03-15*
