--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Packet = require(ReplicatedStorage.Packages.Packet)

local TipsPackets = {
	TipDropped = Packet("TipDropped", {
		TipId = Packet.String,
		Amount = Packet.NumberU16,
		SourcePosition = Packet.Vector3F32,
		Reason = Packet.String,
	}),
	ClaimTip = Packet("ClaimTip", {
		TipId = Packet.String,
	}),
}

return TipsPackets
