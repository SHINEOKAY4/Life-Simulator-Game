-- WorldEventService: manages rotating world events picked from WorldEventDefinitions.
-- Each rotation cycle selects one event at random (avoiding back-to-back repeats).
-- Exposes buff query API so other services can apply event multipliers.
-- Works both in Roblox runtime and in Busted tests loaded via loadfile().

local function hasRobloxRuntime()
	if type(game) ~= "userdata" and type(game) ~= "table" then
		return false
	end
	return pcall(function()
		return game:GetService("Players")
	end)
end

local IS_ROBLOX = hasRobloxRuntime()
local Players = nil
local WorldEventPackets = nil
local WorldEventDefinitions = nil

if IS_ROBLOX then
	Players = game:GetService("Players")
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	WorldEventPackets = require(ReplicatedStorage.Network.WorldEventPackets)
	WorldEventDefinitions = require(ReplicatedStorage.Shared.Definitions.WorldEventDefinitions)
else
	-- In test environment, load definitions via loadfile
	WorldEventDefinitions = assert(loadfile("src/Shared/Definitions/WorldEventDefinitions.luau"))()
end

local WorldEventService = {}

local ROTATION_DURATION_SECONDS = 2 * 60 * 60 -- 2 hours per event cycle

-- Injectable clock for tests
local clockFn = os.time

-- RotationEvent shape:
--   Id: string, Name: string, Description: string, Kind: string,
--   StartsAt: number, EndsAt: number, Buffs: { { Type, Value, Label } }

local currentRotation = {
	Id = "placeholder",
	EndsAt = 0,
	Events = {},
	LastEventId = "", -- track last picked event to avoid repeats
}

-- RNG for event selection
local rngFn = math.random

