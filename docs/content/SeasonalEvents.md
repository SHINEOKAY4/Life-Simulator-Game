---
title: Seasonal Events Rewards
---

# Seasonal Events Rewards

`SeasonalEventService` manages season rotation, challenge completion, and reward distribution for seasonal events.

## Reward Model

- Challenge rewards are earned when progress reaches the challenge target.
- Milestone rewards are unlocked when cumulative `SeasonsCompleted` reaches a threshold (`4`, `8`, `20`).
- "Earned" totals and "Distributed" totals are tracked separately:
- `TotalSeasonalCashEarned` / `TotalSeasonalExperienceEarned` increase when challenges or milestones are completed.
- `TotalCashDistributed` / `TotalExperienceDistributed` increase only when rewards are actually claimed or batch-distributed.

## Claim APIs

- `ClaimChallengeReward(player, challengeId)`
- Validates player, challenge ID, current-season ownership, completion, and not already claimed.
- Executes reward distribution through the injected/default reward executor.
- Returns `DistributionFailed` without mutating claimed state if distribution fails.

- `ClaimMilestoneReward(player, seasonsCompleted)`
- Validates player, milestone threshold, threshold reached, and not already claimed.
- Uses the same reward executor path and failure behavior as challenge claims.

## Batch Distribution

- `DistributeSeasonRewards(player)` collects all pending rewards:
- Completed, unclaimed challenges in the active season.
- Reached, unlocked, unclaimed milestone rewards.
- Distribution is all-or-nothing:
- If any reward grant fails, previously granted rewards in the batch are rolled back in reverse order.
- Claimed flags and distributed totals are restored to pre-batch state on failure.

## Pending Rewards

- `GetPendingRewards(player)` returns:
- `Challenges`: pending challenge rewards.
- `Milestones`: pending milestone rewards.
- `TotalPendingCash` and `TotalPendingExperience`: combined totals.

## Network Surface

Seasonal rewards are exposed through `src/Network/SeasonalEventPackets.luau`:

- `GetSeasonStatus`
- `ClaimChallengeReward`
- `ClaimMilestoneReward`
- `DistributeAllRewards`
- `SeasonTransitioned` and `ChallengeCompleted` event packets

## Tests

Behavioral coverage lives in `Tests/Specs/SeasonalEventSpec.lua`, including:

- Claim validation and duplicate prevention.
- Executor failure handling.
- Batch distribution with mixed reward types.
- Rollback integrity and retry safety.
- Pending reward aggregation and milestone edge cases.
