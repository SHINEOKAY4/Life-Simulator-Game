--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Packet = require(ReplicatedStorage.Packages.Packet)

local TradePackets = {}

-- Client -> Server: Request a trade with another player
-- Args: recipientUserId (number), initiatorItemIds (serialised), recipientItemIds (serialised)
TradePackets.RequestTrade = Packet(
	"RequestTrade",
	Packet.NumberU32,
	Packet.Any,
	Packet.Any
):Response(Packet.Boolean8, Packet.StringLong, Packet.Any)

-- Client -> Server: Accept a pending trade
-- Args: tradeId (string)
TradePackets.AcceptTrade = Packet("AcceptTrade", Packet.String):Response(
	Packet.Boolean8,
	Packet.StringLong
)

-- Client -> Server: Decline a pending trade
-- Args: tradeId (string)
TradePackets.DeclineTrade = Packet("DeclineTrade", Packet.String):Response(
	Packet.Boolean8,
	Packet.StringLong
)

-- Client -> Server: Cancel an outgoing trade
-- Args: tradeId (string)
TradePackets.CancelTrade = Packet("CancelTrade", Packet.String):Response(
	Packet.Boolean8,
	Packet.StringLong
)

-- Client -> Server: Request trade data (pending incoming + outgoing)
TradePackets.GetTradeData = Packet("GetTradeData"):Response(
	Packet.Boolean8,
	Packet.StringLong,
	Packet.Any
)

-- Server -> Client: Notify of incoming trade request
TradePackets.TradeIncoming = Packet("TradeIncoming", {
	TradeId = Packet.String,
	InitiatorName = Packet.String,
	InitiatorUserId = Packet.NumberU32,
	InitiatorItems = Packet.Any,
	RequestedItems = Packet.Any,
})

-- Server -> Client: Trade resolved (accepted/declined/cancelled/expired)
TradePackets.TradeResolved = Packet("TradeResolved", {
	TradeId = Packet.String,
	Status = Packet.String,
	Message = Packet.StringLong,
})

return TradePackets
