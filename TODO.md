# Life Simulator TODO Backlog

## Career Service

- Implement resident shift scheduler (clock-in/out, lateness tracking).
- Award payouts on shift completion using mood/streak/momentum multipliers.
- Persist and decay `CareerStreak` and `MomentumExpireClock` values.
- Surface analytics events for CareerShiftStart and CareerShiftEnd.

## Gig Service

- Track active gig UI state (progress timer, tier feedback, payout toast).
- Consume gig momentum boost when the next career shift starts.
- Add stamina gating hooks so rest/eating replenishes gig capacity.

## Economy & Billing

- Design recurring property tax/plot upkeep drain (per in-game day).
- Add maintenance costs for powered stations with shutoff escalation.
- Expose billing reminders and past-due states to the client HUD.

## UI & Player Feedback

- Show Career vs Gig tabs with requirement checklists and cooldowns.
- Display upcoming paydays, streak multipliers, and unpaid bills.
- Add gig result summary panel (tier, earnings, cooldown timer).

## Data & Persistence

- Version `WorldEventState` schema for future rotation tuning.
- Guard against multi-session world event boost exploits.
- Ensure autosave captures pending payouts and outstanding fees.

## Tech Debt / Observations

