--!strict
-- ReplicatedStorage/Shared/Utilities/Grid.lua
-- Grid and chunk math aligned to a rectangular Plot (BasePart).
-- 1-based indices. Rotation-safe via CFrame transforms.

export type Facing = "North" | "East" | "South" | "West"
export type OriginMode = "BottomLeft" | "TopLeft" | "BottomRight" | "TopRight" | "Center"

--[=[
	@private
	Computes the CFrame for the top surface of the plot at the specified origin corner/center.
]=]
local function ComputeOriginTopCFrame(plot: BasePart, mode: OriginMode): CFrame
	if mode == "Center" then
		return plot.CFrame * CFrame.new(0, plot.Size.Y / 2, 0)
	elseif mode == "BottomLeft" then
		return plot.CFrame * CFrame.new(-plot.Size.X / 2, plot.Size.Y / 2, -plot.Size.Z / 2)
	elseif mode == "TopLeft" then
		return plot.CFrame * CFrame.new(-plot.Size.X / 2, plot.Size.Y / 2, plot.Size.Z / 2)
	elseif mode == "BottomRight" then
		return plot.CFrame * CFrame.new(plot.Size.X / 2, plot.Size.Y / 2, -plot.Size.Z / 2)
	elseif mode == "TopRight" then
		return plot.CFrame * CFrame.new(plot.Size.X / 2, plot.Size.Y / 2, plot.Size.Z / 2)
	end
	error("Unknown origin mode: " .. tostring(mode))
end

--[=[
	@private
	Converts a world point to local X and Z offsets from the grid's origin.
]=]
local function WorldToOffsets(originTopCFrame: CFrame, worldPoint: Vector3): (number, number)
	local relativePoint = originTopCFrame:PointToObjectSpace(worldPoint)
	return relativePoint.X, relativePoint.Z
end

--[=[
	@private
	Swaps width and depth if the facing is East or West.
]=]
local function RotateFootprint(widthInCells: number, depthInCells: number, facing: Facing): (number, number)
	if facing == "East" or facing == "West" then
		return depthInCells, widthInCells
	end
	return widthInCells, depthInCells
end

local Grid = {}
Grid.__index = Grid

export type GridInstance = typeof(setmetatable(
	{} :: {
		Plot: BasePart,
		CellSize: number,
		Columns: number,
		Rows: number,
		OriginTopCFrame: CFrame,
	},
	Grid
))

--[=[
	Constructs a new Grid object.

	@param plot BasePart The part that defines the grid's area and orientation.
	@param cellSize number The size of each square cell in studs.
	@param originMode OriginMode? The corner of the plot to use as the grid's origin (1,1). Defaults to "BottomLeft".
	@return Grid The new Grid object.
]=]
function Grid.new(plot: BasePart, cellSize: number, originMode: OriginMode?): GridInstance
	assert(cellSize > 0, "cellSize must be greater than 0")
	local columns = math.floor(plot.Size.X / cellSize)
	local rows = math.floor(plot.Size.Z / cellSize)
	assert(columns >= 1 and rows >= 1, "Plot too small for given cellSize")

	local originTopCFrame = ComputeOriginTopCFrame(plot, originMode or "BottomLeft")

	local self = setmetatable({}, Grid) :: GridInstance
	self.Plot = plot
	self.CellSize = cellSize
	self.Columns = columns
	self.Rows = rows
	self.OriginTopCFrame = originTopCFrame
	return self
end

--[=[
	Returns the total number of cells in the grid.

	@return number The total cell count (columns × rows).
]=]

function Grid:CellCount(): number
	self = self :: GridInstance
	return self.Columns * self.Rows
end

