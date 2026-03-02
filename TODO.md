# TODO - Life-Simulator-Game

Sprint Roadmap (10 goals)
Status: refresh for Iteration 8 (2026-03-02)

1. [x] Add Daily + Seasonal achievement badges in BadgeService.
   Acceptance:
   - BadgeService includes Daily and Seasonal category entries with unique icons/colors.
   - BadgeServiceSpec covers Daily/Seasonal categories and updated totals.
   - Achievement UI renders Daily/Seasonal badges (manual smoke).

2. [x] Add NotificationPackets and server-to-client push for NotificationService.
   Acceptance:
   - `src/Network/NotificationPackets.luau` defines snapshot and delta packets.
   - `NotificationService.Init` registers remotes and pushes queue updates.
   - Client listens and renders toasts via `src/Client/UserInterface/Notification.luau`.

3. [x] Add achievement stats summary packet + UI widget.
   Acceptance:
   - `AchievementPackets` exposes stats summary request/response.
   - `AchievementService.GetStatsSummary` is wired to the packet.
   - `AchievementUI` shows completion percent and per-category counts.

4. [x] Add mailbox income summary to the HUD.
   Acceptance:
   - Mailbox packets expose balance, income rate, and next rent tick.
   - UI shows mailbox balance + next payout time.
   - Tests cover income rate calculations and packet payloads.

5. [ ] Add tenant review history UI.
   Acceptance:
   - `ReviewPackets` supports fetching and pushing new reviews.
   - UI lists the last 20 reviews with rating, comment, and timestamp.
   - New review events update the UI without re-open.

6. [ ] Add crafting skill progression panel.
   Acceptance:
   - Crafting packets include skill level/XP summary per skill.
   - UI shows per-skill progress bars and next-level XP.
   - Craft completion updates the panel in real time.

7. [ ] Add seasonal buff detail tooltip.
   Acceptance:
   - Seasonal packets include active buff details and multipliers.
   - UI shows active multipliers with descriptions.
   - Buffs refresh on season change and challenge completion.

8. [ ] Add daily reward streak warning.
   Acceptance:
   - Daily reward packets include time-to-expire and grace window info.
   - UI shows countdown warning inside the grace window.
   - Tests cover warning threshold logic.

9. [ ] Add achievement bulk-claim action.
   Acceptance:
   - Achievement service exposes `ClaimAll` for unlocked unclaimed items.
   - UI button claims all and updates counts in-place.
   - Tests cover reward totals and idempotency.

10. [ ] Add quest daily challenge rotation regression tests.
    Acceptance:
    - New spec covers daily challenge rotation across days.
    - Ensures repeatable quest assignment stays consistent.
