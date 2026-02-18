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

	it("gates interactions by required trust level", function()
		ReputationService.AdjustReputation("lowTrust", -35, "seed") -- 15 => Unknown
		local canTrade, gate = ReputationService.CanPerformInteraction("lowTrust", "TradeNegotiation")

		assert.is_false(canTrade)
		assert.is_not_nil(gate)
		assert.equals("Unknown", gate.CurrentTrustLevel)
		assert.equals("Familiar", gate.RequiredTrustLevel)
	end)

	it("applies multiplier-adjusted reputation gain for successful interactions", function()
		local result, err = ReputationService.ProcessInteraction("socialPlayer", "ConflictMediation", "Success")
		assert.is_nil(err)
		assert.is_not_nil(result)
		assert.is_true(result.Applied)
		assert.equals(7, result.ScoreDelta) -- 6 * 1.10 rounded = 7 at Trusted
		assert.equals(57, result.NewScore)
	end)

	it("returns trust gate payload when interaction is blocked", function()
		ReputationService.AdjustReputation("blockedPlayer", -40, "seed") -- 10 => Unknown
		local result, err = ReputationService.ProcessInteraction("blockedPlayer", "ConflictMediation", "Success")
		assert.is_nil(err)
		assert.is_not_nil(result)
		assert.is_false(result.Applied)
		assert.equals("TrustTooLow", result.Reason)
		assert.equals("Trusted", result.RequiredTrustLevel)
		assert.equals("Unknown", result.CurrentTrustLevel)
		assert.equals(0, result.ScoreDelta)
	end)

	it("returns error for unknown interaction type", function()
		local result, err = ReputationService.ProcessInteraction("playerX", "UnknownType", "Success")
		assert.is_nil(result)
		assert.equals("UnknownInteraction", err)
	end)
end)
