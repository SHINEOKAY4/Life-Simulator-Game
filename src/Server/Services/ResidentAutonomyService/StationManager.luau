--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local PlotService = require(ServerScriptService.Server.Services.PlotService)
local StationActionRegistry = require(ServerScriptService.Server.Modules.StationActionRegistry)
local PlotFinder = require(ReplicatedStorage.Shared.Utilities.PlotFinder)
local ItemFinder = require(ReplicatedStorage.Shared.Utilities.ItemFinder)
local BillingConstants = require(ReplicatedStorage.Shared.Definitions.BillingConstants)
local State = require(script.Parent.State)

export type StationRecord = {
	Id: string,
	Residents: { [number]: string },
	Occupied: boolean,
	Model: Model?,
	ActiveOverride: string?,
}

local handlerCache: { [string]: any } = {}
local POWER_OUTAGE_OVERRIDE = BillingConstants.PowerOutageOverrideKey or "BillingPowerOutage"

local StationManager = {}

local function resolveItemSpec(station: StationRecord)
	local cached = State.ItemSpecCache[station.Id]
	if cached ~= nil then
		return cached
	end
	local itemSpec = ItemFinder.FindItemById(station.Id)
	if itemSpec ~= nil then
		State.ItemSpecCache[station.Id] = itemSpec
	end
	return itemSpec
end

local function computeStationCapacity(itemSpec: { [string]: any }?): number
	local capacity = 1
	if typeof(itemSpec) == "table" then
		local maxOccupancy = itemSpec.maxOccupancy
		if typeof(maxOccupancy) == "number" and maxOccupancy > 0 then
			capacity = math.max(1, math.floor(maxOccupancy))
		end
	end
	return capacity
end

local function stationHasSeatAvailable(
	station: StationRecord,
	residentName: string?,
	itemSpec: { [string]: any }?
): boolean
	local occupants = station.Residents
	if typeof(occupants) ~= "table" then
		return true
	end
	if residentName and table.find(occupants, residentName) then
		return true
	end
	local capacity = computeStationCapacity(itemSpec)
	return #occupants < capacity
end

local function updatePowerOverride(player: Player, station: StationRecord, itemSpec: { [string]: any }?)
	local outageActive = player:GetAttribute("BillingPowerOutageActive") == true
	local energyPerHour = itemSpec and itemSpec.EnergyConsumptionPerHour
	local requiresPower = typeof(energyPerHour) == "number" and energyPerHour > 0
	if outageActive then
		if requiresPower then
			station.ActiveOverride = POWER_OUTAGE_OVERRIDE
		end
	elseif station.ActiveOverride == POWER_OUTAGE_OVERRIDE then
		station.ActiveOverride = nil
	end
end

function StationManager.hasVacantStation(
	player: Player,
	stationType: string,
	residentName: string?,
	stationCacheOverride: { [string]: any }?
): boolean
	if not player then
		return false
	end
	local stationCache = stationCacheOverride or PlotService.GetStationsForPlayer(player)
	local stationMap = stationCache[stationType] :: { [string]: StationRecord }?
	if not stationMap then
		return false
	end
	if next(stationMap) == nil then
		return false
	end
	for _, station in pairs(stationMap) do
		if station then
			local itemSpec = resolveItemSpec(station)
			updatePowerOverride(player, station, itemSpec)
			local activeOverride = station.ActiveOverride
			if activeOverride == nil or (residentName and activeOverride == residentName) then
				if stationHasSeatAvailable(station, residentName, itemSpec) then
					return true
				end
			end
		end
	end
	return false
end

local function resolveStationModelForPlayer(player: Player, uniqueId: string): Model?
	local plotIndex = player:GetAttribute("OwnedPlotIndex")
	if typeof(plotIndex) ~= "number" then
		return nil
	end
	local plotModel = PlotFinder.FindPlot(plotIndex)
	if not plotModel then
		return nil
	end
	local container = plotModel:FindFirstChild("Container")
	if not container then
		return nil
	end
	local model = container:FindFirstChild(uniqueId)
	if model and model:IsA("Model") then
		return model
	end
	return nil
end

function StationManager.getStationHandler(stationType: string)
	local cached = handlerCache[stationType]
	if cached ~= nil then
		return cached
	end
	local handler = StationActionRegistry.GetHandler(stationType)
	handlerCache[stationType] = handler
	return handler
end

