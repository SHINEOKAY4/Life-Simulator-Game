--!strict
-- ReplicatedStorage/Network/PayrollPackets.luau

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Packet = require(ReplicatedStorage.Packages.Packet)

local PayrollPackets = {}

PayrollPackets.PayrollUpdate = Packet("PayrollUpdate", {
	PendingAmount = Packet.NumberU32,
	CycleAmount = Packet.NumberU32,
	CollectedAmount = Packet.NumberU32,
	NextPayoutClockTime = Packet.NumberF32,
	TimeRemaining = Packet.NumberF32,
	MailboxEmpty = Packet.Boolean8,
})

PayrollPackets.RequestPayrollInfo = Packet("RequestPayrollInfo"):Response({
	TotalPending = Packet.NumberU32,
	PendingAmount = Packet.NumberU32,
	NextPayoutClockTime = Packet.NumberF32,
	TimeRemaining = Packet.NumberF32,
})

return PayrollPackets
