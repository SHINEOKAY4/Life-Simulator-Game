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

return LevelSnapshotBuilder
