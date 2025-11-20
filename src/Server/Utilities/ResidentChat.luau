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
	if typeof(text) ~= "string" then
		return
	end
	-- Allow empty text if we are clearing (duration 0)
	if text == "" and (duration ~= 0) then
		return
	end

	local finalDuration: number
	if typeof(duration) == "number" then
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

local NeedFriendlyNames: { [string]: { string } } = {
	Hunger = { "🍔", "🍕", "🥗", "😋" },
	Hygiene = { "🚿", "🧼", "🛁", "✨" },
	Fun = { "🎮", "🎲", "🎯", "🤩" },
	Energy = { "😴", "💤", "🛌", "🔋" },
	Social = { "💬", "🗣️", "👋", "😄" },
}

local GenericInterrupts: { string } = {
	"✋",
	"⏳",
	"⏸️",
	"🛑",
}

local NeedFullPhrases: { [string]: { string } } = {
	Hunger = { "😋", "🤰" },
	Energy = { "⚡", "🔋" },
	Hygiene = { "✨", "🧼" },
	Fun = { "🤩", "🎉" },
	Social = { "🤐", "🤫" },
}

local function selectRandom(entries: { string }): string
	return entries[rng:NextInteger(1, #entries)]
end

local function getTimeOfDayGreeting(): string?
	local clockTime = TimeScale.GetClockTime()
	if clockTime >= 5 and clockTime < 12 then
		return selectRandom({ "🌅", "☀️", "🍳" })
	elseif clockTime >= 12 and clockTime < 17 then
		return selectRandom({ "☀️", "🕶️", "🍦" })
	elseif clockTime >= 17 and clockTime < 21 then
		return selectRandom({ "🌇", "🌙", "🕯️" })
	elseif clockTime >= 21 or clockTime < 5 then
		return selectRandom({ "😴", "🦉", "🌌" })
	end
	return nil
end

local InterruptHandlers: { [string]: (InterruptContext?) -> string? } = {
	ManualOverride = function(_context)
		return selectRandom({ "🛑", "✋" })
	end,
	DirectSocialPartnerFailed = function(_context)
		return selectRandom({ "💔", "🏃" })
	end,
	DirectSocialCancelled = function(_context)
		return selectRandom({ "🛑", "💬" })
	end,
	StationRemoved = function(_context)
		return selectRandom({ "❓", "🏚️" })
	end,
	MovementFailed = function(_context)
		return selectRandom({ "🚧", "🚫" })
	end,
	Cancelled = function(_context)
		return selectRandom({ "❌", "🛑" })
	end,
	EnergySatisfied = function(_context)
		return selectRandom({ "⚡", "🔋" })
	end,
}

function ResidentChat.ResolveInterruptText(reason: string?, context: InterruptContext?): string?
	if reason == nil or reason == "" then
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
		local phrases = NeedFriendlyNames[urgentNeed]
		if phrases then
			return selectRandom(phrases)
		end
	end
	local satiatedNeed = string.match(reason, "^NeedFull:(.+)$")
	if satiatedNeed then
		local phrases = NeedFullPhrases[satiatedNeed]
		if phrases then
			return selectRandom(phrases)
		end
	end
	return selectRandom(GenericInterrupts)
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

function ResidentChat.ShowPersistentAction(residentState, text: string)
	if not text or text == "" then
		return
	end
	local head = resolveHead(residentState)
	if not head then
		return
	end
	fireChatBubble(head, text, "Action", -1)
end

function ResidentChat.ClearPersistentAction(residentState)
	local head = resolveHead(residentState)
	if not head then
		return
	end
	fireChatBubble(head, "", "Action", 0)
end

return ResidentChat
