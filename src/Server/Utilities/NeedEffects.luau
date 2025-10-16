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
local PlotService = require(ServerScriptService.Server.Services.PlotService)

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
local SURVIVAL_NEEDS: { [string]: boolean } = {
	Energy = true,
	Hunger = true,
}

local NEED_TO_STATION: { [string]: string } = {
	Hunger = "CookStation",
	Energy = "RestStation",
	Hygiene = "HygieneStation",
	Social = "SocialStation",
	Fun = "FunStation",
}

local function isSurvivalNeed(needName: string?): boolean
	if not needName then
		return false
	end
	return SURVIVAL_NEEDS[needName] == true
end

local function cloneContext(context: ResidentChat.InterruptContext?): ResidentChat.InterruptContext?
	if context == nil then
		return nil
	end
	local clone: ResidentChat.InterruptContext = {}
	for key, value in pairs(context) do
		(clone :: any)[key] = value
	end
	return clone
end

local function clampNeed(needName: string, value: number): number
	local def = NeedConfig.Needs[needName]
	if not def then
		return value
	end
	return math.clamp(value, def.Min, def.Max)
end

local function sanitizeNeed(residentState: any, needName: string): number
	local def = NeedConfig.Needs[needName]
	local minValue = if def then def.Min else -math.huge
	local maxValue = if def then def.Max else math.huge
	local current = residentState:GetNeed(needName)
	if typeof(current) ~= "number" or current ~= current or current == math.huge or current == -math.huge then
		local fallback = if def then def.Min else 0
		residentState:SetNeed(needName, fallback)
		return fallback
	end
	local clamped = math.clamp(current, minValue, maxValue)
	if clamped ~= current then
		residentState:SetNeed(needName, clamped)
	end
	return clamped
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

local function gatherEffectContext(effects: { EffectDef }): ({ [string]: boolean }, { [string]: boolean })
	local targeted: { [string]: boolean } = {}
	local positive: { [string]: boolean } = {}
	for _, effect in ipairs(effects) do
		local needName = effect.Need
		if type(needName) == "string" and needName ~= "" then
			targeted[needName] = true
			local instant = effect.InstantAmount
			if typeof(instant) == "number" and instant > 0 then
				positive[needName] = true
			end
			local rate = effect.RatePerHour
			if typeof(rate) == "number" and rate > 0 then
				positive[needName] = true
			end
		end
	end
	return targeted, positive
end

local function evaluateEmergencyNeeds(
	residentState: any,
	_targetedNeeds: { [string]: boolean },
	positiveTargets: { [string]: boolean },
	contextPlayer: Player?
): (boolean, string?, string?)
	local needsDef = NeedConfig.Needs
	local worstNeed: string? = nil
	local worstDeficit = -math.huge
	local zeroCount = 0
	local targetsHunger = positiveTargets.Hunger == true
	local stationCacheLoaded = false
	local stationCache: { [string]: { [string]: any } }? = nil

	local function hasStationsForNeed(needName: string): boolean
		if contextPlayer == nil then
			return true
		end
		if not stationCacheLoaded then
			stationCacheLoaded = true
			local ok, result = pcall(function()
				return PlotService.GetStationsForPlayer(contextPlayer)
			end)
			if ok and result ~= nil then
				stationCache = result
			else
				stationCache = {}
			end
		end
		local cache = stationCache
		if cache == nil then
			return false
		end
		local stationType = NEED_TO_STATION[needName]
		if not stationType then
			return true
		end
		local scope = cache[stationType]
		return scope ~= nil and next(scope) ~= nil
	end

	for needName, def in pairs(needsDef) do
		local value = sanitizeNeed(residentState, needName)
		local isPositiveTarget = positiveTargets[needName] == true
		local consider = false
		if needName == "Hunger" then
			if not isPositiveTarget and value <= def.Critical then
				consider = true
			end
		elseif needName == "Energy" then
			if not isPositiveTarget and value <= def.Critical then
				if not targetsHunger then
					consider = true
				end
			end
		elseif not isPositiveTarget and value <= def.Critical then
			if isSurvivalNeed(needName) then
				consider = true
			else
				if hasStationsForNeed(needName) then
					consider = true
				end
			end
		end
		if consider then
			if value <= def.Min then
				zeroCount += 1
			end
			local deficit = def.Critical - value
			if deficit > worstDeficit then
				worstDeficit = deficit
				worstNeed = needName
			end
		end
	end
	if worstNeed ~= nil then
		return true, "NeedUrgent:" .. worstNeed, worstNeed
	end
	if zeroCount >= 2 then
		return true, "NeedUrgent:MultipleNeeds", worstNeed
	end
	return false, nil, nil
end

