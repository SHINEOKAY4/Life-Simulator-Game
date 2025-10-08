--!strict
-- ServerScriptService/Server/Classes/PlotState.lua
-- By calling this file init.luau inside a PlotState folder rojo will treat the folder as a module

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Chunks = require(script.Chunks)
local CellObjects = require(script.CellObjects)
local Floors = require(script.Floors)
local Roofs = require(script.Roofs)
local Walls = require(script.Walls)

local ItemFinder = require(ReplicatedStorage.Shared.Utilities.ItemFinder)
local PlacementKey = require(ReplicatedStorage.Shared.Utilities.PlacementKey)

export type Facing = "North" | "East" | "South" | "West"
export type SavedChunk = { cx: number, cz: number }
export type SavedPlacedObject = {
	id: string,
	cellX: number,
	cellZ: number,
	facing: Facing?,
	Metadata: { [string]: any }?,
}

export type PlacedObjectMap = { [string]: SavedPlacedObject }

export type SaveData = {
	UnlockedChunks: { SavedChunk },
	PlacedObjects: PlacedObjectMap,
}

export type PlotState = {
	Grid: any,
	ChunkSizeInCells: number,
	ChunkColumns: number,
	ChunkRows: number,
	ChunkUnlocked: { [number]: boolean },
	CellFree: { [number]: boolean },
	FloorFilled: { [number]: boolean },
	RoofFilled: { [number]: boolean },
	HorizontalEdgeColumns: number,
	HorizontalEdgeRows: number,
	VerticalEdgeColumns: number,
	VerticalEdgeRows: number,
	EdgeFreeHorizontal: { [number]: boolean },
	EdgeFreeVertical: { [number]: boolean },
	Save: SaveData,
	PlacementKey: (self: PlotState, cellX: number, cellZ: number, facing: Facing?) -> string,
	PlacementKeyForType: (
		self: PlotState,
		cellX: number,
		cellZ: number,
		facing: Facing?,
		placementType: string?
	) -> string,
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
		requiresFloorOnBothSides: boolean?
	) -> boolean,
	PlaceWall: (
		self: PlotState,
		objectId: string,
		cellX: number,
		cellZ: number,
		_widthCells: number,
		_depthCells: number,
		facing: Facing,
		requiresFloorOnBothSides: boolean?
	) -> boolean,
	ReplaceWallSegment: (
		self: PlotState,
		objectId: string,
		cellX: number,
		cellZ: number,
		facing: Facing,
		requiresFloorOnBothSides: boolean?,
		replaceableTag: string?
	) -> (string?, string?),
	RemoveWall: (
		self: PlotState,
		cellX: number,
		cellZ: number,
		facing: Facing
	) -> { removedId: string, restoredId: string? }?,
	HydrateFromSave: (self: PlotState) -> (),
	HasFloorUnderFootprint: (
		self: PlotState,
		cellX: number,
		cellZ: number,
		widthCells: number,
		depthCells: number,
		facing: Facing
	) -> boolean,
	CanPlaceFloor: (
		self: PlotState,
		cellX: number,
		cellZ: number,
		widthCells: number?,
		depthCells: number?,
		facing: Facing?
	) -> boolean,
	PlaceFloor: (
		self: PlotState,
		id: string,
		cellX: number,
		cellZ: number,
		widthCells: number?,
		depthCells: number?,
		facing: Facing?
	) -> boolean,
	RemoveFloor: (
		self: PlotState,
		cellX: number,
		cellZ: number,
		widthCells: number?,
		depthCells: number?,
		facing: Facing?
	) -> (),
	CanPlaceRoof: (
		self: PlotState,
		cellX: number,
		cellZ: number,
		widthCells: number,
		depthCells: number,
		facing: Facing
	) -> boolean,
	PlaceRoof: (
		self: PlotState,
		objectId: string,
		cellX: number,
		cellZ: number,
		widthCells: number,
		depthCells: number,
		facing: Facing
	) -> boolean,
	RemoveRoof: (
		self: PlotState,
		cellX: number,
		cellZ: number,
		widthCells: number,
		depthCells: number,
		facing: Facing
	) -> (),
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
	Place: (
		self: PlotState,
		objectId: string,
		anchorX: number,
		anchorZ: number,
		widthCells: number,
		depthCells: number,
		facing: Facing
	) -> (boolean, string),
	RemoveCellObject: (
		self: PlotState,
		cellX: number,
		cellZ: number,
		widthCells: number,
		depthCells: number,
		facing: Facing
	) -> (),
	MoveCellObject: (
		self: PlotState,
		itemId: string,
		fromX: number,
		fromZ: number,
		fromF: Facing,
		toX: number,
		toZ: number,
		toF: Facing
	) -> (boolean, string?),
	MoveFloor: (
		self: PlotState,
		itemId: string,
		fromX: number,
		fromZ: number,
		toX: number,
		toZ: number
	) -> (boolean, string?),
	MoveRoof: (
		self: PlotState,
		itemId: string,
		fromX: number,
		fromZ: number,
		fromF: Facing,
		toX: number,
		toZ: number,
		toF: Facing
	) -> (boolean, string?),
	MoveWall: (
		self: PlotState,
		itemId: string,
		fromX: number,
		fromZ: number,
		fromF: Facing,
		toX: number,
		toZ: number,
		toF: Facing
	) -> (boolean, string?),
	RotateCellObject: (self: PlotState, itemId: string, fromKey: string, toF: Facing) -> (boolean, string?),
	RotateFloor: (self: PlotState) -> (boolean, string?),
	RotateRoof: (self: PlotState, itemId: string, fromKey: string, toF: Facing) -> (boolean, string?),
	RotateWall: (self: PlotState, itemId: string, fromKey: string, toF: Facing) -> (boolean, string?),
}

