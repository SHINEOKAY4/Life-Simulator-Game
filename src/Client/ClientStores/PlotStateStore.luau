-- !strict
-- StarterPlayer/StarterPlayerScripts/Client/ClientStores/PlotStateStore.lua

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local GoodSignal = require(ReplicatedStorage.Packages.GoodSignal)
local PlotFinder = require(ReplicatedStorage.Shared.Utilities.PlotFinder)
local GridModule = require(ReplicatedStorage.Shared.Utilities.Grid)
local Packets = require(ReplicatedStorage.Network.PlacementPackets)
local PlacementKey = require(ReplicatedStorage.Shared.Utilities.PlacementKey)
local ItemFinder = require(ReplicatedStorage.Shared.Utilities.ItemFinder)
local BuildConstants = require(ReplicatedStorage.Shared.Configurations.BuildConstants)

local PlotStateStore = {}
local StateSnapshot = {}

local PlotModel = nil
local CachedSurface: BasePart? = nil
local CachedGrid: any? = nil
local ActiveLevelInitialized = false
local ActiveLevel = 0
local ActiveLevelChanged = GoodSignal.new()
local CutawayChanged = GoodSignal.new()
local RoomSnapshotChanged = GoodSignal.new()

local function deepClone(value: any): any
	if typeof(value) ~= "table" then
		return value
	end

	local result = {}
	for key, entry in pairs(value) do
		result[key] = deepClone(entry)
	end

	return result
end

type CutawayRequestOptions = {
	Priority: number?,
	TargetLevel: number?,
	HidePlacementTypes: { [string]: boolean }?,
}

type CutawayRequest = {
	Source: string,
	Priority: number,
	TargetLevel: number?,
	HidePlacementTypes: { [string]: boolean }?,
}

export type CutawayState = {
	Visible: boolean,
	Source: string?,
	TargetLevel: number,
	HidePlacementTypes: { [string]: boolean },
}

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

type LevelDerivedSnapshot = {
	Level: number,
	Columns: number,
	Rows: number,
	FloorCellsList: { FloorCellDescriptor },
	FloorCellsByIndex: { [number]: FloorCellDescriptor },
	WallSegments: { WallSegmentDescriptor },
	CardinalWallSegments: { WallSegmentDescriptor },
	BlockedCardinalEdges: { [string]: WallSegmentDescriptor },
	RoomAssignments: { [number]: number },
	RoomsById: { [number]: RoomRecord },
	RoomsList: { RoomRecord },
	PlacementCoverageByKey: { [string]: PlacementRoomCoverageRecord },
}

export type PlacementFootprint = {
	PlacementKey: string,
	PlacementType: string,
	Level: number,
	ItemId: string,
	Facing: string,
	WidthCells: number,
	DepthCells: number,
	MinCellX: number,
	MaxCellX: number,
	MinCellZ: number,
	MaxCellZ: number,
}

export type PlacementRoomCoverageRecord = {
	PlacementKey: string,
	PlacementType: string,
	Level: number,
	Facing: string,
	RoomIds: { [number]: boolean },
	HasOutdoorCells: boolean,
}

local DEFAULT_CUTAWAY_HIDE_TYPES = {
	Wall = true,
	Roof = true,
	Ceiling = true,
}

local CutawayRequests: { [string]: CutawayRequest } = {}
local ActiveCutawayState: CutawayState = {
	Visible = false,
	Source = nil,
	TargetLevel = 0,
	HidePlacementTypes = deepClone(DEFAULT_CUTAWAY_HIDE_TYPES),
}

local CARDINAL_FACINGS = {
	North = true,
	East = true,
	South = true,
	West = true,
}

-- Derived level metadata caches powering cutaway heuristics.
local DerivedLevelSnapshots: { [number]: LevelDerivedSnapshot } = {}

local function invalidateDerivedLevelSnapshots()
	DerivedLevelSnapshots = {}
	RoomSnapshotChanged:Fire()
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

local function computeCellIndex(columns: number, cellX: number, cellZ: number): number
	return (cellZ - 1) * columns + cellX
end

local function makeEdgeKey(ax: number, az: number, bx: number, bz: number): string
	if ax > bx or (ax == bx and az > bz) then
		ax, bx = bx, ax
		az, bz = bz, az
	end
	return ("%d:%d:%d:%d"):format(ax, az, bx, bz)
end

local function copyNumberArray(source: { number }?): { number }
	local result: { number } = {}
	if not source then
		return result
	end
	for index = 1, #source do
		result[index] = source[index]
	end
	return result
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

