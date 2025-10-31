--!strict

local ServerScriptService = game:GetService("ServerScriptService")

local PlotService = require(ServerScriptService.Server.Services.PlotService)
local DirectActionService = require(ServerScriptService.Server.Services.DirectActionService)
local KitchenService = require(ServerScriptService.Server.Services.KitchenService)
local StationManager = require(ServerScriptService.Server.Services.ResidentAutonomyService.StationManager)
local State = require(script.Parent.State)
local Constants = require(script.Parent.Constants)

export type ResidentState = any

local Utils = {}

local function hasStationsForNeed(cache: { [string]: any }?, stationType: string): boolean
	if not cache then
		return false
	end
	local scope = cache[stationType]
	return scope ~= nil and next(scope) ~= nil
end

local function hungerHasActionablePath(player: Player?, cache: { [string]: any }?, residentName: string?): boolean
	if player == nil then
		return false
	end
	local stationTypes = State.getStationTypesForNeed("Hunger")
	if #stationTypes == 0 then
		return false
	end

	local cookStationType: string? = nil
	local storageStationType: string? = nil
	for _, stationType in ipairs(stationTypes) do
		if stationType == "CookStation" then
			cookStationType = stationType
		elseif stationType == "FoodStorage" then
			storageStationType = stationType
		end
	end
	if not cookStationType then
		cookStationType = stationTypes[1]
	end

	local residentId = if typeof(residentName) == "string" and residentName ~= "" then residentName else ""

	local function stationAvailable(stationType: string?, filter)
		if not stationType then
			return false
		end
		if not hasStationsForNeed(cache, stationType) then
			return false
		end
		local uniqueId = StationManager.findAvailableStation(player, stationType, residentId, cache, filter)
		return uniqueId ~= nil
	end

	if cookStationType then
		local canCook = KitchenService.HasCookableRecipe(player)
		if canCook and stationAvailable(cookStationType, nil) then
			return true
		end
	end

	if storageStationType then
		local preparedMealId, _, preparedServings, preparedHungerPerPortion =
			KitchenService.GetPreparedMealCandidate(player)
		if preparedMealId and preparedServings > 0 and preparedHungerPerPortion > 0 then
			if stationAvailable(storageStationType, nil) then
				return true
			end
		end
	end

	local bestContainer = KitchenService.PeekBestEdibleContainer(player)
	if bestContainer then
		local function containerFilter(uniqueId: string, _station, _item, _model)
			return uniqueId == bestContainer
		end
		if storageStationType and cache and cache[storageStationType] and cache[storageStationType][bestContainer] then
			if stationAvailable(storageStationType, containerFilter) then
				return true
			end
		end
		if cookStationType and cache and cache[cookStationType] and cache[cookStationType][bestContainer] then
			if stationAvailable(cookStationType, containerFilter) then
				return true
			end
		end
	end

	return false
end

function Utils.hasActionableHungerPath(player: Player?, cache: { [string]: any }?, residentName: string?): boolean
	return hungerHasActionablePath(player, cache, residentName)
end

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
	local hungerActionable: boolean? = nil
	local residentName = if typeof(resident.Name) == "string" then resident.Name else tostring(resident)
	local forcedNeedName = State.getForcedNeed(resident, os.clock())
	for needName, def in pairs(needs) do
		if needName ~= ignoreNeed then
			local value = resident:GetNeed(needName)
			if value <= def.Critical then
				local stationType = State.NeedToStationType[needName]
				if State.SurvivalNeeds[needName] then
					if stationType and DirectActionService.HasHandler(stationType) then
						if not State.isSurvivalNeedUnavailable(resident, needName) then
							local actionable = false
							if needName == "Hunger" then
								if hungerActionable == nil then
									hungerActionable = hungerHasActionablePath(player, cache, residentName)
								end
								actionable = hungerActionable == true
							else
								actionable = hasStationsForNeed(cache, stationType)
							end
							if actionable or forcedNeedName == needName then
								return true
							end
						end
					end
				else
					if stationType then
						if not DirectActionService.HasHandler(stationType) then
							return true
						end
						if cache and hasStationsForNeed(cache, stationType) then
							return true
						end
					else
						return true
					end
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

function Utils.shouldBlockRoam(player: Player, resident: ResidentState, stationCache: { [string]: any }?): boolean
	local needs = State.getNeeds()
	local cache = stationCache or PlotService.GetStationsForPlayer(player)
	local hungerActionable: boolean? = nil
	local residentName = if typeof(resident.Name) == "string" then resident.Name else tostring(resident)
	local forcedNeedName = State.getForcedNeed(resident, os.clock())
	for needName, def in pairs(needs) do
		local value = resident:GetNeed(needName)
		if value <= def.Critical then
			local stationType = State.NeedToStationType[needName]
			if State.SurvivalNeeds[needName] then
				if stationType and DirectActionService.HasHandler(stationType) then
					if not State.isSurvivalNeedUnavailable(resident, needName) then
						local actionable = false
						if needName == "Hunger" then
							if hungerActionable == nil then
								hungerActionable = hungerHasActionablePath(player, cache, residentName)
							end
							actionable = hungerActionable == true
						else
							actionable = hasStationsForNeed(cache, stationType)
						end
						if actionable or forcedNeedName == needName then
							return true
						end
					end
				end
			else
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
