--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NeedConfig = require(ReplicatedStorage.Shared.Configurations.NeedConfig)
local TimeScale = require(ReplicatedStorage.Shared.Utilities.TimeScale)
local Constants = require(script.Parent.Constants)

export type ResidentState = any

local State = {}

State.NeedToStationType = {
	Hunger = "CookStation",
	Energy = "RestStation",
	Hygiene = "HygieneStation",
	Social = "SocialStation",
	Fun = "FunStation",
}

State.SurvivalNeeds = {
	Hunger = true,
	Energy = true,
}

State.NeedPrioritySeed = { "Hunger", "Energy", "Hygiene", "Social", "Fun" }
State.NeedEvaluationOrder = {} :: { string }

State.MissingStationPhrases = {
	Hunger = {
		"I wish we had somewhere to make a meal...",
		"A kitchen would really help right now.",
	},
	Energy = {
		"I could really use a proper bed around here.",
		"No place to sleep... this isn't great.",
	},
	Hygiene = {
		"Sure would be nice to clean up somewhere.",
		"We need a shower or something soon.",
	},
	Social = {
		"Wish we had a spot to hang out with someone.",
		"No place to talk... it's lonely here.",
	},
	Fun = {
		"It'd be great to have something fun to do.",
		"We should really set up a fun station sometime.",
	},
	_default = {
		"I wish we had the right station for this...",
	},
}

State.ResidentCooldowns = setmetatable({} :: { [ResidentState]: { [string]: number } }, { __mode = "k" })
State.ResidentPending = setmetatable({} :: { [ResidentState]: string? }, { __mode = "k" })
State.ResidentNextEvaluation = setmetatable({} :: { [ResidentState]: number }, { __mode = "k" })
State.ResidentLastRoam = setmetatable({} :: { [ResidentState]: number }, { __mode = "k" })
State.ResidentLastJog = setmetatable({} :: { [ResidentState]: number }, { __mode = "k" })
State.NonSurvivalSuppressed = setmetatable({} :: { [ResidentState]: { [string]: number } }, { __mode = "k" })
State.MissingStationComplaints = setmetatable({} :: { [ResidentState]: { [string]: boolean } }, { __mode = "k" })
State.StationIteratorState = {} :: { [number]: { [string]: { version: number, order: { string }, index: number } } }
State.ItemSpecCache = {} :: { [string]: { [string]: any }? }
State.SurvivalUnavailable = setmetatable({} :: { [ResidentState]: { [string]: boolean } }, { __mode = "k" })

State.SecondsPerFullDayCached = TimeScale.GetSecondsPerFullDay()
State.NeedCooldownSeconds = {} :: { [string]: number }

local function convertMinutesToSeconds(minutes: number): number
	if minutes <= 0 then
		return 0
	end
	return minutes * (State.SecondsPerFullDayCached / (24 * 60))
end

function State.getNeeds()
	return NeedConfig.Needs
end

function State.getCircadian()
	return NeedConfig.Circadian
end

