--!strict
-- Room query - uses server authority with efficient hash lookup
-- ⚠️ This module ONLY queries server data - never calculates rooms
-- Room detection logic lives in: src/Server/Classes/PlotState/Rooms.luau
-- Uses O(1) cell index hash lookup - no bounding box approximations

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TenantPackets = require(ReplicatedStorage.Network.TenantPackets)

export type ServerRoom = {
	RoomKey: string,
	Level: number,
	MinCellX: number,
	MinCellZ: number,
	SizeX: number,
	SizeZ: number,
	CellCount: number,
	CellIndices: { number }?,
	Ready: boolean,
	Reason: string?,
	HasBed: boolean?,
	IsEnclosed: boolean?,
	Capacity: number?,
	Occupied: number?,
}

local RoomQuery = {}
local cachedRooms: { ServerRoom }? = nil
local cacheTime = 0
local CACHE_DURATION = 10
local cellLookupCache: { [number]: { [number]: boolean } } = {} -- [roomIndex][cellIndex] = true

local function computeCellIndex(columns: number, cellX: number, cellZ: number): number
	return (cellZ - 1) * columns + cellX
end

function RoomQuery.GetRoomsFromServer(forceRefresh: boolean?): { ServerRoom }?
	local now = os.clock()
	if not forceRefresh and cachedRooms and (now - cacheTime) < CACHE_DURATION then
		return cachedRooms
	end

	local ok, response = pcall(function()
		return TenantPackets.RequestRoomDiagnostics:Fire({})
	end)

	if ok and typeof(response) == "table" and typeof(response.Rooms) == "table" then
		cachedRooms = response.Rooms
		cacheTime = now

		-- Build hash set lookup cache for O(1) cell membership checks
		table.clear(cellLookupCache)
		for i, room in ipairs(response.Rooms) do
			if room.CellIndices and #room.CellIndices > 0 then
				local lookup = {}
				for _, cellIndex in ipairs(room.CellIndices) do
					lookup[cellIndex] = true
				end
				cellLookupCache[i] = lookup
			end
		end
		return response.Rooms
	end

	return nil
end

function RoomQuery.FindRoomAtPosition(level: number, cellX: number, cellZ: number, forceRefresh: boolean?): ServerRoom?
	local rooms = RoomQuery.GetRoomsFromServer(forceRefresh)
	if not rooms then
		return nil
	end

	-- Get grid columns from PlotStateStore
	local Players = game:GetService("Players")
	local LocalPlayer = Players.LocalPlayer
	if not LocalPlayer then
		return nil
	end

	local PlayerScripts = LocalPlayer:FindFirstChild("PlayerScripts")
	if not PlayerScripts then
		return nil
	end

	local ok, PlotStateStore = pcall(function()
		return require(PlayerScripts.Client.ClientStores.PlotStateStore)
	end)

	local columns = nil
	if ok and PlotStateStore and PlotStateStore.GetGrid then
		local grid = PlotStateStore.GetGrid()
		if grid then
			columns = grid.Columns
		end
	end

	-- Always require cell hash lookup - no bounding box fallback
	if not columns then
		warn("[RoomQuery] Cannot determine room without grid columns")
		return nil
	end

	local targetIndex = computeCellIndex(columns, cellX, cellZ)

	for i, room in ipairs(rooms) do
		if room.Level == level then
			local lookup = cellLookupCache[i]
			if lookup and lookup[targetIndex] then
				return room
			end
		end
	end

	return nil
end

function RoomQuery.ClearCache()
	cachedRooms = nil
	table.clear(cellLookupCache)
end

return RoomQuery
