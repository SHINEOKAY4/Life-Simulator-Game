--!strict
--[[
Timer.lua — Drift-free timers with a shared Heartbeat runner.

Design:
- Server-synchronized time via Workspace:GetServerTimeNow()
- Absolute end time (endTime = now + duration) to eliminate drift
- Single Heartbeat drives all active timers
- Per-frame and per-second signals
- Full pause / resume / reset / cancel lifecycle
]]

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local HttpService = game:GetService("HttpService")

local GoodSignal = require(ReplicatedStorage.Packages.GoodSignal)

local Timer = {}
Timer.__index = Timer

type Signal = typeof(GoodSignal.new())

export type TimerInstance = typeof(setmetatable(
	{} :: {
		_startTime: number,
		_tickCount: number,
		_pausedRemainingSeconds: number,
		_endTime: number,
		_lastWholeSecond: number?,
		_perFrameSignal: Signal,
		_perSecondSignal: Signal,
		_endedSignal: Signal,
		_isRunning: boolean,
		_isPaused: boolean,
		_isStopped: boolean,
		_isResumed: boolean,
		_isReset: boolean,
		_identifier: string,
	},
	Timer
))

local ActiveTimerList: { TimerInstance } = {}
local RunnerHeartbeatConnection: RBXScriptConnection? = nil

--- Uses Workspace:GetServerTimeNow for a monotonic, network-synchronized clock.
local function getCurrentServerTime(): number
	return Workspace:GetServerTimeNow()
end

--- Advances all active timers by one frame. Called from Heartbeat.
local function stepAllTimers()
	local listSize = #ActiveTimerList
	if listSize == 0 then
		if RunnerHeartbeatConnection then
			RunnerHeartbeatConnection:Disconnect()
			RunnerHeartbeatConnection = nil
		end
		return
	end

	local currentTime = getCurrentServerTime()
	for index = listSize, 1, -1 do
		local timer = ActiveTimerList[index]

		if (not timer._isRunning) or timer._isStopped then
			table.remove(ActiveTimerList, index)
		else
			-- Compute remaining using absolute end time (drift-free).
			local remainingSeconds = math.max(0, timer._endTime - currentTime)

			-- Per-frame signal.
			timer._tickCount += 1
			timer._perFrameSignal:Fire(remainingSeconds)

			-- Per-second signal (fires only when the whole-second boundary changes).
			local whole = math.floor(remainingSeconds + 1e-6)
			if timer._lastWholeSecond ~= whole then
				timer._lastWholeSecond = whole
				timer._perSecondSignal:Fire(whole)
			end

			-- Completion check.
			if remainingSeconds <= 0 then
				timer._isRunning = false
				timer._isPaused = false
				timer._isStopped = true
				table.remove(ActiveTimerList, index)
				timer._endedSignal:Fire()
			end
		end
	end
end

--- Ensures the shared Heartbeat connection exists.
local function ensureRunnerConnection()
	if not RunnerHeartbeatConnection then
		RunnerHeartbeatConnection = RunService.Heartbeat:Connect(stepAllTimers)
	end
end

--- Registers a timer to be driven by the shared Heartbeat runner.
local function addActiveTimer(timer: TimerInstance)
	table.insert(ActiveTimerList, timer)
	ensureRunnerConnection()
end
--- Creates a new timer instance. The timer is idle until Start is called.
--- @return TimerInstance
function Timer.new(): TimerInstance
	local self = setmetatable({}, Timer) :: TimerInstance

	self._startTime = getCurrentServerTime()
	self._tickCount = 0
	self._pausedRemainingSeconds = 0
	self._endTime = 0
	self._lastWholeSecond = nil

	self._perSecondSignal = GoodSignal.new()
	self._perFrameSignal = GoodSignal.new()
	self._endedSignal = GoodSignal.new()

	self._isRunning = false
	self._isPaused = false
	self._isStopped = false
	self._isResumed = false
	self._isReset = false

	self._identifier = HttpService:GenerateGUID(false)

	return self
