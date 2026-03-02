--!strict
-- Tests/Specs/QuestUISpec.lua
-- Structural tests for the client-side QuestUI module and its wiring.
-- Validates file existence, API shape, packet references, and MainHUD / Main.client integration.

local function readFile(path)
	local file = assert(io.open(path, "r"), "missing file: " .. path)
	local contents = file:read("*a")
	file:close()
	return contents
end

-- ── QuestUI file structure ────────────────────────────────────────────────────

describe("QuestUI file structure", function()
	local src

	before_each(function()
		src = readFile("src/Client/UserInterface/QuestUI.luau")
	end)

	it("QuestUI.luau exists and is non-empty", function()
		assert.is_truthy(#src > 0)
	end)

	it("uses strict mode", function()
		assert.is_truthy(string.find(src, "--!strict", 1, true))
	end)

	it("requires QuestPackets", function()
		assert.is_truthy(string.find(src, "QuestPackets", 1, true))
	end)

	it("requires Notification", function()
		assert.is_truthy(string.find(src, "Notification", 1, true))
	end)

	it("exposes Init()", function()
		assert.is_truthy(string.find(src, "QuestUI.Init", 1, true))
	end)

	it("exposes Toggle()", function()
		assert.is_truthy(string.find(src, "QuestUI.Toggle", 1, true))
	end)

	it("exposes SetVisible()", function()
		assert.is_truthy(string.find(src, "QuestUI.SetVisible", 1, true))
	end)

	it("listens to QuestSnapshotUpdated push packet", function()
		assert.is_truthy(string.find(src, "QuestSnapshotUpdated", 1, true))
	end)

	it("listens to QuestCompleted push packet", function()
		assert.is_truthy(string.find(src, "QuestCompleted", 1, true))
	end)

	it("invokes GetQuestSnapshot to fetch snapshot on open", function()
		assert.is_truthy(string.find(src, "GetQuestSnapshot", 1, true))
	end)

	it("invokes StartQuest packet when starting a quest", function()
		assert.is_truthy(string.find(src, "StartQuest", 1, true))
	end)

	it("invokes ClaimQuest packet when claiming a quest", function()
		assert.is_truthy(string.find(src, "ClaimQuest", 1, true))
	end)

	it("defines filter states for all/active/available/done", function()
		assert.is_truthy(string.find(src, '"all"', 1, true))
		assert.is_truthy(string.find(src, '"active"', 1, true))
		assert.is_truthy(string.find(src, '"available"', 1, true))
		assert.is_truthy(string.find(src, '"done"', 1, true))
	end)

	it("defines STATE_COLORS table for visual state coding", function()
		assert.is_truthy(string.find(src, "STATE_COLORS", 1, true))
	end)

	it("defines STATE_LABELS table for human-readable state names", function()
		assert.is_truthy(string.find(src, "STATE_LABELS", 1, true))
	end)

	it("creates progress bars for in_progress quests", function()
		assert.is_truthy(string.find(src, "createProgressBar", 1, true))
	end)

	it("shows quest completion toast notification", function()
		assert.is_truthy(string.find(src, "Quest Complete!", 1, true))
	end)

	it("returns QuestUI table at end of module", function()
		assert.is_truthy(string.find(src, "return QuestUI", 1, true))
	end)
end)

-- ── MainHUD wiring ────────────────────────────────────────────────────────────

describe("MainHUD QuestUI wiring", function()
	local mainHUDSrc

	before_each(function()
		mainHUDSrc = readFile("src/Client/UserInterface/MainHUD.luau")
	end)

	it("requires QuestUI", function()
		assert.is_truthy(string.find(mainHUDSrc, "require(script.Parent.QuestUI)", 1, true))
	end)

	it("creates QuestsButton", function()
		assert.is_truthy(string.find(mainHUDSrc, "QuestsButton", 1, true))
	end)

	it("connects QuestsButton.Activated to QuestUI.Toggle", function()
		assert.is_truthy(string.find(mainHUDSrc, "QuestUI.Toggle", 1, true))
	end)

	it("includes QuestsButton in configureButtonVisuals loop", function()
		-- The button must appear in the list passed to configureButtonVisuals
		local loopLine = string.match(mainHUDSrc, "for _, button in ipairs%({[^}]+}%)")
		assert.is_truthy(loopLine and string.find(loopLine, "QuestsButton", 1, true))
	end)
end)

-- ── Main.client.luau wiring ───────────────────────────────────────────────────

describe("Main.client.luau QuestUI wiring", function()
	local clientMainSrc

	before_each(function()
		clientMainSrc = readFile("src/Client/Main.client.luau")
	end)

	it("requires QuestUI", function()
		assert.is_truthy(string.find(clientMainSrc, "QuestUI", 1, true))
	end)

	it("calls QuestUI.Init() in a startup step", function()
		assert.is_truthy(string.find(clientMainSrc, "QuestUI.Init", 1, true))
	end)

	it("initialises QuestUI after DailyRewardUI", function()
		local dailyPos = string.find(clientMainSrc, "DailyRewardUI.Init", 1, true)
		local questPos = string.find(clientMainSrc, "QuestUI.Init", 1, true)
		assert.is_truthy(dailyPos and questPos)
		assert.is_truthy(questPos > dailyPos)
	end)
end)

-- ── QuestService integration sanity (behavioral) ──────────────────────────────

local QuestService = assert(loadfile("src/Server/Services/QuestService.luau"))()

describe("QuestService behavioral (QuestUI scenario)", function()
	before_each(function()
		QuestService._ResetForTests()
	end)

	local fakePlayer = { UserId = 77, Name = "TestPlayer" }

	-- NOTE: QuestCatalog is populated lazily via ensureQuestExists (called by StartQuest).
	-- GetPlayerQuests alone won't populate the catalog after _ResetForTests.
	it("quest_basic is startable (available, no prerequisites)", function()
		-- StartQuest returns true only when the quest is in "available" state.
		local ok = QuestService.StartQuest(fakePlayer, "quest_basic")
		assert.is_true(ok)
	end)

	it("quest transitions to in_progress after StartQuest", function()
		local ok = QuestService.StartQuest(fakePlayer, "quest_basic")
		assert.is_true(ok)
		assert.equals("in_progress", QuestService.GetPlayerQuests(fakePlayer)["quest_basic"].State)
	end)

	it("quest transitions to completed when all objectives satisfied", function()
		QuestService.StartQuest(fakePlayer, "quest_basic")
		QuestService.ReportItemCollected(fakePlayer, "quest_basic", "coin", 10)
		QuestService.TriggerObjectiveEvent(fakePlayer, "quest_basic", "visit_npc")
		local state = QuestService.GetPlayerQuests(fakePlayer)["quest_basic"].State
		-- completed or claimed (if AutoClaim kicked in)
		assert.is_truthy(state == "completed" or state == "claimed")
	end)

	it("ClaimQuest grants rewards and marks claimed", function()
		local xpGranted = 0
		QuestService._SetXPSink(function(_, amt) xpGranted = xpGranted + amt end)
		QuestService.StartQuest(fakePlayer, "quest_basic")
		QuestService.ReportItemCollected(fakePlayer, "quest_basic", "coin", 10)
		QuestService.TriggerObjectiveEvent(fakePlayer, "quest_basic", "visit_npc")
		-- State may be "completed" (no AutoClaim) -- attempt explicit claim
		local st = QuestService.GetPlayerQuests(fakePlayer)["quest_basic"].State
		if st == "completed" then
			local ok2 = QuestService.ClaimQuest(fakePlayer, "quest_basic")
			assert.is_true(ok2)
			assert.equals("claimed", QuestService.GetPlayerQuests(fakePlayer)["quest_basic"].State)
			assert.is_true(xpGranted > 0)
		else
			-- auto-claimed already
			assert.equals("claimed", st)
		end
	end)

	it("chained quest unlocks after prerequisite is claimed", function()
		QuestService.StartQuest(fakePlayer, "quest_basic")
		QuestService.ReportItemCollected(fakePlayer, "quest_basic", "coin", 10)
		QuestService.TriggerObjectiveEvent(fakePlayer, "quest_basic", "visit_npc")
		local st = QuestService.GetPlayerQuests(fakePlayer)["quest_basic"].State
		if st == "completed" then
			QuestService.ClaimQuest(fakePlayer, "quest_basic")
		end
		QuestService.RefreshPlayerStates(fakePlayer)
		local chain2 = QuestService.GetPlayerQuests(fakePlayer)["quest_chain_2"]
		assert.is_truthy(chain2)
		assert.is_truthy(chain2.State == "available" or chain2.State == "in_progress")
	end)

	it("StartQuest returns false for unknown quest id", function()
		local ok, err = QuestService.StartQuest(fakePlayer, "no_such_quest")
		assert.is_false(ok)
		assert.equals("UnknownQuest", err)
	end)

	it("progress is tracked per objective", function()
		QuestService.StartQuest(fakePlayer, "quest_basic")
		QuestService.ReportItemCollected(fakePlayer, "quest_basic", "coin", 5)
		local progress = QuestService.GetPlayerQuests(fakePlayer)["quest_basic"].Progress
		assert.equals(5, progress["collect_coins"])
	end)
end)
