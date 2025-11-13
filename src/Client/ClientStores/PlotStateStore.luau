-- !strict
-- StarterPlayer/StarterPlayerScripts/Client/ClientStores/PlotStateStore.lua

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local GoodSignal = require(ReplicatedStorage.Packages.GoodSignal)
local PlotFinder = require(ReplicatedStorage.Shared.Utilities.PlotFinder)
local GridModule = require(ReplicatedStorage.Shared.Utilities.Grid)
local Packets = require(ReplicatedStorage.Network.PlacementPackets)
local PlacementKey = require(ReplicatedStorage.Shared.Utilities.PlacementKey)
local ItemFinder = require(ReplicatedStorage.Shared.Utilities.ItemFinder)
local BuildConstants = require(ReplicatedStorage.Shared.Configurations.BuildConstants)

local PlotStateStore = {}
local StateSnapshot = {}

local PlotModel = nil
local CachedSurface: BasePart? = nil
local CachedGrid: any? = nil
local ActiveLevelInitialized = false
local ActiveLevel = 0
local ActiveLevelChanged = GoodSignal.new()

local function deepClone(value: any): any
	if typeof(value) ~= "table" then
		return value
	end

	local result = {}
	for key, entry in pairs(value) do
		result[key] = deepClone(entry)
	end

	return result
end

local function coerceVector3(value: any): Vector3?
	if typeof(value) == "Vector3" then
		return value
	end
	if typeof(value) ~= "table" then
		return nil
	end

	local xValue = value.X or value.x
	local yValue = value.Y or value.y
	local zValue = value.Z or value.z
	if typeof(xValue) ~= "number" or typeof(yValue) ~= "number" or typeof(zValue) ~= "number" then
		return nil
	end
	return Vector3.new(xValue, yValue, zValue)
end

local function normalizeMetadata(metadata: any): any
	if metadata == nil then
		return nil
	end

	if typeof(metadata) ~= "table" then
		return metadata
	end

	local cloned = deepClone(metadata)
	local wallData = cloned.WallMountData
	if typeof(wallData) == "table" then
		local convertedPosition = coerceVector3(wallData.WorldPosition)
		if convertedPosition then
			wallData.WorldPosition = convertedPosition
		end
		local convertedNormal = coerceVector3(wallData.WallNormal)
		if convertedNormal then
			if convertedNormal.Magnitude > 1e-3 then
				wallData.WallNormal = convertedNormal.Unit
			else
				wallData.WallNormal = Vector3.new(0, 0, -1)
			end
		end
	end

	return cloned
end

local function normalizeSurfaceMountEntry(entry: any)
	if typeof(entry) ~= "table" then
		return nil
	end

	local keyValue = entry.Key or entry.key
	if typeof(keyValue) ~= "string" or keyValue == "" then
		return nil
	end

	local itemIdValue = entry.ItemId or entry.id
	if typeof(itemIdValue) ~= "string" or itemIdValue == "" then
		return nil
	end

	local parentKeyValue = entry.ParentKey or entry.parentKey or ""
	if typeof(parentKeyValue) ~= "string" then
		parentKeyValue = ""
	end

	local localPosition = coerceVector3(entry.LocalPosition) or Vector3.new()
	local rotationValue = entry.LocalRotationY
	local rotationY = if typeof(rotationValue) == "number" then rotationValue else 0
	local metadata = normalizeMetadata(entry.Metadata)

	return {
		key = keyValue,
		id = itemIdValue,
		parentKey = parentKeyValue,
		LocalPosition = localPosition,
		LocalRotationY = rotationY,
		Metadata = metadata,
	}
end

local function ChunkToIndex(chunkX: number, chunkZ: number, chunkColumns: number): number
	return (chunkZ - 1) * chunkColumns + chunkX
end

