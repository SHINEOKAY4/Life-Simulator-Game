--!strict
-- ServerScriptService/Server/Classes/PlotState.luau

local PlotState = {}
PlotState.__index = PlotState

function PlotState.new(grid, chunkSizeInCells, save)
	-- NOTE: This assumes a `grid:ChunkCounts()` method exists that returns the number of chunk columns and rows.
	local chunkColumns: number, chunkRows: number = grid:ChunkCounts(chunkSizeInCells)

	local self = setmetatable({}, PlotState)
	self.Grid = grid
	self.ChunkSizeInCells = chunkSizeInCells
	self.ChunkColumns = chunkColumns
	self.ChunkRows = chunkRows
	-- runtime state (does not persist) simply for faster lookups to avoid table scans
	self.ChunkUnlocked = table.create(chunkColumns * chunkRows, false)
	self.CellFree = table.create(grid:CellCount(), true)

	self.Save = save
	return self
end

function PlotState:ChunkIndex(chunkX: number, chunkZ: number): number
	return self.Grid:ChunkToIndex(chunkX, chunkZ, self.ChunkColumns)
end

function PlotState:IsChunkUnlocked(chunkX: number, chunkZ: number): boolean
	return self.ChunkUnlocked[self:ChunkIndex(chunkX, chunkZ)] == true
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

function PlotState:HydrateFromSave()
	-- Hydrate saved unlocked chunks into runtime state
	for i = 1, #self.Save.UnlockedChunks do
		local chunk = self.Save.UnlockedChunks[i]
		self.ChunkUnlocked[self:ChunkIndex(chunk.cx, chunk.cz)] = true
	end
	-- Hydrate saved placed objects into runtime state
	for i = 1, #self.Save.PlacedObjects do
		local obj = self.Save.PlacedObjects[i]
		local indices = self.Grid:FootprintCells(obj.cellX, obj.cellZ, obj.width, obj.depth, obj.facing)

		for j = 1, #indices do
			self.CellFree[indices[j]] = false
		end
	end
end

function PlotState:IsChunkInBounds(chunkX: number, chunkZ: number): boolean
	return chunkX >= 1 and chunkX <= self.ChunkColumns and chunkZ >= 1 and chunkZ <= self.ChunkRows
end

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
	facing: any
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
	local indices = self.Grid:FootprintCells(anchorX, anchorZ, widthCells, depthCells, facing)
	for i = 1, #indices do
		if not self.CellFree[indices[i]] then
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
	facing
): boolean
	if not self:CanPlace(anchorX, anchorZ, widthCells, depthCells, facing) then
		return false
	end

	local indices = self.Grid:FootprintCells(anchorX, anchorZ, widthCells, depthCells, facing)

	for i = 1, #indices do
		self.CellFree[indices[i]] = false
	end

	return true
end

function PlotState:FreeFootprint(anchorX: number, anchorZ: number, widthCells: number, depthCells: number, facing)
	local indices = self.Grid:FootprintCells(anchorX, anchorZ, widthCells, depthCells, facing)
	for i = 1, #indices do
		self.CellFree[indices[i]] = true
	end
end

function PlotState:Place(
	objectId: string,
	anchorX: number,
	anchorZ: number,
	widthCells: number,
	depthCells: number,
	facing
): boolean
	if not self:ReserveFootprint(anchorX, anchorZ, widthCells, depthCells, facing) then
		return false
	end

	self.Save.PlacedObjects[#self.Save.PlacedObjects + 1] = {
		id = objectId,
		cellX = anchorX,
		cellZ = anchorZ,
		width = widthCells,
		depth = depthCells,
		facing = facing,
	}
	return true
end

return PlotState
