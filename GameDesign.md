# Life Simulator - Game Design Document (GDD)

**Version:** 0.65 (Career/Gig split)
**Platform:** Roblox (multiplayer servers; each player manages their own resident)
**Tone:** Kid-safe, wholesome, transparent

---

## 1) Overview

**High Concept:** Start a life, make everyday choices, grow stats, earn honestly, and progress into better roles.
**Player Fantasy:** I plan a life, build good habits, and see the results.
**Core Identity:** Clarity over grind; long-term identity (jobs, habits, home); solo-friendly systems.

---

## 2) Pillars

- **Everyday Choices Matter** - Eat, rest, work, train; consistency beats spam.
- **Clarity Over Grind** - Visible requirements, fair consequences, capped modifiers.
- **Long-Term Identity** - Roles, habits, and a home you shape over time.
- **Solo-Feasible** - Modular content, low asset overhead, predictable load.

---

## 3) Current Build Snapshot (as of MVP prep)

- **Plot claim & build loop** - Claimable plots with guided camera selector, chunk unlock flow, and grid-based placement for floors, walls, and station furniture; move/rotate/destroy actions run through server validation with placement previews and delta replication.
- **Resident roster & persistence** - DataStore-backed household state loads multiple residents per player, spawns gendered rigs on owned plots, and mirrors core need values to attributes for UI.
- **Needs & autonomy** - Hunger, Energy, Hygiene, Social, and Fun decay on the server; resident AI evaluates available stations, applies moodlets, and falls back to ground rest or roaming when blocked.
- **Direct actions** - Manual override pipeline (beds, kitchens, social tables, hygiene fixtures, fun spots) handles occupancy, cancel tokens, and completion signals so players can steer residents moment-to-moment.
- **Player-facing UI** - Build catalog panels, object selector plus needs HUD, and chunk highlights for expansion; day/night lighting syncs to server time.
- **Server authority & networking** - PlotService/BuildService own placement, station state, and rate-limited remotes; WorldPlacer and delta packets keep client worlds in lockstep.

---

## 4) Core Loop

1. Check **Needs** (Hunger, Energy) and **Mood**.
1. Decide on **Active Play (Player Gig)** vs **Passive Care (Resident Career)**.
1. Run the action: gigs become quick skill checks for the player, careers become autonomous shifts for residents.
1. Gig performance grants burst cash; career reliability builds long-term income and unlocks higher tiers.
1. Repeat while keeping residents prepared so their careers stay productive and the player has stamina for gigs.

---

## 5) Progression Spine

- **Stats:** `IntelligenceLevel`, `FitnessLevel`, `DisciplineLevel`, `SocialLevel`; plus `FitnessPoints` (sub-currency).
- **Eligibility:** Careers have explicit stat gates; higher tiers pay better.
- **Mood Effects:** `payoutMultiplier = 1 + clamp((Mood - 50) / 50, -0.15, 0.15)`.
- **Consequences Ladder:** Lateness or poor effort leads to time-boxed debuffs (no hard fails).

---

## 6) Systems Detail

### 6.1 Needs & Mood

- **Drift (per real-time minute, server):** Hunger +0.5..+1.0, Energy -0.25..-0.5 (tunable).
- **Actions:**
  - **Eat:** Hunger -40% to -55% (module quality modifies).
  - **Rest:** Energy +25% to +40% (bed quality modifies).
  - **Workout:** Energy -20%, Hunger +15%, FitnessPoints +X.
- **Mood (0-100):** recent needs balance, punctuality, successful shifts; max effect 15% clamp.

### 6.2 Work Split: Careers vs. Gigs

- **Careers (Resident Passive Income):** shift-based roles handled by resident autonomy. Players hire residents into a career, prep them (needs, hygiene, mood, stat training), and the AI manages clock-in/clock-out. Career payouts scale with preparation quality, streak history, plot upgrades, and any active Momentum buffs.
- **Gigs (Player Active Income):** short, instanced challenges the player avatar runs directly. Each gig shares a timed skill-check framework (prompt accuracy, rhythm, or pattern matching) but swaps cosmetic theming and stat biases per gig. Performance tiers (Bronze/Silver/Gold) adjust the final multiplier.
- **Scheduling:** Residents attempt one career shift per in-game day automatically; the player gets `DailyGigSlots` (default 3) that refresh at dawn. Completing a gig spends stamina which recovers via player rest/eating to pace repeat runs.
- **Rewards Interaction:** Career pay deposits at shift end into household funds. Successful gigs award immediate cash plus a short-lived "Momentum" buff that boosts the next resident career payout by 5 to 10% if they clock in within one in-game hour.
- **Failure States:** Residents who arrive under-prepped still finish the shift but earn reduced payout; repeated failures trigger temporary mood debuffs. Failed gigs simply consume the slot until its cooldown expires.

