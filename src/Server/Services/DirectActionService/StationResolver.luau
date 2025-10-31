--!strict

local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlotFinder = require(ReplicatedStorage.Shared.Utilities.PlotFinder)
local ItemFinder = require(ReplicatedStorage.Shared.Utilities.ItemFinder)
local NeedConfig = require(ReplicatedStorage.Shared.Configurations.NeedConfig)
local ResidentChat = require(ServerScriptService.Server.Utilities.ResidentChat)
local PlotService = require(ServerScriptService.Server.Services.PlotService)
local ResidentService = require(ServerScriptService.Server.Services.ResidentService)

local Constants = require(script.Parent.Constants)
local Types = require(script.Parent.Types)

local StationNeedMap = Constants.StationNeedMap
local StationKindLabels = Constants.StationKindLabels
local POWER_OUTAGE_OVERRIDE = Constants.POWER_OUTAGE_OVERRIDE
local POWER_OUTAGE_MESSAGE = Constants.POWER_OUTAGE_MESSAGE

local StationResolver = {}

local function resolveStationDisplayName(itemSpec: { [string]: any }?, stationType: string): string?
	if itemSpec then
		local displayName = itemSpec.DisplayName
		if typeof(displayName) == "string" and displayName ~= "" then
			return displayName
		end
		local itemName = itemSpec.Name
		if typeof(itemName) == "string" and itemName ~= "" then
			return itemName
		end
		local tags = itemSpec.Tags
		if typeof(tags) == "table" then
			for _, tag in ipairs(tags) do
				if typeof(tag) == "string" and tag ~= "" then
					return tag
				end
			end
		end
	end
	return StationKindLabels[stationType]
end

local function isNeedAtMax(residentState: any, needName: string, needDef: NeedConfig.NeedDef): boolean
	if typeof(residentState) ~= "table" then
		return false
	end
	local getter = residentState.GetNeed
	if typeof(getter) ~= "function" then
		return false
	end
	local value = getter(residentState, needName)
	if typeof(value) ~= "number" then
		return false
	end
	return value >= needDef.Max
end

local function resolveDefaultActionMode(stationType: string, uniqueId: string): (string?, string?)
	if stationType == "FoodStorage" then
		return "Snack", uniqueId
	end
	return nil, nil
end

function StationResolver.Resolve(
	player: Player,
	residentName: string,
	uniqueId: string
): (Types.StationAssignment?, string?)
	local plotIndex = player:GetAttribute("OwnedPlotIndex") :: number?
	if not plotIndex then
		return nil, "Player does not own a plot"
	end

	local plotModel = PlotFinder.FindPlot(plotIndex)
	if not plotModel then
		return nil, "Plot not found"
	end

	local containerFolder = plotModel:FindFirstChild("Container")
	if not containerFolder then
		return nil, "No containers found on plot"
	end

	local itemModel = containerFolder:FindFirstChild(uniqueId) :: Model?
	if not itemModel then
		return nil, "Item not found in containers"
	end

	local itemId = itemModel:GetAttribute("ItemId") :: string?
	if not itemId then
		return nil, "ItemId attribute not found on item model"
	end

	local itemSpec = ItemFinder.FindItemById(itemId)
	if not itemSpec then
		return nil, "Item specification not found"
	end

	local stationType = itemSpec.StationType
	if not stationType then
		return nil, "Item is not a station"
	end

	local primaryNeed = StationNeedMap[stationType]
	local primaryNeedDef = if primaryNeed then NeedConfig.Needs[primaryNeed] else nil

	local playerStations = PlotService.GetStationsForPlayer(player)
	local stationScope = playerStations[stationType]
	if not stationScope then
		return nil, "Station not found on player's plot"
	end

	local stationRecord = stationScope[uniqueId]
	if not stationRecord then
		return nil, "Station with the given uniqueId not in player's station scope"
	end

	local outageActive = player:GetAttribute("BillingPowerOutageActive") == true
	local energyPerHour = itemSpec.EnergyConsumptionPerHour

	if stationRecord.ActiveOverride == POWER_OUTAGE_OVERRIDE and not outageActive then
		stationRecord.ActiveOverride = nil
	end

	if outageActive then
		if typeof(energyPerHour) == "number" and energyPerHour > 0 then
			stationRecord.ActiveOverride = POWER_OUTAGE_OVERRIDE
			return nil, POWER_OUTAGE_MESSAGE
		end
	end

	if stationRecord.ActiveOverride == POWER_OUTAGE_OVERRIDE then
		return nil, POWER_OUTAGE_MESSAGE
	end

	if table.find(stationRecord.Residents, residentName) then
		return nil, "Resident already assigned to this station"
	end

	local maxOccupancy = itemSpec.maxOccupancy
	if typeof(maxOccupancy) == "number" and maxOccupancy > 0 and #stationRecord.Residents >= maxOccupancy then
		return nil, "Station is at full capacity"
	end

	local residentState = ResidentService.GetResident(player, residentName)
	if not residentState then
		return nil, "Resident not found"
	end
	if residentState.IsOnShift then
		return nil, "Resident is currently working"
	end

	if primaryNeed and primaryNeedDef and isNeedAtMax(residentState, primaryNeed, primaryNeedDef) then
		ResidentChat.ShowInterrupt(residentState, "NeedFull:" .. primaryNeed, {
			StationType = stationType,
			StationName = resolveStationDisplayName(itemSpec, stationType),
			StationId = uniqueId,
			NeedName = primaryNeed,
			Player = player,
		})
		return nil, "Need already satisfied"
	end

	local actionMode, targetContainerId = resolveDefaultActionMode(stationType, uniqueId)

	local assignment: Types.StationAssignment = {
		Player = player,
		ResidentName = residentName,
		ResidentState = residentState,
		StationType = stationType,
		StationId = uniqueId,
		ItemId = itemId,
		ItemSpec = itemSpec,
		StationRecord = stationRecord,
		StationModel = itemModel,
		NeedName = primaryNeed,
		RestModeOverride = nil,
		ManualOverride = true,
		ActionMode = actionMode,
		TargetContainerId = targetContainerId,
		PreparedMealId = nil,
		PreparedMealServings = nil,
		PreparedMealHungerPerPortion = nil,
	}

	return assignment, nil
end

return StationResolver
