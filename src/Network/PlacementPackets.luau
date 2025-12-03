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
	DefaultLevel = Packet.NumberU8,
	MaxLevel = Packet.NumberU8,
	FloorHeightStuds = Packet.NumberF32,
}, { Packet.Boolean8 }, {
	{
		id = Packet.String,
		cellX = Packet.NumberU16,
		cellZ = Packet.NumberU16,
		facing = Packet.Static1,
		WidthCells = Packet.NumberU16,
		DepthCells = Packet.NumberU16,
		Metadata = Packet.Any,
		Level = Packet.NumberU8,
	},
}, {
	{
		key = Packet.String,
		id = Packet.String,
		parentKey = Packet.String,
		LocalPosition = {
			X = Packet.NumberF32,
			Y = Packet.NumberF32,
			Z = Packet.NumberF32,
		},
		LocalRotationY = Packet.NumberF32,
		Metadata = Packet.Any,
	},
})

PlacementPackets.RenamePlotRequest =
	Packet("RenamePlotRequest", Packet.StringLong):Response(Packet.Boolean8, Packet.StringLong, Packet.StringLong)

-- [[ Build Packets ]]

PlacementPackets.PlaceRequest = Packet("PlaceRequest", {
	ItemId = Packet.String,
	CellX = Packet.NumberU8,
	CellZ = Packet.NumberU8,
	Facing = Packet.Static1,
	Level = Packet.NumberU8,
	SurfaceId = Packet.String,
	SubSlotId = Packet.String,
	WallMountEnabled = Packet.Boolean8,
	WallMountCellX = Packet.NumberU16,
	WallMountCellZ = Packet.NumberU16,
	WallMountFacing = Packet.Static1,
	WallMountHeightOffset = Packet.NumberF32,
	WallMountPosX = Packet.NumberF32,
	WallMountPosY = Packet.NumberF32,
	WallMountPosZ = Packet.NumberF32,
	WallMountNormalX = Packet.NumberF32,
	WallMountNormalY = Packet.NumberF32,
	WallMountNormalZ = Packet.NumberF32,
	CeilingMountEnabled = Packet.Boolean8,
	CeilingMountCellX = Packet.NumberU16,
	CeilingMountCellZ = Packet.NumberU16,
	CeilingMountLevel = Packet.NumberU8,
	CeilingMountDropStuds = Packet.NumberF32,
	CeilingMountRotationY = Packet.NumberF32,
	CeilingMountPosX = Packet.NumberF32,
	CeilingMountPosY = Packet.NumberF32,
	CeilingMountPosZ = Packet.NumberF32,
	CeilingMountNormalX = Packet.NumberF32,
	CeilingMountNormalY = Packet.NumberF32,
	CeilingMountNormalZ = Packet.NumberF32,
	WindowEnabled = Packet.Boolean8,
	WindowHeightOffset = Packet.NumberF32,
}):Response(Packet.Boolean8, Packet.StringLong)

PlacementPackets.PlaceFloorAreaRequest = Packet("PlaceFloorAreaRequest", {
	ItemId = Packet.String,
	StartCellX = Packet.NumberU16,
	StartCellZ = Packet.NumberU16,
	EndCellX = Packet.NumberU16,
	EndCellZ = Packet.NumberU16,
	WidthCells = Packet.NumberU16,
	DepthCells = Packet.NumberU16,
	Level = Packet.NumberU8,
	SurfaceId = Packet.String,
}):Response(Packet.Boolean8, Packet.StringLong)

PlacementPackets.PlaceWallStripRequest = Packet("PlaceWallStripRequest", {
	ItemId = Packet.String,
	Facing = Packet.Static1,
	Orientation = Packet.Static2,
	StartCellX = Packet.NumberU16,
	StartCellZ = Packet.NumberU16,
	EndCellX = Packet.NumberU16,
	EndCellZ = Packet.NumberU16,
	Level = Packet.NumberU8,
	SurfaceId = Packet.String,
}):Response(Packet.Boolean8, Packet.StringLong)

PlacementPackets.PlaceRoofAreaRequest = Packet("PlaceRoofAreaRequest", {
	ItemId = Packet.String,
	StartCellX = Packet.NumberU16,
	StartCellZ = Packet.NumberU16,
	EndCellX = Packet.NumberU16,
	EndCellZ = Packet.NumberU16,
	Level = Packet.NumberU8,
}):Response(Packet.Boolean8, Packet.StringLong)

