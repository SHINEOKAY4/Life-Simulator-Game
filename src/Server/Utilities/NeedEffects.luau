--!strict
-- NeedEffects.lua
-- Applies catalog-defined need adjustments while residents interact with stations.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local NeedConfig = require(ReplicatedStorage.Shared.Configurations.NeedConfig)
local TimeScale = require(ReplicatedStorage.Shared.Utilities.TimeScale)
local ServerScriptService = game:GetService("ServerScriptService")
local ResidentDebug = require(ServerScriptService.Server.Utilities.ResidentDebug)
local ResidentChat = require(ServerScriptService.Server.Utilities.ResidentChat)
local PlotService = require(ServerScriptService.Server.Services.PlotService)
local WorldUpdate = require(ServerScriptService.Server.Utilities.WorldUpdate)

local SCHEDULER_TASK_NAME = "NeedEffectsRunner"
local SCHEDULER_INTERVAL = 1 / 30

type SchedulerRuntime = {
	Id: number,
	Step: (dt: number) -> boolean,
	HandleError: (err: any) -> (),
}

local activeRuntimes: { [number]: SchedulerRuntime } = {}
local schedulerActive = false
local nextRuntimeId = 0

local function stepRuntimes(dt: number)
	for _runtimeId, runtime in pairs(activeRuntimes) do
		local success, finishedOrError = pcall(runtime.Step, dt)
		if not success then
			runtime.HandleError(finishedOrError)
		end
	end
	if next(activeRuntimes) == nil then
		WorldUpdate.Unsubscribe(SCHEDULER_TASK_NAME)
		schedulerActive = false
	end
end

local function ensureScheduler()
	if schedulerActive then
		return
	end
	WorldUpdate.Subscribe(SCHEDULER_TASK_NAME, SCHEDULER_INTERVAL, function(dt)
		stepRuntimes(dt)
	end)
	schedulerActive = true
end

type CancelToken = { Cancelled: boolean, Reason: string? }

type EffectDef = {
	Need: string,
	InstantAmount: number?,
	RatePerHour: number?,
}

type NeedDef = NeedConfig.NeedDef
type EmergencyGuard = (residentState: any, value: number, def: NeedDef) -> boolean

