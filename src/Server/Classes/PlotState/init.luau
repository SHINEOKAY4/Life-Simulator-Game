--!strict
-- ServerScriptService/Server/Classes/PlotState.lua
-- By calling this file init.luau inside a PlotState folder rojo will treat the folder as a module

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Chunks = require(script.Chunks)
local CellObjects = require(script.CellObjects)
local Floors = require(script.Floors)
local Roofs = require(script.Roofs)
local Walls = require(script.Walls)
local Attachments = require(script.Attachments)
local Rooms = require(script.Rooms)

local ItemFinder = require(ReplicatedStorage.Shared.Utilities.ItemFinder)
local PlacementKey = require(ReplicatedStorage.Shared.Utilities.PlacementKey)
local PlacementBehavior = require(ReplicatedStorage.Shared.Utilities.PlacementBehavior)
local BuildConstants = require(ReplicatedStorage.Shared.Configurations.BuildConstants)

local function cloneMetadata(value: any): any
	if typeof(value) ~= "table" then
		return value
	end

	local copy = {}
	for key, entry in pairs(value) do
		copy[key] = cloneMetadata(entry)
	end

	return copy
end

local function toPositionTable(position: Vector3 | { [string]: any }?): { X: number, Y: number, Z: number }?
	if typeof(position) == "Vector3" then
		return {
			X = position.X,
			Y = position.Y,
			Z = position.Z,
		}
	end

	if typeof(position) ~= "table" then
		return nil
	end

	local xValue = position.X or position.x
	local yValue = position.Y or position.y
	local zValue = position.Z or position.z
	if typeof(xValue) ~= "number" or typeof(yValue) ~= "number" or typeof(zValue) ~= "number" then
		return nil
	end

	return {
		X = xValue,
		Y = yValue,
		Z = zValue,
	}
end

local function sanitizeRotation(value: any): number?
	if typeof(value) ~= "number" then
		return nil
	end

	if not (value == value) then
		return nil
	end

	return value
end

local function surfaceMountKey(parentKey: string, index: number): string
	return ("%s::%d"):format(parentKey, index)
end

export type Facing = "North" | "East" | "South" | "West" | "NorthEast" | "NorthWest" | "SouthEast" | "SouthWest"
export type SavedChunk = { cx: number, cz: number }
export type SavedPlacedObject = {
	id: string,
	cellX: number,
	cellZ: number,
	facing: Facing?,
	yLevel: number?,
	WidthCells: number?,
	DepthCells: number?,
	Metadata: { [string]: any }?,
}

export type PlacedObjectMap = { [string]: SavedPlacedObject }

export type SavedSurfaceMount = {
	id: string,
	parentKey: string,
	mountIndex: number,
	LocalPosition: { X: number, Y: number, Z: number },
	LocalRotationY: number?,
	Metadata: { [string]: any }?,
}

export type SurfaceMountedMap = { [string]: SavedSurfaceMount }

export type SurfaceMountCounterMap = { [string]: number }

export type Room = {
	Id: number,
	Level: number,
	Cells: { number },
	CellCount: number,
	MinX: number,
	MinZ: number,
	MaxX: number,
	MaxZ: number,
	InsulationScore: number,
	HeatingPower: number,
	CoolingPower: number,
	CurrentTemperature: number,
	LightingScore: number,
}

export type SaveData = {
	UnlockedChunks: { SavedChunk },
	PlacedObjects: PlacedObjectMap,
	SurfaceMountedObjects: SurfaceMountedMap?,
	SurfaceMountCounters: SurfaceMountCounterMap?,
}

