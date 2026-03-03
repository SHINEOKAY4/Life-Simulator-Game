--!strict
-- ServerScriptService/Services/PlotService.lua

local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerSession = require(ServerScriptService.Server.Services.PlayerSession)
local EnergyUsageTracker = require(ServerScriptService.Server.Utilities.EnergyUsageTracker)
local CurrencyService = require(ServerScriptService.Server.Services.CurrencyService)
local Packets = require(ReplicatedStorage.Network.PlacementPackets)
local PlotFinder = require(ReplicatedStorage.Shared.Utilities.PlotFinder)
local GridClass = require(ReplicatedStorage.Shared.Utilities.Grid)
local PlotState = require(ServerScriptService.Server.Classes.PlotState)
local WorldPlacer = require(ServerScriptService.Server.Utilities.WorldPlacer)
local RepairManager = require(ServerScriptService.Server.Modules.Chores.RepairManager)
local ItemFinder = require(ReplicatedStorage.Shared.Utilities.ItemFinder)
local PlacementKey = require(ReplicatedStorage.Shared.Utilities.PlacementKey)
local BuildConstants = require(ReplicatedStorage.Shared.Configurations.BuildConstants)
local GoodSignal = require(ReplicatedStorage.Packages.GoodSignal)
local PlotSerializationUtils = require(ServerScriptService.Server.Utilities.PlotSerializationUtils)

type PlotRuntimeState = PlotState.PlotState
type Facing = PlotState.Facing
type StationOccupancy = {
	Id: string,
	Residents: { [number]: string },
	Occupied: boolean,
	Model: Model?,
	ActiveOverride: string?,
}
type StationInstanceMap = { [string]: StationOccupancy }
type PlayerStationCache = { [string]: StationInstanceMap }

local PlotService = {}
local POWER_OUTAGE_OVERRIDE = "PowerOutage"
local PlotModels: { [number]: Model } = PlotFinder.GetOrderedPlots()
local PlotGrids: { [number]: any } = {} -- [plotIndex] = Grid
local PlayerRuntime: { [number]: PlotRuntimeState } = {}
local PlayerStations: { [number]: PlayerStationCache } = {} -- [playerId] = { stationName = {uid}, ... }
local StationScopeVersions: { [number]: { [string]: number } } = {}

RepairManager.SetRoomResolver(function(player: Player, cellX: number, cellZ: number, level: number?)
	local runtime = PlotService.GetState(player)
	if not runtime then
		return nil
	end
	return runtime:GetRoomAt(cellX, cellZ, level)
end)

local function bumpStationVersion(userId: number, stationType: string)
	local versionMap = StationScopeVersions[userId]
	if not versionMap then
		versionMap = {}
		StationScopeVersions[userId] = versionMap
	end
	versionMap[stationType] = (versionMap[stationType] or 0) + 1
end

PlotService.PlotClaimed = GoodSignal.new()
PlotService.PlotUnclaimed = GoodSignal.new()
PlotService.StationRemoved = GoodSignal.new()

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

	PlotService.PlotClaimed:Fire(player, PlayerRuntime[player.UserId])
	return true, "Plot claimed successfully"
end

