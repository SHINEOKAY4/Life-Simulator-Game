--!strict
-- ServerScriptService/Services/PlotService.lua

local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerSession = require(ServerScriptService.Server.Services.PlayerSession)
local Packets = require(ReplicatedStorage.Network.PlacementPackets)
local PlotFinder = require(ReplicatedStorage.Shared.Utilities.PlotFinder)
local GridClass = require(ServerScriptService.Server.Classes.Grid)
local PlotState = require(ServerScriptService.Server.Classes.PlotState)

local PlotService = {}
local PlotModels: { [number]: Model } = PlotFinder.GetOrderedPlots()
local PlotGrids = {} -- [plotIndex] = Grid
local PlayerRuntime = {} -- [userId] = PlotState

local function InitializePlayerPlot(player: Player, plotModel: Model)
	local coversFolder = plotModel:FindFirstChild("Covers") :: Folder
	local runtimeState = PlayerRuntime[player.UserId] -- PlotState
	if not runtimeState then
		return
	end

	for _, cover in ipairs(coversFolder:GetChildren()) do
		if cover:IsA("BasePart") then
			local cx = cover:GetAttribute("ChunkX") :: number?
			local cz = cover:GetAttribute("ChunkZ") :: number?
			if cx and cz and runtimeState:IsChunkUnlocked(cx, cz) then
				cover.Transparency = 1
				cover.CanQuery = false
			end
		end
	end
end

function PlotService.Init()
	print("PlotService initialized")
	-- Initialize PlotGrids
	for index, plotModel in ipairs(PlotModels) do
		local surface = plotModel:FindFirstChild("Surface") :: BasePart
		local cellSize = plotModel:GetAttribute("CellSize") :: number
		PlotGrids[index] = GridClass.new(surface, cellSize, "BottomLeft")
	end

	Packets.ClaimRequest.OnServerInvoke = function(player: Player, plotIndex: number): (boolean, string)
		return PlotService.Claim(player, plotIndex)
	end

	--#TODO: implement client side logic for unlocking chunks
	Packets.UnlockChunkRequest.OnServerInvoke = function(player, chunkX, chunkZ)
		return PlotService.UnlockArea(player, chunkX, chunkZ)
	end
end

function PlotService.Claim(player: Player, plotIndex: number)
	local plotModel = PlotModels[plotIndex]

	if not plotModel then
		return false, "Invalid plot index"
	end

	if player:GetAttribute("OwnedPlotIndex") then
		return false, "Player already owns a plot"
	end

	if plotModel:GetAttribute("Claimed") then
		return false, "Plot already claimed"
	end

	player:SetAttribute("OwnedPlotIndex", plotIndex)
	plotModel:SetAttribute("Claimed", true)
	plotModel:SetAttribute("Owner", player.UserId)

	PlotService.Load(player, plotModel) -- Order matters: must load before initializing plot
	InitializePlayerPlot(player, plotModel)
	return true, "Plot claimed successfully"
end

function PlotService.Load(player: Player, plotModel: Model)
	local userId = player.UserId
	local plotIndex = plotModel:GetAttribute("IndexOrder") :: number
	local grid = PlotGrids[plotIndex]
	local data = PlayerSession.GetDataAwait(player, "PlotState") :: any

	data.UnlockedChunks = data.UnlockedChunks or {}
	data.PlacedObjects = data.PlacedObjects or {}

	-- If brand new: create default starter area once (persist + runtime)
	if #data.UnlockedChunks == 0 then
		data.UnlockedChunks[1] = { cx = 1, cz = 3 }
	end

	local chunkSizeInCells = 5
	local runtimeState = PlotState.new(grid, chunkSizeInCells, data)
	runtimeState:HydrateFromSave()

	PlayerRuntime[userId] = runtimeState

	-- Possibly add a revision to discard stale client state in future (if problematic)

	local chunkInfo = {
		ChunkSizeInCells = chunkSizeInCells,
		ChunkColumns = runtimeState.ChunkColumns,
		ChunkRows = runtimeState.ChunkRows,
	}

	Packets.PlotStateSync:FireClient(player, chunkInfo, runtimeState.ChunkUnlocked, data.PlacedObjects)
end

function PlotService.Unclaim(player: Player)
	local plotIndex = player:GetAttribute("OwnedPlotIndex") :: number
	if not plotIndex then
		return false, "Player has no claimed plot"
	end

	local plotModel = PlotModels[plotIndex]
	if plotModel then
		plotModel:SetAttribute("Claimed", false)
		plotModel:SetAttribute("Owner", nil)
	end

	player:SetAttribute("OwnedPlotIndex", nil)
	PlayerRuntime[player.UserId] = nil

	return true, "Plot unclaimed"
end

function PlotService.UnlockArea(player: Player, chunkX: number, chunkZ: number): (boolean, string)
	local runtimeState = PlayerRuntime[player.UserId]
	if not runtimeState then
		return false, "Player has no runtime state"
	end

	if not runtimeState:IsChunkInBounds(chunkX, chunkZ) then
		return false, "Chunk out of bounds"
	end

	if runtimeState:IsChunkUnlocked(chunkX, chunkZ) then
		return false, "Already unlocked"
	end

	if not runtimeState:HasAdjacentUnlocked(chunkX, chunkZ) then
		return false, "Chunk not adjacent to unlocked area"
	end

	--#TODO: integrate cost check (currency / cash module)

	local success = runtimeState:UnlockChunk(chunkX, chunkZ)
	if not success then
		return false, "Already unlocked"
	end

	Packets.PlotStateUnlockDelta:FireClient(player, { runtimeState:ChunkIndex(chunkX, chunkZ) })
	return true, "Chunk unlocked"
end

function PlotService.GetState(player: Player)
	return PlayerRuntime[player.UserId]
end

return PlotService
