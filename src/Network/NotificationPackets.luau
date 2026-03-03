--!strict
-- ReplicatedStorage/Network/NotificationPackets.luau
-- Packets for server-driven notifications.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Packet = require(ReplicatedStorage.Packages.Packet)

local NotificationPackets = {}

local NotificationPayload = {
	Id = Packet.NumberU32,
	Category = Packet.String,
	Title = Packet.String,
	Body = Packet.StringLong,
	Icon = Packet.String,
	Priority = Packet.NumberU8,
	Duration = Packet.NumberU16,
	Timestamp = Packet.NumberF64,
	Read = Packet.Boolean8,
	Metadata = Packet.Any,
}

NotificationPackets.StateSnapshot = Packet("NotificationStateSnapshot", {
	Queue = { NotificationPayload },
})

NotificationPackets.NotificationDelta = Packet("NotificationDelta", NotificationPayload)

return NotificationPackets