function State.rebuildNeedEvaluationOrder()
	table.clear(State.NeedEvaluationOrder)
	local needs = State.getNeeds()
	local seen = {} :: { [string]: boolean }
	for _, needName in ipairs(State.NeedPrioritySeed) do
		if needs[needName] and State.NeedToStationType[needName] then
			State.NeedEvaluationOrder[#State.NeedEvaluationOrder + 1] = needName
			seen[needName] = true
		end
	end
	local extras = {} :: { string }
	for needName in pairs(needs) do
		if State.NeedToStationType[needName] and not seen[needName] then
			extras[#extras + 1] = needName
		end
	end
	table.sort(extras)
	for _, needName in ipairs(extras) do
		State.NeedEvaluationOrder[#State.NeedEvaluationOrder + 1] = needName
	end
end

function State.refreshNeedCooldowns()
	table.clear(State.NeedCooldownSeconds)
	local needs = State.getNeeds()
	for needName, def in pairs(needs) do
		State.NeedCooldownSeconds[needName] = convertMinutesToSeconds(def.CooldownMinutes)
	end
	State.rebuildNeedEvaluationOrder()
end

function State.refreshTimeScaleCaches()
	State.SecondsPerFullDayCached = TimeScale.GetSecondsPerFullDay()
	State.refreshNeedCooldowns()
end

function State.getNeedCooldownSeconds(needName: string, def: NeedConfig.NeedDef): number
	local cached = State.NeedCooldownSeconds[needName]
	if cached ~= nil then
		return cached
	end
	local seconds = convertMinutesToSeconds(def.CooldownMinutes)
	State.NeedCooldownSeconds[needName] = seconds
	return seconds
end

local function getOrCreateCooldowns(resident: ResidentState)
	local entry = State.ResidentCooldowns[resident]
	if not entry then
		entry = {}
		State.ResidentCooldowns[resident] = entry
	end
	return entry
end

function State.setNeedCooldown(resident: ResidentState, needName: string)
	local entry = getOrCreateCooldowns(resident)
	entry[needName] = os.clock()
end

function State.isNeedOnCooldown(resident: ResidentState, needName: string, cooldownSeconds: number, nowClock: number)
	if cooldownSeconds <= 0 then
		return false
	end
	local entry = State.ResidentCooldowns[resident]
	if not entry then
		return false
	end
	local last = entry[needName]
	if not last then
		return false
	end
	return nowClock - last < cooldownSeconds
end

local function getOrCreateSuppression(resident: ResidentState)
	local entry = State.NonSurvivalSuppressed[resident]
	if not entry then
		entry = {}
		State.NonSurvivalSuppressed[resident] = entry
	end
	return entry
end

function State.shouldSuppressNonSurvival(resident: ResidentState, stationType: string, stationVersion: number?): boolean
	local storeVersion = stationVersion or -1
	local entry = State.NonSurvivalSuppressed[resident]
	if entry then
		local recorded = entry[stationType]
		if recorded ~= nil then
			if recorded ~= storeVersion then
				entry[stationType] = storeVersion
				return false
			end
			return true
		end
	else
		entry = getOrCreateSuppression(resident)
	end
	entry[stationType] = storeVersion
	return false
end

function State.clearNonSurvivalSuppression(resident: ResidentState, stationType: string)
	local entry = State.NonSurvivalSuppressed[resident]
	if entry then
		entry[stationType] = nil
		if next(entry) == nil then
			State.NonSurvivalSuppressed[resident] = nil
		end
	end
end

local function getOrCreateMissingComplaints(resident: ResidentState)
	local entry = State.MissingStationComplaints[resident]
	if not entry then
		entry = {}
		State.MissingStationComplaints[resident] = entry
	end
	return entry
end

local function getOrCreateSurvivalUnavailable(resident: ResidentState)
	local entry = State.SurvivalUnavailable[resident]
	if not entry then
		entry = {}
		State.SurvivalUnavailable[resident] = entry
	end
	return entry
end

function State.didComplainAboutMissingStation(resident: ResidentState, needName: string): boolean
	local entry = State.MissingStationComplaints[resident]
	return entry ~= nil and entry[needName] == true
end

function State.markMissingStationComplaint(resident: ResidentState, needName: string)
	local entry = getOrCreateMissingComplaints(resident)
	entry[needName] = true
end

function State.getMissingStationPhrases(needName: string)
	return State.MissingStationPhrases[needName] or State.MissingStationPhrases._default
end

function State.markSurvivalNeedUnavailable(resident: ResidentState, needName: string)
	local entry = getOrCreateSurvivalUnavailable(resident)
	entry[needName] = true
end

function State.clearSurvivalNeedUnavailable(resident: ResidentState, needName: string)
	local entry = State.SurvivalUnavailable[resident]
	if entry then
		entry[needName] = nil
		if next(entry) == nil then
			State.SurvivalUnavailable[resident] = nil
		end
	end
end

function State.isSurvivalNeedUnavailable(resident: ResidentState, needName: string): boolean
	local entry = State.SurvivalUnavailable[resident]
	return entry ~= nil and entry[needName] == true
end

function State.setPending(resident: ResidentState, value: string?)
	if value == nil then
		State.ResidentPending[resident] = nil
		return
	end
	State.ResidentPending[resident] = value
end

function State.getPending(resident: ResidentState): string?
	return State.ResidentPending[resident]
end

function State.setNextEvaluation(resident: ResidentState, when: number)
	State.ResidentNextEvaluation[resident] = when
end

function State.clearNextEvaluation(resident: ResidentState)
	State.ResidentNextEvaluation[resident] = nil
end

function State.getNextEvaluation(resident: ResidentState): number?
	return State.ResidentNextEvaluation[resident]
end

function State.getLastRoam(resident: ResidentState): number?
	return State.ResidentLastRoam[resident]
end

function State.recordRoam(resident: ResidentState, when: number)
	State.ResidentLastRoam[resident] = when
end

function State.clearLastRoam(resident: ResidentState)
	State.ResidentLastRoam[resident] = nil
end

function State.getLastJog(resident: ResidentState): number?
	return State.ResidentLastJog[resident]
end

function State.recordJog(resident: ResidentState, when: number)
	State.ResidentLastJog[resident] = when
end

function State.clearLastJog(resident: ResidentState)
	State.ResidentLastJog[resident] = nil
end

function State.computeNextEvaluationDelay(resident: ResidentState): number
	local needs = State.getNeeds()
	local secondsPerGameHour = State.SecondsPerFullDayCached / 24
	local soonest: number? = nil
	for needName, def in pairs(needs) do
		if State.NeedToStationType[needName] then
			local decayPerHour = def.DecayPerHour
			if decayPerHour > 0 then
				local value = resident:GetNeed(needName)
				if value > def.Low then
					local delta = value - def.Low
					local hoursUntilLow = delta / decayPerHour
					if hoursUntilLow > 0 then
						local secondsUntilLow = hoursUntilLow * secondsPerGameHour
						if not soonest or secondsUntilLow < soonest then
							soonest = secondsUntilLow
						end
					end
				end
			end
		end
	end
	local clamped = math.clamp(soonest or 1, 1, 10)
	local lastRoam = State.getLastRoam(resident)
	if lastRoam then
		local now = os.clock()
		local elapsed = now - lastRoam
		if elapsed < Constants.ROAM_MIN_INTERVAL_SECONDS then
			local remaining = Constants.ROAM_MIN_INTERVAL_SECONDS - elapsed
			if remaining > clamped then
				clamped = remaining
			end
		end
	end
	return clamped
end

State.refreshNeedCooldowns()

return State
