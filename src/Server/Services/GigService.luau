--!strict
-- ServerScriptService/Server/Services/GigService.lua

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local HttpService = game:GetService("HttpService")

local PlayerSession = require(ServerScriptService.Server.Services.PlayerSession)
local CurrencyService = require(ServerScriptService.Server.Services.CurrencyService)
local JobCatalog = require(ReplicatedStorage.Shared.Configurations.JobCatalog)
local GigPackets = require(ReplicatedStorage.Network.GigPackets)

local DAILY_GIG_SLOTS = 3
local RUN_TIMEOUT_SECONDS = 10 * 60
local MOMENTUM_DURATION_SECONDS = 60 * 60
local MOMENTUM_AMOUNT = 0.1

local PERFORMANCE_MULTIPLIERS = {
	Bronze = 0.85,
	Silver = 1,
	Gold = 1.2,
}

local DEFAULT_COOLDOWN_SECONDS = 5 * 60
local DEFAULT_VARIANCE = 2

export type GigTuning = {
	BasePayout: number,
	Variance: number,
	CooldownSeconds: number,
}

type RunInfo = {
	GigId: string,
	StartedAt: number,
	CreatedAt: number,
	Tuning: GigTuning,
}

local GigTuning: { [string]: GigTuning } = {
	CourierSprint = { BasePayout = 28, Variance = 6, CooldownSeconds = 8 * 60 },
	CafePopUp = { BasePayout = 24, Variance = 4, CooldownSeconds = 6 * 60 },
	DebugJam = { BasePayout = 32, Variance = 8, CooldownSeconds = 10 * 60 },
}

local JobsById: { [string]: JobCatalog.JobEntry } = {}
for _, job in JobCatalog.Jobs do
	JobsById[job.Id] = job
end

local activeRuns: { [number]: { [string]: RunInfo } } = {}

local GigService = {}

local function getGigState(player: Player)
	local gigState = PlayerSession.GetDataAwait(player, "GigState")
	if gigState == nil then
		return nil, "Gig data unavailable."
	end
	if typeof(gigState.Cooldowns) ~= "table" then
		gigState.Cooldowns = {}
	end
	if typeof(gigState.MomentumBoost) ~= "table" then
		gigState.MomentumBoost = { Amount = 0, ExpiresAt = 0 }
	end
	if typeof(gigState.SlotsUsedToday) ~= "number" then
		gigState.SlotsUsedToday = 0
	end
	local today = os.date("!*t").yday
	if gigState.LastRefreshDay ~= today then
		gigState.LastRefreshDay = today
		gigState.SlotsUsedToday = 0
		gigState.Cooldowns = {}
	end
	local now = os.time()
	for gigId, expiresAt in pairs(gigState.Cooldowns) do
		if typeof(expiresAt) ~= "number" or expiresAt <= now then
			gigState.Cooldowns[gigId] = nil
		end
	end
	return gigState, nil
end

local function getGigTuning(gigId: string): GigTuning
	local tuning = GigTuning[gigId]
	if tuning then
		return tuning
	end
	local catalogEntry = JobsById[gigId]
	if catalogEntry ~= nil then
		return {
			BasePayout = catalogEntry.BasePay,
			Variance = catalogEntry.Variance or DEFAULT_VARIANCE,
			CooldownSeconds = catalogEntry.CooldownSeconds or DEFAULT_COOLDOWN_SECONDS,
		}
	end
	return {
		BasePayout = 20,
		Variance = DEFAULT_VARIANCE,
		CooldownSeconds = DEFAULT_COOLDOWN_SECONDS,
	}
end

local function getPlayerRuns(player: Player)
	local userId = player.UserId
	local runs = activeRuns[userId]
	if not runs then
		runs = {}
		activeRuns[userId] = runs
	end
	return runs
end

local function cleanupRun(player: Player, runId: string)
	local runs = activeRuns[player.UserId]
	if runs then
		runs[runId] = nil
		if next(runs) == nil then
			activeRuns[player.UserId] = nil
		end
	end
