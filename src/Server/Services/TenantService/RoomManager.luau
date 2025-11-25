--!strict
-- Server/Services/TenantService/RoomManager.luau
-- Manages room assignment, capacity tracking, and diagnostics for tenants

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RoomCore = require(ReplicatedStorage.Shared.Utilities.RoomCore)
local DataNormalization = require(script.Parent.DataNormalization)

type TenantLease = DataNormalization.TenantLease
type RoomAssignmentMap = DataNormalization.RoomAssignmentMap

export type TenantRoomDiagnostic = {
	Room: any?,
	Ready: boolean,
	Reason: string?,
}

export type TenantRoomRosterEntry = {
	RoomKey: string,
	Label: string,
	Level: number,
	Capacity: number,
	Occupied: number,
	MinCellX: number,
	MinCellZ: number,
	SizeX: number,
	SizeZ: number,
}

local RoomManager = {}

local function clampRoomUsage(used: number?, capacity: number): number
	local value = if typeof(used) == "number" then used else 0
	return math.clamp(math.floor(value + 0.5), 0, capacity)
end

local function formatRoomLabel(roomKey: string, roomData: any): string
	local customName = roomData and roomData.Name
	if typeof(customName) == "string" and customName ~= "" then
		return customName
	end
	local level = roomData and (roomData.Level or roomData.Floor or 0)
	return string.format("Level %d • %s", level or 0, roomKey)
end

function RoomManager.CollectRooms(plotState: any): ({ [string]: any }, { [string]: TenantRoomDiagnostic })
	if typeof(plotState) ~= "table" or typeof(plotState.GetRoomsForLevel) ~= "function" then
		return {}, {}
	end

	local roomsByKey: { [string]: any } = {}
	local diagnostics: { [string]: TenantRoomDiagnostic } = {}
	local startLevel = plotState.DefaultLevel or 0
	local endLevel = plotState.MaxFloorLevel or startLevel

	for level = startLevel, endLevel do
		local success, levelRooms = pcall(function()
			return plotState:GetRoomsForLevel(level)
		end)

		if success and typeof(levelRooms) == "table" then
			for _, room in ipairs(levelRooms) do
				-- Room should always have RoomKey set during creation
				-- Fallback uses room.Id for uniqueness (not coordinates)
				local roomKey = room.RoomKey or (room.Id and RoomCore.MakeRoomKey(level, room.Id))
				if not roomKey then
					continue
				end
				local ready, reason = RoomCore.EvaluateTenantReadiness(room)
				diagnostics[roomKey] = {
					Room = room,
					Ready = ready,
					Reason = reason,
				}
				if ready then
					roomsByKey[roomKey] = room
				end
			end
		end
	end

	return roomsByKey, diagnostics
end

