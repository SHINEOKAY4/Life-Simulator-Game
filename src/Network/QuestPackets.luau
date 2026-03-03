--!strict
-- Network/QuestPackets.luau
-- Defines network packets for the quest system.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Packet = require(ReplicatedStorage.Packages.Packet)

local QuestPackets = {}

-- Client -> Server: request full quest snapshot for the local player.
-- Response: success flag, JSON-encoded quest states table (or error string).
QuestPackets.GetQuestSnapshot = Packet("GetQuestSnapshot"):Response(Packet.Boolean8, Packet.Any)

-- Client -> Server: start a quest by id.
-- Payload: questId (String).
-- Response: success flag, error string (or nil).
QuestPackets.StartQuest = Packet("QuestStartQuest", Packet.String):Response(Packet.Boolean8, Packet.String)

-- Client -> Server: claim rewards for a completed quest.
-- Payload: questId (String).
-- Response: success flag, error string (or nil).
QuestPackets.ClaimQuest = Packet("QuestClaimQuest", Packet.String):Response(Packet.Boolean8, Packet.String)

-- Server -> Client: pushed whenever quest progress changes for the player.
-- Payload: full quest states snapshot (Any table).
QuestPackets.QuestSnapshotUpdated = Packet("QuestSnapshotUpdated", Packet.Any)

-- Server -> Client: pushed when a quest transitions to completed state.
-- Payload: questId, questName.
QuestPackets.QuestCompleted = Packet("QuestCompleted", {
	QuestId = Packet.String,
	QuestName = Packet.String,
})

return QuestPackets
