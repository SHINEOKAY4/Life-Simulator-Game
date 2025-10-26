--!strict
-- Coordinates shift schedules against the accelerated game clock.
-- Produces events for automatic shift start reminders and auto clock-in/out flows.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local GoodSignal = require(ReplicatedStorage.Packages.GoodSignal)
local TimeScale = require(ReplicatedStorage.Shared.Utilities.TimeScale)
local CareerShiftConfig = require(ReplicatedStorage.Shared.Configurations.CareerShiftConfig)
local ResidentService = require(ServerScriptService.Server.Services.ResidentService)

type ShiftTemplate = CareerShiftConfig.ShiftTemplate

type EventType = "Reminder" | "Start" | "End"

type ScheduledEvent = {
	Time: number,
	Type: EventType,
	UserId: number,
	ResidentName: string,
	ShiftId: string,
	Version: number,
	Cancelled: boolean?,
}

type ResidentRuntime = {
	UserId: number,
	ResidentName: string,
	ShiftId: string,
	Template: ShiftTemplate,
	Player: Player?,
	Version: number,
	Active: boolean,
	AutoManaged: boolean,
	ActiveStartTime: number?,
	NextReminderEvent: ScheduledEvent?,
	NextStartEvent: ScheduledEvent?,
	ActiveEndEvent: ScheduledEvent?,
}

local PROCESS_EPSILON = 0.05

local ShiftSchedulerService = {}

ShiftSchedulerService.ShiftReminder = GoodSignal.new()
ShiftSchedulerService.ShiftStartDue = GoodSignal.new()
ShiftSchedulerService.ShiftEndDue = GoodSignal.new()
ShiftSchedulerService.ShiftMissed = GoodSignal.new()

local runtimesByUser: { [number]: { [string]: ResidentRuntime } } = {}
local eventQueue: { ScheduledEvent } = {}

local function getRuntime(userId: number, residentName: string): ResidentRuntime?
	local map = runtimesByUser[userId]
	if not map then
		return nil
	end
	return map[residentName]
end

local function setRuntime(runtime: ResidentRuntime)
	local map = runtimesByUser[runtime.UserId]
	if not map then
		map = {}
		runtimesByUser[runtime.UserId] = map
	end
	map[runtime.ResidentName] = runtime
end

local function removeRuntime(userId: number, residentName: string)
	local map = runtimesByUser[userId]
	if not map then
		return
	end
	local runtime = map[residentName]
	if runtime then
		runtime.Active = false
		runtime.AutoManaged = false
		if runtime.NextReminderEvent then
			runtime.NextReminderEvent.Cancelled = true
			runtime.NextReminderEvent = nil
		end
		if runtime.NextStartEvent then
			runtime.NextStartEvent.Cancelled = true
			runtime.NextStartEvent = nil
		end
		if runtime.ActiveEndEvent then
			runtime.ActiveEndEvent.Cancelled = true
			runtime.ActiveEndEvent = nil
		end
	end
	map[residentName] = nil
	if next(map) == nil then
		runtimesByUser[userId] = nil
	end
end

local function heapSwap(i: number, j: number)
	eventQueue[i], eventQueue[j] = eventQueue[j], eventQueue[i]
end

local function heapPush(event: ScheduledEvent)
	local index = #eventQueue + 1
	eventQueue[index] = event
	while index > 1 do
		local parent = math.floor(index / 2)
		if eventQueue[parent].Time <= eventQueue[index].Time then
			break
		end
		heapSwap(parent, index)
		index = parent
	end
end

local function heapPop(): ScheduledEvent?
	local count = #eventQueue
	if count == 0 then
		return nil
	end
	local top = eventQueue[1]
	local last = eventQueue[count]
	eventQueue[count] = nil
	count -= 1
	if count > 0 then
		eventQueue[1] = last
		local index = 1
		while true do
			local left = index * 2
			local right = left + 1
			local smallest = index
			if left <= count and eventQueue[left].Time < eventQueue[smallest].Time then
				smallest = left
			end
			if right <= count and eventQueue[right].Time < eventQueue[smallest].Time then
				smallest = right
			end
			if smallest == index then
				break
			end
			heapSwap(index, smallest)
			index = smallest
		end
	end
	return top
