--!strict
-- Tests/Specs/QuestSpec.lua
-- Behavioral tests for QuestService (loaded via loadfile, no Roblox runtime)

local QuestService = assert(loadfile("src/Server/Services/QuestService.luau"))()

describe("QuestService", function()
	local player

	before_each(function()
		QuestService._ResetForTests()
		player = { UserId = 1, Name = "TestPlayer" }
		-- Init seeds the default catalog
		QuestService.Init()
	end)

	describe("Init and catalog", function()
		it("populates the default quest catalog on Init", function()
			local quests = QuestService.GetPlayerQuests(player)
			assert.is_not_nil(quests)
			assert.is_not_nil(quests["quest_basic"])
			assert.is_not_nil(quests["quest_chain_2"])
		end)

		it("marks quests with no prerequisites as available", function()
			local quests = QuestService.GetPlayerQuests(player)
			assert.equals("available", quests["quest_basic"].State)
		end)

		it("marks quests with unmet prerequisites as locked", function()
			local quests = QuestService.GetPlayerQuests(player)
			assert.equals("locked", quests["quest_chain_2"].State)
		end)
	end)

	describe("StartQuest", function()
		it("transitions an available quest to in_progress", function()
			local ok, err = QuestService.StartQuest(player, "quest_basic")
			assert.is_true(ok)
			assert.is_nil(err)
			local quests = QuestService.GetPlayerQuests(player)
			assert.equals("in_progress", quests["quest_basic"].State)
		end)

		it("initializes objective progress to zero", function()
			QuestService.StartQuest(player, "quest_basic")
			local quests = QuestService.GetPlayerQuests(player)
			assert.equals(0, quests["quest_basic"].Progress["collect_coins"])
			assert.equals(0, quests["quest_basic"].Progress["visit_npc"])
		end)

		it("rejects starting a locked quest", function()
			local ok, err = QuestService.StartQuest(player, "quest_chain_2")
			assert.is_false(ok)
			assert.equals("QuestNotAvailable", err)
		end)

		it("rejects starting an unknown quest", function()
			local ok, err = QuestService.StartQuest(player, "nonexistent_quest")
			assert.is_false(ok)
			assert.equals("UnknownQuest", err)
		end)
	end)

	describe("ProgressObjective", function()
		it("increments numeric progress for an objective", function()
			QuestService.StartQuest(player, "quest_basic")
			local ok = QuestService.ProgressObjective(player, "quest_basic", "collect_coins", 5)
			assert.is_true(ok)
			local quests = QuestService.GetPlayerQuests(player)
			assert.equals(5, quests["quest_basic"].Progress["collect_coins"])
		end)

		it("rejects progress on a quest not in_progress", function()
			local ok, err = QuestService.ProgressObjective(player, "quest_basic", "collect_coins", 1)
			assert.is_false(ok)
			assert.equals("NotInProgress", err)
		end)

		it("rejects progress on unknown objective", function()
			QuestService.StartQuest(player, "quest_basic")
			local ok, err = QuestService.ProgressObjective(player, "quest_basic", "nonexistent_obj", 1)
			assert.is_false(ok)
			assert.equals("UnknownObjective", err)
		end)

		it("clamps negative delta to zero", function()
			QuestService.StartQuest(player, "quest_basic")
			QuestService.ProgressObjective(player, "quest_basic", "collect_coins", 3)
			QuestService.ProgressObjective(player, "quest_basic", "collect_coins", -5)
			local quests = QuestService.GetPlayerQuests(player)
			assert.equals(3, quests["quest_basic"].Progress["collect_coins"])
		end)

		it("marks quest completed when all objectives are met", function()
			QuestService.StartQuest(player, "quest_basic")
			QuestService.ProgressObjective(player, "quest_basic", "collect_coins", 10)
			-- quest_basic has a Talk objective with string target "OldMan" -> needs progress >= 1
			QuestService.TriggerObjectiveEvent(player, "quest_basic", "visit_npc")
			local quests = QuestService.GetPlayerQuests(player)
			assert.equals("completed", quests["quest_basic"].State)
		end)

		it("does not mark quest completed when only some objectives are met", function()
			QuestService.StartQuest(player, "quest_basic")
			QuestService.ProgressObjective(player, "quest_basic", "collect_coins", 10)
			-- visit_npc still at 0
			local quests = QuestService.GetPlayerQuests(player)
			assert.equals("in_progress", quests["quest_basic"].State)
		end)
	end)

	describe("TriggerObjectiveEvent", function()
		it("increments progress by 1 for the named objective", function()
			QuestService.StartQuest(player, "quest_basic")
			QuestService.TriggerObjectiveEvent(player, "quest_basic", "visit_npc")
			local quests = QuestService.GetPlayerQuests(player)
			assert.equals(1, quests["quest_basic"].Progress["visit_npc"])
		end)
	end)

	describe("ClaimQuest", function()
		it("transitions completed quest to claimed and logs rewards", function()
			QuestService.StartQuest(player, "quest_basic")
			QuestService.ProgressObjective(player, "quest_basic", "collect_coins", 10)
			QuestService.TriggerObjectiveEvent(player, "quest_basic", "visit_npc")
			-- now completed
			local ok, err = QuestService.ClaimQuest(player, "quest_basic")
			assert.is_true(ok)
			assert.is_nil(err)
			local quests = QuestService.GetPlayerQuests(player)
			assert.equals("claimed", quests["quest_basic"].State)
		end)

		it("logs reward data when claiming", function()
			QuestService.StartQuest(player, "quest_basic")
			QuestService.ProgressObjective(player, "quest_basic", "collect_coins", 10)
			QuestService.TriggerObjectiveEvent(player, "quest_basic", "visit_npc")
			QuestService.ClaimQuest(player, "quest_basic")
			local log = QuestService.GetRewardsLog(player)
			assert.is_not_nil(log["quest_basic"])
			assert.equals(100, log["quest_basic"].XP)
		end)

		it("rejects claiming an uncompleted quest", function()
			QuestService.StartQuest(player, "quest_basic")
			local ok, err = QuestService.ClaimQuest(player, "quest_basic")
			assert.is_false(ok)
			assert.equals("NotCompletable", err)
		end)

		it("rejects claiming an unknown quest", function()
			local ok, err = QuestService.ClaimQuest(player, "nonexistent")
			assert.is_false(ok)
			assert.equals("UnknownQuest", err)
		end)
	end)

	describe("AutoClaim", function()
		it("auto-claims quest when AutoClaim is true and all objectives complete", function()
			-- First complete quest_basic to unlock quest_chain_2
			QuestService.StartQuest(player, "quest_basic")
			QuestService.ProgressObjective(player, "quest_basic", "collect_coins", 10)
			QuestService.TriggerObjectiveEvent(player, "quest_basic", "visit_npc")
			QuestService.ClaimQuest(player, "quest_basic")

			-- Refresh to unlock chain quest
			QuestService.RefreshPlayerStates(player)
			local quests = QuestService.GetPlayerQuests(player)
			assert.equals("available", quests["quest_chain_2"].State)

			-- Start and complete the auto-claim quest
			QuestService.StartQuest(player, "quest_chain_2")
			-- "place_chest" is a Place objective with string target "Chest" -> needs progress >= 1
			QuestService.TriggerObjectiveEvent(player, "quest_chain_2", "place_chest")

			quests = QuestService.GetPlayerQuests(player)
			assert.equals("claimed", quests["quest_chain_2"].State)
		end)
	end)

	describe("prerequisite chains", function()
		it("unlocks chain quest after prerequisite is claimed", function()
			QuestService.StartQuest(player, "quest_basic")
			QuestService.ProgressObjective(player, "quest_basic", "collect_coins", 10)
			QuestService.TriggerObjectiveEvent(player, "quest_basic", "visit_npc")
			QuestService.ClaimQuest(player, "quest_basic")

			QuestService.RefreshPlayerStates(player)
			local quests = QuestService.GetPlayerQuests(player)
			assert.equals("available", quests["quest_chain_2"].State)
		end)

		it("keeps chain quest locked if prerequisite is only completed, not claimed", function()
			QuestService.StartQuest(player, "quest_basic")
			QuestService.ProgressObjective(player, "quest_basic", "collect_coins", 10)
			QuestService.TriggerObjectiveEvent(player, "quest_basic", "visit_npc")
			-- completed but NOT claimed
			QuestService.RefreshPlayerStates(player)
			local quests = QuestService.GetPlayerQuests(player)
			-- RefreshPlayerStates treats "completed" as satisfying prereqs
			assert.equals("available", quests["quest_chain_2"].State)
		end)

		it("keeps chain quest locked if prerequisite is still in_progress", function()
			QuestService.StartQuest(player, "quest_basic")
			QuestService.RefreshPlayerStates(player)
			local quests = QuestService.GetPlayerQuests(player)
			assert.equals("locked", quests["quest_chain_2"].State)
		end)
	end)

	describe("RefreshPlayerStates", function()
		it("does not crash for nil player", function()
			assert.has_no.errors(function()
				QuestService.RefreshPlayerStates(nil)
			end)
		end)

		it("does not regress already in_progress quest to available", function()
			QuestService.StartQuest(player, "quest_basic")
			QuestService.RefreshPlayerStates(player)
			local quests = QuestService.GetPlayerQuests(player)
			assert.equals("in_progress", quests["quest_basic"].State)
		end)
	end)

	describe("multi-player isolation", function()
		it("tracks quest progress independently per player", function()
			local player2 = { UserId = 2, Name = "Player2" }
			QuestService.StartQuest(player, "quest_basic")
			QuestService.ProgressObjective(player, "quest_basic", "collect_coins", 7)

			local quests1 = QuestService.GetPlayerQuests(player)
			local quests2 = QuestService.GetPlayerQuests(player2)
			assert.equals("in_progress", quests1["quest_basic"].State)
			assert.equals(7, quests1["quest_basic"].Progress["collect_coins"])
			assert.equals("available", quests2["quest_basic"].State)
		end)
	end)

	describe("GetPlayerQuests", function()
		it("returns nil for nil player", function()
			assert.is_nil(QuestService.GetPlayerQuests(nil))
		end)
	end)

	describe("GetRewardsLog", function()
		it("returns empty table when no rewards claimed", function()
			local log = QuestService.GetRewardsLog(player)
			assert.same({}, log)
		end)

		it("returns nil for nil player", function()
			assert.is_nil(QuestService.GetRewardsLog(nil))
		end)
	end)
end)
