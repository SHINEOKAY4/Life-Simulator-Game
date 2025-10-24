--!strict
-- ReplicatedStorage/Network/PayrollPackets.luau

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Packet = require(ReplicatedStorage.Packages.Packet)

local PayrollPackets = {}

PayrollPackets.PayrollUpdate = Packet("PayrollUpdate", {
	PayoutAmount = Packet.NumberU32,
	NextPayoutClockTime = Packet.NumberF32,
})

PayrollPackets.RequestPayrollInfo = Packet("RequestPayrollInfo"):Response({
	TotalPending = Packet.NumberU32,
	NextPayoutClockTime = Packet.NumberF32,
	TimeRemaining = Packet.NumberF32,
})

return PayrollPackets
