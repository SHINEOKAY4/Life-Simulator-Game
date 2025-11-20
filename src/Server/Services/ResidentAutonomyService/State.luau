--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NeedConfig = require(ReplicatedStorage.Shared.Configurations.NeedConfig)
local TimeScale = require(ReplicatedStorage.Shared.Utilities.TimeScale)

export type ResidentState = any

local State = {}

State.NeedStationTypes = {
	Hunger = { "CookStation", "FoodStorage" },
	Bladder = { "ComfortStation" },
	Energy = { "RestStation" },
	Hygiene = { "HygieneStation" },
	Social = { "SocialStation" },
	Fun = { "FunStation" },
}

State.ResidentNextEvaluation = setmetatable({} :: { [ResidentState]: number }, { __mode = "k" })
State.StationIteratorState = {} :: { [number]: { [string]: { version: number, order: { string }, index: number } } }
State.ItemSpecCache = {} :: { [string]: { [string]: any }? }

State.SecondsPerFullDayCached = TimeScale.GetSecondsPerFullDay()

function State.getNeeds()
	return NeedConfig.Needs
end

function State.refreshTimeScaleCaches()
	State.SecondsPerFullDayCached = TimeScale.GetSecondsPerFullDay()
end

function State.setNextEvaluation(resident: ResidentState, when: number)
	State.ResidentNextEvaluation[resident] = when
end

function State.clearNextEvaluation(resident: ResidentState)
	State.ResidentNextEvaluation[resident] = nil
end

function State.getNextEvaluation(resident: ResidentState): number?
	return State.ResidentNextEvaluation[resident]
end

function State.setPending(resident: ResidentState, value: string?)
	-- Kept for compatibility with StationManager/ActionQueue if they use it
	-- But ideally we should move away from this if not needed
end

return State