export type PlotState = {
	Owner: Player?,
	Grid: any,
	ChunkSizeInCells: number,
	ChunkColumns: number,
	ChunkRows: number,
	ChunkUnlocked: { [number]: boolean },
	DefaultLevel: number,
	MaxFloorLevel: number,
	FloorHeightStuds: number,
	CellFree: { [number]: boolean },
	FloorFilled: { [number]: boolean },
	RoofFilled: { [number]: boolean },
	CellFreeByLevel: { [number]: { [number]: boolean } },
	FloorFilledByLevel: { [number]: { [number]: boolean } },
	RoofFilledByLevel: { [number]: { [number]: boolean } },
	HorizontalEdgeColumns: number,
	HorizontalEdgeRows: number,
	VerticalEdgeColumns: number,
	VerticalEdgeRows: number,
	EdgeFreeHorizontal: { [number]: boolean },
	EdgeFreeVertical: { [number]: boolean },
	DiagonalForwardEdgeColumns: number,
	DiagonalForwardEdgeRows: number,
	DiagonalBackwardEdgeColumns: number,
	DiagonalBackwardEdgeRows: number,
	EdgeFreeDiagonalForward: { [number]: boolean },
	EdgeFreeDiagonalBackward: { [number]: boolean },
	EdgeFreeHorizontalByLevel: { [number]: { [number]: boolean } },
	EdgeFreeVerticalByLevel: { [number]: { [number]: boolean } },
	EdgeFreeDiagonalForwardByLevel: { [number]: { [number]: boolean } },
	EdgeFreeDiagonalBackwardByLevel: { [number]: { [number]: boolean } },
	FloorAnchorCacheByLevel: { [number]: { [number]: string } }?,
	Save: SaveData,
	SurfaceMountedObjects: SurfaceMountedMap,
	SurfaceMountCounters: SurfaceMountCounterMap,
	PlacementKey: (self: PlotState, cellX: number, cellZ: number, facing: Facing?, yLevel: number?) -> string,
	PlacementKeyForType: (
		self: PlotState,
		cellX: number,
		cellZ: number,
		facing: Facing?,
		placementType: string?,
		yLevel: number?
	) -> string,
	NormalizeLevel: (self: PlotState, yLevel: number?) -> number,
	GetFloorHeightStuds: (self: PlotState) -> number,
	GetCellFreeForLevel: (self: PlotState, yLevel: number?) -> { [number]: boolean },
	GetFloorFilledForLevel: (self: PlotState, yLevel: number?) -> { [number]: boolean },
	InvalidateFloorAnchors: (self: PlotState, yLevel: number?) -> (),
	GetFloorPlacementKey: (self: PlotState, cellX: number, cellZ: number, yLevel: number?) -> string?,
	GetRoofFilledForLevel: (self: PlotState, yLevel: number?) -> { [number]: boolean },
	ChunkIndex: (self: PlotState, chunkX: number, chunkZ: number) -> number,
	IsChunkUnlocked: (self: PlotState, chunkX: number, chunkZ: number) -> boolean,
	IsChunkInBounds: (self: PlotState, chunkX: number, chunkZ: number) -> boolean,
	UnlockChunk: (self: PlotState, chunkX: number, chunkZ: number) -> boolean,
	HasAdjacentUnlocked: (self: PlotState, chunkX: number, chunkZ: number) -> boolean,
	EdgeOfCell: (
		self: PlotState,
		cellX: number,
		cellZ: number,
		facing: Facing
	) -> ("Horizontal" | "Vertical", number, number),
	HorizontalEdgeIndex: (self: PlotState, edgeX: number, edgeZ: number) -> number,
	VerticalEdgeIndex: (self: PlotState, edgeX: number, edgeZ: number) -> number,
	CanPlaceWall: (
		self: PlotState,
		cellX: number,
		cellZ: number,
		facing: Facing,
		requiresFloorOnBothSides: boolean?,
		yLevel: number?
	) -> boolean,
	PlaceWall: (
		self: PlotState,
		objectId: string,
		cellX: number,
		cellZ: number,
		_widthCells: number,
		_depthCells: number,
		facing: Facing,
		requiresFloorOnBothSides: boolean?,
		metadata: { [string]: any }?,
		yLevel: number?
	) -> boolean,
	ReplaceWallSegment: (
		self: PlotState,
		objectId: string,
		cellX: number,
		cellZ: number,
		facing: Facing,
		requiresFloorOnBothSides: boolean?,
		replaceableTag: string?,
		yLevel: number?
	) -> (string?, string?),
	RemoveWall: (
		self: PlotState,
		cellX: number,
		cellZ: number,
		facing: Facing,
		yLevel: number?
	) -> { removedId: string, restoredId: string? }?,
	HydrateFromSave: (self: PlotState) -> (),
	HasFloorUnderFootprint: (
		self: PlotState,
		cellX: number,
		cellZ: number,
		widthCells: number,
		depthCells: number,
		facing: Facing,
		yLevel: number?
	) -> boolean,
	CanPlaceFloor: (
		self: PlotState,
		cellX: number,
		cellZ: number,
		widthCells: number?,
		depthCells: number?,
		facing: Facing?,
		yLevel: number?
	) -> boolean,
	PlaceFloor: (
		self: PlotState,
		id: string,
		cellX: number,
		cellZ: number,
		widthCells: number?,
		depthCells: number?,
		facing: Facing?,
		yLevel: number?,
		metadataOverride: { [string]: any }?
	) -> boolean,
	RemoveFloor: (
		self: PlotState,
		cellX: number,
		cellZ: number,
		widthCells: number?,
		depthCells: number?,
		facing: Facing?,
		yLevel: number?
	) -> (),
	CanPlaceRoof: (
		self: PlotState,
		cellX: number,
		cellZ: number,
		widthCells: number,
		depthCells: number,
		facing: Facing,
		yLevel: number?
	) -> boolean,
	PlaceRoof: (
		self: PlotState,
		objectId: string,
		cellX: number,
		cellZ: number,
		widthCells: number,
		depthCells: number,
		facing: Facing,
		yLevel: number?
	) -> boolean,
	RemoveRoof: (
		self: PlotState,
		cellX: number,
		cellZ: number,
		widthCells: number,
		depthCells: number,
		facing: Facing,
		yLevel: number?
	) -> (),
	CanPlaceWallMounted: (
		self: PlotState,
		cellX: number,
		cellZ: number,
		facing: Facing,
		yLevel: number?
	) -> (boolean, string?),
	PlaceWallMounted: (
		self: PlotState,
		objectId: string,
		cellX: number,
		cellZ: number,
		facing: Facing,
		metadata: { [string]: any }?,
		yLevel: number?
	) -> (boolean, string?),
	RemoveWallMounted: (
		self: PlotState,
		cellX: number,
		cellZ: number,
		facing: Facing,
		yLevel: number?
	) -> SavedPlacedObject?,
	CanPlaceCeilingMounted: (
		self: PlotState,
		cellX: number,
		cellZ: number,
		facing: Facing,
		yLevel: number?
	) -> (boolean, string?),
	PlaceCeilingMounted: (
		self: PlotState,
		objectId: string,
		cellX: number,
		cellZ: number,
		facing: Facing,
		metadata: { [string]: any }?,
		yLevel: number?
	) -> (boolean, string?),
	RemoveCeilingMounted: (
		self: PlotState,
		cellX: number,
		cellZ: number,
		facing: Facing,
		yLevel: number?
	) -> SavedPlacedObject?,
	PlaceSurfaceMount: (
		self: PlotState,
		objectId: string,
		parentKey: string,
		localPosition: Vector3 | { [string]: any },
		localRotationY: number?,
		metadata: { [string]: any }?
	) -> (string?, string?),
	RemoveSurfaceMount: (self: PlotState, mountKey: string) -> SavedSurfaceMount?,
	GetSurfaceMountsForParent: (self: PlotState, parentKey: string) -> { [string]: SavedSurfaceMount },
	GetSurfaceMount: (self: PlotState, mountKey: string) -> SavedSurfaceMount?,
	IsCellBuildable: (self: PlotState, cellX: number, cellZ: number) -> boolean,
	CanPlace: (
		self: PlotState,
		anchorX: number,
		anchorZ: number,
		widthCells: number,
		depthCells: number,
		facing: Facing
	) -> boolean,
	ReserveFootprint: (
		self: PlotState,
		anchorX: number,
		anchorZ: number,
		widthCells: number,
		depthCells: number,
		facing: Facing
	) -> boolean,
	FreeFootprint: (
		self: PlotState,
		anchorX: number,
		anchorZ: number,
		widthCells: number,
		depthCells: number,
		facing: Facing
	) -> (),
	SetFootprintInteriorEdgesFree: (
		self: PlotState,
		anchorX: number,
		anchorZ: number,
		widthCells: number,
		depthCells: number,
		facing: Facing,
		isFree: boolean,
		yLevel: number?
	) -> (),
	Place: (
		self: PlotState,
		objectId: string,
		anchorX: number,
		anchorZ: number,
		widthCells: number,
		depthCells: number,
		facing: Facing,
		yLevel: number?,
		options: { [string]: any }?
	) -> (boolean, string),
	RemoveCellObject: (
		self: PlotState,
		cellX: number,
		cellZ: number,
		widthCells: number,
		depthCells: number,
		facing: Facing,
		yLevel: number?,
		options: { [string]: any }?
	) -> (),
	MoveCellObject: (
		self: PlotState,
		itemId: string,
		fromX: number,
		fromZ: number,
		fromF: Facing,
		toX: number,
		toZ: number,
		toF: Facing,
		fromLevel: number?,
		toLevel: number?,
		options: { [string]: any }?
	) -> (boolean, string?),
	MoveFloor: (
		self: PlotState,
		itemId: string,
		fromX: number,
		fromZ: number,
		toX: number,
		toZ: number,
		fromLevel: number?,
		toLevel: number?
	) -> (boolean, string?),
	MoveRoof: (
		self: PlotState,
		itemId: string,
		fromX: number,
		fromZ: number,
		fromF: Facing,
		toX: number,
		toZ: number,
		toF: Facing,
		fromLevel: number?,
		toLevel: number?
	) -> (boolean, string?),
	MoveWall: (
		self: PlotState,
		itemId: string,
		fromX: number,
		fromZ: number,
		fromF: Facing,
		toX: number,
		toZ: number,
		toF: Facing,
		fromLevel: number?,
		toLevel: number?
	) -> (boolean, string?),
	RotateCellObject: (self: PlotState, itemId: string, fromKey: string, toF: Facing) -> (boolean, string?),
	RotateFloor: (self: PlotState) -> (boolean, string?),
	RotateRoof: (self: PlotState, itemId: string, fromKey: string, toF: Facing) -> (boolean, string?),
	RotateWall: (self: PlotState, itemId: string, fromKey: string, toF: Facing) -> (boolean, string?),
	InvalidateRooms: (self: PlotState, yLevel: number?) -> (),
	GetRoomsForLevel: (self: PlotState, yLevel: number?) -> { Room },
	GetRoomAt: (self: PlotState, cellX: number, cellZ: number, yLevel: number?) -> Room?,
	RecalculateRooms: (self: PlotState, yLevel: number?) -> { Room },
}

