--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local ResidentChat = require(ServerScriptService.Server.Utilities.ResidentChat)
local DirectActionService = require(ServerScriptService.Server.Services.DirectActionService)
local PlotService = require(ServerScriptService.Server.Services.PlotService)
local TraitUtils = require(ReplicatedStorage.Shared.Utilities.TraitUtils)
local NeedConfig = require(ReplicatedStorage.Shared.Configurations.NeedConfig)
local State = require(script.Parent.State)
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
}

local NeedEvaluator = {}

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

local function chooseRestMode(def: NeedConfig.NeedDef, energyValue: number, clockTime: number): string
	if energyValue <= def.Critical then
		return "Sleep"
	end
	if Utils.isNight(clockTime) then
		return "Sleep"
	end
	return "DaySleep"
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

	local hungerDef = needs.Hunger
	local hungerValue = if hungerDef then resident:GetNeed("Hunger") else nil
	local hungerCritical = false
	local survivalSatisfied = true

	if hungerDef and hungerValue ~= nil then
		hungerCritical = hungerValue <= hungerDef.Critical
		if hungerValue < hungerDef.Low then
			survivalSatisfied = false
		end
	end

	local energyDef = needs.Energy
	local energyValue: number? = nil
	if energyDef then
		energyValue = resident:GetNeed("Energy")
		if energyValue < energyDef.Low then
			survivalSatisfied = false
		end
	end

	local hungerStationType = State.NeedToStationType.Hunger
	local hungerStationMap = if hungerStationType then stationCache[hungerStationType] else nil
	local hungerStationsPlaced = hungerStationMap ~= nil and next(hungerStationMap) ~= nil

	local bestDecision: NeedDecision? = nil
	local bestScore = 0
	
	local residentTraits = resident:GetTraits()

	for _, needName in ipairs(State.NeedEvaluationOrder) do
		local def = needs[needName]
		if def then
			local stationType = State.NeedToStationType[needName]
			if stationType and DirectActionService.HasHandler(stationType) then
				local isSurvival = State.SurvivalNeeds[needName] == true
				if not isSurvival and not survivalSatisfied then
					continue
				end

				if needName == "Energy" and hungerDef and hungerValue ~= nil then
					if hungerCritical then
						continue
					end
					if hungerValue < hungerDef.Low and hungerStationsPlaced then
						continue
					end
				end

				local stationMap = stationCache[stationType]
				local hasStationsPlaced = stationMap ~= nil and next(stationMap) ~= nil
				local value = resident:GetNeed(needName)

				if not hasStationsPlaced then
					tryComplainAboutMissingStation(resident, needName, value)
					if isSurvival then
						State.markSurvivalNeedUnavailable(resident, needName)
						continue
					end
				elseif isSurvival then
					State.clearSurvivalNeedUnavailable(resident, needName)
				end

				if not hasStationsPlaced and not isSurvival then
					local stationVersion = PlotService.GetStationVersion(player, stationType) or 0
					if State.shouldSuppressNonSurvival(resident, stationType, stationVersion) then
						continue
					end
					continue
				elseif not isSurvival then
					State.clearNonSurvivalSuppression(resident, stationType)
				end

				local deficit = math.max(0, def.Low - value)
				if deficit > 0 then
					local score = math.clamp(deficit / math.max(1, def.Low), 0, 1)
					if value <= def.Critical then
						score += 1
					end
					if needName == "Energy" and Utils.isNight(clockTime) then
						score *= 1 + State.getCircadian().SleepBias
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
					
					if score > 0 then
						local cooldownSeconds = State.getNeedCooldownSeconds(needName, def)
						local onCooldown = State.isNeedOnCooldown(resident, needName, cooldownSeconds, nowClock)
						if onCooldown and needName == "Energy" and energyDef and energyValue ~= nil then
							local bypass = value <= def.Critical
							if not bypass and value < def.Low and Utils.isNight(clockTime) then
								bypass = true
							end
							if bypass then
								onCooldown = false
							end
						end
						if not onCooldown then
							local uniqueId, stationRecord, itemSpec, stationModel =
								StationManager.findAvailableStation(player, stationType, residentName, stationCache)
							if uniqueId and stationRecord and itemSpec and stationModel then
								if score > bestScore then
									bestScore = score
									local restOverride = if needName == "Energy"
											and energyDef
											and energyValue ~= nil
										then chooseRestMode(energyDef, energyValue, clockTime)
										else nil
									bestDecision = {
										StationType = stationType,
										UniqueId = uniqueId,
										StationRecord = stationRecord,
										ItemSpec = itemSpec,
										StationModel = stationModel,
										NeedName = needName,
										RestModeOverride = restOverride,
									}
								end
							elseif not isSurvival then
								State.clearNonSurvivalSuppression(resident, stationType)
							end
						end
					end
				end
			end
		end
	end

	return bestDecision
end

return NeedEvaluator
