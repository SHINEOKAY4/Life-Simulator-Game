--!strict
-- ReplicatedStorage/Network/ProgressionPackets.luau

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Packet = require(ReplicatedStorage.Packages.Packet)

local ProgressionPackets = {}

ProgressionPackets.ProgressionUpdate = Packet("ProgressionUpdate", {
	Level = Packet.NumberU16,
	ExperienceTotal = Packet.NumberU32,
	ExperienceIntoLevel = Packet.NumberU32,
	ExperienceForNext = Packet.NumberU32,
	Delta = Packet.NumberS32,
	Reason = Packet.String,
	UnlockedItemIds = { Packet.String },
})

return ProgressionPackets
