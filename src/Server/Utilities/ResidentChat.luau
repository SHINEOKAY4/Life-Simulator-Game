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

local MoodletPhrases: { [string]: string } = {
	WellRested = "That nap felt amazing!",
	Satisfied = "Yum, that hit the spot!",
	Chatty = "Let's keep talking!",
	Fresh = "Squeaky clean!",
	Entertained = "That was so much fun!",
}

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
