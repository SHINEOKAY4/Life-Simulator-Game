--!strict
-- StarterPlayerScripts/Client/Modules/WorldEventController.lua

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local WorldEventPackets = require(ReplicatedStorage.Network.WorldEventPackets)
local GoodSignal = require(ReplicatedStorage.Packages.GoodSignal)

export type RotationEvent = {
	Id: string,
	Name: string,
	Description: string,
	Kind: string,
	StartsAt: number,
	EndsAt: number,
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

local function shallowCopyState(state: WorldEventState): WorldEventState
	return {
		RotationId = state.RotationId,
		RotationEndsAt = state.RotationEndsAt,
		ActiveEvents = table.clone(state.ActiveEvents),
	}
end

local function applyState(payload: WorldEventState)
	currentState.RotationId = payload.RotationId or ""
	currentState.RotationEndsAt = payload.RotationEndsAt or 0
	currentState.ActiveEvents = table.clone(payload.ActiveEvents or {})
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
