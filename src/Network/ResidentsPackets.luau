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

ResidentsPackets.ResidentStateSync = Packet("ResidentStateSync", {
	{
		Name = Packet.String,
		Age = Packet.NumberU8,
		Occupation = Packet.String,
		Gender = Packet.String,
		Cash = Packet.NumberU32,
		Mood = Packet.NumberU8,
		Intelligence = Packet.NumberU8,
		Fitness = Packet.NumberU8,
		Social = Packet.NumberU8,
		Hunger = Packet.NumberU8,
		Energy = Packet.NumberU8,
		Hygiene = Packet.NumberU8,
		Fun = Packet.NumberU8,
	},
})

return ResidentsPackets