function PlotStateStore.Init()
	Packets.PlotStateSync.OnClientEvent:Connect(function(chunkInfo, unlockedChunks, placedItems, surfaceMounts)
		StateSnapshot.ChunkInfo = chunkInfo
		StateSnapshot.ChunkUnlocked = unlockedChunks
		StateSnapshot.FloorHeightStuds = chunkInfo.FloorHeightStuds
		StateSnapshot.DefaultLevel = chunkInfo.DefaultLevel
		StateSnapshot.MaxLevel = chunkInfo.MaxLevel

		local defaultLevel = if typeof(chunkInfo.DefaultLevel) == "number" then chunkInfo.DefaultLevel else 0
		local maxLevel = if typeof(chunkInfo.MaxLevel) == "number" then chunkInfo.MaxLevel else defaultLevel

		if not ActiveLevelInitialized then
			ActiveLevel = defaultLevel
			ActiveLevelInitialized = true
			ActiveLevelChanged:Fire(ActiveLevel)
		else
			local clamped = math.clamp(ActiveLevel, defaultLevel, maxLevel)
			if clamped ~= ActiveLevel then
				ActiveLevel = clamped
				ActiveLevelChanged:Fire(ActiveLevel)
			end
		end
		StateSnapshot.ActiveLevel = ActiveLevel

		local placedMap = {}
		if placedItems then
			for _, entry in ipairs(placedItems) do
				local facing = entry.facing or "North"
				local spec = entry.id and ItemFinder.FindItemById(entry.id) or nil
				local metadata = normalizeMetadata(entry.Metadata)
				local widthCells = entry.WidthCells or entry.widthCells
				local depthCells = entry.DepthCells or entry.depthCells
				if not widthCells or widthCells <= 0 then
					widthCells = spec and (spec.WidthCells or spec.Width) or 1
				end
				if not depthCells or depthCells <= 0 then
					depthCells = spec and (spec.DepthCells or spec.Depth) or 1
				end
				local levelValue = entry.Level or entry.level or defaultLevel
				local numericLevel = tonumber(levelValue)
				if numericLevel then
					numericLevel = math.floor(numericLevel + 0.5)
					if numericLevel < defaultLevel then
						numericLevel = defaultLevel
					end
					levelValue = numericLevel
				else
					levelValue = defaultLevel
				end
				local itemSnapshot = {
					id = entry.id,
					cellX = entry.cellX,
					cellZ = entry.cellZ,
					facing = facing,
					WidthCells = widthCells,
					DepthCells = depthCells,
					Metadata = metadata,
					Level = levelValue,
				}
				local placementType = spec and (spec.PlacementType or spec.Type) or "CellObject"
				local key = PlacementKey.ForPlacementType(
					itemSnapshot.cellX,
					itemSnapshot.cellZ,
					facing,
					placementType,
					levelValue
				)
				placedMap[key] = itemSnapshot
			end
		end
		StateSnapshot.PlacedItems = placedMap

		local surfaceMap = {}
		if surfaceMounts then
			for _, entry in ipairs(surfaceMounts) do
				local normalized = normalizeSurfaceMountEntry(entry)
				if normalized then
					surfaceMap[normalized.key] = normalized
				end
			end
		end
		StateSnapshot.SurfaceMounts = surfaceMap

		-- Lazy initialize grid, helpful for external modules that need it
		if not CachedGrid then
			local player = Players.LocalPlayer
			local plotIndex = player:GetAttribute("OwnedPlotIndex") :: number?

			if plotIndex then
				local plotModel = PlotFinder.FindPlot(plotIndex)
				if plotModel then
					local surface = plotModel:FindFirstChild("Surface") :: BasePart?
					local cellSize = plotModel:GetAttribute("CellSize") :: number?
					PlotModel = plotModel
					if surface and cellSize then
						CachedSurface = surface
						CachedGrid = GridModule.new(surface, cellSize, "BottomLeft")
					end
				end
			end
		end
	end)

	Packets.PlotStateUnlockDelta.OnClientEvent:Connect(function(indices)
		if not StateSnapshot.ChunkUnlocked then
			return
		end

		for i = 1, #indices do
			StateSnapshot.ChunkUnlocked[indices[i]] = true
		end
	end)

	-- Added: incremental placement updates (client-side snapshot append)
	Packets.PlacementDelta.OnClientEvent:Connect(function(delta)
		-- delta shape (per PlacementPackets): { Action = "Placed", Item = { Id, CellX, CellZ, Facing } }

		StateSnapshot.PlacedItems = StateSnapshot.PlacedItems or {}

		if not delta or not delta.Item then
			return
		end

		local itemId = delta.Item.ItemId or delta.Item.Id or delta.Item.id
		if not itemId then
			return
		end

		local facing = delta.Item.Facing or "North"
		local spec = itemId and ItemFinder.FindItemById(itemId) or nil
		local placementType = spec and (spec.PlacementType or spec.Type) or "CellObject"
		local metadata = normalizeMetadata(delta.Item.Metadata)
		local widthCells = delta.Item.WidthCells or delta.Item.widthCells
		local depthCells = delta.Item.DepthCells or delta.Item.depthCells
		if not widthCells or widthCells <= 0 then
			widthCells = spec and (spec.WidthCells or spec.Width) or 1
		end
		if not depthCells or depthCells <= 0 then
			depthCells = spec and (spec.DepthCells or spec.Depth) or 1
		end
		local levelValue = delta.Item.Level or delta.Item.level or ActiveLevel
		local numericLevel = tonumber(levelValue)
		if numericLevel then
			numericLevel = math.floor(numericLevel + 0.5)
			if numericLevel < 0 then
				numericLevel = 0
			end
			levelValue = numericLevel
		else
			levelValue = ActiveLevel
		end
		local key = PlacementKey.ForPlacementType(delta.Item.CellX, delta.Item.CellZ, facing, placementType, levelValue)
		if delta.Action == "Removed" then
			StateSnapshot.PlacedItems[key] = nil
			return
		end

		if delta.Action ~= "Placed" then
			return
		end

		StateSnapshot.PlacedItems[key] = {
			id = itemId,
			cellX = delta.Item.CellX,
			cellZ = delta.Item.CellZ,
			facing = facing,
			WidthCells = widthCells,
			DepthCells = depthCells,
			Metadata = metadata,
			Level = levelValue,
		}
	end)

	Packets.SurfaceMountDelta.OnClientEvent:Connect(function(delta)
		StateSnapshot.SurfaceMounts = StateSnapshot.SurfaceMounts or {}
		if not delta or not delta.Mount then
			return
		end

		local normalized = normalizeSurfaceMountEntry(delta.Mount)
		if not normalized then
			return
		end

		if delta.Action == "Removed" then
			StateSnapshot.SurfaceMounts[normalized.key] = nil
			return
		end

		if delta.Action ~= "Placed" and delta.Action ~= "Updated" then
			return
		end

		StateSnapshot.SurfaceMounts[normalized.key] = normalized
	end)