local function getStationIterator(
	userId: number,
	stationType: string,
	stationMap: { [string]: StationRecord }?,
	stationVersion: number
): { version: number, order: { string }, index: number }?
	if not stationMap then
		local perUser = State.StationIteratorState[userId]
		if perUser then
			perUser[stationType] = nil
			if next(perUser) == nil then
				State.StationIteratorState[userId] = nil
			end
		end
		return nil
	end
	local perUser = State.StationIteratorState[userId]
	if not perUser then
		perUser = {}
		State.StationIteratorState[userId] = perUser
	end
	local state = perUser[stationType]
	if not state or state.version ~= stationVersion then
		local order = {}
		local count = 0
		for uniqueId in pairs(stationMap) do
			if typeof(uniqueId) == "string" then
				count += 1
				order[count] = uniqueId
			end
		end
		local newState = {
			version = stationVersion,
			order = order,
			index = 1,
		}
		perUser[stationType] = newState
		state = newState
	end
	return state
end

type StationFilter = (string, StationRecord, { [string]: any }?, Model?) -> boolean

function StationManager.findAvailableStation(
	player: Player,
	stationType: string,
	residentName: string,
	stationCacheOverride: { [string]: any }?,
	filter: StationFilter?
): (string?, StationRecord?, { [string]: any }?, Model?)
	local stationCache = stationCacheOverride or PlotService.GetStationsForPlayer(player)
	local stationMap = stationCache[stationType] :: { [string]: StationRecord }?
	local stationVersion = PlotService.GetStationVersion(player, stationType)
	local iterator = getStationIterator(player.UserId, stationType, stationMap, stationVersion)
	if not iterator then
		return nil, nil, nil, nil
	end
	local order = iterator.order
	local total = #order
	if total == 0 then
		return nil, nil, nil, nil
	end
	for _ = 1, total do
		local uniqueId = order[iterator.index]
		iterator.index += 1
		if iterator.index > total then
			iterator.index = 1
		end
		if uniqueId and stationMap then
			local station = stationMap[uniqueId] :: StationRecord?
			if station and not table.find(station.Residents, residentName) then
				local itemSpec = resolveItemSpec(station)
				if itemSpec then
					updatePowerOverride(player, station, itemSpec)
				else
					updatePowerOverride(player, station, nil)
				end

				local activeOverride = station.ActiveOverride
				if activeOverride == nil or activeOverride == residentName then
					if stationHasSeatAvailable(station, residentName, itemSpec) then
						if not station.Model then
							station.Model = resolveStationModelForPlayer(player, uniqueId)
						end
						local model = station.Model
						if model then
							if filter and not filter(uniqueId, station, itemSpec, model) then
								continue
							end
							return uniqueId, station, itemSpec, model
						end
					end
				end
			end
		end
	end
	return nil, nil, nil, nil
end

function StationManager.releaseStationOccupancy(station: StationRecord, residentName: string)
	local index = table.find(station.Residents, residentName)
	if index then
		table.remove(station.Residents, index)
	end
	if #station.Residents == 0 then
		station.Occupied = false
		station.Model = nil
	end
	if station.ActiveOverride == residentName then
		station.ActiveOverride = nil
	end
end

function StationManager.getStationById(
	player: Player,
	stationType: string,
	uniqueId: string,
	stationCacheOverride: { [string]: any }?
): (StationRecord?, { [string]: any }?, Model?)
	local stationCache = stationCacheOverride or PlotService.GetStationsForPlayer(player)
	local stationMap = stationCache[stationType] :: { [string]: StationRecord }?
	if not stationMap then
		return nil, nil, nil
	end
	local station = stationMap[uniqueId]
	if not station then
		return nil, nil, nil
	end
	if not station.Model then
		station.Model = resolveStationModelForPlayer(player, uniqueId)
	end
	local itemSpec = State.ItemSpecCache[station.Id]
	if itemSpec == nil then
		itemSpec = ItemFinder.FindItemById(station.Id)
		if itemSpec then
			State.ItemSpecCache[station.Id] = itemSpec
		end
	end
	if not itemSpec then
		return nil, nil, station.Model
	end
	return station, itemSpec, station.Model
end

function StationManager.isStationBlockedByOutage(
	player: Player,
	stationType: string,
	stationCacheOverride: { [string]: any }?
): boolean
	if player:GetAttribute("BillingPowerOutageActive") ~= true then
		return false
	end

	local stationCache = stationCacheOverride or PlotService.GetStationsForPlayer(player)
	local stationMap = stationCache[stationType] :: { [string]: StationRecord }?
	if not stationMap then
		return false
	end
	local nextStation = next(stationMap)
	if nextStation == nil then
		return false
	end

	local anyPowerRequired = false
	for _, station in pairs(stationMap) do
		local itemSpec = State.ItemSpecCache[station.Id]
		if itemSpec == nil then
			itemSpec = ItemFinder.FindItemById(station.Id)
			if itemSpec then
				State.ItemSpecCache[station.Id] = itemSpec
			end
		end
		if not itemSpec then
			return false
		end
		local energyPerHour = itemSpec.EnergyConsumptionPerHour
		if typeof(energyPerHour) == "number" and energyPerHour > 0 then
			anyPowerRequired = true
		else
			return false
		end
	end

	return anyPowerRequired
end

return StationManager
