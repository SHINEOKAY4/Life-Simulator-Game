--!strict
-- ReplicatedStorage/Network/WoodcuttingPackets.luau
-- Packet declarations for the woodcutting / tree chopping system.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packet = require(ReplicatedStorage.Packages.Packet)

local WoodcuttingPackets = {}

WoodcuttingPackets.RequestForestSnapshot = Packet("WoodcuttingForestSnapshotRequest"):Response({
	Timestamp = Packet.NumberF32,
	Trees = {
		{
			Guid = Packet.String,
			TypeId = Packet.String,
			State = Packet.String,
			RespawnAt = Packet.NumberF32,
			Position = Packet.Vector3F32,
			BusyUserId = Packet.NumberU32,
		},
	},
})

WoodcuttingPackets.TreeStateChanged = Packet("WoodcuttingTreeStateChanged", {
	Guid = Packet.String,
	TypeId = Packet.String,
	State = Packet.String,
	RespawnAt = Packet.NumberF32,
	Position = Packet.Vector3F32,
	BusyUserId = Packet.NumberU32,
})

WoodcuttingPackets.TreeChopRequest =
	Packet("WoodcuttingTreeChopRequest", Packet.String):Response(Packet.Boolean8, Packet.StringLong, Packet.NumberF32)

WoodcuttingPackets.TreeYieldNotice = Packet("WoodcuttingTreeYieldNotice", {
	Guid = Packet.String,
	ItemDefId = Packet.String,
	Quantity = Packet.NumberU16,
})

WoodcuttingPackets.SellLogsRequest = Packet("WoodcuttingSellLogsRequest", Packet.String, Packet.NumberU16):Response(
	Packet.Boolean8,
	Packet.StringLong,
	Packet.NumberU32
)

return WoodcuttingPackets
