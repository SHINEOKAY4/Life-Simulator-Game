--!strict
-- ReplicatedStorage/Shared/Definitions/Catalog/Doors.luau

local Doors = {
	WoodenDoor = {
		Name = "WoodenDoor",
		PlacementType = "Wall",
		WidthCells = 1,
		DepthCells = 1,
		Facing = { "North", "East", "South", "West" },
		RequiresExistingWall = true,
		RequiresFloorOnBothSides = false,
		ReplaceableWallTag = "segment",
		WallVariant = "Door",
		Tags = { "wall", "door" },
		ModelPath = { "Doors", "WoodenDoor" },
	},
}

return Doors
