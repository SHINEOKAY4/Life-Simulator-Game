--!strict
-- Tracks per-player energy consumption based on station load adjustments.

local Workspace = game:GetService("Workspace")
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerSession = require(ServerScriptService.Server.Services.PlayerSession)
local TimeScale = require(ReplicatedStorage.Shared.Utilities.TimeScale)

export type EnergyState = {
	BaseLoad: number,
	ActiveLoad: number,
	AccumulatedEnergy: number,
	LastTimestamp: number,
	OutageActive: boolean,
}

local DEFAULT_STATE: EnergyState = {
	BaseLoad = 0,
	ActiveLoad = 0,
	AccumulatedEnergy = 0,
	LastTimestamp = 0,
	OutageActive = false,
}

local playerStates: { [number]: EnergyState } = {}

local function cloneState(state: EnergyState): EnergyState
	return {
		BaseLoad = state.BaseLoad,
		ActiveLoad = state.ActiveLoad,
		AccumulatedEnergy = state.AccumulatedEnergy,
		LastTimestamp = state.LastTimestamp,
		OutageActive = state.OutageActive,
	}
end

local function resolveNow(): number
	return Workspace:GetServerTimeNow()
end

local function getEnergyDataTable(player: Player): EnergyState?
	local data = PlayerSession.TryGetData(player, "EnergyState")
	if typeof(data) ~= "table" then
		return nil
	end

	local cast = data :: any
	cast.BaseLoad = typeof(cast.BaseLoad) == "number" and cast.BaseLoad or 0
	cast.ActiveLoad = typeof(cast.ActiveLoad) == "number" and cast.ActiveLoad or 0
	cast.AccumulatedEnergy = typeof(cast.AccumulatedEnergy) == "number" and cast.AccumulatedEnergy or 0
	cast.LastTimestamp = typeof(cast.LastTimestamp) == "number" and cast.LastTimestamp or 0
	cast.OutageActive = cast.OutageActive == true
	return cast
end

local function persistState(player: Player, state: EnergyState)
	local data = getEnergyDataTable(player)
	if data then
		data.BaseLoad = state.BaseLoad
		data.ActiveLoad = state.ActiveLoad
		data.AccumulatedEnergy = state.AccumulatedEnergy
		data.LastTimestamp = state.LastTimestamp
		data.OutageActive = state.OutageActive
	end
end

local function ensureState(player: Player): EnergyState
	local existing = playerStates[player.UserId]
	if existing then
		return existing
	end

	local persistent = getEnergyDataTable(player)
	local state: EnergyState
	if persistent then
		state = {
			BaseLoad = math.max(0, math.round(persistent.BaseLoad)),
			ActiveLoad = math.max(0, math.round(persistent.ActiveLoad)),
			AccumulatedEnergy = math.max(0, persistent.AccumulatedEnergy),
			LastTimestamp = persistent.LastTimestamp,
			OutageActive = persistent.OutageActive,
		}
	else
		state = cloneState(DEFAULT_STATE)
	end

	if state.LastTimestamp <= 0 then
		state.LastTimestamp = resolveNow()
	end

	playerStates[player.UserId] = state
	persistState(player, state)
	return state
end

local function integrate(state: EnergyState, now: number)
	local elapsed = now - state.LastTimestamp
	if elapsed > 0 then
		local load = state.ActiveLoad
		if load > 0 then
			local gameHours = TimeScale.GameHoursFromRealDelta(elapsed)
			if gameHours > 0 then
				state.AccumulatedEnergy += load * gameHours
			end
		end
		state.LastTimestamp = now
	elseif elapsed < 0 then
		state.LastTimestamp = now
	end
end

local EnergyUsageTracker = {}

function EnergyUsageTracker.SyncBaseLoad(player: Player, totalLoad: number)
	local state = ensureState(player)
	local now = resolveNow()
	integrate(state, now)

	state.BaseLoad = math.max(0, totalLoad)
	if state.OutageActive then
		state.ActiveLoad = 0
	else
		state.ActiveLoad = state.BaseLoad
	end

	persistState(player, state)
end

function EnergyUsageTracker.AdjustStationLoad(player: Player, deltaLoad: number)
	if deltaLoad == 0 then
		return
	end

	local state = ensureState(player)
	local now = resolveNow()
	integrate(state, now)

	state.BaseLoad += deltaLoad
	if state.BaseLoad < 0 then
		state.BaseLoad = 0
	end

	if state.OutageActive then
		state.ActiveLoad = 0
	else
		state.ActiveLoad += deltaLoad
		if state.ActiveLoad < 0 then
			state.ActiveLoad = 0
		end
	end

	persistState(player, state)
end

function EnergyUsageTracker.SetOutage(player: Player, isActive: boolean)
	local state = ensureState(player)
	if state.OutageActive == isActive then
		return
	end

	local now = resolveNow()
	integrate(state, now)

	state.OutageActive = isActive
	if isActive then
		state.ActiveLoad = 0
	else
		state.ActiveLoad = state.BaseLoad
	end

	persistState(player, state)
end

function EnergyUsageTracker.CollectUsage(player: Player): number
	local state = ensureState(player)
	local now = resolveNow()
	integrate(state, now)

	local consumed = state.AccumulatedEnergy
	state.AccumulatedEnergy = 0

	persistState(player, state)
	return consumed
end

function EnergyUsageTracker.ResetAccumulated(player: Player)
	local state = ensureState(player)
	state.AccumulatedEnergy = 0
	state.LastTimestamp = resolveNow()
	persistState(player, state)
end

function EnergyUsageTracker.RemovePlayer(player: Player)
	local state = playerStates[player.UserId]
	local now = resolveNow()
	if state then
		integrate(state, now)
		state.LastTimestamp = now
		state.ActiveLoad = 0
		persistState(player, state)
		playerStates[player.UserId] = nil
	else
		local data = getEnergyDataTable(player)
		if data then
			data.LastTimestamp = now
			data.ActiveLoad = 0
		end
	end
end

function EnergyUsageTracker.GetActiveLoad(player: Player): number
	local state = ensureState(player)
	return state.ActiveLoad
end

function EnergyUsageTracker.GetBaseLoad(player: Player): number
	local state = ensureState(player)
	return state.BaseLoad
end

return EnergyUsageTracker
