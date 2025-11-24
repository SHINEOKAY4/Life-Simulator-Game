--!strict
-- Unified room system - single source of truth for all room logic

local RoomCore = {}

-- Constants
RoomCore.MIN_TENANT_ROOM_DIM = 5
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
function RoomCore.MakeRoomKey(level: number, minX: number, minZ: number): string
	return string.format("%d:%d:%d", level, minX, minZ)
end

function RoomCore.ParseRoomKey(roomKey: string?): (number?, number?, number?)
	if type(roomKey) ~= "string" or roomKey == "" then
		return nil, nil, nil
	end
	local pattern = "^(%-?%d+):(%-?%d+):(%-?%d+)$"
	local levelStr, xStr, zStr = string.match(roomKey, pattern)
	if not levelStr then
		return nil, nil, nil
	end
	return tonumber(levelStr), tonumber(xStr), tonumber(zStr)
end

function RoomCore.NormalizeRoomKey(roomKey: string?): string?
	local level, minX, minZ = RoomCore.ParseRoomKey(roomKey)
	if not level or not minX or not minZ then
		return nil
	end
	return RoomCore.MakeRoomKey(level, minX, minZ)
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

	if limitingDim < RoomCore.MIN_TENANT_ROOM_DIM then
		return 0
	end

	local segments = math.floor(limitingDim / RoomCore.MIN_TENANT_ROOM_DIM)
	return math.max(0, segments * 2)
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

	return false, "NotTenantReady"
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
