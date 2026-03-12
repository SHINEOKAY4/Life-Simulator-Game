--!strict
-- Client/ClientStores/LevelSnapshotBuilder.luau
-- Extracts level-specific analysis (floors, walls, roofs) from placement data
-- Room detection removed - uses server-replicated data only

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ItemFinder = require(ReplicatedStorage.Shared.Utilities.ItemFinder)

type FloorCellDescriptor = {
	CellX: number,
	CellZ: number,
	CellIndex: number,
	PlacementKey: string,
	ItemId: string,
}

type CellCoordinate = { CellX: number, CellZ: number }

type WallSegmentDescriptor = {
	CellX: number,
	CellZ: number,
	Facing: string,
	PlacementKey: string,
	ItemId: string,
	Variant: string?,
	Orientation: "Cardinal" | "Diagonal",
	BlocksRooms: boolean,
	AdjacentCells: { CellA: CellCoordinate?, CellB: CellCoordinate? },
}

type RoomRecord = {
	Id: number,
	Level: number,
	CellCount: number,
	MinCellX: number,
	MaxCellX: number,
	MinCellZ: number,
	MaxCellZ: number,
	CellIndices: { number },
}

export type PlacementRoomCoverageRecord = {
	PlacementKey: string,
	PlacementType: string,
	Level: number,
	Facing: string,
	RoomIds: { [number]: boolean },
	HasOutdoorCells: boolean,
}

export type LevelDerivedSnapshot = {
	Level: number,
	Columns: number,
	Rows: number,
	FloorCellsList: { FloorCellDescriptor },
	FloorCellsByIndex: { [number]: FloorCellDescriptor },
	RoofCellsByIndex: { [number]: boolean },
	WallSegments: { WallSegmentDescriptor },
	CardinalWallSegments: { WallSegmentDescriptor },
	BlockedCardinalEdges: { [string]: WallSegmentDescriptor },
	RoomAssignments: { [number]: number },
	RoomsById: { [number]: RoomRecord },
	RoomsList: { RoomRecord },
	PlacementCoverageByKey: { [string]: PlacementRoomCoverageRecord },
}

local LevelSnapshotBuilder = {}

local CARDINAL_FACINGS = {
	North = true,
	East = true,
	South = true,
	West = true,
}

local function computeCellIndex(columns: number, cellX: number, cellZ: number): number
	return (cellZ - 1) * columns + cellX
end

local function rotateFootprint(widthCells: number?, depthCells: number?, facing: string?): (number, number)
	local resolvedWidth = if typeof(widthCells) == "number" and (widthCells :: number) > 0
		then math.floor((widthCells :: number) + 0.5)
		else 1
	local resolvedDepth = if typeof(depthCells) == "number" and (depthCells :: number) > 0
		then math.floor((depthCells :: number) + 0.5)
		else 1
	local facingValue = tostring(facing)
	if facingValue == "East" or facingValue == "West" then
		return resolvedDepth, resolvedWidth
	end
	return resolvedWidth, resolvedDepth
end

local function footprintBounds(
	anchorX: number,
	anchorZ: number,
	widthCells: number?,
	depthCells: number?,
	facing: string?
): (number, number, number, number)
	local rotatedWidth, rotatedDepth = rotateFootprint(widthCells, depthCells, facing)
	local minCellX = math.floor(anchorX + 0.5)
	local minCellZ = math.floor(anchorZ + 0.5)
	local maxCellX = minCellX + rotatedWidth - 1
	local maxCellZ = minCellZ + rotatedDepth - 1
	return minCellX, minCellZ, maxCellX, maxCellZ
end

local function clampFootprint(
	minCellX: number,
	minCellZ: number,
	maxCellX: number,
	maxCellZ: number,
	columns: number,
	rows: number
): (number, number, number, number)
	return math.clamp(minCellX, 1, columns),
		math.clamp(minCellZ, 1, rows),
		math.clamp(maxCellX, 1, columns),
		math.clamp(maxCellZ, 1, rows)
