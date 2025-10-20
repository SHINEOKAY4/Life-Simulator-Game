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

- Version `GigState` for future slot count tuning.
- Guard against multi-session gig slot exhaustion exploits.
- Ensure autosave captures pending payouts and outstanding fees.

## Tech Debt / Observations

- Replace legacy `Occupation` references with `CurrentCareerId` across services.
- Audit ResidentAutonomy fallback actions once career scheduling lands.
- Add unit tests or assertions for CurrencyService when applying modifiers.
-- Need to Fix problem with hunger not being able to interrupt collapsed resident while >= 4 percent energy. Only problem is the resident physically does not get up but need seem to interupt it backend.