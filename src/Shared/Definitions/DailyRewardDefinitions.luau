--!strict
-- DailyRewardDefinitions: 7-day rotating reward cycle with escalating values
-- and milestone bonuses for sustained login streaks.

export type DailyReward = {
	Day: number,
	Cash: number,
	Experience: number,
	Label: string,
}

export type MilestoneBonus = {
	StreakRequired: number,
	BonusCash: number,
	BonusExperience: number,
	Label: string,
}

-- 7-day reward cycle that repeats. Day index is (streak - 1) % 7 + 1.
local DAILY_REWARDS: { DailyReward } = {
	{ Day = 1, Cash = 50, Experience = 15, Label = "Welcome Back" },
	{ Day = 2, Cash = 75, Experience = 20, Label = "Getting Started" },
	{ Day = 3, Cash = 100, Experience = 30, Label = "Momentum" },
	{ Day = 4, Cash = 125, Experience = 35, Label = "Rolling" },
	{ Day = 5, Cash = 175, Experience = 45, Label = "Dedicated" },
	{ Day = 6, Cash = 225, Experience = 55, Label = "Committed" },
	{ Day = 7, Cash = 350, Experience = 80, Label = "Full Week" },
}

-- Milestone bonuses awarded once when a streak target is first reached.
local MILESTONES: { MilestoneBonus } = {
	{ StreakRequired = 7, BonusCash = 200, BonusExperience = 50, Label = "First Full Week" },
	{ StreakRequired = 14, BonusCash = 500, BonusExperience = 100, Label = "Two Week Streak" },
	{ StreakRequired = 30, BonusCash = 1200, BonusExperience = 250, Label = "Monthly Dedication" },
}

-- Cooldown: minimum seconds between claims (20 hours to allow flexible schedules)
local CLAIM_COOLDOWN_SECONDS = 20 * 60 * 60 -- 72000

-- Grace period: maximum seconds before streak resets (48 hours from last claim)
local STREAK_GRACE_SECONDS = 48 * 60 * 60 -- 172800

local DailyRewardDefinitions = {
	Rewards = DAILY_REWARDS,
	Milestones = MILESTONES,
	ClaimCooldownSeconds = CLAIM_COOLDOWN_SECONDS,
	StreakGraceSeconds = STREAK_GRACE_SECONDS,
	CycleLength = #DAILY_REWARDS,
}

function DailyRewardDefinitions.GetRewardForStreak(streak: number): DailyReward
	local dayIndex = ((streak - 1) % #DAILY_REWARDS) + 1
	return DAILY_REWARDS[dayIndex]
end

function DailyRewardDefinitions.GetMilestoneForStreak(streak: number): MilestoneBonus?
	for _, milestone in ipairs(MILESTONES) do
		if milestone.StreakRequired == streak then
			return milestone
		end
	end
	return nil
end

return table.freeze(DailyRewardDefinitions)
