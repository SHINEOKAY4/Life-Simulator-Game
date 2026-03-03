--!strict
-- Tests/Specs/QuestServiceWiringSpec.lua
-- Structural + behavioral tests for QuestService network wiring and server init.
-- Validates that QuestPackets exists, QuestService Init references packets,
-- and Main.server.luau initializes QuestService + DailyRewardService.

local function readFile(path)
	local file = assert(io.open(path, "r"), "missing file: " .. path)
	local contents = file:read("*a")
	file:close()
	return contents
end

local QuestService = assert(loadfile("src/Server/Services/QuestService.luau"))()

describe("QuestPackets structural", function()
	local packetsSrc

	before_each(function()
		packetsSrc = readFile("src/Network/QuestPackets.luau")
	end)

	it("QuestPackets.luau file exists and is non-empty", function()
		assert.is_truthy(#packetsSrc > 0)
	end)

	it("defines GetQuestSnapshot packet", function()
		assert.is_truthy(string.find(packetsSrc, "GetQuestSnapshot", 1, true))
	end)

	it("defines StartQuest packet", function()
		assert.is_truthy(string.find(packetsSrc, "QuestStartQuest", 1, true))
	end)

	it("defines ClaimQuest packet", function()
		assert.is_truthy(string.find(packetsSrc, "QuestClaimQuest", 1, true))
	end)

	it("defines QuestSnapshotUpdated push packet", function()
		assert.is_truthy(string.find(packetsSrc, "QuestSnapshotUpdated", 1, true))
	end)

	it("defines QuestCompleted push packet", function()
		assert.is_truthy(string.find(packetsSrc, "QuestCompleted", 1, true))
	end)
end)

describe("QuestService network wiring", function()
	local serviceSrc

	before_each(function()
		serviceSrc = readFile("src/Server/Services/QuestService.luau")
	end)

	it("requires QuestPackets when in Roblox runtime", function()
		assert.is_truthy(string.find(serviceSrc, "QuestPackets", 1, true))
	end)

	it("wires GetQuestSnapshot.OnServerInvoke", function()
		assert.is_truthy(string.find(serviceSrc, "GetQuestSnapshot.OnServerInvoke", 1, true))
	end)

	it("wires StartQuest.OnServerInvoke", function()
		assert.is_truthy(string.find(serviceSrc, "StartQuest.OnServerInvoke", 1, true))
	end)

	it("wires ClaimQuest.OnServerInvoke", function()
		assert.is_truthy(string.find(serviceSrc, "ClaimQuest.OnServerInvoke", 1, true))
	end)

	it("pushes snapshot to client after progress", function()
		assert.is_truthy(string.find(serviceSrc, "pushSnapshotToClient", 1, true))
	end)

	it("notifies client on quest completion", function()
		assert.is_truthy(string.find(serviceSrc, "notifyQuestCompleted", 1, true))
	end)
end)

describe("Main.server.luau init wiring", function()
	local mainSrc

	before_each(function()
		mainSrc = readFile("src/Server/Main.server.luau")
	end)

	it("requires QuestService", function()
		assert.is_truthy(string.find(mainSrc, "require(ServicesFolder.QuestService)", 1, true))
	end)

	it("initializes QuestService.Init()", function()
		assert.is_truthy(string.find(mainSrc, "QuestService.Init()", 1, true))
	end)

	it("requires DailyRewardService", function()
		assert.is_truthy(string.find(mainSrc, "require(ServicesFolder.DailyRewardService)", 1, true))
	end)

	it("initializes DailyRewardService.Init()", function()
		assert.is_truthy(string.find(mainSrc, "DailyRewardService.Init()", 1, true))
	end)

	it("initializes QuestService before DailyRewardService", function()
		local questPos = string.find(mainSrc, "QuestService.Init()", 1, true)
		local dailyPos = string.find(mainSrc, "DailyRewardService.Init()", 1, true)
		assert.is_truthy(questPos, "QuestService.Init must be present")
		assert.is_truthy(dailyPos, "DailyRewardService.Init must be present")
		assert.is_true(questPos < dailyPos, "QuestService should init before DailyRewardService")
	end)
end)

describe("QuestService behavioral with snapshot hooks", function()
	local player

	before_each(function()
		QuestService._ResetForTests()
		player = { UserId = 1, Name = "TestPlayer" }
		QuestService.Init()
	end)

	it("existing quest lifecycle still works after wiring changes", function()
		-- Start quest
		local ok, err = QuestService.StartQuest(player, "quest_basic")
		assert.is_true(ok)
		assert.is_nil(err)

		-- Progress objectives
		QuestService.ProgressObjective(player, "quest_basic", "collect_coins", 10)
		QuestService.TriggerObjectiveEvent(player, "quest_basic", "visit_npc")

		-- Should be completed
		local quests = QuestService.GetPlayerQuests(player)
		assert.equals("completed", quests["quest_basic"].State)

		-- Claim
		ok, err = QuestService.ClaimQuest(player, "quest_basic")
		assert.is_true(ok)
		assert.is_nil(err)
		assert.equals("claimed", QuestService.GetPlayerQuests(player)["quest_basic"].State)
	end)

	it("ReportItemCollected still completes quests after wiring changes", function()
		QuestService.StartQuest(player, "quest_basic")
		QuestService.ReportItemCollected(player, "quest_basic", "any_item", 10)
		QuestService.TriggerObjectiveEvent(player, "quest_basic", "visit_npc")

		local quests = QuestService.GetPlayerQuests(player)
		assert.equals("completed", quests["quest_basic"].State)
	end)

	it("auto-claim chain quest still works after wiring changes", function()
		-- Complete prerequisite
		QuestService.StartQuest(player, "quest_basic")
		QuestService.ProgressObjective(player, "quest_basic", "collect_coins", 10)
		QuestService.TriggerObjectiveEvent(player, "quest_basic", "visit_npc")
		QuestService.ClaimQuest(player, "quest_basic")
		QuestService.RefreshPlayerStates(player)

		-- Start auto-claim chain quest
		QuestService.StartQuest(player, "quest_chain_2")
		QuestService.TriggerObjectiveEvent(player, "quest_chain_2", "place_chest")

		local quests = QuestService.GetPlayerQuests(player)
		assert.equals("claimed", quests["quest_chain_2"].State)
	end)

	it("repeatable quest lifecycle still works after wiring changes", function()
		-- Complete and claim daily_challenge_collect
		QuestService.StartQuest(player, "daily_challenge_collect")
		QuestService.ProgressObjective(player, "daily_challenge_collect", "daily_collect", 25)
		-- AutoClaim is true, so it should auto-claim
		local quests = QuestService.GetPlayerQuests(player)
		assert.equals("claimed", quests["daily_challenge_collect"].State)

		-- Repeatable: should allow starting again
		local ok = QuestService.StartQuest(player, "daily_challenge_collect")
		assert.is_true(ok)
		quests = QuestService.GetPlayerQuests(player)
		assert.equals("in_progress", quests["daily_challenge_collect"].State)
	end)
end)