local PlotState = {} :: any
PlotState.__index = PlotState

local DEFAULT_LEVEL = 0
local MAX_FLOOR_LEVELS = 3
local FLOOR_HEIGHT_STUDS = BuildConstants.FloorHeightStuds or 16

local function placementKey(cellX: number, cellZ: number, facing: Facing?, yLevel: number?): string
	return PlacementKey.FromComponents(cellX, cellZ, facing, yLevel)
end

local function placementKeyForType(
	cellX: number,
	cellZ: number,
	facing: Facing?,
	placementType: string?,
	yLevel: number?
): string
	return PlacementKey.ForPlacementType(cellX, cellZ, facing, placementType, yLevel)
end

local function normalizeLevel(yLevel: number?): number
	local numeric = tonumber(yLevel)
	if not numeric then
		return DEFAULT_LEVEL
	end
	numeric = math.floor(numeric + 0.5)
	if numeric < DEFAULT_LEVEL then
		return DEFAULT_LEVEL
	end
	if numeric > MAX_FLOOR_LEVELS then
		return MAX_FLOOR_LEVELS
	end
	return numeric
end

PlotState.PlacementKey = placementKey
PlotState.PlacementKeyForType = placementKeyForType

function PlotState.ResolveLevel(yLevel: number?): number
	return normalizeLevel(yLevel)
