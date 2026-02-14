--!strict
-- Server/Services/TenantHelpService.luau
-- Handles timed tenant help requests independently from TenantService.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")
local HttpService = game:GetService("HttpService")

local ProgressionConfig = require(ReplicatedStorage.Shared.Configurations.ProgressionConfig)
local TenantHelpPackets = require(ReplicatedStorage.Network.TenantHelpPackets)
local ProgressionService = require(ServerScriptService.Server.Services.ProgressionService)
local AchievementService = require(ServerScriptService.Server.Services.AchievementService)
local WorldUpdate = require(ServerScriptService.Server.Utilities.WorldUpdate)

local TenantHelpService = {}

export type TenantLease = {
	TenantId: string,
	TenantName: string?,
}

export type Dependencies = {
	GetActiveLeases: (player: Player) -> { [string]: TenantLease }?,
	AddMailboxIncome: (player: Player, amount: number) -> (),
}

local UPDATE_TASK_NAME = "TenantHelpService"
local UPDATE_INTERVAL = 1
local HELP_REQUEST_INTERVAL_MIN = 70
local HELP_REQUEST_INTERVAL_MAX = 140
local HELP_REQUEST_DURATION = 45
local HELP_REQUEST_TIP = 35
local MAX_SIMULTANEOUS_HELP = 1

local HELP_NEEDS: { string } = {
	"Can you help carry in some groceries?",
	"Needs a fast wellness check-in.",
	"Help tighten a loose fixture.",
	"Quick cleanup before guests arrive.",
}

local rng = Random.new()

export type HelpRequest = {
	RequestId: string,
	TenantId: string,
	TenantName: string,
	Need: string,
	ExpiresAt: number,
	RewardXP: number,
	RewardCash: number,
}

export type PlayerHelpState = {
	ActiveRequests: { [string]: HelpRequest },
	NextHelpUnix: number,
}

local dependencies: Dependencies? = nil
local helpStateByUserId: { [number]: PlayerHelpState } = {}

local function serverNow(): number
	return Workspace:GetServerTimeNow()
end

local function resolveHelpReward(): (number, number)
	local rewards = ProgressionConfig.ActionRewards
	local xp = rewards.TenantHelped or 0
	local cash = math.max(0, HELP_REQUEST_TIP)
	return xp, cash
end

