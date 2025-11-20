--!strict
-- NeedEffects.lua
-- Applies catalog-defined need adjustments while residents interact with stations.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local ServerScriptService = game:GetService("ServerScriptService")

local NeedConfig = require(ReplicatedStorage.Shared.Configurations.NeedConfig)
local TimeScale = require(ReplicatedStorage.Shared.Utilities.TimeScale)
local ResidentDebug = require(ServerScriptService.Server.Utilities.ResidentDebug)
local ResidentChat = require(ServerScriptService.Server.Utilities.ResidentChat)
local WorldUpdate = require(ServerScriptService.Server.Utilities.WorldUpdate)

local SCHEDULER_TASK_NAME = "NeedEffectsRunner"
local SCHEDULER_INTERVAL = 1 / 30

type SchedulerRuntime = {
	Id: number,
	Step: (dt: number) -> boolean,
}

local activeRuntimes: { [number]: SchedulerRuntime } = {}
local schedulerActive = false
local nextRuntimeId = 0

local function stepRuntimes(dt: number)
	for _, runtime in pairs(activeRuntimes) do
		runtime.Step(dt)
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
local ABORT_ERROR_PREFIX = "NeedEffectsAborted|"

NeedEffects.ABORT_ERROR_PREFIX = ABORT_ERROR_PREFIX

function NeedEffects.FormatAbortError(reason: string?): string
	local normalized = if reason and reason ~= "" then reason else "Unknown"
	return ABORT_ERROR_PREFIX .. normalized
end

function NeedEffects.ParseAbortReason(message: string?): string?
	if typeof(message) ~= "string" then
		return nil
	end
	if message:sub(1, #ABORT_ERROR_PREFIX) ~= ABORT_ERROR_PREFIX then
		return nil
	end
	local raw = message:sub(#ABORT_ERROR_PREFIX + 1)
	if raw == "" then
		return "Unknown"
	end
	return raw
end

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
): (boolean, string?)
	local effects = behavior.Effects
	local duration = behavior.DurationSeconds or 10
	local shouldEnd = behavior.ShouldEnd
	local appliedInstant: { [number]: boolean } = {}

	local residentName = "UnknownResident"
	if residentState then
		local save = (residentState :: any).Save
		if typeof(save) == "table" and save.Name then
			residentName = save.Name
		elseif (residentState :: any).Name then
			residentName = (residentState :: any).Name
		end
	end

	local chatInterval = behavior.ChatIntervalSeconds
	if chatInterval and chatInterval <= 0 then
		chatInterval = nil
	end
	local chatPhrases = behavior.ChatPhrases

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
			-- Simple global pause for now
			if typeof(residentState.PushNeedDecayPause) == "function" then
				residentState:PushNeedDecayPause()
				pauseApplied = true
				usedGlobalPause = true
			elseif typeof(residentState.SetNeedDecayPaused) == "function" then
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
		if residentState then
			if usedGlobalPause and typeof(residentState.PopNeedDecayPause) == "function" then
				residentState:PopNeedDecayPause()
			elseif usedLegacyToggle and typeof(residentState.SetNeedDecayPaused) == "function" then
				residentState:SetNeedDecayPaused(false)
			end
		end
		pauseApplied = false
		usedGlobalPause = false
		usedLegacyToggle = false
	end

	local isFinalized = false
	local finalReason: string? = nil

	local function finalize(success: boolean, reason: string?, finalProgress: number?)
		if isFinalized then
			return
		end
		isFinalized = true
		if success then
			finalReason = nil
			applyMoodlets(residentState, behavior.Moodlets)
		else
			finalReason = reason or finalReason
		end
		clearActivity(success, reason, finalProgress)
		releasePause()
	end

	local function failReturn(reason: string?, progress: number?): (boolean, string?)
		finalize(false, reason, progress)
		return false, reason
	end

	if
		not residentState
		or typeof(residentState.GetNeed) ~= "function"
		or typeof(residentState.SetNeed) ~= "function"
	then
		return failReturn("InvalidState", trackedProgress)
	end

	if token and token.Cancelled then
		local cancelReason = if token.Reason and token.Reason ~= "" then token.Reason else "Cancelled"
		return failReturn(cancelReason, trackedProgress)
	end

	if not effects or #effects == 0 then
		finalize(true, nil, trackedProgress)
		return true, nil
	end

	duration = math.max(duration, 0)

	ResidentDebug.Trace(EFFECT_CHANNEL, string.format("NeedEffects start: %s", residentName), {
		Resident = residentName,
		Duration = duration,
		Effects = effects,
	})

	applyPause()
	beginActivity()
	emitProgress(0, true)
	applyInstantEffects(residentState, effects, appliedInstant)

	if token and token.Cancelled then
		local cancelReason = if token.Reason and token.Reason ~= "" then token.Reason else "Cancelled"
		ResidentChat.ShowInterrupt(residentState, cancelReason, interruptContext)
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
		return true, nil
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
	local finalResultReason: string? = nil

	local function complete(result: boolean, reason: string?)
		if completed then
			return
		end
		completed = true
		hasResult = true
		finalResult = result
		finalResultReason = reason or finalReason
		activeRuntimes[runtimeId] = nil
		if waitingForResume and runtimeThread then
			waitingForResume = false
			task.spawn(runtimeThread, result, finalResultReason)
			runtimeThread = nil
		end
	end

	local function step(dt: number): boolean
		if completed then
			return true
		end

		if token and token.Cancelled then
			local cancelReason = if token.Reason and token.Reason ~= "" then token.Reason else "Cancelled"
			ResidentChat.ShowInterrupt(residentState, cancelReason, interruptContext)
			local result, failureReason = failReturn(cancelReason, currentProgress())
			complete(result, failureReason)
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
			local reasonLabel = if resolvedReason and resolvedReason ~= "" then resolvedReason else "NeedSatisfied"
			activityReason = reasonLabel
			finalize(true, reasonLabel, currentProgress())
			complete(true, nil)
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
			activityReason = activityReason or "DurationComplete"
			finalize(true, activityReason, currentProgress())
			complete(true, nil)
			return true
		end

		return false
	end

	local runtime: SchedulerRuntime = {
		Id = runtimeId,
		Step = step,
	}
	activeRuntimes[runtimeId] = runtime

	ensureScheduler()

	step(0)

	if completed then
		return finalResult, finalResultReason
	end

	waitingForResume = true
	local resumeResult, resumeReason = coroutine.yield()
	waitingForResume = false
	return resumeResult == true, resumeReason
end

return NeedEffects
