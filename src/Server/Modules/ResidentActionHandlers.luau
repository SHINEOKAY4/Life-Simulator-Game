--!strict

local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DirectActionService = require(ServerScriptService.Server.Services.DirectActionService)
local KitchenService = require(ServerScriptService.Server.Services.KitchenService)
local ResidentMovement = require(ServerScriptService.Server.Utilities.ResidentMovement)
local NeedEffects = require(ServerScriptService.Server.Utilities.NeedEffects)
local NeedConfig = require(ReplicatedStorage.Shared.Configurations.NeedConfig)
local TimeScale = require(ReplicatedStorage.Shared.Utilities.TimeScale)
local ResidentDebug = require(ServerScriptService.Server.Utilities.ResidentDebug)
local ResidentChat = require(ServerScriptService.Server.Utilities.ResidentChat)
local AutonomyState = require(ServerScriptService.Server.Services.ResidentAutonomyService.State)
local StationManager = require(ServerScriptService.Server.Services.ResidentAutonomyService.StationManager)
local MealRecipesModule = require(ReplicatedStorage.Shared.Definitions.MealRecipes)
local FoodUtils = require(ReplicatedStorage.Shared.Utilities.FoodUtils)
local MealRecipes = MealRecipesModule.Recipes

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
	NeedName: string?,
	RestModeOverride: string?,
	ManualOverride: boolean?,
	ActionMode: string?,
	TargetContainerId: string?,
	PreparedMealId: string?,
	PreparedMealServings: number?,
	PreparedMealHungerPerPortion: number?,
}

local ResidentActionHandlers = {}
type CookingSession = KitchenService.CookingSession

type EmergencyGuard = (residentState: any, value: number, def: NeedConfig.NeedDef) -> boolean

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
	EndReasonProvider: ((residentState: any) -> string?)?,
	EmergencyGuards: { [string]: EmergencyGuard }?,
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
	EndReasonProvider: ((residentState: any) -> string?)?,
	EmergencyGuards: { [string]: EmergencyGuard }?,
}

local Needs = NeedConfig.Needs
local Circadian = NeedConfig.Circadian
local ACTION_CHANNEL = "Action"

local StationActionLabels: { [string]: string } = {
	RestStation = "rest",
	CookStation = "cook meal",
	MealStation = "share meal",
	SocialStation = "chat",
	HygieneStation = "wash up",
	FunStation = "have fun",
	FoodStorage = "grab food",
}

local StationKindLabels: { [string]: string } = {
	RestStation = "bed",
	CookStation = "kitchen",
	MealStation = "meal table",
	SocialStation = "hangout",
	HygieneStation = "sink",
	FunStation = "fun spot",
	FoodStorage = "storage",
}

local KitchenFailurePhrases: { [string]: string } = {
	NoCookableRecipe = "We need groceries before we can cook anything.",
	InsufficientIngredients = "We are out of ingredients right now.",
	KitchenStateUnavailable = "The kitchen isn't ready yet.",
	RecipeMissing = "I can't figure out what to cook just yet.",
	KitchenLocked = "The kitchen is closing up right now.",
}

type RawEffect = { [string]: any }
type Effect = { Need: string, InstantAmount: number?, RatePerHour: number? }
type RawMoodlet = { [string]: any }
type Moodlet = { Name: string, DurationSeconds: number, NeedBias: { [string]: number }? }

type ChatOption = ResidentChat.ChatOption

local function humanizeIdentifier(raw: string): string
	local spaced = raw:gsub("(%l)(%u)", "%1 %2")
	spaced = spaced:gsub("[_%-%s]+", " ")
	return spaced:lower()
end

local function resolveStationDisplayName(assignment: HandlerAssignment, stationType: string): string?
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

local function itemHasTag(itemSpec: { [string]: any }?, tag: string): boolean
	if not itemSpec then
		return false
	end
	local tags = itemSpec.Tags
	if typeof(tags) ~= "table" then
		return false
	end
	for _, value in ipairs(tags) do
		if typeof(value) == "string" and value == tag then
			return true
		end
	end
	return false
end

local DINING_STATION_PREFERENCES: { { StationType: string, RequiredTag: string? } } = {
	{ StationType = "MealStation" },
	{ StationType = "SocialStation", RequiredTag = "Table" },
	{ StationType = "FunStation", RequiredTag = "Table" },
	{ StationType = "RestStation", RequiredTag = "Seating" },
}

