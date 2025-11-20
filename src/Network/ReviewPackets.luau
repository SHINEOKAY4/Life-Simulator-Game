--!strict
-- Network/ReviewPackets.luau
-- Defines network events for the tenant review system.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Packet = require(ReplicatedStorage.Packages.Packet)

local ReviewPackets = {}

-- Server -> Client: A new review has been posted
ReviewPackets.NewReview = Packet("NewReview", {
	Review = {
		Id = Packet.String,
		TenantName = Packet.String,
		Rating = Packet.NumberU8,
		Comment = Packet.String,
		Timestamp = Packet.NumberF64,
		Traits = { Packet.String },
	},
})

-- Client -> Server: Request history of reviews
ReviewPackets.GetReviewsRequest = Packet("GetReviewsRequest"):Response({
	{
		Id = Packet.String,
		TenantName = Packet.String,
		Rating = Packet.NumberU8,
		Comment = Packet.String,
		Timestamp = Packet.NumberF64,
		Traits = { Packet.String },
	},
})

return ReviewPackets
