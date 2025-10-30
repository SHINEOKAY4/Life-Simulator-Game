--!strict
-- StarterPlayerScripts/Client/Modules/WorldEventController.lua

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local WorldEventPackets = require(ReplicatedStorage.Network.WorldEventPackets)
local GoodSignal = require(ReplicatedStorage.Packages.GoodSignal)

export type CareerBoostState = {
	Amount: number,
	ExpiresAt: number,
	SourceId: string,
	Description: string,
	Active: boolean,
}

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
	CareerBoost: CareerBoostState,
}

local DEFAULT_STATE: WorldEventState = {
	RotationId = "",
	RotationEndsAt = 0,
	ActiveEvents = {},
	CareerBoost = {
		Amount = 0,
		ExpiresAt = 0,
		SourceId = "",
		Description = "",
		Active = false,
	},
}

local currentState: WorldEventState = table.clone(DEFAULT_STATE)
currentState.ActiveEvents = {}
currentState.CareerBoost = table.clone(DEFAULT_STATE.CareerBoost)
local WorldEventController = {}

WorldEventController.StateChanged = GoodSignal.new()
WorldEventController.CareerBoostChanged = GoodSignal.new()

local function shallowCopyState(state: WorldEventState): WorldEventState
	return {
		RotationId = state.RotationId,
		RotationEndsAt = state.RotationEndsAt,
		ActiveEvents = table.clone(state.ActiveEvents),
		CareerBoost = {
			Amount = state.CareerBoost.Amount,
			ExpiresAt = state.CareerBoost.ExpiresAt,
			SourceId = state.CareerBoost.SourceId,
			Description = state.CareerBoost.Description,
			Active = state.CareerBoost.Active,
		},
	}
end

local function applyCareerBoost(payload: CareerBoostState)
	currentState.CareerBoost = {
		Amount = payload.Amount or 0,
		ExpiresAt = payload.ExpiresAt or 0,
		SourceId = payload.SourceId or "",
		Description = payload.Description or "",
		Active = payload.Active == true,
	}
	WorldEventController.CareerBoostChanged:Fire(table.clone(currentState.CareerBoost))
end

local function applyState(payload: WorldEventState)
	currentState.RotationId = payload.RotationId or ""
	currentState.RotationEndsAt = payload.RotationEndsAt or 0
	currentState.ActiveEvents = table.clone(payload.ActiveEvents or {})
	applyCareerBoost(payload.CareerBoost or DEFAULT_STATE.CareerBoost)
	WorldEventController.StateChanged:Fire(shallowCopyState(currentState))
end

local function handleStateSnapshot(payload)
	if typeof(payload) ~= "table" then
		return
	end
	applyState(payload :: WorldEventState)
end

local function handleBoostUpdate(payload)
	if typeof(payload) ~= "table" then
		return
	end
	applyCareerBoost(payload :: CareerBoostState)
end

function WorldEventController.GetState(): WorldEventState
	return shallowCopyState(currentState)
end

function WorldEventController.GetCareerBoost(): CareerBoostState
	return table.clone(currentState.CareerBoost)
end

function WorldEventController.Init()
	WorldEventPackets.StateSnapshot.OnClientEvent:Connect(handleStateSnapshot)
	WorldEventPackets.CareerBoostGranted.OnClientEvent:Connect(handleBoostUpdate)
	WorldEventPackets.CareerBoostExpired.OnClientEvent:Connect(handleBoostUpdate)
	WorldEventPackets.CareerBoostConsumed.OnClientEvent:Connect(handleBoostUpdate)

	task.defer(function()
		local success, payload = WorldEventPackets.RequestState:Fire()
		if success and typeof(payload) == "table" then
			handleStateSnapshot(payload)
		end
	end)
end

return WorldEventController