end

local function heapPeek(): ScheduledEvent?
	return eventQueue[1]
end

local function clockBaselineHours(): number
	return (tonumber(Lighting:GetAttribute("StartClockTime")) or 16.5) % 24
end

local function secondsPerDay(): number
	return TimeScale.GetSecondsPerFullDay()
end

local function secondsPerMinute(): number
	return secondsPerDay() / (24 * 60)
end

local function clockToDaySeconds(clockTime: number, secPerDay: number): number
	local baseline = clockBaselineHours()
	local deltaHours = (clockTime - baseline) % 24
	return (deltaHours / 24) * secPerDay
end

local function computeDurationSeconds(template: ShiftTemplate, secPerDay: number): number
	local startSeconds = clockToDaySeconds(template.StartClockTime, secPerDay)
	local endSeconds = clockToDaySeconds(template.EndClockTime, secPerDay)
	local duration = (endSeconds - startSeconds) % secPerDay
	if duration <= 0 then
		duration = secPerDay
	end
	return duration
end

local function dayMatches(template: ShiftTemplate, dayIndex: number): boolean
	local dayOfWeek = dayIndex % 7
	for _, allowedDay in template.Days do
		if allowedDay == dayOfWeek then
			return true
		end
	end
	return false
end

local function findWindowAround(template: ShiftTemplate, referenceTime: number, secPerDay: number): (number?, number?)
	local startOffset = clockToDaySeconds(template.StartClockTime, secPerDay)
	local duration = computeDurationSeconds(template, secPerDay)
	local baseDayIndex = math.floor(referenceTime / secPerDay)
	for dayOffset = 0, 1 do
		local dayIndex = baseDayIndex - dayOffset
		if dayIndex < 0 then
			break
		end
		if dayMatches(template, dayIndex) then
			local startTime = dayIndex * secPerDay + startOffset
			local endTime = startTime + duration
			if referenceTime >= startTime and referenceTime < endTime then
				return startTime, endTime
			end
		end
	end
	return nil, nil
end

local function computeNextStartServerTime(template: ShiftTemplate, afterServerTime: number): number?
	local secPerDay = secondsPerDay()
	local startOffset = clockToDaySeconds(template.StartClockTime, secPerDay)
	local baseDayIndex = math.floor(afterServerTime / secPerDay)
	for dayOffset = 0, 7 do
		local candidateDayIndex = baseDayIndex + dayOffset
		local dayOfWeek = candidateDayIndex % 7
		local matches = false
		for _, allowedDay in template.Days do
			if allowedDay == dayOfWeek then
				matches = true
				break
			end
		end
		if not matches then
			continue
		end
		local candidateStart = candidateDayIndex * secPerDay + startOffset
		if candidateStart > afterServerTime + PROCESS_EPSILON then
			return candidateStart
		end
	end
	return nil
end

local function createEvent(
	runtime: ResidentRuntime,
	eventType: EventType,
	time: number,
	version: number
): ScheduledEvent
	local event: ScheduledEvent = {
		Time = time,
		Type = eventType,
		UserId = runtime.UserId,
		ResidentName = runtime.ResidentName,
		ShiftId = runtime.ShiftId,
		Version = version,
	}
	heapPush(event)
	return event
end

local function cancelEvent(event: ScheduledEvent?)
	if event then
		event.Cancelled = true
	end
end

local function planNextWindow(runtime: ResidentRuntime, fromTime: number?)
	cancelEvent(runtime.NextReminderEvent)
	cancelEvent(runtime.NextStartEvent)
	runtime.NextReminderEvent = nil
	runtime.NextStartEvent = nil
	if runtime.Active then
		return
	end
	local nowServer = Workspace:GetServerTimeNow()
	local baseline = math.max(fromTime or nowServer, nowServer)
	local nextStart = computeNextStartServerTime(runtime.Template, baseline)
	if not nextStart then
		return
	end
	local version = (runtime.Version or 0) + 1
	runtime.Version = version
	runtime.NextStartEvent = createEvent(runtime, "Start", nextStart, version)
	local reminderMinutes = runtime.Template.ReminderMinutes or CareerShiftConfig.DEFAULT_REMINDER_MINUTES
	local reminderSeconds = reminderMinutes * secondsPerMinute()
	local reminderTime = nextStart - reminderSeconds
	if reminderTime > nowServer + PROCESS_EPSILON then
		runtime.NextReminderEvent = createEvent(runtime, "Reminder", reminderTime, version)
	else
		runtime.NextReminderEvent = nil
	end
