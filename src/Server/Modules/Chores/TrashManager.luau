--!strict
-- Server/Modules/Chores/TrashManager.luau
-- Drives autonomous trash spawning by calling into ChoreService.

local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

local WorldUpdate = require(ServerScriptService.Server.Utilities.WorldUpdate)
local ChoreService = require(ServerScriptService.Server.Services.ChoreService)
local TenantService = require(ServerScriptService.Server.Services.TenantService)

local TrashManager = {}

local RNG = Random.new()
local UPDATE_TASK_NAME = "TrashManager:Roll"
local UPDATE_INTERVAL = 2
local MAX_TRASH_PER_PLOT = 5

local BASE_WEIGHT = 1
local RANDOM_JITTER = 0.35

local PLAYER_SCAN_LIMIT = 4
local PLAYER_STAGGER_MIN = 2
local PLAYER_STAGGER_MAX = 6
local PLAYER_EMPTY_INTERVAL = 45
local PLAYER_FULL_INTERVAL = 25
local PLAYER_NO_CANDIDATE_INTERVAL = 18
local PLAYER_POST_SPAWN_INTERVAL = 12

local LEASE_CACHE_TTL = 30
local LEASE_CACHE_FAIL_RETRY = 10

local TENANT_BASE_INTERVAL = 210
local TENANT_INTERVAL_WEIGHT_SCALE = 28
local TENANT_INTERVAL_JITTER = 18
local TENANT_MIN_INTERVAL = 45
local TENANT_MAX_INTERVAL = 360
local TENANT_FAIL_COOLDOWN = 25

local TRAIT_WEIGHT_MAP: { [string]: number } = {
	CleanFreak = -1.8,
	Slob = 2.4,
	Glutton = 0.6,
	Ascetic = -0.4,
	Karen = 1.0,
	Chill = -0.2,
}

type TenantLease = TenantService.TenantLease

type PlayerTrashState = {
	NextEvaluation: number,
	TenantCooldowns: { [string]: number },
	LeaseCacheExpiry: number,
	CachedLeases: { [string]: TenantLease }?,
}

type Candidate = {
	tenantId: string,
	lease: TenantLease,
	weight: number,
}

local PlayerStates: { [number]: PlayerTrashState } = {}
local PlayerQueue: { Player } = {}
local QueueIndex = 1

local function getTenantName(lease: any): string?
	if typeof(lease) ~= "table" then
		return nil
	end
	local name = lease.TenantName or lease.Name
	if typeof(name) == "string" and name ~= "" then
		return name
	end
	local tenantId = lease.TenantId
	if typeof(tenantId) == "string" and tenantId ~= "" then
		return tenantId
	end
	return nil
end

local function computeWeight(traits: { string }?): number
	local weight = BASE_WEIGHT + RNG:NextNumber(-RANDOM_JITTER, RANDOM_JITTER)
	if not traits then
		return math.max(0, weight)
	end

	for _, traitId in ipairs(traits) do
		if typeof(traitId) ~= "string" then
			continue
		end
		local modifier = TRAIT_WEIGHT_MAP[traitId]
		if modifier then
			weight += modifier
		end
	end

	return math.max(0, weight)
end

local function computeTenantInterval(weight: number): number
	local base = TENANT_BASE_INTERVAL - (weight * TENANT_INTERVAL_WEIGHT_SCALE)
	base += RNG:NextNumber(-TENANT_INTERVAL_JITTER, TENANT_INTERVAL_JITTER)
	return math.clamp(base, TENANT_MIN_INTERVAL, TENANT_MAX_INTERVAL)
end

