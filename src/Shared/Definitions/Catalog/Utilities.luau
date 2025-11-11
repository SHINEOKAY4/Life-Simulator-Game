--!strict

local Utilities = {
	Electrical = {
		ElectricBox = {
			Name = "Electric Box",
			PlacementType = "CellObject",
			WidthCells = 1,
			DepthCells = 1,
			Facing = { "North", "East", "South", "West" },
			Cost = 200,
			Description = "Durable electric box that safely houses electrical components.",
			Rules = { RequiresFloorUnderAllCells = false },
			Tags = { "Basic", "Electrical" },
			ModelPath = { "Furnitures", "ElectricBox" },
			AssetId = 78735881138394,
			EffectSummary = {
				"Provides a safe enclosure for electrical systems.",
				"Built to withstand various environmental conditions.",
			},
		},
	},
	Waste = {
		TrashBin = {
			Name = "Trash Bin",
			PlacementType = "CellObject",
			WidthCells = 1,
			DepthCells = 1,
			Facing = { "North", "East", "South", "West" },
			Cost = 100,
			Description = "Rugged metal bin with a squeaky lid and plenty of scuffs.",
			Rules = { RequiresFloorUnderAllCells = false },
			Tags = { "Basic", "Utility" },
			ModelPath = { "Furnitures", "TrashBin" },
			AssetId = 80102656688158,
			EffectSummary = {
				"Keeps trash corralled so the yard stays neat.",
				"Stands up to kicks, bumps, and messy days.",
			},
		},

		TrashCan = {
			Name = "Trash Can",
			PlacementType = "CellObject",
			WidthCells = 1,
			DepthCells = 1,
			Facing = { "North", "East", "South", "West" },
			Cost = 50,
			Description = "Simple plastic trash can that's easy to clean and hard to tip over.",
			Rules = { RequiresFloorUnderAllCells = false },
			Tags = { "Basic", "Utility" },
			ModelPath = { "Furnitures", "TrashCan" },
			AssetId = 125225349689812,
			EffectSummary = {
				"Helps keep the area tidy by holding waste.",
				"Lightweight and easy to move when needed.",
			},
		},
	},
	Plumbing = {},
	Safety = {},
	HVAC = {},
	Storage = {
		WoodenRackShelf = {
			Name = "Wooden Rack Shelf",
			PlacementType = "CellObject",
			WidthCells = 1,
			DepthCells = 3,
			Facing = { "North", "East", "South", "West" },
			Cost = 150,
			Description = "Sturdy wooden shelf perfect for storing supplies and knick-knacks.",
			Rules = { RequiresFloorUnderAllCells = false },
			Tags = { "Basic", "Storage" },
			ModelPath = { "Furnitures", "WoodenRackShelf" },
			AssetId = 117968320727197,
			EffectSummary = {
				"Provides extra storage space for various items.",
				"Durable design suitable for busy environments.",
			},
		},
		ModernLoftShelf = {
			Name = "Modern Loft Shelf",
			PlacementType = "CellObject",
			WidthCells = 1,
			DepthCells = 3,
			Facing = { "North", "East", "South", "West" },
			Cost = 200,
			Description = "Sleek modern shelf with a loft design, perfect for contemporary spaces.",
			Rules = { RequiresFloorUnderAllCells = false },
			Tags = { "Modern", "Storage" },
			ModelPath = { "Furnitures", "ModernLoftShelf" },
			AssetId = 118883233870723,
			EffectSummary = {
				"Adds stylish storage to your space.",
				"Combines form and function with a modern aesthetic.",
			},
		},

		GlasslineDisplayShelf = {
			Name = "Glassline Display Shelf",
			PlacementType = "CellObject",
			WidthCells = 1,
			DepthCells = 2,
			Facing = { "North", "East", "South", "West" },
			Cost = 250,
			Description = "Elegant glass display shelf that showcases items with a touch of sophistication.",
			Rules = { RequiresFloorUnderAllCells = false },
			Tags = { "Elegant", "Storage" },
			ModelPath = { "Furnitures", "GlasslineDisplayShelf" },
			AssetId = 126553254807199,
			EffectSummary = {
				"Perfect for displaying collectibles and decor.",
				"Enhances the visual appeal of any room.",
			},
		},
	},
}

return Utilities
