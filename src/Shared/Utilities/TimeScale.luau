--!strict
-- ReplicatedStorage/Shared/Utilities/TimeScale.luau
-- Converts real dt to in-game hours using Lighting.SecondsPerFullDay
local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")

local DEFAULT_SECONDS_PER_DAY = 1440 -- 24 minutes; overridden by attribute anyway

local TimeScale = {}

function TimeScale.GetSecondsPerFullDay(): number
	local v = tonumber(Lighting:GetAttribute("SecondsPerFullDay")) or DEFAULT_SECONDS_PER_DAY
	return math.max(1, v)
end

function TimeScale.GameHoursFromRealDelta(realDt: number): number
	local secPerDay = TimeScale.GetSecondsPerFullDay()
	local realPerGameHour = secPerDay / 24
	return realDt / realPerGameHour
end

function TimeScale.GetClockTime(): number
	local secPerDay = TimeScale.GetSecondsPerFullDay()
	local startClock = (tonumber(Lighting:GetAttribute("StartClockTime")) or 16.5) % 24
	local serverSeconds = Workspace:GetServerTimeNow()
	local phase = (serverSeconds % secPerDay) / secPerDay
	return (phase * 24 + startClock) % 24
end

function TimeScale.GetDayIndex(): number
	local secPerDay = TimeScale.GetSecondsPerFullDay()
	local serverSeconds = Workspace:GetServerTimeNow()
	return math.floor(serverSeconds / secPerDay)
end

function TimeScale.GetSecondsIntoDay(): number
	local secPerDay = TimeScale.GetSecondsPerFullDay()
	local serverSeconds = Workspace:GetServerTimeNow()
	return serverSeconds % secPerDay
end

return TimeScale