local function selectDiningStation(
	player: Player?,
	residentName: string
): (string?, string?, StationManager.StationRecord?, { [string]: any }?, Model?)
	if not player then
		return nil, nil, nil, nil, nil
	end
	for _, preference in ipairs(DINING_STATION_PREFERENCES) do
		local stationType = preference.StationType
		local requiredTag = preference.RequiredTag
		local filter
		if requiredTag then
			filter = function(_id: string, _station: StationManager.StationRecord, itemSpec: { [string]: any }?)
				return itemHasTag(itemSpec, requiredTag)
			end
		end
		local uniqueId, stationRecord, itemSpec, model =
			StationManager.findAvailableStation(player, stationType, residentName, nil, filter)
		if uniqueId and stationRecord and model then
			return stationType, uniqueId, stationRecord, itemSpec, model
		end
	end
	return nil, nil, nil, nil, nil
end

local function reserveAuxStation(stationRecord: StationManager.StationRecord, residentName: string)
	if not table.find(stationRecord.Residents, residentName) then
		table.insert(stationRecord.Residents, residentName)
	end
	stationRecord.Occupied = true
end

local function releaseAuxStation(stationRecord: StationManager.StationRecord?, residentName: string)
	if not stationRecord then
		return
	end
	StationManager.releaseStationOccupancy(stationRecord, residentName)
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
local GroundTarget = nil

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

local REST_LIE_MODES: { [string]: boolean } = {
	Sleep = true,
	DaySleep = true,
	Ground = true,
}

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
			-- Don't exit early if we haven't reached target yet
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

local function applyRestProfile(behavior: Behavior, mode: string?)
	local profile = RestProfiles[mode or "Sleep"] or RestProfiles.Sleep
	local activeMode = profile.Mode
	behavior.UseSeat = profile.UseSeat
	behavior.DurationSeconds = profile.DurationSeconds
	behavior.Effects = {
		{ Need = "Energy", RatePerHour = profile.RatePerHour },
	}
	local shouldEnd, reasonProvider = createRestShouldEnd(activeMode, profile.TargetEnergy)
	behavior.ShouldEnd = shouldEnd
	behavior.EndReasonProvider = reasonProvider
	behavior.Moodlets = if profile.Moodlets then copyMoodlets(profile.Moodlets) else nil
	behavior.ChatPhrases = if profile.ChatPhrases then copyChatPhrases(profile.ChatPhrases) else nil
	behavior.RestProfileKey = activeMode
	local existingGuards = behavior.EmergencyGuards
	local hungerGuard = if existingGuards then existingGuards.Hunger else nil
	local energyNeedDef = Needs.Energy
	local guardTable: { [string]: EmergencyGuard }
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
		if residentState == nil or typeof(residentState.GetNeed) ~= "function" then
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

local function computeMealEatDuration(hungerRestore: number): number
	if hungerRestore <= 0 then
		return 12
	end
	local scaled = math.floor(hungerRestore / 8 + 0.5)
	return math.clamp(scaled, 10, 24)
end

local function buildMealEatingBehavior(hungerRestore: number, recipe: any): Behavior
	local duration = computeMealEatDuration(hungerRestore)
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
	}
	local moodlets: { Moodlet } = {}
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

local function applyMealStationBonus(behavior: Behavior?, seatType: string?, recipe: any?)
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

