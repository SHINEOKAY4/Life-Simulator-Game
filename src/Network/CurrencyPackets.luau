--!strict
-- ReplicatedStorage/Network/CurrencyPackets.lua

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Packet = require(ReplicatedStorage.Packages.Packet)

local CurrencyPackets = {}

CurrencyPackets.PlayerCurrencyDelta = Packet("PlayerCurrencyDelta", {
	CurrencyName = Packet.String,
	Amount = Packet.NumberS32,
	Source = Packet.String,
	ResidentName = Packet.String,
})

return CurrencyPackets
