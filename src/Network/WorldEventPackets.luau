--!strict
-- ReplicatedStorage/Network/WorldEventPackets.lua

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Packet = require(ReplicatedStorage.Packages.Packet)

local WorldEventPackets = {}

local buffPayload = {
	Type = Packet.String,
	Value = Packet.NumberF64,
	Label = Packet.String,
}

local rotationEventPayload = {
	Id = Packet.String,
	Name = Packet.String,
	Description = Packet.StringLong,
	Kind = Packet.String,
	StartsAt = Packet.NumberF64,
	EndsAt = Packet.NumberF64,
	Buffs = { buffPayload },
}

local statePayload = {
	RotationId = Packet.String,
	RotationEndsAt = Packet.NumberF64,
	ActiveEvents = { rotationEventPayload },
}

WorldEventPackets.StateSnapshot = Packet("WorldEventStateSnapshot", statePayload)

WorldEventPackets.RequestState = Packet("WorldEventRequestState"):Response(Packet.Boolean8, statePayload)

return WorldEventPackets