end

function PlotState:NormalizeLevel(yLevel: number?): number
	return normalizeLevel(yLevel)
end

function PlotState:GetFloorHeightStuds(): number
	return FLOOR_HEIGHT_STUDS
end

function PlotState:PlacementKey(cellX: number, cellZ: number, facing: Facing?, yLevel: number?): string
	return placementKey(cellX, cellZ, facing, yLevel)
end

function PlotState:PlacementKeyForType(
	cellX: number,
	cellZ: number,
	facing: Facing?,
	placementType: string?,
	yLevel: number?
): string
	return placementKeyForType(cellX, cellZ, facing, placementType, yLevel)
end

function PlotState:GetCellFreeForLevel(yLevel: number?): { [number]: boolean }
	local level = normalizeLevel(yLevel)
	local existing = self.CellFreeByLevel[level]
	if existing then
		return existing
	end
	local created = table.create(self.Grid:CellCount(), true)
	self.CellFreeByLevel[level] = created
	return created
end

function PlotState:GetFloorFilledForLevel(yLevel: number?): { [number]: boolean }
	local level = normalizeLevel(yLevel)
	local existing = self.FloorFilledByLevel[level]
	if existing then
		return existing
	end
	local created = table.create(self.Grid:CellCount(), false)
	self.FloorFilledByLevel[level] = created
	return created
