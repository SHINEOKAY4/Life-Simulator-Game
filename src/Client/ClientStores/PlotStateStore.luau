-- !strict
-- StarterPlayer/StarterPlayerScripts/Client/ClientStores/PlotStateStore.lua

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packets = require(ReplicatedStorage.Network.PlacementPackets)

local PlotStateStore = {}
local StateSnapshot = {}

local function ChunkToIndex(chunkX: number, chunkZ: number, chunkColumns: number): number
	return (chunkZ - 1) * chunkColumns + chunkX
end

function PlotStateStore.Init()
	Packets.PlotStateSync.OnClientEvent:Connect(function(chunkInfo, unlockedChunks, placedItems)
		StateSnapshot.ChunkInfo = chunkInfo
		StateSnapshot.ChunkUnlocked = unlockedChunks
		StateSnapshot.PlacedItems = placedItems

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
end

function PlotStateStore.GetStateSnapshot()
	return StateSnapshot
end

function PlotStateStore.IsReady(): boolean
	return StateSnapshot.ChunkInfo ~= nil and StateSnapshot.ChunkUnlocked ~= nil
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
