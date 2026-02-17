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

function EmoteService._ResetForTests()
	unlockedByPlayer = {}
end

return EmoteService
