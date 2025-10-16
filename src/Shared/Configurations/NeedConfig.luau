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
	Hunger = { Min = 0, Max = 100, DecayPerHour = 8, Low = 45, Critical = 18, Hysteresis = 10, CooldownMinutes = 60 },
	Energy = { Min = 0, Max = 100, DecayPerHour = 5, Low = 35, Critical = 12, Hysteresis = 12, CooldownMinutes = 240 },
	Hygiene = { Min = 0, Max = 100, DecayPerHour = 5, Low = 35, Critical = 12, Hysteresis = 12, CooldownMinutes = 75 },
	Social = { Min = 0, Max = 100, DecayPerHour = 8, Low = 45, Critical = 18, Hysteresis = 12, CooldownMinutes = 90 },
	Fun = { Min = 0, Max = 100, DecayPerHour = 9, Low = 45, Critical = 20, Hysteresis = 12, CooldownMinutes = 90 },
}

export type Circadian = {
	NightStart: number, -- 22.0
	DayStart: number, -- 6.0
	SleepBias: number, -- weight added to Energy deficit during night
}
local Circadian: Circadian = {
	NightStart = 22.0,
	DayStart = 6.0,
	SleepBias = 0.9, -- encourage stronger bias toward nighttime sleep
}

return {
	Needs = Needs,
	Circadian = Circadian,
}
