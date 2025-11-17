--!strict

local Decorations = {
	Lighting = {
		Lamp = {
			Name = "Lamp",
			PlacementType = "CellObject",
			Station = false,
			WidthCells = 1,
			DepthCells = 1,
			Facing = { "North", "East", "South", "West" },
			EnergyConsumptionPerHour = 1,
			Cost = 75,
			Description = "Warm standing lamp with a woven shade and gentle glow.",
			Rules = { RequiresFloorUnderAllCells = false },
			Tags = { "Basic", "Light" },
			SurfaceOffsetStuds = 0.1,
			ModelPath = { "Furnitures", "Lamp" },
			AssetId = 116003840493275,
			EffectSummary = {
				"Makes late-night rooms feel welcoming.",
				"Only sips a tiny bit of power.",
			},
		},
		PendantLight = {
			Name = "Pendant Light",
			PlacementType = "Ceiling",
			WidthCells = 1,
			DepthCells = 1,
			Facing = { "North", "East", "South", "West" },
			Cost = 110,
			Description = "Suspended ceiling fixture with a matte shade that pools light right where you need it.",
			Tags = { "Lighting", "Ceiling" },
			Rules = { RequiresFloorUnderAllCells = true },
			CeilingMountConfig = {
				MinDropStuds = 2,
				MaxDropStuds = 8,
				DefaultDropStuds = 2,
				RotationStepDegrees = 15,
			},
			ModelPath = { "Decorations", "PendantLight" },
			AssetId = 91401639326401,
			EffectSummary = {
				"Drops a warm spotlight over dining tables or kitchen islands.",
				"Installs on any unlocked level thanks to the new ceiling placement mode.",
			},
		},
	},
	Wall = {},
	Floor = {
		CottageRoundRug = {
			Name = "Cottage Round Rug",
			PlacementType = "CellObject",
			WidthCells = 2,
			DepthCells = 2,
			Facing = { "North", "East", "South", "West" },
			Cost = 150,
			Description = "Cozy round rug with a patchwork design in warm, homey colors.",
			Tags = { "Basic", "Rug" },
			Rules = {
				AllowStacking = true,
				RequiresFloorUnderAllCells = true,
			},
			ModelPath = { "Decorations", "CottageRoundRug" },
			AssetId = 89844549603607,
			EffectSummary = {
				"Adds a comfy, lived-in feel to any room.",
				"Soft underfoot and visually inviting.",
			},
		},
	},
	WindowTreatment = {},
	Plants = {
		Planter = {
			Name = "Planter",
			PlacementType = "CellObject",
			WidthCells = 1,
			DepthCells = 2,
			Facing = { "North", "East", "South", "West" },
			Cost = 100,
			Description = "Tall ceramic planter overflowing with hardy greens.",
			Tags = { "Nature", "Plant" },
			ModelPath = { "Decorations", "Planter" },
			AssetId = 81661116527295,
			EffectSummary = {
				"Freshens any space with a pop of green.",
				"Stays lush without daily watering.",
			},
		},

		PlantPot = {
			Name = "Plant Pot",
			PlacementType = "CellObject",
			WidthCells = 1,
			DepthCells = 1,
			Facing = { "North", "East", "South", "West" },
			Cost = 50,
			Description = "Small terracotta pot housing a cheerful succulent.",
			Tags = { "Nature", "Plant" },
			ModelPath = { "Decorations", "PlantPot" },
			AssetId = 76774175860401,
			EffectSummary = {
				"Adds a touch of life to desks and shelves.",
				"Thrives with minimal care.",
			},
		},

		PottedPlant = {
			Name = "Potted Plant",
			PlacementType = "CellObject",
			WidthCells = 1,
			DepthCells = 1,
			Facing = { "North", "East", "South", "West" },
			Cost = 75,
			Description = "Lush potted plant with broad leaves that brighten any room.",
			Tags = { "Nature", "Plant" },
			ModelPath = { "Decorations", "PottedPlant" },
			AssetId = 80441180073151,
			EffectSummary = {
				"Brings a refreshing green vibe indoors.",
				"Easy to care for and maintain.",
			},
		},

		RaisedGardenBed = {
			Name = "Raised Garden Bed",
			PlacementType = "CellObject",
			WidthCells = 3,
			DepthCells = 2,
			Facing = { "North", "East", "South", "West" },
			Cost = 200,
			Description = "Wooden raised garden bed filled with a variety of vibrant flowers and greenery.",
			Tags = { "Nature", "Garden" },
			ModelPath = { "Decorations", "RaisedGardenBed" },
			AssetId = 130425632647827, -- Placeholder AssetId
			EffectSummary = {
				"Enhances outdoor spaces with colorful blooms.",
				"Perfect for gardening enthusiasts.",
			},
		},
	},
	Statues = {},
	Seasonal = {},
}

return Decorations
