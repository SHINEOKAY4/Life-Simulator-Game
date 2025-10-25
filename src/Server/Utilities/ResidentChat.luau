--!strict
-- ServerScriptService/Server/Utilities/ResidentChat.luau
-- Emits simple chat bubbles for resident actions and moodlets and provides helpers for contextual phrasing.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TimeScale = require(ReplicatedStorage.Shared.Utilities.TimeScale)
local ResidentsPackets = require(ReplicatedStorage.Network.ResidentsPackets)

local ResidentChat = {}

local rng = Random.new()

local DEFAULT_DURATIONS: { [string]: number } = {
	Action = 3,
	Interrupt = 3.5,
	Moodlet = 2,
}

local function fireChatBubble(head: BasePart, text: string, kind: string, duration: number?)
	if not head then
		return
	end
	if typeof(text) ~= "string" or text == "" then
		return
	end
	local finalDuration: number
	if typeof(duration) == "number" and duration > 0 then
		finalDuration = duration
	else
		finalDuration = DEFAULT_DURATIONS[kind] or DEFAULT_DURATIONS.Action
	end
	ResidentsPackets.ResidentChatMessage:Fire({
		Speaker = head,
		Text = text,
		Kind = kind,
		Duration = finalDuration,
	})
end

export type ChatOption = {
	Text: string,
	MinClock: number?,
	MaxClock: number?,
	MinNeeds: { [string]: number }?,
	MaxNeeds: { [string]: number }?,
}

export type InterruptContext = {
	StationType: string?,
	StationName: string?,
	StationId: string?,
	ActionName: string?,
	NeedName: string?,
	PartnerName: string?,
	Player: Player?,
}

-- Moodlet emojis for visual feedback (shorter, cleaner than full text)
local MoodletEmojis: { [string]: string } = {
	WellRested = "😴✨",
	Satisfied = "😋🍽️",
	Chatty = "💬😊",
	Fresh = "🚿✨",
	Entertained = "🎉😄",
}

local StationFriendlyNames: { [string]: string } = {
	RestStation = "my bed",
	CookStation = "the kitchen",
	SocialStation = "the hangout",
	HygieneStation = "the sink",
	FunStation = "the fun spot",
	GroundRest = "this spot",
}

local NeedFriendlyNames: { [string]: { string } } = {
	Hunger = {
		"I could really use a bite to eat",
		"I'm getting pretty hungry",
		"My stomach's rumbling",
		"I need some food",
	},
	Hygiene = {
		"I should take a moment to freshen up",
		"I could use a quick wash",
		"Time to clean up a bit",
		"I need to freshen up",
	},
	Fun = {
		"I could use a little fun first",
		"I need some entertainment",
		"I'm getting bored here",
		"I need a break to have some fun",
	},
	Energy = {
		"I'm running low on energy",
		"I'm feeling exhausted",
		"I really need some rest",
		"I can barely keep my eyes open",
	},
	Social = {
		"I could use some company",
		"I'm feeling lonely",
		"I need someone to talk to",
		"I miss chatting with people",
	},
}

local GenericInterrupts: { string } = {
	"Something popped up; I'll be back soon.",
	"I need to pause for just a moment.",
	"Had to step away for a bit.",
	"I'll handle this real quick.",
	"Give me a second.",
	"Something came up.",
}

local NeedFullPhrases: { [string]: { string } } = {
	Hunger = {
		"I'm already full.",
		"I've eaten enough.",
		"My stomach is satisfied.",
		"I'm not hungry right now.",
	},
	Energy = {
		"I'm wide awake already.",
		"I'm fully rested.",
		"I don't need sleep right now.",
		"I'm energized!",
	},
	Hygiene = {
		"I'm already squeaky clean.",
		"I just freshened up.",
		"I'm clean enough.",
		"I don't need to wash up yet.",
	},
	Fun = {
		"I'm all set for fun right now.",
		"I've had enough entertainment.",
		"I'm not bored yet.",
		"I'm feeling entertained already.",
	},
	Social = {
		"I'm feeling social enough already.",
		"I've had enough conversation for now.",
		"I'm all talked out.",
		"I need some alone time.",
	},
}

local StationArticles: { [string]: boolean } = {
	the = true,
	a = true,
	an = true,
	my = true,
	our = true,
	your = true,
	their = true,
	this = true,
	that = true,
	these = true,
	those = true,
	some = true,
	another = true,
	any = true,
}

local function formatStationForSentence(rawLabel: string?): string?
	if rawLabel == nil then
		return nil
	end
	local trimmed = rawLabel:gsub("^%s+", ""):gsub("%s+$", "")
	if trimmed == "" then
		return nil
	end
	local lower = trimmed:lower()
	local firstWord = lower:match("^(%w+)")
	if firstWord and StationArticles[firstWord] then
		return trimmed
	end
	if trimmed:find("%s") then
		return "the " .. trimmed
	end
	if trimmed == lower then
		return "the " .. trimmed
	end
	if trimmed:match("^%u%l*$") then
		return "the " .. lower
	end
	return "the " .. trimmed
