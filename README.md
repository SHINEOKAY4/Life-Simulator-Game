# 🌍 Game Overview

A life-simulation game that blends **The Sims-style building** with **dual income streams**.  
Players manage a plot of land and place furniture (beds, kitchens, tables, etc.) to support **Residents** (NPCs).  
Residents autonomously satisfy their needs and work **Careers** (passive shift-based income).  
Players can also run **Gigs** (active skill-check minigames) for burst income and momentum bonuses.

The player's core loop is:  
**Place items → Residents survive autonomously → Residents work careers → Run player gigs → Earn coins → Expand plot → Unlock more items → Pay bills → Repeat.**

Players can also **intervene directly** using the **Direct Action System** — selecting Residents and telling them to *Eat*, *Sleep*, *Socialize*, etc. This adds a proactive layer to optimize resident well-being.

---

## 🌱 Early Game

### Starting State

- Claimable plot with one unlocked chunk (5x5 cells)  
- Create up to 4 Residents with customizable names and genders  
- Starter furniture: Wooden Chair ($50), Campfire ($150), Old Mattress ($200)  
- Starting cash from initial gig runs or career earnings  
- Billing system active: Plot tax, electricity usage, food consumption  

### Player Goals

- Keep Residents alive (manage 5 needs: Hunger, Energy, Hygiene, Social, Fun)  
- Place essential furniture: beds (RestStation), cooking stations (CookStation), social tables  
- Learn the grid-based build system:  
  - Floors, walls, roofs with drag-to-place  
  - Cell objects (furniture) with rotation and placement validation  
- Learn the **Direct Action System**:  
  - Click Residents to manually queue actions (Eat, Sleep, Socialize)  
  - Override autonomy to prevent collapses or optimize behavior  
- Assign Residents to **Careers** for passive income:  
  - Cafe Crew: $18/min (Discipline ≥ 0)  
  - Office Assistant: $24/min (Intelligence ≥ 2, Discipline ≥ 1)  
  - Junior Programmer: $36/min (Intelligence ≥ 4, Discipline ≥ 2)  
  - Fitness Trainer: $34/min (Fitness ≥ 4, Social ≥ 2)  
- Run **Player Gigs** for active income:  
  - Courier Sprint: $28±6 (8min cooldown)  
  - Cafe Pop-Up: $24±4 (6min cooldown)  
  - Debug Jam: $32±8 (10min cooldown)  
  - 3 daily gig slots refresh each in-game day  
  - Bronze/Silver/Gold performance tiers multiply payout  
- Pay bills every 8 minutes (480 seconds):  
  - Plot tax (increases with unlocked chunks)  
  - Electricity (varies by powered stations)  
  - Food usage (tracked per cook interaction)

### Player Feeling

- Resource management with multiple systems (needs, careers, gigs, bills)  
- "I'm building a functioning household while juggling active and passive income"  
- Strategic decisions: invest in furniture vs save for expansion vs unlock chunks

---

## 🌿 Mid Game

### Mid Game Progression

- Unlock additional chunks (unlock cost increases per chunk)  
- Support multiple Residents (max 4 per household)  
- Residents qualify for higher-paying careers as stats grow:  
  - Intelligence and Discipline unlock Office Assistant → Junior Programmer  
  - Fitness and Social unlock Fitness Trainer  
- Furniture diversity: Standard Bed ($500), Stove ($200), Refridgerator ($250 storage), Big Wooden Table ($300), Lamp ($75)  
- Billing costs increase with plot expansion and powered appliances  

### Gameplay Depth

- Players balance multiple Residents' needs across stations  
- Kitchen planning matters: pair Stoves for cooking throughput, Refridgerator storage to stage ingredients, and Campfire as the slow fallback  
- **Direct Action System** shifts role:  
  - Less emergency intervention, more strategic optimization  
  - Queue actions to prevent need decay before it becomes critical  
  - Coordinate multiple Residents using shared stations (max occupancy limits)  
- Gig momentum system: successful gigs grant +10% career payout boost for 1 in-game hour  
- Grace periods and overdue states add billing pressure  

### Mid Game Player Feeling

- Mastery and optimization  
- "I'm efficiently managing a household with coordinated routines"  
- Balancing active gig income with passive career automation

---

## 🌳 Late Game

### Late Game Progression

- Maximize plot expansion (all chunks unlocked)  
- Support full 4-Resident household with specialized roles  
- Access to complete furniture catalog with varied station types  
- Residents achieve rare/elite careers through stat investment  
- Consistent billing management becomes routine income drain  
- Gig mastery: consistently hit Gold tier for maximum payouts  

### Endgame Loop

- Fine-tuning household efficiency for maximum income per cycle  
- Strategic stat development to unlock best career paths  
- Balancing active gig income with passive career reliability  
- Dealing with billing pressure and grace/overdue states  
- **Direct Action System** at this stage:  
  - Precision timing for career prep (ensure Residents well-rested before shifts)  
  - Strategic gig momentum transfers to boost career payouts  
  - Multi-Resident coordination on shared high-capacity stations

### Late Game Player Feeling

- Systematic mastery and optimization  
- "I've built an efficient machine where every system feeds into the others"  
- Pride in maximizing income while minimizing waste  

---

## 🚧 Future Systems (Not Yet Implemented)

**Note:** The following features are described in design documents but are not currently in the game:

- **Aging & Life Cycle:** Child → Teen → Adult → Elder → Death progression  
- **Stat Progression:** Study desks, gyms, training equipment that boost Intelligence/Discipline/Fitness/Creativity stats  
- **Hygiene Stations:** Showers, sinks, bathroom fixtures (Hygiene need exists but limited station support)  
- **Family & Legacy:** Children inheriting traits, multi-generational households  
- **Memorial System:** Tracking past Residents and their life achievements  
- **Advanced Careers:** Doctor, Engineer, Musician roles requiring very high stat levels  
- **Plot Tiering:** House tier/quality progression system with prestige rewards  
- **Relationships:** Social connections and interactions between Residents  
- **Rebirth System:** Retire Residents, start new generations with inherited bonuses  

---

## 📚 Game Systems

For detailed technical documentation, see [GameSystems.md](GameSystems.md)