local function getChunkDimensions(): (number?, number?)
	local chunkInfo = StateSnapshot.ChunkInfo
	if not chunkInfo then
		return nil, nil
	end
	local chunkSize = tonumber(chunkInfo.ChunkSizeInCells)
	local chunkColumns = tonumber(chunkInfo.ChunkColumns)
	local chunkRows = tonumber(chunkInfo.ChunkRows)
	if not chunkSize or not chunkColumns or not chunkRows then
		return nil, nil
	end
	return chunkColumns * chunkSize, chunkRows * chunkSize
end

local function sanitizeLevelInput(level: number?): number
	local defaultLevel = PlotStateStore.GetDefaultLevel()
	local maxLevel = PlotStateStore.GetMaxLevel()
	if typeof(level) == "number" then
		local numeric = math.floor((level :: number) + 0.5)
		return math.clamp(numeric, defaultLevel, maxLevel)
	end
	return PlotStateStore.GetActiveLevel()
end

local function buildRoomsForLevel(
	level: number,
	columns: number,
	rows: number,
	floorCellsList: { FloorCellDescriptor },
	floorCellsByIndex: { [number]: FloorCellDescriptor },
	blockedEdges: { [string]: WallSegmentDescriptor }
): ({ [number]: number }, { [number]: RoomRecord }, { RoomRecord })
	local roomAssignments: { [number]: number } = {}
	local roomsById: { [number]: RoomRecord } = {}
	local roomsList: { RoomRecord } = {}
	local visited: { [number]: boolean } = {}

	for _, cell in ipairs(floorCellsList) do
		local startIndex = cell.CellIndex
		if not visited[startIndex] then
			local roomId = #roomsList + 1
			local roomRecord: RoomRecord = {
				Id = roomId,
				Level = level,
				CellCount = 0,
				MinCellX = math.huge,
				MaxCellX = -math.huge,
				MinCellZ = math.huge,
				MaxCellZ = -math.huge,
				CellIndices = {},
			}
			local queue: { number } = { startIndex }
			local head = 1
			visited[startIndex] = true
			roomAssignments[startIndex] = roomId

			while head <= #queue do
				local currentIndex = queue[head]
				head += 1
				local currentCell = floorCellsByIndex[currentIndex]
				if currentCell then
					local cx = currentCell.CellX
					local cz = currentCell.CellZ
					roomRecord.CellCount += 1
					if cx < roomRecord.MinCellX then
						roomRecord.MinCellX = cx
					end
					if cx > roomRecord.MaxCellX then
						roomRecord.MaxCellX = cx
					end
					if cz < roomRecord.MinCellZ then
						roomRecord.MinCellZ = cz
					end
					if cz > roomRecord.MaxCellZ then
						roomRecord.MaxCellZ = cz
					end
					local cellIndices = roomRecord.CellIndices
					cellIndices[#cellIndices + 1] = currentIndex

					local function tryVisitNeighbor(nx: number, nz: number)
						if nx < 1 or nx > columns or nz < 1 or nz > rows then
							return
						end
						local neighborIndex = computeCellIndex(columns, nx, nz)
						if visited[neighborIndex] then
							return
						end
						local neighborCell = floorCellsByIndex[neighborIndex]
						if not neighborCell then
							return
						end
						local edgeKeyValue = makeEdgeKey(cx, cz, nx, nz)
						if blockedEdges[edgeKeyValue] then
							return
						end
						visited[neighborIndex] = true
						roomAssignments[neighborIndex] = roomId
						queue[#queue + 1] = neighborIndex
					end

					tryVisitNeighbor(cx, cz - 1)
					tryVisitNeighbor(cx + 1, cz)
					tryVisitNeighbor(cx, cz + 1)
					tryVisitNeighbor(cx - 1, cz)
				end
			end

			if roomRecord.CellCount > 0 then
				if roomRecord.MinCellX == math.huge then
					roomRecord.MinCellX = 0
					roomRecord.MaxCellX = 0
					roomRecord.MinCellZ = 0
					roomRecord.MaxCellZ = 0
				end
				roomsById[roomId] = roomRecord
				roomsList[#roomsList + 1] = roomRecord
			end
		end
	end

	return roomAssignments, roomsById, roomsList
end

local function buildLevelDerivedSnapshot(level: number): LevelDerivedSnapshot?
	local placedItems = StateSnapshot.PlacedItems
	if not placedItems then
		return nil
	end
	local columns, rows = getChunkDimensions()
	if not columns or not rows then
		return nil
	end

	local floorCellsList: { FloorCellDescriptor } = {}
	local floorCellsByIndex: { [number]: FloorCellDescriptor } = {}
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
			else PlotStateStore.GetDefaultLevel()
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
			minCellX = math.clamp(minCellX, 1, columns)
			minCellZ = math.clamp(minCellZ, 1, rows)
			maxCellX = math.clamp(maxCellX, 1, columns)
			maxCellZ = math.clamp(maxCellZ, 1, rows)
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
			minCellX = math.clamp(minCellX, 1, columns)
			minCellZ = math.clamp(minCellZ, 1, rows)
			maxCellX = math.clamp(maxCellX, 1, columns)
			maxCellZ = math.clamp(maxCellZ, 1, rows)
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

	local roomAssignments, roomsById, roomsList =
		buildRoomsForLevel(level, columns, rows, floorCellsList, floorCellsByIndex, blockedEdges)

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
		WallSegments = wallSegments,
		CardinalWallSegments = cardinalWalls,
		BlockedCardinalEdges = blockedEdges,
		RoomAssignments = roomAssignments,
		RoomsById = roomsById,
		RoomsList = roomsList,
		PlacementCoverageByKey = placementCoverageByKey,
	}
end

local function getLevelDerivedSnapshot(level: number): LevelDerivedSnapshot?
	local cached = DerivedLevelSnapshots[level]
	if cached then
		return cached
	end
	local built = buildLevelDerivedSnapshot(level)
	if not built then
		return nil
	end
	DerivedLevelSnapshots[level] = built
	return built
end

local function cloneHideTypeMap(source: { [string]: boolean }?): { [string]: boolean }
	local result = {}
	if not source then
		return result
	end
	for key, value in pairs(source) do
		if value == true then
			result[key] = true
		end
	end
	return result
end

local function booleanMapsEqual(left: { [string]: boolean }?, right: { [string]: boolean }?): boolean
	if left == right then
		return true
	end
	if not left then
		if not right then
			return true
		end
		for _, value in pairs(right) do
			if value == true then
				return false
			end
		end
		return true
	end
	if not right then
		for _, value in pairs(left) do
			if value == true then
				return false
			end
		end
		return true
	end
	for key, value in pairs(left) do
		if (right[key] or false) ~= (value == true) then
			return false
		end
	end
	for key, value in pairs(right) do
		if (left[key] or false) ~= (value == true) then
			return false
		end
	end
	return true
end

local function normalizeCutawayOptions(source: string, options: CutawayRequestOptions?): CutawayRequest
	local resolved = options or {}
	local resolvedLevel: number? = nil
	if typeof(resolved.TargetLevel) == "number" then
		local defaultLevel = PlotStateStore.GetDefaultLevel()
		local maxLevel = PlotStateStore.GetMaxLevel()
		local candidate = math.floor((resolved.TargetLevel :: number) + 0.5)
		if candidate < defaultLevel then
			candidate = defaultLevel
		end
		if candidate > maxLevel then
			candidate = maxLevel
		end
		resolvedLevel = candidate
	end

	local hideMap = cloneHideTypeMap(DEFAULT_CUTAWAY_HIDE_TYPES)
	if typeof(resolved.HidePlacementTypes) == "table" then
		for placementType, shouldHide in pairs(resolved.HidePlacementTypes :: any) do
			if shouldHide == true then
				hideMap[placementType] = true
			else
				hideMap[placementType] = nil
			end
		end
	end

	local priorityValue = 0
	if typeof(resolved.Priority) == "number" then
		priorityValue = resolved.Priority :: number
	end

	return {
		Source = source,
		Priority = priorityValue,
		TargetLevel = resolvedLevel,
		HidePlacementTypes = hideMap,
	}
end

local function recomputeCutawayState()
	local winningSource: string? = nil
	local winningRequest: CutawayRequest? = nil
	local winningPriority = -math.huge
	for source, request in pairs(CutawayRequests) do
		if request and request.Priority >= winningPriority then
			winningPriority = request.Priority
			winningSource = source
			winningRequest = request
		end
	end

	local newVisible = winningRequest ~= nil
	local resolvedLevel = ActiveLevel
	local resolvedHideTypes = if winningRequest
		then cloneHideTypeMap(winningRequest.HidePlacementTypes)
		else cloneHideTypeMap(DEFAULT_CUTAWAY_HIDE_TYPES)
	if winningRequest and winningRequest.TargetLevel then
		resolvedLevel = winningRequest.TargetLevel
	end

	local stateChanged = newVisible ~= ActiveCutawayState.Visible
		or resolvedLevel ~= ActiveCutawayState.TargetLevel
		or winningSource ~= ActiveCutawayState.Source
		or not booleanMapsEqual(resolvedHideTypes, ActiveCutawayState.HidePlacementTypes)

	if stateChanged then
		ActiveCutawayState.Visible = newVisible
		ActiveCutawayState.Source = winningSource
		ActiveCutawayState.TargetLevel = resolvedLevel
		ActiveCutawayState.HidePlacementTypes = resolvedHideTypes
		CutawayChanged:Fire(PlotStateStore.GetCutawayState())
	end
end

local function coerceVector3(value: any): Vector3?
	if typeof(value) == "Vector3" then
		return value
	end
	if typeof(value) ~= "table" then
		return nil
	end

	local xValue = value.X or value.x
	local yValue = value.Y or value.y
	local zValue = value.Z or value.z
	if typeof(xValue) ~= "number" or typeof(yValue) ~= "number" or typeof(zValue) ~= "number" then
		return nil
	end
	return Vector3.new(xValue, yValue, zValue)
end

local function normalizeMetadata(metadata: any): any
	if metadata == nil then
		return nil
	end

	if typeof(metadata) ~= "table" then
		return metadata
	end

	local cloned = deepClone(metadata)
	local wallData = cloned.WallMountData
	if typeof(wallData) == "table" then
		local convertedPosition = coerceVector3(wallData.WorldPosition)
		if convertedPosition then
			wallData.WorldPosition = convertedPosition
		end
		local convertedNormal = coerceVector3(wallData.WallNormal)
		if convertedNormal then
			if convertedNormal.Magnitude > 1e-3 then
				wallData.WallNormal = convertedNormal.Unit
			else
				wallData.WallNormal = Vector3.new(0, 0, -1)
			end
		end
	end

	return cloned
end

local function normalizeSurfaceMountEntry(entry: any)
	if typeof(entry) ~= "table" then
		return nil
	end

	local keyValue = entry.Key or entry.key
	if typeof(keyValue) ~= "string" or keyValue == "" then
		return nil
	end

	local itemIdValue = entry.ItemId or entry.id
	if typeof(itemIdValue) ~= "string" or itemIdValue == "" then
		return nil
	end

	local parentKeyValue = entry.ParentKey or entry.parentKey or ""
	if typeof(parentKeyValue) ~= "string" then
		parentKeyValue = ""
	end

	local localPosition = coerceVector3(entry.LocalPosition) or Vector3.new()
	local rotationValue = entry.LocalRotationY
	local rotationY = if typeof(rotationValue) == "number" then rotationValue else 0
	local metadata = normalizeMetadata(entry.Metadata)

	return {
		key = keyValue,
		id = itemIdValue,
		parentKey = parentKeyValue,
		LocalPosition = localPosition,
		LocalRotationY = rotationY,
		Metadata = metadata,
	}
end

local function ChunkToIndex(chunkX: number, chunkZ: number, chunkColumns: number): number
	return (chunkZ - 1) * chunkColumns + chunkX
end

function PlotStateStore.Init()
	Packets.PlotStateSync.OnClientEvent:Connect(function(chunkInfo, unlockedChunks, placedItems, surfaceMounts)
		StateSnapshot.ChunkInfo = chunkInfo
		StateSnapshot.ChunkUnlocked = unlockedChunks
		StateSnapshot.FloorHeightStuds = chunkInfo.FloorHeightStuds
		StateSnapshot.DefaultLevel = chunkInfo.DefaultLevel
		StateSnapshot.MaxLevel = chunkInfo.MaxLevel

		local defaultLevel = if typeof(chunkInfo.DefaultLevel) == "number" then chunkInfo.DefaultLevel else 0
		local maxLevel = if typeof(chunkInfo.MaxLevel) == "number" then chunkInfo.MaxLevel else defaultLevel

		if not ActiveLevelInitialized then
			ActiveLevel = defaultLevel
			ActiveLevelInitialized = true
			ActiveLevelChanged:Fire(ActiveLevel)
		else
			local clamped = math.clamp(ActiveLevel, defaultLevel, maxLevel)
			if clamped ~= ActiveLevel then
				ActiveLevel = clamped
				ActiveLevelChanged:Fire(ActiveLevel)
			end
		end
		StateSnapshot.ActiveLevel = ActiveLevel

		local placedMap = {}
		if placedItems then
			for _, entry in ipairs(placedItems) do
				local facing = entry.facing or "North"
				local spec = entry.id and ItemFinder.FindItemById(entry.id) or nil
				local metadata = normalizeMetadata(entry.Metadata)
				local widthCells = entry.WidthCells or entry.widthCells
				local depthCells = entry.DepthCells or entry.depthCells
				if not widthCells or widthCells <= 0 then
					widthCells = spec and (spec.WidthCells or spec.Width) or 1
				end
				if not depthCells or depthCells <= 0 then
					depthCells = spec and (spec.DepthCells or spec.Depth) or 1
				end
				local levelValue = entry.Level or entry.level or defaultLevel
				local numericLevel = tonumber(levelValue)
				if numericLevel then
					numericLevel = math.floor(numericLevel + 0.5)
					if numericLevel < defaultLevel then
						numericLevel = defaultLevel
					end
					levelValue = numericLevel
				else
					levelValue = defaultLevel
				end
				local placementType = spec and (spec.PlacementType or spec.Type) or "CellObject"
				local itemSnapshot = {
					id = entry.id,
					cellX = entry.cellX,
					cellZ = entry.cellZ,
					facing = facing,
					WidthCells = widthCells,
					DepthCells = depthCells,
					Metadata = metadata,
					Level = levelValue,
					PlacementType = placementType,
				}
				local key = PlacementKey.ForPlacementType(
					itemSnapshot.cellX,
					itemSnapshot.cellZ,
					facing,
					placementType,
					levelValue
				)
				placedMap[key] = itemSnapshot
			end
		end
		StateSnapshot.PlacedItems = placedMap

		local surfaceMap = {}
		if surfaceMounts then
			for _, entry in ipairs(surfaceMounts) do
				local normalized = normalizeSurfaceMountEntry(entry)
				if normalized then
					surfaceMap[normalized.key] = normalized
				end
			end
		end
		StateSnapshot.SurfaceMounts = surfaceMap
		invalidateDerivedLevelSnapshots()

		-- Lazy initialize grid, helpful for external modules that need it
		if not CachedGrid then
			local player = Players.LocalPlayer
			local plotIndex = player:GetAttribute("OwnedPlotIndex") :: number?

			if plotIndex then
				local plotModel = PlotFinder.FindPlot(plotIndex)
				if plotModel then
					local surface = plotModel:FindFirstChild("Surface") :: BasePart?
					local cellSize = plotModel:GetAttribute("CellSize") :: number?
					PlotModel = plotModel
					if surface and cellSize then
						CachedSurface = surface
						CachedGrid = GridModule.new(surface, cellSize, "BottomLeft")
					end
				end
			end
		end
	end)

	Packets.PlotStateUnlockDelta.OnClientEvent:Connect(function(indices)
		if not StateSnapshot.ChunkUnlocked then
			return
		end

		for i = 1, #indices do
			StateSnapshot.ChunkUnlocked[indices[i]] = true
		end
	end)

	-- Added: incremental placement updates (client-side snapshot append)
	Packets.PlacementDelta.OnClientEvent:Connect(function(delta)
		-- delta shape (per PlacementPackets): { Action = "Placed", Item = { Id, CellX, CellZ, Facing } }

		StateSnapshot.PlacedItems = StateSnapshot.PlacedItems or {}

		if not delta or not delta.Item then
			return
		end

		local itemId = delta.Item.ItemId or delta.Item.Id or delta.Item.id
		if not itemId then
			return
		end

		local facing = delta.Item.Facing or "North"
		local spec = itemId and ItemFinder.FindItemById(itemId) or nil
		local placementType = spec and (spec.PlacementType or spec.Type) or "CellObject"
		local metadata = normalizeMetadata(delta.Item.Metadata)
		local widthCells = delta.Item.WidthCells or delta.Item.widthCells
		local depthCells = delta.Item.DepthCells or delta.Item.depthCells
		if not widthCells or widthCells <= 0 then
			widthCells = spec and (spec.WidthCells or spec.Width) or 1
		end
		if not depthCells or depthCells <= 0 then
			depthCells = spec and (spec.DepthCells or spec.Depth) or 1
		end
		local levelValue = delta.Item.Level or delta.Item.level or ActiveLevel
		local numericLevel = tonumber(levelValue)
		if numericLevel then
			numericLevel = math.floor(numericLevel + 0.5)
			if numericLevel < 0 then
				numericLevel = 0
			end
			levelValue = numericLevel
		else
			levelValue = ActiveLevel
		end
		local key = PlacementKey.ForPlacementType(delta.Item.CellX, delta.Item.CellZ, facing, placementType, levelValue)
		if delta.Action == "Removed" then
			StateSnapshot.PlacedItems[key] = nil
			invalidateDerivedLevelSnapshots()
			return
		end

		if delta.Action ~= "Placed" and delta.Action ~= "Updated" then
			return
		end

		StateSnapshot.PlacedItems[key] = {
			id = itemId,
			cellX = delta.Item.CellX,
			cellZ = delta.Item.CellZ,
			facing = facing,
			WidthCells = widthCells,
			DepthCells = depthCells,
			Metadata = metadata,
			Level = levelValue,
			PlacementType = placementType,
		}
		invalidateDerivedLevelSnapshots()
	end)

	Packets.SurfaceMountDelta.OnClientEvent:Connect(function(delta)
		StateSnapshot.SurfaceMounts = StateSnapshot.SurfaceMounts or {}
		if not delta or not delta.Mount then
			return
		end

		local normalized = normalizeSurfaceMountEntry(delta.Mount)
		if not normalized then
			return
		end

		if delta.Action == "Removed" then
			StateSnapshot.SurfaceMounts[normalized.key] = nil
			return
		end

		if delta.Action ~= "Placed" and delta.Action ~= "Updated" then
			return
		end

		StateSnapshot.SurfaceMounts[normalized.key] = normalized
	end)
end

function PlotStateStore.GetStateSnapshot()
	StateSnapshot.ActiveLevel = ActiveLevel
	return StateSnapshot
end

function PlotStateStore.IsReady(): boolean
	return StateSnapshot.ChunkInfo ~= nil and StateSnapshot.ChunkUnlocked ~= nil
end

function PlotStateStore.GetPlotModel(): Model?
	return PlotModel
end

function PlotStateStore.GetGrid()
	return CachedGrid
end

function PlotStateStore.GetSurface(): BasePart?
	return CachedSurface
end

function PlotStateStore.GetDefaultLevel(): number
	local info = StateSnapshot.ChunkInfo
	if info and typeof(info.DefaultLevel) == "number" then
		return info.DefaultLevel
	end
	return 0
end

function PlotStateStore.GetMaxLevel(): number
	local info = StateSnapshot.ChunkInfo
	if info and typeof(info.MaxLevel) == "number" then
		return info.MaxLevel
	end
	return PlotStateStore.GetDefaultLevel()
end

function PlotStateStore.GetActiveLevel(): number
	if ActiveLevelInitialized then
		return ActiveLevel
	end
	return PlotStateStore.GetDefaultLevel()
end

function PlotStateStore.SetActiveLevel(level: number)
	if not PlotStateStore.IsReady() then
		return
	end
	local defaultLevel = PlotStateStore.GetDefaultLevel()
	local maxLevel = PlotStateStore.GetMaxLevel()
	local clamped = math.clamp(level, defaultLevel, maxLevel)
	if clamped == ActiveLevel and ActiveLevelInitialized then
		return
	end
	ActiveLevel = clamped
	ActiveLevelInitialized = true
	StateSnapshot.ActiveLevel = ActiveLevel
	ActiveLevelChanged:Fire(ActiveLevel)
	recomputeCutawayState()
end

function PlotStateStore.OnActiveLevelChanged(handler: (number) -> ()): RBXScriptConnection
	return ActiveLevelChanged:Connect(handler)
end

function PlotStateStore.RequestCutaway(source: string, options: CutawayRequestOptions?)
	if typeof(source) ~= "string" or source == "" then
		warn("Cutaway request requires a non-empty source identifier")
		return
	end
	CutawayRequests[source] = normalizeCutawayOptions(source, options)
	recomputeCutawayState()
end

function PlotStateStore.ReleaseCutaway(source: string)
	if typeof(source) ~= "string" or source == "" then
		return
	end
	if CutawayRequests[source] == nil then
		return
	end
	CutawayRequests[source] = nil
	recomputeCutawayState()
end

function PlotStateStore.ClearCutawayRequests()
	if next(CutawayRequests) == nil then
		return
	end
	for source in pairs(CutawayRequests) do
		CutawayRequests[source] = nil
	end
	recomputeCutawayState()
end

function PlotStateStore.GetCutawayState(): CutawayState
	return {
		Visible = ActiveCutawayState.Visible,
		Source = ActiveCutawayState.Source,
		TargetLevel = ActiveCutawayState.TargetLevel,
		HidePlacementTypes = cloneHideTypeMap(ActiveCutawayState.HidePlacementTypes),
	}
end

function PlotStateStore.OnCutawayChanged(handler: (CutawayState) -> ()): RBXScriptConnection
	return CutawayChanged:Connect(handler)
end

function PlotStateStore.OnRoomSnapshotChanged(handler: () -> ()): RBXScriptConnection
	return RoomSnapshotChanged:Connect(handler)
end

function PlotStateStore.GetFloorHeightStuds(): number
	local info = StateSnapshot.ChunkInfo
	if info and typeof(info.FloorHeightStuds) == "number" then
		return info.FloorHeightStuds
	end
	return BuildConstants.FloorHeightStuds or 12
end

function PlotStateStore.GetLevelHeight(level: number?): number
	local resolvedLevel = if typeof(level) == "number" then level else PlotStateStore.GetActiveLevel()
	return PlotStateStore.GetFloorHeightStuds() * resolvedLevel
end

function PlotStateStore.GetPlotContainer(): Instance?
	local plotModel = PlotStateStore.GetPlotModel()
	if not plotModel then
		return nil
	end
	local container = plotModel:FindFirstChild("Container")
	if container and (container:IsA("Folder") or container:IsA("Model")) then
		return container
	end
	return nil
end

function PlotStateStore.ResolvePlacementInstance(key: string): Instance?
	if typeof(key) ~= "string" or key == "" then
		return nil
	end
	local container = PlotStateStore.GetPlotContainer()
	if not container then
		return nil
	end
	return container:FindFirstChild(key)
end

function PlotStateStore.GetPlacementEntry(key: string)
	if typeof(key) ~= "string" or key == "" then
		return nil
	end
	local placedItems = StateSnapshot.PlacedItems
	if not placedItems then
		return nil
	end
	return placedItems[key]
end

function PlotStateStore.IteratePlacements(handler: (string, any) -> any)
	if typeof(handler) ~= "function" then
		return
	end
	local placedItems = StateSnapshot.PlacedItems
	if not placedItems then
		return
	end
	for key, record in pairs(placedItems) do
		local continueSignal = handler(key, record)
		if continueSignal == false then
			break
		end
	end
end

function PlotStateStore.IsChunkUnlocked(chunkX: number, chunkZ: number): boolean
	if not PlotStateStore.IsReady() then
		return false
	end
	local info = StateSnapshot.ChunkInfo
	local unlocked = StateSnapshot.ChunkUnlocked
	return unlocked[ChunkToIndex(chunkX, chunkZ, info.ChunkColumns)] == true
end

function PlotStateStore.IsChunkInBounds(chunkX: number, chunkZ: number): boolean
	if not PlotStateStore.IsReady() then
		return false
	end
	local info = StateSnapshot.ChunkInfo
	return chunkX >= 1 and chunkX <= info.ChunkColumns and chunkZ >= 1 and chunkZ <= info.ChunkRows
end

function PlotStateStore.HasAdjacentUnlocked(chunkX: number, chunkZ: number): boolean
	if not PlotStateStore.IsReady() then
		return false
	end
	local info = StateSnapshot.ChunkInfo
	local unlocked = StateSnapshot.ChunkUnlocked
	local columns = info.ChunkColumns
	local rows = info.ChunkRows

	return (chunkX > 1 and unlocked[ChunkToIndex(chunkX - 1, chunkZ, columns)] == true)
		or (chunkX < columns and unlocked[ChunkToIndex(chunkX + 1, chunkZ, columns)] == true)
		or (chunkZ > 1 and unlocked[ChunkToIndex(chunkX, chunkZ - 1, columns)] == true)
		or (chunkZ < rows and unlocked[ChunkToIndex(chunkX, chunkZ + 1, columns)] == true)
end

function PlotStateStore.CanPurchaseChunk(chunkX: number, chunkZ: number): (boolean, string)
	if not PlotStateStore.IsReady() then
		return false, "State not ready"
	end
	if not PlotStateStore.IsChunkInBounds(chunkX, chunkZ) then
		return false, "Out of bounds"
	end
	if PlotStateStore.IsChunkUnlocked(chunkX, chunkZ) then
		return false, "Already unlocked"
	end
	if not PlotStateStore.HasAdjacentUnlocked(chunkX, chunkZ) then
		return false, "Not adjacent to unlocked area"
	end
	return true, ""
end

function PlotStateStore.RequestPurchase(chunkX: number, chunkZ: number): (boolean, string)
	-- Optional fast-fails for UX; do NOT attempt to mirror all server logic here.
	if not PlotStateStore.IsReady() then
		return false, "State not ready"
	end
	if not PlotStateStore.IsChunkInBounds(chunkX, chunkZ) then
		return false, "Out of bounds"
	end

	-- Always defer to server authority
	local success, message = Packets.UnlockChunkRequest:Fire(chunkX, chunkZ)
	return success, message
end

function PlotStateStore.GetCellDimensions(): (number?, number?)
	return getChunkDimensions()
end

function PlotStateStore.IterateFloorCells(level: number?, handler: (FloorCellDescriptor) -> any)
	if typeof(handler) ~= "function" then
		return
	end
	local resolvedLevel = sanitizeLevelInput(level)
	local snapshot = getLevelDerivedSnapshot(resolvedLevel)
	if not snapshot then
		return
	end
	for _, descriptor in ipairs(snapshot.FloorCellsList) do
		local continueSignal = handler(descriptor)
		if continueSignal == false then
			break
		end
	end
end

function PlotStateStore.IterateWallSegments(
	level: number?,
	handler: (WallSegmentDescriptor) -> any,
	includeDiagonal: boolean?
)
	if typeof(handler) ~= "function" then
		return
	end
	local resolvedLevel = sanitizeLevelInput(level)
	local snapshot = getLevelDerivedSnapshot(resolvedLevel)
	if not snapshot then
		return
	end
	local source = if includeDiagonal == false then snapshot.CardinalWallSegments else snapshot.WallSegments
	for _, segment in ipairs(source) do
		local continueSignal = handler(segment)
		if continueSignal == false then
			break
		end
	end
end

function PlotStateStore.IterateRooms(level: number?, handler: (RoomRecord) -> any)
	if typeof(handler) ~= "function" then
		return
	end
	local resolvedLevel = sanitizeLevelInput(level)
	local snapshot = getLevelDerivedSnapshot(resolvedLevel)
	if not snapshot then
		return
	end
	for _, room in ipairs(snapshot.RoomsList) do
		local continueSignal = handler(room)
		if continueSignal == false then
			break
		end
	end
end

function PlotStateStore.GetRoomIdAtCell(level: number?, cellX: number, cellZ: number): number?
	local resolvedLevel = sanitizeLevelInput(level)
	local snapshot = getLevelDerivedSnapshot(resolvedLevel)
	if not snapshot then
		return nil
	end
	local columns = snapshot.Columns
	local rows = snapshot.Rows
	local clampedX = math.clamp(math.floor(cellX + 0.5), 1, columns)
	local clampedZ = math.clamp(math.floor(cellZ + 0.5), 1, rows)
	local index = computeCellIndex(columns, clampedX, clampedZ)
	return snapshot.RoomAssignments[index]
end

function PlotStateStore.GetRoomInfo(level: number?, roomId: number): RoomRecord?
	if typeof(roomId) ~= "number" then
		return nil
	end
	local resolvedLevel = sanitizeLevelInput(level)
	local snapshot = getLevelDerivedSnapshot(resolvedLevel)
	if not snapshot then
		return nil
	end
	local room = snapshot.RoomsById[roomId]
	if not room then
		return nil
	end
	return {
		Id = room.Id,
		Level = room.Level,
		CellCount = room.CellCount,
		MinCellX = room.MinCellX,
		MaxCellX = room.MaxCellX,
		MinCellZ = room.MinCellZ,
		MaxCellZ = room.MaxCellZ,
		CellIndices = copyNumberArray(room.CellIndices),
	}
end

function PlotStateStore.GetPlacementFootprint(key: string): PlacementFootprint?
	if typeof(key) ~= "string" or key == "" then
		return nil
	end
	local record = PlotStateStore.GetPlacementEntry(key)
	if not record then
		return nil
	end
	local facing = record.facing or "North"
	local anchorX = typeof(record.cellX) == "number" and record.cellX or 1
	local anchorZ = typeof(record.cellZ) == "number" and record.cellZ or 1
	local minCellX, minCellZ, maxCellX, maxCellZ =
		footprintBounds(anchorX, anchorZ, record.WidthCells, record.DepthCells, facing)
	local columns, rows = getChunkDimensions()
	if columns and rows then
		minCellX = math.clamp(minCellX, 1, columns)
		minCellZ = math.clamp(minCellZ, 1, rows)
		maxCellX = math.clamp(maxCellX, 1, columns)
		maxCellZ = math.clamp(maxCellZ, 1, rows)
	end
	local widthCells = math.max(1, math.floor((record.WidthCells or 1) + 0.5))
	local depthCells = math.max(1, math.floor((record.DepthCells or 1) + 0.5))
	return {
		PlacementKey = key,
		PlacementType = record.PlacementType or "CellObject",
		Level = record.Level or PlotStateStore.GetDefaultLevel(),
		ItemId = record.id,
		Facing = facing,
		WidthCells = widthCells,
		DepthCells = depthCells,
		MinCellX = minCellX,
		MaxCellX = maxCellX,
		MinCellZ = minCellZ,
		MaxCellZ = maxCellZ,
	}
end

function PlotStateStore.GetPlacementRoomCoverage(key: string): PlacementRoomCoverageRecord?
	if typeof(key) ~= "string" or key == "" then
		return nil
	end
	local record = PlotStateStore.GetPlacementEntry(key)
	if not record then
		return nil
	end
	local levelValue = if typeof(record.Level) == "number" then record.Level else PlotStateStore.GetDefaultLevel()
	local snapshot = getLevelDerivedSnapshot(levelValue)
	if not snapshot then
		return nil
	end
	local coverage = snapshot.PlacementCoverageByKey and snapshot.PlacementCoverageByKey[key]
	if not coverage then
		return nil
	end
	return {
		PlacementKey = coverage.PlacementKey,
		PlacementType = coverage.PlacementType,
		Level = coverage.Level,
		Facing = coverage.Facing,
		RoomIds = deepClone(coverage.RoomIds),
		HasOutdoorCells = coverage.HasOutdoorCells,
	}
end

return PlotStateStore