end

function PlotState:GetRoofFilledForLevel(yLevel: number?): { [number]: boolean }
	local level = normalizeLevel(yLevel)
	local existing = self.RoofFilledByLevel[level]
	if existing then
		return existing
	end
	local created = table.create(self.Grid:CellCount(), false)
	self.RoofFilledByLevel[level] = created
	return created
end

function PlotState:GetEdgeFreeHorizontalForLevel(yLevel: number?): { [number]: boolean }
	local level = normalizeLevel(yLevel)
	local existing = self.EdgeFreeHorizontalByLevel[level]
	if existing then
		return existing
	end
	local created = table.create(self.HorizontalEdgeColumns * self.HorizontalEdgeRows, true)
	self.EdgeFreeHorizontalByLevel[level] = created
	return created
end

function PlotState:GetEdgeFreeVerticalForLevel(yLevel: number?): { [number]: boolean }
	local level = normalizeLevel(yLevel)
	local existing = self.EdgeFreeVerticalByLevel[level]
	if existing then
		return existing
	end
	local created = table.create(self.VerticalEdgeColumns * self.VerticalEdgeRows, true)
	self.EdgeFreeVerticalByLevel[level] = created
	return created
end

function PlotState:GetEdgeFreeDiagonalForwardForLevel(yLevel: number?): { [number]: boolean }
	local level = normalizeLevel(yLevel)
	local existing = self.EdgeFreeDiagonalForwardByLevel[level]
	if existing then
		return existing
	end
	local created = table.create(self.DiagonalForwardEdgeColumns * self.DiagonalForwardEdgeRows, true)
	self.EdgeFreeDiagonalForwardByLevel[level] = created
	return created
end

function PlotState:GetEdgeFreeDiagonalBackwardForLevel(yLevel: number?): { [number]: boolean }
	local level = normalizeLevel(yLevel)
	local existing = self.EdgeFreeDiagonalBackwardByLevel[level]
	if existing then
		return existing
	end
	local created = table.create(self.DiagonalBackwardEdgeColumns * self.DiagonalBackwardEdgeRows, true)
	self.EdgeFreeDiagonalBackwardByLevel[level] = created
	return created
end

