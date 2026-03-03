--!strict
-- StarterPlayerScripts/Client/Modules/WorldEventController.lua
-- Receives world event state from the server and exposes it to client UI/modules.
-- Now includes buff data for each active event.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local WorldEventPackets = require(ReplicatedStorage.Network.WorldEventPackets)
local GoodSignal = require(ReplicatedStorage.Packages.GoodSignal)

export type EventBuff = {
	Type: string,
	Value: number,
	Label: string,
}

export type RotationEvent = {
	Id: string,
	Name: string,
	Description: string,
	Kind: string,
	StartsAt: number,
	EndsAt: number,
	Buffs: { EventBuff },
}

export type WorldEventState = {
	RotationId: string,
	RotationEndsAt: number,
	ActiveEvents: { RotationEvent },
}

local DEFAULT_STATE: WorldEventState = {
	RotationId = "",
	RotationEndsAt = 0,
	ActiveEvents = {},
}

local currentState: WorldEventState = table.clone(DEFAULT_STATE)
currentState.ActiveEvents = {}

local WorldEventController = {}

WorldEventController.StateChanged = GoodSignal.new()

local function deepCopyBuffs(buffs: { EventBuff }?): { EventBuff }
	if not buffs then
		return {}
	end
	local copy = {}
	for _, buff in ipairs(buffs) do
		table.insert(copy, {
			Type = buff.Type,
			Value = buff.Value,
			Label = buff.Label,
		})
	end
	return copy
end

local function deepCopyEvents(events: { RotationEvent }): { RotationEvent }
	local copy = {}
	for _, event in ipairs(events) do
		table.insert(copy, {
			Id = event.Id,
			Name = event.Name,
			Description = event.Description,
			Kind = event.Kind,
			StartsAt = event.StartsAt,
			EndsAt = event.EndsAt,
			Buffs = deepCopyBuffs(event.Buffs),
		})
	end
	return copy
end

local function shallowCopyState(state: WorldEventState): WorldEventState
	return {
		RotationId = state.RotationId,
		RotationEndsAt = state.RotationEndsAt,
		ActiveEvents = deepCopyEvents(state.ActiveEvents),
	}
end

local function applyState(payload: WorldEventState)
	currentState.RotationId = payload.RotationId or ""
	currentState.RotationEndsAt = payload.RotationEndsAt or 0
	currentState.ActiveEvents = deepCopyEvents(payload.ActiveEvents or {})
	WorldEventController.StateChanged:Fire(shallowCopyState(currentState))
end

local function handleStateSnapshot(payload)
	if typeof(payload) ~= "table" then
		return
	end
	applyState(payload :: WorldEventState)
end

function WorldEventController.GetState(): WorldEventState
	return shallowCopyState(currentState)
end

--[=[
	Get all active buffs from the current world event(s).
	@return { EventBuff }
]=]
function WorldEventController.GetActiveBuffs(): { EventBuff }
	local buffs = {}
	for _, event in ipairs(currentState.ActiveEvents) do
		if event.Buffs then
			for _, buff in ipairs(event.Buffs) do
				table.insert(buffs, {
					Type = buff.Type,
					Value = buff.Value,
					Label = buff.Label,
				})
			end
		end
	end
	return buffs
end

--[=[
	Get a specific buff multiplier value from the active world event.
	Returns 1.0 if no matching buff is active.
	@param buffType string
	@return number
]=]
function WorldEventController.GetBuffMultiplier(buffType: string): number
	for _, event in ipairs(currentState.ActiveEvents) do
		if event.Buffs then
			for _, buff in ipairs(event.Buffs) do
				if buff.Type == buffType then
					return buff.Value
				end
			end
		end
	end
	return 1.0
end

--[=[
	Get the currently active event, or nil if none.
	@return RotationEvent?
]=]
function WorldEventController.GetActiveEvent(): RotationEvent?
	if #currentState.ActiveEvents > 0 then
		local event = currentState.ActiveEvents[1]
		return {
			Id = event.Id,
			Name = event.Name,
			Description = event.Description,
			Kind = event.Kind,
			StartsAt = event.StartsAt,
			EndsAt = event.EndsAt,
			Buffs = deepCopyBuffs(event.Buffs),
		}
	end
	return nil
end

function WorldEventController.Init()
	WorldEventPackets.StateSnapshot.OnClientEvent:Connect(handleStateSnapshot)

	task.defer(function()
		local success, payload = WorldEventPackets.RequestState:Fire()
		if success and typeof(payload) == "table" then
			handleStateSnapshot(payload)
		end
	end)
end

return WorldEventController
