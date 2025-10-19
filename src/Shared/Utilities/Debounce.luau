--!strict
-- Debounce.lua
-- Production-ready, no abbreviations, minimal surface area (YAGNI), Roblox API 2025

local Debounce = {}

export type Key = string | number
export type Scope = string | number | nil

-- Internal state: [scopedKey] = expirationTime (monotonic seconds)
local state: { [string]: number? } = {}

-- Defaults
local DEFAULT_DURATION_SECONDS: number = 0.5

-- Use a monotonic clock for durations so wall-clock changes do not affect behavior.
local function now(): number
	return os.clock()
end

local function toScopedKey(key: Key, scope: Scope): string
	if scope == nil then
		return tostring(key)
	end
	return string.format("[%s]::%s", tostring(scope), tostring(key))
end

local function clearKey(scopedKey: string): ()
	state[scopedKey] = nil
end

local function resolveDuration(durationSeconds: number?): number
	if durationSeconds == nil then
		return DEFAULT_DURATION_SECONDS
	end

	if durationSeconds < 0 then
		warn("[Debounce] Negative durations are clamped to zero.")
		return 0
	end

	return durationSeconds
end

-- Returns expiration time or nil if not active; cleans up expired entries.
local function getActiveExpiration(scopedKey: string): number?
	local expirationTime = state[scopedKey]
	if expirationTime == nil then
		return nil
	end

	if now() >= expirationTime then
		clearKey(scopedKey)
		return nil
	end

	return expirationTime
end

-- Attempts to acquire the debounce for the given key.
-- Returns true if acquired (and sets the expiration), false if currently active.
function Debounce.TryAcquire(key: Key, durationSeconds: number?, scope: Scope): boolean
	local scopedKey = toScopedKey(key, scope)

	local expirationTime = getActiveExpiration(scopedKey)
	if expirationTime ~= nil then
		return false
	end

	state[scopedKey] = now() + resolveDuration(durationSeconds)
	return true
end

-- Runs the callback only if the debounce can be acquired.
-- If the callback throws, the debounce is cleared immediately and the error is rethrown.
function Debounce.RunIfAvailable(key: Key, durationSeconds: number?, callback: () -> (), scope: Scope): boolean
	if Debounce.TryAcquire(key, durationSeconds, scope) then
		local success, result = pcall(function()
			callback()
			return true
		end)
		if not success then
			-- Ensure a failing callback does not leave the debounce stuck.
			clearKey(toScopedKey(key, scope))
			error(tostring(result))
		end
		return true
	end

	return false
end

-- Returns true if the debounce is currently active for the key.
function Debounce.IsActive(key: Key, scope: Scope): boolean
	return getActiveExpiration(toScopedKey(key, scope)) ~= nil
end

-- Returns remaining time in seconds; zero if inactive.
function Debounce.TimeRemaining(key: Key, scope: Scope): number
	local expirationTime = getActiveExpiration(toScopedKey(key, scope))
	if expirationTime == nil then
		return 0
	end
	return math.max(0, expirationTime - now())
end

-- Clears the debounce for the specific key.
function Debounce.Clear(key: Key, scope: Scope): ()
	clearKey(toScopedKey(key, scope))
end

-- Clears all debounces.
function Debounce.ClearAll(): ()
	table.clear(state)
end

-- Waits until the debounce for the key is no longer active.
-- Uses precise sleeps based on remaining time; loops if the window is extended.
function Debounce.WaitUntilInactive(key: Key, scope: Scope): ()
	while true do
		local remaining = Debounce.TimeRemaining(key, scope)
		if remaining <= 0 then
			return
		end
		task.wait(remaining)
	end
end

-- Optional utility: update the default duration for future calls (not required to use Debounce).
function Debounce.SetDefaultDuration(durationSeconds: number): ()
	assert(durationSeconds >= 0, "Duration must be non-negative.")
	DEFAULT_DURATION_SECONDS = durationSeconds
end

return table.freeze(Debounce)