**Starter tuning (tunable):**

| Career | Requirements | Base Pay/min | Shift Length | Notes |
| --- | --- | ---: | ---: | --- |
| Cafe Crew | Discipline >= 1 | 0.30 | 30 | Intro passive income |
| Office Assistant | Intelligence >= 2, Discipline >= 1 | 0.40 | 35 | Filing loop |
| Junior Programmer | Intelligence >= 4, Discipline >= 2 | 0.60 | 40 | Late unlock |
| Fitness Trainer | Fitness >= 4, Social >= 2 | 0.57 | 35 | Mood-sensitive |

| Gig | Stat Bias | Base Payout | Cooldown | Notes |
| --- | --- | ---: | ---: | --- |
| Courier Sprint | Fitness | $28 +/- 6 | 8 min | Rhythm prompts |
| Cafe Pop-Up | Social | $24 +/- 4 | 6 min | Conversation timing |
| Debug Jam | Intelligence | $32 +/- 8 | 10 min | Pattern matching |

**Payout (career):** `pay = basePerMinute * shiftMinutes * moodMultiplier * streakMultiplier * momentumBonus`  
**Payout (gig):** `payout = (base +/- variance) * performanceMultiplier`.

### 6.3 Planner

- **Modes:** Auto or Manual.
- **Manual:** Player sets **AM** and **PM** intents.
- **Auto:** Server picks based on needs and job schedule.
- **Cooldowns:** Prevent mid-shift swaps.

### 6.4 Plot Building (Phase-in, low scope)

- **Grid, snap-to-cell** plot per player; **modules** (no freeform rooms in MVP).
- Launch catalog: **Bed Corner, Kitchenette, Study Desk, Gym Corner, Shower, Wardrobe**.
- Effects are single, non-stacking quality modifiers.
- Actions: **Place, Move, Rotate, Remove, Sell** with server validation and compact saves.

---

## 7) Economy

### 7.1 Currencies and Values

- **Cash:** earn from careers/gigs; spend on upgrades and modules.
- **Stats:** gate careers; gained via actions and streaks.
- **FitnessPoints:** sub-currency for fitness upgrades (optional MVP).
- **No premium pay-to-win** (cosmetics only later).

### 7.2 Economy JSON (MVP)

```json
{
  "currencies": ["Cash"],
  "stats": ["IntelligenceLevel", "FitnessLevel", "DisciplineLevel", "SocialLevel"],
  "derived": ["Mood", "Charisma"],
  "earn": {
    "gig": {"base": [20, 35], "multMood": true},
    "career": {
      "basePerMinute": {
        "CafeCrew": 0.3,
        "OfficeAssistant": 0.4,
        "JuniorProgrammer": 0.6,
        "FitnessTrainer": 0.57
      },
      "multMood": true
    }
  },
  "costs": {
    "intUpgradeBase": 100,
    "intUpgradeStep": 75,
    "plotModules": {
      "BedCorner": 150,
      "Kitchenette": 180,
      "StudyDesk": 120,
      "GymCorner": 200,
      "ShowerBooth": 160,
      "Wardrobe": 80
    }
  },
  "modifiers": {
    "moodClamp": 0.15,
    "bedEnergyBonus": 0.15,
    "kitchenHungerBonus": 0.15
  }
}
```

---

## 8) UI Surfaces

### 8.1 Global HUD

- **Top Bar:** title, global cash, day/part-of-day, navigation (Careers, Activities, Customize, Settings).
- **Lives Roster:** scrollable cards; select active resident.
- **Selected Mini Panel:** name, stage, Hunger/Energy bars, **Inspect** button.
- **Notifications Anchor:** stack for toasts and gig results.

### 8.2 Modals

- **Career Selection:** shows roles, stat gates, pay preview; **Hire/Quit**.
- **Inspector:** name, stats, needs, mood, career, quick actions.
- **Customize:** presets plus rename (filtered).
- **Build Catalog (later):** list to ghost preview to place/move/sell.

---

## 9) Technical Design

### 9.1 Server/Client

- **Server:** career eligibility, hires, payouts, needs drift, action execution, build validation.
- **Client:** input, previews, UI, cosmetics.
- **Remotes:** `RequestOverrideAction`, `CareerSelect`, `CareerQuit`, `GigRequestStart`, `GigSubmitScore`, `BuildRequestPlace`, `BuildRequestMove`, `BuildRequestRotate`, `BuildRequestRemove`, `BuildRequestSell`.
- **Resident Attributes:** Cash, HungerPercent, EnergyPercent, Mood, IntelligenceLevel, FitnessLevel, DisciplineLevel, SocialLevel, CurrentCareerId, CurrentGigPhase, LastSpeechText, LastSpeechClockUnix, PlanMode, PlannedMorningTask, PlannedEveningTask.

