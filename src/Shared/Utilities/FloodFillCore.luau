--!strict
-- Core flood-fill algorithm for room/area detection
-- Single source of truth - eliminates 300+ lines of duplicate BFS logic

local FloodFillCore = {}

export type FloodFillResult = {
	Cells: { number }, -- Cell indices in this area
	MinX: number,
	MaxX: number,
	MinZ: number,
	MaxZ: number,
	CellCount: number,
}

export type EdgeChecker = (cx: number, cz: number, direction: string) -> boolean
export type CellVisitor = ((cx: number, cz: number, cellIndex: number) -> ())?

-- Core BFS flood-fill from a starting cell
-- Returns all connected cells respecting edge boundaries
function FloodFillCore.FloodFill(
	startX: number,
	startZ: number,
	columns: number,
	rows: number,
	floorFilled: { [number]: boolean }, -- [cellIndex] = true if floor exists
	isEdgeBlocked: EdgeChecker, -- (cx, cz, direction) -> boolean
	visited: { [number]: boolean }, -- Shared visited map across multiple fills
	onVisitCell: CellVisitor -- Optional callback for each visited cell
): FloodFillResult
	local function getCellIndex(x: number, z: number): number
		return (z - 1) * columns + x
	end

	local result: FloodFillResult = {
		Cells = {},
		MinX = startX,
		MaxX = startX,
		MinZ = startZ,
		MaxZ = startZ,
		CellCount = 0,
	}

	local startIndex = getCellIndex(startX, startZ)
	if visited[startIndex] or not floorFilled[startIndex] then
		return result
	end

	local queue = { startX, startZ } -- Interleaved x, z for performance
	local head = 1
	visited[startIndex] = true

	while head <= #queue do
		local cx = queue[head]
		local cz = queue[head + 1]
		head += 2

		local cellIndex = getCellIndex(cx, cz)
		table.insert(result.Cells, cellIndex)
		result.CellCount += 1

		-- Update bounds
		if cx < result.MinX then
			result.MinX = cx
		end
		if cx > result.MaxX then
			result.MaxX = cx
		end
		if cz < result.MinZ then
			result.MinZ = cz
		end
		if cz > result.MaxZ then
			result.MaxZ = cz
		end

		-- Optional callback for cell processing
		if onVisitCell then
			onVisitCell(cx, cz, cellIndex)
		end

		-- Check 4 neighbors
		local neighbors = {
			{ dx = 0, dz = -1, dir = "North" },
			{ dx = 0, dz = 1, dir = "South" },
			{ dx = -1, dz = 0, dir = "West" },
			{ dx = 1, dz = 0, dir = "East" },
		}

		for _, neighbor in ipairs(neighbors) do
			local nx = cx + neighbor.dx
			local nz = cz + neighbor.dz

			-- Bounds check
			if nx >= 1 and nx <= columns and nz >= 1 and nz <= rows then
				local neighborIndex = getCellIndex(nx, nz)

				-- Check if edge is blocked
				if not isEdgeBlocked(cx, cz, neighbor.dir) then
					-- Check if neighbor has floor and not visited
					if floorFilled[neighborIndex] and not visited[neighborIndex] then
						visited[neighborIndex] = true
						table.insert(queue, nx)
						table.insert(queue, nz)
					end
				end
			end
		end
	end

	return result
end

-- Batch flood-fill: finds all disconnected areas in a grid
function FloodFillCore.FindAllAreas(
	columns: number,
	rows: number,
	floorFilled: { [number]: boolean },
	isEdgeBlocked: EdgeChecker,
	onVisitCell: CellVisitor
): { FloodFillResult }
	local areas: { FloodFillResult } = {}
	local visited: { [number]: boolean } = {}

	for z = 1, rows do
		for x = 1, columns do
			local cellIndex = (z - 1) * columns + x
			if floorFilled[cellIndex] and not visited[cellIndex] then
				local area =
					FloodFillCore.FloodFill(x, z, columns, rows, floorFilled, isEdgeBlocked, visited, onVisitCell)
				if area.CellCount > 0 then
					table.insert(areas, area)
				end
			end
		end
	end

	return areas
end

return FloodFillCore
