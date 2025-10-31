--!strict
-- ServerScriptService/Server/Classes/ActionQueue.lua
--
-- ActionQueue
-- A minimal and production-ready executor that runs actions (functions that may yield)
-- in strict FIFO order. It uses a single lightweight runner coroutine that starts
-- only when there is work and stops automatically when the queue becomes empty.
--
-- Dependencies:
--   - ReplicatedStorage.Shared.Queue           (FIFO queue data structure)
--   - ReplicatedStorage.Packages.GoodSignal    (signal implementation)
--
-- Public API:
--   local ActionQueue = require(ReplicatedStorage.Shared.ActionQueue)
--   local queue = ActionQueue.new(optionalContext: any?)
--
--   queue:Enqueue(actionName: string, actionFunction: (context: any?) -> ()): ()
--   queue:EnqueueMany(items: { { Name: string, Execute: (context: any?) -> () } }): number
--   queue:Clear(): ()
--   queue:PeekNextActionName(): string?
--   queue:IsEmpty(): boolean
--   queue:Size(): number
--   queue:IsRunnerAlive(): boolean
--   queue:GetCurrentActionName(): string?
--   queue:WaitUntilEmpty(timeoutSeconds: number?): boolean
--   queue:Destroy(): ()
--
-- Signals (GoodSignal):
--   queue.ActionStarted:Fire(actionName: string)
--   queue.ActionFinished:Fire(actionName: string, succeeded: boolean, errorMessage: string?)
--   queue.QueueEmptied:Fire()

-- Diagnostics:
--   queue.CurrentActionName :: string?
--   queue.ProcessedCount :: number
--
-- Notes:
--   - This module does not attempt to forcibly cancel a currently-running action, because
--     arbitrary yielding Luau functions cannot be safely preempted. If you need cooperative
--     cancellation later, pass a cancellation token into your actions and check it inside them.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Queue = require(ReplicatedStorage.Shared.Utilities.Queue)
local GoodSignal = require(ReplicatedStorage.Packages.GoodSignal)

type Signal = typeof(GoodSignal.new())

export type ActionItem = {
	Name: string,
	Execute: (context: any?) -> (), -- may yield
	Cleanup: (() -> ())?,
}

export type ActionQueue = {
	-- Signals
	ActionStarted: Signal, -- (actionName: string)
	ActionFinished: Signal, -- (actionName: string, succeeded: boolean, errorMessage: string?)
	QueueEmptied: Signal, -- ()

	-- Public API
	Enqueue: (self: ActionQueue, actionName: string, actionFunction: (context: any?) -> ()) -> (),
	EnqueueMany: (self: ActionQueue, items: { ActionItem }) -> number,
	Clear: (self: ActionQueue) -> (),
	PeekNextActionName: (self: ActionQueue) -> string?,
	IsEmpty: (self: ActionQueue) -> boolean,
	Size: (self: ActionQueue) -> number,
	IsRunnerAlive: (self: ActionQueue) -> boolean,
	GetCurrentActionName: (self: ActionQueue) -> string?,
	WaitUntilEmpty: (self: ActionQueue, timeoutSeconds: number?) -> boolean,
	Destroy: (self: ActionQueue) -> (),

	-- Read-only diagnostics
	CurrentActionName: string?,
	ProcessedCount: number,
}

local ActionQueue = {}
ActionQueue.__index = ActionQueue

---------------------------------------------------------------------
-- Constructor
---------------------------------------------------------------------

function ActionQueue.new(optionalContext: any?): ActionQueue
	local self = setmetatable({}, ActionQueue) :: any

	self._context = optionalContext
	self._queue = Queue.new()
	self._runnerIsAlive = false
	self._destroyed = false
	self.CurrentActionName = nil :: string?
	self.ProcessedCount = 0

	self.ActionStarted = GoodSignal.new()
	self.ActionFinished = GoodSignal.new()
	self.QueueEmptied = GoodSignal.new()

	return self
end

---------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------

-- Enqueue a single action. The runner will start automatically if needed.
local function validateCleanup(cleanup: (() -> ())?)
	if cleanup ~= nil and typeof(cleanup) ~= "function" then
		error("[ActionQueue] cleanupFunction must be a function when provided", 3)
	end
end

local function executeCleanup(callback: (() -> ())?)
	if not callback then
		return
	end
	local success = pcall(callback)
	if not success then
		warn("[ActionQueue] Cleanup callback failed")
	end
end

function ActionQueue:Enqueue(actionName: string, actionFunction: (context: any?) -> (), cleanupFunction: (() -> ())?)
	self:_EnsureNotDestroyed("Enqueue")
	self:_ValidateAction(actionName, actionFunction)
	validateCleanup(cleanupFunction)

	local item: ActionItem = { Name = actionName, Execute = actionFunction, Cleanup = cleanupFunction }
	self._queue:Push(item)
	self:_StartRunnerIfNeeded()
end

-- Enqueue multiple actions in order. Returns how many were enqueued.
function ActionQueue:EnqueueMany(items: { ActionItem }): number
	self:_EnsureNotDestroyed("EnqueueMany")

	local count = #items
	if count == 0 then
		return 0
	end

	for index = 1, count do
		local item = items[index]
		self:_ValidateAction(item.Name, item.Execute)
		validateCleanup(item.Cleanup)
	end

	self._queue:PushMany(items)
	self:_StartRunnerIfNeeded()
	return count