end

local function resolveCardinalAdjacency(
	cellX: number,
	cellZ: number,
	facing: string
): (CellCoordinate?, CellCoordinate?)
	if facing == "North" then
		return { CellX = cellX, CellZ = cellZ - 1 }, { CellX = cellX, CellZ = cellZ }
	elseif facing == "South" then
		return { CellX = cellX, CellZ = cellZ }, { CellX = cellX, CellZ = cellZ + 1 }
	elseif facing == "East" then
		return { CellX = cellX, CellZ = cellZ }, { CellX = cellX + 1, CellZ = cellZ }
	elseif facing == "West" then
		return { CellX = cellX - 1, CellZ = cellZ }, { CellX = cellX, CellZ = cellZ }
	end
	return nil, nil
end

-- Removes all snapshot contributions for a single placement key.
-- For roof cells the original record's footprint is required to know which indices to clear.
local function removeKeyFromSnapshot(snapshot: LevelDerivedSnapshot, key: string, oldRecord: any?)
	-- Rebuild floor list and index without this key
	local newFloorList: { FloorCellDescriptor } = {}
	local newFloorByIndex: { [number]: FloorCellDescriptor } = {}
	for _, desc in ipairs(snapshot.FloorCellsList) do
		if desc.PlacementKey ~= key then
			newFloorList[#newFloorList + 1] = desc
			newFloorByIndex[desc.CellIndex] = desc
		end
	end
	snapshot.FloorCellsList = newFloorList
	snapshot.FloorCellsByIndex = newFloorByIndex

	-- Rebuild wall arrays without this key
	local newWalls: { WallSegmentDescriptor } = {}
	for _, seg in ipairs(snapshot.WallSegments) do
		if seg.PlacementKey ~= key then
			newWalls[#newWalls + 1] = seg
		end
	end
	snapshot.WallSegments = newWalls

	local newCardinal: { WallSegmentDescriptor } = {}
	for _, seg in ipairs(snapshot.CardinalWallSegments) do
		if seg.PlacementKey ~= key then
			newCardinal[#newCardinal + 1] = seg
		end
	end
	snapshot.CardinalWallSegments = newCardinal

	-- Clear roof cells that belonged to this placement (needs original footprint)
	if oldRecord ~= nil then
		local rec = oldRecord :: any
		if rec.PlacementType == "Roof" then
			local anchorX = typeof(rec.cellX) == "number" and rec.cellX or 1
			local anchorZ = typeof(rec.cellZ) == "number" and rec.cellZ or 1
			local minCellX, minCellZ, maxCellX, maxCellZ =
				footprintBounds(anchorX, anchorZ, rec.WidthCells, rec.DepthCells, rec.facing)
			minCellX, minCellZ, maxCellX, maxCellZ =
				clampFootprint(minCellX, minCellZ, maxCellX, maxCellZ, snapshot.Columns, snapshot.Rows)
			local removedRange: { [number]: boolean } = {}
			for cellZ = minCellZ, maxCellZ do
				for cellX = minCellX, maxCellX do
					removedRange[computeCellIndex(snapshot.Columns, cellX, cellZ)] = true
				end
			end
			local newRoofCells: { [number]: boolean } = {}
			for cellIndex, _ in pairs(snapshot.RoofCellsByIndex) do
				if not removedRange[cellIndex] then
					newRoofCells[cellIndex] = true
				end
			end
			snapshot.RoofCellsByIndex = newRoofCells
		end
	end

	-- Remove from coverage (cast to any to allow nil assignment under --!strict)
	;(snapshot.PlacementCoverageByKey :: any)[key] = nil
end

-- Adds a single placement record's contributions to an existing snapshot.
-- Mirrors the per-item processing inside LevelSnapshotBuilder.Build.
local function addItemToSnapshot(snapshot: LevelDerivedSnapshot, key: string, record: any)
	local rec = record :: any
	local placementType = rec.PlacementType
	if placementType == nil and typeof(rec.id) == "string" then
		local spec = ItemFinder.FindItemById(rec.id)
		if spec then
			placementType = (spec :: any).PlacementType or (spec :: any).Type
		end
	end
	placementType = placementType or "CellObject"

	local columns = snapshot.Columns
	local rows = snapshot.Rows

	if placementType == "Floor" then
		local anchorX = typeof(rec.cellX) == "number" and rec.cellX or 1
		local anchorZ = typeof(rec.cellZ) == "number" and rec.cellZ or 1
		local minCellX, minCellZ, maxCellX, maxCellZ =
			footprintBounds(anchorX, anchorZ, rec.WidthCells, rec.DepthCells, rec.facing)
		minCellX, minCellZ, maxCellX, maxCellZ =
			clampFootprint(minCellX, minCellZ, maxCellX, maxCellZ, columns, rows)
		if minCellX <= maxCellX and minCellZ <= maxCellZ then
			for cellZ = minCellZ, maxCellZ do
				for cellX = minCellX, maxCellX do
					local index = computeCellIndex(columns, cellX, cellZ)
					local descriptor: FloorCellDescriptor = {
						CellX = cellX,
						CellZ = cellZ,
						CellIndex = index,
						PlacementKey = key,
						ItemId = rec.id,
					}
					if not snapshot.FloorCellsByIndex[index] then
						snapshot.FloorCellsList[#snapshot.FloorCellsList + 1] = descriptor
					end
					snapshot.FloorCellsByIndex[index] = descriptor
				end
			end
		end
	elseif placementType == "Roof" or placementType == "Ceiling" then
		local facing = tostring(rec.facing or "North")
		local anchorX = typeof(rec.cellX) == "number" and rec.cellX or 1
		local anchorZ = typeof(rec.cellZ) == "number" and rec.cellZ or 1
		local minCellX, minCellZ, maxCellX, maxCellZ =
			footprintBounds(anchorX, anchorZ, rec.WidthCells, rec.DepthCells, facing)
		minCellX, minCellZ, maxCellX, maxCellZ =
			clampFootprint(minCellX, minCellZ, maxCellX, maxCellZ, columns, rows)
		if minCellX <= maxCellX and minCellZ <= maxCellZ then
			snapshot.PlacementCoverageByKey[key] = {
				PlacementKey = key,
				PlacementType = placementType,
				Level = snapshot.Level,
				Facing = facing,
				RoomIds = {},
				HasOutdoorCells = false,
			}
			if placementType == "Roof" then
				for cellZ = minCellZ, maxCellZ do
					for cellX = minCellX, maxCellX do
						snapshot.RoofCellsByIndex[computeCellIndex(columns, cellX, cellZ)] = true
					end
				end
			end
		end
	elseif placementType == "Wall" then
		local facing = tostring(rec.facing or "North")
		local spec = typeof(rec.id) == "string" and ItemFinder.FindItemById(rec.id) or nil
		local variant = spec and (spec :: any).WallVariant or nil
		local anchorX = math.floor((rec.cellX or 1) + 0.5)
		local anchorZ = math.floor((rec.cellZ or 1) + 0.5)
		local orientation: "Cardinal" | "Diagonal" = if CARDINAL_FACINGS[facing] then "Cardinal" else "Diagonal"
		local segment: WallSegmentDescriptor = {
			CellX = anchorX,
			CellZ = anchorZ,
			Facing = facing,
			PlacementKey = key,
			ItemId = rec.id,
			Variant = variant,
			Orientation = orientation,
			BlocksRooms = false,
			AdjacentCells = { CellA = nil, CellB = nil },
		}
		if orientation == "Cardinal" then
			local cellA, cellB = resolveCardinalAdjacency(anchorX, anchorZ, facing)
			segment.AdjacentCells = { CellA = cellA, CellB = cellB }
			snapshot.CardinalWallSegments[#snapshot.CardinalWallSegments + 1] = segment
		end
		snapshot.WallSegments[#snapshot.WallSegments + 1] = segment
	end
end

-- ⚠️ CRITICAL: Room detection has been removed from client
-- Server is the single source of truth for room boundaries via RoomDataSync packet
-- Do NOT re-add FloodFillCore or room calculation logic here
-- All room data comes from PlotState/Rooms.luau (server) → PlotStateStore (client)

function LevelSnapshotBuilder.Build(
	level: number,
	columns: number,
	rows: number,
	placedItems: { [string]: any },
	defaultLevel: number
): LevelDerivedSnapshot
	local floorCellsList: { FloorCellDescriptor } = {}
	local floorCellsByIndex: { [number]: FloorCellDescriptor } = {}
	local roofCellsByIndex: { [number]: boolean } = {}
	local cardinalWalls: { WallSegmentDescriptor } = {}
	local diagonalWalls: { WallSegmentDescriptor } = {}
	local coverageCellsByPlacement: {
		[string]: {
			PlacementType: string,
			Facing: string,
			Cells: { number },
		},
	} =
		{}

	local function captureCoverageCells(
		placementKey: string,
		placementType: string,
		facing: string,
		minCellX: number,
		minCellZ: number,
		maxCellX: number,
		maxCellZ: number
	)
		local existing = coverageCellsByPlacement[placementKey]
		if not existing then
			existing = {
				PlacementType = placementType,
				Facing = facing,
				Cells = {},
			}
			coverageCellsByPlacement[placementKey] = existing
		end
		if existing.Facing == nil or existing.Facing == "" then
			existing.Facing = facing
		end
		for cellZ = minCellZ, maxCellZ do
			for cellX = minCellX, maxCellX do
				existing.Cells[#existing.Cells + 1] = computeCellIndex(columns, cellX, cellZ)
			end
		end
	end

	for key, record in pairs(placedItems) do
		local placementLevel = if typeof(record.Level) == "number"
			then math.floor((record.Level :: number) + 0.5)
			else defaultLevel
		if placementLevel ~= level then
			continue
		end

		local placementType = (record :: any).PlacementType
		if placementType == nil and typeof(record.id) == "string" then
			local spec = ItemFinder.FindItemById(record.id)
			if spec then
				placementType = spec.PlacementType or spec.Type
			end
		end
		placementType = placementType or "CellObject"

		if placementType == "Floor" then
			local anchorX = typeof(record.cellX) == "number" and record.cellX or 1
			local anchorZ = typeof(record.cellZ) == "number" and record.cellZ or 1
			local minCellX, minCellZ, maxCellX, maxCellZ =
				footprintBounds(anchorX, anchorZ, record.WidthCells, record.DepthCells, record.facing)
			minCellX, minCellZ, maxCellX, maxCellZ =
				clampFootprint(minCellX, minCellZ, maxCellX, maxCellZ, columns, rows)

			if minCellX <= maxCellX and minCellZ <= maxCellZ then
				for cellZ = minCellZ, maxCellZ do
					for cellX = minCellX, maxCellX do
						local index = computeCellIndex(columns, cellX, cellZ)
						local descriptor: FloorCellDescriptor = {
							CellX = cellX,
							CellZ = cellZ,
							CellIndex = index,
							PlacementKey = key,
							ItemId = record.id,
						}
						if floorCellsByIndex[index] then
							floorCellsByIndex[index] = descriptor
						else
							floorCellsByIndex[index] = descriptor
							floorCellsList[#floorCellsList + 1] = descriptor
						end
					end
				end
			end
		elseif placementType == "Roof" or placementType == "Ceiling" then
			local anchorX = typeof(record.cellX) == "number" and record.cellX or 1
			local anchorZ = typeof(record.cellZ) == "number" and record.cellZ or 1
			local minCellX, minCellZ, maxCellX, maxCellZ =
				footprintBounds(anchorX, anchorZ, record.WidthCells, record.DepthCells, record.facing)
			minCellX, minCellZ, maxCellX, maxCellZ =
				clampFootprint(minCellX, minCellZ, maxCellX, maxCellZ, columns, rows)

			if minCellX <= maxCellX and minCellZ <= maxCellZ then
				captureCoverageCells(
					key,
					placementType,
					tostring(record.facing or "North"),
					minCellX,
					minCellZ,
					maxCellX,
					maxCellZ
				)
				if placementType == "Roof" then
					for cellZ = minCellZ, maxCellZ do
						for cellX = minCellX, maxCellX do
							local index = computeCellIndex(columns, cellX, cellZ)
							roofCellsByIndex[index] = true
						end
					end
				end
			end
		elseif placementType == "Wall" then
			local facing = tostring(record.facing or "North")
			local spec = typeof(record.id) == "string" and ItemFinder.FindItemById(record.id) or nil
			local variant = spec and spec.WallVariant or nil
			local anchorX = math.floor((record.cellX or 1) + 0.5)
			local anchorZ = math.floor((record.cellZ or 1) + 0.5)
			local orientation: "Cardinal" | "Diagonal" = if CARDINAL_FACINGS[facing] then "Cardinal" else "Diagonal"
			local segment: WallSegmentDescriptor = {
				CellX = anchorX,
				CellZ = anchorZ,
				Facing = facing,
				PlacementKey = key,
				ItemId = record.id,
				Variant = variant,
				Orientation = orientation,
				BlocksRooms = false, -- Server determines room boundaries
				AdjacentCells = { CellA = nil, CellB = nil },
			}

			if orientation == "Cardinal" then
				local cellA, cellB = resolveCardinalAdjacency(anchorX, anchorZ, facing)
				segment.AdjacentCells = { CellA = cellA, CellB = cellB }
				cardinalWalls[#cardinalWalls + 1] = segment
			else
				diagonalWalls[#diagonalWalls + 1] = segment
			end
		end
	end

	-- Room coverage analysis deferred until server sends room data
	local placementCoverageByKey: { [string]: PlacementRoomCoverageRecord } = {}
	for placementKey, coverage in pairs(coverageCellsByPlacement) do
		placementCoverageByKey[placementKey] = {
			PlacementKey = placementKey,
			PlacementType = coverage.PlacementType,
			Level = level,
			Facing = coverage.Facing,
			RoomIds = {}, -- Populated by PlotStateStore when room data arrives
			HasOutdoorCells = false,
		}
	end

	local wallSegments: { WallSegmentDescriptor } = {}
	for i = 1, #cardinalWalls do
		wallSegments[i] = cardinalWalls[i]
	end
	for i = 1, #diagonalWalls do
		wallSegments[#wallSegments + 1] = diagonalWalls[i]
	end

	return {
		Level = level,
		Columns = columns,
		Rows = rows,
		FloorCellsList = floorCellsList,
		FloorCellsByIndex = floorCellsByIndex,
		RoofCellsByIndex = roofCellsByIndex,
		WallSegments = wallSegments,
		CardinalWallSegments = cardinalWalls,
		BlockedCardinalEdges = {}, -- No longer used for room detection
		RoomAssignments = {}, -- Populated by server data
		RoomsById = {}, -- Populated by server data
		RoomsList = {}, -- Populated by server data
		PlacementCoverageByKey = placementCoverageByKey,
	}
end

-- Apply a single placement delta incrementally to an existing snapshot.
-- Avoids a full snapshot rebuild when individual placements change.
-- oldRecord: the prior PlacedItems entry (for roof cell cleanup); may be nil for new placements.
-- newRecord: the updated PlacedItems entry; nil when action is "Removed".
function LevelSnapshotBuilder.ApplyItemDelta(
	snapshot: LevelDerivedSnapshot,
	key: string,
	action: string,
	oldRecord: any?,
	newRecord: any?
)
	removeKeyFromSnapshot(snapshot, key, oldRecord)
	if (action == "Placed" or action == "Updated") and newRecord ~= nil then
		addItemToSnapshot(snapshot, key, newRecord)
	end
end

return LevelSnapshotBuilder
