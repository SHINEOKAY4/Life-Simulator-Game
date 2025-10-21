--!strict
--ServerScriptService/Server/Services/DirectActionService.lua

local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlotService = require(ServerScriptService.Server.Services.PlotService)
local ResidentService = require(ServerScriptService.Server.Services.ResidentService)
local PlotFinder = require(ReplicatedStorage.Shared.Utilities.PlotFinder)
local ItemFinder = require(ReplicatedStorage.Shared.Utilities.ItemFinder)
local ResidentMovement = require(ServerScriptService.Server.Utilities.ResidentMovement)
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
	NeedName: string?,
	RestModeOverride: string?,
}

type StationCache = { [string]: { [string]: StationRecord } }

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

local MANUAL_MOVE_TIMEOUT_SECONDS = 25
local COLLAPSE_RELEASE_ENERGY = 4

local function isFiniteNumber(value: number): boolean
	return value == value and value > -math.huge and value < math.huge
end

local function isFiniteVector3(value: Vector3): boolean
	return isFiniteNumber(value.X) and isFiniteNumber(value.Y) and isFiniteNumber(value.Z)
end

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

local function clearExistingManualOverride(
	player: Player,
	residentState: any,
	residentName: string,
	stationCacheOverride: StationCache?
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

local function prepareResidentForOverride(residentState: any, timeoutSeconds: number?): (boolean, string?)
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

	ResidentsPackets.RequestResidentMove.OnServerInvoke = function(
		player: Player,
		residentName: string,
		targetPosition: Vector3
	)
		return DirectActionService.MoveResidentToWorldPosition(player, residentName, targetPosition)
	end
end

function DirectActionService.AssignStationToResident(player: Player, residentName: string, uniqueId: string)
	if type(residentName) ~= "string" or residentName == "" then
		return false, "Invalid resident name"
	end
	if type(uniqueId) ~= "string" or uniqueId == "" then
		return false, "Invalid station id"
	end
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
	if residentState.IsOnShift then
		return false, "Resident is currently working"
	end

	local collapseActive = typeof(residentState._EnergyCollapseRelease) == "function"
	if collapseActive then
		local energyValue = residentState:GetNeed("Energy")
		if typeof(energyValue) ~= "number" or energyValue < COLLAPSE_RELEASE_ENERGY then
			return false, "Resident is collapsed"
		end
	end

	local prepared, reason = prepareResidentForOverride(residentState, 3)
	if not prepared then
		return false, reason or "Unable to prepare resident for override"
	end

	clearExistingManualOverride(player, residentState, residentName, playerStations)

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
		NeedName = nil,
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

function DirectActionService.MoveResidentToWorldPosition(player: Player, residentName: string, targetPosition: Vector3)
	if type(residentName) ~= "string" or residentName == "" then
		return false, "Invalid resident name"
	end

	if typeof(targetPosition) ~= "Vector3" or not isFiniteVector3(targetPosition) then
		return false, "Invalid target position"
	end

	local residentState = ResidentService.GetResident(player, residentName)
	if not residentState then
		return false, "Resident not found"
	end
	if residentState.IsOnShift then
		return false, "Resident is currently working"
	end

	local collapseActive = typeof(residentState._EnergyCollapseRelease) == "function"
	if collapseActive then
		local energyValue = residentState:GetNeed("Energy")
		if typeof(energyValue) ~= "number" or energyValue < COLLAPSE_RELEASE_ENERGY then
			return false, "Resident is collapsed"
		end
	end

	local prepared, reason = prepareResidentForOverride(residentState, 3)
	if not prepared then
		return false, reason or "Resident is busy"
	end

	clearExistingManualOverride(player, residentState, residentName)

	residentState:SetManualOverrideState({ Mode = "ManualMove", TargetPosition = targetPosition })

	residentState:EnqueueAction("ManualOverride:Move", function(context)
		local releaseCollapse = residentState._EnergyCollapseRelease
		if typeof(releaseCollapse) == "function" then
			releaseCollapse()
		end
		ResidentMovement.ClearRestPose(residentState)
		local ok, result = pcall(ResidentMovement.GoToWorldPosition, residentState, targetPosition, {
			CancelToken = context.CancelToken,
			TimeoutSeconds = MANUAL_MOVE_TIMEOUT_SECONDS,
			DebugName = "ManualMove",
		})

		residentState:ClearManualOverrideState()
		residentState:EnableAutomation()

		if not ok then
			error(result)
		end

		if result then
			return
		end

		if context.CancelToken.Cancelled then
			error(context.CancelToken.Reason or "Movement cancelled")
		end

		error("Resident could not reach the destination")
	end)

	return true, "Movement queued"
end

return DirectActionService