end

-- Remove all queued (not currently running) actions.
function ActionQueue:Clear()
	if self._destroyed or self._queue == nil then
		return
	end
	local drained = self._queue:Drain(nil)
	if drained then
		for _, item in ipairs(drained :: { ActionItem }) do
			executeCleanup(item.Cleanup)
		end
	end
end

function ActionQueue:IsEmpty(): boolean
	if self._destroyed or self._queue == nil then
		return true
	end

	return self._queue:IsEmpty()
end

function ActionQueue:Size(): number
	if self._destroyed or self._queue == nil then
		return 0
	end

	return self._queue:Size()
end

function ActionQueue:IsRunnerAlive(): boolean
	return self._runnerIsAlive
end

function ActionQueue:GetCurrentActionName(): string?
	return self.CurrentActionName
end

function ActionQueue:PeekNextActionName(): string?
	if self._destroyed or self._queue == nil then
		return nil
	end

	local nextItem = self._queue:Peek()
	return if nextItem then (nextItem :: ActionItem).Name else nil
end

function ActionQueue:WaitUntilEmpty(timeoutSeconds: number?): boolean
	if self._destroyed then
		return true
	end

	local deadline = if timeoutSeconds ~= nil then os.clock() + math.max(timeoutSeconds, 0) else nil

	local function isDone(): boolean
		return self._destroyed or (not self._runnerIsAlive and self:IsEmpty() and self.CurrentActionName == nil)
	end

	if isDone() then
		return true
	end

	if deadline == nil then
		repeat
			self.QueueEmptied:Wait()
		until isDone()
		return true
	end

	repeat
		local remaining = deadline - os.clock()
		if remaining <= 0 then
			break
		end
		local fired = self:_WaitForQueueEmptiedWithTimeout(remaining)
		if not fired then
			break
		end
	until isDone()

	return isDone()
end

function ActionQueue:Destroy()
	if self._destroyed then
		return
	end

	self._destroyed = true

	self:Clear()
	self._queue = nil :: any

	if not self._runnerIsAlive then
		self.QueueEmptied:Fire()
	end

	-- Disconnect signals
	self.ActionStarted:DisconnectAll()
	self.ActionFinished:DisconnectAll()
	self.QueueEmptied:DisconnectAll()

	self._context = nil
	self._runnerIsAlive = false
	self.CurrentActionName = nil
end

---------------------------------------------------------------------
-- Internal runner
---------------------------------------------------------------------

function ActionQueue:_StartRunnerIfNeeded()
	if self._runnerIsAlive or self._destroyed then
		return
	end
	self._runnerIsAlive = true
	task.defer(function()
		self:_Run()
	end)
end

function ActionQueue:_Run()
	local queueSelf = self :: any

	local function shutdown(shouldFireEmpty: boolean)
		queueSelf._runnerIsAlive = false
		queueSelf.CurrentActionName = nil
		if shouldFireEmpty then
			queueSelf.QueueEmptied:Fire()
		end
		if queueSelf._destroyed then
			queueSelf._queue = nil
		end
	end

	while true do
		if queueSelf._destroyed then
			shutdown(true)
			break
		end

		local queue = queueSelf._queue
		if queue == nil then
			shutdown(false)
			break
		end

		local nextItem = queue:Pop()
		if nextItem == nil then
			shutdown(true)
			break
		end

		local currentAction = nextItem :: ActionItem
		local currentActionName = currentAction.Name
		queueSelf.CurrentActionName = currentActionName
		queueSelf.ActionStarted:Fire(currentActionName)

		local succeeded, errorMessageOrNil = pcall(function()
			currentAction.Execute(queueSelf._context)
		end)

		if succeeded then
			queueSelf.ActionFinished:Fire(currentActionName, true, nil :: string?)
		else
			queueSelf.ActionFinished:Fire(currentActionName, false, tostring(errorMessageOrNil))
		end

		queueSelf.ProcessedCount += 1
		queueSelf.CurrentActionName = nil
	end
end

function ActionQueue:_EnsureNotDestroyed(methodName: string)
	if self._destroyed then
		error("[ActionQueue] Attempted to call '" .. methodName .. "' on a destroyed queue", 2)
	end
end

function ActionQueue:_ValidateAction(actionName: string, actionFunction: (context: any?) -> ())
	if type(actionName) ~= "string" or actionName == "" then
		error("[ActionQueue] actionName must be a non-empty string", 3)
	end
	if type(actionFunction) ~= "function" then
		error("[ActionQueue] actionFunction must be a function", 3)
	end
end

function ActionQueue:_WaitForQueueEmptiedWithTimeout(timeoutSeconds: number): boolean
	local thread = coroutine.running()
	local resumed = false
	local connection: any = nil

	connection = self.QueueEmptied:Connect(function()
		if resumed then
			return
		end
		resumed = true
		if connection ~= nil then
			connection:Disconnect()
			connection = nil
		end
		task.spawn(thread, true)
	end)

	local timeoutThread = task.delay(timeoutSeconds, function()
		if resumed then
			return
		end
		resumed = true
		if connection ~= nil then
			connection:Disconnect()
			connection = nil
		end
		task.spawn(thread, false)
	end)

	local fired = coroutine.yield()

	if connection ~= nil then
		connection:Disconnect()
		connection = nil
	end

	task.cancel(timeoutThread)
	return fired == true
end

return ActionQueue
