--!strict

local ServerScriptService = game:GetService("ServerScriptService")

local PlotService = require(ServerScriptService.Server.Services.PlotService)
local DirectActionService = require(ServerScriptService.Server.Services.DirectActionService)
local State = require(script.Parent.State)
local Constants = require(script.Parent.Constants)

export type ResidentState = any

local Utils = {}

function Utils.isNight(clockTime: number): boolean
	local circadian = State.getCircadian()
	local nightStart = circadian.NightStart
	local dayStart = circadian.DayStart
	if nightStart <= dayStart then
		return clockTime >= nightStart and clockTime < dayStart
	end
	return clockTime >= nightStart or clockTime < dayStart
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
	if State.getPending(resident) ~= nil then
		return false
	end
	return true
end

function Utils.preemptRoamForDirectSocial(resident: ResidentState)
	if State.getPending(resident) ~= Constants.ROAM_ACTION_NAME then
		return
	end
	resident:CancelCurrentAction("DirectSocialInvite")
	resident:ClearQueuedActions()
	State.setPending(resident, nil)
end

function Utils.hasBlockingCriticalNeed(
	player: Player,
	resident: ResidentState,
	ignoreNeed: string?,
	stationCache: { [string]: any }?
): boolean
	local needs = State.getNeeds()
	local cache = stationCache or PlotService.GetStationsForPlayer(player)
	for needName, def in pairs(needs) do
		if needName ~= ignoreNeed then
			local value = resident:GetNeed(needName)
			if value <= def.Critical then
				if State.SurvivalNeeds[needName] then
					return true
				end
				local stationType = State.NeedToStationType[needName]
				if stationType then
					if not DirectActionService.HasHandler(stationType) then
						return true
					end
					if cache then
						local scope = cache[stationType]
						if scope and next(scope) ~= nil then
							return true
						end
					end
				else
					return true
				end
			end
		end
	end
	return false
end

function Utils.detectCriticalNeed(resident: ResidentState): string?
	for needName, def in pairs(State.getNeeds()) do
		local value = resident:GetNeed(needName)
		if value <= def.Critical then
			return string.format("NeedUrgent:%s", needName)
		end
	end
	return nil
end

local function hasStationsForNeed(cache: { [string]: any }?, stationType: string): boolean
	if not cache then
		return false
	end
	local scope = cache[stationType]
	return scope ~= nil and next(scope) ~= nil
end

function Utils.shouldBlockRoam(player: Player, resident: ResidentState, stationCache: { [string]: any }?): boolean
	local needs = State.getNeeds()
	local cache = stationCache or PlotService.GetStationsForPlayer(player)
	for needName, def in pairs(needs) do
		local value = resident:GetNeed(needName)
		if value <= def.Critical then
			if State.SurvivalNeeds[needName] then
				return true
			end
			local stationType = State.NeedToStationType[needName]
			if stationType then
				if DirectActionService.HasHandler(stationType) and hasStationsForNeed(cache, stationType) then
					return true
				elseif not DirectActionService.HasHandler(stationType) then
					return true
				end
			else
				return true
			end
		end
	end
	return false
end

function Utils.ensureSocialSatisfaction(resident: ResidentState)
	local needs = State.getNeeds()
	local socialDef = needs.Social
	if not socialDef then
		return
	end
	local value = resident:GetNeed("Social")
	if value >= socialDef.Low then
		return
	end
	local target = math.min(socialDef.Low + socialDef.Hysteresis, socialDef.Max)
	resident:SetNeed("Social", target)
end

return Utils