end

function PlotStateStore.GetStateSnapshot()
	StateSnapshot.ActiveLevel = ActiveLevel
	return StateSnapshot
end

function PlotStateStore.IsReady(): boolean
	return StateSnapshot.ChunkInfo ~= nil and StateSnapshot.ChunkUnlocked ~= nil
end

function PlotStateStore.GetPlotModel(): Model?
	return PlotModel
end

function PlotStateStore.GetGrid()
	return CachedGrid
end

function PlotStateStore.GetSurface(): BasePart?
	return CachedSurface
end

function PlotStateStore.GetDefaultLevel(): number
	local info = StateSnapshot.ChunkInfo
	if info and typeof(info.DefaultLevel) == "number" then
		return info.DefaultLevel
	end
	return 0
end

function PlotStateStore.GetMaxLevel(): number
	local info = StateSnapshot.ChunkInfo
	if info and typeof(info.MaxLevel) == "number" then
		return info.MaxLevel
	end
	return PlotStateStore.GetDefaultLevel()
end

function PlotStateStore.GetActiveLevel(): number
	if ActiveLevelInitialized then
		return ActiveLevel
	end
	return PlotStateStore.GetDefaultLevel()
end

function PlotStateStore.SetActiveLevel(level: number)
	if not PlotStateStore.IsReady() then
		return
	end
	local defaultLevel = PlotStateStore.GetDefaultLevel()
	local maxLevel = PlotStateStore.GetMaxLevel()
	local clamped = math.clamp(level, defaultLevel, maxLevel)
	if clamped == ActiveLevel and ActiveLevelInitialized then
		return
	end
	ActiveLevel = clamped
	ActiveLevelInitialized = true
	StateSnapshot.ActiveLevel = ActiveLevel
	ActiveLevelChanged:Fire(ActiveLevel)
