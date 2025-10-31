--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local ResidentChat = require(ServerScriptService.Server.Utilities.ResidentChat)
local DirectActionService = require(ServerScriptService.Server.Services.DirectActionService)
local PlotService = require(ServerScriptService.Server.Services.PlotService)
local KitchenService = require(ServerScriptService.Server.Services.KitchenService)
local TraitUtils = require(ReplicatedStorage.Shared.Utilities.TraitUtils)
local NeedConfig = require(ReplicatedStorage.Shared.Configurations.NeedConfig)
local State = require(script.Parent.State) :: any
local Utils = require(script.Parent.Utils)
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
	ActionMode: string?,
	TargetContainerId: string?,
	PreparedMealId: string?,
	PreparedMealServings: number?,
	PreparedMealHungerPerPortion: number?,
}

local NeedEvaluator = {}

type KitchenAvailabilitySnapshot = KitchenService.KitchenAvailabilitySnapshot
type StationRecord = StationManager.StationRecord
type StationInfo = {
	Map: { [string]: StationRecord }?,
	HasStations: boolean,
	OutageBlocked: boolean,
	Accessible: boolean,
}

local function tryComplainAboutMissingStation(resident: ResidentState, needName: string, needValue: number)
	local needs = State.getNeeds()
	local def = needs[needName]
	if not def or needValue > def.Critical then
		return
	end
	if State.didComplainAboutMissingStation(resident, needName) then
		return
	end
	State.markMissingStationComplaint(resident, needName)
	local phrases = State.getMissingStationPhrases(needName)
	if phrases then
		ResidentChat.ShowAction(resident, phrases)
	end
end

local function tryComplainAboutPowerOutage(resident: ResidentState, needName: string, needValue: number)
	local needs = State.getNeeds()
	local def = needs[needName]
	if not def or needValue > def.Critical then
		return
	end
	if State.didComplainPowerOutage(resident, needName) then
		return
	end
	State.markPowerOutageComplaint(resident, needName)
	local phrases = State.getPowerOutagePhrases(needName)
	if phrases then
		ResidentChat.ShowAction(resident, phrases)
	end
end

local function chooseRestMode(def: NeedConfig.NeedDef, energyValue: number, clockTime: number): string
	if energyValue <= def.Critical then
		return "Sleep"
	end
	if Utils.isNight(clockTime) then
		return "Sleep"
	end
	return "DaySleep"
end

type StationFilter = (string, StationManager.StationRecord, { [string]: any }?, Model?) -> boolean

type NeedContext = {
	Name: string,
	Def: NeedConfig.NeedDef,
	Value: number,
	StationType: string,
	Survival: boolean,
	Actionable: boolean,
	Score: number,
	Critical: boolean,
	BelowLow: boolean,
	OnCooldown: boolean,
	BypassCooldown: boolean,
	ActionMode: string?,
	TargetContainerId: string?,
	StationFilter: StationFilter?,
	RestModeOverride: string?,
	Unavailable: boolean,
	HasStationsPlaced: boolean,
	StationsAccessible: boolean,
	PowerOutageBlocked: boolean,
	HasFoodOption: boolean?,
	PreparedMealId: string?,
	PreparedMealServings: number?,
	PreparedMealHungerPerPortion: number?,
}

local function buildSnackFilter(targetId: string): StationFilter
	return function(id, _station, itemSpec, _model)
		if id ~= targetId then
			return false
		end
		if itemSpec == nil then
			return false
		end
		local spec = itemSpec :: any
		return spec.StorageConfig ~= nil
	end
end

