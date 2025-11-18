--!strict
-- ReplicatedStorage/Network/TenantPackets.luau

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Packet = require(ReplicatedStorage.Packages.Packet)

local TenantPackets = {}

TenantPackets.ProspectSpawn = Packet("TenantProspectSpawn", {
	ProspectId = Packet.String,
	Slot = Packet.NumberU8,
	Name = Packet.String,
	TierId = Packet.String,
	RentPerInterval = Packet.NumberU32,
	RentIntervalSeconds = Packet.NumberU32,
	Deposit = Packet.NumberU32,
	LeaseSeconds = Packet.NumberU32,
})

TenantPackets.ProspectRemoved = Packet("TenantProspectRemoved", {
	ProspectId = Packet.String,
	Slot = Packet.NumberU8,
	Reason = Packet.String,
})

TenantPackets.ProspectPrompt = Packet("TenantProspectPrompt", {
	ProspectId = Packet.String,
	Slot = Packet.NumberU8,
	Name = Packet.String,
	TierId = Packet.String,
	RentPerInterval = Packet.NumberU32,
	RentIntervalSeconds = Packet.NumberU32,
	Deposit = Packet.NumberU32,
	LeaseSeconds = Packet.NumberU32,
})

TenantPackets.ProspectDecision =
	Packet("TenantProspectDecision", Packet.String, Packet.String):Response(Packet.Boolean8, Packet.StringLong)

return TenantPackets
