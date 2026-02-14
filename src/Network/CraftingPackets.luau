--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Packet = require(ReplicatedStorage.Packages.Packet)

local CraftingPackets = {}

CraftingPackets.GetCraftingData = Packet("GetCraftingData"):Response(Packet.Boolean8, Packet.StringLong, Packet.Any)
CraftingPackets.StartCrafting = Packet("StartCrafting", Packet.String, Packet.String):Response(
	Packet.Boolean8,
	Packet.StringLong,
	Packet.Any
)

CraftingPackets.CraftStarted = Packet("CraftStarted", {
	JobId = Packet.String,
	RecipeId = Packet.String,
	StationId = Packet.String,
	EndsAt = Packet.NumberF64,
})

CraftingPackets.CraftCompleted = Packet("CraftCompleted", {
	JobId = Packet.String,
	RecipeId = Packet.String,
	StationId = Packet.String,
	OutputItemId = Packet.String,
	OutputQuantity = Packet.NumberU16,
	SkillGains = Packet.Any,
	ProgressionExperience = Packet.NumberU16,
})

CraftingPackets.CraftFailed = Packet("CraftFailed", {
	JobId = Packet.String,
	RecipeId = Packet.String,
	Reason = Packet.StringLong,
})

return CraftingPackets