--[=[
	Returns how many chunks fit across the grid in X and Z directions.

	@param chunkSizeInCells number The size of one side of a square chunk, in cells.
	@return number The number of chunk columns (X direction).
	@return number The number of chunk rows (Z direction).
]=]
function Grid:ChunkCounts(chunkSizeInCells: number): (number, number)
	self = self :: GridInstance
	assert(chunkSizeInCells >= 1, "chunkSizeInCells must be >= 1")
	local chunkColumns = math.floor(self.Columns / chunkSizeInCells)
	local chunkRows = math.floor(self.Rows / chunkSizeInCells)
	return chunkColumns, chunkRows
end

--[=[
	Checks if a cell coordinate is within the grid's boundaries.

	@param cellX number The X-coordinate (column) of the cell.
	@param cellZ number The Z-coordinate (row) of the cell.
	@return boolean True if the cell is in bounds, false otherwise.
]=]
function Grid:IsCellInBounds(cellX: number, cellZ: number): boolean
	return cellX >= 1 and cellX <= self.Columns and cellZ >= 1 and cellZ <= self.Rows
end

--[=[
	Clamps a cell coordinate to be within the grid's valid range.

	@param cellX number The X-coordinate (column) of the cell.
	@param cellZ number The Z-coordinate (row) of the cell.
	@return number The clamped cellX.
	@return number The clamped cellZ.
]=]
function Grid:ClampCell(cellX: number, cellZ: number): (number, number)
	return math.clamp(cellX, 1, self.Columns), math.clamp(cellZ, 1, self.Rows)
end

--[=[
	Converts a 2D cell coordinate into a 1D index (row-major order).

	@param cellX number The X-coordinate (column) of the cell.
	@param cellZ number The Z-coordinate (row) of the cell.
	@return number The corresponding 1-based index.
]=]
function Grid:CellToIndex(cellX: number, cellZ: number): number
	assert(self:IsCellInBounds(cellX, cellZ), "Cell out of bounds")
	return (cellZ - 1) * self.Columns + cellX
end

--[=[
	Converts a 1D index into a 2D cell coordinate.

	@param index number The 1-based index.
	@return number The cell's X-coordinate (column).
	@return number The cell's Z-coordinate (row).
]=]
function Grid:IndexToCell(index: number): (number, number)
	self = self :: GridInstance
	assert(index >= 1 and index <= self.Columns * self.Rows, "Index out of bounds")
	local zeroBased = index - 1
	local cellZ = math.floor(zeroBased / self.Columns) + 1
	local cellX = (zeroBased % self.Columns) + 1
	return cellX, cellZ
end

--[=[
	Converts a 3D world position into a grid cell.

	@param worldPoint Vector3 The position in world space.
	@return boolean, number, number Returns (true, cellX, cellZ) if the point is within the grid, otherwise (false, 0, 0).
]=]
function Grid:WorldPointToCell(worldPoint: Vector3): (boolean, number, number)
	self = self :: GridInstance
	local offsetFromLeft, offsetFromBottom = WorldToOffsets(self.OriginTopCFrame, worldPoint)

	if offsetFromLeft < 0 or offsetFromBottom < 0 then
		return false, 0, 0
	end
	if offsetFromLeft >= self.Columns * self.CellSize or offsetFromBottom >= self.Rows * self.CellSize then
		return false, 0, 0
	end

	local cellX = math.floor(offsetFromLeft / self.CellSize) + 1
	local cellZ = math.floor(offsetFromBottom / self.CellSize) + 1
	return true, cellX, cellZ
end

--[=[
	Converts a 3D world position into the nearest valid grid cell, clamping if outside the grid.

	@param worldPoint Vector3 The position in world space.
	@return number The clamped cell's X-coordinate.
	@return number The clamped cell's Z-coordinate.
]=]
function Grid:WorldPointToClampedCell(worldPoint: Vector3): (number, number)
	local offsetFromLeft, offsetFromBottom = WorldToOffsets(self.OriginTopCFrame, worldPoint)
	local cellX = math.floor(offsetFromLeft / self.CellSize) + 1
	local cellZ = math.floor(offsetFromBottom / self.CellSize) + 1
	return self:ClampCell(cellX, cellZ)
end

