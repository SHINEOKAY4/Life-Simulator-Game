--!strict
-- ReplicatedStorage/Network/MailboxPackets.luau
-- Remotes for mailbox rent accumulation and payouts.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Packet = require(ReplicatedStorage.Packages.Packet)

local MailboxPackets = {}

MailboxPackets.BalanceUpdate = Packet("MailboxBalanceUpdate", {
	Balance = Packet.NumberU32,
})

MailboxPackets.CollectionEffect = Packet("MailboxCollectionEffect", {
	Amount = Packet.NumberU32,
})

MailboxPackets.CollectRequest =
	Packet("MailboxCollectRequest"):Response(Packet.Boolean8, Packet.NumberU32, Packet.StringLong)

-- Server-to-client: full income summary (balance + rate + seconds until next payout drip).
MailboxPackets.IncomeSummary = Packet("MailboxIncomeSummary", {
	Balance = Packet.NumberU32,
	IncomePerSecond = Packet.NumberF32,
	NextRentTick = Packet.NumberU32,
})

return MailboxPackets
