# TODO - Life-Simulator-Game

Sprint Roadmap (10 goals)
Status: refresh for Iteration 9 (2026-03-02)

1. [x] Add achievement bulk-claim action.
   Acceptance:
   - Achievement service exposes `ClaimAllAchievements` and a network packet.
   - Achievement UI shows a Claim All button with disabled state when none are claimable.
   - Tests cover reward totals and idempotency.

2. [x] Surface daily challenge status in DailyReward UI.
   Acceptance:
   - `DailyRewardPackets` status schema includes `DailyChallenge` fields (DayId, QuestId, AssignedAt, QuestState).
   - `DailyRewardUI` renders the current daily challenge with quest name and state.
   - `DailyRewardSpec` verifies daily challenge payload wiring.

3. [x] Add quest daily challenge rotation regression tests.
   Acceptance:
   - New spec verifies quest rotation across consecutive UTC days.
   - Ensures repeatable quest assignment remains consistent across resets.

4. [ ] Build Notification inbox panel.
   Acceptance:
   - New client UI lists notifications from `NotificationPackets.StateSnapshot` and deltas.
   - Unread/read state is reflected in the list and can be toggled locally.
   - Manual smoke: opening inbox shows latest 20 notifications in order.

5. [ ] Add category filters to Achievement UI.
   Acceptance:
   - UI provides category filter tabs (All + per-category).
   - Filtered list updates counts and preserves claim button behavior.
   - `AchievementUISpec` covers filter selection and empty states.

6. [ ] Add active quest detail drawer in Quest UI.
   Acceptance:
   - Quest UI shows selected quest objectives, rewards, and state.
   - Drawer updates on `QuestSnapshotUpdated` without reopening.
   - `QuestUISpec` covers rendering and update behavior.

7. [ ] Add tenant review filters by rating.
   Acceptance:
   - Reviews UI supports filtering to 5/4/3+ star ratings.
   - Filter state persists while UI is open.
   - Manual smoke: filter reduces visible rows correctly.

8. [ ] Add mailbox income breakdown tooltip.
   Acceptance:
   - Mailbox packets include per-tenant income breakdown in summary payload.
   - Mailbox HUD shows tooltip with per-tenant contributions and next payout time.
   - Tests verify breakdown totals and payload shape.

9. [ ] Add seasonal event reward summary panel.
   Acceptance:
   - Seasonal status payload includes pending rewards count and next milestone label.
   - Seasonal UI shows pending counts and next milestone progress.
   - `SeasonalEventUISpec` covers summary rendering.

10. [ ] Add world event tips cooldown safeguards.
    Acceptance:
    - Tip selection enforces a cooldown per tip.
    - `WorldEventTipsSpec` covers cooldown rotation behavior.
