--!strict

local Outdoor = {
	Landscaping = {
		PineTree = {
			Name = "Pine Tree",
			PlacementType = "CellObject",
			WidthCells = 1,
			DepthCells = 1,
			Facing = { "North", "East", "South", "West" },
			Cost = 250,
			Description = "Stately evergreen that whispers in the wind and adds height to the yard.",
			Tags = { "Nature", "Tree" },
			ModelPath = { "Decorations", "PineTree" },
			AssetId = 7766554433,
			EffectSummary = {
				"Gives the plot a lush, evergreen accent.",
				"Never sheds needles in your build.",
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
			Description = "Stone-ring campfire that crackles bright and invites stories.",
			Tags = { "Basic", "Fire" },
			ModelPath = { "Furnitures", "Campfire" },
			AssetId = 116024324956421,
			StationEffects = {
				DurationSeconds = 60,
			},
			EffectSummary = {
				"Lets two residents roast dinner under the stars.",
				"Throws off warm light for late-night hangouts.",
			},
		},
	},

	Structures = {},
	Gardening = {},
	WaterFeatures = {},
	PathsAndFencing = {
		FarmsteadFence = {
			Name = "Farmstead Fence",
			PlacementType = "CellObject",
			WidthCells = 1,
			DepthCells = 3,
			Facing = { "North", "East", "South", "West" },
			Cost = 75,
			Description = "Rustic wooden fence that adds charm and defines your outdoor space.",
			Tags = { "Basic", "Fence" },
			ModelPath = { "Furnitures", "FarmsteadFence" },
			AssetId = 102794549547064,
			EffectSummary = {
				"Defines the boundaries of your yard with rustic charm.",
				"Adds a cozy, farmstead feel to outdoor areas.",
			},
		},
	},
	Patio = {
		ParkBench = {
			Name = "Park Bench",
			PlacementType = "CellObject",
			StationType = "RestStation",
			Station = true,
			maxOccupancy = 2,
			WidthCells = 1,
			DepthCells = 2,
			Facing = { "North", "East", "South", "West" },
			Cost = 200,
			Description = "Classic wooden park bench perfect for relaxing outdoors.",
			Rules = { RequiresFloorUnderAllCells = false },
			Tags = { "Basic", "Seating" },
			ModelPath = { "Furnitures", "ParkBench" },
			AssetId = 78161112143828,
			StationEffects = {
				RestMode = "Sit",
			},
			EffectSummary = {
				"Provides a comfortable spot to sit and enjoy the outdoors.",
				"Enhances the look of any patio or garden area.",
			},
		},
	},
}

return Outdoor
