--!strict
-- ReplicatedStorage/Shared/Definitions/Catalog/Furnitures.luau

local Furnitures = {
	WoodenChair = {
		Name = "Wooden Chair",
		PlacementType = "CellObject",
		ActionType = "Rest",
		Station = true,
		maxOccupancy = 1,
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
		ActionType = "Socialize",
		Station = true,
		maxOccupancy = 4,
		WidthCells = 2,
		DepthCells = 1,
		Facing = { "North", "East", "South", "West" },
		Cost = 100,
		Rules = { RequiresFloorUnderAllCells = false },
		Tags = { "Basic", "Table" },
		ModelPath = { "Furnitures", "WoodenTable" },
	},
	OldMattress = {
		Name = "Old Mattress",
		PlacementType = "CellObject",
		ActionType = "Sleep",
		Station = true,
		maxOccupancy = 1,
		WidthCells = 2,
		DepthCells = 1,
		Facing = { "North", "East", "South", "West" },
		Cost = 200,
		Rules = { RequiresFloorUnderAllCells = false },
		Tags = { "Basic", "Bed" },
		ModelPath = { "Furnitures", "OldMattress" },
	},

	Campfire = {
		Name = "Campfire",
		PlacementType = "CellObject",
		ActionType = "Cook",
		Station = true,
		maxOccupancy = 2,
		WidthCells = 2,
		DepthCells = 2,
		Facing = { "North", "East", "South", "West" },
		Cost = 150,
		Rules = { RequiresFloorUnderAllCells = false },
		Tags = { "Basic", "Fire" },
		ModelPath = { "Furnitures", "Campfire" },
	},
}

return Furnitures
