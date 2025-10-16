# Life Simulator — Game Design Document (GDD)

**Version:** 0.6 (MVP-focused)  
**Platform:** Roblox (multiplayer servers; each player manages their own resident)  
**Tone:** Kid‑safe, wholesome, transparent

---

## 1) Overview
**High Concept:** Start a life, make everyday choices, grow stats, earn honestly, and progress into better roles.  
**Player Fantasy:** “I plan a life, build good habits, and see the results.”  
**Core Identity:** Clarity over grind; long‑term identity (jobs, habits, home); solo‑friendly systems.

---

## 2) Pillars
- **Everyday Choices Matter** — Eat, rest, work, train; consistency beats spam.
- **Clarity Over Grind** — Visible requirements, fair consequences, capped modifiers.
- **Long‑Term Identity** — Roles, habits, and a home you shape over time.
- **Solo‑Feasible** — Modular content, low asset overhead, predictable load.

---

## 3) Current Build Snapshot (as of MVP prep)
- **Plot claim & build loop** — Claimable plots with guided camera selector, chunk unlock flow, and grid-based placement for floors, walls, and station furniture; move/rotate/destroy actions run through server validation with placement previews and delta replication.
- **Resident roster & persistence** — DataStore-backed household state loads multiple residents per player, spawns gendered rigs on owned plots, and mirrors core need values to attributes for UI.
- **Needs & autonomy** — Hunger, Energy, Hygiene, Social, and Fun decay on the server; resident AI evaluates available stations, applies moodlets, and falls back to ground rest or roaming when blocked.
- **Direct actions** — Manual override pipeline (beds, kitchens, social tables, hygiene fixtures, fun spots) handles occupancy, cancel tokens, and completion signals so players can steer residents moment-to-moment.
- **Player-facing UI** — Build catalog panels, object selector with radial controls, resident selector + needs HUD, and chunk highlights for expansion; day/night lighting syncs to server time.
- **Server authority & networking** — PlotService/BuildService own placement, station state, and rate-limited remotes; WorldPlacer and delta packets keep client worlds in lockstep.

---

## 4) Core Loop
1. Check **Needs** (Hunger, Energy) and **Mood**.  
2. Choose actions (**Work, Eat, Rest, Workout**).  
3. Perform action → earn cash / gain stats → adjust needs/mood.  
4. Meet requirements → **apply for higher‑tier job**.  
5. Repeat while keeping punctuality and effort high to avoid soft debuffs.

---

## 5) Progression Spine
- **Stats:** `IntelligenceLevel`, `FitnessLevel`, `DisciplineLevel`, `SocialLevel`; plus `FitnessPoints` (sub‑currency).  
- **Eligibility:** Jobs have explicit stat gates; higher tiers pay better.  
- **Mood Effects:** `payoutMultiplier = 1 + clamp((Mood−50)/50, −0.15, +0.15)`  
- **Consequences Ladder:** Lateness/poor effort → time‑boxed debuffs (no hard fails).

---

## 6) Systems Detail

### 6.1 Needs & Mood
- **Drift (per real‑time minute, server):** Hunger +0.5..+1.0, Energy −0.25..−0.5 (tunable).  
- **Actions:**  
  - **Eat:** Hunger −40% to −55% (module quality modifies).  
  - **Rest:** Energy +25% to +40% (bed quality modifies).  
  - **Workout:** Energy −20%, Hunger +15%, FitnessPoints +X.  
- **Mood (0–100):** recent needs balance, punctuality, successful shifts → ±15% effect clamp.

### 6.2 Work: Gigs and Professions
- **Gigs:** short tasks, quick payouts; always available; minimal gates.  
- **Professions:** shift‑based roles with higher base pay; require stats; player **chooses** job explicitly.  
- **Punctuality/Effort:** tracked per shift; soft debuffs on repeated issues.

**Starter roles (tunable):**

| Role | Type | Requirements | Pay Base | Notes |
|---|---|---|---:|---|
| Cafe Crew | Profession | Discipline ≥ 1 | $18 | Stability starter |
| Office Assistant | Profession | Intelligence ≥ 2, Discipline ≥ 1 | $24 | Filing tasks |
| Courier | Gig | none | $20–$30 per run | Distance variance |
| Junior Programmer | Profession | Intelligence ≥ 4, Discipline ≥ 2 | $36 | Study synergy |
| Fitness Trainer | Profession | FitnessLevel ≥ 4, Social ≥ 2 | $34 | Mood synergy |

**Payout (profession):** `pay = basePay × shiftMinutes × moodMultiplier × streakMultiplier`  
**Payout (gig):** `payout = base ± variance`, then × `moodMultiplier`

### 6.3 Planner
- **Modes:** Auto or Manual.  
- **Manual:** Player sets **AM** and **PM** intents.  
- **Auto:** Server picks based on needs and job schedule.  
- **Cooldowns:** Prevent mid‑shift swaps.

### 6.4 Plot Building (Phase‑in, low scope)
- **Grid, snap‑to‑cell** plot per player; **modules** (no freeform rooms in MVP).  
- Launch catalog: **Bed Corner, Kitchenette, Study Desk, Gym Corner, Shower, Wardrobe**.  
- Effects are single, non‑stacking quality modifiers.  
- Actions: **Place, Move, Rotate, Remove, Sell**; server‑validated; compact save.

---

## 7) Economy

