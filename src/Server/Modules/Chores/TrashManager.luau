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
local UPDATE_INTERVAL = 8
local MAX_TRASH_PER_PLOT = 5

local BASE_WEIGHT = 1
local RANDOM_JITTER = 0.35

local TRAIT_WEIGHT_MAP: { [string]: number } = {
	CleanFreak = -1.8,
	Slob = 2.4,
	Glutton = 0.6,
	Ascetic = -0.4,
	Karen = 1.0,
	Chill = -0.2,
}

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

local function rollTrashCandidate(): (Player?, any)
	local weighted = {}
	for _, player in ipairs(Players:GetPlayers()) do
		if ChoreService.GetTrashCount(player) >= MAX_TRASH_PER_PLOT then
			continue
		end
		local leases = TenantService.GetActiveLeases(player)
		if not leases then
			continue
		end
		for _, lease in pairs(leases) do
			local weight = computeWeight(lease.Traits)
			if weight > 0 then
				weighted[#weighted + 1] = {
					player = player,
					lease = lease,
					weight = weight,
				}
			end
		end
	end

	if #weighted == 0 then
		return nil, nil
	end

	local total = 0
	for _, entry in ipairs(weighted) do
		total += entry.weight
	end
	local roll = RNG:NextNumber(0, math.max(total, 0.001))
	local cursor = 0
	for _, entry in ipairs(weighted) do
		cursor += entry.weight
		if roll <= cursor then
			return entry.player, entry.lease
		end
	end

	local fallback = weighted[#weighted]
	return fallback.player, fallback.lease
end

function TrashManager._Step()
	local player, tenantData = rollTrashCandidate()
	if player and tenantData then
		local tenantName = getTenantName(tenantData)
		if not tenantName then
			return
		end
		local plotIndex = player:GetAttribute("OwnedPlotIndex")
		if typeof(plotIndex) ~= "number" then
			return
		end
		ChoreService.SpawnMess(player, {
			TenantName = tenantName,
			PlotIndex = plotIndex,
		})
	end
end

function TrashManager.Start()
	WorldUpdate.Subscribe(UPDATE_TASK_NAME, UPDATE_INTERVAL, function()
		TrashManager._Step()
	end)
end

return TrashManager
