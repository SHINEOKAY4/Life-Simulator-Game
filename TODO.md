# TODO - Life-Simulator-Game

Sprint Roadmap (Iter 2–11, refreshed 2026-03-03)
Status: Iter 5 review sweep complete — tests + selene clean

Review Log
- Iter 5: merged origin/main; gh auth failed (treated as no open issue);
  ran ./run_tests.sh and selene src (0 errors, 0 warnings); no regressions found.

Guiding Principles
- Preserve all shipped behavior; no feature removal.
- Each goal delivers measurable test coverage, stability, or clarity.
- Acceptance checks are required before marking a goal done.

---

1) [x] Goal 1 - BillingCalculator Behavioral Spec
Goal: add a busted spec that exercises the four billing formulas with
      inline-replicated constants (no Roblox deps), including edge cases.
Acceptance Checks:
- Tests/Specs/BillingCalculatorSpec.lua exists and runs under busted.
- CalculatePropertyTax: zero cells, one cell, many cells all match formula.
- CalculateElectricity: zero kWh, fractional kWh match formula.
- CalculateWater: zero residents, many residents match formula.
- CalculateInternet: all four tiers (None/Basic/Standard/Premium) return correct costs.
- Unknown tier returns 0.
- All spec assertions pass; no lint warnings.

2) [x] Goal 2 - CurrencyService Validation Spec
Goal: test the parameter-validation guards (EnsurePositiveInteger, AssertParameters)
      with inline stubs so no Roblox runtime is required.
Acceptance Checks:
- Tests/Specs/CurrencyServiceValidationSpec.lua exists.
- Negative amounts, NaN, Inf, non-integer, and zero are each tested.
- Valid inputs pass without error.
- Error messages match expected substrings.

3) [ ] Goal 3 - ChoreService Spec
Goal: structural + light behavioral tests for ChoreService: chore-record shape,
      ID uniqueness, trash vs repair routing, reward semantics.
Acceptance Checks:
- Tests/Specs/ChoreServiceSpec.lua exists.
- Source-level assertions confirm ActiveChores usage, ID generation, handler dispatch.
- Reward amount range is validated in at least one test.
- Spec passes cleanly under busted.

4) [ ] Goal 4 - WeatherService Spec
Goal: test the weather-selection weight logic (replicated inline) and state
      structure for all four seasons.
Acceptance Checks:
- Tests/Specs/WeatherServiceSpec.lua exists.
- pickWeatherForSeason inline replica produces only valid weather types per season.
- Spring, Summer, Autumn, Winter each tested independently.
- Season cycling order (Spring→Summer→Autumn→Winter→Spring) asserted structurally.
- Spec passes cleanly.

5) [ ] Goal 5 - CraftingService Job-Lifecycle Spec
Goal: extend coverage beyond skill-panel math to include job record shape,
      skill-requirement validation paths, and ingredient deduction logic.
Acceptance Checks:
- Tests/Specs/CraftingJobSpec.lua exists.
- Job shape (JobId, RecipeId, StartedAt, EndsAt, ConsumedIngredients) verified.
- Skill-requirement gates confirmed structurally in source.
- Ingredient consumption logic paths asserted (structural).
- Spec passes cleanly.

6) [ ] Goal 6 - BillingService Cycle Spec
Goal: test billing cycle boundary semantics: due-date calculation, grace-period
      threshold, power-outage trigger wiring, payment settlement paths.
Acceptance Checks:
- Tests/Specs/BillingServiceCycleSpec.lua exists.
- CycleDurationSeconds / GracePeriodSeconds boundary math validated inline.
- Source-level assertions confirm PowerOutageAttribute wiring.
- Spec passes cleanly.

7) [ ] Goal 7 - ResidentService Spec
Goal: structural + behavioral tests for ResidentService: occupancy tracking,
      lease-state machine, eviction trigger conditions.
Acceptance Checks:
- Tests/Specs/ResidentServiceSpec.lua exists.
- Occupancy count math tested inline.
- Source-level assertions confirm eviction dispatch path.
- Lease-state transitions asserted structurally.
- Spec passes cleanly.

8) [ ] Goal 8 - ReviewService Rating Logic Spec
Goal: inline-replicate the rating formula from ReviewService and assert penalty
      branches for missed payments, trash count, and temperature offset.
Acceptance Checks:
- Tests/Specs/ReviewRatingSpec.lua exists.
- Base rating range (3–5) asserted.
- Missed-payment penalty lowers rating correctly.
- Trash penalty is clamped at rating ≥ 1.
- Temperature comfort offset branches tested.
- Spec passes cleanly.

9) [ ] Goal 9 - ComfortRating Spec
Goal: test the two pure functions in ComfortRating that have no Roblox deps:
      calculateTemperatureScore (inline) and ScoreToStars / GetScoreNote.
Acceptance Checks:
- Tests/Specs/ComfortRatingSpec.lua exists.
- Ideal temperature band returns score ≥ 60 (inline formula verified).
- Extreme temperatures return score approaching 0.
- ScoreToStars: 0→0 stars, 100→5 stars, 50→2.5 stars.
- GetScoreNote: each threshold band returns correct string.
- Spec passes cleanly.

10) [ ] Goal 10 - Full Sweep: Test Green + Lint Clean + Docs Refresh
Goal: run complete test suite and selene, fix any regressions, and update
      docs index to reference all new specs added in Goals 1–9.
Acceptance Checks:
- ./run_tests.sh exits 0 with no failures.
- selene src/ exits 0 with 0 errors and 0 warnings.
- docs/content/ reflects the new specs (at minimum one docs update).
- CHANGELOG.md entry added for Goals 1–9 deliverables.
