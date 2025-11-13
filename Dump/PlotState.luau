--!strict
-- ServerScriptService/Server/Classes/PlotState.lua

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ItemFinder = require(ReplicatedStorage.Shared.Utilities.ItemFinder)

export type Facing = "North" | "East" | "South" | "West"
export type SaveData = {
	UnlockedChunks: { { cx: number, cz: number } },
	PlacedObjects: {
		{
			id: string,
			cellX: number,
			cellZ: number,
			facing: Facing?,
		}
	},
}

local PlotState = {}
PlotState.__index = PlotState
local function resolveCatalog(objectId: string): (any?, string, number, number)
	local spec = ItemFinder.FindItemById(objectId)
	local placementType = (spec and (spec.PlacementType or spec.Type)) or "CellObject"
	local width = (spec and (spec.WidthCells or spec.Width)) or 1
	local depth = (spec and (spec.DepthCells or spec.Depth)) or 1
	return spec, placementType, width, depth
end
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
		widthCells: number,
		depthCells: number,
		facing: Facing,
		requiresFloorOnBothSides: boolean?,
		metadata: { [string]: any }?
	) -> boolean,
	RemoveWall: (self: PlotState, cellX: number, cellZ: number, facing: Facing) -> (),
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
	RemoveRoof: (
		self: PlotState,
		cellX: number,
		cellZ: number,
		widthCells: number,
		depthCells: number,
		facing: Facing
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
	) -> boolean,
	RemoveCellObject: (
		self: PlotState,
		cellX: number,
		cellZ: number,
		widthCells: number,
		depthCells: number,
		facing: Facing
	) -> (),
}

function PlotState.new(grid: any, chunkSizeInCells: number, save: SaveData): PlotState
	-- NOTE: This assumes a `grid:ChunkCounts()` method exists that returns the number of chunk columns and rows.
	local chunkColumns: number, chunkRows: number = grid:ChunkCounts(chunkSizeInCells)
	local self = setmetatable({} :: any, PlotState) :: PlotState
	self.Grid = grid
	self.ChunkSizeInCells = chunkSizeInCells
	self.ChunkColumns = chunkColumns
	self.ChunkRows = chunkRows
	-- runtime state (does not persist) simply for faster lookups to avoid table scans
	self.ChunkUnlocked = table.create(chunkColumns * chunkRows, false)

	self.CellFree = table.create(grid:CellCount(), true)

	self.FloorFilled = table.create(grid:CellCount(), false)
	self.RoofFilled = table.create(grid:CellCount(), false)

	self.HorizontalEdgeColumns = grid.Columns -- x in [1..Columns]
	self.HorizontalEdgeRows = grid.Rows + 1 -- z in [1..Rows+1]
	self.VerticalEdgeColumns = grid.Columns + 1 -- x in [1..Columns+1]
	self.VerticalEdgeRows = grid.Rows -- z in [1..Rows]

	self.EdgeFreeHorizontal = table.create(self.HorizontalEdgeColumns * self.HorizontalEdgeRows, true)
	self.EdgeFreeVertical = table.create(self.VerticalEdgeColumns * self.VerticalEdgeRows, true)

	self.Save = save
	return self
end

-- Chunk Helpers --
function PlotState:ChunkIndex(chunkX: number, chunkZ: number): number
	return self.Grid:ChunkToIndex(chunkX, chunkZ, self.ChunkColumns)
end

function PlotState:IsChunkUnlocked(chunkX: number, chunkZ: number): boolean
	return self.ChunkUnlocked[self:ChunkIndex(chunkX, chunkZ)] == true
end

function PlotState:IsChunkInBounds(chunkX: number, chunkZ: number): boolean
	return chunkX >= 1 and chunkX <= self.ChunkColumns and chunkZ >= 1 and chunkZ <= self.ChunkRows
end