-- Pick one event from the pool, avoiding the last-picked event when possible.
local function pickNextEvent()
	local pool = WorldEventDefinitions.EventPool
	local count = #pool
	if count == 0 then
		error("WorldEventDefinitions.EventPool is empty")
	end
	if count == 1 then
		return pool[1]
	end

	-- Build a candidate list excluding last event
	local candidates = {}
	for _, def in ipairs(pool) do
		if def.Id ~= currentRotation.LastEventId then
			candidates[#candidates + 1] = def
		end
	end

	-- Fallback: if somehow all filtered out, use full pool
	if #candidates == 0 then
		candidates = pool
	end

	local index = rngFn(1, #candidates)
	return candidates[index]
end

local function buildRotationEvent(def, now, endsAt)
	local buffs = {}
	for _, buff in ipairs(def.Buffs) do
		buffs[#buffs + 1] = {
			Type = buff.Type,
			Value = buff.Value,
			Label = buff.Label,
		}
	end
	return {
		Id = def.Id,
		Name = def.Name,
		Description = def.Description,
		Kind = def.Kind,
		StartsAt = now,
		EndsAt = endsAt,
		Buffs = buffs,
	}
end

local function ensureRotation()
	if currentRotation.EndsAt <= clockFn() or #currentRotation.Events == 0 then
		local now = clockFn()
		local endsAt = now + ROTATION_DURATION_SECONDS

		local chosen = pickNextEvent()
		local event = buildRotationEvent(chosen, now, endsAt)

		currentRotation.Events = { event }
		currentRotation.EndsAt = endsAt
		currentRotation.Id = string.format("rotation_%d", endsAt)
		currentRotation.LastEventId = chosen.Id
	end
end

local function buildStateSnapshot()
	ensureRotation()
	local eventsCopy = {}
	for i, event in ipairs(currentRotation.Events) do
		-- Deep copy buffs
		local buffsCopy = {}
		for _, buff in ipairs(event.Buffs) do
			buffsCopy[#buffsCopy + 1] = {
				Type = buff.Type,
				Value = buff.Value,
				Label = buff.Label,
			}
		end
		eventsCopy[i] = {
			Id = event.Id,
			Name = event.Name,
			Description = event.Description,
			Kind = event.Kind,
			StartsAt = event.StartsAt,
			EndsAt = event.EndsAt,
			Buffs = buffsCopy,
		}
	end
	return {
		RotationId = currentRotation.Id,
		RotationEndsAt = currentRotation.EndsAt,
		ActiveEvents = eventsCopy,
	}
end

local function sendSnapshotToPlayer(player)
	if WorldEventPackets then
		WorldEventPackets.StateSnapshot:FireClient(player, buildStateSnapshot())
	end
end

local function broadcastSnapshot()
	if not Players then
		return
	end
	local snapshot = buildStateSnapshot()
	for _, player in ipairs(Players:GetPlayers()) do
		if WorldEventPackets then
			WorldEventPackets.StateSnapshot:FireClient(player, snapshot)
		end
	end
end

function WorldEventService.Init()
	ensureRotation()
	if IS_ROBLOX and WorldEventPackets then
		WorldEventPackets.RequestState.OnServerInvoke = function(_player)
			return true, buildStateSnapshot()
		end
		Players.PlayerAdded:Connect(sendSnapshotToPlayer)
		for _, player in ipairs(Players:GetPlayers()) do
			sendSnapshotToPlayer(player)
		end

		-- Periodic check: rotate events when the current cycle expires.
		task.defer(function()
			while true do
				task.wait(30)
				local now = clockFn()
				if currentRotation.EndsAt <= now then
					ensureRotation()
					broadcastSnapshot()
				end
			end
		end)
	end
end

function WorldEventService.GetStateSnapshot(_player)
	return buildStateSnapshot()
end

--[=[
	Get the active world-event buff multiplier for a given buff type.
	Returns 1.0 if no matching buff is currently active.

	@param buffType string -- "XPMultiplier", "CashMultiplier", "CraftSpeedMultiplier", "ChoreRewardMultiplier", "TipMultiplier"
	@return number -- The multiplier value (1.0 = no buff)
]=]
function WorldEventService.GetBuffMultiplier(buffType)
	if type(buffType) ~= "string" then
		return 1.0
	end
	ensureRotation()
	for _, event in ipairs(currentRotation.Events) do
		for _, buff in ipairs(event.Buffs) do
			if buff.Type == buffType then
				return buff.Value
			end
		end
	end
	return 1.0
end

--[=[
	Get all active buff entries for the current rotation.
	@return { { Type: string, Value: number, Label: string } }
]=]
function WorldEventService.GetActiveBuffs()
	ensureRotation()
	local buffs = {}
	for _, event in ipairs(currentRotation.Events) do
		for _, buff in ipairs(event.Buffs) do
			buffs[#buffs + 1] = {
				Type = buff.Type,
				Value = buff.Value,
				Label = buff.Label,
			}
		end
	end
	return buffs
end

--[=[
	Get the currently active event definition, or nil if none.
	@return RotationEvent?
]=]
function WorldEventService.GetActiveEvent()
	ensureRotation()
	if #currentRotation.Events > 0 then
		return currentRotation.Events[1]
	end
	return nil
end

-- ============ Test helpers (not used in production) ============

function WorldEventService._ResetForTests()
	currentRotation.Id = "placeholder"
	currentRotation.EndsAt = 0
	currentRotation.Events = {}
	currentRotation.LastEventId = ""
	clockFn = os.time
	rngFn = math.random
end

function WorldEventService._SetClock(fn)
	if fn then
		clockFn = fn
	else
		clockFn = os.time
	end
end

function WorldEventService._SetRng(fn)
	if fn then
		rngFn = fn
	else
		rngFn = math.random
	end
end

function WorldEventService._ForceExpire()
	currentRotation.EndsAt = 0
end

function WorldEventService._GetLastEventId()
	return currentRotation.LastEventId
end

function WorldEventService._GetRotationDuration()
	return ROTATION_DURATION_SECONDS
end

return WorldEventService