--[=[
	Calculates the CFrame for the center of a given cell on the plot's top surface.

	@param cellX number The X-coordinate of the cell.
	@param cellZ number The Z-coordinate of the cell.
	@param heightOffset number? An optional vertical offset from the plot's top surface.
	@return CFrame The CFrame at the center of the cell.
]=]
function Grid:CellToWorldCenterCFrame(cellX: number, cellZ: number, heightOffset: number?): CFrame
	self = self :: GridInstance
	assert(self:IsCellInBounds(cellX, cellZ), "Cell out of bounds")
	local offsetX = (cellX - 0.5) * self.CellSize
	local offsetZ = (cellZ - 0.5) * self.CellSize
	local y = heightOffset or 0
	return self.OriginTopCFrame * CFrame.new(offsetX, y, offsetZ)
end

--[=[
	Calculates the world space Vector3 position for the center of a given cell.

	@param cellX number The X-coordinate of the cell.
	@param cellZ number The Z-coordinate of the cell.
	@param heightOffset number? An optional vertical offset.
	@return Vector3 The Vector3 position at the center of the cell.
]=]
function Grid:CellToWorldCenter(cellX: number, cellZ: number, heightOffset: number?): Vector3
	return self:CellToWorldCenterCFrame(cellX, cellZ, heightOffset).Position
end

--[=[
	Calculates all cell indices covered by a rectangular footprint. Asserts if any part of the footprint is out of bounds.

	@param anchorCellX number The X-coordinate of the footprint's anchor cell.
	@param anchorCellZ number The Z-coordinate of the footprint's anchor cell.
	@param widthInCells number The width of the footprint in cells.
	@param depthInCells number The depth of the footprint in cells.
	@param facing Facing The orientation of the footprint.
	@return {number} An array of 1-based indices for all covered cells.
]=]
function Grid:FootprintCells(
	anchorCellX: number,
	anchorCellZ: number,
	widthInCells: number,
	depthInCells: number,
	facing: Facing
): { number }
	assert(widthInCells > 0 and depthInCells > 0, "Footprint size must be greater than 0")

	local rotatedWidth, rotatedDepth = RotateFootprint(widthInCells, depthInCells, facing)

	assert(
		anchorCellX >= 1
			and anchorCellZ >= 1
			and (anchorCellX + rotatedWidth - 1) <= self.Columns
			and (anchorCellZ + rotatedDepth - 1) <= self.Rows,
		"Footprint goes out of bounds"
	)

	local count = rotatedWidth * rotatedDepth
	local indices = table.create(count)
	local i = 0
	local columns = self.Columns

	for offsetZ = 0, rotatedDepth - 1 do
		local z = anchorCellZ + offsetZ
		local rowOffset = (z - 1) * columns
		for offsetX = 0, rotatedWidth - 1 do
			local x = anchorCellX + offsetX
			i += 1
			indices[i] = rowOffset + x
		end
	end

	return indices
end