### 9.2 Data & Save

- **PlayerData:** Lives (one active for now), plot state, currency.
- **Save cadence:** shift end, hire/quit, gig completion, upgrade, plot edit, rename.
- **Compact plot save:** short keys; catalog server-side.

### 9.3 Performance Budget

- One decision per resident per think window (~0.3-0.6s LOD).
- Pathfinding only for the **active** resident.
- Attribute batching (>=1% change).
- StreamingEnabled on; plots under dedicated folders.
- DataStore: <=1 write per meaningful event.

### 9.4 Anti-Exploit

- **Ownership checks** on all actions.
- **Remote throttle** (>=0.18s).
- **Deterministic shift seeds** (no re-roll abuse).
- **Clamp payouts;** server-verified career gates.

### 9.5 Module Ownership Changes

- **ResidentAutonomyService:** handles resident careers exclusively; queues passive shifts, applies Momentum boosts, tracks streaks, and never triggers gig content.
- **JobService renamed to CareerService:** rename and limit to career assignments, stat validation, and long-term progression unlocks; expose `SetCareerForResident` and `GetCareerInfo`.
- **GigService (new, server):** owns active gig lifecycle (slot tracking, cooldowns, remotes) powered by a reusable `GigChallenge` module that maps gig IDs to prompt sets and scoring curves.
- **GigManager (new, client):** presents available gigs, launches the shared minigame UI, posts results via `GigSubmitScore`.
- **CurrencyService:** now accepts `source = "Career"` or `source = "Gig"` for analytics splits.
- **UI Modules:** update `JobSelectionUI` into `CareerSelectionUI`; add `GigPanel` for gig slots, stamina, and cooldown readouts.
- **Data Schemas:** augment resident saves with `CurrentCareerId`, `CareerStreak`, and `MomentumExpireClock`; add player-level `GigSlotsUsedToday` and `GigCooldowns`.

---

## 10) Content Plan (MVP)

- **Player Gigs:** Courier Sprint, Cafe Pop-Up.
- **Resident Careers:** Cafe Crew, Office Assistant, Junior Programmer, Fitness Trainer.
- **Upgrades:** Intelligence and Discipline; FitnessPoints via workout loops.
- **Build Modules:** Bed, Kitchenette, Study Desk, Gym, Shower, Wardrobe.

---

## 11) Onboarding

- First join: name plus appearance; quick tutorial (Eat then Rest then Work).
- First career: show two starter careers with green checks (requirements met).
- Tooltips: surface payout math, mood effects, and gig stamina costs.

---

## 12) Live-Ops & Roadmap

- **Phase A (ship):** current stack + Career Selection; Mood; starter careers + gigs; minimal build modules.
- **Phase B:** aging (Toddler-to-Adult) with term progression; track points; teen part-time gigs.
- **Phase C:** relationships (exclusive), start family (new Life slots); plot catalog expansion; events.
- **Monetization:** cosmetics only after engagement is stable.

---

## 13) Analytics & Targets

- **Events:** SessionStart, ActionPerformed(type), CareerShiftStart(role, onTime, effort), CareerShiftEnd(role, onTime, effort), CareerHire(role), CareerQuit(role), GigComplete(type, tier), GigFail(type), UpgradePurchased(type, level), BuildEdit(action, type), SaveCommit(reason).
- **Targets (soft launch):** D1 28%, D7 8%, average session 10 minutes.

---

## 14) Risks & Mitigations

- **Free-build scope creep:** ship plot modules only; no walls/doors in MVP.
- **Clarity:** career cards show requirements and estimated pay; gig cards show difficulty and stamina cost.
- **Server load:** one active resident per player; coarse passive logic; avoid per-tick saves.
- **Content treadmill:** palette swaps and parametric variants of modules.

---

## 15) MVP Definition (strict)

1. Resident ownership & spawn.
1. Needs + Mood (+/-15% clamp).
1. Player gigs (1) + resident careers (2) with visible requirements.
1. Manual/Auto planning (AM/PM).
1. Career Selection modal (Hire/Quit).
1. Customization + rename (filtered).
1. Plot modules (3 items) with server validation.
1. Save/Load for currency, job, needs snapshot, plot.

---

## 16) Kill / Pivot Criteria

- Careers blow up scope (>2): pivot to **gigs-first**, defer higher-tier careers.
- Plot modules cause nav issues: make modules cosmetic only until anchors stabilize.
- D1 < 20% after two content refreshes: add stronger short-session hooks (daily goals, streaks) before new systems.
