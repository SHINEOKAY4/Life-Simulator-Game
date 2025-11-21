--!strict
-- ReplicatedStorage/Network/ResidentsPackets.lua

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Packet = require(ReplicatedStorage.Packages.Packet)

local ResidentsPackets = {}

ResidentsPackets.DeleteResidentRequest =
	Packet("DeleteResidentRequest", Packet.String):Response(Packet.Boolean8, Packet.StringLong)

ResidentsPackets.PlayerResidentDelta = Packet("PlayerResidentDelta", {
	UserId = Packet.NumberF64,
	ResidentName = Packet.String, -- Mainly for deletions
	ResidentDelta = {
		{
			Name = Packet.String,
			TenantId = Packet.String,
			Traits = { Packet.String },
		},
	},
})
ResidentsPackets.PlayersResidentsSync = Packet("ResidentStateSync", {
	UserId = Packet.NumberF64,
	Residents = {
		{
			Name = Packet.String,
			TenantId = Packet.String,
			Traits = { Packet.String },
		},
	},
})

ResidentsPackets.ResidentChatMessage = Packet("ResidentChatMessage", {
	Speaker = Packet.Instance,
	Text = Packet.StringLong,
	Kind = Packet.String,
	Duration = Packet.NumberF32,
})

return ResidentsPackets
