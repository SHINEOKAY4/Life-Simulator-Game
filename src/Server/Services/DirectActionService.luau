--!strict
--ServerScriptService/Server/Services/DirectActionService.lua

local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlotService = require(ServerScriptService.Server.Services.PlotService)
local ResidentService = require(ServerScriptService.Server.Services.ResidentService)
local PlotFinder = require(ReplicatedStorage.Shared.Utilities.PlotFinder)
local ItemFinder = require(ReplicatedStorage.Shared.Utilities.ItemFinder)
local ResidentsPackets = require(ReplicatedStorage.Network.ResidentsPackets)
local GoodSignal = require(ReplicatedStorage.Packages.GoodSignal)

type StationRecord = {
	Id: string,
	Residents: { string },
	Occupied: boolean,
	Model: Model?,
	ActiveOverride: string?,
}

type StationAssignment = {
	Player: Player,
	ResidentName: string,
	ResidentState: any,
	StationType: string,
	StationId: string,
	ItemId: string,
	ItemSpec: { [string]: any },
	StationRecord: StationRecord,
	StationModel: Model,
	RestModeOverride: string?,
}

local DirectActionService = {}
DirectActionService.OverrideStarted = GoodSignal.new()
DirectActionService.OverrideCompleted = GoodSignal.new()
DirectActionService.OverrideFailed = GoodSignal.new()

local OverrideHandlers: {
	[string]: (
		context: { Resident: any, CancelToken: { Cancelled: boolean, Reason: string? } },
		StationAssignment
	) -> (),
} =
	{}

function DirectActionService.GetHandler(stationType: string)
	return OverrideHandlers[stationType]
end

function DirectActionService.HasHandler(stationType: string): boolean
	return OverrideHandlers[stationType] ~= nil
end

local function releaseStationOccupancy(station: StationRecord, residentName: string)
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

local function finalizeAssignment(assignment: StationAssignment, succeeded: boolean, message: string?)
	releaseStationOccupancy(assignment.StationRecord, assignment.ResidentName)
	assignment.ResidentState:ClearManualOverrideState()
	assignment.ResidentState:EnableAutomation()
	if succeeded then
		DirectActionService.OverrideCompleted:Fire(assignment, message)
	else
		DirectActionService.OverrideFailed:Fire(assignment, message)
	end
end

local function resolveHandler(stationType: string)
	return OverrideHandlers[stationType]
		or function(context, _assignment)
			if context.CancelToken.Cancelled then
				return
			end
			-- Override handlers can be registered via DirectActionService.RegisterHandler.
		end
end

local function enqueueOverrideAction(assignment: StationAssignment)
	local residentState = assignment.ResidentState
	local handler = resolveHandler(assignment.StationType)
	local actionName = string.format("ManualOverride:%s", assignment.StationType)

	residentState:EnqueueAction(actionName, function(context)
		local ok, result = xpcall(handler, debug.traceback, context, assignment)
		finalizeAssignment(assignment, ok, if ok then nil else result)
		if not ok then
			error(result)
		end
	end)
end

local function prepareResidentForOverride(residentState: any, timeoutSeconds: number?): (boolean, string?)
	residentState:CancelCurrentAction("ManualOverride")
	local idle = residentState:WaitUntilIdle(timeoutSeconds)
	if not idle then
		residentState:ResetCancelToken()
		return false, "Resident is busy"
	end
	residentState:ClearQueuedActions()
	residentState:ResetCancelToken()
	residentState:DisableAutomation()
	return true, nil
end

function DirectActionService.RegisterHandler(
	stationType: string,
	handler: (
		context: { Resident: any, CancelToken: { Cancelled: boolean, Reason: string? } },
		StationAssignment
	) -> ()
)
	OverrideHandlers[stationType] = handler
end

function DirectActionService.Init()
	ResidentsPackets.RequestAssignStation.OnServerInvoke = function(
		player: Player,
		residentName: string,
		uniqueId: string
	)
		local success, message = DirectActionService.AssignStationToResident(player, residentName, uniqueId)
		return success, message
	end
end

function DirectActionService.AssignStationToResident(player: Player, residentName: string, uniqueId: string)
	local plotIndex = player:GetAttribute("OwnedPlotIndex") :: number
	if not plotIndex then
		return false, "Player does not own a plot"
	end

	local plotModel = PlotFinder.FindPlot(plotIndex)
	local containerFolder = plotModel and plotModel:FindFirstChild("Container")
	if not containerFolder then
		return false, "No containers found on plot"
	end

	local itemModel = containerFolder:FindFirstChild(uniqueId) :: Model?
	if not itemModel then
		return false, "Item not found in containers"
	end

	local itemId = itemModel:GetAttribute("ItemId") :: string?
	if not itemId then
		return false, "ItemId attribute not found on item model"
	end

	local itemSpec = ItemFinder.FindItemById(itemId)
	if not itemSpec then
		return false, "Item specification not found"
	end

	local stationType = itemSpec.StationType
	if not stationType then
		return false, "Item is not a station"
	end

	local playerStations = PlotService.GetStationsForPlayer(player)
	local stationScope = playerStations[stationType]
	if not stationScope then
		return false, "Station not found on player's plot"
	end

	local resolvedStation = stationScope[uniqueId]
	if not resolvedStation then
		return false, "Station with the given uniqueId not in player's station scope"
	end

	if table.find(resolvedStation.Residents, residentName) then
		return false, "Resident already assigned to this station"
	end

	local maxOccupancy = itemSpec.maxOccupancy
	if typeof(maxOccupancy) == "number" and maxOccupancy > 0 and #resolvedStation.Residents >= maxOccupancy then
		return false, "Station is at full capacity"
	end

	local residentState = ResidentService.GetResident(player, residentName)
	if not residentState then
		return false, "Resident not found"
	end

	local prepared, reason = prepareResidentForOverride(residentState, 3)
	if not prepared then
		return false, reason or "Unable to prepare resident for override"
	end

	resolvedStation.Occupied = true
	resolvedStation.Model = itemModel
	resolvedStation.ActiveOverride = residentName
	if not table.find(resolvedStation.Residents, residentName) then
		table.insert(resolvedStation.Residents, residentName)
	end

	local assignment: StationAssignment = {
		Player = player,
		ResidentName = residentName,
		ResidentState = residentState,
		StationType = stationType,
		StationId = uniqueId,
		ItemId = itemId,
		ItemSpec = itemSpec,
		StationRecord = resolvedStation,
		StationModel = itemModel,
		RestModeOverride = nil,
	}

	residentState:SetManualOverrideState({
		StationType = stationType,
		StationId = uniqueId,
		ItemId = itemId,
	})

	DirectActionService.OverrideStarted:Fire(assignment)
	enqueueOverrideAction(assignment)
	return true, "Manual override queued"
end

return DirectActionService