end

local function scheduleEnd(runtime: ResidentRuntime, startServerTime: number, overrideEndTime: number?)
	cancelEvent(runtime.ActiveEndEvent)
	runtime.ActiveEndEvent = nil
	local secPerDay = secondsPerDay()
	local durationSeconds = computeDurationSeconds(runtime.Template, secPerDay)
	local endTime = overrideEndTime or (startServerTime + durationSeconds)
	if endTime <= Workspace:GetServerTimeNow() + PROCESS_EPSILON then
		return
	end
	local version = runtime.Version or 0
	runtime.ActiveEndEvent = createEvent(runtime, "End", endTime, version)
	runtime.ActiveStartTime = startServerTime
end

local function handleStartConfirmation(runtime: ResidentRuntime, event: ScheduledEvent, result)
	cancelEvent(runtime.NextReminderEvent)
	runtime.NextReminderEvent = nil
	runtime.NextStartEvent = nil
	local outcome = result and result.Outcome or "Missed"
	if outcome == "Started" then
		runtime.Active = true
		runtime.AutoManaged = true
		scheduleEnd(runtime, result.StartServerTimeOverride or event.Time, result.EndServerTimeOverride)
	elseif outcome == "Skipped" then
		runtime.Active = runtime.Active
		runtime.AutoManaged = false
		planNextWindow(runtime, event.Time)
	elseif outcome == "Missed" then
		runtime.Active = false
		runtime.AutoManaged = false
		planNextWindow(runtime, event.Time)
		ShiftSchedulerService.ShiftMissed:Fire({
			Player = runtime.Player,
			UserId = runtime.UserId,
			ResidentName = runtime.ResidentName,
			Shift = runtime.Template,
			Reason = result and result.Reason or "",
		})
	else
		planNextWindow(runtime, event.Time)
	end
end

local function handleEndConfirmation(runtime: ResidentRuntime, event: ScheduledEvent, result)
	runtime.ActiveEndEvent = nil
	local outcome = result and result.Outcome or "Ended"
	if outcome == "Extended" then
		local extensionSeconds = result and result.ExtendSeconds or 0
		local nextEndTime = event.Time + math.max(extensionSeconds, secondsPerMinute())
		scheduleEnd(runtime, runtime.ActiveStartTime or event.Time, nextEndTime)
		return
	end
	runtime.Active = false
	runtime.AutoManaged = false
	planNextWindow(runtime, result and result.NextStartFrom or event.Time)
end

local function dispatchStartEvent(event: ScheduledEvent, runtime: ResidentRuntime)
	local confirmed = false
	ShiftSchedulerService.ShiftStartDue:Fire({
		Player = runtime.Player,
		UserId = runtime.UserId,
		ResidentName = runtime.ResidentName,
		Shift = runtime.Template,
		StartServerTime = event.Time,
		Confirm = function(result)
			if confirmed then
				return
			end
			confirmed = true
			handleStartConfirmation(runtime, event, result)
		end,
	})
	if not confirmed then
		task.defer(function()
			if confirmed then
				return
			end
			handleStartConfirmation(
				runtime,
				event,
				{
					Outcome = "Missed",
					Reason = "NoConfirm",
					StartServerTimeOverride = nil :: number?,
					EndServerTimeOverride = nil :: number?,
				} :: any
			)
		end)
	end
end

