--!strict
-- ServerScriptService/Server/Services/WorldEventService.lua

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WorldEventPackets = require(ReplicatedStorage.Network.WorldEventPackets)

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
		Id = "community_festival",
		Name = "Community Festival",
		Description = "Residents celebrate together, unlocking unique décor rewards in the shop.",
		Kind = "Celebration",
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

local function buildStateSnapshot(): { [string]: any }
	ensureRotation()
	return {
		RotationId = currentRotation.Id,
		RotationEndsAt = currentRotation.EndsAt,
		ActiveEvents = table.clone(currentRotation.Events),
	}
end

local function sendSnapshotToPlayer(player: Player)
	WorldEventPackets.StateSnapshot:FireClient(player, buildStateSnapshot())
end

function WorldEventService.Init()
	ensureRotation()
	WorldEventPackets.RequestState.OnServerInvoke = function(_player: Player)
		return true, buildStateSnapshot()
	end
	Players.PlayerAdded:Connect(sendSnapshotToPlayer)
	for _, player in ipairs(Players:GetPlayers()) do
		sendSnapshotToPlayer(player)
	end
end

function WorldEventService.GetStateSnapshot(_player: Player)
	return buildStateSnapshot()
end

return WorldEventService
