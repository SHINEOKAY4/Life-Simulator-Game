--!strict

local State = require(script.Parent.State)
local StationManager = require(script.Parent.StationManager)

export type ResidentState = any
export type NeedDecision = {
	StationType: string,
	UniqueId: string,
	StationRecord: StationManager.StationRecord,
	ItemSpec: { [string]: any },
	StationModel: Model,
	NeedName: string,
	RestModeOverride: string?,
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
	station.Occupied = true
	if not table.find(station.Residents, residentName) then
		table.insert(station.Residents, residentName)
	end
	local assignment = buildAssignment(player, residentName, resident, decision)
	local actionName = string.format("Auto:%s:%s", decision.StationType, decision.NeedName)
	State.setPending(resident, decision.NeedName)
	State.clearNextEvaluation(resident)
	resident:EnqueueAction(actionName, function(context)
		if context.CancelToken.Cancelled then
			StationManager.releaseStationOccupancy(station, residentName)
			State.setPending(resident, nil)
			return
		end
		local ok, result = (xpcall :: any)(handler, debug.traceback, context, assignment)
		StationManager.releaseStationOccupancy(station, residentName)
		State.setPending(resident, nil)
		if ok then
			State.setNeedCooldown(resident, decision.NeedName)
			return
		end
		warn(string.format("[ResidentAutonomy] Handler for %s failed: %s", decision.StationType, tostring(result)))
		error(result)
	end)
	return true
end

return ActionQueue
