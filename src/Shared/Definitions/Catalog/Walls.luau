--!strict
-- ReplicatedStorage/Shared/Definitions/Catalog/Walls.luau

local Walls = {
	WoodenWall = {
		Name = "WoodenWall",
		PlacementType = "Wall",
		WidthCells = 1,
		DepthCells = 1,
		Facing = { "North", "East", "South", "West" },
		Cost = 75,
		Tags = { "segment" },
		ModelPath = { "Walls", "WoodenWall" },
	},
}

return Walls