function PlotService.Load(player: Player, plotModel: Model)
	local userId = player.UserId
	local plotIndex = plotModel:GetAttribute("IndexOrder") :: number
	local grid = PlotGrids[plotIndex]
	local plotStateData = PlayerSession.GetDataAwait(player, "PlotState") :: any
	local currencyStateData = PlayerSession.GetDataAwait(player, "CurrencyState") :: any

	plotStateData.UnlockedChunks = plotStateData.UnlockedChunks or {}
	plotStateData.PlacedObjects = plotStateData.PlacedObjects or {}
	plotStateData.InteractableCooldowns = plotStateData.InteractableCooldowns or {}

	-- If brand new: create default starter area once (persist + runtime)
	if #plotStateData.UnlockedChunks == 0 then
		plotStateData.UnlockedChunks[1] = { cx = 1, cz = 3 }
	end

	local chunkSizeInCells = 5
	local runtimeState = PlotState.new(grid, chunkSizeInCells, plotStateData)
	runtimeState.Owner = player
	runtimeState:HydrateFromSave()

	PlayerRuntime[userId] = runtimeState
	PlayerStations[userId] = {}
	StationScopeVersions[userId] = StationScopeVersions[userId] or {}

	local totalEnergyLoad = 0
	-- Station names are the object IDs of the stations and the key is the unique id for easier reference
	local stationCache = PlayerStations[userId]
	for uniqueKey, obj in pairs(plotStateData.PlacedObjects) do
		local facing = obj.facing or "North"
		local metadataClone = if obj.Metadata ~= nil then PlotSerializationUtils.CloneMetadata(obj.Metadata) else nil
		WorldPlacer.Spawn(player, grid, obj.id, obj.cellX, obj.cellZ, facing, obj.yLevel, {
			metadata = metadataClone,
		})

		local itemSpec = ItemFinder.FindItemById(obj.id)
		local energyPerHour = itemSpec and itemSpec.EnergyConsumptionPerHour
		local stationType = itemSpec and itemSpec.StationType
		if stationType then
			local stationScope = stationCache[stationType]
			if not stationScope then
				stationScope = {}
				stationCache[stationType] = stationScope
			end
			local activeOverrideValue = nil
			if player:GetAttribute("PowerOutageActive") == true then
				if typeof(energyPerHour) == "number" and energyPerHour > 0 then
					activeOverrideValue = POWER_OUTAGE_OVERRIDE
				end
			end
			stationScope[uniqueKey] = {
				Id = obj.id,
				Residents = {},
				Occupied = false,
				Model = nil,
				ActiveOverride = activeOverrideValue,
			}
			bumpStationVersion(userId, stationType)
		end

		if typeof(energyPerHour) == "number" and energyPerHour > 0 then
			totalEnergyLoad += energyPerHour
		end
	end

	for mountKey, mount in pairs(plotStateData.SurfaceMountedObjects or {}) do
		if
			typeof(mount) == "table"
			and typeof(mount.id) == "string"
			and typeof(mount.parentKey) == "string"
			and mount.parentKey ~= ""
		then
			WorldPlacer.SpawnSurfaceMount(player, mount.parentKey, mountKey, mount.id, mount)
		end
	end

	for currencyName, amount in pairs(currencyStateData or {}) do
		player:SetAttribute(currencyName, amount)
	end
	-- Possibly add a revision to discard stale client state in future (if problematic)

	local chunkInfo = {
		ChunkSizeInCells = chunkSizeInCells,
		ChunkColumns = runtimeState.ChunkColumns,
		ChunkRows = runtimeState.ChunkRows,
		DefaultLevel = runtimeState.DefaultLevel,
		MaxLevel = runtimeState.MaxFloorLevel,
		FloorHeightStuds = runtimeState:GetFloorHeightStuds(),
	}

	local placedSnapshot = PlotSerializationUtils.FlattenPlacedObjects(
		plotStateData.PlacedObjects,
		runtimeState.DefaultLevel,
		ItemFinder.FindItemById
	)
	local surfaceMountSnapshot = PlotSerializationUtils.FlattenSurfaceMounts(runtimeState.SurfaceMountedObjects)
	Packets.PlotStateSync:FireClient(
		player,
		chunkInfo,
		runtimeState.ChunkUnlocked,
		placedSnapshot,
		surfaceMountSnapshot
	)

	EnergyUsageTracker.SyncBaseLoad(player, totalEnergyLoad)
	local outageActive = player:GetAttribute("PowerOutageActive") == true
	EnergyUsageTracker.SetOutage(player, outageActive)
end

function PlotService.Unclaim(player: Player)
	local plotIndex = player:GetAttribute("OwnedPlotIndex") :: number
	if not plotIndex then
		return false, "Player has no claimed plot"
	end

	local plotModel = PlotModels[plotIndex]
	if plotModel then
		local containerFolder = plotModel:FindFirstChild("Container") :: Folder
		local coversFolder = plotModel:FindFirstChild("Covers") :: Folder
		local grid = PlotGrids[plotIndex]
		for _, cover in ipairs(coversFolder:GetChildren()) do
			if cover:IsA("BasePart") then
				cover.Transparency = 0
				cover.CanQuery = true
			end
		end

		for _, item in ipairs(containerFolder:GetChildren()) do
			if item:IsA("Model") then
				local placementTypeAttr = item:GetAttribute("PlacementType")
				if placementTypeAttr == "SurfaceMounted" then
					item:Destroy()
				else
					local itemIdAttr = item:GetAttribute("ItemId")
					local cellXAttr = item:GetAttribute("CellX")
					local cellZAttr = item:GetAttribute("CellZ")
					local facingAttr = item:GetAttribute("Facing")
					local levelAttr = item:GetAttribute("Level")
					if
						typeof(itemIdAttr) == "string"
						and typeof(cellXAttr) == "number"
						and typeof(cellZAttr) == "number"
					then
						local facingSource = if typeof(facingAttr) == "string" then facingAttr else "North"
						local facingValue: Facing = PlacementKey.NormalizeFacing(facingSource :: any) :: Facing
						local normalizedLevel = if typeof(levelAttr) == "number" then levelAttr else nil
						WorldPlacer.Despawn(
							player,
							grid,
							itemIdAttr,
							cellXAttr,
							cellZAttr,
							facingValue,
							normalizedLevel
						)
					end
					item:Destroy()
				end
			end
		end
		plotModel:SetAttribute("Claimed", false)
		plotModel:SetAttribute("Owner", nil)
	end

	player:SetAttribute("OwnedPlotIndex", nil)
	PlayerRuntime[player.UserId] = nil
	PlayerStations[player.UserId] = nil
	StationScopeVersions[player.UserId] = nil

	PlotService.PlotUnclaimed:Fire(player, plotIndex)
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

	local unlockedCount = #runtimeState.Save.UnlockedChunks
	local baseCost = BuildConstants.ExpansionBaseCost or 400
	local increment = BuildConstants.ExpansionCostIncrement or 200
	local cost = baseCost + math.max(0, unlockedCount - 1) * increment

	local rawCurrencyData = PlayerSession.GetDataAwait(player, "CurrencyState")
	local currencyData = if typeof(rawCurrencyData) == "table" then rawCurrencyData :: { [string]: number } else {}
	local currentCash = CurrencyService.Get(player, "Cash", currencyData)

	if currentCash < cost then
		return false, "Insufficient funds"
	end

	local success = runtimeState:UnlockChunk(chunkX, chunkZ)
	if not success then
		return false, "Already unlocked"
	end

	CurrencyService.Remove(player, "Cash", cost, currencyData)

	Packets.PlotStateUnlockDelta:FireClient(player, { runtimeState:ChunkIndex(chunkX, chunkZ) })
	return true, "Chunk unlocked"
