-- !strict
-- StarterPlayer/StarterPlayerScripts/Client/ClientStores/PlotStateStore.lua

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local GoodSignal = require(ReplicatedStorage.Packages.GoodSignal)
local PlotFinder = require(ReplicatedStorage.Shared.Utilities.PlotFinder)
local GridModule = require(ReplicatedStorage.Shared.Utilities.Grid)
local Packets = require(ReplicatedStorage.Network.PlacementPackets)
local ItemFinder = require(ReplicatedStorage.Shared.Utilities.ItemFinder)
local BuildConstants = require(ReplicatedStorage.Shared.Configurations.BuildConstants)

local LevelSnapshotBuilder = require(script.Parent.LevelSnapshotBuilder)
local DataNormalization = require(script.Parent.DataNormalization)
local CutawayStateManager = require(script.Parent.CutawayStateManager)
local PacketProcessor = require(script.Parent.PacketProcessor)

type StateSnapshotType = {
	ChunkInfo: { [string]: any }?,
	ChunkUnlocked: { [number]: boolean }?,
	PlacedItems: { [string]: any }?,
	SurfaceMounts: { [string]: any }?,
	FloorHeightStuds: number?,
	DefaultLevel: number?,
	MaxLevel: number?,
	ActiveLevel: number?,
}

local PlotStateStore = {}
local StateSnapshot: StateSnapshotType = {}

local PlotModel = nil
local CachedSurface: BasePart? = nil
local CachedGrid: any? = nil
local ActiveLevelInitialized = false
local ActiveLevel = 0
local ActiveLevelChanged = GoodSignal.new()
local RoomSnapshotChanged = GoodSignal.new()
local PlacementMetadataChanged = GoodSignal.new()

-- Cutaway state manager instance
local CutawayManager: any = nil

export type CutawayState = CutawayStateManager.CutawayState
export type CutawayRequestOptions = CutawayStateManager.CutawayRequestOptions

-- Type aliases for types used in public API
type FloorCellDescriptor = {
	CellX: number,
	CellZ: number,
	CellIndex: number,
	PlacementKey: string,
	ItemId: string,
}

