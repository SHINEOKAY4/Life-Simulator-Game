--!strict
-- ServerScriptService/Server/Utilities/ResidentChat.luau
-- Emits simple chat bubbles for resident actions and moodlets and provides helpers for contextual phrasing.

local ChatService = game:GetService("Chat")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TimeScale = require(ReplicatedStorage.Shared.Utilities.TimeScale)

local ResidentChat = {}

local rng = Random.new()

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

local MoodletPhrases: { [string]: string } = {
	WellRested = "That nap felt amazing!",
	Satisfied = "Yum, that hit the spot!",
	Chatty = "Let's keep talking!",
	Fresh = "Squeaky clean!",
	Entertained = "That was so much fun!",
}

local StationFriendlyNames: { [string]: string } = {
	RestStation = "my bed",
	CookStation = "the kitchen",
	SocialStation = "the hangout",
	HygieneStation = "the sink",
	FunStation = "the fun spot",
	GroundRest = "this spot",
}

local NeedFriendlyNames: { [string]: string } = {
	Hunger = "I'm starving",
	Hygiene = "I really need to clean up",
	Fun = "I need something fun first",
	Energy = "I'm running on empty",
	Social = "I need to talk to someone",
}

local GenericInterrupts: { string } = {
	"I got pulled away unexpectedly...",
	"Something came up, so I had to stop.",
	"Can't keep going right now.",
}

local function selectRandom(entries: { string }): string
	return entries[rng:NextInteger(1, #entries)]
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
	local base = NeedFriendlyNames[reasonNeed]
	local stationLabel = resolveStationLabel(context)
	if base and stationLabel then
		return string.format("%s—leaving %s.", base, stationLabel)
	elseif base then
		return base .. "."
	elseif stationLabel then
		return string.format("Leaving %s to deal with something urgent.", stationLabel)
	end
	local friendlyNeed = humanizeReason(reasonNeed)
	return string.format("Need to handle %s right away.", friendlyNeed)
end

local InterruptHandlers: { [string]: (InterruptContext?) -> string? } = {
	ManualOverride = function(context)
		local stationLabel = resolveStationLabel(context)
		if stationLabel then
			return string.format("I'll pause at %s so you can take over.", stationLabel)
		end
		return "Okay, handing things back to you."
	end,
	DirectSocialPartnerFailed = function(context)
		local partner = resolvePartnerName(context)
		if partner then
			return string.format("%s bailed on me mid-chat...", partner)
		end
		return "My chat partner walked off on me."
	end,
	DirectSocialCancelled = function(context)
		local partner = resolvePartnerName(context)
		if partner then
			return string.format("Our chat with %s got cut short.", partner)
		end
		return "That conversation just got cancelled."
	end,
	StationRemoved = function(context)
		local stationLabel = resolveStationLabel(context)
		if stationLabel then
			return string.format("My %s vanished!", stationLabel)
		end
		return "The thing I was using disappeared!"
	end,
	MovementFailed = function(context)
		local stationLabel = resolveStationLabel(context)
		if stationLabel then
			return string.format("I can't reach %s.", stationLabel)
		end
		return "Couldn't get there."
	end,
	Cancelled = function(_context)
		return "That got cancelled."
	end,
	EnergySatisfied = function(context)
		local stationLabel = resolveStationLabel(context)
		if stationLabel then
			return string.format("Feeling rested—done at %s.", stationLabel)
		end
		return "Feeling rested and ready."
	end,
}

local InterruptColorMap: { [string]: Enum.ChatColor } = {
	ManualOverride = Enum.ChatColor.Blue,
	DirectSocialPartnerFailed = Enum.ChatColor.Blue,
	DirectSocialCancelled = Enum.ChatColor.Blue,
	EnergySatisfied = Enum.ChatColor.Blue,
}

local function resolveInterruptColor(reason: string?): Enum.ChatColor
	if not reason or reason == "" then
		return Enum.ChatColor.Red
	end
	local normalized = reason
	local urgentNeed = string.match(reason, "^NeedUrgent:(.+)$")
	if urgentNeed then
		return Enum.ChatColor.Red
	end
	local mapped = InterruptColorMap[normalized]
	if mapped then
		return mapped
	end
	return Enum.ChatColor.Red
end

function ResidentChat.ResolveInterruptText(reason: string?, context: InterruptContext?): string?
	if reason == nil or reason == "" then
		local stationLabel = resolveStationLabel(context)
		if stationLabel then
			return string.format("Had to stop at %s.", stationLabel)
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
	local stationLabel = resolveStationLabel(context)
	local friendlyReason = humanizeReason(reason)
	if stationLabel then
		return string.format("Stopped at %s because %s.", stationLabel, friendlyReason)
	end
	return string.format("Stopped because %s.", friendlyReason)
end

function ResidentChat.ResolveInterruptColor(reason: string?): Enum.ChatColor
	return resolveInterruptColor(reason)
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
	local success, value = pcall(function()
		return getter(residentState, needName)
	end)
	if not success or typeof(value) ~= "number" then
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
			local hasConditions = option.MinClock ~= nil or option.MaxClock ~= nil
			local meetsTime = clockInRange(clockTime, option.MinClock, option.MaxClock)
			local meetsNeeds = needsMeetBounds(residentState, option.MinNeeds, option.MaxNeeds)
			if meetsTime and meetsNeeds then
				valid[#valid + 1] = text
			elseif not hasConditions and option.MinNeeds == nil and option.MaxNeeds == nil then
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
	ChatService:Chat(head, text, Enum.ChatColor.White)
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
	local color = ResidentChat.ResolveInterruptColor(reason)
	ChatService:Chat(head, text, color)
end

function ResidentChat.ShowMoodlet(residentState, moodletName: string)
	local head = resolveHead(residentState)
	if not head then
		return
	end
	local text = MoodletPhrases[moodletName]
	if not text then
		return
	end
	ChatService:Chat(head, text, Enum.ChatColor.Green)
end

return ResidentChat
