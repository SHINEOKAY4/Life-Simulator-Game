# Game Systems Overview

## Table of Contents

- [Core Systems](#core-systems)
  - [1. Plot System](#1-plot-system)
  - [3. Item System](#3-item-system)
  - [4. NPC System](#4-npc-system)
  - [5. Economy System](#5-economy-system)
- [Gameplay Systems](#gameplay-systems)
  - [7. Motives & Needs System](#7-motives--needs-system)
  - [8. Stat & Progression System](#8-stat--progression-system)
  - [9. Life Cycle & Legacy System](#9-life-cycle--legacy-system)
  - [10. Job & Career System](#10-job--career-system)
- [Player-Facing Systems](#player-facing-systems)
  - [11. Build/Placement UI System](#11-buildplacement-ui-system)
  - [12. HUD / Info System](#12-hud--info-system)
  - [13. Visual World System](#13-visual-world-system)
- [Support Systems (Live Ops)](#support-systems-live-ops)
  - [14. Rate Limiting & Security](#14-rate-limiting--security)
  - [15. Analytics & Telemetry](#15-analytics--telemetry)
  - [16. Feature Flag System](#16-feature-flag-system)
  - [17. Direct Action System](#17-direct-action-system)

---

## Core Systems

### 1. Plot System

- Manages ownership of the land
- Defines grid size for placement (expands with house tier)
- Handles placement/removal of items
- Tracks occupancy for collision/validation


### 2. Item System

- Catalog of buyable/placeable objects
- Defines function: which NPC motives/stat it affects
- Costs, footprint, clearance requirements
- Persistence: which items are placed where

### 3. NPC System

- Creates/manages lives
- Includes life cycle: birth → child → teen → adult → elder → death
- Stats/motives (Hunger, Energy, Hygiene, Fun, Health, Happiness, etc.)
- Behaviors: finds items to satisfy needs

### 4. Economy System

- Jobs and income per NPC
- Daily payouts, scaling by stats
- Costs for items, upgrades, NPC creation
- Balance curve: slow early, exponential midgame, prestige/rebirth late

---

## Gameplay Systems

### 5. Motives & Needs System

- Regular ticking down of NPC motives (Hunger, Energy, etc.)
- Items can satisfy specific motives
- Poor motives apply penalties to stats/jobs
- If critical needs are unmet → health decline → early death

### 6. Stat & Progression System

- NPCs build stats (Intellect, Discipline, Creativity, etc.) from items
- Stats affect career paths and job payouts
- Education/training items improve stats faster

### 7. Life Cycle & Legacy System

- NPC ages over in-game years
- Children inherit traits/stats partially from parents
- Death → NPC removed; history log updated
- Legacy system: memorial UI or generations tree

### 8. Job & Career System

- Catalog of jobs with requirements (stats, age)
- NPCs auto-pick best available job
- Jobs provide daily income and prestige
- High-end jobs gated by high stats + good life support

---

## Player-Facing Systems

### 9. Build/Placement UI System

- Catalog shop menu
- Ghost preview with red/green snap
- Error feedback (occupied, no funds)
- Rotation sanity check: select a placed wall/cell object, press Rotate on the radial UI, and confirm the server re-spawns it with the new facing without duplicating or deleting it.

### 10. HUD / Info System

- Coins balance
- NPC motives panel (bars)
- Job info + daily payout timer
- House tier info + upgrade button

### 11. Visual World System

- item models, NPC avatars
- NPC animations (idle, walk, use item)
- Placement visuals (hover grid highlight)

---

## Support Systems (Live Ops)

### 12. Rate Limiting & Security

- Prevent remote spam and dupe exploits
- Server-only authority on costs, placement, payouts

### 13. Analytics & Telemetry

- Track economy balance (coins earned/spent)
- Track NPC deaths, upgrades purchased
- Track session length, churn points

### 14. Feature Flag System

- Server can disable payouts, stop purchases, or adjust multipliers live
- Critical for hotfixing without republishing

### 15. Direct Action System

- Allows players to proactively shape NPC behavior
- Action menu opens when clicking an NPC
- Shows available commands (Eat, Sleep, Study, etc.) based on nearby items
- Commands override NPC autonomy temporarily, then return to normal AI
- Provides agency while keeping autonomous simulation intact
- Balances indirect (environment) and direct (commands) influence
