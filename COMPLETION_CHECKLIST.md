# Life Simulator - Core Loop Completion Checklist

## 🎯 Critical Path (Blocks Core Loop)

### 1. Career Auto-Scheduler
**Status:** ❌ Not Started  
**Priority:** CRITICAL  
**Blocks:** Passive income, autonomous gameplay

**Requirements:**
- [ ] Create shift scheduling logic (check every 30 in-game minutes)
- [ ] Auto-call `CareerService.StartResidentShift()` when:
  - [ ] Resident has assigned career
  - [ ] Not currently on shift
  - [ ] Energy > 40
  - [ ] Hunger > 40
  - [ ] Within scheduled work hours
- [ ] Auto-call `CareerService.StopResidentShift()` at shift end
- [ ] Implement "call out sick" logic for low needs
- [ ] Add clock-in/clock-out timestamps to ResidentState
- [ ] Track lateness/attendance stats

**Implementation Location:**
- Option A: Add to `ResidentAutonomyService`
- Option B: Create new `ShiftScheduler` module

**Testing Criteria:**
- [ ] Resident automatically starts shift at scheduled time
- [ ] Resident automatically ends shift after work duration
- [ ] Payroll accumulates correctly during shift
- [ ] Resident doesn't start shift if needs too low

---

### 2. Gig Minigame Implementation
**Status:** ❌ Not Started  
**Priority:** CRITICAL  
**Blocks:** Active income, player engagement

**Requirements:**
- [ ] Build UI for at least ONE playable gig minigame
- [ ] Implement scoring system that feeds `GigService.SubmitScore()`
- [ ] Create visual feedback for performance tiers (Bronze/Silver/Gold)
- [ ] Add progress timer UI
- [ ] Show payout calculation on completion
- [ ] Display remaining daily slots (3 max)
- [ ] Show cooldown timers between gigs

**Recommended Starting Gig:** DebugJam (pattern matching - simplest)

**DebugJam Mechanics:**
- [ ] Show code snippet with syntax errors
- [ ] Player clicks/highlights errors within time limit
- [ ] Score based on: correct fixes × speed multiplier
- [ ] Bronze: 0-50 points, Silver: 51-80, Gold: 81+

**Alternative Options:**
- CourierSprint: Time-based delivery challenges
- CafePopUp: Order matching/memory game

**Testing Criteria:**
- [ ] Player can start gig from UI
- [ ] Minigame runs and calculates score
- [ ] Payout appears in wallet after completion
- [ ] Momentum bonus (+10% career) applies for 1 hour
- [ ] Daily slots decrement correctly
- [ ] Cooldown prevents spam

---

### 3. Stat Progression System
**Status:** ❌ Not Started  
**Priority:** CRITICAL  
**Blocks:** Career unlocks, progression loop

**Requirements:**

#### Furniture/Items
- [ ] Add Study Desk furniture (boosts Intelligence)
- [ ] Add Gym Equipment (boosts Fitness)
- [ ] Add Art Easel (boosts Creativity)
- [ ] Add Bookshelf (boosts Discipline)
- [ ] Add Couch/TV (boosts Social with group interactions)

#### Station Behavior
- [ ] Update `Furnitures.luau` catalog with new stat-boosting items
- [ ] Add stat gain logic to `ResidentActionHandlers.luau`
- [ ] Configure stat points per session (e.g., +1-3 per use)
- [ ] Add diminishing returns per day (prevent grinding)
- [ ] Make residents autonomously seek stat-boost stations

#### UI Feedback
- [ ] Show +Stat notification when resident uses station
- [ ] Display current stats in Resident Roster
- [ ] Show stat requirements for locked careers (grayed out)

**Testing Criteria:**
- [ ] Resident uses study desk → Intelligence increases
- [ ] Resident uses gym → Fitness increases
- [ ] Stats persist across sessions
- [ ] Career unlocks when stat requirements met
- [ ] Residents autonomously use stat stations when idle

---

## 🚀 High Priority (Enables Full Experience)

### 4. Career Unlock UI
**Status:** ❌ Not Started  
**Priority:** HIGH

**Requirements:**
- [ ] Show all careers in JobSelectionUI (not just qualified ones)
- [ ] Gray out locked careers with tooltip showing requirements
- [ ] Example: "JuniorProgrammer - Requires Intelligence: 40 (Current: 25)"
- [ ] Highlight newly unlocked careers with visual effect
- [ ] Show BasePay and requirements clearly

