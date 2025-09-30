--!strict
-- ReplicatedStorage/Shared/Definitions/Catalog/Furnitures.luau

local Furnitures = {
	WoodenChair = {
		Name = "Wooden Chair",
		PlacementType = "CellObject",
		WidthCells = 1,
		DepthCells = 1,
		Facing = { "North", "East", "South", "West" },
		Cost = 50,
		Rules = { RequiresFloorUnderAllCells = false },
		Tags = { "Basic", "Seating" },
		ModelPath = { "Furnitures", "WoodenChair" },
	},
}

return Furnitures
