-- !strict
-- StarterPlayer/StarterPlayerScripts/Client/ClientStores/PlotStateStore.lua

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local PlotFinder = require(ReplicatedStorage.Shared.Utilities.PlotFinder)
local GridModule = require(ReplicatedStorage.Shared.Utilities.Grid)
local Packets = require(ReplicatedStorage.Network.PlacementPackets)

local PlotStateStore = {}
local StateSnapshot = {}

local CachedSurface: BasePart? = nil
local CachedGrid: any? = nil

local function ChunkToIndex(chunkX: number, chunkZ: number, chunkColumns: number): number
	return (chunkZ - 1) * chunkColumns + chunkX
end

function PlotStateStore.Init()
	Packets.PlotStateSync.OnClientEvent:Connect(function(chunkInfo, unlockedChunks, placedItems)
		StateSnapshot.ChunkInfo = chunkInfo
		StateSnapshot.ChunkUnlocked = unlockedChunks
		StateSnapshot.PlacedItems = placedItems

		-- Lazy initialize grid, helpful for external modules that need it
		if not CachedGrid then
			local player = Players.LocalPlayer
			local plotIndex = player:GetAttribute("OwnedPlotIndex") :: number?

			if plotIndex then
				local plotModel = PlotFinder.FindPlot(plotIndex)
				if plotModel then
					local surface = plotModel:FindFirstChild("Surface") :: BasePart?
					local cellSize = plotModel:GetAttribute("CellSize") :: number?

					if surface and cellSize then
						CachedSurface = surface
						CachedGrid = GridModule.new(surface, cellSize, "BottomLeft")
					end
				end
			end
		end

		print("PlotStateStore: Received plot state sync")
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

		if not StateSnapshot.PlacedItems then
			StateSnapshot.PlacedItems = {} -- Added: ensure table exists
		end

		if delta and delta.Action == "Removed" and delta.Item then
			for i = #StateSnapshot.PlacedItems, 1, -1 do
				local o = StateSnapshot.PlacedItems[i]
				local id = o.id or o.Id or o.ItemId
				if
					id == delta.Item.ItemId
					and o.cellX == delta.Item.CellX
					and o.cellZ == delta.Item.CellZ
					and (o.facing or "North") == (delta.Item.Facing or "North")
				then
					table.remove(StateSnapshot.PlacedItems, i)
					break
				end
			end
			return
		end
		-- Only handle "Placed" for now (YAGNI) -- Added
		if not delta or delta.Action ~= "Placed" or not delta.Item then
			return
		end

		local itemId = delta.Item.ItemId or delta.Item.Id or delta.Item.id
		if not itemId then
			return
		end
		-- Append a normalized item entry, matching PlotStateSync schema
		local entry = {
			id = itemId,
			cellX = delta.Item.CellX,
			cellZ = delta.Item.CellZ,
			facing = delta.Item.Facing or "North",
		}

		StateSnapshot.PlacedItems[#StateSnapshot.PlacedItems + 1] = entry
	end)
end

function PlotStateStore.GetStateSnapshot()
	return StateSnapshot
end

function PlotStateStore.IsReady(): boolean
	return StateSnapshot.ChunkInfo ~= nil and StateSnapshot.ChunkUnlocked ~= nil
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

--#TODO: Add function to get placed items, purchase items, remove items, etc.
return PlotStateStore
