--!strict

local Decorations = {
	PineTree = {
		Name = "Pine Tree",
		PlacementType = "CellObject",
		WidthCells = 1,
		DepthCells = 1,
		Facing = { "North", "East", "South", "West" },
		Cost = 250,
		Tags = { "Nature", "Tree" },
		ModelPath = { "Decorations", "PineTree" },
	},

	Planter = {
		Name = "Planter",
		PlacementType = "CellObject",
		WidthCells = 1,
		DepthCells = 2,
		Facing = { "North", "East", "South", "West" },
		Cost = 100,
		Tags = { "Nature", "Plant" },
		ModelPath = { "Decorations", "Planter" },
	},
}

return Decorations
