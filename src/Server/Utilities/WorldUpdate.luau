--!strict
-- WorldUpdate.lua
-- Centralized lightweight update dispatcher.
-- Allows multiple systems to subscribe periodic callbacks

local RunService = game:GetService("RunService")

type Task = {
	Name: string,
	Interval: number,
	Accum: number,
	Callback: (dt: number) -> (),
}

local WorldUpdate = {}
local _tasks: { [string]: Task } = {}
local _connection: RBXScriptConnection? = nil

local function safeInvoke(name: string, callback: (dt: number) -> (), dt: number)
	local ok, err = (pcall :: any)(callback, dt)
	if not ok then
		warn(string.format("[WorldUpdate] Task '%s' failed: %s", name, tostring(err)))
	end
	return ok :: boolean
end

-- Internal: starts the single heartbeat when first subscriber joins.
local function ensureConnection()
	if _connection then
		return
	end
	_connection = RunService.Heartbeat:Connect(function(dt)
		for name, task in pairs(_tasks) do
			task.Accum += dt
			local interval = task.Interval
			while task.Accum >= interval do
				task.Accum -= interval
				safeInvoke(name, task.Callback, interval)
				if _tasks[name] ~= task then
					break
				end
			end
		end

		-- Auto-shutdown when no tasks remain.
		if next(_tasks) == nil then
			if _connection then
				_connection:Disconnect()
				_connection = nil
			end
		end
	end)
end

--- Subscribes a periodic callback.
-- @param name unique key for this subscriber
-- @param intervalSeconds minimum interval between calls
-- @param callback function(dt: number) -- must not yield
--- Subscribes a periodic callback.
-- @param name unique key for this subscriber (non-empty string)
-- @param intervalSeconds minimum interval between calls
-- @param callback function(dt: number) -- must not yield; receives the clamped interval
function WorldUpdate.Subscribe(name: string, intervalSeconds: number, callback: (dt: number) -> ())
	assert(type(name) == "string" and name ~= "", "WorldUpdate.Subscribe expects a non-empty string name")
	assert(
		type(intervalSeconds) == "number" and intervalSeconds > 0,
		"WorldUpdate.Subscribe expects a positive interval"
	)
	assert(type(callback) == "function", "WorldUpdate.Subscribe expects a function callback")

	if _tasks[name] then
		warn(string.format("[WorldUpdate] Task '%s' is already registered; replacing with new callback", name))
	end

	_tasks[name] = {
		Name = name,
		Interval = math.max(intervalSeconds, 1 / 60), -- clamp  1 frame
		Accum = 0,
		Callback = callback,
	}
	ensureConnection()
end

--- Unsubscribes a previously registered callback.
function WorldUpdate.Unsubscribe(name: string)
	_tasks[name] = nil
end

--- Returns whether a task is currently registered.
function WorldUpdate.IsSubscribed(name: string): boolean
	return _tasks[name] ~= nil
end

--- Returns the number of registered tasks.
function WorldUpdate.GetTaskCount(): number
	local count = 0
	for _ in pairs(_tasks) do
		count += 1
	end
	return count
end

--- Immediately clears all tasks and stops the heartbeat.
function WorldUpdate.ClearAll()
	table.clear(_tasks)
	if _connection then
		_connection:Disconnect()
		_connection = nil
	end
end

return WorldUpdate
