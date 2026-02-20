--!strict
-- Unit tests for EmoteService

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
end)
