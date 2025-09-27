--!strict
-- ReplicatedStorage/Network/PlacementPackets.luau
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Packet = require(ReplicatedStorage.Packages.Packet)

local PlacementPackets = {}

PlacementPackets.ClaimRequest = Packet("ClaimRequest", Packet.NumberU8):Response(Packet.Boolean8, Packet.StringLong)
PlacementPackets.UnlockChunkRequest =
	Packet("UnlockChunkRequest", Packet.NumberU8, Packet.NumberU8):Response(Packet.Boolean8, Packet.StringLong)

return PlacementPackets
