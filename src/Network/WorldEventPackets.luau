--!strict
-- ReplicatedStorage/Network/WorldEventPackets.lua

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Packet = require(ReplicatedStorage.Packages.Packet)

local WorldEventPackets = {}

local careerBoostPayload = {
	Amount = Packet.NumberF32,
	ExpiresAt = Packet.NumberF64,
	SourceId = Packet.String,
	Description = Packet.StringLong,
	Active = Packet.Boolean8,
}

local rotationEventPayload = {
	Id = Packet.String,
	Name = Packet.String,
	Description = Packet.StringLong,
	Kind = Packet.String,
	StartsAt = Packet.NumberF64,
	EndsAt = Packet.NumberF64,
}

local statePayload = {
	RotationId = Packet.String,
	RotationEndsAt = Packet.NumberF64,
	ActiveEvents = { rotationEventPayload },
	CareerBoost = careerBoostPayload,
}

WorldEventPackets.StateSnapshot = Packet("WorldEventStateSnapshot", statePayload)

WorldEventPackets.CareerBoostGranted = Packet("WorldEventCareerBoostGranted", careerBoostPayload)
WorldEventPackets.CareerBoostExpired = Packet("WorldEventCareerBoostExpired", {
	SourceId = Packet.String,
	Description = Packet.StringLong,
})
WorldEventPackets.CareerBoostConsumed = Packet("WorldEventCareerBoostConsumed", {
	SourceId = Packet.String,
	Description = Packet.StringLong,
})

WorldEventPackets.RequestState = Packet("WorldEventRequestState"):Response(Packet.Boolean8, statePayload)

return WorldEventPackets
