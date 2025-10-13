--!strict

local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DirectActionService = require(ServerScriptService.Server.Services.DirectActionService)
local ResidentMovement = require(ServerScriptService.Server.Utilities.ResidentMovement)
local NeedEffects = require(ServerScriptService.Server.Utilities.NeedEffects)
local NeedConfig = require(ReplicatedStorage.Shared.Configurations.NeedConfig)
local TimeScale = require(ReplicatedStorage.Shared.Utilities.TimeScale)
local ResidentDebug = require(ServerScriptService.Server.Utilities.ResidentDebug)
local ResidentChat = require(ServerScriptService.Server.Utilities.ResidentChat)

export type HandlerContext = {
	Resident: any,
	CancelToken: { Cancelled: boolean, Reason: string? },
}

export type HandlerAssignment = {
	Player: Player,
	ResidentName: string,
	ResidentState: any,
	StationType: string,
	StationId: string,
	ItemId: string,
	ItemSpec: { [string]: any },
	StationRecord: any,
	StationModel: Model,
	RestModeOverride: string?,
}

local ResidentActionHandlers = {}

type Behavior = {
	ApproachDistance: number?,
	MoveTimeoutSeconds: number?,
	UseSeat: boolean?,
	DurationSeconds: number?,
	ShouldEnd: ((residentState: any) -> boolean)?,
	Effects: { Effect }?,
	Moodlets: { Moodlet }?,
	ChatPhrases: { ChatOption }?,
	ChatIntervalSeconds: number?,
	RestProfileKey: string?,
}

export type BehaviorSpec = {
	ApproachDistance: number?,
	MoveTimeoutSeconds: number?,
	UseSeat: boolean?,
	DurationSeconds: number?,
	ShouldEnd: ((residentState: any) -> boolean)?,
	Effects: { RawEffect }?,
	Moodlets: { RawMoodlet }?,
	ChatPhrases: { any }?,
	ChatIntervalSeconds: number?,
	RestProfileKey: string?,
}

local Needs = NeedConfig.Needs
local Circadian = NeedConfig.Circadian
local ACTION_CHANNEL = "Action"

type RawEffect = { [string]: any }
type Effect = { Need: string, InstantAmount: number?, RatePerHour: number? }
type RawMoodlet = { [string]: any }
type Moodlet = { Name: string, DurationSeconds: number, NeedBias: { [string]: number }? }

type ChatOption = ResidentChat.ChatOption

local function normalizeClock(clock: number): number
	local result = clock % 24
	if result < 0 then
		result += 24
	end
	return result
end

local function copyNeedBounds(bounds: { [string]: any }?): { [string]: number }?
	if typeof(bounds) ~= "table" then
		return nil
	end
	local copy: { [string]: number } = {}
	local count = 0
	for needName, value in pairs(bounds) do
		if typeof(needName) == "string" and typeof(value) == "number" then
			copy[needName] = value
			count += 1
		end
	end
	if count == 0 then
		return nil
	end
	return copy
end

local function copyEffects(effects: { RawEffect }?): { Effect }?
	if not effects then
		return nil
	end
	local clone: { Effect } = {}
	for _, effect in ipairs(effects) do
		local need = effect.Need :: string?
		if need then
			local entry = {
				Need = need,
				InstantAmount = effect.InstantAmount :: number?,
				RatePerHour = effect.RatePerHour :: number?,
			}
			table.insert(clone, entry)
		end
	end
	return clone
end

local function copyMoodlets(moodlets: { RawMoodlet }?): { Moodlet }?
	if not moodlets then
		return nil
	end
	local clone: { Moodlet } = {}
	for _, moodlet in ipairs(moodlets) do
		local name = moodlet.Name :: string?
		local duration = moodlet.DurationSeconds :: number?
		if name and duration and duration > 0 then
			local entry: Moodlet = {
				Name = name,
				DurationSeconds = duration,
				NeedBias = if typeof(moodlet.NeedBias) == "table"
					then moodlet.NeedBias :: { [string]: number }
					else nil,
			}
			table.insert(clone, entry)
		end
	end
	return clone
end