function NeedEffects.Run(
	residentState: any,
	token: CancelToken?,
	behavior: Behavior,
	interruptContext: ResidentChat.InterruptContext?
): boolean
	local effects = behavior.Effects
	local duration = behavior.DurationSeconds or 10
	local shouldEnd = behavior.ShouldEnd
	local appliedInstant: { [number]: boolean } = {}
	local residentName = if residentState and residentState.Save then residentState.Save.Name else "UnknownResident"
	local chatInterval = behavior.ChatIntervalSeconds
	if chatInterval and chatInterval <= 0 then
		chatInterval = nil
	end
	local chatPhrases = behavior.ChatPhrases
	local targetedNeeds: { [string]: boolean }
	local positiveNeeds: { [string]: boolean }
	local contextPlayer = if interruptContext then interruptContext.Player else nil
	if effects then
		targetedNeeds, positiveNeeds = gatherEffectContext(effects)
	else
		targetedNeeds = {}
		positiveNeeds = {}
	end
	local pauseApplied = false
	local function applyPause()
		if pauseApplied then
			return
		end
		if residentState and typeof(residentState.PushNeedDecayPause) == "function" then
			residentState:PushNeedDecayPause()
			pauseApplied = true
			return
		end
		if residentState and typeof(residentState.SetNeedDecayPaused) == "function" then
			residentState:SetNeedDecayPaused(true)
			pauseApplied = true
		end
	end
	local function releasePause()
		if not pauseApplied then
			return
		end
		if residentState and typeof(residentState.PopNeedDecayPause) == "function" then
			residentState:PopNeedDecayPause()
		elseif residentState and typeof(residentState.SetNeedDecayPaused) == "function" then
			residentState:SetNeedDecayPaused(false)
		end
		pauseApplied = false
	end
	local function finalize(success: boolean)
		if success then
			applyMoodlets(residentState, behavior.Moodlets)
		end
		releasePause()
	end
	local function failReturn(): boolean
		releasePause()
		return false
	end
	local function emitEmergency(reason: string, needName: string?)
		local context = cloneContext(interruptContext)
		if context then
			context.NeedName = needName or context.NeedName
		end
		ResidentChat.ShowInterrupt(residentState, reason, context)
		ResidentDebug.Trace(EFFECT_CHANNEL, string.format("NeedEffects emergency stop: %s", residentName), {
			Reason = reason,
			Need = needName,
		})
	end
	local function abortIfEmergency(): boolean
		local emergency, emergencyReason, emergencyNeed =
			evaluateEmergencyNeeds(residentState, targetedNeeds, positiveNeeds, contextPlayer)
		if emergency and emergencyReason then
			emitEmergency(emergencyReason, emergencyNeed)
			return true
		end
		return false
	end
	if
		not residentState
		or typeof(residentState.GetNeed) ~= "function"
		or typeof(residentState.SetNeed) ~= "function"
	then
		ResidentDebug.Trace(EFFECT_CHANNEL, "NeedEffects missing resident interfaces", {
			Resident = residentName,
		})
		return false
	end
	if token and token.Cancelled then
		return false
	end
	if not effects or #effects == 0 then
		finalize(true)
		return true
	end
	duration = math.max(duration, 0)
	for needName in pairs(targetedNeeds) do
		sanitizeNeed(residentState, needName)
	end
	ResidentDebug.Trace(EFFECT_CHANNEL, string.format("NeedEffects start: %s", residentName), {
		Resident = residentName,
		Duration = duration,
		Effects = effects,
	})
	if abortIfEmergency() then
		return false
	end
	applyPause()
	applyInstantEffects(residentState, effects, appliedInstant)
	if abortIfEmergency() then
		return failReturn()
	end
	if token and token.Cancelled then
		local cancelReason = if token.Reason and token.Reason ~= "" then token.Reason else "Cancelled"
		ResidentChat.ShowInterrupt(residentState, cancelReason, interruptContext)
		ResidentDebug.Trace(EFFECT_CHANNEL, string.format("NeedEffects cancelled: %s", residentName))
		return failReturn()
	end
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
	if duration == 0 then
		finalize(true)
		return true
	end
	while elapsed < duration do
		if token and token.Cancelled then
			local cancelReason = if token.Reason and token.Reason ~= "" then token.Reason else "Cancelled"
			ResidentChat.ShowInterrupt(residentState, cancelReason, interruptContext)
			ResidentDebug.Trace(EFFECT_CHANNEL, string.format("NeedEffects cancelled: %s", residentName))
			return failReturn()
		end
		if abortIfEmergency() then
			return failReturn()
		end
		if shouldEnd and shouldEnd(residentState) then
			local reasonResolver = behavior.EndReasonProvider
			if reasonResolver then
				local reason = reasonResolver(residentState)
				if reason and reason ~= "" then
					ResidentChat.ShowInterrupt(residentState, reason, interruptContext)
				end
			end
			ResidentDebug.Trace(EFFECT_CHANNEL, string.format("NeedEffects early exit: %s", residentName), {
				Elapsed = elapsed,
			})
			finalize(true)
			return true
		end
		RunService.Heartbeat:Wait()
		local now = os.clock()
		local realDelta = now - lastTick
		lastTick = now
		elapsed += realDelta
		local gameHours = TimeScale.GameHoursFromRealDelta(realDelta)
		if typeof(gameHours) ~= "number" or gameHours ~= gameHours or gameHours <= 0 then
			gameHours = 0
		end
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
	finalize(true)
	return true
end

return NeedEffects
