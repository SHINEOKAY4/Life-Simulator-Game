--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NeedConfig = require(ReplicatedStorage.Shared.Configurations.NeedConfig)
local TimeScale = require(ReplicatedStorage.Shared.Utilities.TimeScale)
local Constants = require(script.Parent.Constants)

export type ResidentState = any
type StationReservation = { Station: any, ResidentName: string }

local State = {}

State.NeedStationTypes = {
	Hunger = { "CookStation", "FoodStorage" },
	Energy = { "RestStation" },
	Hygiene = { "HygieneStation" },
	Social = { "SocialStation" },
	Fun = { "FunStation" },
}

State.NeedToStationType = {}
for needName, stationList in pairs(State.NeedStationTypes) do
	local primary = stationList[1]
	if primary then
		State.NeedToStationType[needName] = primary
	end
end

local SURVIVAL_NEEDS = table.freeze({
	Hunger = true,
	Energy = true,
})

State.SurvivalNeeds = SURVIVAL_NEEDS

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

State.PowerOutagePhrases = {
	Hunger = {
		"No power means no dinner... this outage is rough.",
		"Can't cook anything while the lights are out.",
	},
	_default = {
		"Can't do that while the power's out...",
	},
}

State.ResidentCooldowns = setmetatable({} :: { [ResidentState]: { [string]: number } }, { __mode = "k" })
State.ResidentPending = setmetatable({} :: { [ResidentState]: string? }, { __mode = "k" })
State.ResidentNextEvaluation = setmetatable({} :: { [ResidentState]: number }, { __mode = "k" })
State.ResidentLastRoam = setmetatable({} :: { [ResidentState]: number }, { __mode = "k" })
State.ResidentLastJog = setmetatable({} :: { [ResidentState]: number }, { __mode = "k" })
State.NonSurvivalSuppressed = setmetatable({} :: { [ResidentState]: { [string]: number } }, { __mode = "k" })
State.MissingStationComplaints = setmetatable({} :: { [ResidentState]: { [string]: boolean } }, { __mode = "k" })
State.PowerOutageComplaints = setmetatable({} :: { [ResidentState]: { [string]: boolean } }, { __mode = "k" })
State.StationIteratorState = {} :: { [number]: { [string]: { version: number, order: { string }, index: number } } }
State.ItemSpecCache = {} :: { [string]: { [string]: any }? }
State.SurvivalUnavailable = setmetatable({} :: { [ResidentState]: { [string]: boolean } }, { __mode = "k" })
State.PendingStationReservations = setmetatable({} :: { [ResidentState]: { StationReservation } }, { __mode = "k" })
State.InterruptedNeedDelays = setmetatable({} :: { [ResidentState]: { [string]: number } }, { __mode = "k" })
State.ForcedNeedPriorities =
	setmetatable({} :: { [ResidentState]: { Need: string, ExpiresAt: number } }, { __mode = "k" })

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

function State.getStationTypesForNeed(needName: string): { string }
	local configured = State.NeedStationTypes[needName]
	if configured then
		return configured
	end
	local single = State.NeedToStationType[needName]
	if single then
		return { single }
	end
	return {}
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
	State.clearInterruptedNeed(resident, needName)
	State.clearForcedNeed(resident, needName)
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

local function getOrCreatePowerOutageComplaints(resident: ResidentState)
	local entry = State.PowerOutageComplaints[resident]
	if not entry then
		entry = {}
		State.PowerOutageComplaints[resident] = entry
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

function State.getPowerOutagePhrases(needName: string)
	return State.PowerOutagePhrases[needName] or State.PowerOutagePhrases._default
end

function State.didComplainPowerOutage(resident: ResidentState, needName: string): boolean
	local entry = State.PowerOutageComplaints[resident]
	return entry ~= nil and entry[needName] == true
end

function State.markPowerOutageComplaint(resident: ResidentState, needName: string)
	local entry = getOrCreatePowerOutageComplaints(resident)
	entry[needName] = true
end

function State.clearPowerOutageComplaint(resident: ResidentState, needName: string)
	local entry = State.PowerOutageComplaints[resident]
	if entry then
		entry[needName] = nil
		if next(entry) == nil then
			State.PowerOutageComplaints[resident] = nil
		end
	end
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

