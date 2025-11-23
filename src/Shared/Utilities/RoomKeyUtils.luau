--!strict
-- ReplicatedStorage/Shared/Utilities/RoomKeyUtils.luau
-- Normalizes the server/client representation of tenant room keys.

local RoomKeyUtils = {}

local ROOM_KEY_PATTERN = "^(%-?%d+):(%-?%d+):(%-?%d+)$"

local function round(value: number?): number
	if typeof(value) == "number" then
		return math.floor(value + 0.5)
	end
	return 0
end

function RoomKeyUtils.Format(level: number?, minCellX: number?, minCellZ: number?): string
	local resolvedLevel = round(level)
	local resolvedX = round(minCellX)
	local resolvedZ = round(minCellZ)
	return ("%d:%d:%d"):format(resolvedLevel, resolvedX, resolvedZ)
end

function RoomKeyUtils.Parse(roomKey: string?): (number?, number?, number?)
	if type(roomKey) ~= "string" or roomKey == "" then
		return nil, nil, nil
	end
	local levelStr, xStr, zStr = string.match(roomKey, ROOM_KEY_PATTERN)
	if not levelStr then
		return nil, nil, nil
	end
	return tonumber(levelStr), tonumber(xStr), tonumber(zStr)
end

function RoomKeyUtils.Normalize(roomKey: string?): string?
	local level, minX, minZ = RoomKeyUtils.Parse(roomKey)
	if not level or not minX or not minZ then
		return nil
	end
	return RoomKeyUtils.Format(level, minX, minZ)
end

function RoomKeyUtils.IsValid(roomKey: string?): boolean
	local level, minX, minZ = RoomKeyUtils.Parse(roomKey)
	return typeof(level) == "number" and typeof(minX) == "number" and typeof(minZ) == "number"
end

return RoomKeyUtils
