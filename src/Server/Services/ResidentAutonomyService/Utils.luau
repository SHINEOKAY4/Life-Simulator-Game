--!strict

local State = require(script.Parent.State)

export type ResidentState = any

local Utils = {}

function Utils.isNight(clockTime: number): boolean
	-- Simple check, can use config if needed
	return clockTime >= 22 or clockTime < 6
end

function Utils.shouldEvaluate(resident: ResidentState): boolean
	if resident == nil then
		return false
	end
	if not resident.AutoActionsEnabled then
		return false
	end
	if resident.CurrentOverride ~= nil then
		return false
	end
	if resident.IsBusy then
		return false
	end
	local queue = resident.ActionQueue
	if not queue or not queue:IsEmpty() then
		return false
	end
	-- Check if pending action via State (compatibility)
	if State.getPending and State.getPending(resident) ~= nil then
		return false
	end
	return true
end

return Utils
