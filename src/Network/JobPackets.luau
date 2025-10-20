--!strict
-- ReplicatedStorage/Network/JobPackets.lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Packet = require(ReplicatedStorage.Packages.Packet)

local JobPackets = {}

JobPackets.RequestJob = Packet("RequestJob", Packet.String, Packet.String):Response(Packet.Boolean8, Packet.StringLong)
JobPackets.StartResidentShift = Packet("StartResidentShift", Packet.String):Response(Packet.Boolean8, Packet.StringLong)
JobPackets.StopResidentShift =
	Packet("StopResidentShift", Packet.String):Response(Packet.Boolean8, Packet.StringLong, Packet.NumberS32)

return JobPackets