local function randomNeed(): string
	if #HELP_NEEDS == 0 then
		return "Needs a quick hand."
	end
	return HELP_NEEDS[rng:NextInteger(1, #HELP_NEEDS)]
end

local function ensureState(player: Player): PlayerHelpState
	local state = helpStateByUserId[player.UserId]
	if not state then
		state = {
			ActiveRequests = {},
			NextHelpUnix = serverNow() + HELP_REQUEST_INTERVAL_MIN,
		}
		helpStateByUserId[player.UserId] = state
	end
	return state
end

local function removeRequest(
	state: PlayerHelpState,
	player: Player,
	requestId: string,
	tenantId: string,
	reason: string
)
	state.ActiveRequests[requestId] = nil
	TenantHelpPackets.HelpRequestRemoved:FireClient(player, {
		RequestId = requestId,
		TenantId = tenantId,
		Reason = reason,
	})
end

local function broadcastHelpSpawn(player: Player, request: HelpRequest)
	TenantHelpPackets.HelpRequestSpawn:FireClient(player, {
		RequestId = request.RequestId,
		TenantId = request.TenantId,
		TenantName = request.TenantName,
		Need = request.Need,
		ExpiresAt = request.ExpiresAt,
		RewardXP = request.RewardXP,
		RewardCash = request.RewardCash,
	})
end

local function cleanupPlayer(player: Player)
	helpStateByUserId[player.UserId] = nil
end

local function trySpawnRequest(player: Player, state: PlayerHelpState)
	if not dependencies then
		return
	end

	local now = serverNow()
	if state.NextHelpUnix > now then
		return
	end

	if next(state.ActiveRequests) ~= nil then
		state.NextHelpUnix = now + HELP_REQUEST_INTERVAL_MIN
		return
	end

	local leases = dependencies.GetActiveLeases(player)
	if not leases or not next(leases) then
		state.NextHelpUnix = now + HELP_REQUEST_INTERVAL_MIN
		return
	end

	local leaseList: { TenantLease } = {}
	for _, lease in pairs(leases) do
		leaseList[#leaseList + 1] = lease
	end

	if #leaseList == 0 then
		state.NextHelpUnix = now + HELP_REQUEST_INTERVAL_MIN
		return
	end

	local activeCount = 0
	for _ in pairs(state.ActiveRequests) do
		activeCount += 1
	end
	if activeCount >= MAX_SIMULTANEOUS_HELP then
		state.NextHelpUnix = now + HELP_REQUEST_INTERVAL_MIN
		return
	end

	local picked = leaseList[rng:NextInteger(1, #leaseList)]
	local xpReward, cashReward = resolveHelpReward()
	local request: HelpRequest = {
		RequestId = HttpService:GenerateGUID(false),
		TenantId = picked.TenantId,
		TenantName = picked.TenantName or "Tenant",
		Need = randomNeed(),
		ExpiresAt = now + HELP_REQUEST_DURATION,
		RewardXP = xpReward,
		RewardCash = cashReward,
	}

	state.ActiveRequests[request.RequestId] = request
	state.NextHelpUnix = now + rng:NextNumber(HELP_REQUEST_INTERVAL_MIN, HELP_REQUEST_INTERVAL_MAX)
	broadcastHelpSpawn(player, request)
end

local function expireRequests(player: Player, state: PlayerHelpState)
	local now = serverNow()
	for id, request in pairs(state.ActiveRequests) do
		if request.ExpiresAt <= now then
			removeRequest(state, player, id, request.TenantId, "Expired")
		end
	end
end

local function stepHelp(_dt: number)
	for _, player in ipairs(Players:GetPlayers()) do
		local state = helpStateByUserId[player.UserId]
		if state then
			expireRequests(player, state)
			trySpawnRequest(player, state)
		end
	end
end

function TenantHelpService.RegisterPlayer(player: Player)
	ensureState(player)
end

function TenantHelpService.UnregisterPlayer(player: Player)
	local state = helpStateByUserId[player.UserId]
	if not state then
		return
	end

	for id, request in pairs(state.ActiveRequests) do
		removeRequest(state, player, id, request.TenantId, "PlayerLeft")
	end
	cleanupPlayer(player)
end

function TenantHelpService.RemoveRequestsForTenant(player: Player, tenantId: string, reason: string)
	local state = helpStateByUserId[player.UserId]
	if not state then
		return
	end

	for id, request in pairs(state.ActiveRequests) do
		if request.TenantId == tenantId then
			removeRequest(state, player, id, tenantId, reason)
		end
	end
end

local function handleHelpInteraction(player: Player, requestId: string): (boolean, string)
	local state = helpStateByUserId[player.UserId]
	if not state then
		return false, "No active tenant requests."
	end

	local request = state.ActiveRequests[requestId]
	if not request then
		return false, "Request expired."
	end

	local now = serverNow()
	if request.ExpiresAt <= now then
		removeRequest(state, player, requestId, request.TenantId, "Expired")
		return false, "Request expired."
	end

	removeRequest(state, player, requestId, request.TenantId, "Completed")
	if dependencies then
		if request.RewardCash > 0 then
			dependencies.AddMailboxIncome(player, request.RewardCash)
		end
	end
	ProgressionService.RecordTenantHelped(player)
	AchievementService.RecordTenantHelpCompleted(player)
	state.NextHelpUnix = now + HELP_REQUEST_INTERVAL_MIN

	return true, string.format("%s appreciated the help!", request.TenantName)
end

function TenantHelpService.Init(providedDependencies: Dependencies)
	dependencies = providedDependencies

	TenantHelpPackets.HelpInteraction.OnServerInvoke = function(player: Player, requestId: string)
		local success, message = handleHelpInteraction(player, requestId)
		return success, message
	end

	WorldUpdate.Subscribe(UPDATE_TASK_NAME, UPDATE_INTERVAL, stepHelp)
end

return TenantHelpService