function RoomManager.ReconcileAssignments(
	leases: { [string]: TenantLease },
	roomMap: { [string]: any }?,
	assignments: RoomAssignmentMap,
	onEvict: (tenantId: string) -> ()
): { [string]: boolean }
	local changedTenants: { [string]: boolean } = {}

	local function setLeaseRoom(tenantId: string, lease: TenantLease, roomKey: string?)
		if lease.RoomKey ~= roomKey then
			lease.RoomKey = roomKey
			changedTenants[tenantId] = true
		end
	end

	-- Clear all assignments
	for key in pairs(assignments) do
		assignments[key] = nil :: any
	end

	if not roomMap or not next(roomMap) then
		-- Evict all tenants when no rooms available
		for tenantId in pairs(leases) do
			onEvict(tenantId)
		end
		return changedTenants
	end

	-- Build occupancy map
	local occupancy: RoomAssignmentMap = {}
	for roomKey, room in pairs(roomMap) do
		local capacity = room.TenantCapacity or 0
		if capacity > 0 then
			occupancy[roomKey] = 0
		end
	end

	-- Collect tenants needing reassignment
	local reassignQueue: { string } = {}
	for tenantId, lease in pairs(leases) do
		local roomKey = lease.RoomKey
		if roomKey and occupancy[roomKey] ~= nil then
			local capacity = roomMap[roomKey].TenantCapacity or 0
			local used = occupancy[roomKey] or 0
			if used < capacity then
				occupancy[roomKey] = used + 1
			else
				setLeaseRoom(tenantId, lease, nil)
				reassignQueue[#reassignQueue + 1] = tenantId
			end
		else
			setLeaseRoom(tenantId, lease, nil)
			reassignQueue[#reassignQueue + 1] = tenantId
		end
	end

	-- Try to reassign displaced tenants
	for _, tenantId in ipairs(reassignQueue) do
		local lease = leases[tenantId]
		if lease then
			local assigned = false
			for roomKey, room in pairs(roomMap) do
				local capacity = room.TenantCapacity or 0
				local used = occupancy[roomKey] or 0
				if capacity > 0 and used < capacity then
					setLeaseRoom(tenantId, lease, roomKey)
					occupancy[roomKey] = used + 1
					assigned = true
					break
				end
			end

			if not assigned then
				onEvict(tenantId)
			end
		end
	end

	-- Update assignments from occupancy
	for roomKey, used in pairs(occupancy) do
		if used > 0 then
			assignments[roomKey] = used
		end
	end

	return changedTenants
end

function RoomManager.FindAvailableRoom(roomMap: { [string]: any }?, assignments: RoomAssignmentMap): string?
	if not roomMap or not next(roomMap) then
		return nil
	end

	for roomKey, room in pairs(roomMap) do
		local capacity = math.max(room.TenantCapacity or 0, 0)
		if capacity > 0 then
			local used = clampRoomUsage(assignments[roomKey], capacity)
			if used < capacity then
				return roomKey
			end
		end
	end

	return nil
end

function RoomManager.CountAvailability(roomMap: { [string]: any }?, assignments: RoomAssignmentMap): (number, number)
	if not roomMap or not next(roomMap) then
		return 0, 0
	end

	local total = 0
	local available = 0

	for roomKey, room in pairs(roomMap) do
		local capacity = math.max(room.TenantCapacity or 0, 0)
		if capacity > 0 then
			total += capacity
			local used = clampRoomUsage(assignments[roomKey], capacity)
			available += capacity - used
		end
	end

	return total, math.max(available, 0)
end

function RoomManager.BuildRoster(roomMap: { [string]: any }, assignments: RoomAssignmentMap): { TenantRoomRosterEntry }
	local roster: { TenantRoomRosterEntry } = {}

	for roomKey, room in pairs(roomMap) do
		local capacity = math.max(room.TenantCapacity or 0, 0)
		if capacity > 0 then
			local occupied = clampRoomUsage(assignments[roomKey], capacity)
			local minCellX = room.MinCellX or room.MinX or 0
			local minCellZ = room.MinCellZ or room.MinZ or 0
			local maxCellX = room.MaxCellX or room.MaxX or minCellX
			local maxCellZ = room.MaxCellZ or room.MaxZ or minCellZ
			local sizeX = math.max((maxCellX - minCellX) + 1, 0)
			local sizeZ = math.max((maxCellZ - minCellZ) + 1, 0)

			roster[#roster + 1] = {
				RoomKey = roomKey,
				Label = formatRoomLabel(roomKey, room),
				Level = room.Level or room.Floor or 0,
				Capacity = capacity,
				Occupied = occupied,
				MinCellX = minCellX,
				MinCellZ = minCellZ,
				SizeX = sizeX,
				SizeZ = sizeZ,
			}
		end
	end

	table.sort(roster, function(a, b)
		if a.Level == b.Level then
			return a.RoomKey < b.RoomKey
		end
		return a.Level < b.Level
	end)

	return roster
end

function RoomManager.BuildDiagnostics(
	diagnostics: { [string]: TenantRoomDiagnostic },
	assignments: RoomAssignmentMap,
	defaultLevel: number
): { [number]: { [string]: any } }
	local payload: { [number]: { [string]: any } } = {}

	for roomKey, info in pairs(diagnostics) do
		local roomData = info and info.Room or nil
		local minCellX = 0
		local minCellZ = 0
		local sizeX = 0
		local sizeZ = 0
		local level = defaultLevel
		local cellCount = 0
		local hasBed = false
		local isEnclosed = false
		local capacity = 0
		local cellIndices: { number }? = nil

		if roomData then
			minCellX = roomData.MinCellX or roomData.MinX or 0
			minCellZ = roomData.MinCellZ or roomData.MinZ or 0
			sizeX = roomData.WidthCells or ((roomData.MaxCellX or roomData.MaxX or minCellX) - minCellX + 1)
			sizeZ = roomData.DepthCells or ((roomData.MaxCellZ or roomData.MaxZ or minCellZ) - minCellZ + 1)
			level = roomData.Level or roomData.Floor or defaultLevel
			cellCount = roomData.CellCount or (sizeX * sizeZ)
			hasBed = roomData.HasBed == true
			isEnclosed = roomData.IsEnclosed == true
			capacity = math.max(roomData.TenantCapacity or 0, 0)
			-- Only include cell indices for tenant-ready rooms (bandwidth optimization)
			if info and info.Ready then
				if roomData.Cells and typeof(roomData.Cells) == "table" then
					cellIndices = roomData.Cells
				elseif roomData.CellIndices and typeof(roomData.CellIndices) == "table" then
					cellIndices = roomData.CellIndices
				end
			end
		end

		sizeX = math.max(sizeX, 0)
		sizeZ = math.max(sizeZ, 0)
		cellCount = math.max(cellCount, 0)
		local occupied = clampRoomUsage(assignments[roomKey], capacity)

		local entry: { [string]: any } = {
			RoomKey = roomKey,
			Level = level,
			MinCellX = minCellX,
			MinCellZ = minCellZ,
			SizeX = sizeX,
			SizeZ = sizeZ,
			CellCount = cellCount,
			CellIndices = cellIndices or {}, -- Always send array, empty if not ready (packet expects array)
			Ready = info and info.Ready == true,
			Reason = info and info.Reason or "",
			HasBed = hasBed,
			IsEnclosed = isEnclosed,
			Capacity = capacity,
			Occupied = occupied,
		}
		payload[#payload + 1] = entry
	end

	table.sort(payload, function(a, b)
		if a.Level == b.Level then
			return a.RoomKey < b.RoomKey
		end
		return a.Level < b.Level
	end)

	return payload
end

function RoomManager.GetFirstIssueReason(diagnostics: { [string]: TenantRoomDiagnostic }?): string?
	if not diagnostics then
		return nil
	end
	for _, info in pairs(diagnostics) do
		if info and not info.Ready then
			return RoomCore.GetReasonMessage(info.Reason)
		end
	end
	return nil
end

function RoomManager.NormalizeRoomKey(roomKey: string?): string?
	return RoomCore.NormalizeRoomKey(roomKey)
end

function RoomManager.ReleaseRoomAssignment(lease: TenantLease?, assignments: RoomAssignmentMap)
	if not lease or not lease.RoomKey then
		return
	end

	local roomKey = lease.RoomKey
	local current = assignments[roomKey]
	if typeof(current) == "number" then
		local nextValue = current - 1
		if nextValue > 0 then
			assignments[roomKey] = nextValue
		else
			assignments[roomKey] = nil
		end
	end
	lease.RoomKey = nil
end

return RoomManager