type Behavior = {
	Effects: { EffectDef }?,
	DurationSeconds: number?,
	ShouldEnd: ((residentState: any) -> boolean)?,
	Moodlets: { { Name: string, DurationSeconds: number, NeedBias: { [string]: number }? } }?,
	ChatIntervalSeconds: number?,
	ChatPhrases: { ResidentChat.ChatOption }?,
	EndReasonProvider: ((residentState: any) -> string?)?,
	EmergencyGuards: { [string]: EmergencyGuard }?,
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
	contextPlayer: Player?,
	guardOverrides: { [string]: EmergencyGuard }?
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
		local guard = guardOverrides and guardOverrides[needName]
		if guard then
			local ok, suppress = pcall(guard, residentState, value, def)
			if not ok then
				ResidentDebug.Trace(EFFECT_CHANNEL, string.format("Emergency guard error: %s", tostring(guard)), {
					Need = needName,
					Error = suppress,
				})
			elseif suppress then
				continue
			end
		end
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
	local emergencyGuards = behavior.EmergencyGuards
	local contextPlayer = if interruptContext then interruptContext.Player else nil
	if effects then
		targetedNeeds, positiveNeeds = gatherEffectContext(effects)
	else
		targetedNeeds = {}
		positiveNeeds = {}
	end
	local pauseApplied = false
	local pausedNeeds: { [string]: boolean }? = nil
	local usedGlobalPause = false
	local usedLegacyToggle = false
	local residentModel: Model? = if residentState and residentState.Model then residentState.Model else nil
	local activityTracking = false
	local trackedProgress = 0
	local lastEmitTime = 0
	local activityReason: string? = nil
	local stationType = if interruptContext and typeof(interruptContext.StationType) == "string"
		then interruptContext.StationType :: string
		else nil
	local stationAction = if interruptContext and typeof(interruptContext.ActionName) == "string"
		then interruptContext.ActionName :: string
		else nil
	local shouldTrackStation = residentModel ~= nil
		and stationType ~= nil
		and stationType:find("Station", 1, true) ~= nil
	local function setAttribute(attribute: string, value: any)
		if not residentModel then
			return
		end
		residentModel:SetAttribute(attribute, value)
	end
	local function beginActivity()
		if not shouldTrackStation or activityTracking then
			return
		end
		activityTracking = true
		trackedProgress = 0
		lastEmitTime = 0
		activityReason = nil
		setAttribute("StationActivityActive", true)
		setAttribute("StationActivityType", stationType)
		setAttribute("StationActivityAction", stationAction)
		setAttribute("StationActivityDuration", duration)
		setAttribute("StationActivityStart", Workspace:GetServerTimeNow())
		setAttribute("StationActivityProgress", 0)
		setAttribute("StationActivityReason", nil)
	end
	local function emitProgress(progress: number, force: boolean?)
		if not activityTracking then
			return
		end
		trackedProgress = math.clamp(progress, 0, 1)
		if not residentModel then
			return
		end
		if trackedProgress >= 1 or force then
			setAttribute("StationActivityProgress", trackedProgress)
			return
		end
		local now = Workspace:GetServerTimeNow()
		if now - lastEmitTime >= 0.2 then
			lastEmitTime = now
			setAttribute("StationActivityProgress", trackedProgress)
		end
	end
	local function clearActivity(_success: boolean, reason: string?, finalProgress: number?)
		if not activityTracking then
			return
		end
		local progressValue = if finalProgress ~= nil then math.clamp(finalProgress, 0, 1) else trackedProgress
		emitProgress(progressValue, true)
		activityTracking = false
		setAttribute("StationActivityActive", false)
		setAttribute("StationActivityReason", reason)
		setAttribute("StationActivityDuration", nil)
		setAttribute("StationActivityStart", nil)
		setAttribute("StationActivityType", nil)
		setAttribute("StationActivityAction", nil)
		activityReason = nil
	end
	local function applyPause()
		if pauseApplied then
			return
		end
		if residentState then
			local pauseNeedFn = typeof(residentState.PushNeedPause) == "function"
			if pauseNeedFn then
				local added = false
				for needName, isPositive in pairs(positiveNeeds) do
					if isPositive then
						if not pausedNeeds then
							pausedNeeds = {}
						end
						local needs = pausedNeeds :: { [string]: boolean }
						if not needs[needName] then
							(residentState :: any):PushNeedPause(needName)
							needs[needName] = true
						end
						added = true
					end
				end
				if added then
					pauseApplied = true
					return
				end
			end
			if typeof(residentState.PushNeedDecayPause) == "function" then
				residentState:PushNeedDecayPause()
				pauseApplied = true
				usedGlobalPause = true
				return
			end
			if typeof(residentState.SetNeedDecayPaused) == "function" then
				residentState:SetNeedDecayPaused(true)
				pauseApplied = true
				usedLegacyToggle = true
			end
		end
	end
	local function releasePause()
		if not pauseApplied then
			return
		end
		local canPopNeed = pausedNeeds ~= nil and residentState and typeof(residentState.PopNeedPause) == "function"
		if canPopNeed then
			local needs = pausedNeeds :: { [string]: boolean }
			pausedNeeds = nil
			for needName in pairs(needs) do
				(residentState :: any):PopNeedPause(needName)
			end
		elseif residentState then
			local popFn = if typeof(residentState.PopNeedDecayPause) == "function"
				then function()
					residentState:PopNeedDecayPause()
				end
				else nil
			local toggleFn = if typeof(residentState.SetNeedDecayPaused) == "function"
				then function()
					residentState:SetNeedDecayPaused(false)
				end
				else nil
			local releaseOrder = {
				{ Condition = usedGlobalPause, Fn = popFn },
				{ Condition = usedLegacyToggle, Fn = toggleFn },
				{ Condition = true, Fn = popFn },
				{ Condition = true, Fn = toggleFn },
			}
			for _, candidate in ipairs(releaseOrder) do
				local fn = candidate.Fn
				if fn and candidate.Condition then
					fn()
					break
				end
			end
		end
		pauseApplied = false
		usedGlobalPause = false
		usedLegacyToggle = false
	end
	local function finalize(success: boolean, reason: string?, finalProgress: number?)
		if success then
			applyMoodlets(residentState, behavior.Moodlets)
		end
		clearActivity(success, reason, finalProgress)
		releasePause()
	end
	local function failReturn(reason: string?, progress: number?): boolean
		clearActivity(false, reason, progress)
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
	local function abortIfEmergency(): (boolean, string?)
		local emergency, emergencyReason, emergencyNeed =
			evaluateEmergencyNeeds(residentState, targetedNeeds, positiveNeeds, contextPlayer, emergencyGuards)
		if emergency and emergencyReason then
			emitEmergency(emergencyReason, emergencyNeed)
			activityReason = emergencyReason
			return true, emergencyReason
		end
		return false, nil
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
	local abortEarly, abortReason = abortIfEmergency()
	if abortEarly then
		return failReturn(abortReason, trackedProgress)
	end
	applyPause()
	beginActivity()
	emitProgress(0, true)
	applyInstantEffects(residentState, effects, appliedInstant)
	local abortAfterInstant, abortInstantReason = abortIfEmergency()
	if abortAfterInstant then
		return failReturn(abortInstantReason, trackedProgress)
	end
	if token and token.Cancelled then
		local cancelReason = if token.Reason and token.Reason ~= "" then token.Reason else "Cancelled"
		ResidentChat.ShowInterrupt(residentState, cancelReason, interruptContext)
		ResidentDebug.Trace(EFFECT_CHANNEL, string.format("NeedEffects cancelled: %s", residentName))
		activityReason = cancelReason
		return failReturn(cancelReason, trackedProgress)
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
		finalize(true, nil, trackedProgress)
		return true
	end

	local function currentProgress(): number
		if duration > 0 then
			return math.clamp(if duration ~= 0 then elapsed / duration else 0, 0, 1)
		end
		return math.clamp(trackedProgress, 0, 1)
	end

	nextRuntimeId += 1
	local runtimeId = nextRuntimeId
	local runtimeThread: thread? = coroutine.running()
	local waitingForResume = false
	local completed = false
	local finalResult = false
	local hasResult = false

	local function complete(result: boolean)
		if completed then
			return
		end
		completed = true
		hasResult = true
		finalResult = result
		activeRuntimes[runtimeId] = nil
		if waitingForResume and runtimeThread then
			waitingForResume = false
			task.spawn(runtimeThread, result)
			runtimeThread = nil
		end
	end

	local function handleSchedulerError(err: any)
		if completed then
			return
		end
		ResidentDebug.Trace(EFFECT_CHANNEL, string.format("NeedEffects runtime error: %s", tostring(err)), {
			Resident = residentName,
		})
		activityReason = activityReason or "EffectError"
		local result = failReturn(activityReason, currentProgress())
		complete(result)
	end

	local function step(dt: number): boolean
		if completed then
			return true
		end

		if token and token.Cancelled then
			local cancelReason = if token.Reason and token.Reason ~= "" then token.Reason else "Cancelled"
			ResidentChat.ShowInterrupt(residentState, cancelReason, interruptContext)
			ResidentDebug.Trace(EFFECT_CHANNEL, string.format("NeedEffects cancelled: %s", residentName))
			activityReason = cancelReason
			local result = failReturn(cancelReason, currentProgress())
			complete(result)
			return true
		end

		local abortDuring, abortReasonDuring = abortIfEmergency()
		if abortDuring then
			local result = failReturn(abortReasonDuring, currentProgress())
			complete(result)
			return true
		end

		if shouldEnd and shouldEnd(residentState) then
			local reasonResolver = behavior.EndReasonProvider
			local resolvedReason: string? = nil
			if reasonResolver then
				resolvedReason = reasonResolver(residentState)
				if resolvedReason and resolvedReason ~= "" then
					ResidentChat.ShowInterrupt(residentState, resolvedReason, interruptContext)
				end
			end
			ResidentDebug.Trace(EFFECT_CHANNEL, string.format("NeedEffects early exit: %s", residentName), {
				Elapsed = elapsed,
			})
			local reasonLabel = if resolvedReason and resolvedReason ~= "" then resolvedReason else "NeedSatisfied"
			activityReason = reasonLabel
			finalize(true, reasonLabel, currentProgress())
			complete(true)
			return true
		end

		if dt <= 0 then
			return false
		end

		local now = os.clock()
		local realDelta = now - lastTick
		if not (realDelta >= 0) or realDelta ~= realDelta then
			realDelta = dt
		end
		lastTick = now
		elapsed += realDelta

		local gameHours = TimeScale.GameHoursFromRealDelta(realDelta)
		if typeof(gameHours) ~= "number" or gameHours ~= gameHours or gameHours <= 0 then
			gameHours = 0
		end
		if gameHours > 0 then
			for _, effect in ipairs(effects) do
				local rate = effect.RatePerHour
				if rate and rate ~= 0 then
					applyDelta(residentState, effect.Need, rate * gameHours)
				end
			end
		end

		if nextChatTime and chatInterval and now >= nextChatTime then
			repeat
				emitChat()
				nextChatTime += chatInterval
			until nextChatTime == nil or nextChatTime > now
		end

		if duration > 0 then
			emitProgress(math.min(elapsed / duration, 1))
		end

		if elapsed >= duration then
			ResidentDebug.Trace(EFFECT_CHANNEL, string.format("NeedEffects completed: %s", residentName), {
				Elapsed = elapsed,
			})
			activityReason = activityReason or "DurationComplete"
			finalize(true, activityReason, currentProgress())
			complete(true)
			return true
		end

		return false
	end

	local runtime: SchedulerRuntime = {
		Id = runtimeId,
		Step = step,
		HandleError = handleSchedulerError,
	}
	activeRuntimes[runtimeId] = runtime

	ensureScheduler()

	local success, resultOrError = pcall(step, 0)
	if not success then
		handleSchedulerError(resultOrError)
	end

	if completed then
		if not hasResult then
			return false
		end
		return finalResult
	end

	waitingForResume = true
	local resumeResult = coroutine.yield()
	waitingForResume = false
	return resumeResult == true
end

return NeedEffects
