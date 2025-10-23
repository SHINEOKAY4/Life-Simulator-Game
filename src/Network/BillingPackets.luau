--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packet = require(ReplicatedStorage.Packages.Packet)

local BillingPackets = {}

BillingPackets.BillingBreakdownUpdate = Packet("BillingBreakdownUpdate", {
	PlotTax = Packet.NumberU16,
	Electric = Packet.NumberU16,
	Food = Packet.NumberU16,
	Total = Packet.NumberU16,
	OutstandingTotal = Packet.NumberU16,
	DueClockTime = Packet.NumberF32,
	TimeRemaining = Packet.NumberF32,
})

BillingPackets.RequestBillingInfo = Packet("RequestBillingInfo"):Response({
	PlotTax = Packet.NumberU16,
	Electric = Packet.NumberU16,
	Food = Packet.NumberU16,
	Total = Packet.NumberU16,
	OutstandingTotal = Packet.NumberU16,
	DueClockTime = Packet.NumberF32,
	TimeRemaining = Packet.NumberF32,
})

BillingPackets.PayBillRequest = Packet("PayBillRequest"):Response(Packet.Boolean8, Packet.StringLong)

return BillingPackets
