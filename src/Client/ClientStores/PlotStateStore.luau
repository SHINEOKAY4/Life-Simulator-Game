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
				local itemSnapshot = {
					id = entry.id,
					cellX = entry.cellX,
					cellZ = entry.cellZ,
					facing = facing,
				}
				local spec = itemSnapshot.id and ItemFinder.FindItemById(itemSnapshot.id) or nil
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
	local columns, rows = info.ChunkColumns, info.ChunkRows

	if chunkX > 1 and unlocked[ChunkToIndex(chunkX - 1, chunkZ, columns)] then
		return true
	end
	if chunkX < columns and unlocked[ChunkToIndex(chunkX + 1, chunkZ, columns)] then
		return true
	end
	if chunkZ > 1 and unlocked[ChunkToIndex(chunkX, chunkZ - 1, columns)] then
		return true
	end
	if chunkZ < rows and unlocked[ChunkToIndex(chunkX, chunkZ + 1, columns)] then
		return true
	end
	return false
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
