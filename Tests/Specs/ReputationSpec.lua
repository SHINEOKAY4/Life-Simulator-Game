--!strict
-- Unit tests for ReputationService

local ReputationService = assert(loadfile("src/Server/Services/ReputationService.luau"))()

describe("ReputationService", function()
	before_each(function()
		ReputationService._ResetForTests()
	end)

	it("returns expected trust levels for score thresholds", function()
		assert.equals("Unknown", ReputationService.GetTrustLevel(0))
		assert.equals("Familiar", ReputationService.GetTrustLevel(25))
		assert.equals("Trusted", ReputationService.GetTrustLevel(50))
		assert.equals("Elite", ReputationService.GetTrustLevel(75))
	end)

	it("builds rankings sorted by reputation score descending", function()
		ReputationService.AdjustReputation("alice", 20, "seed") -- 70
		ReputationService.AdjustReputation("bob", -15, "seed") -- 35
		ReputationService.AdjustReputation("charlie", 30, "seed") -- 80

		local data = ReputationService.GetReputationData("alice")
		assert.is_not_nil(data)
		assert.equals(3, #data.Rankings)
		assert.equals("charlie", data.Rankings[1].PlayerName)
		assert.equals("alice", data.Rankings[2].PlayerName)
		assert.equals("bob", data.Rankings[3].PlayerName)
		assert.equals(2, data.PlayerRank)
	end)

	it("awards tier reward once when crossing to a higher trust tier", function()
		local first = ReputationService.AdjustReputation("playerA", 30, "boost")
		assert.equals(80, first.NewScore)
		assert.equals("Elite", first.TrustLevel)
		assert.equals(250, first.RewardEarned)

		local second = ReputationService.AdjustReputation("playerA", -30, "drop")
		assert.equals(50, second.NewScore)
		assert.equals(0, second.RewardEarned)

		local third = ReputationService.AdjustReputation("playerA", 40, "recover")
		assert.equals(90, third.NewScore)
		assert.equals(0, third.RewardEarned)

		local data = ReputationService.GetReputationData("playerA")
		assert.equals(250, data.LifetimeRewards)
	end)

	it("applies review outcomes to reputation score", function()
		local result = ReputationService.ProcessReviewOutcome("reviewPlayer", 5, "Complete")
		assert.is_not_nil(result)
		assert.equals(14, result.ScoreDelta)

		local data = ReputationService.GetReputationData("reviewPlayer")
		assert.equals(64, data.Snapshot.ReputationScore)
		assert.equals("Trusted", data.Snapshot.TrustLevel)
	end)
end)
