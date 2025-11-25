--!strict
-- Network packets for billing system

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Packet = require(ReplicatedStorage.Packages.Packet)

local BillingPackets = {}

-- Client requests to pay the current bill
BillingPackets.PayBill = Packet("PayBill"):Response(Packet.Boolean8, Packet.StringLong)

return BillingPackets
