--!strict
-- Network/DailyRewardPackets.luau
-- Defines network packets for the daily reward system.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Packet = require(ReplicatedStorage.Packages.Packet)

local DailyRewardPackets = {}

local RewardSchema = {
	Day = Packet.NumberU8,
	Cash = Packet.NumberU32,
	Experience = Packet.NumberU32,
	Label = Packet.String,
}

local MilestoneSchema = {
	StreakRequired = Packet.NumberU16,
	BonusCash = Packet.NumberU32,
	BonusExperience = Packet.NumberU32,
	Label = Packet.String,
}

local DailyChallengeSchema = {
	DayId = Packet.NumberU32,
	QuestId = Packet.String,
	AssignedAt = Packet.NumberU32,
	QuestState = Packet.String,
}

local StatusSchema = {
	CurrentStreak = Packet.NumberU16,
	LongestStreak = Packet.NumberU16,
	TotalClaimed = Packet.NumberU32,
	TotalCashEarned = Packet.NumberU32,
	TotalExperienceEarned = Packet.NumberU32,
	CanClaim = Packet.Boolean8,
	SecondsUntilClaim = Packet.NumberU32,
	NextStreak = Packet.NumberU16,
	SecondsUntilStreakExpiry = Packet.NumberU32,
	InGraceWindow = Packet.Boolean8,
	StreakWarning = Packet.Boolean8,
	DailyChallenge = DailyChallengeSchema,
}

local ClaimResultSchema = {
	Streak = Packet.NumberU16,
	DayLabel = Packet.String,
	CashEarned = Packet.NumberU32,
	ExperienceEarned = Packet.NumberU32,
	LongestStreak = Packet.NumberU16,
	StreakReset = Packet.Boolean8,
}

DailyRewardPackets.GetDailyRewardStatus = Packet("GetDailyRewardStatus"):Response(StatusSchema)
DailyRewardPackets.ClaimDailyReward = Packet("ClaimDailyReward"):Response(ClaimResultSchema)
DailyRewardPackets.DailyRewardUpdated = Packet("DailyRewardUpdated", StatusSchema)

return DailyRewardPackets
