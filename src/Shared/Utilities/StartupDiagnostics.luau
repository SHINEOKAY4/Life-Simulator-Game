--!strict

local StartupDiagnostics = {}
StartupDiagnostics.__index = StartupDiagnostics

type ClockFn = () -> number
type SinkFn = (message: string, payload: { [string]: any }?) -> ()

export type StartupDiagnostics = {
	Channel: string,
	_sequence: number,
	_clock: ClockFn,
	_log: SinkFn,
	_warn: SinkFn,
	_emit: (self: StartupDiagnostics, phase: string, name: string, elapsedMs: number?, payload: { [string]: any }?) -> (),
	Boundary: <T...>(self: StartupDiagnostics, name: string, callback: (T...) -> ...any, T...) -> ...any,
	ResolveDependency: <T...>(self: StartupDiagnostics, dependencyPath: string, resolver: (T...) -> ...any, T...) -> ...any,
}

local function defaultLog(message: string, payload: { [string]: any }?)
	if payload == nil then
		print(message)
		return
	end

	print(message, payload)
end

local function defaultWarn(message: string, payload: { [string]: any }?)
	if payload == nil then
		warn(message)
		return
	end

	warn(message, payload)
end

local function toMilliseconds(seconds: number): number
	return math.floor(seconds * 1000 + 0.5)
end

function StartupDiagnostics.new(channel: string, options: { Clock: ClockFn?, Log: SinkFn?, Warn: SinkFn? }?): StartupDiagnostics
	assert(type(channel) == "string" and channel ~= "", "channel must be a non-empty string")

	local opts = options or {}
	local self: StartupDiagnostics = setmetatable({
		Channel = channel,
		_sequence = 0,
		_clock = opts.Clock or os.clock,
		_log = opts.Log or defaultLog,
		_warn = opts.Warn or defaultWarn,
	}, StartupDiagnostics)

	return self
end

function StartupDiagnostics:_emit(
	phase: string,
	name: string,
	elapsedMs: number?,
	payload: { [string]: any }?
)
	self._sequence += 1
	local message = ("[StartupDiagnostics][%s][%03d][%s] %s"):format(self.Channel, self._sequence, phase, name)
	if elapsedMs ~= nil then
		message = ("%s (%dms)"):format(message, elapsedMs)
	end

	if phase == "ERROR" then
		self._warn(message, payload)
		return
	end

	self._log(message, payload)
end

function StartupDiagnostics:Boundary<T...>(name: string, callback: (T...) -> ...any, ...: T...): ...any
	self:_emit("BEGIN", name, nil, nil)

	local startedAt = self._clock()
	local result = table.pack(pcall(callback, ...))
	local elapsedMs = toMilliseconds(self._clock() - startedAt)

	if not result[1] then
		self:_emit("ERROR", name, elapsedMs, {
			Error = tostring(result[2]),
		})
		error(result[2], 0)
	end

	self:_emit("OK", name, elapsedMs, nil)
	return table.unpack(result, 2, result.n)
end

function StartupDiagnostics:ResolveDependency<T...>(
	dependencyPath: string,
	resolver: (T...) -> ...any,
	...: T...
): ...any
	return self:Boundary(("Resolve %s"):format(dependencyPath), resolver, ...)
end

return StartupDiagnostics
