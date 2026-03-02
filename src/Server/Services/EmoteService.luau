-- EmoteService.luau
-- Manages emote definitions and per-player unlock state.
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
local EmotePackets = nil

if IS_ROBLOX then
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	Players = game:GetService("Players")
	EmotePackets = require(ReplicatedStorage.Network.EmotePackets)
end

local EmoteService = {}

EmoteService.EmoteDefinitions = {
	wave = {
		id = "wave",
		name = "Wave",
		description = "Wave to nearby players.",
	},
	dance = {
		id = "dance",
		name = "Dance",
		description = "Show off your dance moves.",
	},
	laugh = {
		id = "laugh",
		name = "Laugh",
		description = "Laugh out loud.",
	},
	cry = {
		id = "cry",
		name = "Cry",
		description = "Shed a dramatic tear.",
	},
	clap = {
		id = "clap",
		name = "Clap",
		description = "Applaud with enthusiasm.",
	},
}

-- Ordered list of emote ids for consistent UI display
EmoteService.EmoteOrder = { "wave", "dance", "laugh", "cry", "clap" }

local unlockedByPlayer = {}

local function ensureUnlockedSet(playerId)
	if unlockedByPlayer[playerId] == nil then
		unlockedByPlayer[playerId] = {}
	end
	return unlockedByPlayer[playerId]
end

local function isValidPlayerId(playerId)
	return playerId ~= nil
end

function EmoteService.UnlockEmote(playerId, emoteId)
	if not isValidPlayerId(playerId) then
		return false
	end
	if EmoteService.EmoteDefinitions[emoteId] == nil then
		return false
	end

	local emoteSet = ensureUnlockedSet(playerId)
	if emoteSet[emoteId] then
		return false
	end

	emoteSet[emoteId] = true
	return true
end

function EmoteService.GetUnlockedEmotes(playerId)
	local out = {}
	if not isValidPlayerId(playerId) then
		return out
	end

	local emoteSet = unlockedByPlayer[playerId]
	if not emoteSet then
		return out
	end

	for emoteId, _ in pairs(emoteSet) do
		table.insert(out, emoteId)
	end
	table.sort(out)
	return out
end

-- Returns an ordered array of emote definition tables for all emotes unlocked by playerId.
function EmoteService.GetUnlockedEmoteInfos(playerId)
	local unlocked = unlockedByPlayer[playerId]
	local out = {}
	for _, emoteId in ipairs(EmoteService.EmoteOrder) do
		if unlocked and unlocked[emoteId] then
			local def = EmoteService.EmoteDefinitions[emoteId]
			table.insert(out, { id = def.id, name = def.name, description = def.description })
		end
	end
	return out
end

function EmoteService.Init()
	if not IS_ROBLOX then
		return
	end

	-- Unlock all base emotes for every player on join
	local function onPlayerAdded(player)
		local playerId = player.UserId
		for emoteId in pairs(EmoteService.EmoteDefinitions) do
			EmoteService.UnlockEmote(playerId, emoteId)
		end
	end

	for _, player in ipairs(Players:GetPlayers()) do
		onPlayerAdded(player)
	end
	Players.PlayerAdded:Connect(onPlayerAdded)

	Players.PlayerRemoving:Connect(function(player)
		unlockedByPlayer[player.UserId] = nil
	end)

	-- GetEmotes: return ordered list of unlocked emote definitions
	EmotePackets.GetEmotes.OnServerInvoke = function(player)
		local infos = EmoteService.GetUnlockedEmoteInfos(player.UserId)
		return true, infos
	end

	-- PerformEmote: validate and broadcast to all clients
	EmotePackets.PerformEmote.OnServerInvoke = function(player, emoteId)
		if typeof(emoteId) ~= "string" then
			return false, "Invalid emote id"
		end
		if EmoteService.EmoteDefinitions[emoteId] == nil then
			return false, "Unknown emote"
		end
		local unlocked = unlockedByPlayer[player.UserId]
		if not unlocked or not unlocked[emoteId] then
			return false, "Emote not unlocked"
		end

		EmotePackets.EmotePerformed.FireAllClients({
			PlayerId = player.UserId,
			EmoteId = emoteId,
		})

		return true, ""
	end
end

function EmoteService._ResetForTests()
	unlockedByPlayer = {}
end

return EmoteService