PlacementPackets.PlacementDelta = Packet("PlacementDelta", {
	Action = Packet.Static2,
	Item = {
		ItemId = Packet.String,
		CellX = Packet.NumberU8,
		CellZ = Packet.NumberU8,
		Facing = Packet.Static1,
		WidthCells = Packet.NumberU16,
		DepthCells = Packet.NumberU16,
		Metadata = Packet.Any,
		Level = Packet.NumberU8,
		SubSlotId = Packet.String,
	},
})

PlacementPackets.SurfaceMountDelta = Packet("SurfaceMountDelta", {
	Action = Packet.Static2,
	Mount = {
		Key = Packet.String,
		ParentKey = Packet.String,
		ItemId = Packet.String,
		LocalPosition = {
			X = Packet.NumberF32,
			Y = Packet.NumberF32,
			Z = Packet.NumberF32,
		},
		LocalRotationY = Packet.NumberF32,
		Metadata = Packet.Any,
	},
})

PlacementPackets.PlaceSurfaceMountRequest = Packet("PlaceSurfaceMountRequest", {
	ItemId = Packet.String,
	ParentKey = Packet.String,
	LocalPosX = Packet.NumberF32,
	LocalPosY = Packet.NumberF32,
	LocalPosZ = Packet.NumberF32,
	LocalRotationY = Packet.NumberF32,
	Metadata = Packet.Any,
}):Response(Packet.Boolean8, Packet.StringLong)

PlacementPackets.DestroySurfaceMountRequest = Packet("DestroySurfaceMountRequest", {
	MountKey = Packet.String,
}):Response(Packet.Boolean8, Packet.StringLong)

PlacementPackets.PaintSurfaceRequest = Packet("PaintSurfaceRequest", {
	PlacementKey = Packet.String,
	SurfaceId = Packet.String,
	PaintColor = Packet.Any,
}):Response(Packet.Boolean8, Packet.StringLong)

PlacementPackets.PaintSurfaceBatchRequest = Packet("PaintSurfaceBatchRequest", {
	PlacementKeys = { Packet.String },
	SurfaceId = Packet.String,
	PaintColor = Packet.Any,
}):Response(Packet.Boolean8, Packet.StringLong)

PlacementPackets.DestroyRequest = Packet("DestroyRequest", {
	ItemId = Packet.String,
	CellX = Packet.NumberU8,
	CellZ = Packet.NumberU8,
	Facing = Packet.Static1,
	Level = Packet.NumberU8,
	SubSlotId = Packet.String,
}):Response(Packet.Boolean8, Packet.StringLong)

PlacementPackets.MoveRequest = Packet("MoveRequest", {
	ItemId = Packet.String,
	FromCellX = Packet.NumberU8,
	FromCellZ = Packet.NumberU8,
	FromFacing = Packet.Static1,
	FromLevel = Packet.NumberU8,
	ToCellX = Packet.NumberU8,
	ToCellZ = Packet.NumberU8,
	ToFacing = Packet.Static1, -- allow rotate-during-move; client can pass old facing if not rotating
	ToLevel = Packet.NumberU8,
	SubSlotId = Packet.String,
}):Response(Packet.Boolean8, Packet.StringLong)

PlacementPackets.RotateRequest = Packet("RotateRequest", {
	ItemId = Packet.String,
	FromKey = Packet.String,
	ToFacing = Packet.Static1,
}):Response(Packet.Boolean8, Packet.StringLong)

PlacementPackets.UtilityUpdate = Packet("UtilityUpdate", {
	{
		Key = Packet.String,
		Metadata = Packet.Any,
	},
})

PlacementPackets.ConnectUtilityRequest = Packet("ConnectUtilityRequest", {
	SourceKey = Packet.String,
	TargetKey = Packet.String,
}):Response(Packet.Boolean8, Packet.StringLong)

PlacementPackets.DisconnectUtilityRequest = Packet("DisconnectUtilityRequest", {
	SourceKey = Packet.String,
	TargetKey = Packet.String,
}):Response(Packet.Boolean8, Packet.StringLong)

PlacementPackets.TogglePowerRequest = Packet("TogglePowerRequest", {
	Key = Packet.String,
	IsOn = Packet.Boolean8,
}):Response(Packet.Boolean8, Packet.StringLong)

-- Room replication (server → client) - replaces client-side room detection
PlacementPackets.RoomDataSync = Packet("RoomDataSync", {
	Level = Packet.NumberU8,
	Rooms = {
		{
			Id = Packet.NumberU16,
			RoomKey = Packet.String,
			MinCellX = Packet.NumberU16,
			MaxCellX = Packet.NumberU16,
			MinCellZ = Packet.NumberU16,
			MaxCellZ = Packet.NumberU16,
			CellIndices = { Packet.NumberU16 },
			IsEnclosed = Packet.Boolean8,
		},
	},
})

return PlacementPackets
