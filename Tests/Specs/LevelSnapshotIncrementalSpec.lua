-- Structural checks for PlotState snapshot incremental diff optimization (Iter 7)
local function readFile(path)
	local file = assert(io.open(path, "r"), "missing file: " .. path)
	local contents = file:read("*a")
	file:close()
	return contents
end

describe("LevelSnapshotBuilder incremental diff", function()
	local lsb

	before_each(function()
		lsb = readFile("src/Client/ClientStores/LevelSnapshotBuilder.luau")
	end)

	it("exports ApplyItemDelta function", function()
		assert.is_truthy(
			string.find(lsb, "LevelSnapshotBuilder.ApplyItemDelta", 1, true),
			"ApplyItemDelta must be exported from LevelSnapshotBuilder"
		)
	end)

	it("defines removeKeyFromSnapshot local helper", function()
		assert.is_truthy(
			string.find(lsb, "removeKeyFromSnapshot", 1, true),
			"removeKeyFromSnapshot local helper must be defined"
		)
	end)

	it("defines addItemToSnapshot local helper", function()
		assert.is_truthy(
			string.find(lsb, "addItemToSnapshot", 1, true),
			"addItemToSnapshot local helper must be defined"
		)
	end)

	it("ApplyItemDelta calls removeKeyFromSnapshot unconditionally", function()
		local fnStart = string.find(lsb, "function LevelSnapshotBuilder.ApplyItemDelta", 1, true)
		assert.is_truthy(fnStart, "ApplyItemDelta function must exist")
		local fnBody = string.sub(lsb, fnStart, fnStart + 600)
		assert.is_truthy(
			string.find(fnBody, "removeKeyFromSnapshot(snapshot, key", 1, true),
			"ApplyItemDelta must call removeKeyFromSnapshot"
		)
	end)

	it("ApplyItemDelta calls addItemToSnapshot for non-removal actions", function()
		local fnStart = string.find(lsb, "function LevelSnapshotBuilder.ApplyItemDelta", 1, true)
		assert.is_truthy(fnStart, "ApplyItemDelta function must exist")
		local fnBody = string.sub(lsb, fnStart, fnStart + 600)
		assert.is_truthy(
			string.find(fnBody, "addItemToSnapshot(snapshot, key", 1, true),
			"ApplyItemDelta must call addItemToSnapshot for Placed/Updated actions"
		)
	end)

	it("removeKeyFromSnapshot rebuilds FloorCellsList and FloorCellsByIndex", function()
		local fnStart = string.find(lsb, "local function removeKeyFromSnapshot", 1, true)
		assert.is_truthy(fnStart, "removeKeyFromSnapshot must be defined")
		local fnBody = string.sub(lsb, fnStart, fnStart + 2000)
		assert.is_truthy(string.find(fnBody, "FloorCellsList", 1, true))
		assert.is_truthy(string.find(fnBody, "FloorCellsByIndex", 1, true))
		assert.is_truthy(string.find(fnBody, "WallSegments", 1, true))
		assert.is_truthy(string.find(fnBody, "CardinalWallSegments", 1, true))
	end)
end)

describe("PacketProcessor old-record passthrough", function()
	local src

	before_each(function()
		src = readFile("src/Client/ClientStores/PacketProcessor.luau")
	end)

	it("captures oldRecord before mutating PlacedItems", function()
		assert.is_truthy(
			string.find(src, "local oldRecord = currentPlacedItems[key]", 1, true),
			"oldRecord must be captured before mutation"
		)
	end)

	it("ApplyPlacementDelta returns oldRecord as third value on success", function()
		assert.is_truthy(
			string.find(src, "return key, true, oldRecord", 1, true),
			"ApplyPlacementDelta must return oldRecord as third value"
		)
	end)

	it("return type annotation includes third optional value", function()
		assert.is_truthy(
			string.find(src, "): (string?, boolean, any?)", 1, true),
			"return type must declare the oldRecord third value"
		)
	end)
end)

describe("PlotStateStore incremental snapshot update", function()
	local src

	before_each(function()
		src = readFile("src/Client/ClientStores/PlotStateStore.luau")
	end)

	it("PlacementDelta handler captures oldRecord from ApplyPlacementDelta", function()
		local handlerPos = string.find(src, "PlacementDelta.OnClientEvent", 1, true)
		assert.is_truthy(handlerPos, "PlacementDelta handler must exist")
		local handlerBody = string.sub(src, handlerPos, handlerPos + 2500)
		assert.is_truthy(
			string.find(handlerBody, "appliedKey, changed, oldRecord", 1, true),
			"PlacementDelta handler must capture oldRecord as third return value"
		)
	end)

	it("PlacementDelta handler applies incremental update via ApplyItemDelta", function()
		local handlerPos = string.find(src, "PlacementDelta.OnClientEvent", 1, true)
		assert.is_truthy(handlerPos, "PlacementDelta handler must exist")
		local handlerBody = string.sub(src, handlerPos, handlerPos + 2500)
		assert.is_truthy(
			string.find(handlerBody, "LevelSnapshotBuilder.ApplyItemDelta", 1, true),
			"PlacementDelta handler must call LevelSnapshotBuilder.ApplyItemDelta"
		)
	end)

	it("PlacementDelta handler does NOT call invalidateDerivedLevelSnapshots", function()
		local handlerPos = string.find(src, "PlacementDelta.OnClientEvent", 1, true)
		assert.is_truthy(handlerPos, "PlacementDelta handler must exist")
		local handlerBody = string.sub(src, handlerPos, handlerPos + 2500)
		assert.is_falsy(
			string.find(handlerBody, "invalidateDerivedLevelSnapshots()", 1, true),
			"PlacementDelta handler must NOT call invalidateDerivedLevelSnapshots (incremental update instead)"
		)
	end)

	it("PlacementDelta handler still fires RoomSnapshotChanged and PlacementsChanged", function()
		local handlerPos = string.find(src, "PlacementDelta.OnClientEvent", 1, true)
		assert.is_truthy(handlerPos, "PlacementDelta handler must exist")
		local handlerBody = string.sub(src, handlerPos, handlerPos + 2500)
		assert.is_truthy(
			string.find(handlerBody, "RoomSnapshotChanged:Fire()", 1, true),
			"PlacementDelta handler must still fire RoomSnapshotChanged"
		)
		assert.is_truthy(
			string.find(handlerBody, "PlacementsChanged:Fire()", 1, true),
			"PlacementDelta handler must still fire PlacementsChanged"
		)
	end)
end)
