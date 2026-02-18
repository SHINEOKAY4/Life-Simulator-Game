--!strict
-- Integration tests: seasonal rewards distributed properly across all seasons (game modes)

local SeasonalEventService = assert(loadfile("src/Server/Services/SeasonalEventService.luau"))()

describe("Seasonal Rewards Integration", function()
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
	end)

	-- Season challenge data for verification
	-- Spring: spring_builder (300/$75), spring_green (200/$50) = 500/$125
	-- Summer: summer_landlord (350/$80), summer_crafter (250/$60) = 600/$140
	-- Autumn: autumn_crafter (400/$90), autumn_trader (300/$70) = 700/$160
	-- Winter: winter_repair (450/$100), winter_warmth (275/$65) = 725/$165
	-- Total challenges across all seasons: 2525 cash / 590 xp
	-- "First Year" milestone (4 seasons): 500 cash / 120 xp
	-- Grand total: 3025 cash / 710 xp

	-- ========== Full-Cycle Distribution ==========

	describe("Full-cycle reward distribution across all seasons", function()
		it("distributes correct challenge rewards for Spring", function()
			SeasonalEventService.TransitionSeason("player1", "Spring")
			SeasonalEventService.RecordProgress("player1", "SeasonalBuildPlacements", 20)
			SeasonalEventService.RecordProgress("player1", "SeasonalChoresCompleted", 8)

			local result, err = SeasonalEventService.DistributeSeasonRewards("player1")
			assert.is_nil(err)
			assert.equals(2, result.ChallengesDistributed)
			assert.equals(0, result.MilestonesDistributed)
			assert.equals(500, result.TotalCashDistributed)
			assert.equals(125, result.TotalExperienceDistributed)
		end)

		it("distributes correct challenge rewards for Summer", function()
			SeasonalEventService.TransitionSeason("player1", "Spring")
			currentTime = currentTime + 1000
			SeasonalEventService.TransitionSeason("player1", "Summer")
			SeasonalEventService.RecordProgress("player1", "SeasonalTenantHelps", 6)
			SeasonalEventService.RecordProgress("player1", "SeasonalCraftingJobs", 5)

			local result, err = SeasonalEventService.DistributeSeasonRewards("player1")
			assert.is_nil(err)
			assert.equals(2, result.ChallengesDistributed)
			assert.equals(0, result.MilestonesDistributed)
			assert.equals(600, result.TotalCashDistributed)
			assert.equals(140, result.TotalExperienceDistributed)
		end)

		it("distributes correct challenge rewards for Autumn", function()
			SeasonalEventService.TransitionSeason("player1", "Spring")
			currentTime = currentTime + 1000
			SeasonalEventService.TransitionSeason("player1", "Summer")
			currentTime = currentTime + 1000
			SeasonalEventService.TransitionSeason("player1", "Autumn")
			SeasonalEventService.RecordProgress("player1", "SeasonalCraftingJobs", 10)
			SeasonalEventService.RecordProgress("player1", "SeasonalTradesCompleted", 3)

			local result, err = SeasonalEventService.DistributeSeasonRewards("player1")
			assert.is_nil(err)
			assert.equals(2, result.ChallengesDistributed)
			assert.equals(0, result.MilestonesDistributed)
			assert.equals(700, result.TotalCashDistributed)
			assert.equals(160, result.TotalExperienceDistributed)
		end)

		it("distributes correct challenge rewards for Winter", function()
			SeasonalEventService.TransitionSeason("player1", "Spring")
			currentTime = currentTime + 1000
			SeasonalEventService.TransitionSeason("player1", "Summer")
			currentTime = currentTime + 1000
			SeasonalEventService.TransitionSeason("player1", "Autumn")
			currentTime = currentTime + 1000
			SeasonalEventService.TransitionSeason("player1", "Winter")
			SeasonalEventService.RecordProgress("player1", "SeasonalChoresCompleted", 12)
			SeasonalEventService.RecordProgress("player1", "SeasonalTenantHelps", 4)

			local result, err = SeasonalEventService.DistributeSeasonRewards("player1")
			assert.is_nil(err)
			assert.equals(2, result.ChallengesDistributed)
			assert.equals(0, result.MilestonesDistributed)
			assert.equals(725, result.TotalCashDistributed)
			assert.equals(165, result.TotalExperienceDistributed)
		end)
	end)

	-- ========== End-to-End Full Year ==========

	describe("End-to-end full year with challenges and milestone", function()
		local function completeFullYear(playerId)
			-- Spring
			SeasonalEventService.TransitionSeason(playerId, "Spring")
			SeasonalEventService.RecordProgress(playerId, "SeasonalBuildPlacements", 20)
			SeasonalEventService.RecordProgress(playerId, "SeasonalChoresCompleted", 8)

			-- Summer
			currentTime = currentTime + 1000
			SeasonalEventService.TransitionSeason(playerId, "Summer")
			SeasonalEventService.RecordProgress(playerId, "SeasonalTenantHelps", 6)
			SeasonalEventService.RecordProgress(playerId, "SeasonalCraftingJobs", 5)

			-- Autumn
			currentTime = currentTime + 1000
			SeasonalEventService.TransitionSeason(playerId, "Autumn")
			SeasonalEventService.RecordProgress(playerId, "SeasonalCraftingJobs", 10)
			SeasonalEventService.RecordProgress(playerId, "SeasonalTradesCompleted", 3)

			-- Winter
			currentTime = currentTime + 1000
			SeasonalEventService.TransitionSeason(playerId, "Winter")
			SeasonalEventService.RecordProgress(playerId, "SeasonalChoresCompleted", 12)
			SeasonalEventService.RecordProgress(playerId, "SeasonalTenantHelps", 4)

			-- Transition to next Spring to finalize the year
			currentTime = currentTime + 1000
			SeasonalEventService.TransitionSeason(playerId, "Spring")
		end

		it("accumulates correct totals distributing season by season", function()
			-- Spring
			SeasonalEventService.TransitionSeason("player1", "Spring")
			SeasonalEventService.RecordProgress("player1", "SeasonalBuildPlacements", 20)
			SeasonalEventService.RecordProgress("player1", "SeasonalChoresCompleted", 8)
			local r1 = SeasonalEventService.DistributeSeasonRewards("player1")
			assert.equals(500, r1.TotalCashDistributed)
			assert.equals(125, r1.TotalExperienceDistributed)

			-- Summer
			currentTime = currentTime + 1000
			SeasonalEventService.TransitionSeason("player1", "Summer")
			SeasonalEventService.RecordProgress("player1", "SeasonalTenantHelps", 6)
			SeasonalEventService.RecordProgress("player1", "SeasonalCraftingJobs", 5)
			local r2 = SeasonalEventService.DistributeSeasonRewards("player1")
			assert.equals(600, r2.TotalCashDistributed)
			assert.equals(140, r2.TotalExperienceDistributed)

			-- Autumn
			currentTime = currentTime + 1000
			SeasonalEventService.TransitionSeason("player1", "Autumn")
			SeasonalEventService.RecordProgress("player1", "SeasonalCraftingJobs", 10)
			SeasonalEventService.RecordProgress("player1", "SeasonalTradesCompleted", 3)
			local r3 = SeasonalEventService.DistributeSeasonRewards("player1")
			assert.equals(700, r3.TotalCashDistributed)
			assert.equals(160, r3.TotalExperienceDistributed)

			-- Winter
			currentTime = currentTime + 1000
			SeasonalEventService.TransitionSeason("player1", "Winter")
			SeasonalEventService.RecordProgress("player1", "SeasonalChoresCompleted", 12)
			SeasonalEventService.RecordProgress("player1", "SeasonalTenantHelps", 4)
			local r4 = SeasonalEventService.DistributeSeasonRewards("player1")
			assert.equals(725, r4.TotalCashDistributed)
			assert.equals(165, r4.TotalExperienceDistributed)

			-- Complete the year cycle -> triggers "First Year" milestone
			currentTime = currentTime + 1000
			SeasonalEventService.TransitionSeason("player1", "Spring")
			local r5 = SeasonalEventService.DistributeSeasonRewards("player1")
			assert.equals(1, r5.MilestonesDistributed)
			assert.equals(500, r5.TotalCashDistributed)
			assert.equals(120, r5.TotalExperienceDistributed)

			-- Verify cumulative state
			local status = SeasonalEventService.GetStatus("player1")
			-- Total cash: 500 + 600 + 700 + 725 + 500 = 3025
			assert.equals(3025, status.TotalCashDistributed)
			-- Total xp: 125 + 140 + 160 + 165 + 120 = 710
			assert.equals(710, status.TotalExperienceDistributed)
		end)

		it("awards First Year milestone after 4 season transitions", function()
			completeFullYear("player1")

			local milestone = SeasonalEventService.GetMilestoneForCount(4)
			assert.is_not_nil(milestone)
			assert.equals("First Year", milestone.Label)
			assert.equals(500, milestone.BonusCash)
			assert.equals(120, milestone.BonusExperience)

			local result, err = SeasonalEventService.DistributeSeasonRewards("player1")
			assert.is_nil(err)
			-- All 8 challenges from Autumn+Winter should have been completed but
			-- challenges reset on season transition; only current season challenges
			-- are pending. The milestone should still be pending though.
			assert.is_true(result.MilestonesDistributed >= 1)

			local hasMilestone = false
			for _, detail in ipairs(result.Details) do
				if detail.Type == "milestone" and detail.Id == "4" then
					hasMilestone = true
				end
			end
			assert.is_true(hasMilestone)
		end)

		it("buffs are season-specific throughout all transitions", function()
			SeasonalEventService.TransitionSeason("player1", "Spring")
			assert.equals(1.15, SeasonalEventService.GetBuffMultiplier("player1", "XPMultiplier"))
			assert.equals(1.0, SeasonalEventService.GetBuffMultiplier("player1", "CashMultiplier"))

			currentTime = currentTime + 1000
			SeasonalEventService.TransitionSeason("player1", "Summer")
			assert.equals(1.20, SeasonalEventService.GetBuffMultiplier("player1", "CashMultiplier"))
			assert.equals(1.0, SeasonalEventService.GetBuffMultiplier("player1", "XPMultiplier"))

			currentTime = currentTime + 1000
			SeasonalEventService.TransitionSeason("player1", "Autumn")
			assert.equals(1.25, SeasonalEventService.GetBuffMultiplier("player1", "CraftSpeedMultiplier"))
			assert.equals(1.0, SeasonalEventService.GetBuffMultiplier("player1", "CashMultiplier"))

			currentTime = currentTime + 1000
			SeasonalEventService.TransitionSeason("player1", "Winter")
			assert.equals(1.20, SeasonalEventService.GetBuffMultiplier("player1", "XPMultiplier"))
			assert.equals(1.0, SeasonalEventService.GetBuffMultiplier("player1", "CraftSpeedMultiplier"))
		end)
	end)

	-- ========== Multi-Player Full-Cycle Isolation ==========

	describe("Multi-player full-cycle isolation", function()
		it("two players completing different seasons have independent rewards", function()
			-- Player1 completes Spring
			SeasonalEventService.TransitionSeason("player1", "Spring")
			SeasonalEventService.RecordProgress("player1", "SeasonalBuildPlacements", 20)
			SeasonalEventService.RecordProgress("player1", "SeasonalChoresCompleted", 8)

			-- Player2 completes Summer
			SeasonalEventService.TransitionSeason("player2", "Spring")
			currentTime = currentTime + 1000
			SeasonalEventService.TransitionSeason("player2", "Summer")
			SeasonalEventService.RecordProgress("player2", "SeasonalTenantHelps", 6)
			SeasonalEventService.RecordProgress("player2", "SeasonalCraftingJobs", 5)

			-- Distribute independently
			local r1, err1 = SeasonalEventService.DistributeSeasonRewards("player1")
			local r2, err2 = SeasonalEventService.DistributeSeasonRewards("player2")

			assert.is_nil(err1)
			assert.is_nil(err2)

			-- Player1 got Spring rewards
			assert.equals(500, r1.TotalCashDistributed)
			assert.equals(125, r1.TotalExperienceDistributed)

			-- Player2 got Summer rewards
			assert.equals(600, r2.TotalCashDistributed)
			assert.equals(140, r2.TotalExperienceDistributed)
		end)

		it("one player's distribution failure does not affect another", function()
			local callCount = 0
			SeasonalEventService._SetRewardExecutor(function(playerId, cash, xp, source)
				callCount = callCount + 1
				-- Fail only for player2
				if playerId == "player2" then
					return false, "SimulatedFailure"
				end
				return true, nil
			end)

			-- Both complete Spring challenges
			SeasonalEventService.TransitionSeason("player1", "Spring")
			SeasonalEventService.RecordProgress("player1", "SeasonalBuildPlacements", 20)

			SeasonalEventService.TransitionSeason("player2", "Spring")
			SeasonalEventService.RecordProgress("player2", "SeasonalBuildPlacements", 20)

			-- Player1 succeeds
			local r1, err1 = SeasonalEventService.DistributeSeasonRewards("player1")
			assert.is_nil(err1)
			assert.equals(1, r1.ChallengesDistributed)
			assert.equals(300, r1.TotalCashDistributed)

			-- Player2 fails
			local r2, err2 = SeasonalEventService.DistributeSeasonRewards("player2")
			assert.is_nil(r2)
			assert.equals("DistributionFailed", err2)

			-- Player1's state remains intact
			local status1 = SeasonalEventService.GetStatus("player1")
			assert.equals(300, status1.TotalCashDistributed)

			-- Player2 has no distributed rewards (rollback)
			local pending2 = SeasonalEventService.GetPendingRewards("player2")
			assert.equals(1, #pending2.Challenges)
		end)
	end)

	-- ========== Consecutive Years ==========

	describe("Consecutive full-year cycles", function()
		it("earns both First Year and Seasoned Veteran milestones after 2 full years", function()
			local seasons = { "Spring", "Summer", "Autumn", "Winter" }

			-- Complete 8 season transitions (2 full years)
			for i = 1, 9 do
				currentTime = currentTime + (i * 1000)
				local idx = ((i - 1) % 4) + 1
				SeasonalEventService.TransitionSeason("player1", seasons[idx])
			end

			-- Both milestones should be pending
			local result, err = SeasonalEventService.DistributeSeasonRewards("player1")
			assert.is_nil(err)
			assert.equals(2, result.MilestonesDistributed)
			-- 500 + 1000 = 1500 cash; 120 + 250 = 370 xp
			assert.equals(1500, result.TotalCashDistributed)
			assert.equals(370, result.TotalExperienceDistributed)

			local seen = {}
			for _, detail in ipairs(result.Details) do
				seen[detail.Id] = true
			end
			assert.is_true(seen["4"])  -- First Year
			assert.is_true(seen["8"])  -- Seasoned Veteran
		end)
	end)

	-- ========== Pending Rewards Accuracy ==========

	describe("Pending rewards across all seasons", function()
		it("reports pending rewards correctly for each season's challenges", function()
			-- Spring: complete one challenge, leave one pending
			SeasonalEventService.TransitionSeason("player1", "Spring")
			SeasonalEventService.RecordProgress("player1", "SeasonalBuildPlacements", 20)
			SeasonalEventService.RecordProgress("player1", "SeasonalChoresCompleted", 8)
			-- Claim only one
			SeasonalEventService.ClaimChallengeReward("player1", "spring_builder")

			local pending = SeasonalEventService.GetPendingRewards("player1")
			assert.equals(1, #pending.Challenges)
			assert.equals("spring_green", pending.Challenges[1].Id)
			assert.equals(200, pending.TotalPendingCash)
			assert.equals(50, pending.TotalPendingExperience)
		end)

		it("reports combined challenge and milestone pending rewards", function()
			local seasons = { "Spring", "Summer", "Autumn", "Winter" }
			-- Complete 4 transitions + back to Spring
			for i = 1, 5 do
				currentTime = currentTime + (i * 1000)
				local idx = ((i - 1) % 4) + 1
				SeasonalEventService.TransitionSeason("player1", seasons[idx])
			end

			-- Complete current Spring challenges
			SeasonalEventService.RecordProgress("player1", "SeasonalBuildPlacements", 20)
			SeasonalEventService.RecordProgress("player1", "SeasonalChoresCompleted", 8)

			local pending = SeasonalEventService.GetPendingRewards("player1")
			-- 2 challenges + 1 milestone
			assert.equals(2, #pending.Challenges)
			assert.equals(1, #pending.Milestones)
			-- 300 + 200 (challenges) + 500 (milestone) = 1000
			assert.equals(1000, pending.TotalPendingCash)
			-- 75 + 50 (challenges) + 120 (milestone) = 245
			assert.equals(245, pending.TotalPendingExperience)
		end)
	end)

	-- ========== Reward Executor Integration ==========

	describe("Custom reward executor across all seasons", function()
		it("executor receives correct amounts for each season's challenges", function()
			local executorLog = {}
			SeasonalEventService._SetRewardExecutor(function(playerId, cash, xp, source)
				table.insert(executorLog, {
					PlayerId = playerId,
					Cash = cash,
					XP = xp,
					Source = source,
				})
				return true, nil
			end)

			-- Spring
			SeasonalEventService.TransitionSeason("player1", "Spring")
			SeasonalEventService.RecordProgress("player1", "SeasonalBuildPlacements", 20)
			SeasonalEventService.RecordProgress("player1", "SeasonalChoresCompleted", 8)
			SeasonalEventService.DistributeSeasonRewards("player1")

			-- Summer
			currentTime = currentTime + 1000
			SeasonalEventService.TransitionSeason("player1", "Summer")
			SeasonalEventService.RecordProgress("player1", "SeasonalTenantHelps", 6)
			SeasonalEventService.RecordProgress("player1", "SeasonalCraftingJobs", 5)
			SeasonalEventService.DistributeSeasonRewards("player1")

			-- Autumn
			currentTime = currentTime + 1000
			SeasonalEventService.TransitionSeason("player1", "Autumn")
			SeasonalEventService.RecordProgress("player1", "SeasonalCraftingJobs", 10)
			SeasonalEventService.RecordProgress("player1", "SeasonalTradesCompleted", 3)
			SeasonalEventService.DistributeSeasonRewards("player1")

			-- Winter
			currentTime = currentTime + 1000
			SeasonalEventService.TransitionSeason("player1", "Winter")
			SeasonalEventService.RecordProgress("player1", "SeasonalChoresCompleted", 12)
			SeasonalEventService.RecordProgress("player1", "SeasonalTenantHelps", 4)
			SeasonalEventService.DistributeSeasonRewards("player1")

			-- 8 challenge distributions (2 per season)
			assert.equals(8, #executorLog)

			-- Verify all executor calls were for player1
			for _, entry in ipairs(executorLog) do
				assert.equals("player1", entry.PlayerId)
				assert.is_true(entry.Cash > 0)
				assert.is_true(entry.XP > 0)
			end

			-- Verify total cash and xp across all executor calls
			local totalCash = 0
			local totalXP = 0
			for _, entry in ipairs(executorLog) do
				totalCash = totalCash + entry.Cash
				totalXP = totalXP + entry.XP
			end
			-- 500 + 600 + 700 + 725 = 2525
			assert.equals(2525, totalCash)
			-- 125 + 140 + 160 + 165 = 590
			assert.equals(590, totalXP)
		end)
	end)

	-- ========== Notification Verification ==========

	describe("Notifications across full seasonal cycle", function()
		it("generates distribution notifications for each season", function()
			SeasonalEventService.TransitionSeason("player1", "Spring")
			SeasonalEventService.RecordProgress("player1", "SeasonalBuildPlacements", 20)
			SeasonalEventService.RecordProgress("player1", "SeasonalChoresCompleted", 8)
			SeasonalEventService._testNotifications = {}
			SeasonalEventService.DistributeSeasonRewards("player1")

			local n1 = #SeasonalEventService._testNotifications
			assert.is_true(n1 > 0)
			assert.equals("Rewards Distributed!", SeasonalEventService._testNotifications[1].Title)

			currentTime = currentTime + 1000
			SeasonalEventService.TransitionSeason("player1", "Summer")
			SeasonalEventService.RecordProgress("player1", "SeasonalTenantHelps", 6)
			SeasonalEventService.RecordProgress("player1", "SeasonalCraftingJobs", 5)
			SeasonalEventService._testNotifications = {}
			SeasonalEventService.DistributeSeasonRewards("player1")

			local n2 = #SeasonalEventService._testNotifications
			assert.is_true(n2 > 0)
			assert.equals("Rewards Distributed!", SeasonalEventService._testNotifications[1].Title)
		end)
	end)
end)
