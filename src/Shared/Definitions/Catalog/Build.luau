--!strict

local Build = {

	Roofs = {
		FlatRoof = {
			Name = "Flat Roof",
			PlacementType = "Roof",
			WidthCells = 1,
			DepthCells = 1,
			Facing = { "Up" },
			Cost = 100,
			Description = "Classic shingle panel that caps your house and keeps the weather out.",
			Tags = { "roof", "standard" },
			ModelPath = { "Roofs", "StandardRoof" },
			AssetId = 123456789,
			EffectSummary = {
				"Seals the ceiling so rooms feel sheltered.",
				"Lines up neatly with matching roof pieces.",
			},
		},
	},
	Walls = {
		StandardWall = {
			Name = "Standard Wall",
			PlacementType = "Wall",
			WidthCells = 1,
			DepthCells = 1,
			Facing = { "North", "East", "South", "West", "NorthEast", "NorthWest" },
			Cost = 50,
			Description = "Smooth plaster wall section that brings structure and privacy to a room.",
			Tags = { "wall", "standard" },
			ModelPath = { "Walls", "StandardWall" },
			AssetId = 101105961277316,
			EffectSummary = {
				"Closes off a side of the room for a finished look.",
				"Sturdy enough to hold doors, windows, and wall decor.",
			},
		},
	},
	Floors = {
		StandardFloor = {
			Name = "Standard Floor",
			PlacementType = "Floor",
			WidthCells = 1,
			DepthCells = 1,
			Facing = { "North", "East", "South", "West" },
			Cost = 50,
			Description = "Warm hardwood plank that makes any space feel move-in ready.",
			Tags = { "floor", "standard" },
			ModelPath = { "Floors", "StandardFloor" },
			AssetId = 132794131684702,
			EffectSummary = {
				"Gives residents a polished surface to walk on.",
				"Keeps furniture level and looking tidy.",
			},
		},
	},
	Arches = {},
	Doors = {
		WoodenDoor = {
			Name = "Wooden Door",
			PlacementType = "Wall",
			WidthCells = 1,
			DepthCells = 1,
			Facing = { "North", "East", "South", "West" },
			Cost = 250,
			RequiresExistingWall = true,
			RequiresFloorOnBothSides = false,
			ReplaceableWallTag = "wall",
			WallVariant = "Door",
			Tags = { "wall", "door", "standard" },
			ModelPath = { "Doors", "WoodenDoor" },
			AssetId = 564738291,
			Description = "Simple wooden door with a brass knob and clean trim.",
			EffectSummary = {
				"Opens a passage so residents can move between rooms.",
				"Closes to muffle noise and give a bit of privacy.",
			},
		},
	},
	Stairs = {},
	Columns = {},
	Foundations = {},
}

return Build
