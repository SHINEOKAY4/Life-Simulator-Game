--!strict

local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AutonomyState = require(ServerScriptService.Server.Services.ResidentAutonomyService.State)
local NeedConfig = require(ReplicatedStorage.Shared.Configurations.NeedConfig)
local TimeScale = require(ReplicatedStorage.Shared.Utilities.TimeScale)

local Types = require(script.Parent.Types)

local BehaviorConfig = {}

local Needs = NeedConfig.Needs
local Circadian = NeedConfig.Circadian

export type Effect = Types.Effect
export type Moodlet = Types.Moodlet
export type ChatOption = Types.ChatOption
export type Behavior = Types.Behavior
export type BehaviorSpec = Types.BehaviorSpec

local function humanizeIdentifier(raw: string): string
	local spaced = raw:gsub("(%l)(%u)", "%1 %2")
	spaced = spaced:gsub("[_%-%s]+", " ")
	return spaced:lower()
end

BehaviorConfig.humanizeIdentifier = humanizeIdentifier

function BehaviorConfig.copyNeedBounds(bounds: { [string]: any }?): { [string]: number }?
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

function BehaviorConfig.copyEffects(effects: { Types.RawEffect }?): { Effect }?
	if not effects then
		return nil
	end
	local clone: { Effect } = {}
	for _, effect in ipairs(effects) do
		local need = effect.Need :: string?
		if need then
			local entry: Effect = {
				Need = need,
				InstantAmount = effect.InstantAmount :: number?,
				RatePerHour = effect.RatePerHour :: number?,
			}
			table.insert(clone, entry)
		end
	end
	return clone
end

function BehaviorConfig.copyMoodlets(moodlets: { Types.RawMoodlet }?): { Moodlet }?
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
	if #clone == 0 then
		return nil
	end
	return clone
end

