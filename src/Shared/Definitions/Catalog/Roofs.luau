--!strict

local Roofs = {
	RoofFlat = {
		Name = "Roof Flat",
		PlacementType = "Roof",
		WidthCells = 1,
		DepthCells = 1,
		Facing = { "North", "East", "South", "West" },
		HeightStuds = 12,
		Cost = 150,
		Rules = {
			RequiresFloorUnderAllCells = true, -- like walls
		},
		ModelPath = { "Roofs", "RoofFlat" },
	},
}

return Roofs