local function dispatchReminderEvent(event: ScheduledEvent, runtime: ResidentRuntime)
	ShiftSchedulerService.ShiftReminder:Fire({
		Player = runtime.Player,
		UserId = runtime.UserId,
		ResidentName = runtime.ResidentName,
		Shift = runtime.Template,
		StartServerTime = runtime.NextStartEvent and runtime.NextStartEvent.Time or event.Time,
	})
	runtime.NextReminderEvent = nil
end

local function dispatchEndEvent(event: ScheduledEvent, runtime: ResidentRuntime)
	local confirmed = false
	ShiftSchedulerService.ShiftEndDue:Fire({
		Player = runtime.Player,
		UserId = runtime.UserId,
		ResidentName = runtime.ResidentName,
		Shift = runtime.Template,
		EndServerTime = event.Time,
		Confirm = function(result)
			if confirmed then
				return
			end
			confirmed = true
			handleEndConfirmation(runtime, event, result)
		end,
	})
	if not confirmed then
		task.defer(function()
			if confirmed then
				return
			end
			handleEndConfirmation(
				runtime,
				event,
				{
					Outcome = "Ended",
					ExtendSeconds = nil :: number?,
					NextStartFrom = nil :: number?,
				} :: any
			)
		end)
	end
end

local function processEvents() -- Why is this called in a runservice loop and then there is another while loop???
	local now = Workspace:GetServerTimeNow()
	while true do
		local nextEvent = heapPeek()
		if not nextEvent then
			return
		end
		if nextEvent.Cancelled then
			heapPop()
			continue
		end
		if nextEvent.Time > now + PROCESS_EPSILON then
			return
		end
		heapPop()
		local runtime = getRuntime(nextEvent.UserId, nextEvent.ResidentName)
		if not runtime then
			continue
		end
		if runtime.ShiftId ~= nextEvent.ShiftId or runtime.Version ~= nextEvent.Version then
			continue
		end
		if nextEvent.Type == "Reminder" then
			dispatchReminderEvent(nextEvent, runtime)
		elseif nextEvent.Type == "Start" then
			dispatchStartEvent(nextEvent, runtime)
		elseif nextEvent.Type == "End" then
			dispatchEndEvent(nextEvent, runtime)
		end
	end
end

function ShiftSchedulerService.ApplyShiftAssignment(player: Player, residentState: any, shiftId: string)
	local template = CareerShiftConfig.GetShift(shiftId)
	if not template then
		warn(string.format("[ShiftScheduler] Unknown shift '%s'", shiftId))
		return
	end
	local userId = player.UserId
	local residentNameValue = residentState.Save.Name
	if type(residentNameValue) ~= "string" or residentNameValue == "" then
		warn("[ShiftScheduler] Resident name missing for shift assignment")
		return
	end
	local residentName = residentNameValue
	local existing = getRuntime(userId, residentName)
	local runtime: ResidentRuntime
	if existing then
		runtime = existing
		runtime.ShiftId = shiftId
		runtime.Template = template
		runtime.Player = player
	else
		runtime = {
			UserId = userId,
			ResidentName = residentName,
			ShiftId = shiftId,
			Template = template,
			Player = player,
			Version = 0,
			Active = false,
			AutoManaged = false,
			ActiveStartTime = nil,
			NextReminderEvent = nil,
			NextStartEvent = nil,
			ActiveEndEvent = nil,
		} :: ResidentRuntime
		setRuntime(runtime)
	end
	local isOnShift = residentState.IsOnShift == true
	runtime.Active = isOnShift
	runtime.AutoManaged = false
	if isOnShift then
		runtime.ActiveStartTime = runtime.ActiveStartTime or Workspace:GetServerTimeNow()
	else
		runtime.ActiveStartTime = nil
	end
	cancelEvent(runtime.NextReminderEvent)
	cancelEvent(runtime.NextStartEvent)
	cancelEvent(runtime.ActiveEndEvent)
	runtime.NextReminderEvent = nil
	runtime.NextStartEvent = nil
	runtime.ActiveEndEvent = nil
	if isOnShift then
		return
	end
	planNextWindow(runtime)
end

function ShiftSchedulerService.ClearShift(player: Player, residentName: string)
	removeRuntime(player.UserId, residentName)
end