type WallSegmentDescriptor = {
	CellX: number,
	CellZ: number,
	Facing: string,
	PlacementKey: string,
	ItemId: string,
	Variant: string?,
	Orientation: "Cardinal" | "Diagonal",
	BlocksRooms: boolean,
	AdjacentCells: { CellA: { CellX: number, CellZ: number }?, CellB: { CellX: number, CellZ: number }? },
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

type LevelDerivedSnapshot = LevelSnapshotBuilder.LevelDerivedSnapshot

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

export type PlacementRoomCoverageRecord = LevelSnapshotBuilder.PlacementRoomCoverageRecord

-- Derived level metadata caches powering cutaway heuristics.
local DerivedLevelSnapshots: { [number]: LevelDerivedSnapshot } = {}

local function invalidateDerivedLevelSnapshots()
	DerivedLevelSnapshots = {}
	RoomSnapshotChanged:Fire()
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

local function resolveSnapshotCellIndex(snapshot: LevelDerivedSnapshot, cellX: number, cellZ: number): number?
	local columns = snapshot.Columns
	local rows = snapshot.Rows
	if columns <= 0 or rows <= 0 then
		return nil
	end
	local clampedX = math.clamp(math.floor(cellX + 0.5), 1, columns)
	local clampedZ = math.clamp(math.floor(cellZ + 0.5), 1, rows)
	return computeCellIndex(columns, clampedX, clampedZ)
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

local function getLevelDerivedSnapshot(level: number): LevelDerivedSnapshot?
	local cached = DerivedLevelSnapshots[level]
	if cached then
		return cached
	end

	local placedItems = StateSnapshot.PlacedItems
	if not placedItems then
		return nil
	end
	local columns, rows = getChunkDimensions()
	if not columns or not rows then
		return nil
	end

	local built = LevelSnapshotBuilder.Build(level, columns, rows, placedItems, PlotStateStore.GetDefaultLevel())
	DerivedLevelSnapshots[level] = built
	return built
end

local function ChunkToIndex(chunkX: number, chunkZ: number, chunkColumns: number): number
	return (chunkZ - 1) * chunkColumns + chunkX
end

function PlotStateStore.Init()
	-- Initialize CutawayManager
	local defaultLevel = 0
	local maxLevel = 0
	local function getActiveLevel(): number
		return ActiveLevel
	end

	Packets.PlotStateSync.OnClientEvent:Connect(function(chunkInfo, unlockedChunks, placedItems, surfaceMounts)
		StateSnapshot.ChunkInfo = chunkInfo
		StateSnapshot.ChunkUnlocked = unlockedChunks
		StateSnapshot.FloorHeightStuds = chunkInfo.FloorHeightStuds
		StateSnapshot.DefaultLevel = chunkInfo.DefaultLevel
		StateSnapshot.MaxLevel = chunkInfo.MaxLevel

		defaultLevel = if typeof(chunkInfo.DefaultLevel) == "number" then chunkInfo.DefaultLevel else 0
		maxLevel = if typeof(chunkInfo.MaxLevel) == "number" then chunkInfo.MaxLevel else defaultLevel

		-- Initialize CutawayManager on first sync
		if not CutawayManager then
			CutawayManager = CutawayStateManager.new(defaultLevel, maxLevel, getActiveLevel)
		end

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

		StateSnapshot.PlacedItems = PacketProcessor.NormalizePlacedItemsArray(placedItems, defaultLevel)

		local surfaceMap = {}
		if surfaceMounts then
			for _, entry in ipairs(surfaceMounts) do
				local normalized = DataNormalization.NormalizeSurfaceMountEntry(entry)
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
		if not StateSnapshot.PlacedItems then
			StateSnapshot.PlacedItems = {}
		end
		local _, changed = PacketProcessor.ApplyPlacementDelta(
			StateSnapshot.PlacedItems :: { [string]: any },
			delta,
			PlotStateStore.GetDefaultLevel()
		)
		if changed then
			invalidateDerivedLevelSnapshots()
		end
	end)

	Packets.SurfaceMountDelta.OnClientEvent:Connect(function(delta)
		if not StateSnapshot.SurfaceMounts then
			StateSnapshot.SurfaceMounts = {}
		end
		if not delta or not delta.Mount then
			return
		end

		local normalized = DataNormalization.NormalizeSurfaceMountEntry(delta.Mount)
		if not normalized then
			return
		end

		local surfaceMounts = StateSnapshot.SurfaceMounts :: { [string]: any }
		if delta.Action == "Removed" then
			surfaceMounts[normalized.key] = nil
			return
		end

		if delta.Action ~= "Placed" and delta.Action ~= "Updated" then
			return
		end

		surfaceMounts[normalized.key] = normalized
	end)

	Packets.UtilityUpdate.OnClientEvent:Connect(function(changes)
		if not StateSnapshot.PlacedItems then
			StateSnapshot.PlacedItems = {}
		end
		local placedItems = StateSnapshot.PlacedItems :: { [string]: any }
		local anyChanged = false
		for _, change in ipairs(changes) do
			local key = change.Key
			local metadata = DataNormalization.NormalizeMetadata(change.Metadata)
			local entry = placedItems[key]
			if entry then
				entry.Metadata = metadata
				anyChanged = true
			end
		end
		if anyChanged then
			PlacementMetadataChanged:Fire()
		end
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
	if CutawayManager then
		CutawayManager.RefreshState()
	end
end

function PlotStateStore.OnActiveLevelChanged(handler: (number) -> ()): RBXScriptConnection
	return ActiveLevelChanged:Connect(handler)
end

function PlotStateStore.RequestCutaway(source: string, options: CutawayRequestOptions?)
	if not CutawayManager then
		return
	end
	CutawayManager.RequestCutaway(source, options)
end

function PlotStateStore.ReleaseCutaway(source: string)
	if not CutawayManager then
		return
	end
	CutawayManager.ReleaseCutaway(source)
end

function PlotStateStore.ClearCutawayRequests()
	if not CutawayManager then
		return
	end
	CutawayManager.ClearAllRequests()
end

function PlotStateStore.GetCutawayState(): CutawayState
	if not CutawayManager then
		return {
			Visible = false,
			Source = nil,
			TargetLevel = PlotStateStore.GetActiveLevel(),
			HidePlacementTypes = {},
		}
	end
	return CutawayManager.GetState()
end

function PlotStateStore.OnCutawayChanged(handler: (CutawayState) -> ()): RBXScriptConnection
	if not CutawayManager then
		local signal = GoodSignal.new()
		return signal:Connect(handler)
	end
	return CutawayManager.OnCutawayChanged(handler)
end

function PlotStateStore.OnRoomSnapshotChanged(handler: () -> ()): RBXScriptConnection
	return RoomSnapshotChanged:Connect(handler)
end

function PlotStateStore.OnPlacementMetadataChanged(handler: () -> ()): RBXScriptConnection
	return PlacementMetadataChanged:Connect(handler)
end

function PlotStateStore.GetFloorHeightStuds(): number
	local info = StateSnapshot.ChunkInfo
	if info and typeof(info.FloorHeightStuds) == "number" then
		return info.FloorHeightStuds
	end
	return BuildConstants.FloorHeightStuds or 16
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

function PlotStateStore.GetRoomsForLevel(level: number?): { RoomRecord }?
	local resolvedLevel = sanitizeLevelInput(level)
	local snapshot = getLevelDerivedSnapshot(resolvedLevel)
	if not snapshot then
		return nil
	end

	-- Return a shallow copy of the rooms list
	local rooms = {}
	for i, room in ipairs(snapshot.RoomsList) do
		rooms[i] = {
			Id = room.Id,
			RoomId = room.Id, -- Alias for compatibility
			Level = room.Level,
			CellCount = room.CellCount,
			MinCellX = room.MinCellX,
			MaxCellX = room.MaxCellX,
			MinCellZ = room.MinCellZ,
			MaxCellZ = room.MaxCellZ,
			CellIndices = copyNumberArray(room.CellIndices),
			Cells = copyNumberArray(room.CellIndices), -- Alias for compatibility
		}
	end
	return rooms
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
		RoomIds = DataNormalization.DeepClone(coverage.RoomIds),
		HasOutdoorCells = coverage.HasOutdoorCells,
	}
end

function PlotStateStore.HasFloorAtCell(level: number?, cellX: number, cellZ: number): boolean
	local resolvedLevel = sanitizeLevelInput(level)
	local snapshot = getLevelDerivedSnapshot(resolvedLevel)
	if not snapshot then
		return false
	end
	local index = resolveSnapshotCellIndex(snapshot, cellX, cellZ)
	if not index then
		return false
	end
	return snapshot.FloorCellsByIndex[index] ~= nil
end

function PlotStateStore.GetFloorPlacementKey(level: number?, cellX: number, cellZ: number): string?
	local resolvedLevel = sanitizeLevelInput(level)
	local snapshot = getLevelDerivedSnapshot(resolvedLevel)
	if not snapshot then
		return nil
	end
	local index = resolveSnapshotCellIndex(snapshot, cellX, cellZ)
	if not index then
		return nil
	end
	local descriptor = snapshot.FloorCellsByIndex[index]
	if not descriptor then
		return nil
	end
	return descriptor.PlacementKey
end

function PlotStateStore.GetFloorPlacementKeyByIndex(level: number?, cellIndex: number): string?
	if typeof(cellIndex) ~= "number" then
		return nil
	end
	local resolvedLevel = sanitizeLevelInput(level)
	local snapshot = getLevelDerivedSnapshot(resolvedLevel)
	if not snapshot then
		return nil
	end
	local descriptor = snapshot.FloorCellsByIndex[cellIndex]
	if not descriptor then
		return nil
	end
	return descriptor.PlacementKey
end

function PlotStateStore.HasRoofCoverage(level: number?, cellX: number, cellZ: number): boolean
	local resolvedLevel = sanitizeLevelInput(level)
	local snapshot = getLevelDerivedSnapshot(resolvedLevel)
	if not snapshot then
		return false
	end
	local index = resolveSnapshotCellIndex(snapshot, cellX, cellZ)
	if not index then
		return false
	end
	return snapshot.RoofCellsByIndex[index] == true
end

function PlotStateStore.HasCeilingSupport(level: number?, cellX: number, cellZ: number): boolean
	local resolvedLevel = sanitizeLevelInput(level)
	if PlotStateStore.HasRoofCoverage(resolvedLevel, cellX, cellZ) then
		return true
	end
	local aboveLevel = resolvedLevel + 1
	if aboveLevel > PlotStateStore.GetMaxLevel() then
		return false
	end
	return PlotStateStore.HasFloorAtCell(aboveLevel, cellX, cellZ)
end

function PlotStateStore.IsCellUnlocked(cellX: number, cellZ: number): boolean
	if not PlotStateStore.IsReady() then
		return false
	end
	local chunkInfo = StateSnapshot.ChunkInfo
	if not chunkInfo then
		return false
	end
	local chunkSize = tonumber(chunkInfo.ChunkSizeInCells)
	local chunkColumns = tonumber(chunkInfo.ChunkColumns)
	local chunkRows = tonumber(chunkInfo.ChunkRows)
	if not chunkSize or chunkSize <= 0 or not chunkColumns or not chunkRows then
		return false
	end
	local maxCellX = chunkColumns * chunkSize
	local maxCellZ = chunkRows * chunkSize
	local resolvedX = math.clamp(math.floor(cellX + 0.5), 1, maxCellX)
	local resolvedZ = math.clamp(math.floor(cellZ + 0.5), 1, maxCellZ)
	local chunkX = math.floor((resolvedX - 1) / chunkSize) + 1
	local chunkZ = math.floor((resolvedZ - 1) / chunkSize) + 1
	if chunkX < 1 or chunkX > chunkColumns or chunkZ < 1 or chunkZ > chunkRows then
		return false
	end
	return PlotStateStore.IsChunkUnlocked(chunkX, chunkZ)
end

function PlotStateStore.OptimisticDisconnect(sourceKey: string, targetKey: string)
	local sourceEntry = StateSnapshot.PlacedItems and StateSnapshot.PlacedItems[sourceKey]
	local targetEntry = StateSnapshot.PlacedItems and StateSnapshot.PlacedItems[targetKey]

	local changed = false

	local function removeConnection(entry: any, keyToRemove: string)
		if entry and entry.Metadata and entry.Metadata.Connections then
			local connections = entry.Metadata.Connections
			for i = #connections, 1, -1 do
				if connections[i] == keyToRemove then
					table.remove(connections, i)
					changed = true
				end
			end

			-- Optimistic power down: assume disconnection cuts power for non-sources
			-- This gives immediate visual feedback (icon turns red)
			if entry.id then
				local spec = ItemFinder.FindItemById(entry.id)
				if spec and not spec.PowerSource then
					if entry.Metadata.IsPowered ~= false then
						entry.Metadata.IsPowered = false
						changed = true
					end
				end
			end
		end
	end

	removeConnection(sourceEntry, targetKey)
	removeConnection(targetEntry, sourceKey)

	if changed then
		PlacementMetadataChanged:Fire()
	end
end

return PlotStateStore
