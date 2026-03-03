--!strict
-- Behavioral tests for PlotService serialization paths

local PlotSerializationUtils = assert(loadfile("src/Server/Utilities/PlotSerializationUtils.luau"))()

describe("PlotService serialization utils", function()
	it("deep-clones metadata tables", function()
		local input = { a = 1, nested = { b = 2 } }
		local output = PlotSerializationUtils.CloneMetadata(input)

		assert.equals(1, output.a)
		assert.equals(2, output.nested.b)
		assert.is_not.equal(input, output)
		assert.is_not.equal(input.nested, output.nested)

		output.nested.b = 9
		assert.equals(2, input.nested.b)
	end)

	it("flattens placed objects with deterministic order and size fallbacks", function()
		local specs = {
			["wall_lamp"] = { WidthCells = 3, DepthCells = 2 },
		}
		local map = {
			b_key = {
				id = "wall_lamp",
				cellX = 6,
				cellZ = 7,
				facing = "East",
				Metadata = { WidthCells = 0, custom = true },
				yLevel = 4,
			},
			a_key = {
				id = "chair_basic",
				cellX = 1,
				cellZ = 2,
				Metadata = { WidthCells = 2, DepthCells = 1 },
			},
		}

		local snapshot = PlotSerializationUtils.FlattenPlacedObjects(map, 2, function(itemId)
			return specs[itemId]
		end)

		assert.equals(2, #snapshot)
		assert.equals("chair_basic", snapshot[1].id)
		assert.equals(2, snapshot[1].WidthCells)
		assert.equals(1, snapshot[1].DepthCells)
		assert.equals(2, snapshot[1].Level)
		assert.equals("North", snapshot[1].facing)

		assert.equals("wall_lamp", snapshot[2].id)
		assert.equals(3, snapshot[2].WidthCells)
		assert.equals(2, snapshot[2].DepthCells)
		assert.equals(4, snapshot[2].Level)
		assert.equals("East", snapshot[2].facing)

		snapshot[2].Metadata.custom = false
		assert.is_true(map.b_key.Metadata.custom)
	end)

	it("flattens valid surface mounts and normalizes defaults", function()
		local map = {
			z = {
				id = "poster_1",
				parentKey = "wall_a",
				LocalPosition = { x = 4, y = 5, z = 6 },
				LocalRotationY = 45,
				Metadata = { tag = "kitchen" },
			},
			a = {
				id = "clock_1",
				parentKey = "wall_b",
				LocalPosition = { X = 1, Y = 2, Z = 3 },
			},
			bad = {
				id = 15,
				parentKey = "wall_c",
			},
		}

		local snapshot = PlotSerializationUtils.FlattenSurfaceMounts(map)

		assert.equals(2, #snapshot)
		assert.equals("a", snapshot[1].key)
		assert.equals(0, snapshot[1].LocalRotationY)
		assert.same({ X = 1, Y = 2, Z = 3 }, snapshot[1].LocalPosition)

		assert.equals("z", snapshot[2].key)
		assert.same({ X = 4, Y = 5, Z = 6 }, snapshot[2].LocalPosition)
		assert.equals(45, snapshot[2].LocalRotationY)

		snapshot[2].Metadata.tag = "changed"
		assert.equals("kitchen", map.z.Metadata.tag)
	end)
end)