end

function PlotService.GetState(player: Player): PlotRuntimeState?
	return PlayerRuntime[player.UserId]
end

function PlotService.GetGrid(plotIndex: number): any?
	return PlotGrids[plotIndex]
end

function PlotService.GetGridForPlot(plotModel: Model?): any?
	if not plotModel then
		return nil
	end

	local indexOrder = plotModel:GetAttribute("IndexOrder")
	if typeof(indexOrder) ~= "number" then
		return nil
	end

	return PlotService.GetGrid(indexOrder)
end

function PlotService.GetStationsForPlayer(player: Player): PlayerStationCache
	local userId = player.UserId
	local stations = PlayerStations[userId]
	if not stations then
		stations = {}
		PlayerStations[userId] = stations
	end
	if not StationScopeVersions[userId] then
		StationScopeVersions[userId] = {}
	end
	return stations
end

function PlotService.AddStationForPlayer(player: Player, stationName: string, uniqueId: string, itemId: string)
	local userId = player.UserId
	local stationCache = PlayerStations[userId]
	if not stationCache then
		stationCache = {}
		PlayerStations[userId] = stationCache
	end
	if not StationScopeVersions[userId] then
		StationScopeVersions[userId] = {}
	end

	local stationScope = stationCache[stationName]
	if not stationScope then
		stationScope = {}
		stationCache[stationName] = stationScope
	end
	local itemSpec = ItemFinder.FindItemById(itemId)
	local energyPerHour = itemSpec and itemSpec.EnergyConsumptionPerHour
	local activeOverrideValue = nil
	if player:GetAttribute("PowerOutageActive") == true then
		if typeof(energyPerHour) == "number" and energyPerHour > 0 then
			activeOverrideValue = POWER_OUTAGE_OVERRIDE
		end
	end
	stationScope[uniqueId] = {
		Id = itemId,
		Residents = {},
		Occupied = false,
		Model = nil,
		ActiveOverride = activeOverrideValue,
	}
	bumpStationVersion(userId, stationName)
	if typeof(energyPerHour) == "number" and energyPerHour > 0 then
		EnergyUsageTracker.AdjustStationLoad(player, energyPerHour)
	end
end

function PlotService.RemoveStationForPlayer(player: Player, stationName: string, uniqueId: string)
	local userId = player.UserId
	local stationCache = PlayerStations[userId]
	if not stationCache then
		return
	end

	local stationInstances = stationCache[stationName]
	if not stationInstances then
		return
	end

	local removed = stationInstances[uniqueId]
	if not removed then
		return
	end

	local occupants: { string } = {}
	if typeof(removed.Residents) == "table" then
		for _, residentName in ipairs(removed.Residents) do
			if typeof(residentName) == "string" then
				occupants[#occupants + 1] = residentName
			end
		end
	end

	stationInstances[uniqueId] = nil
	bumpStationVersion(userId, stationName)

	if next(stationInstances) == nil then
		stationCache[stationName] = nil
	end

	local itemSpec = ItemFinder.FindItemById(removed.Id)
	local energyPerHour = itemSpec and itemSpec.EnergyConsumptionPerHour
	if typeof(energyPerHour) == "number" and energyPerHour > 0 then
		EnergyUsageTracker.AdjustStationLoad(player, -energyPerHour)
	end

	PlotService.StationRemoved:Fire(player, stationName, uniqueId, occupants)
end

function PlotService.GetStationVersion(player: Player, stationType: string): number
	local versionMap = StationScopeVersions[player.UserId]
	if not versionMap then
		return 0
	end
	return versionMap[stationType] or 0
end
return PlotService