local PlotState = {} :: any
PlotState.__index = PlotState

local function placementKey(cellX: number, cellZ: number, facing: Facing?): string
	return PlacementKey.FromComponents(cellX, cellZ, facing)
end

local function placementKeyForType(cellX: number, cellZ: number, facing: Facing?, placementType: string?): string
	return PlacementKey.ForPlacementType(cellX, cellZ, facing, placementType)
end

PlotState.PlacementKey = placementKey
PlotState.PlacementKeyForType = placementKeyForType

function PlotState:PlacementKey(cellX: number, cellZ: number, facing: Facing?): string
	return placementKey(cellX, cellZ, facing)
end

function PlotState:PlacementKeyForType(cellX: number, cellZ: number, facing: Facing?, placementType: string?): string
	return placementKeyForType(cellX, cellZ, facing, placementType)
end

function PlotState.new(grid: any, chunkSizeInCells: number, save: SaveData): PlotState
	local chunkColumns: number, chunkRows: number = grid:ChunkCounts(chunkSizeInCells)
	local self = setmetatable({} :: any, PlotState) :: PlotState
	self.Grid = grid
	self.ChunkSizeInCells = chunkSizeInCells
	self.ChunkColumns = chunkColumns
	self.ChunkRows = chunkRows
	self.ChunkUnlocked = table.create(chunkColumns * chunkRows, false)
	self.CellFree = table.create(grid:CellCount(), true)
	self.FloorFilled = table.create(grid:CellCount(), false)
	self.RoofFilled = table.create(grid:CellCount(), false)
	self.HorizontalEdgeColumns = grid.Columns
	self.HorizontalEdgeRows = grid.Rows + 1
	self.VerticalEdgeColumns = grid.Columns + 1
	self.VerticalEdgeRows = grid.Rows
	self.EdgeFreeHorizontal = table.create(self.HorizontalEdgeColumns * self.HorizontalEdgeRows, true)
	self.EdgeFreeVertical = table.create(self.VerticalEdgeColumns * self.VerticalEdgeRows, true)
	self.Save = save
	self.Save.PlacedObjects = self.Save.PlacedObjects or {}

	local normalizedPlaced: PlacedObjectMap = {}
	for key, savedObject in pairs(self.Save.PlacedObjects) do
		if typeof(savedObject) == "table" then
			local spec = savedObject.id and ItemFinder.FindItemById(savedObject.id) or nil
			local cellX = savedObject.cellX or 0
			local cellZ = savedObject.cellZ or 0
			local facing: Facing = PlacementKey.NormalizeFacing(savedObject.facing)
			savedObject.facing = facing
			local _, _, _, typed = PlacementKey.ParseWithType(key)
			local placementType = typed or (spec and (spec.PlacementType or spec.Type)) or "CellObject"
			local normalizedKey = PlacementKey.ForPlacementType(cellX, cellZ, facing, placementType)
			normalizedPlaced[normalizedKey] = savedObject
		end
	end
	self.Save.PlacedObjects = normalizedPlaced
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
		local placementType = spec.PlacementType
		local facing = savedObject.facing or "North"

		if placementType == "Floor" then
			local width = spec.WidthCells
			local depth = spec.DepthCells
			local floorFacing: Facing = "North"
			local indices = self.Grid:FootprintCells(savedObject.cellX, savedObject.cellZ, width, depth, floorFacing)
			for j = 1, #indices do
				self.FloorFilled[indices[j]] = true
			end
		elseif placementType == "Wall" then
			local alignment, edgeX, edgeZ = self:EdgeOfCell(savedObject.cellX, savedObject.cellZ, facing)
			if alignment == "Horizontal" then
				self.EdgeFreeHorizontal[self:HorizontalEdgeIndex(edgeX, edgeZ)] = false
			else
				self.EdgeFreeVertical[self:VerticalEdgeIndex(edgeX, edgeZ)] = false
			end
		elseif placementType == "Roof" then
			local width = spec.WidthCells
			local depth = spec.DepthCells
			local indices = self.Grid:FootprintCells(savedObject.cellX, savedObject.cellZ, width, depth, facing)
			for j = 1, #indices do
				self.RoofFilled[indices[j]] = true
			end
		else
			local width = spec.WidthCells
			local depth = spec.DepthCells
			local cellIndices = self.Grid:FootprintCells(savedObject.cellX, savedObject.cellZ, width, depth, facing)
			for j = 1, #cellIndices do
				self.CellFree[cellIndices[j]] = false
			end
		end
	end
end

Chunks.attach(PlotState)
CellObjects.attach(PlotState)
Floors.attach(PlotState)
Roofs.attach(PlotState)
Walls.attach(PlotState)

return PlotState
