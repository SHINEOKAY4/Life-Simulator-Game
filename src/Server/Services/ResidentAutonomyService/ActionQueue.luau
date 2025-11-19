--!strict

local ServerScriptService = game:GetService("ServerScriptService")

local State = require(script.Parent.State)
local StationManager = require(script.Parent.StationManager)
local NeedEffects = require(ServerScriptService.Server.Utilities.NeedEffects)

export type ResidentState = any
export type NeedDecision = {
	StationType: string,
	UniqueId: string,
	StationRecord: StationManager.StationRecord,
	ItemSpec: { [string]: any },
	StationModel: Model,
	NeedName: string,
	RestModeOverride: string?,
	ActionMode: string?,
	TargetContainerId: string?,
	PreparedMealId: string?,
	PreparedMealServings: number?,
	PreparedMealHungerPerPortion: number?,
}

local ActionQueue = {}

local function buildAssignment(player: Player, residentName: string, resident: ResidentState, decision: NeedDecision)
	local assignment = {
		Player = player,
		ResidentName = residentName,
		ResidentState = resident,
		StationType = decision.StationType,
		StationId = decision.UniqueId,
		ItemId = decision.StationRecord.Id,
		ItemSpec = decision.ItemSpec,
		StationRecord = decision.StationRecord,
		StationModel = decision.StationModel,
		NeedName = decision.NeedName,
		ManualOverride = false,
		ActionMode = decision.ActionMode,
		TargetContainerId = decision.TargetContainerId,
		PreparedMealId = decision.PreparedMealId,
		PreparedMealServings = decision.PreparedMealServings,
		PreparedMealHungerPerPortion = decision.PreparedMealHungerPerPortion,
	}
	if decision.RestModeOverride then
		assignment.RestModeOverride = decision.RestModeOverride
	end
	return assignment
end

function ActionQueue.enqueueNeedAction(
	player: Player,
	residentName: string,
	resident: ResidentState,
	decision: NeedDecision
): boolean
	local handler = StationManager.getStationHandler(decision.StationType)
	if not handler then
		return false
	end

	local station = decision.StationRecord
	local uniqueId = decision.UniqueId
	local itemSpec = decision.ItemSpec
	local stationModel = decision.StationModel
	local actionMode = decision.ActionMode

	station.Occupied = true
	if not table.find(station.Residents, residentName) then
		table.insert(station.Residents, residentName)
	end

	State.addPendingStationReservation(resident, station, residentName)

	local pendingNeed = decision.NeedName
	State.setPending(resident, pendingNeed)

	local consumedReservation = false
	local releasedReservation = false

	local function clearPending()
		if pendingNeed and State.getPending(resident) == pendingNeed then
			State.setPending(resident, nil)
		end
	end

	local function markReservationConsumed()
		if consumedReservation then
			return
		end
		consumedReservation = true
		State.consumePendingStationReservation(resident, station, residentName)
	end

	local function releaseReservation()
		if releasedReservation then
			return
		end
		releasedReservation = true
		if not consumedReservation then
			markReservationConsumed()
		end
		StationManager.releaseStationOccupancy(station, residentName)
		clearPending()
	end

	local assignment = buildAssignment(player, residentName, resident, decision)
	assignment.StationRecord = station
	assignment.ItemSpec = itemSpec
	assignment.StationModel = stationModel
	assignment.StationId = uniqueId
	assignment.ItemId = station.Id
	assignment.ActionMode = actionMode

	local actionName = string.format("Auto:%s:%s", decision.StationType, decision.NeedName)
	State.clearNextEvaluation(resident)
	resident:EnqueueAction(actionName, function(context)
		markReservationConsumed()
		if context.CancelToken.Cancelled then
			releaseReservation()
			return
		end
		local ok, result = (xpcall :: any)(handler, debug.traceback, context, assignment)
		releaseReservation()
		if ok then
			State.setNeedCooldown(resident, decision.NeedName)
			return
		end
		local message = if typeof(result) == "string" then result else tostring(result)
		local abortReason = NeedEffects.ParseAbortReason(message)
		if abortReason then
			local now = os.clock()
			if typeof(abortReason) == "string" and abortReason:sub(1, 11) == "NeedUrgent:" then
				local urgentNeed = abortReason:sub(12)
				if urgentNeed ~= "" then
					State.setForcedNeed(resident, urgentNeed, now)
				end
			end
			State.registerInterruptedNeed(resident, decision.NeedName, now)
			return
		end
		warn(string.format("[ResidentAutonomy] Handler for %s failed: %s", decision.StationType, message))
		error(result)
	end, releaseReservation)
	return true
end

function ActionQueue.enqueueFallbackAction(
	player: Player,
	residentName: string,
	resident: ResidentState,
	actionType: string,
	itemSpec: { [string]: any }
): boolean
	local handler = StationManager.getStationHandler(actionType)
	if not handler then
		return false
	end

	local actionName = string.format("Fallback:%s", actionType)
	State.clearNextEvaluation(resident)

	resident:EnqueueAction(actionName, function(context)
		if context.CancelToken.Cancelled then
			return
		end

		local assignment = {
			Player = player,
			ResidentName = residentName,
			ResidentState = resident,
			StationType = actionType,
			StationId = "Fallback",
			ItemSpec = itemSpec,
			StationRecord = nil,
			StationModel = nil,
			NeedName = nil,
			ManualOverride = false,
		}

		local ok, result = (xpcall :: any)(handler, debug.traceback, context, assignment)
		if not ok then
			warn(string.format("[ResidentAutonomy] Fallback handler for %s failed: %s", actionType, tostring(result)))
		end
	end)

	return true
end

return ActionQueue