function PlotState:UnlockChunk(chunkX: number, chunkZ: number) -- Idempotent write-through (used during gameplay)
	local chunkIndex = self:ChunkIndex(chunkX, chunkZ)

	if self.ChunkUnlocked[chunkIndex] then
		return false
	end

	self.ChunkUnlocked[chunkIndex] = true

	self.Save.UnlockedChunks[#self.Save.UnlockedChunks + 1] = { cx = chunkX, cz = chunkZ }
	return true
end

function PlotState:HasAdjacentUnlocked(chunkX: number, chunkZ: number): boolean
	if chunkX > 1 and self:IsChunkUnlocked(chunkX - 1, chunkZ) then
		return true
	end
	if chunkX < self.ChunkColumns and self:IsChunkUnlocked(chunkX + 1, chunkZ) then
		return true
	end
	if chunkZ > 1 and self:IsChunkUnlocked(chunkX, chunkZ - 1) then
		return true
	end
	if chunkZ < self.ChunkRows and self:IsChunkUnlocked(chunkX, chunkZ + 1) then
		return true
	end
	return false
end

-- Walls --

function PlotState:EdgeOfCell(cellX: number, cellZ: number, facing: Facing): ("Horizontal" | "Vertical", number, number)
	if facing == "North" then
		return "Horizontal", cellX, cellZ -- edge above the cell
	elseif facing == "South" then
		return "Horizontal", cellX, cellZ + 1 -- edge below the cell
	elseif facing == "West" then
		return "Vertical", cellX, cellZ -- edge left of the cell
	else
		return "Vertical", cellX + 1, cellZ -- edge right of the cell
	end
end

function PlotState:HorizontalEdgeIndex(edgeX: number, edgeZ: number): number
	assert(edgeX >= 1 and edgeX <= self.HorizontalEdgeColumns, "Horizontal edge x out of bounds")
	assert(edgeZ >= 1 and edgeZ <= self.HorizontalEdgeRows, "Horizontal edge z out of bounds")
	return (edgeZ - 1) * self.HorizontalEdgeColumns + edgeX
end

function PlotState:VerticalEdgeIndex(edgeX: number, edgeZ: number): number
	assert(edgeX >= 1 and edgeX <= self.VerticalEdgeColumns, "Vertical edge x out of bounds")
	assert(edgeZ >= 1 and edgeZ <= self.VerticalEdgeRows, "Vertical edge z out of bounds")
	return (edgeZ - 1) * self.VerticalEdgeColumns + edgeX
end

function PlotState:CanPlaceWall(
	cellX: number,
	cellZ: number,
	facing: Facing,
	requiresFloorOnBothSides: boolean?
): boolean
	-- Chunk gating for the 1x1 anchor footprint
	local minChunkX, minChunkZ, maxChunkX, maxChunkZ =
		self.Grid:FootprintChunkRange(cellX, cellZ, 1, 1, facing, self.ChunkSizeInCells)

	for checkChunkZ = minChunkZ, maxChunkZ do
		for checkChunkX = minChunkX, maxChunkX do
			if not self:IsChunkUnlocked(checkChunkX, checkChunkZ) then
				return false
			end
		end
	end

	local alignment, edgeX, edgeZ = self:EdgeOfCell(cellX, cellZ, facing)

	if alignment == "Horizontal" then
		if not self.EdgeFreeHorizontal[self:HorizontalEdgeIndex(edgeX, edgeZ)] then
			return false
		end
		if requiresFloorOnBothSides then
			-- Adjacent cells: north (edgeZ-1) and south (edgeZ)
			if edgeZ >= 2 and not self.FloorFilled[self.Grid:CellToIndex(edgeX, edgeZ - 1)] then
				return false
			end
			if edgeZ <= self.Grid.Rows and not self.FloorFilled[self.Grid:CellToIndex(edgeX, edgeZ)] then
				return false
			end
		end
	else -- Vertical
		if not self.EdgeFreeVertical[self:VerticalEdgeIndex(edgeX, edgeZ)] then
			return false
		end
		if requiresFloorOnBothSides then
			-- Adjacent cells: west (edgeX-1) and east (edgeX)
			if edgeX >= 2 and not self.FloorFilled[self.Grid:CellToIndex(edgeX - 1, edgeZ)] then
				return false
			end
			if edgeX <= self.Grid.Columns and not self.FloorFilled[self.Grid:CellToIndex(edgeX, edgeZ)] then
				return false
			end
		end
	end

	return true
end

function PlotState:PlaceWall(
	objectId: string,
	cellX: number,
	cellZ: number,
	_widthCells: number,
	_depthCells: number,
	facing: Facing,
	requiresFloorOnBothSides: boolean?
): boolean
	if not self:CanPlaceWall(cellX, cellZ, facing, requiresFloorOnBothSides) then
		return false
	end

	local alignment, edgeX, edgeZ = self:EdgeOfCell(cellX, cellZ, facing)
	if alignment == "Horizontal" then
		self.EdgeFreeHorizontal[self:HorizontalEdgeIndex(edgeX, edgeZ)] = false
	else
		self.EdgeFreeVertical[self:VerticalEdgeIndex(edgeX, edgeZ)] = false
	end

	self.Save.PlacedObjects[#self.Save.PlacedObjects + 1] = {
		id = objectId,
		cellX = cellX,
		cellZ = cellZ,
		facing = facing,
	}
	return true
end

function PlotState:RemoveWall(cellX: number, cellZ: number, facing: Facing)
	local alignment, edgeX, edgeZ = self:EdgeOfCell(cellX, cellZ, facing)
	if alignment == "Horizontal" then
		self.EdgeFreeHorizontal[self:HorizontalEdgeIndex(edgeX, edgeZ)] = true
	else
		self.EdgeFreeVertical[self:VerticalEdgeIndex(edgeX, edgeZ)] = true
	end

	-- Remove from Save.PlacedObjects (linear scan)
	for i = #self.Save.PlacedObjects, 1, -1 do
		local obj = self.Save.PlacedObjects[i]
		local _, placementType = resolveCatalog(obj.id)
		local objFacing = obj.facing or "North"
		if placementType == "Wall" and obj.cellX == cellX and obj.cellZ == cellZ and objFacing == facing then
			table.remove(self.Save.PlacedObjects, i)
			break
		end
	end
end
-- Hydration from save --
function PlotState:HydrateFromSave()
	-- Chunks
	for i = 1, #self.Save.UnlockedChunks do
		local savedChunk = self.Save.UnlockedChunks[i]
		self.ChunkUnlocked[self:ChunkIndex(savedChunk.cx, savedChunk.cz)] = true
	end

	-- Placed entities
	for i = 1, #self.Save.PlacedObjects do
		local savedObject = self.Save.PlacedObjects[i]
		local _, placementType, width, depth = resolveCatalog(savedObject.id)
		local facing = savedObject.facing or "North"

		if placementType == "Floor" then
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
			local indices = self.Grid:FootprintCells(savedObject.cellX, savedObject.cellZ, width, depth, facing)
			for j = 1, #indices do
				self.RoofFilled[indices[j]] = true
			end
		else -- CellObject footprint occupancy
			local cellIndices = self.Grid:FootprintCells(savedObject.cellX, savedObject.cellZ, width, depth, facing)
			for j = 1, #cellIndices do
				self.CellFree[cellIndices[j]] = false
			end
		end
	end
end

-- Floor --
function PlotState:HasFloorUnderFootprint(
	cellX: number,
	cellZ: number,
	widthCells: number,
	depthCells: number,
	facing: Facing
): boolean
	local indices = self.Grid:FootprintCells(cellX, cellZ, widthCells, depthCells, facing)
	for i = 1, #indices do
		if not self.FloorFilled[indices[i]] then
			return false
		end
	end

	return true
end

function PlotState:CanPlaceFloor(
	cellX: number,
	cellZ: number,
	widthCells: number?,
	depthCells: number?,
	facing: Facing?
): boolean
	local w = widthCells or 1
	local d = depthCells or 1
	local f = facing or "North"

	if w < 1 or d < 1 then
		return false
	end

	local minCellX: number, minCellZ: number, maxCellX: number, maxCellZ: number =
		self.Grid:FootprintBounds(cellX, cellZ, w, d, f)
	if minCellX < 1 or minCellZ < 1 or maxCellX > self.Grid.Columns or maxCellZ > self.Grid.Rows then
		return false
	end

	local minChunkX: number, minChunkZ: number, maxChunkX: number, maxChunkZ: number =
		self.Grid:FootprintChunkRange(cellX, cellZ, w, d, f, self.ChunkSizeInCells)
	for chunkZ = minChunkZ, maxChunkZ do
		for chunkX = minChunkX, maxChunkX do
			if not self:IsChunkUnlocked(chunkX, chunkZ) then
				return false
			end
		end
	end

	local indices = self.Grid:FootprintCells(cellX, cellZ, w, d, f)
	for i = 1, #indices do
		if self.FloorFilled[indices[i]] then
			return false
		end
	end

	return true
end

function PlotState:PlaceFloor(
	id: string,
	cellX: number,
	cellZ: number,
	widthCells: number?,
	depthCells: number?,
	facing: Facing?
): boolean
	local w = widthCells or 1
	local d = depthCells or 1
	local f = facing or "North"

	if not self:CanPlaceFloor(cellX, cellZ, w, d, f) then
		return false
	end

	local indices = self.Grid:FootprintCells(cellX, cellZ, w, d, f)
	for i = 1, #indices do
		self.FloorFilled[indices[i]] = true
	end

	self.Save.PlacedObjects[#self.Save.PlacedObjects + 1] = {
		id = id,
		cellX = cellX,
		cellZ = cellZ,
		facing = f,
	}
	return true
end

function PlotState:RemoveFloor(cellX: number, cellZ: number, widthCells: number?, depthCells: number?, facing: Facing?)
	local w = widthCells or 1
	local d = depthCells or 1
	local f = facing or "North"
	local indices = self.Grid:FootprintCells(cellX, cellZ, w, d, f)
	for i = 1, #indices do
		self.FloorFilled[indices[i]] = false
	end

	for i = #self.Save.PlacedObjects, 1, -1 do
		local obj = self.Save.PlacedObjects[i]
		local _, placementType, specWidth, specDepth = resolveCatalog(obj.id)
		local objFacing = obj.facing or "North"
		if
			placementType == "Floor"
			and obj.cellX == cellX
			and obj.cellZ == cellZ
			and specWidth == w
			and specDepth == d
			and objFacing == f
		then
			table.remove(self.Save.PlacedObjects, i)
			break
		end
	end
end

-- Roofs --

-- ADDED: CanPlaceRoof — allow overlap with objects, forbid overlap with another roof
function PlotState:CanPlaceRoof(
	cellX: number,
	cellZ: number,
	widthCells: number,
	depthCells: number,
	facing: Facing
): boolean
	-- same chunk gating you use elsewhere
	local minX, minZ, maxX, maxZ =
		self.Grid:FootprintChunkRange(cellX, cellZ, widthCells, depthCells, facing, self.ChunkSizeInCells)
	for cz = minZ, maxZ do
		for cx = minX, maxX do
			if not self:IsChunkUnlocked(cx, cz) then
				return false
			end
		end
	end

	-- forbid roof-on-roof stacking
	local indices = self.Grid:FootprintCells(cellX, cellZ, widthCells, depthCells, facing)
	for i = 1, #indices do
		if self.RoofFilled[indices[i]] then
			return false
		end
	end

	return true
end

-- ADDED: PlaceRoof — mark roof occupancy and persist to Save.PlacedObjects
function PlotState:PlaceRoof(
	objectId: string,
	cellX: number,
	cellZ: number,
	widthCells: number,
	depthCells: number,
	facing: Facing
): boolean
	if not self:CanPlaceRoof(cellX, cellZ, widthCells, depthCells, facing) then
		return false
	end

	-- mark roof occupancy
	local indices = self.Grid:FootprintCells(cellX, cellZ, widthCells, depthCells, facing)
	for i = 1, #indices do
		self.RoofFilled[indices[i]] = true
	end

	-- persist
	self.Save.PlacedObjects[#self.Save.PlacedObjects + 1] = {
		id = objectId,
		cellX = cellX,
		cellZ = cellZ,
		facing = facing,
	}
	return true
end

function PlotState:RemoveRoof(cellX: number, cellZ: number, width: number, depth: number, facing: Facing)
	-- ✅ normalize
	width = tonumber(width) or 1
	depth = tonumber(depth) or 1

	local indices = self.Grid:FootprintCells(cellX, cellZ, width, depth, facing)
	for i = 1, #indices do
		self.RoofFilled[indices[i]] = false
	end
	for i = #self.Save.PlacedObjects, 1, -1 do
		local o = self.Save.PlacedObjects[i]
		local _, placementType, specWidth, specDepth = resolveCatalog(o.id)
		local objFacing = o.facing or "North"
		if
			placementType == "Roof"
			and o.cellX == cellX
			and o.cellZ == cellZ
			and specWidth == width
			and specDepth == depth
			and objFacing == facing
		then
			table.remove(self.Save.PlacedObjects, i)
			break
		end
	end
end
-- Cell Objects --
function PlotState:IsCellBuildable(cellX: number, cellZ: number): boolean
	if not self.Grid:IsCellInBounds(cellX, cellZ) then
		return false
	end

	local chunkX, chunkZ = self.Grid:CellToChunk(cellX, cellZ, self.ChunkSizeInCells)

	if not self:IsChunkUnlocked(chunkX, chunkZ) then
		return false
	end

	return self.CellFree[self.Grid:CellToIndex(cellX, cellZ)] == true
end

function PlotState:CanPlace(
	anchorX: number,
	anchorZ: number,
	widthCells: number,
	depthCells: number,
	facing: Facing
): boolean
	-- Bounds + chunk gating
	local minChunkX, minChunkZ, maxChunkX, maxChunkZ =
		self.Grid:FootprintChunkRange(anchorX, anchorZ, widthCells, depthCells, facing, self.ChunkSizeInCells)

	for chunkZ = minChunkZ, maxChunkZ do
		for chunkX = minChunkX, maxChunkX do
			if not self:IsChunkUnlocked(chunkX, chunkZ) then
				return false
			end
		end
	end

	-- Cell occupancy
	local cellIndices = self.Grid:FootprintCells(anchorX, anchorZ, widthCells, depthCells, facing)
	for i = 1, #cellIndices do
		if not self.CellFree[cellIndices[i]] then
			return false
		end
	end

	return true
end

function PlotState:ReserveFootprint(
	anchorX: number,
	anchorZ: number,
	widthCells: number,
	depthCells: number,
	facing: Facing
): boolean
	if not self:CanPlace(anchorX, anchorZ, widthCells, depthCells, facing) then
		return false
	end

	local cellIndices = self.Grid:FootprintCells(anchorX, anchorZ, widthCells, depthCells, facing)
	for i = 1, #cellIndices do
		self.CellFree[cellIndices[i]] = false
	end

	return true
end

function PlotState:FreeFootprint(
	anchorX: number,
	anchorZ: number,
	widthCells: number,
	depthCells: number,
	facing: Facing
)
	local cellIndices = self.Grid:FootprintCells(anchorX, anchorZ, widthCells, depthCells, facing)
	for i = 1, #cellIndices do
		self.CellFree[cellIndices[i]] = true
	end
end

function PlotState:Place(
	objectId: string,
	anchorX: number,
	anchorZ: number,
	widthCells: number,
	depthCells: number,
	facing: Facing
): boolean
	if not self:ReserveFootprint(anchorX, anchorZ, widthCells, depthCells, facing) then
		return false
	end

	self.Save.PlacedObjects[#self.Save.PlacedObjects + 1] = {
		id = objectId,
		cellX = anchorX,
		cellZ = anchorZ,
		facing = facing,
	}
	return true
end

function PlotState:RemoveCellObject(cellX: number, cellZ: number, width: number, depth: number, facing: Facing)
	-- ✅ normalize
	width = tonumber(width) or 1
	depth = tonumber(depth) or 1

	local indices = self.Grid:FootprintCells(cellX, cellZ, width, depth, facing)
	for i = 1, #indices do
		self.CellFree[indices[i]] = true
	end
	for i = #self.Save.PlacedObjects, 1, -1 do
		local o = self.Save.PlacedObjects[i]
		local _, placementType, specWidth, specDepth = resolveCatalog(o.id)
		local objFacing = o.facing or "North"
		if
			placementType == "CellObject"
			and o.cellX == cellX
			and o.cellZ == cellZ
			and specWidth == width
			and specDepth == depth
			and objFacing == facing
		then
			table.remove(self.Save.PlacedObjects, i)
			break
		end
	end
end

function PlotState:MoveCellObject(
	itemId: string,
	fromX: number,
	fromZ: number,
	fromF: Facing,
	toX: number,
	toZ: number,
	toF: Facing
): boolean
	local spec = ItemFinder.FindItemById(itemId)
	if not spec then
		return false
	end

	local placementType = spec.PlacementType or spec.Type or "CellObject"
	if placementType ~= "CellObject" then
		return false
	end

	local w = spec.WidthCells or spec.Width or 1
	local d = spec.DepthCells or spec.Depth or 1

	-- locate exact saved entry
	local idx
	for i = #self.Save.PlacedObjects, 1, -1 do
		local o = self.Save.PlacedObjects[i]
		if o.id == itemId and o.cellX == fromX and o.cellZ == fromZ and (o.facing or "North") == fromF then
			idx = i
			break
		end
	end
	if not idx then
		return false
	end

	-- normal validation for destination
	if not self:CanPlace(toX, toZ, w, d, toF) then
		return false
	end

	-- atomic swap: free old → reserve new, rollback on failure
	self:FreeFootprint(fromX, fromZ, w, d, fromF)
	if not self:ReserveFootprint(toX, toZ, w, d, toF) then
		self:ReserveFootprint(fromX, fromZ, w, d, fromF)
		return false
	end

	-- persist
	local o = self.Save.PlacedObjects[idx]
	o.cellX, o.cellZ, o.facing = toX, toZ, toF
	return true
end

return PlotState
