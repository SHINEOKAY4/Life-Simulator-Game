--!strict
-- ReplicatedStorage/Network/ChorePackets.luau

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Packet = require(ReplicatedStorage.Packages.Packet)

local ChorePackets = {}

ChorePackets.ChoreSpawned = Packet("ChoreSpawned", {
	ChoreId = Packet.String,
	Type = Packet.String, -- "Trash", "Puddle", "BrokenItem"
	TenantName = Packet.String,
	PlotIndex = Packet.NumberU8,
	Metadata = Packet.Any,
})

ChorePackets.ChoreRemoved = Packet("ChoreRemoved", {
	ChoreId = Packet.String,
	Reason = Packet.String,
})

ChorePackets.CompleteChore = Packet("CompleteChore", Packet.String):Response(Packet.Boolean8, Packet.String)

return ChorePackets
