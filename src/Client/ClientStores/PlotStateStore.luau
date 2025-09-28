-- !strict
-- StarterPlayer/StarterPlayerScripts/Client/ClientStores/PlotStateStore.luau

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GoodSignal = require(ReplicatedStorage.Packages.GoodSignal)
local Packets = require(ReplicatedStorage.Network.PlacementPackets)

local PlotStateStore = {}
local StateSnapshot = {}

PlotStateStore.StateChanged = GoodSignal.new()
PlotStateStore.StateUnlockChanged = GoodSignal.new()
PlotStateStore.StatePlacedItemsChanged = GoodSignal.new()

local function ChunkToIndex(chunkX: number, chunkZ: number, chunkColumns: number): number
	return (chunkZ - 1) * chunkColumns + chunkX
end

function PlotStateStore.Init()
	Packets.PlotStateSync.OnClientEvent:Connect(function(chunkInfo, unlockedChunks, placedItems)
		StateSnapshot.ChunkInfo = chunkInfo
		StateSnapshot.ChunkUnlocked = unlockedChunks
		StateSnapshot.PlacedItems = placedItems

		PlotStateStore.StateChanged:Fire(StateSnapshot)
		print("PlotStateStore: Received plot state sync")
	end)

	Packets.PlotStateUnlockDelta.OnClientEvent:Connect(function(indices)
		for i = 1, #indices do
			StateSnapshot.ChunkUnlocked[indices[i]] = true
		end
		PlotStateStore.StateUnlockChanged:Fire(indices, StateSnapshot.ChunkUnlocked)
	end)
end

function PlotStateStore.ObserveUnlockState(callback: (changedIndices: { number }?, snapshot: { boolean }) -> ())
	return PlotStateStore.StateUnlockChanged:Connect(callback)
end

function PlotStateStore.ObserveStateChanged(callback: (newState: typeof(StateSnapshot)) -> ())
	return PlotStateStore.StateChanged:Connect(callback)
end

function PlotStateStore.GetStateSnapshot()
	return StateSnapshot
end

function PlotStateStore.IsChunkUnlocked(chunkX: number, chunkZ: number): boolean
	local info = StateSnapshot.ChunkInfo
	local unlocked = StateSnapshot.ChunkUnlocked
	if not info or not unlocked then
		return false
	end
	return unlocked[ChunkToIndex(chunkX, chunkZ, info.ChunkColumns)] == true
end

return PlotStateStore
