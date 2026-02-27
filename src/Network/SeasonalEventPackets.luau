--!strict
-- Network/SeasonalEventPackets.luau
-- Defines network packets for the seasonal event system.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Packet = require(ReplicatedStorage.Packages.Packet)

local SeasonalEventPackets = {}

local BuffSchema = {
	Type = Packet.String,
	Value = Packet.Float32,
	Label = Packet.String,
}

local ChallengeStatusSchema = {
	Id = Packet.String,
	Name = Packet.String,
	Description = Packet.String,
	StatKey = Packet.String,
	CurrentValue = Packet.NumberU32,
	TargetValue = Packet.NumberU32,
	Completed = Packet.Boolean8,
	RewardClaimed = Packet.Boolean8,
	RewardCash = Packet.NumberU32,
	RewardExperience = Packet.NumberU32,
}

local SeasonStatusSchema = {
	CurrentSeason = Packet.String,
	SeasonName = Packet.String,
	SeasonDescription = Packet.String,
	Buffs = { BuffSchema },
	Challenges = { ChallengeStatusSchema },
	SeasonsCompleted = Packet.NumberU16,
	TotalChallengesCompleted = Packet.NumberU16,
	TotalSeasonalCashEarned = Packet.NumberU32,
	TotalSeasonalExperienceEarned = Packet.NumberU32,
	TotalCashDistributed = Packet.NumberU32,
	TotalExperienceDistributed = Packet.NumberU32,
	SeasonStartTime = Packet.NumberU32,
	ClaimedMilestoneRewardSeasons = { Packet.NumberU16 },
	ClaimedMilestonesCount = Packet.NumberU16,
}

local TransitionSchema = {
	PreviousSeason = Packet.String,
	NewSeason = Packet.String,
	SeasonName = Packet.String,
	SeasonsCompleted = Packet.NumberU16,
	WasTransition = Packet.Boolean8,
}

local RewardClaimResultSchema = {
	Success = Packet.Boolean8,
	CashDistributed = Packet.NumberU32,
	ExperienceDistributed = Packet.NumberU32,
	RewardName = Packet.String,
	ErrorMessage = Packet.String,
}

SeasonalEventPackets.GetSeasonStatus = Packet("GetSeasonStatus"):Response(SeasonStatusSchema)
SeasonalEventPackets.SeasonTransitioned = Packet("SeasonTransitioned", TransitionSchema)
SeasonalEventPackets.ChallengeCompleted = Packet("ChallengeCompleted", ChallengeStatusSchema)
SeasonalEventPackets.ClaimChallengeReward = Packet("ClaimChallengeReward"):Response(RewardClaimResultSchema)
SeasonalEventPackets.ClaimMilestoneReward = Packet("ClaimMilestoneReward"):Response(RewardClaimResultSchema)
SeasonalEventPackets.DistributeAllRewards = Packet("DistributeAllRewards"):Response(RewardClaimResultSchema)

return SeasonalEventPackets
