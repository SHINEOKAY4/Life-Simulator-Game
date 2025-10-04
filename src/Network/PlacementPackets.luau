--!strict
-- ReplicatedStorage/Network/PlacementPackets.lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Packet = require(ReplicatedStorage.Packages.Packet)

local PlacementPackets = {}

-- [[ Plot Packets ]]
PlacementPackets.ClaimRequest = Packet("ClaimRequest", Packet.NumberU8):Response(Packet.Boolean8, Packet.StringLong)

PlacementPackets.UnlockChunkRequest =
	Packet("UnlockChunkRequest", Packet.NumberU8, Packet.NumberU8):Response(Packet.Boolean8, Packet.StringLong)

PlacementPackets.PlotStateUnlockDelta = Packet("PlotStateUnlockDelta", { Packet.NumberU16 })

PlacementPackets.PlotStateSync = Packet("PlotStateSync", {
	ChunkSizeInCells = Packet.NumberU8,
	ChunkColumns = Packet.NumberU8,
	ChunkRows = Packet.NumberU8,
}, { Packet.Boolean8 }, {
	{
		id = Packet.String,
		cellX = Packet.NumberU16,
		cellZ = Packet.NumberU16,
		facing = Packet.String,
	},
})

-- [[ Build Packets ]]

PlacementPackets.PlaceRequest = Packet("PlaceRequest", {
	ItemId = Packet.String,
	CellX = Packet.NumberU8,
	CellZ = Packet.NumberU8,
	Facing = Packet.String,
}):Response(Packet.Boolean8, Packet.StringLong)

PlacementPackets.PlacementDelta = Packet("PlacementDelta", {
	Action = Packet.String,
	Item = {
		ItemId = Packet.String,
		CellX = Packet.NumberU8,
		CellZ = Packet.NumberU8,
		Facing = Packet.String,
	},
})

PlacementPackets.DestroyRequest = Packet("DestroyRequest", {
	ItemId = Packet.String,
	CellX = Packet.NumberU8,
	CellZ = Packet.NumberU8,
	Facing = Packet.String,
}):Response(Packet.Boolean8, Packet.StringLong)

PlacementPackets.MoveRequest = Packet("MoveRequest", {
	ItemId = Packet.String,
	FromCellX = Packet.NumberU8,
	FromCellZ = Packet.NumberU8,
	FromFacing = Packet.String,
	ToCellX = Packet.NumberU8,
	ToCellZ = Packet.NumberU8,
	ToFacing = Packet.String, -- allow rotate-during-move; client can pass old facing if not rotating
}):Response(Packet.Boolean8, Packet.StringLong)

PlacementPackets.RotateRequest = Packet("RotateRequest", {
	ItemId = Packet.String,
	FromKey = Packet.String,
	ToFacing = Packet.String,
}):Response(Packet.Boolean8, Packet.StringLong)

return PlacementPackets
