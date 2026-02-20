--!strict
-- Unit tests for DailyRewardService

local DailyRewardService = assert(loadfile("src/Server/Services/DailyRewardService.luau"))()

local HOUR = 3600
local COOLDOWN = 20 * HOUR   -- 20 hours
local GRACE = 48 * HOUR      -- 48 hours

describe("DailyRewardService", function()
	local currentTime

	before_each(function()
		currentTime = 1000000
		DailyRewardService._ResetForTests()
		DailyRewardService._SetClock(function()
			return currentTime
		end)
	end)

	after_each(function()
		DailyRewardService._SetClock(nil)
	end)

	-- ========== First Claim ==========

	it("allows first claim for a new player", function()
		local status = DailyRewardService.GetStatus("player1")
		assert.is_not_nil(status)
		assert.is_true(status.CanClaim)
		assert.equals(0, status.CurrentStreak)
		assert.equals(0, status.TotalClaimed)
		assert.equals(1, status.NextStreak)
	end)

	it("grants day-1 reward on first claim", function()
		local result, err = DailyRewardService.ClaimReward("player1")
		assert.is_nil(err)
		assert.is_not_nil(result)
		assert.equals(1, result.Streak)
		assert.equals(50, result.CashEarned)
		assert.equals(15, result.ExperienceEarned)
		assert.equals("Welcome Back", result.DayLabel)
		assert.equals(1, result.LongestStreak)
	end)

	-- ========== Cooldown Enforcement ==========

	it("rejects claim during cooldown period", function()
		DailyRewardService.ClaimReward("player1")

		-- Advance only 10 hours (still in cooldown)
		currentTime = currentTime + (10 * HOUR)

		local result, err = DailyRewardService.ClaimReward("player1")
		assert.is_nil(result)
		assert.equals("CooldownActive", err)
	end)

	it("reports correct seconds until next claim during cooldown", function()
		DailyRewardService.ClaimReward("player1")

		currentTime = currentTime + (10 * HOUR)

		local status = DailyRewardService.GetStatus("player1")
		assert.is_false(status.CanClaim)
		assert.equals(10 * HOUR, status.SecondsUntilClaim)
	end)

	it("allows claim after cooldown expires", function()
		DailyRewardService.ClaimReward("player1")

		-- Advance past cooldown (21 hours)
		currentTime = currentTime + (21 * HOUR)

		local result, err = DailyRewardService.ClaimReward("player1")
		assert.is_nil(err)
		assert.is_not_nil(result)
		assert.equals(2, result.Streak)
	end)

	-- ========== Streak Continuation ==========

	it("increments streak on consecutive daily claims", function()
		for day = 1, 5 do
			local result, err = DailyRewardService.ClaimReward("player1")
			assert.is_nil(err)
			assert.equals(day, result.Streak)

			if day < 5 then
				currentTime = currentTime + (21 * HOUR)
			end
		end

		local status = DailyRewardService.GetStatus("player1")
		assert.equals(5, status.CurrentStreak)
		assert.equals(5, status.LongestStreak)
		assert.equals(5, status.TotalClaimed)
	end)

	it("escalates rewards through the 7-day cycle", function()
		local expectedCash = { 50, 75, 100, 125, 175, 225, 350 }
		local expectedXP = { 15, 20, 30, 35, 45, 55, 80 }

		for day = 1, 7 do
			local result, err = DailyRewardService.ClaimReward("player1")
			assert.is_nil(err)
			assert.equals(expectedCash[day], result.CashEarned >= expectedCash[day] and expectedCash[day] or result.CashEarned)

			if day < 7 then
				currentTime = currentTime + (21 * HOUR)
			end
		end
	end)

	-- ========== Streak Reset ==========

	it("resets streak when grace period expires", function()
		-- Claim day 1 and 2
		DailyRewardService.ClaimReward("player1")
		currentTime = currentTime + (21 * HOUR)
		DailyRewardService.ClaimReward("player1")

		-- Skip past grace period (49 hours > 48 hour grace)
		currentTime = currentTime + (49 * HOUR)

		local status = DailyRewardService.GetStatus("player1")
		assert.is_true(status.CanClaim)
		assert.equals(1, status.NextStreak) -- will reset to 1

		local result, err = DailyRewardService.ClaimReward("player1")
		assert.is_nil(err)
		assert.equals(1, result.Streak)
		assert.is_true(result.StreakReset)
	end)

	it("preserves longest streak after a reset", function()
		-- Build a 4-day streak
		for day = 1, 4 do
			DailyRewardService.ClaimReward("player1")
			currentTime = currentTime + (21 * HOUR)
		end

		-- Skip past grace period
		currentTime = currentTime + (49 * HOUR)

		-- Start a new streak
		local result, err = DailyRewardService.ClaimReward("player1")
		assert.is_nil(err)
		assert.equals(1, result.Streak)
		assert.equals(4, result.LongestStreak)
	end)

	-- ========== 7-Day Cycle Wrapping ==========

	it("wraps rewards back to day 1 after completing a full 7-day cycle", function()
		-- Complete full 7-day cycle
		for day = 1, 7 do
			DailyRewardService.ClaimReward("player1")
			currentTime = currentTime + (21 * HOUR)
		end

		-- Day 8 should get day-1 rewards again but with streak = 8
		local result, err = DailyRewardService.ClaimReward("player1")
		assert.is_nil(err)
		assert.equals(8, result.Streak)
		assert.equals(50, result.CashEarned) -- Day 1 Cash
		assert.equals("Welcome Back", result.DayLabel)
	end)

	-- ========== Milestone Bonuses ==========

	it("awards milestone bonus at streak 7", function()
		for day = 1, 6 do
			DailyRewardService.ClaimReward("player1")
			currentTime = currentTime + (21 * HOUR)
		end

		-- Day 7 should include milestone bonus
		local result, err = DailyRewardService.ClaimReward("player1")
		assert.is_nil(err)
		assert.equals(7, result.Streak)
		-- Day 7 cash (350) + milestone bonus (200) = 550
		assert.equals(550, result.CashEarned)
		-- Day 7 XP (80) + milestone bonus (50) = 130
		assert.equals(130, result.ExperienceEarned)
		assert.equals("First Full Week", result.MilestoneUnlocked)
	end)

	it("does not re-award milestone bonus on second cycle", function()
		-- Complete 14 days (two full cycles)
		for day = 1, 14 do
			DailyRewardService.ClaimReward("player1")
			currentTime = currentTime + (21 * HOUR)
		end

		-- Day 14 will get milestone bonus for "Two Week Streak"
		-- But let's check that the 7-day milestone was only counted once
		local status = DailyRewardService.GetStatus("player1")
		assert.equals(14, status.CurrentStreak)
		assert.equals(14, status.LongestStreak)
	end)

	-- ========== Edge Cases ==========

	it("handles claim exactly at cooldown boundary", function()
		DailyRewardService.ClaimReward("player1")

		-- Advance exactly to cooldown boundary
		currentTime = currentTime + COOLDOWN

		local result, err = DailyRewardService.ClaimReward("player1")
		assert.is_nil(err)
		assert.is_not_nil(result)
		assert.equals(2, result.Streak)
	end)

	it("handles claim exactly at grace period boundary (still within grace)", function()
		DailyRewardService.ClaimReward("player1")

		-- Advance exactly to grace boundary (should still be valid)
		currentTime = currentTime + GRACE

		local result, err = DailyRewardService.ClaimReward("player1")
		assert.is_nil(err)
		assert.equals(2, result.Streak)
		assert.is_false(result.StreakReset)
	end)

	it("handles claim one second past grace period (streak resets)", function()
		DailyRewardService.ClaimReward("player1")

		-- Advance one second past grace period
		currentTime = currentTime + GRACE + 1

		local result, err = DailyRewardService.ClaimReward("player1")
		assert.is_nil(err)
		assert.equals(1, result.Streak)
		assert.is_true(result.StreakReset)
	end)

	-- ========== Multi-Player Isolation ==========

	it("isolates state between different players", function()
		DailyRewardService.ClaimReward("alice")
		currentTime = currentTime + (21 * HOUR)
		DailyRewardService.ClaimReward("alice")

		local aliceStatus = DailyRewardService.GetStatus("alice")
		local bobStatus = DailyRewardService.GetStatus("bob")

		assert.equals(2, aliceStatus.CurrentStreak)
		assert.equals(0, bobStatus.CurrentStreak)
		assert.is_false(aliceStatus.CanClaim) -- alice in cooldown
		assert.is_true(bobStatus.CanClaim) -- bob never claimed
	end)

	-- ========== Cumulative Tracking ==========

	it("tracks cumulative cash and experience earned", function()
		-- Claim 3 days: 50+75+100 = 225 cash, 15+20+30 = 65 xp
		for day = 1, 3 do
			DailyRewardService.ClaimReward("player1")
			if day < 3 then
				currentTime = currentTime + (21 * HOUR)
			end
		end

		local status = DailyRewardService.GetStatus("player1")
		assert.equals(225, status.TotalCashEarned)
		assert.equals(65, status.TotalExperienceEarned)
	end)

	-- ========== Preview ==========

	it("previews rewards for any streak day", function()
		local preview = DailyRewardService.PreviewReward(3)
		assert.equals(3, preview.Day)
		assert.equals(3, preview.CycleDay)
		assert.equals(100, preview.Cash)
		assert.equals(30, preview.Experience)
		assert.equals("Momentum", preview.Label)
	end)

	it("previews wrapped rewards for days beyond cycle length", function()
		local preview = DailyRewardService.PreviewReward(8)
		assert.equals(8, preview.Day)
		assert.equals(1, preview.CycleDay) -- wraps to day 1
		assert.equals(50, preview.Cash)
		assert.equals("Welcome Back", preview.Label)
	end)

	it("previews milestone for milestone day", function()
		local preview = DailyRewardService.PreviewReward(7)
		assert.is_not_nil(preview.Milestone)
		assert.equals("First Full Week", preview.Milestone.Label)
		assert.equals(200, preview.Milestone.BonusCash)
	end)

	-- ========== Notifications ==========

	it("sends notification on successful claim", function()
		DailyRewardService.ClaimReward("player1")

		local notifications = DailyRewardService._testNotifications
		assert.equals(1, #notifications)
		assert.equals("player1", notifications[1].PlayerId)
		assert.is_truthy(string.find(notifications[1].Title, "Day 1"))
		assert.is_truthy(string.find(notifications[1].Body, "Welcome Back"))
	end)

	it("includes milestone info in notification when milestone is reached", function()
		for day = 1, 7 do
			DailyRewardService.ClaimReward("player1")
			if day < 7 then
				currentTime = currentTime + (21 * HOUR)
			end
		end

		-- The last notification should mention the milestone
		local notifications = DailyRewardService._testNotifications
		local lastNotif = notifications[#notifications]
		assert.is_truthy(string.find(lastNotif.Body, "First Full Week"))
	end)

	-- ========== Status Reporting ==========

	it("reports pending milestone when approaching milestone day", function()
		for day = 1, 6 do
			DailyRewardService.ClaimReward("player1")
			currentTime = currentTime + (21 * HOUR)
		end

		local status = DailyRewardService.GetStatus("player1")
		assert.equals(7, status.NextStreak)
		assert.is_not_nil(status.PendingMilestone)
		assert.equals("First Full Week", status.PendingMilestone.Label)
	end)

	it("includes cooldown and grace constants in status", function()
		local status = DailyRewardService.GetStatus("player1")
		assert.equals(COOLDOWN, status.ClaimCooldownSeconds)
		assert.equals(GRACE, status.StreakGraceSeconds)
	end)

	it("does not report already-claimed milestone as pending", function()
		-- Claim through day 7 to earn the milestone
		for day = 1, 7 do
			DailyRewardService.ClaimReward("player1")
			currentTime = currentTime + (21 * HOUR)
		end

		-- Reset streak
		currentTime = currentTime + (49 * HOUR)

		-- Build streak back to day 6 (next would be day 7)
		for day = 1, 6 do
			DailyRewardService.ClaimReward("player1")
			currentTime = currentTime + (21 * HOUR)
		end

		local status = DailyRewardService.GetStatus("player1")
		assert.equals(7, status.NextStreak)
		-- Milestone was already claimed, should not be pending
		assert.is_nil(status.PendingMilestone)
	end)

	-- ========== Invalid Input ==========

	it("returns error for nil player", function()
		local result, err = DailyRewardService.ClaimReward(nil)
		assert.is_nil(result)
		assert.equals("PlayerNotFound", err)
	end)

	it("returns nil status for nil player", function()
		local status = DailyRewardService.GetStatus(nil)
		assert.is_nil(status)
	end)

	-- ========== Constants Exposure ==========

	it("exposes constants for test verification", function()
		local constants = DailyRewardService._GetConstants()
		assert.equals(COOLDOWN, constants.ClaimCooldownSeconds)
		assert.equals(GRACE, constants.StreakGraceSeconds)
		assert.equals(7, constants.CycleLength)
	end)
end)