local function executeStationAction(stationType: string, context: HandlerContext, assignment: HandlerAssignment)
	if context.CancelToken.Cancelled then
		return
	end
	local actionMode = assignment.ActionMode
	local isSnack = actionMode == "Snack"
	local isPreparedMeal = actionMode == "PreparedMeal"
	local actionLabel = StationActionLabels[stationType] or "use station"
	if stationType == "CookStation" then
		if isSnack then
			actionLabel = "grab snack"
		elseif isPreparedMeal then
			actionLabel = "eat meal"
		else
			actionLabel = "cook meal"
		end
	end
	if isPreparedMeal and stationType ~= "CookStation" then
		actionLabel = "eat meal"
	end
	local stationName = resolveStationDisplayName(assignment, stationType)
	ResidentDebug.Trace(
		ACTION_CHANNEL,
		string.format("Handler start: %s -> %s", assignment.ResidentName, stationType),
		{
			Resident = assignment.ResidentName,
			StationType = stationType,
			StationId = assignment.StationId,
		}
	)
	local diningReservationRecord: StationManager.StationRecord? = nil
	local diningReservationType: string? = nil
	local diningReservationModel: Model? = nil
	local diningReservationItemSpec: { [string]: any }? = nil
	local diningReservationUniqueId: string? = nil
	local followUpStationTypeOverride: string? = nil
	local followUpStationIdOverride: string? = nil
	local followUpStationNameOverride: string? = nil
	local diningArrivalInfo: any = nil
	local function releaseDiningReservation()
		releaseAuxStation(diningReservationRecord, assignment.ResidentName)
		diningReservationRecord = nil
		diningReservationType = nil
		diningReservationModel = nil
		diningReservationItemSpec = nil
		diningReservationUniqueId = nil
		followUpStationTypeOverride = nil
		followUpStationIdOverride = nil
		followUpStationNameOverride = nil
		diningArrivalInfo = nil
	end
	local function ensureDiningReservation()
		if diningReservationRecord then
			return
		end
		local seatStationType, seatUniqueId, seatRecord, seatItemSpec, seatModel =
			selectDiningStation(assignment.Player, assignment.ResidentName)
		if seatStationType and seatRecord and seatModel then
			reserveAuxStation(seatRecord, assignment.ResidentName)
			diningReservationRecord = seatRecord
			diningReservationType = seatStationType
			diningReservationModel = seatModel
			diningReservationItemSpec = seatItemSpec
			diningReservationUniqueId = seatUniqueId
		end
	end

	local primaryReleased = false
	local function releasePrimaryReservation()
		if primaryReleased then
			return
		end
		primaryReleased = true
		local stationRecord = assignment.StationRecord
		if stationRecord then
			StationManager.releaseStationOccupancy(stationRecord, assignment.ResidentName)
		end
	end
	local preparedMealId: string? = nil
	local preparedMealServings = 0
	local preparedMealHungerPerPortion = 0
	local preparedMealRecipe: MealRecipesModule.MealRecipe? = nil
	if isPreparedMeal then
		preparedMealId = assignment.PreparedMealId
		preparedMealServings = math.max(1, assignment.PreparedMealServings or 1)
		preparedMealHungerPerPortion = assignment.PreparedMealHungerPerPortion or 0
		if preparedMealId then
			preparedMealRecipe = MealRecipes[preparedMealId]
		end
	end
	local followUpBehavior: Behavior? = nil
	local followUpRecipe: MealRecipesModule.MealRecipe? = nil
	local behavior = mergeBehavior(stationType, assignment.ItemSpec)
	if isSnack then
		behavior.DurationSeconds = behavior.DurationSeconds or 16
		if not behavior.ChatPhrases then
			behavior.ChatPhrases = {
				{ Text = "Grabbing a quick snack." },
				{ Text = "Let me eat something fast." },
			}
		end
	elseif isPreparedMeal then
		behavior.DurationSeconds = math.min(behavior.DurationSeconds or 10, 6)
		behavior.Effects = nil
		if not behavior.ChatPhrases then
			behavior.ChatPhrases = {
				{ Text = "Let me plate some leftovers." },
				{ Text = "Warming up a meal." },
			}
		end
	end
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
	local manualOverride = assignment.ManualOverride == true
	if manualOverride and assignment.NeedName then
		local needDef = Needs[assignment.NeedName]
		if needDef then
			local originalShouldEnd = behavior.ShouldEnd
			behavior.ShouldEnd = function(residentState)
				local getter = residentState and residentState.GetNeed
				if typeof(getter) == "function" then
					local value = getter(residentState, assignment.NeedName)
					if typeof(value) == "number" then
						if value >= needDef.Max then
							return true
						end
						return false
					end
				end
				if originalShouldEnd then
					return originalShouldEnd(residentState)
				end
				return false
			end
			local originalReason = behavior.EndReasonProvider
			behavior.EndReasonProvider = function(residentState)
				local getter = residentState and residentState.GetNeed
				if typeof(getter) == "function" then
					local value = getter(residentState, assignment.NeedName)
					if typeof(value) == "number" and value >= needDef.Max then
						return "NeedFull:" .. assignment.NeedName
					end
				end
				if originalReason then
					return originalReason(residentState)
				end
				return nil
			end
		end
	end
	local restPoseMode: string? = nil
	local restPoseEligible = false
	if stationType == "RestStation" then
		restPoseMode = behavior.RestProfileKey
		if restPoseMode and REST_LIE_MODES[restPoseMode] and behavior.UseSeat ~= true then
			restPoseEligible = true
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

	local cookingSession: CookingSession? = nil
	if stationType == "CookStation" and assignment.Player and not isSnack and not isPreparedMeal then
		local beginOk, beginResult = KitchenService.BeginCooking(assignment.Player, assignment, behavior, nil)
		if not beginOk then
			local reason = tostring(beginResult)
			ResidentChat.ShowInterrupt(assignment.ResidentState, reason, {
				StationType = stationType :: string,
				StationId = assignment.StationId,
				StationName = stationName,
				NeedName = assignment.NeedName,
				ActionName = actionLabel,
				Player = assignment.Player,
			})
			ResidentDebug.Trace(ACTION_CHANNEL, string.format("Kitchen session blocked: %s", assignment.ResidentName), {
				Resident = assignment.ResidentName,
				StationType = stationType,
				Failure = reason,
				Hint = KitchenFailurePhrases[reason],
			})
			return
		end
		cookingSession = beginResult :: CookingSession
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
		local cancelToken = context.CancelToken
		local reason = "MovementFailed"
		if cancelToken.Cancelled then
			reason = cancelToken.Reason or "Cancelled"
		end
		if cookingSession then
			KitchenService.CancelCooking(cookingSession, reason)
			cookingSession = nil
		end
		ResidentChat.ShowInterrupt(assignment.ResidentState, reason, {
			StationType = stationType :: string,
			StationId = assignment.StationId,
			StationName = stationName,
			NeedName = assignment.NeedName,
			ActionName = actionLabel,
		})
		ResidentDebug.Trace(ACTION_CHANNEL, string.format("Movement failed in handler: %s", assignment.ResidentName), {
			Resident = assignment.ResidentName,
			StationType = stationType,
		})
		releaseDiningReservation()
		return
	end
	local restPoseApplied = false
	if arrival then
		ResidentMovement.FaceStation(assignment.ResidentState, arrival.EntryCFrame)
		if restPoseEligible then
			restPoseApplied = ResidentMovement.ApplyRestPose(assignment.ResidentState, {
				Mode = restPoseMode,
				StationModel = assignment.StationModel,
				EntryCFrame = arrival.EntryCFrame,
				EntryAttachment = arrival.EntryAttachment,
			})
		end
		if behavior.UseSeat and arrival.Seat then
			ResidentMovement.SeatResident(assignment.ResidentState, arrival.Seat, context.CancelToken)
		end
	end
	if isSnack then
		local player = assignment.Player
		local containerId = assignment.TargetContainerId or assignment.StationId
		if not player or not containerId or containerId == "" then
			ResidentChat.ShowInterrupt(assignment.ResidentState, "NoFoodAvailable", {
				StationType = stationType :: string,
				StationId = assignment.StationId,
				StationName = stationName,
				NeedName = assignment.NeedName,
				ActionName = actionLabel,
			})
			releaseDiningReservation()
			return
		end
		local consumeOk, hungerRestore = KitchenService.TryConsumeEdibleFromContainer(player, containerId)
		if not consumeOk or not hungerRestore or hungerRestore <= 0 then
			ResidentChat.ShowInterrupt(assignment.ResidentState, "NoFoodAvailable", {
				StationType = stationType :: string,
				StationId = assignment.StationId,
				StationName = stationName,
				NeedName = assignment.NeedName,
				ActionName = actionLabel,
			})
			releaseDiningReservation()
			return
		end
		followUpBehavior = buildMealEatingBehavior(hungerRestore, nil)
		behavior.Effects = nil
		ensureDiningReservation()
	elseif isPreparedMeal then
		local player = assignment.Player
		if not player or not preparedMealId or preparedMealHungerPerPortion <= 0 then
			ResidentChat.ShowInterrupt(assignment.ResidentState, "NoFoodAvailable", {
				StationType = stationType :: string,
				StationId = assignment.StationId,
				StationName = stationName,
				NeedName = assignment.NeedName,
				ActionName = actionLabel,
			})
			releaseDiningReservation()
			return
		end
		local consumed = KitchenService.ConsumePreparedMeal(player, preparedMealId, preparedMealServings)
		if not consumed then
			ResidentChat.ShowInterrupt(assignment.ResidentState, "NoFoodAvailable", {
				StationType = stationType :: string,
				StationId = assignment.StationId,
				StationName = stationName,
				NeedName = assignment.NeedName,
				ActionName = actionLabel,
			})
			releaseDiningReservation()
			return
		end
		local totalRestore = preparedMealHungerPerPortion * preparedMealServings
		if totalRestore <= 0 and preparedMealRecipe then
			totalRestore = FoodUtils.ComputeHungerEffect(preparedMealRecipe.HungerRestore)
		end
		if totalRestore <= 0 then
			totalRestore = 12
		end
		followUpBehavior = buildMealEatingBehavior(totalRestore, preparedMealRecipe)
		followUpRecipe = preparedMealRecipe
		ensureDiningReservation()
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

	local abortReason: string? = nil
	local stageSuccess = false
	local stageError: any = nil
	local stageAbortReason: string? = nil

	local runOk, runResult, runReason = pcall(function()
		return NeedEffects.Run(assignment.ResidentState, context.CancelToken, behavior, {
			StationType = stationType,
			StationId = assignment.StationId,
			StationName = stationName,
			NeedName = assignment.NeedName,
			ActionName = actionLabel,
			Player = assignment.Player,
		})
	end)

	if runOk then
		if runResult == true then
			stageSuccess = true
		else
			stageAbortReason = runReason
			if not stageAbortReason or stageAbortReason == "" then
				if context.CancelToken.Cancelled then
					stageAbortReason = context.CancelToken.Reason or "Cancelled"
				else
					stageAbortReason = "Interrupted"
				end
			end
		end
	else
		stageError = runResult
	end

	if cookingSession then
		if stageSuccess then
			if context.CancelToken.Cancelled then
				KitchenService.CancelCooking(cookingSession, context.CancelToken.Reason or "Cancelled")
			else
				local consumedPortions, recipe = KitchenService.CompleteCooking(cookingSession)
				if consumedPortions and consumedPortions > 0 and recipe then
					local perPortion = FoodUtils.ComputeHungerEffect(recipe.HungerRestore)
					local totalRestore = perPortion * consumedPortions
					if totalRestore > 0 then
						followUpBehavior = buildMealEatingBehavior(totalRestore, recipe)
						followUpRecipe = recipe
						ensureDiningReservation()
					end
				end
			end
		else
			local cancelReason = stageAbortReason
			if not cancelReason or cancelReason == "" then
				if context.CancelToken.Cancelled then
					cancelReason = context.CancelToken.Reason or "Cancelled"
				else
					cancelReason = "ActionError"
				end
			end
			KitchenService.CancelCooking(cookingSession, cancelReason)
		end
		cookingSession = nil
	end

	abortReason = stageAbortReason

	local followUpSuccess = true
	local followUpError: any = nil
	local followUpAbortReason: string? = nil
	local eatActionLabel = if isSnack then "eat snack" else "eat meal"
	local activeFollowUp = followUpBehavior

	if stageSuccess and activeFollowUp and not context.CancelToken.Cancelled then
		if not diningReservationRecord then
			ensureDiningReservation()
		end
		if diningReservationType == "MealStation" then
			applyMealStationBonus(activeFollowUp, diningReservationType, followUpRecipe)
		end
		if restPoseApplied then
			ResidentMovement.ClearRestPose(assignment.ResidentState)
			restPoseApplied = false
		end
		if arrival and behavior.UseSeat then
			ResidentMovement.LeaveSeat(assignment.ResidentState, arrival.Seat)
		end
		if diningReservationModel then
			if assignment.StationType == "FoodStorage" then
				releasePrimaryReservation()
			end
			local diningBehavior = mergeBehavior(diningReservationType or stationType, diningReservationItemSpec or {})
			local seatOccupantIndex: number? = nil
			local seatOccupantCount: number? = nil
			if diningReservationRecord then
				local residents = diningReservationRecord.Residents
				if typeof(residents) == "table" then
					seatOccupantCount = #residents
					local foundSeatIndex = table.find(residents, assignment.ResidentName)
					if foundSeatIndex then
						seatOccupantIndex = foundSeatIndex
					end
				end
			end
			if diningReservationItemSpec then
				local maxSeat = diningReservationItemSpec.maxOccupancy
				if typeof(maxSeat) == "number" and maxSeat > 0 then
					if not seatOccupantCount or seatOccupantCount < maxSeat then
						seatOccupantCount = maxSeat
					end
				end
			end
			local seatArrived, seatArrival =
				ResidentMovement.GoToStation(assignment.ResidentState, diningReservationModel, {
					CancelToken = context.CancelToken,
					ApproachDistance = diningBehavior.ApproachDistance,
					TimeoutSeconds = diningBehavior.MoveTimeoutSeconds,
					EnsureSeat = diningBehavior.UseSeat,
					OccupantIndex = seatOccupantIndex,
					OccupantCount = seatOccupantCount,
				})
			if seatArrived and seatArrival then
				ResidentMovement.FaceStation(assignment.ResidentState, seatArrival.EntryCFrame)
				if diningBehavior.UseSeat and seatArrival.Seat then
					ResidentMovement.SeatResident(assignment.ResidentState, seatArrival.Seat, context.CancelToken)
				end
				diningArrivalInfo = seatArrival
				followUpStationTypeOverride = diningReservationType
				followUpStationIdOverride = diningReservationUniqueId or assignment.StationId
				if diningReservationItemSpec then
					local display = diningReservationItemSpec.DisplayName
					if typeof(display) == "string" and display ~= "" then
						followUpStationNameOverride = display
					else
						local itemName = diningReservationItemSpec.Name
						if typeof(itemName) == "string" and itemName ~= "" then
							followUpStationNameOverride = itemName
						end
					end
				end
			else
				releaseDiningReservation()
			end
		else
			releaseDiningReservation()
		end

		if not activeFollowUp.ChatIntervalSeconds then
			local followUpLine = ResidentChat.SelectChatText(assignment.ResidentState, activeFollowUp.ChatPhrases, nil)
			if followUpLine then
				ResidentChat.ShowAction(assignment.ResidentState, followUpLine)
			end
		end
		ResidentDebug.Trace(ACTION_CHANNEL, string.format("Running meal consumption: %s", assignment.ResidentName), {
			Resident = assignment.ResidentName,
			StationType = stationType,
			Behavior = activeFollowUp,
		})
		local followUpRunOk, followUpRunResult, followUpRunReason = pcall(function()
			return NeedEffects.Run(assignment.ResidentState, context.CancelToken, activeFollowUp, {
				StationType = followUpStationTypeOverride or stationType,
				StationId = followUpStationIdOverride or assignment.StationId,
				StationName = followUpStationNameOverride or stationName,
				NeedName = assignment.NeedName,
				ActionName = eatActionLabel,
				Player = assignment.Player,
			})
		end)
		if followUpRunOk then
			if followUpRunResult ~= true then
				followUpSuccess = false
				followUpAbortReason = followUpRunReason
				if not followUpAbortReason or followUpAbortReason == "" then
					if context.CancelToken.Cancelled then
						followUpAbortReason = context.CancelToken.Reason or "Cancelled"
					else
						followUpAbortReason = "Interrupted"
					end
				end
			end
		else
			followUpSuccess = false
			followUpError = followUpRunResult
		end
	end

	if followUpAbortReason then
		abortReason = followUpAbortReason
	end

	if restPoseApplied then
		ResidentMovement.ClearRestPose(assignment.ResidentState)
	end
	if arrival and behavior.UseSeat then
		ResidentMovement.LeaveSeat(assignment.ResidentState, arrival.Seat)
	end
	if diningArrivalInfo and diningArrivalInfo.Seat then
		ResidentMovement.LeaveSeat(assignment.ResidentState, diningArrivalInfo.Seat)
	end
	releaseDiningReservation()

	if stageError then
		error(stageError)
	end
	if followUpError then
		error(followUpError)
	end
	if abortReason then
		error(NeedEffects.FormatAbortError(abortReason), 0)
	end
	if not stageSuccess then
		error("NeedEffectsFailed")
	end
	if not followUpSuccess then
		error("NeedEffectsFailed")
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

local function handleMealStation(context: HandlerContext, assignment: HandlerAssignment)
	executeStationAction("MealStation", context, assignment)
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

local function handleFoodStorage(context: HandlerContext, assignment: HandlerAssignment)
	executeStationAction("FoodStorage", context, assignment)
end

register("RestStation", handleRestStation)
register("CookStation", handleCookStation)
register("MealStation", handleMealStation)
register("SocialStation", handleSocialStation)
register("HygieneStation", handleHygieneStation)
register("FunStation", handleFunStation)
register("FoodStorage", handleFoodStorage)

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