local function copyChatPhrases(phrases: { any }?): { ChatOption }?
	if not phrases then
		return nil
	end
	local clone: { ChatOption } = {}
	for _, phrase in ipairs(phrases) do
		if typeof(phrase) == "string" then
			if phrase ~= "" then
				clone[#clone + 1] = {
					Text = phrase,
					MinClock = nil,
					MaxClock = nil,
					MinNeeds = nil,
					MaxNeeds = nil,
				}
			end
		elseif typeof(phrase) == "table" then
			local text = phrase.Text
			if typeof(text) == "string" and text ~= "" then
				local option: ChatOption = {
					Text = text,
					MinClock = nil,
					MaxClock = nil,
					MinNeeds = nil,
					MaxNeeds = nil,
				}
				local minClock = phrase.MinClock
				local maxClock = phrase.MaxClock
				local minNeeds = copyNeedBounds(phrase.MinNeeds)
				local maxNeeds = copyNeedBounds(phrase.MaxNeeds)
				if typeof(minClock) == "number" then
					option.MinClock = normalizeClock(minClock)
				end
				if typeof(maxClock) == "number" then
					option.MaxClock = normalizeClock(maxClock)
				end
				if minNeeds then
					option.MinNeeds = minNeeds
				end
				if maxNeeds then
					option.MaxNeeds = maxNeeds
				end
				clone[#clone + 1] = option
			end
		end
	end
	if #clone == 0 then
		return nil
	end
	return clone
end

local function shallowCopyBehavior(spec: BehaviorSpec?): Behavior
	local result: Behavior = {}
	if not spec then
		return result
	end
	for key, value in pairs(spec) do
		if key == "Effects" and type(value) == "table" then
			result.Effects = copyEffects(value)
		elseif key == "Moodlets" and type(value) == "table" then
			result.Moodlets = copyMoodlets(value)
		elseif key == "ChatPhrases" and type(value) == "table" then
			result.ChatPhrases = copyChatPhrases(value)
		else
			(result :: any)[key] = value
		end
	end
	return result
end

local StationDefaults: { [string]: BehaviorSpec } = {
	RestStation = {
		ApproachDistance = 3,
		MoveTimeoutSeconds = 25,
	},
	CookStation = {
		ApproachDistance = 3,
		MoveTimeoutSeconds = 25,
		DurationSeconds = 20,
		Effects = {
			{ Need = "Hunger", RatePerHour = 360 },
		},
		Moodlets = {
			{ Name = "Satisfied", DurationSeconds = 120, NeedBias = { Hunger = -0.2 } },
		},
		ChatPhrases = {
			"I could use a bite!",
			"Cooking something tasty.",
		},
		ShouldEnd = function(residentState)
			local def = Needs.Hunger
			if not def then
				return false
			end
			local threshold = math.min(def.Max, def.Low + def.Hysteresis)
			return residentState:GetNeed("Hunger") >= threshold
		end,
	},
	SocialStation = {
		ApproachDistance = 3,
		MoveTimeoutSeconds = 25,
		DurationSeconds = 180,
		Effects = {
			{ Need = "Fun", RatePerHour = 12 },
		},
		Moodlets = {
			{ Name = "Entertained", DurationSeconds = 180, NeedBias = { Fun = -0.25 } },
		},
		ChatIntervalSeconds = 6,
		ChatPhrases = {
			"Let's catch up!",
			"I want to chat for a bit.",
			"Anything exciting happen today?",
			"Tell me about your day!",
			"You won't believe what I heard earlier.",
			"We should plan something fun soon.",
			"I love hearing your stories.",
			"Got any good gossip?",
		},
		ShouldEnd = function(residentState)
			local def = Needs.Fun
			if not def then
				return false
			end
			local threshold = math.min(def.Max, def.Low + def.Hysteresis)
			return residentState:GetNeed("Fun") >= threshold
		end,
	},
	HygieneStation = {
		ApproachDistance = 3,
		MoveTimeoutSeconds = 25,
		DurationSeconds = 22,
		Effects = {
			{ Need = "Hygiene", RatePerHour = 320 },
		},
		Moodlets = {
			{ Name = "Fresh", DurationSeconds = 160, NeedBias = { Hygiene = -0.25 } },
		},
		ChatPhrases = {
			"I need to freshen up!",
			"Time for a quick wash.",
		},
		ShouldEnd = function(residentState)
			local def = Needs.Hygiene
			if not def then
				return false
			end
			local threshold = math.min(def.Max, def.Low + def.Hysteresis)
			return residentState:GetNeed("Hygiene") >= threshold
		end,
	},
	FunStation = {
		ApproachDistance = 3,
		MoveTimeoutSeconds = 25,
		DurationSeconds = 150,
		Effects = {
			{ Need = "Fun", RatePerHour = 18 },
		},
		Moodlets = {
			{ Name = "Entertained", DurationSeconds = 200, NeedBias = { Fun = -0.3 } },
		},
		ChatPhrases = {
			"I need some fun!",
			"This will be exciting!",
		},
		ShouldEnd = function(residentState)
			local def = Needs.Fun
			if not def then
				return false
			end
			local threshold = math.min(def.Max, def.Low + def.Hysteresis)
			return residentState:GetNeed("Fun") >= threshold
		end,
	},
}

type RestProfile = {
	Mode: string,
	DurationSeconds: number,
	RatePerHour: number,
	UseSeat: boolean,
	TargetEnergy: number?,
	ChatPhrases: { any }?,
	Moodlets: { { Name: string, DurationSeconds: number, NeedBias: { [string]: number }? } }?,
}

local function computeEnergyTarget(base: number?, delta: number?): number?
	if not base then
		return nil
	end
	if not delta then
		return base
	end
	return math.clamp(base + delta, Needs.Energy.Min, Needs.Energy.Max)
end

local SleepTarget = computeEnergyTarget(Needs.Energy.Max, -1)
local NapTarget = computeEnergyTarget(Needs.Energy.Low, Needs.Energy.Hysteresis + 6)
local GroundTarget = computeEnergyTarget(Needs.Energy.Low, 4)

local energyDef = Needs.Energy
local energyLow = if energyDef then energyDef.Low else 40
local energyCritical = if energyDef then energyDef.Critical else 15

local function isNight(clockTime: number): boolean
	local nightStart = Circadian.NightStart
	local dayStart = Circadian.DayStart
	if nightStart <= dayStart then
		if nightStart == dayStart then
			return clockTime >= nightStart
		end
		return clockTime >= nightStart and clockTime < dayStart
	end
	return clockTime >= nightStart or clockTime < dayStart
end

local RestProfiles: { [string]: RestProfile } = {
	Sleep = {
		Mode = "Sleep",
		DurationSeconds = 420,
		RatePerHour = 12,
		UseSeat = false,
		TargetEnergy = SleepTarget,
		ChatPhrases = {
			{
				Text = "Turning in for the night...",
				MinClock = 19,
				MaxClock = 6,
			},
			{
				Text = "I'm exhausted... time to lie down.",
				MaxNeeds = { Energy = energyLow },
			},
			{
				Text = "Time for a long rest.",
			},
			{
				Text = "Grabbing proper sleep while I can.",
				MinClock = 6,
				MaxClock = 19,
			},
		} :: { any },
		Moodlets = {
			{ Name = "WellRested", DurationSeconds = 240, NeedBias = { Energy = -0.3 } },
		},
	},
	Nap = {
		Mode = "Nap",
		DurationSeconds = 180,
		RatePerHour = 10,
		UseSeat = true,
		TargetEnergy = NapTarget,
		ChatPhrases = {
			{
				Text = "Just a quick nap...",
				MaxClock = 20,
			},
			{
				Text = "Let me rest my eyes for a bit.",
			},
			{
				Text = "Power nap coming right up.",
				MinClock = 10,
				MaxClock = 18,
			},
		} :: { any },
	},
	DaySleep = {
		Mode = "DaySleep",
		DurationSeconds = 240,
		RatePerHour = 10,
		UseSeat = false,
		TargetEnergy = computeEnergyTarget(Needs.Energy.Low, Needs.Energy.Hysteresis + 4),
		ChatPhrases = {
			{
				Text = "Grabbing a quick lie-down...",
				MinClock = 8,
				MaxClock = 20,
			},
			{
				Text = "Just resting until I'm steady again.",
				MaxNeeds = { Energy = energyLow },
			},
			{
				Text = "Can't burn out—short reset time.",
			},
		} :: { any },
	},
	Ground = {
		Mode = "Ground",
		DurationSeconds = 420,
		RatePerHour = 6,
		UseSeat = false,
		TargetEnergy = GroundTarget,
		ChatPhrases = {
			{
				Text = "I guess the floor will have to do...",
			},
			{
				Text = "Not ideal, but I need to rest.",
			},
			{
				Text = "Too tired to care where I sleep.",
				MaxNeeds = { Energy = energyCritical },
			},
		} :: { any },
	},
}

local function createRestShouldEnd(mode: string, targetEnergy: number?): (any) -> boolean
	local hungerDef = Needs.Hunger
	local energyDefLocal = Needs.Energy
	return function(residentState)
		if hungerDef and residentState:GetNeed("Hunger") <= hungerDef.Critical then
			return true
		end
		if targetEnergy then
			local energy = residentState:GetNeed("Energy")
			if energy >= targetEnergy then
				if mode == "Sleep" then
					local clockTime = TimeScale.GetClockTime()
					if isNight(clockTime) then
						return false
					end
				end
				return true
			end
		end
		if mode ~= "Sleep" and energyDefLocal then
			local energy = residentState:GetNeed("Energy")
			if energy >= energyDefLocal.Low then
				return true
			end
		end
		return false
	end
end

local function applyRestProfile(behavior: Behavior, mode: string?)
	local profile = RestProfiles[mode or "Sleep"] or RestProfiles.Sleep
	local activeMode = profile.Mode
	behavior.UseSeat = profile.UseSeat
	behavior.DurationSeconds = profile.DurationSeconds
	behavior.Effects = {
		{ Need = "Energy", RatePerHour = profile.RatePerHour },
	}
	behavior.ShouldEnd = createRestShouldEnd(activeMode, profile.TargetEnergy)
	behavior.Moodlets = if profile.Moodlets then copyMoodlets(profile.Moodlets) else nil
	behavior.ChatPhrases = if profile.ChatPhrases then copyChatPhrases(profile.ChatPhrases) else nil
	behavior.RestProfileKey = activeMode
end

local function mergeBehavior(stationType: string, itemSpec: { [string]: any }): Behavior
	local base = StationDefaults[stationType]
	local behavior = shallowCopyBehavior(base)
	local overrides = itemSpec and itemSpec.StationEffects
	if overrides then
		local overrideCopy = shallowCopyBehavior(overrides :: Behavior)
		for key, value in pairs(overrideCopy) do
			(behavior :: any)[key] = value
		end
	end
	if stationType == "RestStation" then
		local overrideChat = behavior.ChatPhrases
		local overrideMoodlets = behavior.Moodlets
		local behaviorAny = behavior :: any
		local restMode = behaviorAny.RestMode
		behaviorAny.RestMode = nil
		applyRestProfile(behavior, restMode)
		if overrideChat ~= nil then
			behavior.ChatPhrases = overrideChat
		end
		if overrideMoodlets ~= nil then
			behavior.Moodlets = overrideMoodlets
		end
	end
	if not behavior.Effects then
		behavior.Effects = {}
	end
	return behavior
end

local function executeStationAction(stationType: string, context: HandlerContext, assignment: HandlerAssignment)
	if context.CancelToken.Cancelled then
		return
	end
	ResidentDebug.Trace(
		ACTION_CHANNEL,
		string.format("Handler start: %s -> %s", assignment.ResidentName, stationType),
		{
			Resident = assignment.ResidentName,
			StationType = stationType,
			StationId = assignment.StationId,
		}
	)
	local behavior = mergeBehavior(stationType, assignment.ItemSpec)
	if stationType == "RestStation" then
		local restOverride = assignment.RestModeOverride
		if restOverride and restOverride ~= behavior.RestProfileKey then
			local baseProfile = behavior.RestProfileKey
			local allowOverride = true
			if baseProfile == "Nap" and restOverride ~= "Nap" then
				allowOverride = false
			end
			if allowOverride then
				applyRestProfile(behavior, restOverride)
			end
		end
	end
	local occupantIndex: number? = nil
	local occupantCount: number? = nil
	local stationRecord = assignment.StationRecord
	if stationRecord then
		local residents = stationRecord.Residents
		if typeof(residents) == "table" then
			occupantCount = #residents
			local foundIndex = table.find(residents, assignment.ResidentName)
			if foundIndex then
				occupantIndex = foundIndex
			end
		end
	end
	local itemSpec = assignment.ItemSpec
	if itemSpec then
		local maxOccupancy = itemSpec.maxOccupancy
		if typeof(maxOccupancy) == "number" and maxOccupancy > 0 then
			if not occupantCount or occupantCount < maxOccupancy then
				occupantCount = maxOccupancy
			end
		end
	end
	local arrived, arrival = ResidentMovement.GoToStation(assignment.ResidentState, assignment.StationModel, {
		CancelToken = context.CancelToken,
		ApproachDistance = behavior.ApproachDistance,
		TimeoutSeconds = behavior.MoveTimeoutSeconds,
		EnsureSeat = behavior.UseSeat,
		OccupantIndex = occupantIndex,
		OccupantCount = occupantCount,
	})
	if not arrived or context.CancelToken.Cancelled then
		ResidentDebug.Trace(ACTION_CHANNEL, string.format("Movement failed in handler: %s", assignment.ResidentName), {
			Resident = assignment.ResidentName,
			StationType = stationType,
		})
		return
	end
	if arrival then
		ResidentMovement.FaceStation(assignment.ResidentState, arrival.EntryCFrame)
		if behavior.UseSeat and arrival.Seat then
			ResidentMovement.SeatResident(assignment.ResidentState, arrival.Seat, context.CancelToken)
		end
	end
	if not behavior.ChatIntervalSeconds then
		local initialLine = ResidentChat.SelectChatText(assignment.ResidentState, behavior.ChatPhrases, nil)
		if initialLine then
			ResidentChat.ShowAction(assignment.ResidentState, initialLine)
		end
	end
	ResidentDebug.Trace(ACTION_CHANNEL, string.format("Running effects: %s", assignment.ResidentName), {
		Resident = assignment.ResidentName,
		StationType = stationType,
		Behavior = behavior,
	})
	NeedEffects.Run(assignment.ResidentState, context.CancelToken, behavior)
	if arrival and behavior.UseSeat then
		ResidentMovement.LeaveSeat(assignment.ResidentState, arrival.Seat)
	end
	ResidentDebug.Trace(
		ACTION_CHANNEL,
		string.format("Handler completed: %s -> %s", assignment.ResidentName, stationType),
		{
			Resident = assignment.ResidentName,
			StationType = stationType,
		}
	)
end

local function register(stationType: string, handler: (context: HandlerContext, assignment: HandlerAssignment) -> ())
	DirectActionService.RegisterHandler(stationType, handler)
end

local function handleRestStation(context: HandlerContext, assignment: HandlerAssignment)
	executeStationAction("RestStation", context, assignment)
end

local function handleCookStation(context: HandlerContext, assignment: HandlerAssignment)
	executeStationAction("CookStation", context, assignment)
end

local function handleSocialStation(context: HandlerContext, assignment: HandlerAssignment)
	executeStationAction("SocialStation", context, assignment)
end

local function handleHygieneStation(context: HandlerContext, assignment: HandlerAssignment)
	executeStationAction("HygieneStation", context, assignment)
end

local function handleFunStation(context: HandlerContext, assignment: HandlerAssignment)
	executeStationAction("FunStation", context, assignment)
end

register("RestStation", handleRestStation)
register("CookStation", handleCookStation)
register("SocialStation", handleSocialStation)
register("HygieneStation", handleHygieneStation)
register("FunStation", handleFunStation)

function ResidentActionHandlers.GetDefaultBehavior(stationType: string): BehaviorSpec?
	local base = StationDefaults[stationType]
	if not base then
		return nil
	end
	local behavior = shallowCopyBehavior(base)
	if stationType == "RestStation" then
		applyRestProfile(behavior, "Sleep")
	end
	return behavior
end

function ResidentActionHandlers.GetRestBehavior(mode: string?): BehaviorSpec?
	local base = StationDefaults.RestStation
	if not base then
		return nil
	end
	local behavior = shallowCopyBehavior(base)
	applyRestProfile(behavior, mode)
	return behavior
end

function ResidentActionHandlers.GetDirectSocialBehavior(): BehaviorSpec?
	local base = StationDefaults.SocialStation
	if not base then
		return nil
	end
	return shallowCopyBehavior(base)
end

return ResidentActionHandlers
