--!strict
-- Network packets for billing system

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Packet = require(ReplicatedStorage.Packages.Packet)

local BillingPackets = {}

-- Client requests to pay the current bill
BillingPackets.PayBill = Packet("PayBill"):Response(Packet.Boolean8, Packet.StringLong)

-- Client -> Server: request the player's current internet tier name.
-- Response: success flag, tier name string (e.g. "None", "Basic", "Standard", "Premium").
BillingPackets.GetInternetTier = Packet("BillingGetInternetTier"):Response(Packet.Boolean8, Packet.String)

-- Client -> Server: set the player's internet tier.
-- Payload: tier name string.
-- Response: success flag, accepted tier name (or error string).
BillingPackets.SetInternetTier = Packet("BillingSetInternetTier", Packet.String):Response(Packet.Boolean8, Packet.String)

return BillingPackets