function PlotState.new(grid: any, chunkSizeInCells: number, save: SaveData): PlotState
	local chunkColumns: number, chunkRows: number = grid:ChunkCounts(chunkSizeInCells)
	local self = setmetatable({} :: any, PlotState) :: PlotState
	self.Owner = nil
	self.Grid = grid
	self.ChunkSizeInCells = chunkSizeInCells
	self.ChunkColumns = chunkColumns
	self.ChunkRows = chunkRows
	self.ChunkUnlocked = table.create(chunkColumns * chunkRows, false)
	self.DefaultLevel = DEFAULT_LEVEL
	self.MaxFloorLevel = MAX_FLOOR_LEVELS
	self.FloorHeightStuds = FLOOR_HEIGHT_STUDS
	self.CellFreeByLevel = {}
	self.FloorFilledByLevel = {}
	self.RoofFilledByLevel = {}

	local baseCellCount = grid:CellCount()
	self.CellFreeByLevel[self.DefaultLevel] = table.create(baseCellCount, true)
	self.FloorFilledByLevel[self.DefaultLevel] = table.create(baseCellCount, false)
	self.RoofFilledByLevel[self.DefaultLevel] = table.create(baseCellCount, false)
	self.CellFree = self.CellFreeByLevel[self.DefaultLevel]
	self.FloorFilled = self.FloorFilledByLevel[self.DefaultLevel]
	self.RoofFilled = self.RoofFilledByLevel[self.DefaultLevel]
	self.HorizontalEdgeColumns = grid.Columns
	self.HorizontalEdgeRows = grid.Rows + 1
	self.VerticalEdgeColumns = grid.Columns + 1
	self.VerticalEdgeRows = grid.Rows
	self.EdgeFreeHorizontalByLevel = {}
	self.EdgeFreeVerticalByLevel = {}
	self.DiagonalForwardEdgeColumns = grid.Columns
	self.DiagonalForwardEdgeRows = grid.Rows
	self.DiagonalBackwardEdgeColumns = grid.Columns
	self.DiagonalBackwardEdgeRows = grid.Rows
	self.EdgeFreeDiagonalForwardByLevel = {}
	self.EdgeFreeDiagonalBackwardByLevel = {}

	local horizontalCount = self.HorizontalEdgeColumns * self.HorizontalEdgeRows
	local verticalCount = self.VerticalEdgeColumns * self.VerticalEdgeRows
	local diagForwardCount = self.DiagonalForwardEdgeColumns * self.DiagonalForwardEdgeRows
	local diagBackwardCount = self.DiagonalBackwardEdgeColumns * self.DiagonalBackwardEdgeRows

	self.EdgeFreeHorizontalByLevel[self.DefaultLevel] = table.create(horizontalCount, true)
	self.EdgeFreeVerticalByLevel[self.DefaultLevel] = table.create(verticalCount, true)
	self.EdgeFreeDiagonalForwardByLevel[self.DefaultLevel] = table.create(diagForwardCount, true)
	self.EdgeFreeDiagonalBackwardByLevel[self.DefaultLevel] = table.create(diagBackwardCount, true)
	self.EdgeFreeHorizontal = self.EdgeFreeHorizontalByLevel[self.DefaultLevel]
	self.EdgeFreeVertical = self.EdgeFreeVerticalByLevel[self.DefaultLevel]
	self.EdgeFreeDiagonalForward = self.EdgeFreeDiagonalForwardByLevel[self.DefaultLevel]
	self.EdgeFreeDiagonalBackward = self.EdgeFreeDiagonalBackwardByLevel[self.DefaultLevel]
	self.FloorAnchorCacheByLevel = {}
	self.Save = save
	self.Save.UnlockedChunks = self.Save.UnlockedChunks or {}
	self.Save.PlacedObjects = self.Save.PlacedObjects or {}
	self.Save.SurfaceMountedObjects = self.Save.SurfaceMountedObjects or {}
	self.Save.SurfaceMountCounters = self.Save.SurfaceMountCounters or {}
	self.SurfaceMountedObjects = self.Save.SurfaceMountedObjects :: SurfaceMountedMap
	self.SurfaceMountCounters = self.Save.SurfaceMountCounters :: SurfaceMountCounterMap

	local normalizedPlaced: PlacedObjectMap = {}
	local keyRemap: { [string]: string } = {}
	local normalizedSurfaceMounted: SurfaceMountedMap = {}
	local mountCounters: SurfaceMountCounterMap = {}
	for key, savedMount in pairs(self.SurfaceMountedObjects) do
		if typeof(savedMount) == "table" then
			local parentKey = savedMount.parentKey
			local mountIndex = savedMount.mountIndex
			if typeof(parentKey) == "string" and parentKey ~= "" and typeof(mountIndex) == "number" then
				local canonicalParent = parentKey
				local counterValue = mountCounters[canonicalParent]
				if not counterValue or mountIndex > counterValue then
					mountCounters[canonicalParent] = mountIndex
				end
				savedMount.parentKey = canonicalParent
				savedMount.mountIndex = mountIndex
				savedMount.LocalPosition = toPositionTable(savedMount.LocalPosition)
					or {
						X = 0,
						Y = 0,
						Z = 0,
					}
				savedMount.LocalRotationY = sanitizeRotation(savedMount.LocalRotationY)
				normalizedSurfaceMounted[key] = savedMount
			end
		end
	end
	self.SurfaceMountedObjects = normalizedSurfaceMounted
	self.SurfaceMountCounters = mountCounters
	self.Save.SurfaceMountedObjects = normalizedSurfaceMounted
	self.Save.SurfaceMountCounters = mountCounters
	for key, savedObject in pairs(self.Save.PlacedObjects) do
		if typeof(savedObject) == "table" then
			local spec = savedObject.id and ItemFinder.FindItemById(savedObject.id) or nil
			local cellX = savedObject.cellX or 0
			local cellZ = savedObject.cellZ or 0
			local facing: Facing = PlacementKey.NormalizeFacing(savedObject.facing)
			savedObject.facing = facing
			local normalizedLevel = normalizeLevel(savedObject.yLevel)
			savedObject.yLevel = normalizedLevel
			local _, _, _, typed = PlacementKey.ParseWithType(key)
			local defaultPlacementType = (spec and (spec.PlacementType or spec.Type)) or "CellObject"
			local placementType = typed or defaultPlacementType
			local placementKeyType = placementType
			if spec then
				local preferredKeyType = PlacementBehavior.getPlacementKeyLabel(spec)
				if placementType == defaultPlacementType and preferredKeyType ~= placementType then
					placementKeyType = preferredKeyType
				else
					placementKeyType = placementType
				end
			end
			local normalizedKey = PlacementKey.ForPlacementType(cellX, cellZ, facing, placementKeyType, normalizedLevel)
			normalizedPlaced[normalizedKey] = savedObject
			if key ~= normalizedKey then
				keyRemap[key] = normalizedKey
			end
		end
	end
	self.Save.PlacedObjects = normalizedPlaced

	if next(keyRemap) then
		local updatedCounters: SurfaceMountCounterMap = {}
		for _, savedMount in pairs(self.SurfaceMountedObjects) do
			local remappedParent = keyRemap[savedMount.parentKey]
			if remappedParent then
				savedMount.parentKey = remappedParent
			end
			local counterValue = updatedCounters[savedMount.parentKey]
			if not counterValue or savedMount.mountIndex > counterValue then
				updatedCounters[savedMount.parentKey] = savedMount.mountIndex
			end
		end
		self.SurfaceMountCounters = updatedCounters
		self.Save.SurfaceMountCounters = updatedCounters
	end
	return self
