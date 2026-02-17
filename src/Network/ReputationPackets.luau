--!strict
-- Network/ReputationPackets.luau
-- Defines network packets for player social reputation.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Packet = require(ReplicatedStorage.Packages.Packet)

local ReputationPackets = {}

local SnapshotSchema = {
	ReputationScore = Packet.NumberU8,
	TrustLevel = Packet.String,
	RewardMultiplier = Packet.NumberF64,
	NextTrustLevel = Packet.String,
	PointsToNextLevel = Packet.NumberU8,
}

local RankingEntrySchema = {
	Rank = Packet.NumberU16,
	PlayerName = Packet.String,
	ReputationScore = Packet.NumberU8,
	TrustLevel = Packet.String,
	IsLocalPlayer = Packet.Boolean8,
}

local DataSchema = {
	Snapshot = SnapshotSchema,
	Rankings = { RankingEntrySchema },
	PlayerRank = Packet.NumberU16,
	LifetimeRewards = Packet.NumberU32,
}

ReputationPackets.ReputationUpdated = Packet("ReputationUpdated", DataSchema)
ReputationPackets.GetReputationRequest = Packet("GetReputationRequest"):Response(DataSchema)

return ReputationPackets
