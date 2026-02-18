--!strict
-- Unit tests for SeasonalEventService

local SeasonalEventService = assert(loadfile("src/Server/Services/SeasonalEventService.luau"))()

describe("SeasonalEventService", function()
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

	-- ========== Season Transition ==========

	describe("TransitionSeason", function()
		it("initializes a player into Spring", function()
			local result, err = SeasonalEventService.TransitionSeason("player1", "Spring")
			assert.is_nil(err)
			assert.is_not_nil(result)
			assert.equals("Spring", result.NewSeason)
			assert.equals("Spring Bloom", result.SeasonName)
			assert.is_true(result.WasTransition)
			assert.equals(0, result.SeasonsCompleted)
		end)

		it("transitions from Spring to Summer and increments completed count", function()
			SeasonalEventService.TransitionSeason("player1", "Spring")
			currentTime = currentTime + 86400 -- advance 1 day
			local result, err = SeasonalEventService.TransitionSeason("player1", "Summer")
			assert.is_nil(err)
			assert.equals("Spring", result.PreviousSeason)
			assert.equals("Summer", result.NewSeason)
			assert.equals("Summer Heat", result.SeasonName)
			assert.equals(1, result.SeasonsCompleted)
		end)

		it("rejects invalid season ID", function()
			local result, err = SeasonalEventService.TransitionSeason("player1", "Monsoon")
			assert.is_nil(result)
			assert.equals("InvalidSeason", err)
		end)

		it("rejects nil player", function()
			local result, err = SeasonalEventService.TransitionSeason(nil, "Spring")
			assert.is_nil(result)
			assert.equals("InvalidPlayer", err)
		end)

		it("does not increment completed count when re-entering same season", function()
			SeasonalEventService.TransitionSeason("player1", "Spring")
			currentTime = currentTime + 100
			local result = SeasonalEventService.TransitionSeason("player1", "Spring")
			assert.equals(0, result.SeasonsCompleted)
		end)

		it("resets challenge progress on season change", function()
			SeasonalEventService.TransitionSeason("player1", "Spring")
			SeasonalEventService.RecordProgress("player1", "SeasonalBuildPlacements", 10)

			local progressBefore = SeasonalEventService.GetChallengeProgress("player1", "spring_builder")
			assert.equals(10, progressBefore.CurrentValue)

			SeasonalEventService.TransitionSeason("player1", "Summer")

			local progressAfter = SeasonalEventService.GetChallengeProgress("player1", "spring_builder")
			assert.is_nil(progressAfter) -- spring challenge not in summer
		end)

		it("returns buffs and challenges for new season", function()
			local result = SeasonalEventService.TransitionSeason("player1", "Autumn")
			assert.is_not_nil(result.Buffs)
			assert.equals(1, #result.Buffs)
			assert.equals("CraftSpeedMultiplier", result.Buffs[1].Type)
			assert.is_not_nil(result.Challenges)
			assert.equals(2, #result.Challenges)
		end)

		it("cycles through all four seasons correctly", function()
			local seasons = { "Spring", "Summer", "Autumn", "Winter" }
			for i, season in ipairs(seasons) do
				currentTime = currentTime + (i * 1000)
				local result = SeasonalEventService.TransitionSeason("player1", season)
				assert.equals(season, result.NewSeason)
			end
			local status = SeasonalEventService.GetStatus("player1")
			assert.equals("Winter", status.CurrentSeason)
			assert.equals(3, status.SeasonsCompleted) -- Spring->Summer->Autumn->Winter = 3 transitions
		end)
	end)

	-- ========== Challenge Progress ==========

	describe("RecordProgress", function()
		it("tracks progress for a seasonal stat", function()
			SeasonalEventService.TransitionSeason("player1", "Spring")
			SeasonalEventService.RecordProgress("player1", "SeasonalBuildPlacements", 5)

			local progress = SeasonalEventService.GetChallengeProgress("player1", "spring_builder")
			assert.is_not_nil(progress)
			assert.equals(5, progress.CurrentValue)
			assert.equals(20, progress.TargetValue)
			assert.is_false(progress.Completed)
		end)

		it("accumulates progress across multiple calls", function()
			SeasonalEventService.TransitionSeason("player1", "Spring")
			SeasonalEventService.RecordProgress("player1", "SeasonalBuildPlacements", 8)
			SeasonalEventService.RecordProgress("player1", "SeasonalBuildPlacements", 7)

			local progress = SeasonalEventService.GetChallengeProgress("player1", "spring_builder")
			assert.equals(15, progress.CurrentValue)
			assert.is_false(progress.Completed)
		end)

		it("completes a challenge when target is reached", function()
			SeasonalEventService.TransitionSeason("player1", "Spring")
			local result = SeasonalEventService.RecordProgress("player1", "SeasonalBuildPlacements", 20)

			assert.is_not_nil(result)
			assert.equals(1, #result)
			assert.equals("spring_builder", result[1].ChallengeId)
			assert.equals("Spring Construction", result[1].ChallengeName)
			assert.equals(300, result[1].RewardCash)
			assert.equals(75, result[1].RewardExperience)

			local progress = SeasonalEventService.GetChallengeProgress("player1", "spring_builder")
			assert.is_true(progress.Completed)
		end)

		it("completes a challenge when target is exceeded", function()
			SeasonalEventService.TransitionSeason("player1", "Spring")
			local result = SeasonalEventService.RecordProgress("player1", "SeasonalBuildPlacements", 25)

			assert.is_not_nil(result)
			assert.equals(1, #result)
			assert.equals("spring_builder", result[1].ChallengeId)
		end)

		it("does not re-complete an already completed challenge", function()
			SeasonalEventService.TransitionSeason("player1", "Spring")
			SeasonalEventService.RecordProgress("player1", "SeasonalBuildPlacements", 20)
			local result = SeasonalEventService.RecordProgress("player1", "SeasonalBuildPlacements", 5)

			assert.is_nil(result) -- no new completions
		end)

		it("tracks cumulative reward totals", function()
			SeasonalEventService.TransitionSeason("player1", "Spring")
			SeasonalEventService.RecordProgress("player1", "SeasonalBuildPlacements", 20)
			SeasonalEventService.RecordProgress("player1", "SeasonalChoresCompleted", 8)

			local status = SeasonalEventService.GetStatus("player1")
			assert.equals(2, status.TotalChallengesCompleted)
			assert.equals(500, status.TotalSeasonalCashEarned) -- 300 + 200
			assert.equals(125, status.TotalSeasonalExperienceEarned) -- 75 + 50
		end)

		it("returns nil for nil player", function()
			local result = SeasonalEventService.RecordProgress(nil, "SeasonalBuildPlacements", 5)
			assert.is_nil(result)
		end)

		it("returns nil for empty stat key", function()
			SeasonalEventService.TransitionSeason("player1", "Spring")
			local result = SeasonalEventService.RecordProgress("player1", "", 5)
			assert.is_nil(result)
		end)

		it("defaults amount to 1 when not specified", function()
			SeasonalEventService.TransitionSeason("player1", "Spring")
			SeasonalEventService.RecordProgress("player1", "SeasonalBuildPlacements")

			local progress = SeasonalEventService.GetChallengeProgress("player1", "spring_builder")
			assert.equals(1, progress.CurrentValue)
		end)
	end)

	-- ========== GetStatus ==========

	describe("GetStatus", function()
		it("returns full status snapshot", function()
			SeasonalEventService.TransitionSeason("player1", "Summer")
			local status = SeasonalEventService.GetStatus("player1")

			assert.is_not_nil(status)
			assert.equals("Summer", status.CurrentSeason)
			assert.equals("Summer Heat", status.SeasonName)
			assert.is_not_nil(status.Buffs)
			assert.equals(1, #status.Buffs)
			assert.is_not_nil(status.Challenges)
			assert.equals(2, #status.Challenges)
			assert.equals(0, status.TotalChallengesCompleted)
		end)

		it("returns nil for nil player", function()
			local status = SeasonalEventService.GetStatus(nil)
			assert.is_nil(status)
		end)

		it("shows challenge progress in status", function()
			SeasonalEventService.TransitionSeason("player1", "Summer")
			SeasonalEventService.RecordProgress("player1", "SeasonalTenantHelps", 3)

			local status = SeasonalEventService.GetStatus("player1")
			local found = false
			for _, challenge in ipairs(status.Challenges) do
				if challenge.Id == "summer_landlord" then
					assert.equals(3, challenge.CurrentValue)
					assert.equals(6, challenge.TargetValue)
					assert.is_false(challenge.Completed)
					found = true
				end
			end
			assert.is_true(found)
		end)
	end)

	-- ========== GetActiveBuffs ==========

	describe("GetActiveBuffs", function()
		it("returns buffs for the current season", function()
			SeasonalEventService.TransitionSeason("player1", "Spring")
			local buffs = SeasonalEventService.GetActiveBuffs("player1")

			assert.equals(1, #buffs)
			assert.equals("XPMultiplier", buffs[1].Type)
			assert.equals(1.15, buffs[1].Value)
		end)

		it("returns different buffs for different seasons", function()
			SeasonalEventService.TransitionSeason("player1", "Autumn")
			local buffs = SeasonalEventService.GetActiveBuffs("player1")

			assert.equals(1, #buffs)
			assert.equals("CraftSpeedMultiplier", buffs[1].Type)
			assert.equals(1.25, buffs[1].Value)
		end)

		it("returns empty table for nil player", function()
			local buffs = SeasonalEventService.GetActiveBuffs(nil)
			assert.equals(0, #buffs)
		end)
	end)

	-- ========== GetBuffMultiplier ==========

	describe("GetBuffMultiplier", function()
		it("returns the correct multiplier for active buff type", function()
			SeasonalEventService.TransitionSeason("player1", "Summer")
			local multiplier = SeasonalEventService.GetBuffMultiplier("player1", "CashMultiplier")
			assert.equals(1.20, multiplier)
		end)

		it("returns 1.0 for non-active buff type", function()
			SeasonalEventService.TransitionSeason("player1", "Summer")
			local multiplier = SeasonalEventService.GetBuffMultiplier("player1", "XPMultiplier")
			assert.equals(1.0, multiplier)
		end)

		it("returns 1.0 for nil player", function()
			local multiplier = SeasonalEventService.GetBuffMultiplier(nil, "XPMultiplier")
			assert.equals(1.0, multiplier)
		end)

		it("returns 1.0 for nil buff type", function()
			SeasonalEventService.TransitionSeason("player1", "Spring")
			local multiplier = SeasonalEventService.GetBuffMultiplier("player1", nil)
			assert.equals(1.0, multiplier)
		end)
	end)

	-- ========== Milestones ==========

	describe("Milestones", function()
		it("awards First Year milestone after 4 seasons completed", function()
			local seasons = { "Spring", "Summer", "Autumn", "Winter", "Spring" }
			for i, season in ipairs(seasons) do
				currentTime = currentTime + (i * 1000)
				SeasonalEventService.TransitionSeason("player1", season)
			end

			local status = SeasonalEventService.GetStatus("player1")
			assert.equals(4, status.SeasonsCompleted)
			-- Milestone cash should be added
			assert.equals(500, status.TotalSeasonalCashEarned)
			assert.equals(120, status.TotalSeasonalExperienceEarned)
		end)

		it("does not re-award a milestone on repeat", function()
			-- Complete 4 seasons
			local seasons = { "Spring", "Summer", "Autumn", "Winter", "Spring" }
			for i, season in ipairs(seasons) do
				currentTime = currentTime + (i * 1000)
				SeasonalEventService.TransitionSeason("player1", season)
			end

			-- Now transition again through another full cycle to reach 8
			local moreSessions = { "Summer", "Autumn", "Winter", "Spring" }
			for i, season in ipairs(moreSessions) do
				currentTime = currentTime + (i * 1000)
				SeasonalEventService.TransitionSeason("player1", season)
			end

			local status = SeasonalEventService.GetStatus("player1")
			assert.equals(8, status.SeasonsCompleted)
			-- Should have milestone 4 (500) + milestone 8 (1000)
			assert.equals(1500, status.TotalSeasonalCashEarned)
			assert.equals(370, status.TotalSeasonalExperienceEarned) -- 120 + 250
		end)

		it("returns milestone label in transition result", function()
			local seasons = { "Spring", "Summer", "Autumn", "Winter", "Spring" }
			local lastResult
			for i, season in ipairs(seasons) do
				currentTime = currentTime + (i * 1000)
				lastResult = SeasonalEventService.TransitionSeason("player1", season)
			end
			assert.equals("First Year", lastResult.MilestoneUnlocked)
		end)

		it("returns nil milestone for non-milestone transitions", function()
			local result = SeasonalEventService.TransitionSeason("player1", "Spring")
			assert.is_nil(result.MilestoneUnlocked)
		end)
	end)

	-- ========== Notifications ==========

	describe("Notifications", function()
		it("sends notification on season transition", function()
			SeasonalEventService.TransitionSeason("player1", "Spring")

			local notifs = SeasonalEventService._testNotifications
			assert.equals(1, #notifs)
			assert.equals("player1", notifs[1].PlayerId)
			assert.truthy(string.find(notifs[1].Title, "Spring Bloom"))
			assert.truthy(string.find(notifs[1].Body, "Renewal and growth"))
		end)

		it("sends notification on challenge completion", function()
			SeasonalEventService.TransitionSeason("player1", "Spring")
			SeasonalEventService._testNotifications = {} -- clear transition notification

			SeasonalEventService.RecordProgress("player1", "SeasonalBuildPlacements", 20)

			local notifs = SeasonalEventService._testNotifications
			assert.equals(1, #notifs)
			assert.equals("Challenge Complete!", notifs[1].Title)
			assert.truthy(string.find(notifs[1].Body, "Spring Construction"))
		end)

		it("includes milestone in season transition notification", function()
			local seasons = { "Spring", "Summer", "Autumn", "Winter" }
			for i, season in ipairs(seasons) do
				currentTime = currentTime + (i * 1000)
				SeasonalEventService.TransitionSeason("player1", season)
			end

			SeasonalEventService._testNotifications = {}
			currentTime = currentTime + 5000
			SeasonalEventService.TransitionSeason("player1", "Spring")

			local notifs = SeasonalEventService._testNotifications
			assert.equals(1, #notifs)
			assert.truthy(string.find(notifs[1].Body, "First Year"))
		end)

		it("calls external notification sink when set", function()
			local sinkCalls = {}
			SeasonalEventService._SetNotificationSink(function(playerId, title, body, metadata)
				table.insert(sinkCalls, { PlayerId = playerId, Title = title })
			end)

			SeasonalEventService.TransitionSeason("player1", "Winter")

			assert.equals(1, #sinkCalls)
			assert.equals("player1", sinkCalls[1].PlayerId)
		end)
	end)

	-- ========== Multi-Player Isolation ==========

	describe("Multi-player isolation", function()
		it("tracks seasons independently per player", function()
			SeasonalEventService.TransitionSeason("player1", "Spring")
			SeasonalEventService.TransitionSeason("player2", "Winter")

			local status1 = SeasonalEventService.GetStatus("player1")
			local status2 = SeasonalEventService.GetStatus("player2")

			assert.equals("Spring", status1.CurrentSeason)
			assert.equals("Winter", status2.CurrentSeason)
		end)

		it("tracks challenge progress independently per player", function()
			SeasonalEventService.TransitionSeason("player1", "Spring")
			SeasonalEventService.TransitionSeason("player2", "Spring")

			SeasonalEventService.RecordProgress("player1", "SeasonalBuildPlacements", 15)
			SeasonalEventService.RecordProgress("player2", "SeasonalBuildPlacements", 5)

			local p1 = SeasonalEventService.GetChallengeProgress("player1", "spring_builder")
			local p2 = SeasonalEventService.GetChallengeProgress("player2", "spring_builder")

			assert.equals(15, p1.CurrentValue)
			assert.equals(5, p2.CurrentValue)
		end)
	end)

	-- ========== GetNextSeason ==========

	describe("GetNextSeason", function()
		it("returns Summer after Spring", function()
			SeasonalEventService.TransitionSeason("player1", "Spring")
			assert.equals("Summer", SeasonalEventService.GetNextSeason("player1"))
		end)

		it("returns Autumn after Summer", function()
			SeasonalEventService.TransitionSeason("player1", "Summer")
			assert.equals("Autumn", SeasonalEventService.GetNextSeason("player1"))
		end)

		it("returns Winter after Autumn", function()
			SeasonalEventService.TransitionSeason("player1", "Autumn")
			assert.equals("Winter", SeasonalEventService.GetNextSeason("player1"))
		end)

		it("returns Spring after Winter (wraps)", function()
			SeasonalEventService.TransitionSeason("player1", "Winter")
			assert.equals("Spring", SeasonalEventService.GetNextSeason("player1"))
		end)

		it("returns nil for nil player", function()
			assert.is_nil(SeasonalEventService.GetNextSeason(nil))
		end)
	end)

	-- ========== GetAllSeasons ==========

	describe("GetAllSeasons", function()
		it("returns all four season definitions", function()
			local seasons = SeasonalEventService.GetAllSeasons()
			assert.equals(4, #seasons)
			assert.equals("Spring", seasons[1].Id)
			assert.equals("Summer", seasons[2].Id)
			assert.equals("Autumn", seasons[3].Id)
			assert.equals("Winter", seasons[4].Id)
		end)

		it("includes buff and challenge counts", function()
			local seasons = SeasonalEventService.GetAllSeasons()
			for _, season in ipairs(seasons) do
				assert.is_true(season.BuffCount >= 1)
				assert.is_true(season.ChallengeCount >= 2)
				assert.equals(5, season.DurationDays)
			end
		end)
	end)

	-- ========== GetMilestoneForCount ==========

	describe("GetMilestoneForCount", function()
		it("returns milestone for valid count", function()
			local m = SeasonalEventService.GetMilestoneForCount(4)
			assert.is_not_nil(m)
			assert.equals("First Year", m.Label)
			assert.equals(500, m.BonusCash)
		end)

		it("returns nil for non-milestone count", function()
			local m = SeasonalEventService.GetMilestoneForCount(3)
			assert.is_nil(m)
		end)

		it("returns milestone for 8 seasons", function()
			local m = SeasonalEventService.GetMilestoneForCount(8)
			assert.is_not_nil(m)
			assert.equals("Seasoned Veteran", m.Label)
		end)
	end)

	-- ========== Weather Integration ==========

	describe("Weather integration", function()
		it("transitions all tracked players when weather season changes", function()
			SeasonalEventService.TransitionSeason("player1", "Spring")
			SeasonalEventService.TransitionSeason("player2", "Spring")

			local transitioned, err = SeasonalEventService.HandleWeatherSeasonChanged("Summer")
			assert.is_nil(err)
			assert.equals(2, transitioned)

			local p1 = SeasonalEventService.GetStatus("player1")
			local p2 = SeasonalEventService.GetStatus("player2")
			assert.equals("Summer", p1.CurrentSeason)
			assert.equals("Summer", p2.CurrentSeason)
			assert.equals(1, p1.SeasonsCompleted)
			assert.equals(1, p2.SeasonsCompleted)
		end)

		it("ignores repeated weather season values without incrementing completed seasons", function()
			SeasonalEventService.TransitionSeason("player1", "Spring")
			local transitioned, err = SeasonalEventService.HandleWeatherSeasonChanged("Spring")
			assert.is_nil(err)
			assert.equals(1, transitioned)

			local status = SeasonalEventService.GetStatus("player1")
			assert.equals("Spring", status.CurrentSeason)
			assert.equals(0, status.SeasonsCompleted)
		end)

		it("subscribes to weather service updates in Init and auto-transitions", function()
			local listenerName
			local weatherCallback
			local mockWeatherService = {
				GetState = function()
					return { Season = "Spring" }
				end,
				SubscribeSeasonChanged = function(name, callback)
					listenerName = name
					weatherCallback = callback
				end,
			}

			SeasonalEventService.Init(mockWeatherService)
			SeasonalEventService.TransitionSeason("player1", "Spring")

			assert.equals("SeasonalEventService", listenerName)
			assert.is_not_nil(weatherCallback)

			weatherCallback("Autumn")

			local status = SeasonalEventService.GetStatus("player1")
			assert.equals("Autumn", status.CurrentSeason)
			assert.equals(1, status.SeasonsCompleted)
		end)
	end)

	-- ========== Edge Cases ==========

	describe("Edge cases", function()
		it("handles progress for stat not matching any challenge", function()
			SeasonalEventService.TransitionSeason("player1", "Spring")
			local result = SeasonalEventService.RecordProgress("player1", "NonExistentStat", 10)
			assert.is_nil(result) -- no completions
		end)

		it("GetChallengeProgress returns nil for non-existent challenge", function()
			SeasonalEventService.TransitionSeason("player1", "Spring")
			local result = SeasonalEventService.GetChallengeProgress("player1", "fake_challenge")
			assert.is_nil(result)
		end)

		it("preserves total stats across season transitions", function()
			SeasonalEventService.TransitionSeason("player1", "Spring")
			SeasonalEventService.RecordProgress("player1", "SeasonalBuildPlacements", 20)

			local status1 = SeasonalEventService.GetStatus("player1")
			assert.equals(300, status1.TotalSeasonalCashEarned)

			currentTime = currentTime + 1000
			SeasonalEventService.TransitionSeason("player1", "Summer")
			SeasonalEventService.RecordProgress("player1", "SeasonalTenantHelps", 6)

			local status2 = SeasonalEventService.GetStatus("player1")
			assert.equals(650, status2.TotalSeasonalCashEarned) -- 300 + 350
			assert.equals(155, status2.TotalSeasonalExperienceEarned) -- 75 + 80
			assert.equals(2, status2.TotalChallengesCompleted)
		end)

		it("handles negative amount gracefully", function()
			SeasonalEventService.TransitionSeason("player1", "Spring")
			SeasonalEventService.RecordProgress("player1", "SeasonalBuildPlacements", -5)

			local progress = SeasonalEventService.GetChallengeProgress("player1", "spring_builder")
			-- negative should be treated as default (1)
			assert.equals(1, progress.CurrentValue)
		end)

		it("handles zero amount as default 1", function()
			SeasonalEventService.TransitionSeason("player1", "Spring")
			SeasonalEventService.RecordProgress("player1", "SeasonalBuildPlacements", 0)

			local progress = SeasonalEventService.GetChallengeProgress("player1", "spring_builder")
			assert.equals(1, progress.CurrentValue)
		end)
	end)

	-- ========== _ResetForTests ==========

	describe("_ResetForTests", function()
		it("clears all player state", function()
			SeasonalEventService.TransitionSeason("player1", "Spring")
			SeasonalEventService.RecordProgress("player1", "SeasonalBuildPlacements", 10)

			SeasonalEventService._ResetForTests()

			-- Fresh state should show default
			local status = SeasonalEventService.GetStatus("player1")
			assert.equals("Spring", status.CurrentSeason)
			assert.equals(0, status.SeasonsCompleted)
			assert.equals(0, status.TotalChallengesCompleted)
		end)

		it("clears notifications", function()
			SeasonalEventService.TransitionSeason("player1", "Spring")
			assert.is_true(#SeasonalEventService._testNotifications > 0)

			SeasonalEventService._ResetForTests()
			assert.equals(0, #SeasonalEventService._testNotifications)
		end)
	end)
end)
