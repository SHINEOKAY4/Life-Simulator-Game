--!strict
-- Smoke test: exercises the pending rewards system (GetPendingRewards,
-- ClaimChallengeReward, ClaimMilestoneReward, DistributeSeasonRewards)
-- in isolation to ensure all entry-points work end-to-end.

local SeasonalEventService = assert(loadfile("src/Server/Services/SeasonalEventService.luau"))()

describe("Pending Rewards Smoke", function()
	local currentTime

	before_each(function()
		currentTime = 1000000
		SeasonalEventService._ResetForTests()
		SeasonalEventService._SetClock(function()
			return currentTime
		end)
	end)

	after_each(function()
		SeasonalEventService._SetClock(nil)
		SeasonalEventService._SetNotificationSink(nil)
		SeasonalEventService._SetRewardExecutor(nil)
	end)

	-- ========== GetPendingRewards smoke ==========

	describe("GetPendingRewards", function()
		it("starts with zero pending rewards for a fresh player", function()
			SeasonalEventService.TransitionSeason("smoke1", "Spring")

			local pending = SeasonalEventService.GetPendingRewards("smoke1")
			assert.is_not_nil(pending)
			assert.equals(0, #pending.Challenges)
			assert.equals(0, #pending.Milestones)
			assert.equals(0, pending.TotalPendingCash)
			assert.equals(0, pending.TotalPendingExperience)
		end)

		it("reflects a single completed challenge as pending", function()
			SeasonalEventService.TransitionSeason("smoke1", "Spring")
			SeasonalEventService.RecordProgress("smoke1", "SeasonalBuildPlacements", 20)

			local pending = SeasonalEventService.GetPendingRewards("smoke1")
			assert.equals(1, #pending.Challenges)
			assert.equals("spring_builder", pending.Challenges[1].Id)
			assert.equals(300, pending.TotalPendingCash)
			assert.equals(75, pending.TotalPendingExperience)
		end)

		it("reflects multiple completed challenges as pending", function()
			SeasonalEventService.TransitionSeason("smoke1", "Spring")
			SeasonalEventService.RecordProgress("smoke1", "SeasonalBuildPlacements", 20)
			SeasonalEventService.RecordProgress("smoke1", "SeasonalChoresCompleted", 8)

			local pending = SeasonalEventService.GetPendingRewards("smoke1")
			assert.equals(2, #pending.Challenges)
			assert.equals(500, pending.TotalPendingCash)
			assert.equals(125, pending.TotalPendingExperience)
		end)

		it("includes milestone rewards in pending totals", function()
			-- Complete 4 seasons to unlock "First Year" milestone
			local seasons = { "Spring", "Summer", "Autumn", "Winter" }
			for i = 1, 5 do
				currentTime = currentTime + (i * 1000)
				local idx = ((i - 1) % 4) + 1
				SeasonalEventService.TransitionSeason("smoke1", seasons[idx])
			end

			local pending = SeasonalEventService.GetPendingRewards("smoke1")
			assert.equals(1, #pending.Milestones)
			assert.equals("First Year", pending.Milestones[1].Label)
			assert.equals(500, pending.Milestones[1].BonusCash)
			assert.equals(120, pending.Milestones[1].BonusExperience)
		end)
	end)

	-- ========== ClaimChallengeReward smoke ==========

	describe("ClaimChallengeReward", function()
		it("claims a single challenge reward and clears it from pending", function()
			SeasonalEventService.TransitionSeason("smoke1", "Spring")
			SeasonalEventService.RecordProgress("smoke1", "SeasonalBuildPlacements", 20)

			-- Claim the reward
			local result, err = SeasonalEventService.ClaimChallengeReward("smoke1", "spring_builder")
			assert.is_nil(err)
			assert.is_not_nil(result)
			assert.equals(300, result.CashDistributed)
			assert.equals(75, result.ExperienceDistributed)

			-- Verify it is no longer pending
			local pending = SeasonalEventService.GetPendingRewards("smoke1")
			assert.equals(0, #pending.Challenges)
			assert.equals(0, pending.TotalPendingCash)
			assert.equals(0, pending.TotalPendingExperience)
		end)

		it("rejects claiming an uncompleted challenge", function()
			SeasonalEventService.TransitionSeason("smoke1", "Spring")

			local result, err = SeasonalEventService.ClaimChallengeReward("smoke1", "spring_builder")
			assert.is_nil(result)
			assert.is_not_nil(err)
		end)

		it("rejects double-claiming the same challenge", function()
			SeasonalEventService.TransitionSeason("smoke1", "Spring")
			SeasonalEventService.RecordProgress("smoke1", "SeasonalBuildPlacements", 20)

			local result1, err1 = SeasonalEventService.ClaimChallengeReward("smoke1", "spring_builder")
			assert.is_nil(err1)

			local result2, err2 = SeasonalEventService.ClaimChallengeReward("smoke1", "spring_builder")
			assert.is_nil(result2)
			assert.is_not_nil(err2)
		end)
	end)

	-- ========== ClaimMilestoneReward smoke ==========

	describe("ClaimMilestoneReward", function()
		it("claims a milestone reward and clears it from pending", function()
			local seasons = { "Spring", "Summer", "Autumn", "Winter" }
			for i = 1, 5 do
				currentTime = currentTime + (i * 1000)
				local idx = ((i - 1) % 4) + 1
				SeasonalEventService.TransitionSeason("smoke1", seasons[idx])
			end

			-- "First Year" milestone at 4 seasons completed
			local result, err = SeasonalEventService.ClaimMilestoneReward("smoke1", 4)
			assert.is_nil(err)
			assert.is_not_nil(result)
			assert.equals(500, result.CashDistributed)
			assert.equals(120, result.ExperienceDistributed)

			-- Verify it is no longer pending
			local pending = SeasonalEventService.GetPendingRewards("smoke1")
			assert.equals(0, #pending.Milestones)
		end)

		it("rejects claiming a milestone that has not been reached", function()
			SeasonalEventService.TransitionSeason("smoke1", "Spring")

			local result, err = SeasonalEventService.ClaimMilestoneReward("smoke1", 4)
			assert.is_nil(result)
			assert.is_not_nil(err)
		end)
	end)

	-- ========== DistributeSeasonRewards smoke ==========

	describe("DistributeSeasonRewards", function()
		it("batch-distributes all pending rewards at once", function()
			SeasonalEventService.TransitionSeason("smoke1", "Spring")
			SeasonalEventService.RecordProgress("smoke1", "SeasonalBuildPlacements", 20)
			SeasonalEventService.RecordProgress("smoke1", "SeasonalChoresCompleted", 8)

			local result, err = SeasonalEventService.DistributeSeasonRewards("smoke1")
			assert.is_nil(err)
			assert.is_not_nil(result)
			assert.equals(2, result.ChallengesDistributed)
			assert.equals(500, result.TotalCashDistributed)
			assert.equals(125, result.TotalExperienceDistributed)

			-- All pending should now be zero
			local pending = SeasonalEventService.GetPendingRewards("smoke1")
			assert.equals(0, #pending.Challenges)
			assert.equals(0, pending.TotalPendingCash)
		end)

		it("returns zero summary when nothing is pending", function()
			SeasonalEventService.TransitionSeason("smoke1", "Spring")

			local result, err = SeasonalEventService.DistributeSeasonRewards("smoke1")
			assert.is_nil(err)
			assert.is_not_nil(result)
			assert.equals(0, result.ChallengesDistributed)
			assert.equals(0, result.MilestonesDistributed)
			assert.equals(0, result.TotalCashDistributed)
			assert.equals(0, result.TotalExperienceDistributed)
		end)

		it("distributes challenge and milestone rewards together", function()
			-- Complete 4 seasons to unlock "First Year" milestone
			local seasons = { "Spring", "Summer", "Autumn", "Winter" }
			for i = 1, 5 do
				currentTime = currentTime + (i * 1000)
				local idx = ((i - 1) % 4) + 1
				SeasonalEventService.TransitionSeason("smoke1", seasons[idx])
			end

			-- Also complete a challenge in the current season (Spring again)
			SeasonalEventService.RecordProgress("smoke1", "SeasonalBuildPlacements", 20)

			local result, err = SeasonalEventService.DistributeSeasonRewards("smoke1")
			assert.is_nil(err)
			assert.equals(1, result.ChallengesDistributed)
			assert.equals(1, result.MilestonesDistributed)
			-- spring_builder (300) + First Year (500) = 800 cash
			assert.equals(800, result.TotalCashDistributed)
			-- spring_builder (75) + First Year (120) = 195 xp
			assert.equals(195, result.TotalExperienceDistributed)

			-- Verify all cleared from pending
			local pending = SeasonalEventService.GetPendingRewards("smoke1")
			assert.equals(0, #pending.Challenges)
			assert.equals(0, #pending.Milestones)
			assert.equals(0, pending.TotalPendingCash)
			assert.equals(0, pending.TotalPendingExperience)
		end)
	end)

	-- ========== Rollback on executor failure ==========

	describe("Rollback on executor failure", function()
		it("rolls back batch distribution when executor fails mid-way", function()
			SeasonalEventService.TransitionSeason("smoke1", "Spring")
			SeasonalEventService.RecordProgress("smoke1", "SeasonalBuildPlacements", 20)
			SeasonalEventService.RecordProgress("smoke1", "SeasonalChoresCompleted", 8)

			local callCount = 0
			SeasonalEventService._SetRewardExecutor(function(playerId, cash, xp, source)
				callCount = callCount + 1
				-- Fail on the second forward grant (not rollback calls)
				if callCount == 2 and cash > 0 then
					return false, "SimulatedFailure"
				end
				return true, nil
			end)

			local result, err = SeasonalEventService.DistributeSeasonRewards("smoke1")
			assert.is_nil(result)
			assert.equals("DistributionFailed", err)

			-- After rollback, rewards should still be pending
			SeasonalEventService._SetRewardExecutor(nil) -- restore default
			local pending = SeasonalEventService.GetPendingRewards("smoke1")
			assert.equals(2, #pending.Challenges)
			assert.equals(500, pending.TotalPendingCash)
			assert.equals(125, pending.TotalPendingExperience)
		end)

		it("does not leave partial state on single claim failure", function()
			SeasonalEventService.TransitionSeason("smoke1", "Spring")
			SeasonalEventService.RecordProgress("smoke1", "SeasonalBuildPlacements", 20)

			SeasonalEventService._SetRewardExecutor(function()
				return false, "SimulatedFailure"
			end)

			local result, err = SeasonalEventService.ClaimChallengeReward("smoke1", "spring_builder")
			assert.is_nil(result)
			assert.equals("DistributionFailed", err)

			-- Reward should still be pending
			SeasonalEventService._SetRewardExecutor(nil)
			local pending = SeasonalEventService.GetPendingRewards("smoke1")
			assert.equals(1, #pending.Challenges)
			assert.equals(300, pending.TotalPendingCash)
		end)
	end)

	-- ========== Isolation subprocess ==========

	describe("Subprocess isolation #subprocess", function()
		it("runs this spec file in its own busted process #subprocess", function()
			-- Verify this spec can execute cleanly in a fresh process,
			-- proving the pending rewards system has no hidden dependencies.
			local logPath = "/tmp/pending_rewards_smoke.log"
			local cmd =
				"PATH=\"$HOME/.luarocks/bin:$PATH\" busted Tests/Specs/PendingRewardsSmokeSpec.lua"
				.. " --exclude-tags=subprocess > "
				.. logPath
				.. " 2>&1"
			local ok, reason, code = os.execute(cmd)

			local passed = false
			local exitCode = -1
			if type(ok) == "number" then
				exitCode = ok
				passed = ok == 0
			elseif type(ok) == "boolean" then
				exitCode = code or (ok and 0 or 1)
				passed = ok and exitCode == 0 and reason == "exit"
			end

			if not passed then
				local output = "(no output captured)"
				local handle = io.open(logPath, "r")
				if handle then
					output = handle:read("*a") or output
					handle:close()
				end
				error(
					string.format(
						"Isolated pending rewards smoke run failed (exit=%s).\nCommand: %s\nOutput:\n%s",
						tostring(exitCode),
						cmd,
						output
					)
				)
			end
		end)
	end)
end)