end

function PlotState:HydrateFromSave()
	for i = 1, #self.Save.UnlockedChunks do
		local savedChunk = self.Save.UnlockedChunks[i]
		self.ChunkUnlocked[self:ChunkIndex(savedChunk.cx, savedChunk.cz)] = true
	end

	for _, savedObject in pairs(self.Save.PlacedObjects) do
		local spec = ItemFinder.FindItemById(savedObject.id)
		assert(spec, ("Unknown catalog item '%s'"):format(savedObject.id))
		local placementType = spec.PlacementType or spec.Type or "CellObject"
		local facing = savedObject.facing or "North"
		local yLevel = normalizeLevel(savedObject.yLevel)
		local metadata = savedObject.Metadata
		local metaWidth = metadata and metadata.WidthCells or metadata and metadata.widthCells
		local metaDepth = metadata and metadata.DepthCells or metadata and metadata.depthCells
		local widthFallback = spec.WidthCells or spec.Width or 1
		local depthFallback = spec.DepthCells or spec.Depth or 1
		local resolvedWidth = metaWidth or widthFallback
		local resolvedDepth = metaDepth or depthFallback

		if placementType == "Floor" then
			local floorFacing: Facing = "North"
			local indices = self.Grid:FootprintCells(
				savedObject.cellX,
				savedObject.cellZ,
				resolvedWidth,
				resolvedDepth,
				floorFacing
			)
			local levelFloors = self:GetFloorFilledForLevel(yLevel)
			for j = 1, #indices do
				levelFloors[indices[j]] = true
			end
		elseif placementType == "Wall" then
			local alignment, edgeX, edgeZ = self:EdgeOfCell(savedObject.cellX, savedObject.cellZ, facing)
			local horizontalEdges = self:GetEdgeFreeHorizontalForLevel(yLevel)
			local verticalEdges = self:GetEdgeFreeVerticalForLevel(yLevel)
			local diagForwardEdges = self:GetEdgeFreeDiagonalForwardForLevel(yLevel)
			local diagBackwardEdges = self:GetEdgeFreeDiagonalBackwardForLevel(yLevel)
			if alignment == "Horizontal" then
				horizontalEdges[self:HorizontalEdgeIndex(edgeX, edgeZ)] = false
			elseif alignment == "Vertical" then
				verticalEdges[self:VerticalEdgeIndex(edgeX, edgeZ)] = false
			elseif alignment == "DiagonalForward" then
				diagForwardEdges[self:DiagonalForwardEdgeIndex(edgeX, edgeZ)] = false
				local cellOccupancy = self:GetCellFreeForLevel(yLevel)
				cellOccupancy[self.Grid:CellToIndex(savedObject.cellX, savedObject.cellZ)] = false
			elseif alignment == "DiagonalBackward" then
				diagBackwardEdges[self:DiagonalBackwardEdgeIndex(edgeX, edgeZ)] = false
				local cellOccupancy = self:GetCellFreeForLevel(yLevel)
				cellOccupancy[self.Grid:CellToIndex(savedObject.cellX, savedObject.cellZ)] = false
			end
		elseif placementType == "Roof" then
			local indices =
				self.Grid:FootprintCells(savedObject.cellX, savedObject.cellZ, resolvedWidth, resolvedDepth, facing)
			local levelRoofs = self:GetRoofFilledForLevel(yLevel)
			for j = 1, #indices do
				levelRoofs[indices[j]] = true
			end
		elseif placementType == "WallMounted" or placementType == "Ceiling" then
			-- Wall and ceiling attachments do not reserve grid occupancy during hydration.
			do
			end
		else
			local cellIndices =
				self.Grid:FootprintCells(savedObject.cellX, savedObject.cellZ, resolvedWidth, resolvedDepth, facing)
			local occupancy = self:GetCellFreeForLevel(yLevel)
			for j = 1, #cellIndices do
				occupancy[cellIndices[j]] = false
			end
			if self.SetFootprintInteriorEdgesFree then
				self:SetFootprintInteriorEdgesFree(
					savedObject.cellX,
					savedObject.cellZ,
					resolvedWidth,
					resolvedDepth,
					facing,
					false,
					yLevel
				)
			end
		end
	end
