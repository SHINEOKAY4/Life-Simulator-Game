--!strict
-- ReplicatedStorage/Network/TenantHelpPackets.luau

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Packet = require(ReplicatedStorage.Packages.Packet)

local TenantHelpPackets = {}

TenantHelpPackets.HelpRequestSpawn = Packet("TenantHelpRequestSpawn", {
	RequestId = Packet.String,
	TenantId = Packet.String,
	TenantName = Packet.String,
	Need = Packet.String,
	ExpiresAt = Packet.NumberF64,
	RewardXP = Packet.NumberU32,
	RewardCash = Packet.NumberU32,
})

TenantHelpPackets.HelpRequestRemoved = Packet("TenantHelpRequestRemoved", {
	RequestId = Packet.String,
	TenantId = Packet.String,
	Reason = Packet.String,
})

TenantHelpPackets.HelpInteraction =
	Packet("TenantHelpInteraction", Packet.String):Response(Packet.Boolean8, Packet.StringLong)

return TenantHelpPackets