end

--- Starts the timer for the specified duration (in seconds).
--- Uses an absolute end time to avoid drift.
--- @param duration number Duration in seconds (must be > 0).
function Timer.Start(self: TimerInstance, duration: number)
	if self._isRunning then
		return
	end
	assert(type(duration) == "number" and duration > 0, "Timer.Start: duration must be > 0")

	self._tickCount = 0
	self._startTime = getCurrentServerTime()
	self._endTime = self._startTime + duration
	self._lastWholeSecond = nil

	self._isRunning = true
	self._isPaused = false
	self._isStopped = false
	self._isResumed = false
	self._isReset = false

	addActiveTimer(self)
end

--- Pauses the timer, preserving the remaining time.
function Timer.Pause(self: TimerInstance)
	if (not self._isRunning) or self._isPaused then
		return
	end

	self._pausedRemainingSeconds = math.max(0, self._endTime - getCurrentServerTime())
	self._isPaused = true
	self._isRunning = false
	-- The runner will drop this instance on the next sweep; Resume will re-add it.
end

--- Resumes a previously paused timer from its preserved remaining time.
function Timer.Resume(self: TimerInstance)
	if (not self._isPaused) or self._pausedRemainingSeconds <= 0 then
		return
	end

	self._endTime = getCurrentServerTime() + self._pausedRemainingSeconds
	self._isPaused = false
	self._isRunning = true
	self._isResumed = true
	self._lastWholeSecond = nil

	addActiveTimer(self)
end

--- Cancels the timer immediately without firing the ended signal.
--- After cancel, Remaining() returns 0 until Start is called again.
function Timer.Cancel(self: TimerInstance)
	if (not self._isRunning) and not self._isPaused then
		return
	end

	self._isRunning = false
	self._isPaused = false
	self._isStopped = true
	self._pausedRemainingSeconds = 0
	-- The runner will drop this instance; no ended signal on cancel.
end

--- Resets the timer.
--- If duration is provided, the timer restarts with that duration.
--- If omitted, it restarts using the last known remaining time (if any), otherwise cancels.
--- @param duration number? Optional new duration in seconds.
function Timer.Reset(self: TimerInstance, duration: number?)
	local wasPaused = self._isPaused
	local remaining = if wasPaused then self._pausedRemainingSeconds else math.max(0, self:Remaining())

	local base = duration or remaining
	if base <= 0 then
		self:Cancel()
		return
	end

	self._tickCount = 0
	self._startTime = getCurrentServerTime()
	self._endTime = self._startTime + base
	self._lastWholeSecond = nil

	self._isReset = true
	self._isStopped = false
	self._isPaused = false
	self._isRunning = true

	addActiveTimer(self)
end

--- Returns the remaining time in seconds.
--- While running, it is computed from the absolute end time; while paused, it is the preserved value.
--- @return number remainingSeconds
function Timer.Remaining(self: TimerInstance): number
	if self._isRunning then
		return math.max(0, self._endTime - getCurrentServerTime())
	end
	return math.max(0, self._pausedRemainingSeconds or 0)
end

--- Subscribes a callback that receives the remaining time every frame.
--- @param callback fun(remainingSeconds: number)
--- @return RBXScriptConnection
function Timer.OnFrame(self: TimerInstance, callback: (number) -> ())
	return self._perFrameSignal:Connect(callback)
end

--- Subscribes a callback that receives whole seconds, emitted only when the number changes.
--- @param callback fun(wholeSeconds: number)
--- @return RBXScriptConnection
function Timer.OnSecond(self: TimerInstance, callback: (number) -> ())
	return self._perSecondSignal:Connect(callback)
end

--- Subscribes a callback fired exactly once when the timer completes.
--- @param callback fun()
--- @return RBXScriptConnection
function Timer.OnEnded(self: TimerInstance, callback: () -> ())
	return self._endedSignal:Connect(callback)
end

return Timer
