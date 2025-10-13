--!strict
-- ReplicatedStorage/Shared/Definitions/Catalog/Furnitures.luau

local Furnitures = {
	WoodenChair = {
		Name = "Wooden Chair",
		PlacementType = "CellObject",
		StationType = "RestStation",
		Station = true,
		maxOccupancy = 1,
		WidthCells = 1,
		DepthCells = 1,
		Facing = { "North", "East", "South", "West" },
		Cost = 50,
		Rules = { RequiresFloorUnderAllCells = false },
		Tags = { "Basic", "Seating" },
		ModelPath = { "Furnitures", "WoodenChair" },
		StationEffects = {
			RestMode = "Nap",
		},
	},
	WoodenTable = {
		Name = "Wooden Table",
		PlacementType = "CellObject",
		StationType = "FunStation",
		Station = true,
		maxOccupancy = 4,
		WidthCells = 2,
		DepthCells = 1,
		Facing = { "North", "East", "South", "West" },
		Cost = 100,
		Rules = { RequiresFloorUnderAllCells = false },
		Tags = { "Basic", "Table" },
		ModelPath = { "Furnitures", "WoodenTable" },
		StationEffects = {
			DurationSeconds = 150,
			Effects = {
				{ Need = "Fun", RatePerHour = 12 },
			},
		},
	},

	Refridgerator = {
		Name = "Refridgerator",
		PlacementType = "CellObject",
		StationType = "CookStation",
		Station = true,
		maxOccupancy = 1,
		WidthCells = 1,
		DepthCells = 1,
		Facing = { "North", "East", "South", "West" },
		Cost = 250,
		Rules = { RequiresFloorUnderAllCells = false },
		Tags = { "Comfort", "Appliance" },
		ModelPath = { "Furnitures", "Refridgerator" },
		StationEffects = {
			DurationSeconds = 16,
			Effects = {
				{ Need = "Hunger", RatePerHour = 420 },
			},
		},
	},

	Stove = {
		Name = "Stove",
		PlacementType = "CellObject",
		StationType = "CookStation",
		Station = true,
		maxOccupancy = 1,
		WidthCells = 1,
		DepthCells = 1,
		Facing = { "North", "East", "South", "West" },
		Cost = 200,
		Rules = { RequiresFloorUnderAllCells = false },
		Tags = { "Comfort", "Appliance" },
		ModelPath = { "Furnitures", "Stove" },
		StationEffects = {
			DurationSeconds = 22,
			Effects = {
				{ Need = "Hunger", RatePerHour = 500 },
			},
		},
	},

	BigWoodenTable = {
		Name = "Big Wooden Table",
		PlacementType = "CellObject",
		StationType = "FunStation",
		Station = true,
		maxOccupancy = 8,
		WidthCells = 2,
		DepthCells = 3,
		Facing = { "North", "East", "South", "West" },
		Cost = 300,
		Rules = { RequiresFloorUnderAllCells = false },
		Tags = { "Comfort", "Table" },
		ModelPath = { "Furnitures", "BigWoodenTable" },
		StationEffects = {
			DurationSeconds = 210,
			Effects = {
				{ Need = "Fun", RatePerHour = 14 },
			},
		},
	},

	OldMattress = {
		Name = "Old Mattress",
		PlacementType = "CellObject",
		StationType = "RestStation",
		Station = true,
		maxOccupancy = 1,
		WidthCells = 2,
		DepthCells = 1,
		Facing = { "North", "East", "South", "West" },
		Cost = 200,
		Rules = { RequiresFloorUnderAllCells = false },
		Tags = { "Basic", "Bed" },
		ModelPath = { "Furnitures", "OldMattress" },
		StationEffects = {
			RestMode = "Sleep",
		},
	},

	Campfire = {
		Name = "Campfire",
		PlacementType = "CellObject",
		StationType = "CookStation",
		Station = true,
		maxOccupancy = 2,
		WidthCells = 2,
		DepthCells = 2,
		Facing = { "North", "East", "South", "West" },
		Cost = 150,
		Rules = { RequiresFloorUnderAllCells = false },
		Tags = { "Basic", "Fire" },
		ModelPath = { "Furnitures", "Campfire" },
		StationEffects = {
			DurationSeconds = 20,
			Effects = {
				{ Need = "Hunger", RatePerHour = 380 },
			},
		},
	},

	StandardBed = {
		Name = "Standard Bed",
		PlacementType = "CellObject",
		StationType = "RestStation",
		Station = true,
		maxOccupancy = 2,
		WidthCells = 3,
		DepthCells = 2,
		Facing = { "North", "East", "South", "West" },
		Cost = 500,
		Rules = { RequiresFloorUnderAllCells = false },
		Tags = { "Comfort", "Bed" },
		ModelPath = { "Furnitures", "StandardBed" },
		StationEffects = {
			RestMode = "Sleep",
		},
	},

	Lamp = {
		Name = "Lamp",
		PlacementType = "CellObject",
		Station = false,
		WidthCells = 1,
		DepthCells = 1,
		Facing = { "North", "East", "South", "West" },
		Cost = 75,
		Rules = { RequiresFloorUnderAllCells = false },
		Tags = { "Basic", "Light" },
		SurfaceOffsetStuds = 0.1,
		ModelPath = { "Furnitures", "Lamp" },
	},
}

return Furnitures