local function getOrCreateReservationList(resident: ResidentState): { StationReservation }
	local list = State.PendingStationReservations[resident]
	if not list then
		list = {}
		State.PendingStationReservations[resident] = list
	end
	return list
end

function State.addPendingStationReservation(resident: ResidentState, stationRecord: any, residentName: string)
	if not stationRecord or residentName == "" then
		return
	end
	local list = getOrCreateReservationList(resident)
	list[#list + 1] = {
		Station = stationRecord,
		ResidentName = residentName,
	}
end

function State.consumePendingStationReservation(
	resident: ResidentState,
	stationRecord: any,
	residentName: string
): StationReservation?
	local list = State.PendingStationReservations[resident]
	if not list then
		return nil
	end
	for index = #list, 1, -1 do
		local entry = list[index]
		if entry.Station == stationRecord and entry.ResidentName == residentName then
			table.remove(list, index)
			if #list == 0 then
				State.PendingStationReservations[resident] = nil
			end
			return entry
		end
	end
	return nil
end

function State.releasePendingStationReservations(resident: ResidentState, releaseFn: (any, string) -> ())
	local list = State.PendingStationReservations[resident]
	if not list then
		return
	end
	State.PendingStationReservations[resident] = nil
	for index = #list, 1, -1 do
		local entry = list[index]
		releaseFn(entry.Station, entry.ResidentName)
	end
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

local function getOrCreateInterrupted(resident: ResidentState)
	local entry = State.InterruptedNeedDelays[resident]
	if not entry then
		entry = {}
		State.InterruptedNeedDelays[resident] = entry
	end
	return entry
end

function State.registerInterruptedNeed(resident: ResidentState, needName: string, nowClock: number?)
	local duration = Constants.INTERRUPTED_NEED_RETRY_SECONDS
	if duration <= 0 then
		return
	end
	local now = nowClock or os.clock()
	local entry = getOrCreateInterrupted(resident)
	entry[needName] = now + duration
end

local function cleanupInterruptedEntry(resident: ResidentState, entry: { [string]: number })
	if next(entry) == nil then
		State.InterruptedNeedDelays[resident] = nil
	end
end

function State.clearInterruptedNeed(resident: ResidentState, needName: string)
	local entry = State.InterruptedNeedDelays[resident]
	if not entry then
		return
	end
	entry[needName] = nil
	cleanupInterruptedEntry(resident, entry)
end

function State.shouldBlockInterruptedNeed(resident: ResidentState, needName: string, nowClock: number): boolean
	local entry = State.InterruptedNeedDelays[resident]
	if not entry then
		return false
	end
	local expire = entry[needName]
	if not expire then
		return false
	end
	if nowClock >= expire then
		entry[needName] = nil
		cleanupInterruptedEntry(resident, entry)
		return false
	end
	return true
end

local function setForcedNeedEntry(resident: ResidentState, needName: string, nowClock: number)
	local timeout = math.max(Constants.FORCED_NEED_TIMEOUT_SECONDS, 0)
	local expiresAt = if timeout > 0 then nowClock + timeout else math.huge
	State.ForcedNeedPriorities[resident] = {
		Need = needName,
		ExpiresAt = expiresAt,
	}
end

function State.setForcedNeed(resident: ResidentState, needName: string, nowClock: number?)
	if needName == "" then
		return
	end
	local now = nowClock or os.clock()
	setForcedNeedEntry(resident, needName, now)
end

function State.getForcedNeed(resident: ResidentState, nowClock: number): string?
	local entry = State.ForcedNeedPriorities[resident]
	if not entry then
		return nil
	end
	if nowClock >= entry.ExpiresAt then
		State.ForcedNeedPriorities[resident] = nil
		return nil
	end
	return entry.Need
end

function State.clearForcedNeed(resident: ResidentState, needName: string?)
	local entry = State.ForcedNeedPriorities[resident]
	if not entry then
		return
	end
	if needName == nil or entry.Need == needName then
		State.ForcedNeedPriorities[resident] = nil
	end
end

State.refreshNeedCooldowns()

return State