### 7.1 Currencies and Values
- **Cash:** earn from gigs/professions; spend on upgrades and modules.  
- **Stats:** gate professions; gained via actions and streaks.  
- **FitnessPoints:** sub‑currency for fitness upgrades (optional MVP).  
- **No premium pay‑to‑win** (cosmetics only later).

### 7.2 Economy JSON (MVP)
```json
{
  "currencies": ["Cash"],
  "stats": ["IntelligenceLevel", "FitnessLevel", "DisciplineLevel", "SocialLevel"],
  "derived": ["Mood", "Charisma"],
  "earn": {
    "gig": {"base": [20, 35], "multMood": true},
    "profession": {
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
- **Top Bar:** title, global cash, day/part‑of‑day, nav (Careers, Activities, Customize, Settings).  
- **Lives Roster:** scrollable cards; select active resident.  
- **Selected Mini Panel:** name, stage, Hunger/Energy bars, **Inspect**.  
- **Notifications Anchor:** for toasts.

### 8.2 Modals
- **Job Selection:** shows roles, stat gates, pay preview; **Hire/Quit**.  
- **Inspector:** name, stats, needs, mood, profession, quick actions.  
- **Customize:** presets + rename (filtered).  
- **Build Catalog (later):** list → ghost preview → place/move/sell.

---

## 9) Technical Design

### 9.1 Server/Client
- **Server:** job eligibility, hires, payouts, needs drift, action execution, build validation.  
- **Client:** input, previews, UI, cosmetics.  
- **Remotes:** `RequestOverrideAction`, `JobSelect/JobQuit`, `BuildRequest(Place/Move/Rotate/Remove/Sell)`.  
- **Resident Attributes:** Cash, HungerPercent, EnergyPercent, Mood, IntelligenceLevel, FitnessLevel, DisciplineLevel, SocialLevel, CurrentJobId, CurrentGigPhase, LastSpeechText, LastSpeechClockUnix, PlanMode, PlannedMorningTask, PlannedEveningTask.

### 9.2 Data & Save
- **PlayerData:** Lives (one active for now), Plot state, Currency.  
- **Save cadence:** shift end, hire/quit, upgrade, plot edit, rename.  
- **Compact plot save:** short keys; catalog server‑side.

### 9.3 Performance Budget
- One decision per resident per think window (≈0.3–0.6s LOD).  
- Pathfinding only for the **active** resident.  
- Attribute batching (≥1% change).  
- StreamingEnabled on; plots under dedicated folders.  
- DataStore: ≤1 write per meaningful event.

### 9.4 Anti‑Exploit
- Ownership checks on all actions.  
- Remote throttle (≥0.18s).  
- Deterministic shift seeds (no re‑roll abuse).  
- Clamp payouts; server‑verified job gates.

---

## 10) Content Plan (MVP)
**Gigs:** Courier run; Cafe runner variant.  
**Professions:** Cafe Crew, Office Assistant, Junior Programmer, Fitness Trainer.  
**Upgrades:** Intelligence + Discipline; FitnessPoints via workout.  
**Build Modules:** Bed, Kitchenette, Study Desk, Gym, Shower, Wardrobe.

---

## 11) Onboarding
- First join: name + appearance; 3‑step tutorial: Eat → Rest → Work.  
- First job: show two starter roles with green checks (requirements met).  
- Tooltips: show clear math on payouts and mood effects.

---

## 12) Live‑Ops & Roadmap
- **Phase A (ship):** current stack + Job Selection; Mood; two professions + gigs; minimal build modules.  
- **Phase B:** aging (Toddler→Adult) with term progression; track points; teen part‑time jobs.  
- **Phase C:** relationships (exclusive), start family (new Life slots); plot catalog expansion; events.  
- **Monetization:** cosmetics only after engagement is stable.

---

## 13) Analytics & Targets
- **Events:** SessionStart, ActionPerformed(type), ShiftStart/End(role, onTime, effort), Hire/Quit(role), GigComplete(type), UpgradePurchased(type, level), BuildEdit(action, type), SaveCommit(reason).  
- **Targets (soft launch):** D1 ≥ 28%, D7 ≥ 8%, Avg session ≥ 10 min.

---

## 14) Risks & Mitigations
- **Free‑build scope creep:** ship plot **modules** only; no walls/doors in MVP.  
- **Clarity:** role cards show **requirements + estimated pay**.  
- **Server load:** one active resident per player; coarse passive logic; avoid per‑tick saves.  
- **Content treadmill:** palette swaps and parametric variants of modules.

---

## 15) MVP Definition (strict)
1) Resident ownership & spawn  
2) Needs + Mood (±15% clamp)  
3) Gigs (1–2) + Professions (≥2) with visible requirements  
4) Manual/Auto planning (AM/PM)  
5) Job Selection modal (Hire/Quit)  
6) Customization + rename (filtered)  
7) Plot modules (≥3 items) with server validation  
8) Save/Load for currency, job, needs snapshot, plot

**Estimates:** Vertical Slice **2–3 weeks** • MVP **4–6 weeks** (solo)

---

## 16) Kill / Pivot Criteria
- Professions blow up scope (>2×): pivot to **gigs‑first**, defer professions.
- Plot modules cause nav issues: make modules **cosmetic only** until anchors stable.
- D1 < 20% after two content refreshes: add stronger short‑session hooks (daily goals, streaks) before new systems.
