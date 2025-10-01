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
	WoodenTable = {
		Name = "Wooden Table",
		PlacementType = "CellObject",
		WidthCells = 2,
		DepthCells = 1,
		Facing = { "North", "East", "South", "West" },
		Cost = 100,
		Rules = { RequiresFloorUnderAllCells = false },
		Tags = { "Basic", "Table" },
		ModelPath = { "Furnitures", "WoodenTable" },
	},
}

return Furnitures
