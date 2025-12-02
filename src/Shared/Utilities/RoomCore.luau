--!strict
-- Unified room system - single source of truth for all room logic
--
-- ROOM KEY FORMAT: "level:roomId" (e.g., "0:1", "0:2", "1:1")
-- - Uses room ID instead of coordinates to guarantee uniqueness
-- - Previously used "level:minX:minZ" which caused duplicate keys when rooms shared minimum coordinates
-- - Old keys in saved data are auto-migrated by TenantService.RoomManager.ReconcileAssignments

local RoomCore = {}

-- Constants
RoomCore.MIN_TENANT_ROOM_DIM = 4
RoomCore.MIN_TENANT_ROOM_CELLS = RoomCore.MIN_TENANT_ROOM_DIM * RoomCore.MIN_TENANT_ROOM_DIM

export type MinimalRoom = {
	Id: number,
	Level: number,
	MinX: number,
	MaxX: number,
	MinZ: number,
	MaxZ: number,
	CellCount: number,
	CellIndices: { number },
}

export type TenantRoom = {
	Id: number,
	Level: number,
	MinX: number,
	MaxX: number,
	MinZ: number,
	MaxZ: number,
	CellCount: number,
	CellIndices: { number },
	WidthCells: number,
	DepthCells: number,
	RoomKey: string,
	IsEnclosed: boolean,
	HasBed: boolean,
	BedCount: number,
	IsTenantRoom: boolean,
	TenantCapacity: number,
}

-- Room key utilities
-- Format: "level:roomId" for guaranteed uniqueness
function RoomCore.MakeRoomKey(level: number, roomId: number): string
	return string.format("%d:%d", level, roomId)
end

-- Parse room key in format "level:roomId"
-- Returns (level, roomId)
function RoomCore.ParseRoomKey(roomKey: string?): (number?, number?)
	if type(roomKey) ~= "string" or roomKey == "" then
		return nil, nil
	end
	local pattern = "^(%-?%d+):(%-?%d+)$"
	local levelStr, idStr = string.match(roomKey, pattern)
	if not levelStr then
		return nil, nil
	end
	return tonumber(levelStr), tonumber(idStr)
end

function RoomCore.NormalizeRoomKey(roomKey: string?): string?
	local level, roomId = RoomCore.ParseRoomKey(roomKey)
	if not level or not roomId then
		return nil
	end
	return RoomCore.MakeRoomKey(level, roomId)
end

-- Room validation
function RoomCore.MeetsMinimumSize(room: MinimalRoom): boolean
	local width = room.MaxX - room.MinX + 1
	local depth = room.MaxZ - room.MinZ + 1
	return width >= RoomCore.MIN_TENANT_ROOM_DIM
		and depth >= RoomCore.MIN_TENANT_ROOM_DIM
		and room.CellCount >= RoomCore.MIN_TENANT_ROOM_CELLS
end

function RoomCore.CalculateTenantCapacity(room: MinimalRoom): number
	local width = room.MaxX - room.MinX + 1
	local depth = room.MaxZ - room.MinZ + 1
	local limitingDim = math.min(width, depth)

	-- Must meet minimum room size
	if limitingDim < RoomCore.MIN_TENANT_ROOM_DIM then
		return 0
	end

	-- Scale capacity based on total room area
	-- 32 cells per tenant (8x8 room = 64 cells = 2 tenants)
	local cellCount = room.CellCount
	local capacity = math.floor(cellCount / 32)
	return math.max(1, capacity) -- At least 1 tenant if room meets minimum size
end

function RoomCore.EvaluateTenantReadiness(room: TenantRoom): (boolean, string?)
	if not room then
		return false, "NotTenantReady"
	end

	-- Fast path: already validated
	if room.IsTenantRoom and (room.TenantCapacity or 0) > 0 then
		return true, nil
	end

	if not room.HasBed then
		return false, "MissingBed"
	end

	if not room.IsEnclosed then
		return false, "NotEnclosed"
	end

	if not RoomCore.MeetsMinimumSize(room) then
		return false, "TooSmall"
	end

	-- All checks passed
	return true, nil
end

-- Reason messages
local REASON_MESSAGES = {
	MissingBed = "Place a bed inside that room before inviting tenants.",
	NotEnclosed = "Fully enclose the room with walls and at least one door.",
	TooSmall = string.format(
		"Tenant rooms must be at least %dx%d cells.",
		RoomCore.MIN_TENANT_ROOM_DIM,
		RoomCore.MIN_TENANT_ROOM_DIM
	),
	NoCapacity = "Add another tenant-ready room or free one up before inviting tenants.",
	NotTenantReady = "That room is not tenant-ready yet.",
}

function RoomCore.GetReasonMessage(reason: string?): string
	if not reason then
		return REASON_MESSAGES.NotTenantReady
	end
	return REASON_MESSAGES[reason] or REASON_MESSAGES.NotTenantReady
end

return RoomCore