end

function PlotStateStore.OnActiveLevelChanged(handler: (number) -> ()): RBXScriptConnection
	return ActiveLevelChanged:Connect(handler)
end

function PlotStateStore.GetFloorHeightStuds(): number
	local info = StateSnapshot.ChunkInfo
	if info and typeof(info.FloorHeightStuds) == "number" then
		return info.FloorHeightStuds
	end
	return BuildConstants.FloorHeightStuds or 12
end

function PlotStateStore.GetLevelHeight(level: number?): number
	local resolvedLevel = if typeof(level) == "number" then level else PlotStateStore.GetActiveLevel()
	return PlotStateStore.GetFloorHeightStuds() * resolvedLevel
end

function PlotStateStore.IsChunkUnlocked(chunkX: number, chunkZ: number): boolean
	if not PlotStateStore.IsReady() then
		return false
	end
	local info = StateSnapshot.ChunkInfo
	local unlocked = StateSnapshot.ChunkUnlocked
	return unlocked[ChunkToIndex(chunkX, chunkZ, info.ChunkColumns)] == true
end

function PlotStateStore.IsChunkInBounds(chunkX: number, chunkZ: number): boolean
	if not PlotStateStore.IsReady() then
		return false
	end
	local info = StateSnapshot.ChunkInfo
	return chunkX >= 1 and chunkX <= info.ChunkColumns and chunkZ >= 1 and chunkZ <= info.ChunkRows
end

function PlotStateStore.HasAdjacentUnlocked(chunkX: number, chunkZ: number): boolean
	if not PlotStateStore.IsReady() then
		return false
	end
	local info = StateSnapshot.ChunkInfo
	local unlocked = StateSnapshot.ChunkUnlocked
	local columns = info.ChunkColumns
	local rows = info.ChunkRows

	return (chunkX > 1 and unlocked[ChunkToIndex(chunkX - 1, chunkZ, columns)] == true)
		or (chunkX < columns and unlocked[ChunkToIndex(chunkX + 1, chunkZ, columns)] == true)
		or (chunkZ > 1 and unlocked[ChunkToIndex(chunkX, chunkZ - 1, columns)] == true)
		or (chunkZ < rows and unlocked[ChunkToIndex(chunkX, chunkZ + 1, columns)] == true)
end

function PlotStateStore.CanPurchaseChunk(chunkX: number, chunkZ: number): (boolean, string)
	if not PlotStateStore.IsReady() then
		return false, "State not ready"
	end
	if not PlotStateStore.IsChunkInBounds(chunkX, chunkZ) then
		return false, "Out of bounds"
	end
	if PlotStateStore.IsChunkUnlocked(chunkX, chunkZ) then
		return false, "Already unlocked"
	end
	if not PlotStateStore.HasAdjacentUnlocked(chunkX, chunkZ) then
		return false, "Not adjacent to unlocked area"
	end
	return true, ""
end

function PlotStateStore.RequestPurchase(chunkX: number, chunkZ: number): (boolean, string)
	-- Optional fast-fails for UX; do NOT attempt to mirror all server logic here.
	if not PlotStateStore.IsReady() then
		return false, "State not ready"
	end
	if not PlotStateStore.IsChunkInBounds(chunkX, chunkZ) then
		return false, "Out of bounds"
	end

	-- Always defer to server authority
	local success, message = Packets.UnlockChunkRequest:Fire(chunkX, chunkZ)
	return success, message
end

return PlotStateStore