--[=[
	Calculates all cell indices covered by a footprint, skipping any cells that fall outside the grid. Useful for previews.

	@param anchorCellX number The X-coordinate of the footprint's anchor cell.
	@param anchorCellZ number The Z-coordinate of the footprint's anchor cell.
	@param widthInCells number The width of the footprint.
	@param depthInCells number The depth of the footprint.
	@param facing Facing The orientation of the footprint.
	@return {number} An array of 1-based indices for the valid, covered cells.
]=]
function Grid:ClippedFootprintCells(
	anchorCellX: number,
	anchorCellZ: number,
	widthInCells: number,
	depthInCells: number,
	facing: Facing
): { number }
	assert(widthInCells > 0 and depthInCells > 0, "Footprint size must be greater than 0")

	local rotatedWidth, rotatedDepth = RotateFootprint(widthInCells, depthInCells, facing)
	local indices = {}

	for offsetZ = 0, rotatedDepth - 1 do
		local z = anchorCellZ + offsetZ
		if z >= 1 and z <= self.Rows then
			local rowOffset = (z - 1) * self.Columns
			for offsetX = 0, rotatedWidth - 1 do
				local x = anchorCellX + offsetX
				if x >= 1 and x <= self.Columns then
					indices[#indices + 1] = rowOffset + x
				end
			end
		end
	end

	return indices
end

--[=[
	Calculates the chunk coordinate that a given cell belongs to.

	@param cellX number The X-coordinate of the cell.
	@param cellZ number The Z-coordinate of the cell.
	@param chunkSizeInCells number The size of one side of a square chunk, in cells.
	@return number The chunk's X-coordinate.
	@return number The chunk's Z-coordinate.
]=]
function Grid:CellToChunk(cellX: number, cellZ: number, chunkSizeInCells: number): (number, number)
	assert(chunkSizeInCells >= 1, "chunkSizeInCells must be >= 1")
	local chunkX = math.floor((cellX - 1) / chunkSizeInCells) + 1
	local chunkZ = math.floor((cellZ - 1) / chunkSizeInCells) + 1
	return chunkX, chunkZ
end

--[=[
	Converts a 2D chunk coordinate into a 1D index.

	@param chunkX number The X-coordinate of the chunk.
	@param chunkZ number The Z-coordinate of the chunk.
	@param chunkColumns number The total number of chunks along the X-axis of the grid.
	@return number The corresponding 1-based chunk index.
]=]
function Grid:ChunkToIndex(chunkX: number, chunkZ: number, chunkColumns: number): number
	assert(chunkColumns >= 1, "chunkColumns must be >= 1")
	return (chunkZ - 1) * chunkColumns + chunkX
end

--[=[
	Converts a 1D chunk index back into a 2D chunk coordinate.

	@param index number The 1-based chunk index.
	@param chunkColumns number The total number of chunks along the X-axis.
	@return number The chunk's X-coordinate.
	@return number The chunk's Z-coordinate.
]=]
function Grid:IndexToChunk(index: number, chunkColumns: number): (number, number)
	assert(index >= 1, "index must be >= 1")
	assert(chunkColumns >= 1, "chunkColumns must be >= 1")
	local zeroBased = index - 1
	local chunkZ = math.floor(zeroBased / chunkColumns) + 1
	local chunkX = (zeroBased % chunkColumns) + 1
	return chunkX, chunkZ
end

--[=[
	Calculates the CFrame for the center of a given chunk on the plot's top surface.

	@param chunkX number The X-coordinate of the chunk.
	@param chunkZ number The Z-coordinate of the chunk.
	@param chunkSizeInCells number The size of one side of a square chunk, in cells.
	@param heightOffset number? An optional vertical offset.
	@return CFrame The CFrame at the center of the chunk.
]=]
function Grid:ChunkCenterCFrame(chunkX: number, chunkZ: number, chunkSizeInCells: number, heightOffset: number?): CFrame
	self = self :: GridInstance
	assert(chunkSizeInCells >= 1, "chunkSizeInCells must be >= 1")
	local chunkWorldSize = chunkSizeInCells * self.CellSize
	local centerX = (chunkX - 0.5) * chunkWorldSize
	local centerZ = (chunkZ - 0.5) * chunkWorldSize
	local y = heightOffset or 0
	return self.OriginTopCFrame * CFrame.new(centerX, y, centerZ)
end

--[=[
	Returns the axis-aligned cell bounds of a rotated footprint.
	Useful for quick chunk range checks without redoing rotation math outside.
]=]
function Grid:FootprintBounds(
	anchorCellX: number,
	anchorCellZ: number,
	widthInCells: number,
	depthInCells: number,
	facing: Facing
): (number, number, number, number)
	local rotatedWidth, rotatedDepth = RotateFootprint(widthInCells, depthInCells, facing)
	local minCellX = anchorCellX
	local minCellZ = anchorCellZ
	local maxCellX = anchorCellX + rotatedWidth - 1
	local maxCellZ = anchorCellZ + rotatedDepth - 1
	return minCellX, minCellZ, maxCellX, maxCellZ
end

--[=[
	Returns the inclusive chunk range covered by a rotated footprint.
]=]
function Grid:FootprintChunkRange(
	anchorCellX: number,
	anchorCellZ: number,
	widthInCells: number,
	depthInCells: number,
	facing: Facing,
	chunkSizeInCells: number
): (number, number, number, number)
	local minCellX, minCellZ, maxCellX, maxCellZ =
		self:FootprintBounds(anchorCellX, anchorCellZ, widthInCells, depthInCells, facing)

	local minChunkX, minChunkZ = self:CellToChunk(minCellX, minCellZ, chunkSizeInCells)
	local maxChunkX, maxChunkZ = self:CellToChunk(maxCellX, maxCellZ, chunkSizeInCells)
	return minChunkX, minChunkZ, maxChunkX, maxChunkZ
end

--[=[
	Returns the local offset from the anchor cell center to the center of a rotated footprint.
	Useful for placing models whose pivots sit at their geometric center instead of the anchor cell.

	@param widthInCells number The unrotated footprint width in cells.
	@param depthInCells number The unrotated footprint depth in cells.
	@param facing Facing The facing to account for when computing the rotated footprint.
	@return Vector3 The offset vector in grid-space axes (X = columns, Z = rows).
]=]
function Grid:FootprintCenterOffset(widthInCells: number, depthInCells: number, facing: Facing): Vector3
	local rotatedWidth, rotatedDepth = RotateFootprint(widthInCells, depthInCells, facing)
	local offsetX = (rotatedWidth - 1) * 0.5 * self.CellSize
	local offsetZ = (rotatedDepth - 1) * 0.5 * self.CellSize
	return Vector3.new(offsetX, 0, offsetZ)
end

--[=[
	Returns the CFrame positioned at the center of the rotated footprint for an anchor cell.

	@param anchorCellX number The X-coordinate of the anchor cell (minimum column involved).
	@param anchorCellZ number The Z-coordinate of the anchor cell (minimum row involved).
	@param widthInCells number The unrotated footprint width in cells.
	@param depthInCells number The unrotated footprint depth in cells.
	@param facing Facing The facing to account for when computing the rotated footprint.
	@return CFrame The world-space CFrame of the footprint center, aligned to the plot surface orientation.
]=]
function Grid:FootprintCenterCFrame(
	anchorCellX: number,
	anchorCellZ: number,
	widthInCells: number,
	depthInCells: number,
	facing: Facing
): CFrame
	local base: CFrame = self:CellToWorldCenterCFrame(anchorCellX, anchorCellZ)
	local offset = self:FootprintCenterOffset(widthInCells, depthInCells, facing)
	return base * CFrame.new(offset)
end

function Grid:CellToWorldEdgeCenterCFrame(cellX: number, cellZ: number, facing: Facing, heightOffset: number?): CFrame
	self = self :: GridInstance
	local half = self.CellSize * 0.5
	local y = heightOffset or 0
	local offsetX = (cellX - 0.5) * self.CellSize
	local offsetZ = (cellZ - 0.5) * self.CellSize

	if facing == "North" then
		-- top edge of the cell
		return self.OriginTopCFrame * CFrame.new(offsetX, y, offsetZ - half)
	elseif facing == "South" then
		-- bottom edge
		return self.OriginTopCFrame * CFrame.new(offsetX, y, offsetZ + half) * CFrame.Angles(0, math.rad(180), 0)
	elseif facing == "West" then
		-- left edge
		return self.OriginTopCFrame * CFrame.new(offsetX - half, y, offsetZ) * CFrame.Angles(0, math.rad(270), 0)
	else -- "East"
		-- right edge
		return self.OriginTopCFrame * CFrame.new(offsetX + half, y, offsetZ) * CFrame.Angles(0, math.rad(90), 0)
	end
end

return Grid
