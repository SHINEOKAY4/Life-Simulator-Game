--!strict
-- ReplicatedStorage/Shared/Definitions/Catalog/Electronics.luau

local Electronics = {
	LivingRoom = {
		FlatScreenTV = {
			Name = "Flat Screen TV",
			PlacementType = "WallMounted",
			StationType = "FunStation",
			Station = true,
			RequiresPower = true,
			maxOccupancy = 3,
			WidthCells = 1,
			DepthCells = 1,
			Facing = { "North", "East", "South", "West", "NorthEast", "NorthWest", "SouthEast", "SouthWest" },
			Cost = 750,
			Description = "Wall-mounted entertainment that keeps residents engaged.",
			WallMountConfig = {
				AttachmentSurface = "Back",
				OffsetFromWall = 0.15,
				MinHeight = 2.5,
				MaxHeight = 5,
				RequiresFloorSupport = false,
				CollisionCheck = true,
				VisualSize = Vector3.new(2.4, 1.4, 0.3),
			},
			Rules = {
				RequiresFloorUnderAllCells = false,
			},
			Tags = { "Entertainment", "WallMounted", "Electronics" },
			ModelPath = { "Electronics", "FlatScreenTV" },
			AssetId = 0,
			StationEffects = {
				Effects = {
					Facing = { "North", "East", "South", "West", "NorthEast", "NorthWest", "SouthEast", "SouthWest" },
				},
			},
		},
	},
}

return Electronics
