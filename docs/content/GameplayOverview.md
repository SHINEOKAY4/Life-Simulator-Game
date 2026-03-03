---
title: Gameplay Systems Overview
---

# Gameplay Systems Overview

This page explains how the core gameplay loops connect at a system level.

## Core Loop

1. Claim a plot and unlock buildable chunks.
2. Place and configure objects to improve utility and room quality.
3. Progress quests, seasonal challenges, and daily rewards.
4. Attract and manage tenants for recurring mailbox income.
5. Reinvest earnings into upgrades, expansion, and progression unlocks.

## Major Runtime Services

- `PlotService`: plot ownership, runtime plot state, placed-object snapshots, station occupancy.
- `BuildService`: validates and applies building actions on the plot grid.
- `TenantService`: property valuation, tenant offers, lease servicing, room assignment, mailbox balance.
- `QuestService`: objective progression and reward eligibility for quest-driven content.
- `SeasonalEventService`: active season, challenge progress, and milestone reward tracking.
- `DailyRewardService`: streak/cooldown logic and daily claim rewards.
- `AchievementService`: unlock conditions and achievement reward publication.
- `ProgressionService`: XP accumulation and leveling flow.
- `BillingService` and `CurrencyService`: economy grants/spends and wallet mutation.
- `NotificationService`: user-facing event notifications consumed by UI and services.

## Data + Event Flow

1. Player actions mutate service state (build, claim, complete objective, collect reward).
2. Service logic validates action preconditions and computes outcomes.
3. `PlayerSession`-backed state is updated (profile sub-states per feature).
4. Network packets broadcast deltas/snapshots to client UI.
5. UI updates visible status (currency, streaks, challenges, active tenants, alerts).

## Tenant Loop Details

- Room readiness is derived from enclosed-bedroom checks and bed requirements.
- Offers are scheduled from valuation score + timing config.
- Lease servicing accrues rent over time and settles into mailbox balance.
- Tenant departures trigger review hooks and room reassignment/cleanup.

## Reward Systems

- Seasonal rewards: challenge completion + milestone thresholds per season progression.
- Daily rewards: streak-sensitive payouts with cooldown/grace boundaries.
- Achievements: system-level milestones that often bridge multiple services.

## Recommended Reading Order

1. `intro`
2. `GameplayOverview`
3. `SeasonalEvents`
4. Generated architecture pages under `generated/architecture`
5. Generated API pages under `generated/api`
