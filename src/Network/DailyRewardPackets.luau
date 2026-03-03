--!strict
-- Network/DailyRewardPackets.luau
-- Defines network packets for the daily reward system.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Packet = require(ReplicatedStorage.Packages.Packet)

local DailyRewardPackets = {}

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
	ClaimCooldownSeconds = Packet.NumberU32,
	StreakGraceSeconds = Packet.NumberU32,
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
	MilestoneUnlocked = Packet.StringLong,
	LongestStreak = Packet.NumberU16,
	StreakReset = Packet.Boolean8,
}

DailyRewardPackets.GetDailyRewardStatus = Packet("GetDailyRewardStatus"):Response(StatusSchema)
DailyRewardPackets.ClaimDailyReward = Packet("ClaimDailyReward"):Response(ClaimResultSchema)
DailyRewardPackets.DailyRewardUpdated = Packet("DailyRewardUpdated", StatusSchema)

return DailyRewardPackets
