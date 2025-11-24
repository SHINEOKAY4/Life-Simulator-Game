--!strict
-- StarterPlayerScripts/Client/Modules/TenantRoomTracker.luau
-- Keeps tenant room assignments in sync with the current plot snapshot and
-- exposes helpers for picking random wander points inside a tenant's room.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlotStateStore = require(script.Parent.Parent.ClientStores.PlotStateStore)
local TenantStore = require(script.Parent.Parent.ClientStores.TenantStore)
local RoomCore = require(ReplicatedStorage.Shared.Utilities.RoomCore)

local LOCAL_PLAYER = Players.LocalPlayer
local LOCAL_USER_ID = LOCAL_PLAYER and LOCAL_PLAYER.UserId or 0
local rng = Random.new()

export type RoomSample = {
	Level: number,
	CellIndices: { number },
	MinCellX: number,
	MaxCellX: number,
	MinCellZ: number,
	MaxCellZ: number,
}

local TenantRoomTracker = {}

local isInitialized = false
local roomSamplesByKey: { [string]: RoomSample } = {}
local tenantRoomKeys: { [string]: string } = {}

local function copyNumberArray(source: { number }?): { number }
	local result: { number } = {}
	if not source then
		return result
	end
	for index = 1, #source do
		result[index] = source[index]
	end
	return result
end

local function normalizeRoomKey(roomKey: string?): string?
	if typeof(roomKey) ~= "string" or roomKey == "" then
		return nil
	end
	return RoomCore.NormalizeRoomKey(roomKey)
end

local function rebuildRoomSamples()
	if not PlotStateStore.IsReady() then
		return
	end

	table.clear(roomSamplesByKey)

	local defaultLevel = PlotStateStore.GetDefaultLevel()
	local maxLevel = PlotStateStore.GetMaxLevel()
	local startLevel = math.min(defaultLevel, maxLevel)
	local endLevel = math.max(defaultLevel, maxLevel)

	for level = startLevel, endLevel do
		PlotStateStore.IterateRooms(level, function(room)
			if room.CellCount and room.CellCount > 0 then
				local key = RoomCore.MakeRoomKey(room.Level, room.MinCellX, room.MinCellZ)
				roomSamplesByKey[key] = {
					Level = room.Level,
					CellIndices = copyNumberArray(room.CellIndices),
					MinCellX = room.MinCellX,
					MaxCellX = room.MaxCellX,
					MinCellZ = room.MinCellZ,
					MaxCellZ = room.MaxCellZ,
				}
			end
			return nil
		end)
	end
end

local function applyTenantPayload(tenantData: any)
	if typeof(tenantData) ~= "table" then
		return
	end
	local tenantId = tenantData.TenantId
	if type(tenantId) ~= "string" or tenantId == "" then
		return
	end
	local normalizedKey = normalizeRoomKey(tenantData.RoomKey)
	if normalizedKey then
		tenantRoomKeys[tenantId] = normalizedKey
	else
		tenantRoomKeys[tenantId] = nil
	end
end

local function handleTenantAdded(userId: number, tenantData: any)
	if userId ~= LOCAL_USER_ID then
		return
	end
	applyTenantPayload(tenantData)
end

local function handleTenantUpdated(userId: number, tenantData: any)
	if userId ~= LOCAL_USER_ID then
		return
	end
	applyTenantPayload(tenantData)
end

local function handleTenantRemoved(userId: number, tenantId: string)
	if userId ~= LOCAL_USER_ID then
		return
	end
	tenantRoomKeys[tenantId] = nil
end

local function primeTenantAssignments()
	local snapshot = TenantStore.GetTenants()
	if not snapshot then
		return
	end
	for _, tenantData in pairs(snapshot) do
		applyTenantPayload(tenantData)
	end
end

local function waitForPlotStateReady()
	if PlotStateStore.IsReady() then
		rebuildRoomSamples()
		return
	end
	task.spawn(function()
		while task.wait(0.5) do
			if PlotStateStore.IsReady() then
				rebuildRoomSamples()
				break
			end
		end
	end)
end

local function pickCellFromRoom(sample: RoomSample): (number?, number?)
	local cells = sample.CellIndices
	if not cells or #cells == 0 then
		return nil, nil
	end
	local grid = PlotStateStore.GetGrid()
	if not grid then
		return nil, nil
	end
	local pickIndex = cells[rng:NextInteger(1, #cells)]
	local columns = grid.Columns
	local rows = grid.Rows
	if not columns or not rows then
		return nil, nil
	end
	local zeroBased = pickIndex - 1
	local cellZ = math.floor(zeroBased / columns) + 1
	local cellX = (zeroBased % columns) + 1
	if cellX < 1 or cellX > columns or cellZ < 1 or cellZ > rows then
		return nil, nil
	end
	return cellX, cellZ
end

function TenantRoomTracker.Init()
	if isInitialized then
		return
	end
	isInitialized = true

	TenantStore.TenantAdded:Connect(handleTenantAdded)
	TenantStore.TenantsUpdated:Connect(handleTenantUpdated)
	TenantStore.TenantRemoved:Connect(handleTenantRemoved)

	PlotStateStore.OnRoomSnapshotChanged(rebuildRoomSamples)
	PlotStateStore.OnPlacementMetadataChanged(rebuildRoomSamples)

	primeTenantAssignments()
	rebuildRoomSamples()
	waitForPlotStateReady()
end

function TenantRoomTracker.GetRoomKeyForTenant(tenantId: string): string?
	return tenantRoomKeys[tenantId]
end

function TenantRoomTracker.GetRoomSampleForTenant(tenantId: string): RoomSample?
	local roomKey = tenantRoomKeys[tenantId]
	if not roomKey then
		return nil
	end
	if not roomSamplesByKey[roomKey] then
		rebuildRoomSamples()
	end
	return roomSamplesByKey[roomKey]
end

function TenantRoomTracker.GetRandomTargetForTenant(tenantId: string): Vector3?
	if type(tenantId) ~= "string" or tenantId == "" then
		return nil
	end
	local sample = TenantRoomTracker.GetRoomSampleForTenant(tenantId)
	if not sample then
		return nil
	end
	local grid = PlotStateStore.GetGrid()
	if not grid then
		return nil
	end
	local cellX, cellZ = pickCellFromRoom(sample)
	if not cellX or not cellZ then
		return nil
	end
	local heightOffset = PlotStateStore.GetLevelHeight(sample.Level)
	local position = grid:CellToWorldCenter(cellX, cellZ, heightOffset)
	local jitterRange = math.min(grid.CellSize * 0.35, 2)
	if jitterRange > 0 then
		local jitterX = rng:NextNumber(-jitterRange, jitterRange)
		local jitterZ = rng:NextNumber(-jitterRange, jitterRange)
		position += Vector3.new(jitterX, 0, jitterZ)
	end
	return position
end

return TenantRoomTracker