function ShiftSchedulerService.SyncPlayerResidents(player: Player)
	local residents = ResidentService.GetResidents(player)
	if not residents then
		return
	end
	local userId = player.UserId
	local tracked = {}
	for name, resident in residents do
		local save = resident.Save
		local assignedShiftId = save.AssignedShiftId
		if type(assignedShiftId) == "string" and assignedShiftId ~= "" then
			tracked[name] = true
			ShiftSchedulerService.ApplyShiftAssignment(player, resident, assignedShiftId)
		else
			ShiftSchedulerService.ClearShift(player, name)
		end
	end
	local existing = runtimesByUser[userId]
	if existing then
		for name in existing do
			if not tracked[name] then
				removeRuntime(userId, name)
			end
		end
	end
end

function ShiftSchedulerService.NotifyClockIn(player: Player, residentName: string)
	local runtime = getRuntime(player.UserId, residentName)
	if not runtime then
		return
	end
	runtime.Player = player
	runtime.Active = true
	runtime.AutoManaged = false
	runtime.ActiveStartTime = Workspace:GetServerTimeNow()
	cancelEvent(runtime.NextReminderEvent)
	cancelEvent(runtime.NextStartEvent)
	runtime.NextReminderEvent = nil
	runtime.NextStartEvent = nil
end

function ShiftSchedulerService.NotifyClockOut(player: Player, residentName: string)
	local runtime = getRuntime(player.UserId, residentName)
	if not runtime then
		return
	end
	runtime.Player = player
	runtime.Active = false
	runtime.AutoManaged = false
	runtime.ActiveStartTime = nil
	cancelEvent(runtime.ActiveEndEvent)
	runtime.ActiveEndEvent = nil
	planNextWindow(runtime)
end

export type ShiftRuntimeSnapshot = {
	Template: ShiftTemplate,
	Active: boolean,
	AutoManaged: boolean,
	ActiveStartTime: number?,
	ActiveEndTime: number?,
	NextStartTime: number?,
	IsWithinWindow: boolean,
	WindowStartTime: number?,
	WindowEndTime: number?,
}

function ShiftSchedulerService.GetShiftRuntimeSnapshot(player: Player, residentName: string): ShiftRuntimeSnapshot?
	local runtime = getRuntime(player.UserId, residentName)
	if not runtime then
		return nil
	end
	local template = runtime.Template
	if not template then
		return nil
	end
	local now = Workspace:GetServerTimeNow()
	local secPerDay = secondsPerDay()
	local windowStart, windowEnd = findWindowAround(template, now, secPerDay)
	local nextStartTime: number?
	if runtime.NextStartEvent then
		nextStartTime = runtime.NextStartEvent.Time
	else
		nextStartTime = computeNextStartServerTime(template, now)
	end
	local activeEndTime = if runtime.ActiveEndEvent then runtime.ActiveEndEvent.Time else nil
	if runtime.Active and not activeEndTime and runtime.ActiveStartTime then
		activeEndTime = runtime.ActiveStartTime + computeDurationSeconds(template, secPerDay)
	end
	return {
		Template = template,
		Active = runtime.Active,
		AutoManaged = runtime.AutoManaged,
		ActiveStartTime = runtime.ActiveStartTime,
		ActiveEndTime = activeEndTime,
		NextStartTime = nextStartTime,
		IsWithinWindow = windowStart ~= nil,
		WindowStartTime = windowStart,
		WindowEndTime = windowEnd,
	}
end

function ShiftSchedulerService.RemovePlayer(player: Player)
	local map = runtimesByUser[player.UserId]
	if not map then
		return
	end
	for name in map do
		removeRuntime(player.UserId, name)
	end
end

function ShiftSchedulerService.Init()
	RunService.Heartbeat:Connect(processEvents)
	ResidentService.PlayerResidentsChanged:Connect(function(player)
		ShiftSchedulerService.SyncPlayerResidents(player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		ShiftSchedulerService.RemovePlayer(player)
	end)
	for _, player in ipairs(Players:GetPlayers()) do
		ShiftSchedulerService.SyncPlayerResidents(player)
	end
end

return ShiftSchedulerService
