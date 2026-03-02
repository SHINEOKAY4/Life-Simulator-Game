-- Tests/Specs/EmoteSpec.lua
-- Structural + behavioral tests for the emote system.
-- Covers EmotePackets, EmoteService logic, EmoteUI structure, and integration wiring.

local function readFile(path)
	local file = assert(io.open(path, "r"), "missing file: " .. path)
	local contents = file:read("*a")
	file:close()
	return contents
end

-- ── EmoteService behavioral logic (direct loadfile) ──────────────────────────

local EmoteService = assert(loadfile("src/Server/Services/EmoteService.luau"))()

describe("EmoteService", function()
	before_each(function()
		EmoteService._ResetForTests()
	end)

	it("should include at least five basic emote definitions", function()
		local defs = EmoteService.EmoteDefinitions
		assert.is.truthy(defs.wave)
		assert.is.truthy(defs.dance)
		assert.is.truthy(defs.laugh)
		assert.is.truthy(defs.cry)
		assert.is.truthy(defs.clap)
	end)

	it("should unlock a valid emote", function()
		local unlocked = EmoteService.UnlockEmote(1, "wave")
		assert.is_true(unlocked)
		assert.same({ "wave" }, EmoteService.GetUnlockedEmotes(1))
	end)

	it("should reject unknown emote ids", function()
		assert.is_false(EmoteService.UnlockEmote(1, "moonwalk"))
	end)

	it("should reject nil player id", function()
		assert.is_false(EmoteService.UnlockEmote(nil, "wave"))
	end)

	it("should not unlock the same emote twice", function()
		assert.is_true(EmoteService.UnlockEmote(2, "dance"))
		assert.is_false(EmoteService.UnlockEmote(2, "dance"))
	end)

	it("should return empty table for player with no unlocked emotes", function()
		assert.same({}, EmoteService.GetUnlockedEmotes(999))
	end)

	it("should return sorted unlocked emotes", function()
		assert.is_true(EmoteService.UnlockEmote(3, "wave"))
		assert.is_true(EmoteService.UnlockEmote(3, "clap"))
		assert.is_true(EmoteService.UnlockEmote(3, "cry"))

		assert.same({ "clap", "cry", "wave" }, EmoteService.GetUnlockedEmotes(3))
	end)

	it("should isolate unlock state by player", function()
		assert.is_true(EmoteService.UnlockEmote(11, "laugh"))
		assert.is_true(EmoteService.UnlockEmote(12, "dance"))

		assert.same({ "laugh" }, EmoteService.GetUnlockedEmotes(11))
		assert.same({ "dance" }, EmoteService.GetUnlockedEmotes(12))
	end)

	it("EmoteDefinitions has exactly 5 entries", function()
		local count = 0
		for _ in pairs(EmoteService.EmoteDefinitions) do
			count = count + 1
		end
		assert.are.equal(5, count)
	end)

	it("each EmoteDefinition has id, name, and description fields", function()
		for emoteId, def in pairs(EmoteService.EmoteDefinitions) do
			assert.are.equal(emoteId, def.id)
			assert.is_truthy(def.name and #def.name > 0)
			assert.is_truthy(def.description and #def.description > 0)
		end
	end)

	it("GetUnlockedEmoteInfos returns empty for player with no unlocks", function()
		local infos = EmoteService.GetUnlockedEmoteInfos(42)
		assert.are.equal(0, #infos)
	end)

	it("GetUnlockedEmoteInfos returns tables with id/name/description", function()
		EmoteService.UnlockEmote(7, "wave")
		local infos = EmoteService.GetUnlockedEmoteInfos(7)
		assert.are.equal(1, #infos)
		assert.are.equal("wave", infos[1].id)
		assert.is_truthy(infos[1].name)
		assert.is_truthy(infos[1].description)
	end)

	it("GetUnlockedEmoteInfos respects EmoteOrder ordering", function()
		EmoteService.UnlockEmote(5, "clap")
		EmoteService.UnlockEmote(5, "dance")
		EmoteService.UnlockEmote(5, "wave")
		local infos = EmoteService.GetUnlockedEmoteInfos(5)
		assert.are.equal(3, #infos)
		assert.are.equal("wave", infos[1].id)
		assert.are.equal("dance", infos[2].id)
		assert.are.equal("clap", infos[3].id)
	end)

	it("_ResetForTests clears all player state", function()
		EmoteService.UnlockEmote(99, "wave")
		EmoteService._ResetForTests()
		assert.same({}, EmoteService.GetUnlockedEmotes(99))
	end)

	it("EmoteOrder contains all 5 emote ids in valid order", function()
		assert.are.equal(5, #EmoteService.EmoteOrder)
		for _, emoteId in ipairs(EmoteService.EmoteOrder) do
			assert.is_truthy(EmoteService.EmoteDefinitions[emoteId])
		end
	end)
end)

-- ── EmotePackets file structure ──────────────────────────────────────────────

describe("EmotePackets file structure", function()
	local src

	before_each(function()
		src = readFile("src/Network/EmotePackets.luau")
	end)

	it("EmotePackets.luau exists and is non-empty", function()
		assert.is_truthy(#src > 0)
	end)

	it("uses strict mode", function()
		assert.is_truthy(string.find(src, "--!strict", 1, true))
	end)

	it("defines GetEmotes packet", function()
		assert.is_truthy(string.find(src, "GetEmotes", 1, true))
	end)

	it("defines PerformEmote packet", function()
		assert.is_truthy(string.find(src, "PerformEmote", 1, true))
	end)

	it("defines EmotePerformed broadcast packet", function()
		assert.is_truthy(string.find(src, "EmotePerformed", 1, true))
	end)

	it("EmotePerformed includes PlayerId field", function()
		assert.is_truthy(string.find(src, "PlayerId", 1, true))
	end)

	it("EmotePerformed includes EmoteId field", function()
		assert.is_truthy(string.find(src, "EmoteId", 1, true))
	end)

	it("returns EmotePackets table", function()
		assert.is_truthy(string.find(src, "return EmotePackets", 1, true))
	end)
end)

-- ── EmoteService file structure ──────────────────────────────────────────────

describe("EmoteService file structure", function()
	local src

	before_each(function()
		src = readFile("src/Server/Services/EmoteService.luau")
	end)

	it("exposes GetUnlockedEmoteInfos function", function()
		assert.is_truthy(string.find(src, "GetUnlockedEmoteInfos", 1, true))
	end)

	it("exposes Init() function", function()
		assert.is_truthy(string.find(src, "EmoteService.Init", 1, true))
	end)

	it("guards Roblox requires behind IS_ROBLOX", function()
		assert.is_truthy(string.find(src, "IS_ROBLOX", 1, true))
	end)

	it("cleans up player state on PlayerRemoving", function()
		assert.is_truthy(string.find(src, "PlayerRemoving", 1, true))
	end)

	it("broadcasts EmotePerformed on PerformEmote", function()
		assert.is_truthy(string.find(src, "EmotePerformed", 1, true))
	end)
end)

-- ── EmoteUI file structure ───────────────────────────────────────────────────

describe("EmoteUI file structure", function()
	local src

	before_each(function()
		src = readFile("src/Client/UserInterface/EmoteUI.luau")
	end)

	it("EmoteUI.luau exists and is non-empty", function()
		assert.is_truthy(#src > 0)
	end)

	it("uses strict mode", function()
		assert.is_truthy(string.find(src, "--!strict", 1, true))
	end)

	it("requires EmotePackets", function()
		assert.is_truthy(string.find(src, "EmotePackets", 1, true))
	end)

	it("exposes Init()", function()
		assert.is_truthy(string.find(src, "EmoteUI.Init", 1, true))
	end)

	it("exposes Toggle()", function()
		assert.is_truthy(string.find(src, "EmoteUI.Toggle", 1, true))
	end)

	it("exposes SetVisible()", function()
		assert.is_truthy(string.find(src, "EmoteUI.SetVisible", 1, true))
	end)

	it("calls GetEmotes to fetch available emotes", function()
		assert.is_truthy(string.find(src, "GetEmotes", 1, true))
	end)

	it("calls PerformEmote when an emote card is clicked", function()
		assert.is_truthy(string.find(src, "PerformEmote", 1, true))
	end)

	it("has a PerformButton on each emote card", function()
		assert.is_truthy(string.find(src, "PerformButton", 1, true))
	end)

	it("shows emote name on each card", function()
		assert.is_truthy(string.find(src, "EmoteName", 1, true))
	end)

	it("shows emote description on each card", function()
		assert.is_truthy(string.find(src, "EmoteDesc", 1, true))
	end)

	it("has close button", function()
		assert.is_truthy(string.find(src, "CloseButton", 1, true))
	end)

	it("uses dim overlay", function()
		assert.is_truthy(string.find(src, "Overlay", 1, true))
	end)
end)

-- ── Server Main.server.luau wiring ──────────────────────────────────────────

describe("Server Main.server.luau emote wiring", function()
	local src

	before_each(function()
		src = readFile("src/Server/Main.server.luau")
	end)

	it("requires EmoteService", function()
		assert.is_truthy(string.find(src, "EmoteService", 1, true))
	end)

	it("calls EmoteService.Init in startup sequence", function()
		assert.is_truthy(string.find(src, "EmoteService.Init", 1, true))
	end)

	it("EmoteService.Init is wrapped in runStartupStep", function()
		assert.is_truthy(string.find(src, 'runStartupStep("EmoteService.Init"', 1, true))
	end)
end)

-- ── Client Main.client.luau wiring ──────────────────────────────────────────

describe("Client Main.client.luau emote wiring", function()
	local src

	before_each(function()
		src = readFile("src/Client/Main.client.luau")
	end)

	it("requires EmoteUI", function()
		assert.is_truthy(string.find(src, "EmoteUI", 1, true))
	end)

	it("calls EmoteUI.Init in startup sequence", function()
		assert.is_truthy(string.find(src, "EmoteUI.Init", 1, true))
	end)

	it("EmoteUI.Init is wrapped in runStartupStep", function()
		assert.is_truthy(string.find(src, 'runStartupStep("EmoteUI.Init"', 1, true))
	end)

	it("EmoteUI.Init comes after StorageInventoryUI.Init", function()
		local storagePos = string.find(src, "StorageInventoryUI.Init", 1, true)
		local emotePos = string.find(src, "EmoteUI.Init", 1, true)
		assert.is_truthy(storagePos and emotePos and emotePos > storagePos)
	end)
end)

-- ── MainHUD.luau emote wiring ────────────────────────────────────────────────

describe("MainHUD.luau emote wiring", function()
	local src

	before_each(function()
		src = readFile("src/Client/UserInterface/MainHUD.luau")
	end)

	it("requires EmoteUI", function()
		assert.is_truthy(string.find(src, "EmoteUI", 1, true))
	end)

	it("declares EmotesButton", function()
		assert.is_truthy(string.find(src, "EmotesButton", 1, true))
	end)

	it("connects EmotesButton.Activated to EmoteUI.Toggle", function()
		assert.is_truthy(string.find(src, "EmoteUI.Toggle", 1, true))
	end)

	it("includes EmotesButton in configureButtonVisuals loop", function()
		-- The ipairs loop that calls configureButtonVisuals for each button must include EmotesButton.
		-- We search for the for-loop array which contains WorldEventsButton and EmotesButton together.
		local loopStart = string.find(src, "for _, button in ipairs", 1, true)
		assert.is_truthy(loopStart)
		local loopRegion = string.sub(src, loopStart, loopStart + 500)
		assert.is_truthy(string.find(loopRegion, "EmotesButton", 1, true))
	end)

	it("EmotesButton LayoutOrder is after WorldEventsButton", function()
		assert.is_truthy(string.find(src, "WorldEventsButton.LayoutOrder + 1", 1, true))
	end)
end)
