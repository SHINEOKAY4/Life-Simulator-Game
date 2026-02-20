--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Packet = require(ReplicatedStorage.Packages.Packet)

local AchievementPackets = {}

AchievementPackets.GetSnapshot = Packet("GetAchievementSnapshot"):Response(Packet.Boolean8, Packet.StringLong, Packet.Any)
AchievementPackets.ClaimAchievement = Packet("ClaimAchievement", Packet.String):Response(
	Packet.Boolean8,
	Packet.StringLong,
	Packet.Any
)

AchievementPackets.SnapshotUpdated = Packet("AchievementSnapshotUpdated", Packet.Any)
AchievementPackets.AchievementUnlocked = Packet("AchievementUnlocked", {
	AchievementId = Packet.String,
	UnlockedAt = Packet.NumberF64,
})

return AchievementPackets
