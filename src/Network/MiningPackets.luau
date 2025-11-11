--!strict
-- ReplicatedStorage/Network/MiningPackets.luau
-- Packet declarations for the mining system (rock state sync, requests, yields).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packet = require(ReplicatedStorage.Packages.Packet)

local MiningPackets = {}

MiningPackets.RequestMineSnapshot = Packet("MiningSnapshotRequest"):Response({
	Timestamp = Packet.NumberF32,
	Rocks = {
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

MiningPackets.RockStateChanged = Packet("MiningRockStateChanged", {
	Guid = Packet.String,
	TypeId = Packet.String,
	State = Packet.String,
	RespawnAt = Packet.NumberF32,
	Position = Packet.Vector3F32,
	BusyUserId = Packet.NumberU32,
})

MiningPackets.RockMineRequest =
	Packet("MiningRockMineRequest", Packet.String):Response(Packet.Boolean8, Packet.StringLong, Packet.NumberF32)

MiningPackets.RockYieldNotice = Packet("MiningRockYieldNotice", {
	Guid = Packet.String,
	ItemDefId = Packet.String,
	Quantity = Packet.NumberU16,
})

MiningPackets.SellOreRequest = Packet("MiningSellOreRequest", Packet.String, Packet.NumberU16):Response(
	Packet.Boolean8,
	Packet.StringLong,
	Packet.NumberU32
)

return MiningPackets
