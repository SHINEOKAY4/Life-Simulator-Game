--!strict
-- ReplicatedStorage/Network/GigPackets.lua

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Packet = require(ReplicatedStorage.Packages.Packet)

local GigPackets = {}

GigPackets.RequestStart =
	Packet("GigRequestStart", Packet.String):Response(Packet.Boolean8, Packet.StringLong, Packet.StringLong)
GigPackets.SubmitScore = Packet("GigSubmitScore", Packet.String, Packet.String):Response(
	Packet.Boolean8,
	Packet.StringLong,
	Packet.NumberF32
)

return GigPackets