local function weightedPick(candidates: { Candidate }): Candidate?
	local total = 0
	for _, entry in ipairs(candidates) do
		total += entry.weight
	end
	if total <= 0 then
		return nil
	end
	local roll = RNG:NextNumber(0, total)
	local cursor = 0
	for _, entry in ipairs(candidates) do
		cursor += entry.weight
		if roll <= cursor then
			return entry
		end
	end
	return candidates[#candidates]
end

local function registerPlayer(player: Player)
	local userId = player.UserId
	if PlayerStates[userId] then
		return
	end
	PlayerStates[userId] = {
		NextEvaluation = os.clock() + RNG:NextNumber(PLAYER_STAGGER_MIN, PLAYER_STAGGER_MAX),
		TenantCooldowns = {},
		LeaseCacheExpiry = 0,
		CachedLeases = nil,
	}
	PlayerQueue[#PlayerQueue + 1] = player
end

local function removeFromQueue(player: Player)
	for index = #PlayerQueue, 1, -1 do
		if PlayerQueue[index] == player then
			table.remove(PlayerQueue, index)
			if index < QueueIndex then
				QueueIndex -= 1
			elseif QueueIndex > #PlayerQueue then
				QueueIndex = 1
			end
			break
		end
	end
	if #PlayerQueue == 0 then
		QueueIndex = 1
	end
end

local function unregisterPlayer(player: Player)
	local stateKey = player and player.UserId
	if stateKey then
		PlayerStates[stateKey] = nil
	end
	if player then
		removeFromQueue(player)
	end
end

local function refreshLeases(player: Player, state: PlayerTrashState, nowClock: number): { [string]: TenantLease }?
	if state.LeaseCacheExpiry > nowClock and state.CachedLeases then
		return state.CachedLeases
	end

	local leases = TenantService.GetActiveLeases(player)
	if not leases then
		state.CachedLeases = nil
		state.LeaseCacheExpiry = nowClock + LEASE_CACHE_FAIL_RETRY
		state.TenantCooldowns = {}
		return nil
	end

	state.CachedLeases = leases
	state.LeaseCacheExpiry = nowClock + LEASE_CACHE_TTL
	for tenantId in pairs(state.TenantCooldowns) do
		if not leases[tenantId] then
			state.TenantCooldowns[tenantId] = nil
		end
	end

	return leases
end

local function scheduleNext(state: PlayerTrashState, nowClock: number, minInterval: number, maxInterval: number)
	if maxInterval < minInterval then
		maxInterval = minInterval
	end
	state.NextEvaluation = nowClock + RNG:NextNumber(minInterval, maxInterval)
end

local function evaluatePlayer(player: Player, state: PlayerTrashState, nowClock: number)
	local trashCount = ChoreService.GetTrashCount(player)
	if trashCount >= MAX_TRASH_PER_PLOT then
		scheduleNext(state, nowClock, PLAYER_FULL_INTERVAL, PLAYER_FULL_INTERVAL + 5)
		return
	end

	local leases = refreshLeases(player, state, nowClock)
	if not leases or next(leases) == nil then
		scheduleNext(state, nowClock, PLAYER_EMPTY_INTERVAL, PLAYER_EMPTY_INTERVAL + 10)
		return
	end

	local candidates: { Candidate } = {}
	for tenantId, lease in pairs(leases) do
		if type(tenantId) ~= "string" then
			continue
		end
		local cooldown = state.TenantCooldowns[tenantId]
		if cooldown and cooldown > nowClock then
			continue
		end
		local weight = computeWeight(lease.Traits)
		if weight > 0 then
			candidates[#candidates + 1] = {
				tenantId = tenantId,
				lease = lease,
				weight = weight,
			}
		end
	end

	if #candidates == 0 then
		scheduleNext(state, nowClock, PLAYER_NO_CANDIDATE_INTERVAL, PLAYER_NO_CANDIDATE_INTERVAL + 8)
		return
	end

	local chosen = weightedPick(candidates)
	if not chosen then
		scheduleNext(state, nowClock, PLAYER_NO_CANDIDATE_INTERVAL, PLAYER_NO_CANDIDATE_INTERVAL + 8)
		return
	end

	local tenantName = getTenantName(chosen.lease)
	if not tenantName then
		state.TenantCooldowns[chosen.tenantId] = nowClock + TENANT_FAIL_COOLDOWN
		scheduleNext(state, nowClock, PLAYER_NO_CANDIDATE_INTERVAL, PLAYER_NO_CANDIDATE_INTERVAL + 8)
		return
	end

	local plotIndex = player:GetAttribute("OwnedPlotIndex")
	if typeof(plotIndex) ~= "number" then
		state.TenantCooldowns[chosen.tenantId] = nowClock + TENANT_FAIL_COOLDOWN
		scheduleNext(state, nowClock, PLAYER_NO_CANDIDATE_INTERVAL, PLAYER_NO_CANDIDATE_INTERVAL + 8)
		return
	end

	ChoreService.SpawnMess(player, {
		TenantName = tenantName,
		PlotIndex = plotIndex,
	})

	state.TenantCooldowns[chosen.tenantId] = nowClock + computeTenantInterval(chosen.weight)
	scheduleNext(state, nowClock, PLAYER_POST_SPAWN_INTERVAL, PLAYER_POST_SPAWN_INTERVAL + 6)
end

local function step(nowClock: number)
	if #PlayerQueue == 0 then
		return
	end

	local processed = 0
	local checked = 0
	local total = #PlayerQueue
	while processed < PLAYER_SCAN_LIMIT and checked < total do
		if QueueIndex > #PlayerQueue then
			QueueIndex = 1
			total = #PlayerQueue
			if total == 0 then
				return
			end
		end

		local player = PlayerQueue[QueueIndex]
		QueueIndex += 1
		checked += 1
		if not player or not player.Parent then
			if player then
				unregisterPlayer(player)
			end
			total = #PlayerQueue
			continue
		end

		local state = PlayerStates[player.UserId]
		if state and nowClock >= state.NextEvaluation then
			processed += 1
			evaluatePlayer(player, state, nowClock)
		end
	end
end

function TrashManager._Step()
	step(os.clock())
end

function TrashManager.Start()
	for _, player in ipairs(Players:GetPlayers()) do
		registerPlayer(player)
	end
	Players.PlayerAdded:Connect(registerPlayer)
	Players.PlayerRemoving:Connect(unregisterPlayer)

	WorldUpdate.Subscribe(UPDATE_TASK_NAME, UPDATE_INTERVAL, function()
		TrashManager._Step()
	end)
end

return TrashManager
