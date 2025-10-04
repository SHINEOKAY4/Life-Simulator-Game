--!strict
-- ServerScriptService/Services/PlotService.lua

local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerSession = require(ServerScriptService.Server.Services.PlayerSession)
local Packets = require(ReplicatedStorage.Network.PlacementPackets)
local PlotFinder = require(ReplicatedStorage.Shared.Utilities.PlotFinder)
local GridClass = require(ReplicatedStorage.Shared.Utilities.Grid)
local PlotState = require(ServerScriptService.Server.Classes.PlotState)
local WorldPlacer = require(ServerScriptService.Server.Utilities.WorldPlacer)

type PlotRuntimeState = PlotState.PlotState
type PlacedObjectMap = PlotState.PlacedObjectMap
type PlacedObjectSnapshot = { id: string, cellX: number, cellZ: number, facing: string }

local PlotService = {}
local PlotModels: { [number]: Model } = PlotFinder.GetOrderedPlots()
local PlotGrids: { [number]: any } = {} -- [plotIndex] = Grid
local PlayerRuntime: { [number]: PlotRuntimeState } = {}

local function flattenPlacedObjects(map: PlacedObjectMap): { PlacedObjectSnapshot }
	local keys = {}
	for key in pairs(map) do
		keys[#keys + 1] = key
	end
	table.sort(keys)

	local result = table.create(#keys)
	for index = 1, #keys do
		local saved = map[keys[index]]
		if saved then
			result[index] = {
				id = saved.id,
				cellX = saved.cellX,
				cellZ = saved.cellZ,
				facing = (saved.facing or "North") :: string,
			}
		end
	end

	return result
end

local function InitializePlayerPlot(player: Player, plotModel: Model)
	local coversFolder = plotModel:FindFirstChild("Covers") :: Folder
	local runtimeState = PlayerRuntime[player.UserId]
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

	Packets.UnlockChunkRequest.OnServerInvoke = function(player, chunkX, chunkZ)
		local plotIndex = player:GetAttribute("OwnedPlotIndex") :: number
		local plotModel = PlotFinder.FindPlot(plotIndex)
		local coversFolder = plotModel and plotModel:FindFirstChild("Covers") :: Folder
		local success, message = PlotService.UnlockArea(player, chunkX, chunkZ)
		if success then
			local coverPart = coversFolder
				and coversFolder:FindFirstChild("Cover_" .. chunkX .. "_" .. chunkZ) :: BasePart?
			if coverPart then
				coverPart.Transparency = 1
				coverPart.CanQuery = false
			end
		end
		return success, message
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

	for _, obj in pairs(data.PlacedObjects) do
		local facing = obj.facing or "North"
		WorldPlacer.Spawn(player, grid, obj.id, obj.cellX, obj.cellZ, facing)
	end

	-- Possibly add a revision to discard stale client state in future (if problematic)

	local chunkInfo = {
		ChunkSizeInCells = chunkSizeInCells,
		ChunkColumns = runtimeState.ChunkColumns,
		ChunkRows = runtimeState.ChunkRows,
	}

	local placedSnapshot = flattenPlacedObjects(data.PlacedObjects)
	Packets.PlotStateSync:FireClient(player, chunkInfo, runtimeState.ChunkUnlocked, placedSnapshot)
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

function PlotService.GetState(player: Player): PlotRuntimeState?
	return PlayerRuntime[player.UserId]
end

return PlotService
