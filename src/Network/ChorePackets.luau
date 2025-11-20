--!strict
-- ReplicatedStorage/Network/ChorePackets.luau

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Packet = require(ReplicatedStorage.Packages.Packet)

local ChorePackets = {}

ChorePackets.ChoreSpawned = Packet("ChoreSpawned", {
	ChoreId = Packet.String,
	Type = Packet.String, -- "Trash", "Puddle", "BrokenItem"
	Position = Packet.Vector3F32,
	PlotIndex = Packet.NumberU8,
	TargetId = Packet.String, -- Optional: ID of the item broken
})

ChorePackets.ChoreRemoved = Packet("ChoreRemoved", {
	ChoreId = Packet.String,
	Reason = Packet.String,
})

ChorePackets.CompleteChore = Packet("CompleteChore", Packet.String):Response(Packet.Boolean8, Packet.String)

return ChorePackets
