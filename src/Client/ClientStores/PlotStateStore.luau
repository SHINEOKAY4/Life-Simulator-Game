-- !strict
-- StarterPlayer/StarterPlayerScripts/Client/ClientStores/PlotStateStore.lua

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local PlotFinder = require(ReplicatedStorage.Shared.Utilities.PlotFinder)
local GridModule = require(ReplicatedStorage.Shared.Utilities.Grid)
local Packets = require(ReplicatedStorage.Network.PlacementPackets)
local PlacementKey = require(ReplicatedStorage.Shared.Utilities.PlacementKey)
local ItemFinder = require(ReplicatedStorage.Shared.Utilities.ItemFinder)

local PlotStateStore = {}
local StateSnapshot = {}

local PlotModel = nil
local CachedSurface: BasePart? = nil
local CachedGrid: any? = nil

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

local function ChunkToIndex(chunkX: number, chunkZ: number, chunkColumns: number): number
	return (chunkZ - 1) * chunkColumns + chunkX
end

function PlotStateStore.Init()
	Packets.PlotStateSync.OnClientEvent:Connect(function(chunkInfo, unlockedChunks, placedItems)
		StateSnapshot.ChunkInfo = chunkInfo
		StateSnapshot.ChunkUnlocked = unlockedChunks
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
				local itemSnapshot = {
					id = entry.id,
					cellX = entry.cellX,
					cellZ = entry.cellZ,
					facing = facing,
					WidthCells = widthCells,
					DepthCells = depthCells,
					Metadata = metadata,
				}
				local placementType = spec and (spec.PlacementType or spec.Type) or "CellObject"
				local key = PlacementKey.ForPlacementType(itemSnapshot.cellX, itemSnapshot.cellZ, facing, placementType)
				placedMap[key] = itemSnapshot
			end
		end
		StateSnapshot.PlacedItems = placedMap

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
		local key = PlacementKey.ForPlacementType(delta.Item.CellX, delta.Item.CellZ, facing, placementType)
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
		}
	end)
end

function PlotStateStore.GetStateSnapshot()
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
