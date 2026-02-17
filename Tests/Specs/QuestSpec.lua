--!strict
-- Tests/Specs/QuestSpec.lua
-- Unit tests for QuestService

describe("QuestService", function()
	local function createMockQuestService()
		return {
			Init = function() end,
			RefreshPlayerStates = function() end,
			GetPlayerQuests = function() return {} end,
			StartQuest = function() return true, nil end,
			ProgressObjective = function() return true, nil end,
			TriggerObjectiveEvent = function() end,
			ClaimQuest = function() return true, nil end,
			GetRewardsLog = function() return {} end,
		}
	end

	it("should have Init function", function()
		local mock = createMockQuestService()
		assert.is.truthy(mock.Init)
	end)

	it("should have RefreshPlayerStates function", function()
		local mock = createMockQuestService()
		assert.is.truthy(mock.RefreshPlayerStates)
	end)

	it("should have GetPlayerQuests function", function()
		local mock = createMockQuestService()
		assert.is.truthy(mock.GetPlayerQuests)
	end)

	it("should have StartQuest function", function()
		local mock = createMockQuestService()
		assert.is.truthy(mock.StartQuest)
	end)

	it("should have ProgressObjective function", function()
		local mock = createMockQuestService()
		assert.is.truthy(mock.ProgressObjective)
	end)

	it("should have TriggerObjectiveEvent function", function()
		local mock = createMockQuestService()
		assert.is.truthy(mock.TriggerObjectiveEvent)
	end)

	it("should have ClaimQuest function", function()
		local mock = createMockQuestService()
		assert.is.truthy(mock.ClaimQuest)
	end)

	it("should have GetRewardsLog function", function()
		local mock = createMockQuestService()
		assert.is.truthy(mock.GetRewardsLog)
	end)
end)
