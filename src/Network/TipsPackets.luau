--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Packet = require(ReplicatedStorage.Packages.Packet)

local TipsPackets = {
	TipDropped = Packet("TipDropped", {
		Amount = Packet.NumberU16,
		SourcePosition = Packet.Vector3F32,
	}),
}

return TipsPackets
