--!strict
-- NeedEffects.lua
-- Applies catalog-defined need adjustments while residents interact with stations.

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NeedConfig = require(ReplicatedStorage.Shared.Configurations.NeedConfig)
local TimeScale = require(ReplicatedStorage.Shared.Utilities.TimeScale)
local ServerScriptService = game:GetService("ServerScriptService")
local ResidentDebug = require(ServerScriptService.Server.Utilities.ResidentDebug)
local ResidentChat = require(ServerScriptService.Server.Utilities.ResidentChat)

type CancelToken = { Cancelled: boolean, Reason: string? }

type EffectDef = {
	Need: string,
	InstantAmount: number?,
	RatePerHour: number?,
}

type Behavior = {
	Effects: { EffectDef }?,
	DurationSeconds: number?,
	ShouldEnd: ((residentState: any) -> boolean)?,
	Moodlets: { { Name: string, DurationSeconds: number, NeedBias: { [string]: number }? } }?,
	ChatIntervalSeconds: number?,
	ChatPhrases: { ResidentChat.ChatOption }?,
	EndReasonProvider: ((residentState: any) -> string?)?,
}

local NeedEffects = {}
local EFFECT_CHANNEL = "Effects"

local function clampNeed(needName: string, value: number): number
	local def = NeedConfig.Needs[needName]
	if not def then
		return value
	end
	return math.clamp(value, def.Min, def.Max)
end

local function applyDelta(residentState: any, needName: string, delta: number)
	local current = residentState:GetNeed(needName)
	residentState:SetNeed(needName, clampNeed(needName, current + delta))
end

local function applyInstantEffects(residentState: any, effects: { EffectDef }, applied: { [number]: boolean })
	for index, effect in ipairs(effects) do
		if effect.InstantAmount and not applied[index] then
			applyDelta(residentState, effect.Need, effect.InstantAmount)
			applied[index] = true
		end
	end
end

local function applyMoodlets(
	residentState: any,
	moodlets: { { Name: string, DurationSeconds: number, NeedBias: { [string]: number }? } }?
)
	if not moodlets or not residentState or type(residentState.AddMoodlet) ~= "function" then
		return
	end
	for _, moodlet in ipairs(moodlets) do
		local added = residentState:AddMoodlet(moodlet)
		if added then
			ResidentChat.ShowMoodlet(residentState, moodlet.Name)
		end
	end
end

function NeedEffects.Run(
	residentState: any,
	token: CancelToken?,
	behavior: Behavior,
	interruptContext: ResidentChat.InterruptContext?
): boolean
	local effects = behavior.Effects
	if not effects or #effects == 0 then
		applyMoodlets(residentState, behavior.Moodlets)
		return true
	end
	local duration = behavior.DurationSeconds or 10
	local shouldEnd = behavior.ShouldEnd
	local appliedInstant: { [number]: boolean } = {}
	local residentName = if residentState and residentState.Save then residentState.Save.Name else "UnknownResident"
	local chatInterval = behavior.ChatIntervalSeconds
	if chatInterval and chatInterval <= 0 then
		chatInterval = nil
	end
	local chatPhrases = behavior.ChatPhrases
	ResidentDebug.Trace(EFFECT_CHANNEL, string.format("NeedEffects start: %s", residentName), {
		Resident = residentName,
		Duration = duration,
		Effects = effects,
	})
	applyInstantEffects(residentState, effects, appliedInstant)
	local elapsed = 0
	local lastTick = os.clock()
	local nextChatTime: number? = nil
	local lastChatText: string? = nil
	local function emitChat()
		if not chatPhrases then
			return
		end
		local selected = ResidentChat.SelectChatText(residentState, chatPhrases, lastChatText)
		if selected then
			ResidentChat.ShowAction(residentState, selected)
			lastChatText = selected
		end
	end
	if chatInterval and chatPhrases and #chatPhrases > 0 then
		emitChat()
		nextChatTime = os.clock() + chatInterval
	end
	while elapsed < duration do
		if token and token.Cancelled then
			local cancelReason = if token.Reason and token.Reason ~= "" then token.Reason else "Cancelled"
			ResidentChat.ShowInterrupt(residentState, cancelReason, interruptContext)
			applyMoodlets(residentState, behavior.Moodlets)
			ResidentDebug.Trace(EFFECT_CHANNEL, string.format("NeedEffects cancelled: %s", residentName))
			return false
		end
		if shouldEnd and shouldEnd(residentState) then
			local reasonResolver = behavior.EndReasonProvider
			if reasonResolver then
				local reason = reasonResolver(residentState)
				if reason and reason ~= "" then
					ResidentChat.ShowInterrupt(residentState, reason, interruptContext)
				end
			end
			applyMoodlets(residentState, behavior.Moodlets)
			ResidentDebug.Trace(EFFECT_CHANNEL, string.format("NeedEffects early exit: %s", residentName), {
				Elapsed = elapsed,
			})
			return true
		end
		RunService.Heartbeat:Wait()
		local now = os.clock()
		local realDelta = now - lastTick
		lastTick = now
		elapsed += realDelta
		local gameHours = TimeScale.GameHoursFromRealDelta(realDelta)
		if gameHours > 0 then
			for _, effect in ipairs(effects) do
				if effect.RatePerHour and effect.RatePerHour ~= 0 then
					local delta = effect.RatePerHour * gameHours
					applyDelta(residentState, effect.Need, delta)
				end
			end
		end
		if nextChatTime and chatInterval and now >= nextChatTime then
			emitChat()
			nextChatTime = now + chatInterval
		end
	end
	ResidentDebug.Trace(EFFECT_CHANNEL, string.format("NeedEffects completed: %s", residentName), {
		Elapsed = elapsed,
	})
	applyMoodlets(residentState, behavior.Moodlets)
	return true
end

return NeedEffects
