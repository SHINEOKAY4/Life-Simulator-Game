--!strict
-- ReplicatedStorage/Shared/Configurations/NeedConfig.lua
-- Per-in-game-hour decay with low/critical thresholds and simple circadian hints.

export type NeedDef = {
	Min: number,
	Max: number,
	DecayPerHour: number, -- units per in-game hour
	Low: number, -- begin tending
	Critical: number, -- emergency
	Hysteresis: number, -- leave action when value rebounds above Low + Hysteresis
	CooldownMinutes: number, -- avoid repeating same action immediately
}

export type NeedConfig = { [string]: NeedDef }

local Needs: NeedConfig = {
	Hunger = { Min = 0, Max = 100, DecayPerHour = 15, Low = 45, Critical = 20, Hysteresis = 8, CooldownMinutes = 3 },
	Energy = { Min = 0, Max = 100, DecayPerHour = 8, Low = 40, Critical = 15, Hysteresis = 10, CooldownMinutes = 5 },
	Hygiene = { Min = 0, Max = 100, DecayPerHour = 6, Low = 35, Critical = 10, Hysteresis = 12, CooldownMinutes = 6 },
	Fun = { Min = 0, Max = 100, DecayPerHour = 10, Low = 50, Critical = 25, Hysteresis = 10, CooldownMinutes = 4 },
	Social = { Min = 0, Max = 100, DecayPerHour = 6, Low = 40, Critical = 15, Hysteresis = 8, CooldownMinutes = 4 },
}

-- Circadian hints (used by PriorityPolicy)
export type Circadian = {
	NightStart: number, -- 22.0
	DayStart: number, -- 6.0
	SleepBias: number, -- weight added to Energy deficit during night
}
local Circadian: Circadian = {
	NightStart = 22.0,
	DayStart = 6.0,
	SleepBias = 0.20, -- +20% urgency for Energy during night
}

return {
	Needs = Needs,
	Circadian = Circadian,
}
