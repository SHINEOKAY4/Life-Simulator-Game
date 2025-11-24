--!strict
-- Shared room detection - single source of truth for flood-fill algorithm

export type Room = {
	Id: number,
	Level: number,
	CellCount: number,
	MinX: number,
	MaxX: number,
	MinZ: number,
	MaxZ: number,
	CellIndices: { number },
}

local RoomDetection = {}

local function computeCellIndex(columns: number, x: number, z: number): number
	return (z - 1) * columns + x
end

local function indexToCoords(index: number, columns: number): (number, number)
	local z = math.floor((index - 1) / columns) + 1
	local x = ((index - 1) % columns) + 1
	return x, z
end

local function makeEdgeKey(x: number, z: number, direction: string): string
	return ("%d_%d_%s"):format(x, z, direction)
end

-- Core flood-fill algorithm
function RoomDetection.DetectRooms(
	level: number,
	columns: number,
	rows: number,
	floorCells: { number }, -- Array of cell indices with floors
	blockedEdges: { [string]: boolean } -- Edge keys that block movement
): ({ [number]: number }, { Room })
	local cellAssignments: { [number]: number } = {} -- [cellIndex] = roomId
	local rooms: { Room } = {}
	local visited: { [number]: boolean } = {}

	for _, startIndex in ipairs(floorCells) do
		if visited[startIndex] then
			continue
		end

		local roomId = #rooms + 1
		local room: Room = {
			Id = roomId,
			Level = level,
			CellCount = 0,
			MinX = math.huge,
			MaxX = -math.huge,
			MinZ = math.huge,
			MaxZ = -math.huge,
			CellIndices = {},
		}

		local queue = { startIndex }
		local queueHead = 1
		visited[startIndex] = true
		cellAssignments[startIndex] = roomId

		while queueHead <= #queue do
			local currentIndex = queue[queueHead]
			queueHead += 1

			local x, z = indexToCoords(currentIndex, columns)
			room.CellCount += 1
			table.insert(room.CellIndices, currentIndex)
			room.MinX = math.min(room.MinX, x)
			room.MaxX = math.max(room.MaxX, x)
			room.MinZ = math.min(room.MinZ, z)
			room.MaxZ = math.max(room.MaxZ, z)

			-- Check 4 neighbors (North, South, East, West)
			local neighbors = {
				{ dx = 0, dz = -1, edge = "North" },
				{ dx = 0, dz = 1, edge = "South" },
				{ dx = 1, dz = 0, edge = "East" },
				{ dx = -1, dz = 0, edge = "West" },
			}

			for _, neighbor in ipairs(neighbors) do
				local nx = x + neighbor.dx
				local nz = z + neighbor.dz

				if nx >= 1 and nx <= columns and nz >= 1 and nz <= rows then
					local edgeKey = makeEdgeKey(x, z, neighbor.edge)
					if not blockedEdges[edgeKey] then
						local neighborIndex = computeCellIndex(columns, nx, nz)
						if not visited[neighborIndex] then
							-- Check if neighbor has floor
							local hasFloor = false
							for _, floorIndex in ipairs(floorCells) do
								if floorIndex == neighborIndex then
									hasFloor = true
									break
								end
							end

							if hasFloor then
								visited[neighborIndex] = true
								cellAssignments[neighborIndex] = roomId
								table.insert(queue, neighborIndex)
							end
						end
					end
				end
			end
		end

		table.insert(rooms, room)
	end

	return cellAssignments, rooms
end

function RoomDetection.GetRoomAtCell(
	cellX: number,
	cellZ: number,
	columns: number,
	cellAssignments: { [number]: number }
): number?
	local index = computeCellIndex(columns, cellX, cellZ)
	return cellAssignments[index]
end

function RoomDetection.MakeRoomKey(level: number, minX: number, minZ: number): string
	return ("%d:%d:%d"):format(level or 0, minX or 0, minZ or 0)
end

-- Validate if room is tenant-ready
function RoomDetection.EvaluateTenantReadiness(room: Room): (boolean, string?)
	if not room then
		return false, "NotTenantReady"
	end

	local capacity = math.max(room.TenantCapacity or 0, 0)
	if room.IsTenantRoom and capacity > 0 then
		return true, nil
	end

	if not room.HasBed then
		return false, "MissingBed"
	end
	if not room.IsEnclosed then
		return false, "NotEnclosed"
	end

	local widthCells = room.MaxX - room.MinX + 1
	local depthCells = room.MaxZ - room.MinZ + 1
	if
		widthCells < MIN_TENANT_ROOM_DIM
		or depthCells < MIN_TENANT_ROOM_DIM
		or room.CellCount < MIN_TENANT_ROOM_CELLS
	then
		return false, "TooSmall"
	end

	return false, "NotTenantReady"
end

-- Calculate tenant capacity for a room
function RoomDetection.CalculateRoomCapacity(room: Room): number
	local limitingDim = math.min(room.WidthCells or 0, room.DepthCells or 0)
	if limitingDim < MIN_TENANT_ROOM_DIM then
		return 0
	end
	local segments = math.floor(limitingDim / MIN_TENANT_ROOM_DIM)
	if segments <= 0 then
		return 0
	end
	return segments * 2
end

-- Check if room meets minimum size requirements
function RoomDetection.MeetsMinimumSize(room: Room): boolean
	local width = room.MaxX - room.MinX + 1
	local depth = room.MaxZ - room.MinZ + 1
	return width >= MIN_TENANT_ROOM_DIM and depth >= MIN_TENANT_ROOM_DIM and room.CellCount >= MIN_TENANT_ROOM_CELLS
end

return RoomDetection