end

local function computePayout(tuning: GigTuning, tier: string): number
	local variance = tuning.Variance or 0
	local randomOffset = 0
	if variance > 0 then
		randomOffset = math.random(-variance, variance)
	end
	local base = tuning.BasePayout + randomOffset
	if base < 0 then
		base = 0
	end
	local multiplier = PERFORMANCE_MULTIPLIERS[tier] or PERFORMANCE_MULTIPLIERS.Silver
	local payout = math.floor(base * multiplier)
	if payout < 0 then
		payout = 0
	end
	return payout
end

function GigService.RequestStart(player: Player, gigId: string): (boolean, string, string?)
	local jobEntry = JobsById[gigId]
	if jobEntry == nil or jobEntry.Type ~= "Gig" then
		return false, "Gig not available.", nil
	end
	local gigState, gigStateError = getGigState(player)
	if gigState == nil then
		return false, gigStateError or "Unable to fetch gig state.", nil
	end
	if gigState.SlotsUsedToday >= DAILY_GIG_SLOTS then
		return false, "No gig slots remaining today.", nil
	end
	local now = os.time()
	local tuning = getGigTuning(gigId)
	local cooldownExpiry = gigState.Cooldowns[gigId]
	if typeof(cooldownExpiry) == "number" and cooldownExpiry > now then
		local remaining = cooldownExpiry - now
		return false, string.format("%s is on cooldown for %d more seconds.", jobEntry.Name, remaining), nil
	end
	gigState.SlotsUsedToday += 1
	gigState.Cooldowns[gigId] = now + (tuning.CooldownSeconds or DEFAULT_COOLDOWN_SECONDS)

	local runId = HttpService:GenerateGUID(false)
	local runs = getPlayerRuns(player)
	runs[runId] = {
		GigId = gigId,
		StartedAt = os.clock(),
		CreatedAt = now,
		Tuning = tuning,
	}
	return true, jobEntry.Name .. " gig started!", runId
end

function GigService.SubmitScore(player: Player, runId: string, tier: string): (boolean, string, number)
	local runs = activeRuns[player.UserId]
	if not runs then
		return false, "No active gigs.", 0
	end
	local runInfo = runs[runId]
	if runInfo == nil then
		return false, "Gig session expired.", 0
	end
	if os.clock() - runInfo.StartedAt > RUN_TIMEOUT_SECONDS then
		cleanupRun(player, runId)
		return false, "Gig session timed out.", 0
	end
	local gigState, gigStateError = getGigState(player)
	if gigState == nil then
		cleanupRun(player, runId)
		return false, gigStateError or "Unable to resolve gig state.", 0
	end
	local tuning = runInfo.Tuning
	local payout = computePayout(tuning, tier)
	local currencyState = PlayerSession.GetDataAwait(player, "CurrencyState")
	if currencyState == nil then
		cleanupRun(player, runId)
		return false, "Currency state unavailable.", 0
	end
	CurrencyService.Add(player, "Cash", payout, currencyState)
	gigState.MomentumBoost.Amount = MOMENTUM_AMOUNT
	gigState.MomentumBoost.ExpiresAt = os.time() + MOMENTUM_DURATION_SECONDS
	cleanupRun(player, runId)
	return true, string.format("Earned $%d", payout), payout
end

function GigService.Init()
	GigPackets.RequestStart.OnServerInvoke = function(player: Player, gigId: string)
		local ok, message, runId = GigService.RequestStart(player, gigId)
		return ok, message, runId or ""
	end
	GigPackets.SubmitScore.OnServerInvoke = function(player: Player, runId: string, tier: string)
		local ok, message, payout = GigService.SubmitScore(player, runId, tier)
		return ok, message, payout
	end
	Players.PlayerRemoving:Connect(function(player)
		activeRuns[player.UserId] = nil
	end)
end

return GigService
