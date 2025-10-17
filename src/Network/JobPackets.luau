--!strict
-- ReplicatedStorage/Network/JobPackets.lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Packet = require(ReplicatedStorage.Packages.Packet)

local JobPackets = {}

JobPackets.RequestJob = Packet("RequestJob", Packet.String, Packet.String):Response(Packet.Boolean8, Packet.StringLong)

return JobPackets