function BehaviorConfig.copyChatPhrases(phrases: { any }?): { ChatOption }?
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
				local minNeeds = BehaviorConfig.copyNeedBounds(phrase.MinNeeds)
				local maxNeeds = BehaviorConfig.copyNeedBounds(phrase.MaxNeeds)
				if typeof(minClock) == "number" then
					option.MinClock = minClock % 24
				end
				if typeof(maxClock) == "number" then
					option.MaxClock = maxClock % 24
				end
				option.MinNeeds = minNeeds
				option.MaxNeeds = maxNeeds
				clone[#clone + 1] = option
			end
		end
	end
	if #clone == 0 then
		return nil
	end
	return clone
end

function BehaviorConfig.shallowCopyBehavior(spec: BehaviorSpec?): Behavior
	local result: Behavior = {}
	if not spec then
		return result
	end
	for key, value in pairs(spec) do
		if key == "Effects" and type(value) == "table" then
			result.Effects = BehaviorConfig.copyEffects(value)
		elseif key == "Moodlets" and type(value) == "table" then
			result.Moodlets = BehaviorConfig.copyMoodlets(value)
		elseif key == "ChatPhrases" and type(value) == "table" then
			result.ChatPhrases = BehaviorConfig.copyChatPhrases(value)
		else
			(result :: any)[key] = value
		end
	end
	return result
end

local function computeEnergyTarget(base: number?, delta: number?): number?
	if not base then
		return nil
	end
	if not delta then
		return base
	end
	return math.clamp(base + delta, Needs.Energy.Min, Needs.Energy.Max)
end

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

local RestProfiles: {
	[string]: {
		Mode: string,
		DurationSeconds: number,
		RatePerHour: number,
		UseSeat: boolean,
		TargetEnergy: number?,
		ChatPhrases: { any }?,
		Moodlets: { { Name: string, DurationSeconds: number, NeedBias: { [string]: number }? } }?,
	},
} =
	{
		Sleep = {
			Mode = "Sleep",
			DurationSeconds = 420,
			RatePerHour = 12,
			UseSeat = false,
			TargetEnergy = computeEnergyTarget(Needs.Energy.Max, -1),
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
			TargetEnergy = computeEnergyTarget(Needs.Energy.Low, Needs.Energy.Hysteresis + 6),
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
		Relax = {
			Mode = "Relax",
			DurationSeconds = 210,
			RatePerHour = 9,
			UseSeat = true,
			TargetEnergy = computeEnergyTarget(Needs.Energy.Low, Needs.Energy.Hysteresis + 4),
			ChatPhrases = {
				{ Text = "Taking a moment to relax." },
				{ Text = "Getting comfy for a bit." },
				{
					Text = "Just lounging for a moment.",
					MinClock = 9,
					MaxClock = 22,
				},
			} :: { any },
			Moodlets = {
				{ Name = "Relaxed", DurationSeconds = 150, NeedBias = { Energy = -0.15, Fun = -0.05 } },
			},
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
			TargetEnergy = nil,
			ChatPhrases = {
				{ Text = "I guess the floor will have to do..." },
				{ Text = "Not ideal, but I need to rest." },
				{
					Text = "Too tired to care where I sleep.",
					MaxNeeds = { Energy = energyCritical },
				},
			} :: { any },
		},
	}

local REST_LIE_MODES: { [string]: boolean } = {
	Sleep = true,
	DaySleep = true,
	Ground = true,
}

BehaviorConfig.REST_LIE_MODES = REST_LIE_MODES

local SEATED_ONLY_REST_MODES: { [string]: boolean } = {
	Nap = true,
	Relax = true,
}

BehaviorConfig.SEATED_ONLY_REST_MODES = SEATED_ONLY_REST_MODES

local function createRestShouldEnd(mode: string, targetEnergy: number?): ((any) -> boolean, (any) -> string?)
	local hungerDef = Needs.Hunger
	local energyDefLocal = Needs.Energy
	local function computeExitReason(residentState): string?
		if hungerDef then
			local hunger = residentState:GetNeed("Hunger")
			if hunger <= hungerDef.Critical then
				if not AutonomyState.isSurvivalNeedUnavailable(residentState, "Hunger") then
					if not energyDefLocal then
						return "NeedUrgent:Hunger"
					end
					local energy = residentState:GetNeed("Energy")
					if energy > energyDefLocal.Critical then
						return "NeedUrgent:Hunger"
					end
				end
			end
		end
		if targetEnergy then
			local energy = residentState:GetNeed("Energy")
			if energy >= targetEnergy then
				if mode == "Sleep" then
					local clockTime = TimeScale.GetClockTime()
					if isNight(clockTime) then
						return nil
					end
				end
				return "EnergySatisfied"
			end
			return nil
		end
		if mode ~= "Sleep" and energyDefLocal then
			local energy = residentState:GetNeed("Energy")
			if energy >= energyDefLocal.Low then
				return "EnergySatisfied"
			end
		end
		return nil
	end
	local function shouldEnd(residentState)
		return computeExitReason(residentState) ~= nil
	end
	return shouldEnd, computeExitReason
end

function BehaviorConfig.applyRestProfile(behavior: Behavior, mode: string?)
	local profile = RestProfiles[mode or "Sleep"] or RestProfiles.Sleep
	behavior.UseSeat = profile.UseSeat
	behavior.DurationSeconds = profile.DurationSeconds
	behavior.Effects = {
		{ Need = "Energy", RatePerHour = profile.RatePerHour },
	}
	local shouldEnd, reasonProvider = createRestShouldEnd(profile.Mode, profile.TargetEnergy)
	behavior.ShouldEnd = shouldEnd
	behavior.EndReasonProvider = reasonProvider
	behavior.Moodlets = if profile.Moodlets then BehaviorConfig.copyMoodlets(profile.Moodlets) else nil
	behavior.ChatPhrases = if profile.ChatPhrases then BehaviorConfig.copyChatPhrases(profile.ChatPhrases) else nil
	behavior.RestProfileKey = profile.Mode

	local existingGuards = behavior.EmergencyGuards
	local hungerGuard = if existingGuards then existingGuards.Hunger else nil
	local energyNeedDef = Needs.Energy
	local guardTable: { [string]: (any, number, any) -> boolean }
	if existingGuards then
		guardTable = existingGuards
	else
		guardTable = {}
	end
	guardTable.Hunger = function(residentState, hungerValue, hungerDef)
		if hungerGuard and hungerGuard(residentState, hungerValue, hungerDef) then
			return true
		end
		if not energyNeedDef then
			return false
		end
		local energyValue = residentState:GetNeed("Energy")
		if typeof(energyValue) ~= "number" then
			return false
		end
		local threshold = 0
		if typeof(energyNeedDef.Low) == "number" then
			threshold = energyNeedDef.Low
		end
		if typeof(energyNeedDef.Critical) == "number" then
			threshold = math.max(threshold, energyNeedDef.Critical)
		end
		return energyValue <= threshold
	end
	behavior.EmergencyGuards = guardTable
end

local StationActionLabels: { [string]: string } = {
	RestStation = "rest",
	CookStation = "cook meal",
	MealStation = "share meal",
	SocialStation = "chat",
	HygieneStation = "wash up",
	ComfortStation = "use restroom",
	FunStation = "have fun",
	FoodStorage = "grab food",
}

BehaviorConfig.StationActionLabels = StationActionLabels

local StationKindLabels: { [string]: string } = {
	RestStation = "bed",
	CookStation = "kitchen",
	MealStation = "meal table",
	SocialStation = "hangout",
	HygieneStation = "sink",
	ComfortStation = "bathroom",
	FunStation = "fun spot",
	FoodStorage = "storage",
}

BehaviorConfig.StationKindLabels = StationKindLabels

function BehaviorConfig.resolveStationDisplayName(assignment: Types.HandlerAssignment, stationType: string): string?
	local spec = assignment.ItemSpec
	if spec then
		local displayName = spec.DisplayName
		if typeof(displayName) == "string" and displayName ~= "" then
			return displayName
		end
		local name = spec.Name
		if typeof(name) == "string" and name ~= "" then
			return name
		end
		local tags = spec.Tags
		if typeof(tags) == "table" then
			for _, tag in ipairs(tags) do
				if typeof(tag) == "string" and tag ~= "" then
					return humanizeIdentifier(tag)
				end
			end
		end
	end
	local fallback = StationKindLabels[stationType]
	if fallback then
		return fallback
	end
	if typeof(stationType) == "string" and stationType ~= "" then
		return humanizeIdentifier(stationType)
	end
	return nil
end

local StationDefaults: { [string]: BehaviorSpec } = {
	RestStation = {
		ApproachDistance = 3,
		MoveTimeoutSeconds = 25,
	},
	CookStation = {
		ApproachDistance = 3,
		MoveTimeoutSeconds = 25,
		DurationSeconds = 30,
		ChatPhrases = {
			"I could use a bite!",
			"Cooking something tasty.",
		},
	},
	MealStation = {
		ApproachDistance = 3,
		MoveTimeoutSeconds = 22,
		UseSeat = true,
		ChatPhrases = {
			"Let's grab a seat and eat.",
			"Time to enjoy this meal together.",
		},
	},
	SocialStation = {
		ApproachDistance = 3,
		MoveTimeoutSeconds = 25,
		DurationSeconds = 180,
		Effects = {
			{ Need = "Social", RatePerHour = 24 },
			{ Need = "Fun", RatePerHour = 8 },
		},
		Moodlets = {
			{ Name = "Chatty", DurationSeconds = 200, NeedBias = { Social = -0.3, Fun = -0.15 } },
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
			local socialDef = Needs.Social
			if not socialDef then
				return false
			end
			local survivalNeeds = AutonomyState.SurvivalNeeds
			for needName in pairs(survivalNeeds) do
				if needName ~= "Social" then
					local needDef = Needs[needName]
					if needDef then
						local value = residentState:GetNeed(needName)
						if value <= needDef.Critical then
							if AutonomyState.isSurvivalNeedUnavailable(residentState, needName) then
								continue
							end
							return true
						end
					end
				end
			end
			local threshold = math.min(socialDef.Max, socialDef.Low + socialDef.Hysteresis)
			return residentState:GetNeed("Social") >= threshold
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
	ComfortStation = {
		ApproachDistance = 3,
		MoveTimeoutSeconds = 18,
		DurationSeconds = 18,
		Effects = {
			{ Need = "Bladder", RatePerHour = 280 },
		},
		ChatPhrases = {
			"I really have to go...",
			"Excuse me for a moment!",
		},
		ShouldEnd = function(residentState)
			local def = Needs.Bladder
			if not def then
				return false
			end
			local threshold = math.min(def.Max, def.Low + def.Hysteresis)
			return residentState:GetNeed("Bladder") >= threshold
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
	FoodStorage = {
		ApproachDistance = 3,
		MoveTimeoutSeconds = 18,
		DurationSeconds = 12,
		ChatPhrases = {
			"Let me grab something quick.",
			"Checking the fridge.",
		},
	},
}

BehaviorConfig.StationDefaults = StationDefaults

function BehaviorConfig.mergeBehavior(stationType: string, itemSpec: { [string]: any }?): Behavior
	local base = StationDefaults[stationType]
	local behavior = BehaviorConfig.shallowCopyBehavior(base)
	local overrides = if itemSpec then itemSpec.StationEffects else nil
	if overrides then
		local overrideCopy = BehaviorConfig.shallowCopyBehavior(overrides :: Behavior)
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
		BehaviorConfig.applyRestProfile(behavior, restMode)
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

function BehaviorConfig.computeMealEatDuration(hungerRestore: number): number
	if hungerRestore <= 0 then
		return 12
	end
	local scaled = math.floor(hungerRestore / 8 + 0.5)
	return math.clamp(scaled, 10, 24)
end

function BehaviorConfig.buildMealEatingBehavior(hungerRestore: number, recipe: any?): Behavior
	local duration = BehaviorConfig.computeMealEatDuration(hungerRestore)
	local recipeName = if recipe
			and typeof(recipe.Name) == "string"
			and recipe.Name ~= ""
		then recipe.Name
		else "this meal"
	local totalRestore = math.max(hungerRestore, 0)
	local ratePerHour = 0
	if duration > 0 and totalRestore > 0 then
		local gameHours = math.max(TimeScale.GameHoursFromRealDelta(duration), 1e-3)
		ratePerHour = totalRestore / gameHours
	end
	local effects: { Effect }? = nil
	if ratePerHour > 0 then
		effects = {
			{ Need = "Hunger", RatePerHour = ratePerHour },
		}
	elseif totalRestore > 0 then
		effects = {
			{ Need = "Hunger", InstantAmount = totalRestore },
		}
	end
	local behavior: Behavior = {
		DurationSeconds = duration,
		Effects = effects,
		ChatPhrases = {
			{ Text = string.format("Enjoying %s.", recipeName) },
			{ Text = "Taking a moment to eat." },
			{ Text = "Digging in." },
		},
		UseSeat = true,
	}
	local moodlets: { Types.Moodlet } = {}
	local moodBonus = recipe and recipe.MoodBonus
	if typeof(moodBonus) == "number" and moodBonus > 0 then
		moodlets[#moodlets + 1] = {
			Name = "WellFed",
			DurationSeconds = 180,
			NeedBias = { Hunger = -0.25 },
		}
	else
		moodlets[#moodlets + 1] = {
			Name = "Satisfied",
			DurationSeconds = 120,
			NeedBias = { Hunger = -0.2 },
		}
	end
	behavior.Moodlets = moodlets
	return behavior
end

function BehaviorConfig.applyMealStationBonus(behavior: Behavior?, seatType: string?, recipe: any?)
	if not behavior or seatType ~= "MealStation" then
		return
	end
	local effects = behavior.Effects
	if not effects then
		effects = {}
		behavior.Effects = effects
	end
	local effectList = effects :: { Effect }
	effectList[#effectList + 1] = { Need = "Social", InstantAmount = 8 }
	effectList[#effectList + 1] = { Need = "Fun", InstantAmount = 4 }
	local moodlets = behavior.Moodlets
	if not moodlets then
		moodlets = {}
		behavior.Moodlets = moodlets
	end
	local moodletList = moodlets :: { Moodlet }
	moodletList[#moodletList + 1] = {
		Name = "SharedMeal",
		DurationSeconds = 150,
		NeedBias = { Social = -0.25, Hunger = -0.1 },
	}
	local recipeName = recipe and recipe.Name
	if typeof(recipeName) == "string" and recipeName ~= "" then
		local chatList = behavior.ChatPhrases
		if not chatList then
			chatList = {}
			behavior.ChatPhrases = chatList
		end
		local chatOptions = chatList :: { ChatOption }
		chatOptions[#chatOptions + 1] = { Text = string.format("Sharing %s together.", recipeName) }
	end
end

function BehaviorConfig.getStationLabel(stationType: string?): string
	if not stationType then
		return "use station"
	end
	return StationActionLabels[stationType] or "use station"
end

return BehaviorConfig