---

### 5. Visual Feedback & Juice
**Status:** ❌ Not Started  
**Priority:** HIGH

**Requirements:**
- [ ] Payroll payout toast notification (+$X received!)
- [ ] Billing due warning (1 minute before overdue)
- [ ] Stat gain particles/animations
- [ ] Career momentum indicator (glowing effect for 1 hour after gig)
- [ ] Money counter animation when wallet changes
- [ ] Gig performance tier badges (Bronze/Silver/Gold medals)

---

### 6. Goals & Objectives System
**Status:** ❌ Not Started  
**Priority:** HIGH

**Requirements:**
- [ ] New player tutorial objectives:
  - [ ] Place first furniture
  - [ ] Hire first resident
  - [ ] Assign first career
  - [ ] Run first gig
  - [ ] Survive first billing cycle
- [ ] Milestone objectives:
  - [ ] Earn $1000 total
  - [ ] Unlock second career
  - [ ] Reach 50 in any stat
  - [ ] Manage 3 residents simultaneously
- [ ] Show objectives in HUD with progress tracking

---

## ✨ Polish & Enhancement (Post-MVP)

### 7. Expanded Content
**Status:** ❌ Not Started  
**Priority:** MEDIUM

- [ ] Add 4-6 more careers (mid-tier and advanced)
- [ ] Add 2-3 more gig minigames
- [ ] Create hygiene stations (shower, sink, toilet)
- [ ] Add decorative furniture
- [ ] Implement food variety (affects Hunger satisfaction rate)

---

### 8. Advanced Systems (Future)
**Status:** ❌ Not Started  
**Priority:** LOW

- [ ] Aging system (residents gain experience over time)
- [ ] Relationship system (resident-to-resident interactions)
- [ ] Family/legacy system (multiple generations)
- [ ] Random events (promotions, emergencies, opportunities)
- [ ] Resident personalities affecting behavior
- [ ] Plot expansion beyond current grid size

---

## 📊 Completion Criteria

### Minimal Viable Core Loop
You have a working core loop when:
- ✅ Billing drains money automatically (DONE)
- ❌ Residents earn money from careers automatically
- ❌ Players earn money from gigs actively
- ❌ Stats increase through gameplay
- ❌ Career unlocks via stat progression
- ❌ Loop is self-sustaining (income > expenses)

### Functional Prototype
You have a functional prototype when:
- ❌ All 3 critical path items complete
- ❌ At least 1 gig is fun to play repeatedly
- ❌ Clear visual feedback for all income/expense events
- ❌ Players understand what to do next (objectives/goals)

### Polished Experience
You have a polished experience when:
- ❌ All high priority items complete
- ❌ Tutorial guides new players
- ❌ Multiple career paths available
- ❌ 3+ gig minigames provide variety
- ❌ Stat progression feels meaningful

---

## 🗓️ Suggested Timeline

### Week 1: Get Money Flowing
- Day 1-2: Career auto-scheduler
- Day 3-4: Placeholder gig (simplest minigame)
- Day 5-7: Test income vs expenses balance

### Week 2: Enable Progression
- Day 8-10: Stat-boosting furniture
- Day 11-12: Career unlock UI
- Day 13-14: Visual feedback & juice

### Week 3: Make It Fun
- Day 15-17: Polish main gig minigame
- Day 18-19: Goals/objectives system
- Day 20-21: New player experience & tutorial

---

## 🧪 Testing Protocol

After completing each critical path item:

1. **Create new save** - Test from zero state
2. **Hire resident** - Assign them a career
3. **Wait for auto-shift** - Verify they work automatically
4. **Check payroll** - Confirm earnings accumulate
5. **Run gig** - Verify payout and momentum bonus
6. **Use stat furniture** - Confirm stat increases
7. **Unlock career** - Verify progression works
8. **Survive billing** - Ensure income > expenses

---

## 📝 Notes

- **Current State:** Infrastructure 90% complete, gameplay 10% complete
- **Main Blocker:** No way for players to earn money (careers don't auto-run, gigs have no gameplay)
- **Working Systems:** Billing, building, needs autonomy, direct actions, payroll tracking
- **Architecture Strength:** Server-authority with delta replication is solid foundation

**When all critical path items are complete, you'll have a playable core loop!**