end

local function selectRandom(entries: { string }): string
	return entries[rng:NextInteger(1, #entries)]
end

local function getTimeOfDayGreeting(): string?
	local clockTime = TimeScale.GetClockTime()
	if clockTime >= 5 and clockTime < 12 then
		return selectRandom({ "Good morning!", "Morning!", "Rise and shine!" })
	elseif clockTime >= 12 and clockTime < 17 then
		return selectRandom({ "Good afternoon!", "Afternoon!", "Hey there!" })
	elseif clockTime >= 17 and clockTime < 21 then
		return selectRandom({ "Good evening!", "Evening!", "Hey!" })
	elseif clockTime >= 21 or clockTime < 5 then
		return selectRandom({ "It's getting late...", "Long day...", "Still up..." })
	end
	return nil
end

local function humanizeReason(raw: string): string
	local spaced = raw:gsub("(%l)(%u)", "%1 %2")
	spaced = spaced:gsub("(%u)(%u%l)", "%1 %2")
	spaced = spaced:gsub("[_%-]", " ")
	return spaced:lower()
end

local function resolveStationLabel(context: InterruptContext?): string?
	if not context then
		return nil
	end
	local explicitName = context.StationName
	if typeof(explicitName) == "string" and explicitName ~= "" then
		return explicitName
	end
	local stationType = context.StationType
	if stationType then
		local friendly = StationFriendlyNames[stationType]
		if friendly then
			return friendly
		end
	end
	local actionName = context.ActionName
	if typeof(actionName) == "string" and actionName ~= "" then
		return actionName
	end
	return nil
end

local function resolvePartnerName(context: InterruptContext?): string?
	if not context then
		return nil
	end
	local partner = context.PartnerName
	if typeof(partner) == "string" and partner ~= "" then
		return partner
	end
	return nil
end

local function resolveNeedName(context: InterruptContext?): string?
	if not context then
		return nil
	end
	local needName = context.NeedName
	if typeof(needName) == "string" and needName ~= "" then
		return needName
	end
	return nil
end

local function buildUrgentNeedText(reasonNeed: string, context: InterruptContext?): string
	local phrases = NeedFriendlyNames[reasonNeed]
	local base = if phrases then selectRandom(phrases) else nil
	local stationLabel = resolveStationLabel(context)
	local stationPhrase = if stationLabel then formatStationForSentence(stationLabel) or stationLabel else nil

	-- Don't repeat "I need X" if the station is already for that need
	local actionName = if context then context.ActionName else nil
	local contextNeed = if context then context.NeedName else nil
	local isDuplicateContext = (actionName and actionName:lower():find(reasonNeed:lower()))
		or (contextNeed and contextNeed:lower() == reasonNeed:lower())
		or (stationLabel and stationLabel:lower():find(reasonNeed:lower()))

	if base and stationPhrase and not isDuplicateContext then
		return string.format("%s, so I'm stepping away from %s.", base, stationPhrase)
	elseif base then
		return base .. "."
	elseif stationPhrase then
		return string.format("Stepping away from %s to handle something important.", stationPhrase)
	end
	local friendlyNeed = humanizeReason(reasonNeed)
	return string.format("I need to handle %s right away.", friendlyNeed)
end

local InterruptHandlers: { [string]: (InterruptContext?) -> string? } = {
	ManualOverride = function(context)
		local stationLabel = resolveStationLabel(context)
		local stationPhrase = if stationLabel then formatStationForSentence(stationLabel) or stationLabel else nil
		local variations = if stationPhrase
			then {
				string.format("I'll step away from %s for now.", stationPhrase),
				string.format("Pausing at %s for a moment.", stationPhrase),
				string.format("I need to stop using %s.", stationPhrase),
			}
			else {
				"I'll take a short break for now.",
				"Pausing for a moment.",
				"I need to step away.",
			}
		return selectRandom(variations)
	end,
	DirectSocialPartnerFailed = function(context)
		local partner = resolvePartnerName(context)
		if partner then
			local variations = {
				string.format("I think %s had to step away mid-chat.", partner),
				string.format("Looks like %s couldn't continue.", partner),
				string.format("%s had to leave suddenly.", partner),
			}
			return selectRandom(variations)
		end
		return selectRandom({
			"Looks like my chat partner had to leave.",
			"They had to step away.",
			"Our conversation got cut short.",
		})
	end,
	DirectSocialCancelled = function(context)
		local partner = resolvePartnerName(context)
		if partner then
			local variations = {
				string.format("Our chat with %s paused for now.", partner),
				string.format("I'll catch up with %s later.", partner),
				string.format("I need to postpone talking with %s.", partner),
			}
			return selectRandom(variations)
		end
		return selectRandom({
			"That conversation is on hold for the moment.",
			"I'll continue that chat later.",
			"We'll pick this up another time.",
		})
	end,
	StationRemoved = function(context)
		local stationLabel = resolveStationLabel(context)
		local stationPhrase = if stationLabel then formatStationForSentence(stationLabel) or stationLabel else nil
		if stationPhrase then
			local variations = {
				string.format("Looks like %s is gone for now.", stationPhrase),
				string.format("I can't use %s anymore.", stationPhrase),
				string.format("%s disappeared!", stationPhrase),
			}
			return selectRandom(variations)
		end
		return selectRandom({
			"What I was using is gone for now.",
			"That just disappeared on me!",
			"I can't use that anymore.",
		})
	end,
	MovementFailed = function(context)
		local stationLabel = resolveStationLabel(context)
		local stationPhrase = if stationLabel then formatStationForSentence(stationLabel) or stationLabel else nil
		if stationPhrase then
			local variations = {
				string.format("I can't quite reach %s right now.", stationPhrase),
				string.format("I'm having trouble getting to %s.", stationPhrase),
				string.format("I can't get to %s from here.", stationPhrase),
			}
			return selectRandom(variations)
		end
		return selectRandom({
			"I can't get there just yet.",
			"I'm having trouble reaching that spot.",
			"The path is blocked.",
		})
	end,
	Cancelled = function(_context)
		return selectRandom({
			"That was cancelled for now.",
			"Plans changed.",
			"Never mind that.",
		})
	end,
	EnergySatisfied = function(context)
		local stationLabel = resolveStationLabel(context)
		local stationPhrase = if stationLabel then formatStationForSentence(stationLabel) or stationLabel else nil
		if stationPhrase then
			local variations = {
				string.format("Feeling rested—wrapping up at %s.", stationPhrase),
				string.format("I'm energized now! Done with %s.", stationPhrase),
				string.format("All recharged! Leaving %s.", stationPhrase),
			}
			return selectRandom(variations)
		end
		return selectRandom({
			"Feeling rested and ready.",
			"I'm fully energized now!",
			"All recharged!",
		})
	end,
}

function ResidentChat.ResolveInterruptText(reason: string?, context: InterruptContext?): string?
	if reason == nil or reason == "" then
		local stationLabel = resolveStationLabel(context)
		if stationLabel then
			local stationPhrase = formatStationForSentence(stationLabel) or stationLabel
			return string.format("Had to pause at %s for now.", stationPhrase)
		end
		return selectRandom(GenericInterrupts)
	end
	local handler = InterruptHandlers[reason]
	if handler then
		local result = handler(context)
		if result and result ~= "" then
			return result
		end
	end
	local urgentNeed = string.match(reason, "^NeedUrgent:(.+)$")
	if urgentNeed then
		local parsedNeed = urgentNeed
		local contextNeed = resolveNeedName(context)
		if not parsedNeed and contextNeed then
			parsedNeed = contextNeed
		end
		if parsedNeed then
			return buildUrgentNeedText(parsedNeed, context)
		end
	end
	local satiatedNeed = string.match(reason, "^NeedFull:(.+)$")
	if satiatedNeed then
		local phrases = NeedFullPhrases[satiatedNeed]
		if phrases then
			return selectRandom(phrases)
		end
		local friendlyNeed = humanizeReason(satiatedNeed)
		return string.format("I'm already topped up on %s.", friendlyNeed)
	end
	local stationLabel = resolveStationLabel(context)
	local friendlyReason = humanizeReason(reason)
	if stationLabel then
		local stationPhrase = formatStationForSentence(stationLabel) or stationLabel
		return string.format("Paused at %s because %s.", stationPhrase, friendlyReason)
	end
	return string.format("Paused because %s.", friendlyReason)
end

local function resolveHead(residentState): BasePart?
	if not residentState then
		return nil
	end
	local model = residentState.Model
	if model and model:IsA("Model") then
		local head = model:FindFirstChild("Head")
		if head and head:IsA("BasePart") then
			return head
		end
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

local function clockInRange(clockTime: number, minClock: number?, maxClock: number?): boolean
	if minClock == nil and maxClock == nil then
		return true
	end
	local normalizedMin = if minClock ~= nil then normalizeClock(minClock) else nil
	local normalizedMax = if maxClock ~= nil then normalizeClock(maxClock) else nil
	if normalizedMin ~= nil and normalizedMax ~= nil then
		if normalizedMin == normalizedMax then
			return true
		end
		if normalizedMin < normalizedMax then
			return clockTime >= normalizedMin and clockTime < normalizedMax
		else
			return clockTime >= normalizedMin or clockTime < normalizedMax
		end
	elseif normalizedMin ~= nil then
		return clockTime >= normalizedMin
	elseif normalizedMax ~= nil then
		return clockTime < normalizedMax
	end
	return true
end

local function getNeedValue(residentState, needName: string): number?
	if not residentState then
		return nil
	end
	local getter = residentState.GetNeed
	if typeof(getter) ~= "function" then
		return nil
	end
	local value = getter(residentState, needName)
	if typeof(value) ~= "number" then
		return nil
	end
	return value
end

local function needsMeetBounds(residentState, minNeeds: { [string]: number }?, maxNeeds: { [string]: number }?): boolean
	if minNeeds then
		for needName, threshold in pairs(minNeeds) do
			local value = getNeedValue(residentState, needName)
			if value == nil or value < threshold then
				return false
			end
		end
	end
	if maxNeeds then
		for needName, threshold in pairs(maxNeeds) do
			local value = getNeedValue(residentState, needName)
			if value == nil or value > threshold then
				return false
			end
		end
	end
	return true
end

function ResidentChat.ResolveChatTexts(residentState, options: { ChatOption }?): { string }
	if not options or #options == 0 then
		return {}
	end
	local clockTime = TimeScale.GetClockTime()
	local valid: { string } = {}
	local fallback: { string } = {}
	for _, option in ipairs(options) do
		local text = option.Text
		if typeof(text) == "string" and text ~= "" then
			local hasTimeConditions = option.MinClock ~= nil or option.MaxClock ~= nil
			local hasNeedConditions = option.MinNeeds ~= nil or option.MaxNeeds ~= nil
			local hasAnyConditions = hasTimeConditions or hasNeedConditions

			local meetsTime = clockInRange(clockTime, option.MinClock, option.MaxClock)
			local meetsNeeds = needsMeetBounds(residentState, option.MinNeeds, option.MaxNeeds)

			if meetsTime and meetsNeeds then
				valid[#valid + 1] = text
			elseif not hasAnyConditions then
				fallback[#fallback + 1] = text
			end
		end
	end
	if #valid > 0 then
		return valid
	end
	return fallback
end

function ResidentChat.SelectChatText(residentState, options: { ChatOption }?, lastText: string?): string?
	local choices = ResidentChat.ResolveChatTexts(residentState, options)
	if #choices == 0 then
		return nil
	end
	local filtered: { string } = {}
	if lastText then
		for _, text in ipairs(choices) do
			if text ~= lastText then
				filtered[#filtered + 1] = text
			end
		end
	end
	local pool = if #filtered > 0 then filtered else choices
	return pool[rng:NextInteger(1, #pool)]
end

function ResidentChat.GetTimeOfDayGreeting(): string?
	return getTimeOfDayGreeting()
end

function ResidentChat.ShowAction(residentState, phrases: { string } | { ChatOption } | string?)
	if phrases == nil then
		return
	end
	local text: string?
	if typeof(phrases) == "string" then
		text = phrases
	elseif typeof(phrases) == "table" then
		if #phrases == 0 then
			return
		end
		local first = phrases[1]
		if typeof(first) == "table" then
			text = ResidentChat.SelectChatText(residentState, phrases :: { ChatOption }, nil)
		else
			local strings: { string } = {}
			for _, entry in ipairs(phrases) do
				if typeof(entry) == "string" and entry ~= "" then
					strings[#strings + 1] = entry
				end
			end
			if #strings == 0 then
				return
			end
			text = strings[rng:NextInteger(1, #strings)]
		end
	end
	if not text or text == "" then
		return
	end
	local head = resolveHead(residentState)
	if not head then
		return
	end
	fireChatBubble(head, text, "Action", DEFAULT_DURATIONS.Action)
end

function ResidentChat.ShowInterrupt(residentState, reason: string?, context: InterruptContext?)
	local text = ResidentChat.ResolveInterruptText(reason, context)
	if not text or text == "" then
		return
	end
	local head = resolveHead(residentState)
	if not head then
		return
	end
	fireChatBubble(head, text, "Interrupt", DEFAULT_DURATIONS.Interrupt)
end

function ResidentChat.ShowMoodlet(residentState, moodletName: string)
	local head = resolveHead(residentState)
	if not head then
		return
	end
	-- Use emoji instead of full text for cleaner, less cluttered feedback
	local emoji = MoodletEmojis[moodletName]
	if not emoji or emoji == "" then
		return
	end
	fireChatBubble(head, emoji, "Moodlet", DEFAULT_DURATIONS.Moodlet)
end

return ResidentChat