end

function PlotState:GetSurfaceMount(mountKey: string): SavedSurfaceMount?
	if typeof(mountKey) ~= "string" or mountKey == "" then
		return nil
	end

	return self.SurfaceMountedObjects[mountKey]
end

function PlotState:GetSurfaceMountsForParent(parentKey: string): { [string]: SavedSurfaceMount }
	local result: { [string]: SavedSurfaceMount } = {}
	if typeof(parentKey) ~= "string" or parentKey == "" then
		return result
	end

	for key, entry in pairs(self.SurfaceMountedObjects) do
		if entry.parentKey == parentKey then
			result[key] = entry
		end
	end

	return result
end

function PlotState:PlaceSurfaceMount(
	objectId: string,
	parentKey: string,
	localPosition: Vector3 | { [string]: any },
	localRotationY: number?,
	metadata: { [string]: any }?
): (string?, string?)
	if typeof(objectId) ~= "string" or objectId == "" then
		return nil, "Invalid object id"
	end

	if typeof(parentKey) ~= "string" or parentKey == "" then
		return nil, "Invalid parent"
	end

	local canonicalParent = parentKey
	if not self.Save.PlacedObjects[canonicalParent] then
		return nil, "Parent not found"
	end

	local positionTable = toPositionTable(localPosition)
	if not positionTable then
		return nil, "Invalid mount position"
	end

	local counters = self.SurfaceMountCounters
	local nextIndex = (counters[canonicalParent] or 0) + 1
	local candidateKey = surfaceMountKey(canonicalParent, nextIndex)
	while self.SurfaceMountedObjects[candidateKey] do
		nextIndex += 1
		candidateKey = surfaceMountKey(canonicalParent, nextIndex)
	end
	counters[canonicalParent] = nextIndex

	local entry: SavedSurfaceMount = {
		id = objectId,
		parentKey = canonicalParent,
		mountIndex = nextIndex,
		LocalPosition = positionTable,
		LocalRotationY = sanitizeRotation(localRotationY),
		Metadata = metadata and cloneMetadata(metadata) or nil,
	}

	self.SurfaceMountedObjects[candidateKey] = entry
	return candidateKey, nil
end

function PlotState:RemoveSurfaceMount(mountKey: string): SavedSurfaceMount?
	if typeof(mountKey) ~= "string" or mountKey == "" then
		return nil
	end

	local saved = self.SurfaceMountedObjects[mountKey]
	if not saved then
		return nil
	end

	self.SurfaceMountedObjects[mountKey] = nil
	return saved
end

Chunks.attach(PlotState)
CellObjects.attach(PlotState)
Floors.attach(PlotState)
Roofs.attach(PlotState)
Walls.attach(PlotState)
Attachments.attach(PlotState)
Rooms.attach(PlotState)

return PlotState
