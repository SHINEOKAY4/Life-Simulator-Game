--!strict

local ServerScriptService = game:GetService("ServerScriptService")

local PlotService = require(ServerScriptService.Server.Services.PlotService)
local ResidentMovement = require(ServerScriptService.Server.Utilities.ResidentMovement)

local Types = require(script.Parent.Types)

local ManualOverrideCoordinator = {}

local COLLAPSE_RELEASE_ENERGY = 4

local function releaseStationOccupancy(station: Types.StationRecord, residentName: string)
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

local function forceClearActions(residentState: any, reason: string)
	if typeof(residentState.ForceStopAllActions) == "function" then
		residentState:ForceStopAllActions(reason)
		return
	end
	residentState:CancelCurrentAction(reason)
	residentState:ClearQueuedActions()
	local activeName = residentState.CurrentAction
	if residentState.SetDestination then
		residentState:SetDestination(nil)
	else
		residentState.Destination = nil
	end
	residentState.CurrentAction = nil
	residentState.IsBusy = false
	if residentState.ActionChanged then
		residentState.ActionChanged:Fire(nil)
	end
	if activeName and residentState.ActionCompleted then
		residentState.ActionCompleted:Fire(activeName, false, reason)
	end
	residentState:ResetCancelToken()
end

local function ensureCollapseReleased(residentState: any, timeoutSeconds: number?): (boolean, string?)
	local releaseFn = residentState._EnergyCollapseRelease
	if typeof(releaseFn) ~= "function" then
		return true, nil
	end
	local energyValue = residentState:GetNeed("Energy")
	if typeof(energyValue) ~= "number" then
		return false, "Resident is collapsed"
	end
	local releaseThreshold = COLLAPSE_RELEASE_ENERGY - 0.25
	if energyValue < releaseThreshold then
		return false, "Resident is collapsed"
	end
	releaseFn()
	ResidentMovement.ClearRestPose(residentState)
	local idle = residentState:WaitUntilIdle(timeoutSeconds)
	if idle then
		residentState:ResetCancelToken()
		return true, nil
	end
	forceClearActions(residentState, "ManualOverride")
	ResidentMovement.ClearRestPose(residentState)
	local cleared = residentState:WaitUntilIdle(timeoutSeconds)
	if cleared then
		residentState:ResetCancelToken()
		return true, nil
	end
	return false, "Resident is busy"
end

function ManualOverrideCoordinator.prepareResident(residentState: any, timeoutSeconds: number?): (boolean, string?)
	local collapseReleased, collapseReason = ensureCollapseReleased(residentState, timeoutSeconds)
	if not collapseReleased then
		return false, collapseReason
	end
	residentState:CancelCurrentAction("ManualOverride")
	residentState:ClearQueuedActions()
	local idle = residentState:WaitUntilIdle(timeoutSeconds)
	if not idle then
		forceClearActions(residentState, "ManualOverride")
	else
		residentState:ResetCancelToken()
	end
	residentState:DisableAutomation()
	residentState:ClearQueuedActions()
	return true, nil
end

function ManualOverrideCoordinator.clearExistingOverride(
	player: Player,
	residentState: any,
	residentName: string,
	stationCacheOverride: { [string]: { [string]: Types.StationRecord } }?
)
	local currentOverride = residentState.CurrentOverride
	if typeof(currentOverride) ~= "table" then
		residentState:ClearManualOverrideState()
		return
	end
	local stationType = currentOverride.StationType
	local stationId = currentOverride.StationId
	if typeof(stationType) == "string" and typeof(stationId) == "string" then
		local cache = stationCacheOverride or PlotService.GetStationsForPlayer(player)
		local scope = cache[stationType]
		local stationRecord = scope and scope[stationId]
		if stationRecord then
			releaseStationOccupancy(stationRecord, residentName)
		end
	end
	residentState:ClearManualOverrideState()
end

function ManualOverrideCoordinator.reserveStation(assignment: Types.StationAssignment)
	local station = assignment.StationRecord
	station.Occupied = true
	station.Model = assignment.StationModel
	station.ActiveOverride = assignment.ResidentName
	if not table.find(station.Residents, assignment.ResidentName) then
		table.insert(station.Residents, assignment.ResidentName)
	end
end

function ManualOverrideCoordinator.releaseStation(assignment: Types.StationAssignment)
	releaseStationOccupancy(assignment.StationRecord, assignment.ResidentName)
end

function ManualOverrideCoordinator.enqueueOverrideAction(
	assignment: Types.StationAssignment,
	actionName: string,
	handler: (
		context: { Resident: any, CancelToken: { Cancelled: boolean, Reason: string? } },
		Types.StationAssignment
	) -> (),
	finalize: (boolean, string?) -> ()
)
	local residentState = assignment.ResidentState
	local finalized = false
	local function finalizeOnce(succeeded: boolean, message: string?)
		if finalized then
			return
		end
		finalized = true
		finalize(succeeded, message)
	end

	residentState:EnqueueAction(actionName, function(context)
		local success, result = xpcall(function()
			handler(context, assignment)
		end, debug.traceback)
		if success then
			finalizeOnce(true, nil)
			return
		end
		local message: string
		if typeof(result) == "string" then
			local firstLine = result:match("^[^\n]+")
			message = firstLine or result
		else
			message = tostring(result)
		end
		finalizeOnce(false, message)
		error(result)
	end, function()
		if not finalized then
			finalizeOnce(false, "Cancelled")
		end
	end)
end

return ManualOverrideCoordinator
