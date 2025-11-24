--!strict
-- Client/ClientStores/LevelSnapshotBuilder.luau
-- Extracts level-specific analysis (floors, walls, roofs, rooms) from placement data

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FloodFillCore = require(ReplicatedStorage.Shared.Utilities.FloodFillCore)
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

local function makeEdgeKey(ax: number, az: number, bx: number, bz: number): string
	if ax > bx or (ax == bx and az > bz) then
		ax, bx = bx, ax
		az, bz = bz, az
	end
	return ("%d:%d:%d:%d"):format(ax, az, bx, bz)
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

local function buildRoomsForLevel(
	level: number,
	columns: number,
	rows: number,
	floorCellsList: { FloorCellDescriptor },
	blockedEdges: { [string]: WallSegmentDescriptor }
): ({ [number]: number }, { [number]: RoomRecord }, { RoomRecord })
	local roomAssignments: { [number]: number } = {}
	local roomsById: { [number]: RoomRecord } = {}
	local roomsList: { RoomRecord } = {}

	local floorFilled: { [number]: boolean } = {}
	for _, cell in ipairs(floorCellsList) do
		floorFilled[cell.CellIndex] = true
	end

	local function isEdgeBlocked(cx: number, cz: number, direction: string): boolean
		local nx, nz
		if direction == "North" then
			nx, nz = cx, cz - 1
		elseif direction == "South" then
			nx, nz = cx, cz + 1
		elseif direction == "West" then
			nx, nz = cx - 1, cz
		elseif direction == "East" then
			nx, nz = cx + 1, cz
		else
			return true
		end
		local edgeKey = makeEdgeKey(cx, cz, nx, nz)
		return blockedEdges[edgeKey] ~= nil
	end

	local areas = FloodFillCore.FindAllAreas(columns, rows, floorFilled, isEdgeBlocked, nil)

	for roomId, area in ipairs(areas) do
		local roomRecord: RoomRecord = {
			Id = roomId,
			Level = level,
			CellCount = area.CellCount,
			MinCellX = area.MinX,
			MaxCellX = area.MaxX,
			MinCellZ = area.MinZ,
			MaxCellZ = area.MaxZ,
			CellIndices = area.Cells,
		}

		for _, cellIndex in ipairs(area.Cells) do
			roomAssignments[cellIndex] = roomId
		end

		roomsById[roomId] = roomRecord
		roomsList[#roomsList + 1] = roomRecord
	end

	return roomAssignments, roomsById, roomsList
end

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
	local blockedEdges: { [string]: WallSegmentDescriptor } = {}
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
			local blocksRooms = orientation == "Cardinal" and variant ~= "Door"
			local segment: WallSegmentDescriptor = {
				CellX = anchorX,
				CellZ = anchorZ,
				Facing = facing,
				PlacementKey = key,
				ItemId = record.id,
				Variant = variant,
				Orientation = orientation,
				BlocksRooms = blocksRooms,
				AdjacentCells = { CellA = nil, CellB = nil },
			}

			if orientation == "Cardinal" then
				local cellA, cellB = resolveCardinalAdjacency(anchorX, anchorZ, facing)
				segment.AdjacentCells = { CellA = cellA, CellB = cellB }
				cardinalWalls[#cardinalWalls + 1] = segment
				if blocksRooms and cellA and cellB then
					local ax, az = cellA.CellX, cellA.CellZ
					local bx, bz = cellB.CellX, cellB.CellZ
					if
						ax >= 1
						and ax <= columns
						and az >= 1
						and az <= rows
						and bx >= 1
						and bx <= columns
						and bz >= 1
						and bz <= rows
					then
						local edgeKeyValue = makeEdgeKey(ax, az, bx, bz)
						blockedEdges[edgeKeyValue] = segment
					end
				end
			else
				diagonalWalls[#diagonalWalls + 1] = segment
			end
		end
	end

	local roomAssignments, roomsById, roomsList = buildRoomsForLevel(level, columns, rows, floorCellsList, blockedEdges)

	local placementCoverageByKey: { [string]: PlacementRoomCoverageRecord } = {}
	for placementKey, coverage in pairs(coverageCellsByPlacement) do
		local roomMap: { [number]: boolean } = {}
		local hasOutdoor = false
		for _, cellIndex in ipairs(coverage.Cells) do
			local roomId = roomAssignments[cellIndex]
			if roomId then
				roomMap[roomId] = true
			else
				hasOutdoor = true
			end
		end
		placementCoverageByKey[placementKey] = {
			PlacementKey = placementKey,
			PlacementType = coverage.PlacementType,
			Level = level,
			Facing = coverage.Facing,
			RoomIds = roomMap,
			HasOutdoorCells = hasOutdoor,
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
		BlockedCardinalEdges = blockedEdges,
		RoomAssignments = roomAssignments,
		RoomsById = roomsById,
		RoomsList = roomsList,
		PlacementCoverageByKey = placementCoverageByKey,
	}
end

return LevelSnapshotBuilder
