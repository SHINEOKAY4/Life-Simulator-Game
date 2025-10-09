--!strict
-- ReplicatedStorage/Network/ResidentsPackets.lua

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Packet = require(ReplicatedStorage.Packages.Packet)

local ResidentsPackets = {}

ResidentsPackets.PromptResidentCreation = Packet("PromptResidentCreation")

ResidentsPackets.AddResidentRequest = Packet("CreateResidentRequest", {
	Name = Packet.String,
	Gender = Packet.String,
}):Response(Packet.Boolean8, Packet.StringLong)

ResidentsPackets.DeleteResidentRequest =
	Packet("DeleteResidentRequest", Packet.String):Response(Packet.Boolean8, Packet.StringLong)

ResidentsPackets.PlayerResidentDelta = Packet("PlayerResidentDelta", {
	UserId = Packet.NumberF64,
	ResidentName = Packet.String, -- Mainly for deletions
	ResidentDelta = {
		{
			Name = Packet.String,
			Age = Packet.NumberU8,
			Gender = Packet.String,
			Traits = { Packet.String },
			Occupation = Packet.String,
			Needs = {
				Hunger = Packet.NumberU8,
				Energy = Packet.NumberU8,
				Hygiene = Packet.NumberU8,
				Fun = Packet.NumberU8,
				Social = Packet.NumberU8,
			},
		},
	},
})
ResidentsPackets.PlayersResidentsSync = Packet("ResidentStateSync", {
	UserId = Packet.NumberF64,
	Residents = {
		{
			Name = Packet.String,
			Age = Packet.NumberU8,
			Gender = Packet.String,
			Traits = { Packet.String },
			Occupation = Packet.String,
			Needs = {
				Hunger = Packet.NumberU8,
				Energy = Packet.NumberU8,
				Hygiene = Packet.NumberU8,
				Fun = Packet.NumberU8,
				Social = Packet.NumberU8,
			},
		},
	},
})

return ResidentsPackets