local function buildNeedContexts(
	player: Player,
	resident: ResidentState,
	nowClock: number,
	clockTime: number,
	stationCache: { [string]: any },
	residentTraits: { string },
	needs: { [string]: NeedConfig.NeedDef },
	circadianSleepBias: number,
	isNightTime: boolean
): ({ NeedContext }, NeedContext?)
	local contexts = table.create(#State.NeedEvaluationOrder)
	local hungerContext: NeedContext? = nil

	local stationAccessCache: { [string]: StationInfo } = {}
	local stationVersionCache: { [string]: number } = {}
	local handlerCache: { [string]: boolean } = {}

	local function getStationInfo(stationType: string): StationInfo
		local cached = stationAccessCache[stationType]
		if cached then
			return cached
		end
		local stationMap = stationCache[stationType] :: { [string]: StationRecord }?
		local hasStations = stationMap ~= nil and next(stationMap) ~= nil
		local outageBlocked = false
		if hasStations then
			outageBlocked = StationManager.isStationBlockedByOutage(player, stationType, stationCache)
		end
		local info: StationInfo = {
			Map = stationMap,
			HasStations = hasStations,
			OutageBlocked = outageBlocked,
			Accessible = hasStations and not outageBlocked,
		}
		stationAccessCache[stationType] = info
		return info
	end

	local function getStationVersion(stationType: string): number
		local cached = stationVersionCache[stationType]
		if cached ~= nil then
			return cached
		end
		local version = PlotService.GetStationVersion(player, stationType) or 0
		stationVersionCache[stationType] = version
		return version
	end

	local function hasHandler(stationType: string): boolean
		local cached = handlerCache[stationType]
		if cached ~= nil then
			return cached
		end
		local available = DirectActionService.HasHandler(stationType)
		handlerCache[stationType] = available
		return available
	end

	local kitchenSnapshot: KitchenAvailabilitySnapshot? = KitchenService.GetAvailabilitySnapshot(player)
	local preparedMealId: string? = nil
	local preparedMealServings = 0
	local preparedMealHungerPerPortion = 0
	local bestContainerId: string? = nil
	local hasCookableRecipe = false

	if kitchenSnapshot then
		if kitchenSnapshot.HasPreparedMeal and kitchenSnapshot.BestMealId then
			if kitchenSnapshot.BestMealServings > 0 and kitchenSnapshot.BestMealHungerPerPortion > 0 then
				preparedMealId = kitchenSnapshot.BestMealId
				preparedMealServings = kitchenSnapshot.BestMealServings
				preparedMealHungerPerPortion = kitchenSnapshot.BestMealHungerPerPortion
			end
		end
		bestContainerId = kitchenSnapshot.BestContainerId
		hasCookableRecipe = kitchenSnapshot.HasCookable
	else
		local mealId, _, servings, hungerPerPortion = KitchenService.GetPreparedMealCandidate(player)
		if mealId and servings > 0 and hungerPerPortion > 0 then
			preparedMealId = mealId
			preparedMealServings = servings
			preparedMealHungerPerPortion = hungerPerPortion
		end
		bestContainerId = KitchenService.PeekBestEdibleContainer(player)
		hasCookableRecipe = KitchenService.HasCookableRecipe(player)
	end

	for _, needName in ipairs(State.NeedEvaluationOrder) do
		local def = needs[needName]
		if def == nil then
			continue
		end

		local stationTypes = State.getStationTypesForNeed(needName)
		local stationType = stationTypes[1]
		if not stationType then
			continue
		end

		local hasAnyHandler = false
		for _, candidate in ipairs(stationTypes) do
			if hasHandler(candidate) then
				hasAnyHandler = true
				break
			end
		end
		if not hasAnyHandler then
			continue
		end

		if not hasHandler(stationType) then
			for _, candidate in ipairs(stationTypes) do
				if hasHandler(candidate) then
					stationType = candidate
					break
				end
			end
		end

		local stationInfo = getStationInfo(stationType)
		local stationMap = stationInfo.Map
		local stationsPlaced = stationInfo.HasStations
		local outageBlocksStations = stationInfo.OutageBlocked
		local stationsAccessible = stationInfo.Accessible

		local survival = State.SurvivalNeeds[needName] == true
		local alternateStationType = if #stationTypes > 1 then stationTypes[2] else nil
		local value = resident:GetNeed(needName)
		local critical = value <= def.Critical
		local belowLow = value < def.Low
		local unavailable = State.isSurvivalNeedUnavailable(resident, needName)

		local context: NeedContext = {
			Name = needName,
			Def = def,
			Value = value,
			StationType = stationType,
			Survival = survival,
			Actionable = false,
			Score = 0,
			Critical = critical,
			BelowLow = belowLow,
			OnCooldown = false,
			BypassCooldown = false,
			ActionMode = nil,
			TargetContainerId = nil,
			StationFilter = nil,
			RestModeOverride = nil,
			Unavailable = unavailable,
			HasStationsPlaced = stationsPlaced,
			StationsAccessible = stationsAccessible,
			PowerOutageBlocked = outageBlocksStations,
			HasFoodOption = nil,
			PreparedMealId = nil,
			PreparedMealServings = nil,
			PreparedMealHungerPerPortion = nil,
		}

		if needName == "Energy" then
			context.RestModeOverride = chooseRestMode(def, value, clockTime)
		end

		if not stationsPlaced then
			tryComplainAboutMissingStation(resident, needName, value)
			State.clearPowerOutageComplaint(resident, needName)
			if survival then
				State.markSurvivalNeedUnavailable(resident, needName)
				context.Unavailable = true
			else
				local stationVersion = getStationVersion(stationType)
				if State.shouldSuppressNonSurvival(resident, stationType, stationVersion) then
					context.Actionable = false
				end
			end
		elseif outageBlocksStations then
			tryComplainAboutPowerOutage(resident, needName, value)
			if survival then
				State.markSurvivalNeedUnavailable(resident, needName)
			end
			context.Unavailable = true
		else
			if survival then
				State.clearSurvivalNeedUnavailable(resident, needName)
				context.Unavailable = false
			else
				State.clearNonSurvivalSuppression(resident, stationType)
			end
			State.clearPowerOutageComplaint(resident, needName)
		end

		local actionMode: string? = nil
		local targetContainerId: string? = nil
		local stationFilter: StationFilter? = nil

		if survival then
			if needName == "Hunger" then
				local cookStationType = stationType
				local cookInfo = stationInfo
				local storageStationType = alternateStationType
				local storageInfo = storageStationType and getStationInfo(storageStationType) or nil

				local anyStationsPlaced = cookInfo.HasStations or (storageInfo and storageInfo.HasStations) or false
				local anyAccessible = cookInfo.Accessible or (storageInfo and storageInfo.Accessible) or false
				local anyOutageBlock = (cookInfo.HasStations and cookInfo.OutageBlocked) or false
				if storageInfo and storageInfo.HasStations and storageInfo.OutageBlocked then
					anyOutageBlock = true
				end

				context.HasStationsPlaced = anyStationsPlaced
				context.StationsAccessible = anyAccessible
				context.PowerOutageBlocked = anyOutageBlock
				context.HasFoodOption = false

				local hasPreparedMealOption = false
				if storageInfo and storageInfo.Accessible and preparedMealId ~= nil then
					if preparedMealServings > 0 and preparedMealHungerPerPortion > 0 then
						hasPreparedMealOption = true
					end
				end

				if hasPreparedMealOption and storageStationType then
					actionMode = "PreparedMeal"
					context.StationType = storageStationType
					context.PreparedMealId = preparedMealId
					context.PreparedMealServings = math.max(1, math.min(preparedMealServings, 1))
					context.PreparedMealHungerPerPortion = preparedMealHungerPerPortion
					context.HasStationsPlaced = storageInfo and storageInfo.HasStations or false
					context.StationsAccessible = storageInfo and storageInfo.Accessible or false
					context.PowerOutageBlocked = storageInfo and storageInfo.OutageBlocked or false
					context.Unavailable = not (storageInfo and storageInfo.Accessible or false)
					context.HasFoodOption = true
				else
					local canCook = cookInfo.Accessible and hasCookableRecipe
					if canCook then
						actionMode = "Cook"
						context.StationType = cookStationType
						context.HasStationsPlaced = cookInfo.HasStations
						context.StationsAccessible = cookInfo.Accessible
						context.PowerOutageBlocked = cookInfo.OutageBlocked
						context.Unavailable = false
						context.HasFoodOption = true
					else
						local chosenContainerId = bestContainerId
						local targetStationType: string? = nil
						local targetInfo: StationInfo? = nil

						if chosenContainerId and chosenContainerId ~= "" then
							if storageInfo and storageInfo.Map and storageInfo.Map[chosenContainerId] then
								targetStationType = storageStationType
								targetInfo = storageInfo
							elseif stationMap and stationMap[chosenContainerId] then
								targetStationType = cookStationType
								targetInfo = cookInfo
							end
						end

						if targetStationType and targetInfo and targetInfo.Accessible then
							actionMode = "Snack"
							targetContainerId = chosenContainerId
							stationFilter = buildSnackFilter(chosenContainerId :: string)
							context.StationType = targetStationType
							context.HasStationsPlaced = targetInfo.HasStations
							context.StationsAccessible = targetInfo.Accessible
							context.PowerOutageBlocked = targetInfo.OutageBlocked
							context.Unavailable = false
							context.HasFoodOption = true
						else
							context.Unavailable = true
						end
					end
				end

				if not context.HasFoodOption then
					if anyStationsPlaced then
						local blockedByOutage = (cookInfo.HasStations and cookInfo.OutageBlocked) or false
						if storageInfo and storageInfo.HasStations and storageInfo.OutageBlocked then
							blockedByOutage = true
						end
						context.PowerOutageBlocked = blockedByOutage
						context.Unavailable = true
						State.markSurvivalNeedUnavailable(resident, needName)
					else
						State.markSurvivalNeedUnavailable(resident, needName)
						context.Unavailable = true
					end
				else
					context.Unavailable = false
					State.clearSurvivalNeedUnavailable(resident, needName)
				end
			else
				if not stationsAccessible then
					context.Unavailable = true
				else
					context.Unavailable = false
				end
			end
		end

		context.ActionMode = actionMode
		context.TargetContainerId = targetContainerId
		context.StationFilter = stationFilter

		if not context.Unavailable and belowLow then
			local deficit = def.Low - value
			local score = math.clamp(deficit / math.max(1, def.Low), 0, 1)
			if critical then
				score += 1
			end
			if needName == "Energy" and isNightTime then
				score *= 1 + circadianSleepBias
			end
			local traitBias = TraitUtils.GetNeedScoreBias(residentTraits, needName)
			local moodBias = resident:GetMoodBias(needName, nowClock)
			local biasTotal = traitBias + moodBias
			if biasTotal ~= 0 then
				local multiplier = 1 + biasTotal
				if multiplier > 0 then
					score *= multiplier
				else
					score = 0
				end
			end

			context.Score = score
		end

		if not context.Unavailable then
			local cooldownSeconds = State.getNeedCooldownSeconds(needName, def)
			local onCooldown = State.isNeedOnCooldown(resident, needName, cooldownSeconds, nowClock)
			local bypassCooldown = false
			if needName == "Energy" then
				bypassCooldown = critical or (belowLow and isNightTime)
			elseif needName == "Hunger" then
				bypassCooldown = critical
			end
			context.OnCooldown = onCooldown
			context.BypassCooldown = bypassCooldown

			if context.Score > 0 then
				local canAct = not onCooldown or bypassCooldown
				if survival then
					if needName == "Hunger" then
						context.Actionable = canAct and actionMode ~= nil
					else
						context.Actionable = canAct and stationsAccessible
					end
				else
					context.Actionable = canAct and stationsAccessible
				end
			end
		end

		if context.Actionable and State.shouldBlockInterruptedNeed(resident, needName, nowClock) then
			context.Actionable = false
			context.Score = 0
		end

		contexts[#contexts + 1] = context
		if needName == "Hunger" then
			hungerContext = context
		end
	end

	return contexts, hungerContext
end

local function hasBlockingSurvivalNeed(contexts: { NeedContext }, skipNeedName: string): boolean
	for _, context in ipairs(contexts) do
		if context.Survival and context.Name ~= skipNeedName then
			if context.Unavailable then
				continue
			end
			if context.Score > 0 then
				if context.Name == ("Hunger" :: string) then
					if context.StationsAccessible and context.HasFoodOption and context.Actionable then
						return true
					end
				else
					if context.StationsAccessible and context.Actionable then
						return true
					end
				end
			end
		end
	end
	return false
end

function NeedEvaluator.evaluate(
	player: Player,
	residentName: string,
	resident: ResidentState,
	nowClock: number,
	clockTime: number,
	stationCacheMaybe: { [string]: any }?
): NeedDecision?
	local stationCache = stationCacheMaybe or PlotService.GetStationsForPlayer(player)
	local needs = State.getNeeds()
	local residentTraits = resident:GetTraits()
	local isNightTime = Utils.isNight(clockTime)
	local circadianSleepBias = State.getCircadian().SleepBias

	local contexts, hungerContext = buildNeedContexts(
		player,
		resident,
		nowClock,
		clockTime,
		stationCache,
		residentTraits,
		needs,
		circadianSleepBias,
		isNightTime
	)

	local bestDecision: NeedDecision? = nil
	local bestScore = 0

	local forcedNeedName = State.getForcedNeed(resident, nowClock)
	local forcedContext: NeedContext? = nil
	if forcedNeedName then
		for _, context in ipairs(contexts) do
			if context.Name == forcedNeedName then
				forcedContext = context
				if context.Actionable then
					local uniqueId, stationRecord, itemSpec, stationModel = StationManager.findAvailableStation(
						player,
						context.StationType,
						residentName,
						stationCache,
						context.StationFilter
					)
					if uniqueId and stationRecord and itemSpec and stationModel then
						State.clearForcedNeed(resident, forcedNeedName)
						State.clearInterruptedNeed(resident, forcedNeedName)
						return {
							StationType = context.StationType,
							UniqueId = uniqueId,
							StationRecord = stationRecord,
							ItemSpec = itemSpec,
							StationModel = stationModel,
							NeedName = context.Name,
							RestModeOverride = context.RestModeOverride,
							ActionMode = context.ActionMode,
							TargetContainerId = context.TargetContainerId,
							PreparedMealId = context.PreparedMealId,
							PreparedMealServings = context.PreparedMealServings,
							PreparedMealHungerPerPortion = context.PreparedMealHungerPerPortion,
						}
					end
				end
				break
			end
		end
		if not forcedContext then
			State.clearForcedNeed(resident, forcedNeedName)
		else
			return nil
		end
	end

	local hungerActionable = if hungerContext then hungerContext.Actionable else false
	local hungerCritical = if hungerContext then hungerContext.Critical else false

	for _, context in ipairs(contexts) do
		local needNameValue: string = context.Name
		if not context.Actionable then
			continue
		end
		if context.Score <= 0 then
			continue
		end
		if not context.Survival and hasBlockingSurvivalNeed(contexts, needNameValue :: string) then
			continue
		end
		if needNameValue == ("Energy" :: string) and hungerContext then
			if hungerCritical and hungerActionable then
				continue
			end
		end
		if context.OnCooldown and not context.BypassCooldown then
			continue
		end

		local uniqueId, stationRecord, itemSpec, stationModel = StationManager.findAvailableStation(
			player,
			context.StationType,
			residentName,
			stationCache,
			context.StationFilter
		)

		if not (uniqueId and stationRecord and itemSpec and stationModel) then
			context.Actionable = false
			if not context.Survival then
				State.clearNonSurvivalSuppression(resident, context.StationType)
			elseif needNameValue == ("Hunger" :: string) then
				hungerActionable = false
			end
			continue
		end

		if needNameValue == ("Hunger" :: string) then
			hungerActionable = true
		end

		if context.Score > bestScore then
			bestScore = context.Score
			bestDecision = {
				StationType = context.StationType,
				UniqueId = uniqueId,
				StationRecord = stationRecord,
				ItemSpec = itemSpec,
				StationModel = stationModel,
				NeedName = needNameValue :: string,
				RestModeOverride = context.RestModeOverride,
				ActionMode = context.ActionMode,
				TargetContainerId = context.TargetContainerId,
				PreparedMealId = context.PreparedMealId,
				PreparedMealServings = context.PreparedMealServings,
				PreparedMealHungerPerPortion = context.PreparedMealHungerPerPortion,
			}
		end
	end

	return bestDecision
end

return NeedEvaluator
