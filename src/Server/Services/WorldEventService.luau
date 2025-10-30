--!strict
-- ServerScriptService/Server/Services/WorldEventService.lua

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local PlayerSession = require(ServerScriptService.Server.Services.PlayerSession)
local WorldEventPackets = require(ReplicatedStorage.Network.WorldEventPackets)

export type CareerBoostOptions = {
	Amount: number,
	DurationSeconds: number,
	SourceId: string?,
	Description: string?,
}

local WorldEventService = {}

local ROTATION_DURATION_SECONDS = 2 * 60 * 60

export type RotationEvent = {
	Id: string,
	Name: string,
	Description: string,
	Kind: string,
	StartsAt: number,
	EndsAt: number,
}

local rotationTemplate: { RotationEvent } = {
	{
		Id = "career_momentum_burst",
		Name = "Momentum Winds",
		Description = "Career payouts gain a temporary burst when residents finish a shift with momentum.",
		Kind = "Boost",
		StartsAt = 0,
		EndsAt = 0,
	},
}

local currentRotation = {
	Id = "placeholder",
	EndsAt = 0,
	Events = {} :: { RotationEvent },
}

local function deepCopyRotationEvents(): { RotationEvent }
	local now = os.time()
	local endsAt = now + ROTATION_DURATION_SECONDS
	local events: { RotationEvent } = {}
	for index, eventDefinition in ipairs(rotationTemplate) do
		events[index] = {
			Id = eventDefinition.Id,
			Name = eventDefinition.Name,
			Description = eventDefinition.Description,
			Kind = eventDefinition.Kind,
			StartsAt = now,
			EndsAt = endsAt,
		}
	end
	return events
end

local function ensureRotation()
	if currentRotation.EndsAt <= os.time() or #currentRotation.Events == 0 then
		currentRotation.Events = deepCopyRotationEvents()
		currentRotation.EndsAt = os.time() + ROTATION_DURATION_SECONDS
		currentRotation.Id = string.format("rotation_%d", currentRotation.EndsAt)
	end
end

type CareerBoostState = {
	Amount: number,
	ExpiresAt: number,
	SourceId: string,
	Description: string,
}

type PlayerWorldEventState = {
	CareerBoost: CareerBoostState,
}

local function ensureCareerBoostState(boost: any): CareerBoostState
	if typeof(boost) ~= "table" then
		return {
			Amount = 0,
			ExpiresAt = 0,
			SourceId = "",
			Description = "",
		}
	end
	local amount = tonumber(boost.Amount) or 0
	local expiresAt = tonumber(boost.ExpiresAt) or 0
	local sourceId = if typeof(boost.SourceId) == "string" then boost.SourceId else ""
	local description = if typeof(boost.Description) == "string" then boost.Description else ""
	return {
		Amount = amount,
		ExpiresAt = expiresAt,
		SourceId = sourceId,
		Description = description,
	}
end

local function ensurePlayerState(player: Player): PlayerWorldEventState?
	local state = PlayerSession.GetDataAwait(player, "WorldEventState")
	if state == nil then
		return nil
	end
	local boost = ensureCareerBoostState(state.CareerBoost)
	state.CareerBoost = boost
	return state :: PlayerWorldEventState
end

local function buildCareerBoostPayload(boost: CareerBoostState): { [string]: any }
	local now = os.time()
	local active = boost.Amount > 0 and boost.ExpiresAt > now
	if not active and (boost.Amount ~= 0 or boost.ExpiresAt ~= 0) then
		boost.Amount = 0
		boost.ExpiresAt = 0
		boost.SourceId = ""
		boost.Description = ""
	end
	return {
		Amount = boost.Amount,
		ExpiresAt = boost.ExpiresAt,
		SourceId = boost.SourceId,
		Description = boost.Description,
		Active = active,
	}
end

local function buildStateSnapshot(player: Player): { [string]: any }?
	local state = ensurePlayerState(player)
	if not state then
		return nil
	end
	ensureRotation()
	return {
		RotationId = currentRotation.Id,
		RotationEndsAt = currentRotation.EndsAt,
		ActiveEvents = table.clone(currentRotation.Events),
		CareerBoost = buildCareerBoostPayload(state.CareerBoost),
	}
end

local function sendSnapshotToPlayer(player: Player)
	local payload = buildStateSnapshot(player)
	if not payload then
		return
	end
	WorldEventPackets.StateSnapshot:FireClient(player, payload)
end

local function onPlayerAdded(player: Player)
	sendSnapshotToPlayer(player)
end

local function onPlayerRemoving(_player: Player)
	-- Currently no runtime state to clean up
end

function WorldEventService.Init()
	ensureRotation()
	WorldEventPackets.RequestState.OnServerInvoke = function(player: Player)
		local payload = buildStateSnapshot(player)
		if not payload then
			return false,
				{
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
		end
		return true, payload
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in ipairs(Players:GetPlayers()) do
		onPlayerAdded(player)
	end
end

local function updateBoost(state: PlayerWorldEventState, options: CareerBoostOptions): CareerBoostState
	local now = os.time()
	local duration = math.max(0, options.DurationSeconds)
	local expiresAt = if duration > 0 then now + duration else now
	state.CareerBoost.Amount = math.max(0, options.Amount)
	state.CareerBoost.ExpiresAt = expiresAt
	state.CareerBoost.SourceId = options.SourceId or "world_event"
	state.CareerBoost.Description = options.Description or ""
	return state.CareerBoost
end

function WorldEventService.ApplyCareerBoost(player: Player, options: CareerBoostOptions): boolean
	assert(typeof(player) == "Instance" and player:IsA("Player"), "Invalid player instance")
	assert(typeof(options) == "table", "Career boost options must be a table")
	local state = ensurePlayerState(player)
	if not state then
		return false
	end
	local boost = updateBoost(state, options)
	WorldEventPackets.CareerBoostGranted:FireClient(player, buildCareerBoostPayload(boost))
	return true
end

function WorldEventService.ConsumeCareerBoost(player: Player): (number, boolean)
	local state = ensurePlayerState(player)
	if not state then
		return 1, false
	end
	local boost = state.CareerBoost
	local now = os.time()
	if boost.Amount > 0 and boost.ExpiresAt > now then
		local multiplier = 1 + boost.Amount
		local sourceId = boost.SourceId
		local description = boost.Description
		boost.Amount = 0
		boost.ExpiresAt = 0
		boost.SourceId = ""
		boost.Description = ""
		WorldEventPackets.CareerBoostConsumed:FireClient(player, {
			SourceId = sourceId,
			Description = description,
		})
		return multiplier, true
	end
	if boost.Amount > 0 then
		boost.Amount = 0
	end
	if boost.ExpiresAt > 0 and boost.ExpiresAt <= now then
		local sourceId = boost.SourceId
		local description = boost.Description
		boost.ExpiresAt = 0
		boost.SourceId = ""
		boost.Description = ""
		WorldEventPackets.CareerBoostExpired:FireClient(player, {
			SourceId = sourceId,
			Description = description,
		})
	end
	return 1, false
end

function WorldEventService.GetStateSnapshot(player: Player)
	return buildStateSnapshot(player)
end

return WorldEventService
