-- Tests/Specs/AchievementSpec.lua
-- Behavioral tests for AchievementService (loaded via loadfile, no Roblox runtime)

local AchievementService = assert(loadfile("src/Server/Services/AchievementService.luau"))()

describe("AchievementService", function()
	local player
	local currentTime

	before_each(function()
		currentTime = 1000000
		AchievementService._ResetForTests()
		AchievementService._SetClock(function()
			return currentTime
		end)
		player = { UserId = 1, Name = "TestPlayer" }
	end)

	after_each(function()
		AchievementService._SetClock(nil)
	end)

	-- ========== Snapshot from empty state ==========

	describe("GetSnapshot", function()
		it("returns a snapshot with all definitions for a new player", function()
			local snapshot = AchievementService.GetSnapshot(player)
			assert.is_not_nil(snapshot)
			assert.equals(13, snapshot.TotalCount)
			assert.equals(0, snapshot.UnlockedCount)
			assert.equals(0, snapshot.ClaimedCount)
			assert.equals(13, #snapshot.Achievements)
		end)

		it("reports zero progress for a fresh player", function()
			local snapshot = AchievementService.GetSnapshot(player)
			for _, row in ipairs(snapshot.Achievements) do
				assert.equals(0, row.CurrentValue)
				assert.equals(0, row.ProgressValue)
				assert.is_false(row.IsUnlocked)
				assert.is_false(row.IsClaimed)
			end
		end)

		it("returns nil for nil player", function()
			local snapshot = AchievementService.GetSnapshot(nil)
			assert.is_nil(snapshot)
		end)
	end)

	describe("GetUnlockedAndInProgress", function()
		it("returns nil for nil player", function()
			local result = AchievementService.GetUnlockedAndInProgress(nil)
			assert.is_nil(result)
		end)

		it("returns empty lists for a new player", function()
			local result = AchievementService.GetUnlockedAndInProgress(player)
			assert.is_not_nil(result)
			assert.equals(0, result.UnlockedCount)
			assert.equals(0, result.InProgressCount)
			assert.equals(0, #result.Unlocked)
			assert.equals(0, #result.InProgress)
		end)

		it("separates unlocked achievements from in-progress achievements", function()
			AchievementService.RecordBuildPlaced(player, 25) -- unlocks builder_novice, progresses builder_pro
			AchievementService.RecordChoreCompleted(player) -- progresses chores_starter only

			local result = AchievementService.GetUnlockedAndInProgress(player)
			assert.equals(1, result.UnlockedCount)
			assert.equals(3, result.InProgressCount)

			local unlockedIds = {}
			for _, row in ipairs(result.Unlocked) do
				unlockedIds[row.Id] = true
			end
			assert.is_true(unlockedIds["builder_novice"])

			local inProgressIds = {}
			for _, row in ipairs(result.InProgress) do
				inProgressIds[row.Id] = true
				assert.is_false(row.IsUnlocked)
				assert.is_true(row.ProgressValue > 0)
			end
			assert.is_true(inProgressIds["builder_pro"])
			assert.is_true(inProgressIds["chores_starter"])
			assert.is_true(inProgressIds["chores_veteran"])
			assert.is_nil(inProgressIds["builder_novice"])
		end)
	end)

	describe("GetClaimableAchievements", function()
		it("returns nil for nil player", function()
			local result = AchievementService.GetClaimableAchievements(nil)
			assert.is_nil(result)
		end)

		it("returns empty claimable list for a new player", function()
			local result = AchievementService.GetClaimableAchievements(player)
			assert.is_not_nil(result)
			assert.equals(0, result.ClaimableCount)
			assert.equals(0, #result.Claimable)
		end)

		it("returns only unlocked but unclaimed achievements", function()
			AchievementService.RecordBuildPlaced(player, 25) -- unlock builder_novice
			AchievementService.RecordChoreCompleted(player) -- only progress chores

			local beforeClaim = AchievementService.GetClaimableAchievements(player)
			assert.equals(1, beforeClaim.ClaimableCount)
			assert.equals("builder_novice", beforeClaim.Claimable[1].Id)
			assert.is_true(beforeClaim.Claimable[1].IsUnlocked)
			assert.is_false(beforeClaim.Claimable[1].IsClaimed)

			AchievementService.ClaimAchievement(player, "builder_novice")
			local afterClaim = AchievementService.GetClaimableAchievements(player)
			assert.equals(0, afterClaim.ClaimableCount)
			assert.equals(0, #afterClaim.Claimable)
		end)
	end)

	-- ========== GetAchievementMetadata ==========

	describe("GetAchievementMetadata", function()
		it("returns the full definition for a valid achievement id", function()
			local meta = AchievementService.GetAchievementMetadata("builder_novice")
			assert.is_not_nil(meta)
			assert.equals("builder_novice", meta.Id)
			assert.equals("Blueprint Beginner", meta.Name)
			assert.equals("Place 25 objects in build mode.", meta.Description)
			assert.equals("Building", meta.Category)
			assert.equals("BuildPlacements", meta.StatKey)
			assert.equals(25, meta.TargetValue)
			assert.equals(10, meta.SortOrder)
			assert.is_not_nil(meta.Rewards)
			assert.equals(150, meta.Rewards.Cash)
			assert.equals(40, meta.Rewards.Experience)
		end)

		it("returns metadata for every known achievement id", function()
			local ids = {
				"builder_novice", "builder_pro",
				"chores_starter", "chores_veteran",
				"tenant_help_first", "tenant_help_expert",
				"crafting_novice", "crafting_expert",
				"level_5", "level_12",
			}
			for _, id in ipairs(ids) do
				local meta = AchievementService.GetAchievementMetadata(id)
				assert.is_not_nil(meta, "expected metadata for " .. id)
				assert.equals(id, meta.Id)
				assert.is_string(meta.Name)
				assert.is_string(meta.Description)
				assert.is_string(meta.Category)
				assert.is_string(meta.StatKey)
				assert.is_number(meta.TargetValue)
				assert.is_number(meta.SortOrder)
				assert.is_table(meta.Rewards)
			end
		end)

		it("returns nil for a non-existent achievement id", function()
			local meta = AchievementService.GetAchievementMetadata("totally_fake_id")
			assert.is_nil(meta)
		end)

		it("returns nil for an empty string id", function()
			local meta = AchievementService.GetAchievementMetadata("")
			assert.is_nil(meta)
		end)

		it("returns nil for a nil id", function()
			local meta = AchievementService.GetAchievementMetadata(nil)
			assert.is_nil(meta)
		end)

		it("returns nil for a numeric id", function()
			local meta = AchievementService.GetAchievementMetadata(42)
			assert.is_nil(meta)
		end)

		it("returns nil for a boolean id", function()
			local meta = AchievementService.GetAchievementMetadata(true)
			assert.is_nil(meta)
		end)

		it("returns nil for a table id", function()
			local meta = AchievementService.GetAchievementMetadata({})
			assert.is_nil(meta)
		end)

		it("returns a fresh table each call (not a shared reference)", function()
			local meta1 = AchievementService.GetAchievementMetadata("builder_novice")
			local meta2 = AchievementService.GetAchievementMetadata("builder_novice")
			assert.is_not_nil(meta1)
			assert.is_not_nil(meta2)
			assert.are_not.equal(meta1, meta2) -- different table references
			assert.equals(meta1.Id, meta2.Id)
		end)

		it("does not include player-specific state in the result", function()
			-- Record some progress first
			AchievementService.RecordBuildPlaced(player, 10)
			local meta = AchievementService.GetAchievementMetadata("builder_novice")
			-- Metadata should be purely static definition data
			assert.is_nil(meta.CurrentValue)
			assert.is_nil(meta.ProgressValue)
			assert.is_nil(meta.IsUnlocked)
			assert.is_nil(meta.IsClaimed)
			assert.is_nil(meta.UnlockedAt)
			assert.is_nil(meta.ClaimedAt)
		end)
	end)

	-- ========== GetAchievementsByCategory ==========

	describe("GetAchievementsByCategory", function()
		it("returns both building achievements for Building category", function()
			local results = AchievementService.GetAchievementsByCategory("Building")
			assert.equals(2, #results)
			assert.equals("builder_novice", results[1].Id)
			assert.equals("builder_pro", results[2].Id)
			for _, row in ipairs(results) do
				assert.equals("Building", row.Category)
			end
		end)

		it("returns both household achievements for Household category", function()
			local results = AchievementService.GetAchievementsByCategory("Household")
			assert.equals(2, #results)
			assert.equals("chores_starter", results[1].Id)
			assert.equals("chores_veteran", results[2].Id)
			for _, row in ipairs(results) do
				assert.equals("Household", row.Category)
			end
		end)

		it("returns both tenant achievements for Tenants category", function()
			local results = AchievementService.GetAchievementsByCategory("Tenants")
			assert.equals(2, #results)
			assert.equals("tenant_help_first", results[1].Id)
			assert.equals("tenant_help_expert", results[2].Id)
			for _, row in ipairs(results) do
				assert.equals("Tenants", row.Category)
			end
		end)

		it("returns both crafting achievements for Crafting category", function()
			local results = AchievementService.GetAchievementsByCategory("Crafting")
			assert.equals(2, #results)
			assert.equals("crafting_novice", results[1].Id)
			assert.equals("crafting_expert", results[2].Id)
			for _, row in ipairs(results) do
				assert.equals("Crafting", row.Category)
			end
		end)

		it("returns both progression achievements for Progression category", function()
			local results = AchievementService.GetAchievementsByCategory("Progression")
			assert.equals(2, #results)
			assert.equals("level_5", results[1].Id)
			assert.equals("level_12", results[2].Id)
			for _, row in ipairs(results) do
				assert.equals("Progression", row.Category)
			end
		end)

		it("returns empty list for unknown category", function()
			local results = AchievementService.GetAchievementsByCategory("UnknownCategory")
			assert.is_table(results)
			assert.equals(0, #results)
		end)

		it("matches categories case-insensitively", function()
			local results = AchievementService.GetAchievementsByCategory("building")
			assert.is_table(results)
			assert.equals(2, #results)
			assert.equals("builder_novice", results[1].Id)
			assert.equals("builder_pro", results[2].Id)
		end)

		it("ignores leading/trailing whitespace in category", function()
			local results = AchievementService.GetAchievementsByCategory("  Building  ")
			assert.is_table(results)
			assert.equals(2, #results)
			assert.equals("builder_novice", results[1].Id)
			assert.equals("builder_pro", results[2].Id)
		end)

		it("returns empty list for empty category string", function()
			local results = AchievementService.GetAchievementsByCategory("")
			assert.is_table(results)
			assert.equals(0, #results)
		end)

		it("returns empty list for nil category", function()
			local results = AchievementService.GetAchievementsByCategory(nil)
			assert.is_table(results)
			assert.equals(0, #results)
		end)

		it("returns empty list for non-string category", function()
			local results = AchievementService.GetAchievementsByCategory(123)
			assert.is_table(results)
			assert.equals(0, #results)
		end)

		it("returns fresh tables (no shared references)", function()
			local a = AchievementService.GetAchievementsByCategory("Building")
			local b = AchievementService.GetAchievementsByCategory("Building")
			assert.are_not.equal(a, b)
			assert.are_not.equal(a[1], b[1])
		end)
	end)

	-- ========== GetAchievementCategories ==========

	describe("GetAchievementCategories", function()
		it("returns all known categories in definition order", function()
			local categories = AchievementService.GetAchievementCategories()
			assert.equals(6, #categories)
			assert.equals("Building", categories[1])
			assert.equals("Household", categories[2])
			assert.equals("Tenants", categories[3])
			assert.equals("Crafting", categories[4])
			assert.equals("Progression", categories[5])
			assert.equals("Daily", categories[6])
		end)

		it("returns each category only once", function()
			local categories = AchievementService.GetAchievementCategories()
			local seen = {}
			for _, category in ipairs(categories) do
				assert.is_nil(seen[category], "duplicate category " .. tostring(category))
				seen[category] = true
			end
		end)

		it("returns a fresh table each call", function()
			local a = AchievementService.GetAchievementCategories()
			local b = AchievementService.GetAchievementCategories()
			assert.are_not.equal(a, b)
			assert.equals(a[1], b[1])
			a[1] = "Mutated"
			assert.equals("Building", b[1])
		end)
	end)

	-- ========== GetAchievementProgress ==========

	describe("GetAchievementProgress", function()
		it("returns nil for nil player", function()
			local progress = AchievementService.GetAchievementProgress(nil, "builder_novice")
			assert.is_nil(progress)
		end)

		it("returns nil for a non-existent achievement id", function()
			local progress = AchievementService.GetAchievementProgress(player, "nonexistent_achievement")
			assert.is_nil(progress)
		end)

		it("returns nil for empty string achievement id", function()
			local progress = AchievementService.GetAchievementProgress(player, "")
			assert.is_nil(progress)
		end)

		it("returns nil for non-string achievement id", function()
			local progress = AchievementService.GetAchievementProgress(player, 123)
			assert.is_nil(progress)
		end)

		it("returns 0 for a new player with no progress on an achievement", function()
			local progress = AchievementService.GetAchievementProgress(player, "builder_novice")
			assert.equals(0, progress)
		end)

		it("returns partial progress for an in-progress achievement", function()
			AchievementService.RecordBuildPlaced(player, 10)
			local progress = AchievementService.GetAchievementProgress(player, "builder_novice")
			assert.equals(10, progress)
		end)

		it("returns the target value for a fully unlocked achievement", function()
			AchievementService.RecordBuildPlaced(player, 25)
			local progress = AchievementService.GetAchievementProgress(player, "builder_novice")
			assert.equals(25, progress)
		end)

		it("clamps progress to target value when stat exceeds threshold", function()
			AchievementService.RecordBuildPlaced(player, 200)
			local progress = AchievementService.GetAchievementProgress(player, "builder_novice")
			-- builder_novice target is 25; once unlocked stat snaps to target
			assert.equals(25, progress)
		end)

		it("returns correct progress for a higher-tier in-progress achievement", function()
			AchievementService.RecordBuildPlaced(player, 30)
			-- builder_pro target is 150; 30 is partial progress
			local progress = AchievementService.GetAchievementProgress(player, "builder_pro")
			assert.equals(30, progress)
		end)

		it("returns correct progress for overwrite-max stat (level)", function()
			AchievementService.RecordLevelReached(player, 3)
			local progress = AchievementService.GetAchievementProgress(player, "level_5")
			assert.equals(3, progress)
		end)

		it("returns target value for a claimed achievement", function()
			AchievementService.RecordBuildPlaced(player, 25)
			AchievementService.ClaimAchievement(player, "builder_novice")
			local progress = AchievementService.GetAchievementProgress(player, "builder_novice")
			assert.equals(25, progress)
		end)

		it("returns independent progress per player", function()
			local player2 = { UserId = 99, Name = "OtherPlayer" }
			AchievementService.RecordBuildPlaced(player, 15)
			AchievementService.RecordBuildPlaced(player2, 5)

			local p1 = AchievementService.GetAchievementProgress(player, "builder_novice")
			local p2 = AchievementService.GetAchievementProgress(player2, "builder_novice")
			assert.equals(15, p1)
			assert.equals(5, p2)
		end)

		it("tracks progress independently across multi-tier achievements sharing one stat", function()
			AchievementService.RecordBuildPlaced(player, 25)

			local noviceProgress = AchievementService.GetAchievementProgress(player, "builder_novice")
			local proProgress = AchievementService.GetAchievementProgress(player, "builder_pro")

			assert.equals(25, noviceProgress)
			assert.equals(25, proProgress)
		end)

		it("clamps each multi-tier achievement at its own target", function()
			AchievementService.RecordBuildPlaced(player, 500)

			local noviceProgress = AchievementService.GetAchievementProgress(player, "builder_novice")
			local proProgress = AchievementService.GetAchievementProgress(player, "builder_pro")

			assert.equals(25, noviceProgress)
			assert.equals(150, proProgress)
		end)
	end)

	-- ========== GetPlayerAchievements ==========

	describe("GetPlayerAchievements", function()
		it("returns nil for nil player", function()
			local result = AchievementService.GetPlayerAchievements(nil)
			assert.is_nil(result)
		end)

		it("returns all achievement IDs with zero progress for a new player", function()
			local result = AchievementService.GetPlayerAchievements(player)
			assert.is_not_nil(result)
			assert.is_table(result)

			local expectedIds = {
				"builder_novice", "builder_pro",
				"chores_starter", "chores_veteran",
				"tenant_help_first", "tenant_help_expert",
				"crafting_novice", "crafting_expert",
				"level_5", "level_12",
			}
			for _, id in ipairs(expectedIds) do
				assert.equals(0, result[id], "expected 0 progress for " .. id)
			end
		end)

		it("returns exactly 13 entries matching the defined achievements", function()
			local result = AchievementService.GetPlayerAchievements(player)
			local count = 0
			for _ in pairs(result) do
				count = count + 1
			end
			assert.equals(13, count)
		end)

		it("returns mixed progress values after partial activity", function()
			AchievementService.RecordBuildPlaced(player, 10)
			AchievementService.RecordChoreCompleted(player)
			AchievementService.RecordChoreCompleted(player)
			AchievementService.RecordChoreCompleted(player)
			AchievementService.RecordLevelReached(player, 3)

			local result = AchievementService.GetPlayerAchievements(player)
			assert.is_not_nil(result)

			-- Building: 10 placements, both below targets
			assert.equals(10, result["builder_novice"])
			assert.equals(10, result["builder_pro"])

			-- Chores: 3 completed; targets are 10 and 50
			assert.equals(3, result["chores_starter"])
			assert.equals(3, result["chores_veteran"])

			-- Tenant help: no activity
			assert.equals(0, result["tenant_help_first"])
			assert.equals(0, result["tenant_help_expert"])

			-- Crafting: no activity
			assert.equals(0, result["crafting_novice"])
			assert.equals(0, result["crafting_expert"])

			-- Level: reached 3; targets are 5 and 12
			assert.equals(3, result["level_5"])
			assert.equals(3, result["level_12"])
		end)

		it("clamps progress at target for unlocked achievements", function()
			AchievementService.RecordBuildPlaced(player, 200) -- unlocks both building achievements
			local result = AchievementService.GetPlayerAchievements(player)

			assert.equals(25, result["builder_novice"])  -- clamped to target 25
			assert.equals(150, result["builder_pro"])     -- clamped to target 150
		end)

		it("returns correct progress after claiming achievements", function()
			AchievementService.RecordBuildPlaced(player, 25)
			AchievementService.ClaimAchievement(player, "builder_novice")
			local result = AchievementService.GetPlayerAchievements(player)

			-- Claimed achievement still reports its target progress
			assert.equals(25, result["builder_novice"])
			-- Unclaimed/in-progress still has correct value
			assert.equals(25, result["builder_pro"])
		end)

		it("returns independent results per player", function()
			local player2 = { UserId = 77, Name = "Player2" }
			AchievementService.RecordBuildPlaced(player, 15)
			AchievementService.RecordChoreCompleted(player2)

			local r1 = AchievementService.GetPlayerAchievements(player)
			local r2 = AchievementService.GetPlayerAchievements(player2)

			assert.equals(15, r1["builder_novice"])
			assert.equals(0, r1["chores_starter"])

			assert.equals(0, r2["builder_novice"])
			assert.equals(1, r2["chores_starter"])
		end)
	end)

	-- ========== GetStatsSummary ==========

	describe("GetStatsSummary", function()
		it("returns nil for nil player", function()
			local summary = AchievementService.GetStatsSummary(nil)
			assert.is_nil(summary)
		end)

		it("returns zero counts and 0% completion for a new player", function()
			local summary = AchievementService.GetStatsSummary(player)
			assert.is_not_nil(summary)
			assert.equals(13, summary.TotalCount)
			assert.equals(0, summary.UnlockedCount)
			assert.equals(0, summary.ClaimedCount)
			assert.equals(0, summary.CompletionPercent)
			assert.equals(0, summary.CashEarned)
			assert.equals(0, summary.XpEarned)
		end)

		it("reports correct total rewards available across all achievements", function()
			local summary = AchievementService.GetStatsSummary(player)
			-- Sum of all Cash rewards: 150+500+225+800+250+1200+175+900+350+1400+100+400+750 = 7200
			assert.equals(7200, summary.TotalCashAvailable)
			-- Sum of all XP rewards: 40+120+55+180+60+260+70+280+0+0+25+100+200 = 1390
			assert.equals(1390, summary.TotalXpAvailable)
		end)

		it("reports correct completion percentage after unlocking achievements", function()
			AchievementService.RecordBuildPlaced(player, 25)  -- unlocks builder_novice (1 of 13)
			local summary = AchievementService.GetStatsSummary(player)
			assert.equals(1, summary.UnlockedCount)
			assert.equals(8, summary.CompletionPercent)  -- 1/13 = 7.69% rounds to 8%
		end)

		it("rounds completion percentage to nearest integer", function()
			-- Unlock 3 of 13
			AchievementService.RecordBuildPlaced(player, 150) -- 2 building achievements
			AchievementService.RecordChoreCompleted(player)
			for _ = 1, 9 do
				AchievementService.RecordChoreCompleted(player)
			end
			-- Now chores_starter is also unlocked (10 chores)
			local summary = AchievementService.GetStatsSummary(player)
			assert.equals(3, summary.UnlockedCount)
			assert.equals(23, summary.CompletionPercent)  -- 3/13 = 23.08% rounds to 23%
		end)

		it("tracks earned rewards only from claimed achievements", function()
			AchievementService.RecordBuildPlaced(player, 25)
			-- Unlocked but not claimed: earned should still be 0
			local beforeClaim = AchievementService.GetStatsSummary(player)
			assert.equals(0, beforeClaim.CashEarned)
			assert.equals(0, beforeClaim.XpEarned)

			-- Claim the achievement
			AchievementService.ClaimAchievement(player, "builder_novice")
			local afterClaim = AchievementService.GetStatsSummary(player)
			assert.equals(150, afterClaim.CashEarned)
			assert.equals(40, afterClaim.XpEarned)
			assert.equals(1, afterClaim.ClaimedCount)
		end)

		it("accumulates earned rewards across multiple claims", function()
			AchievementService.RecordBuildPlaced(player, 150)
			AchievementService.ClaimAchievement(player, "builder_novice")
			AchievementService.ClaimAchievement(player, "builder_pro")

			local summary = AchievementService.GetStatsSummary(player)
			assert.equals(650, summary.CashEarned)   -- 150 + 500
			assert.equals(160, summary.XpEarned)      -- 40 + 120
			assert.equals(2, summary.ClaimedCount)
		end)

		it("includes per-category breakdown", function()
			local summary = AchievementService.GetStatsSummary(player)
			assert.is_table(summary.Categories)
			assert.is_not_nil(summary.Categories["Building"])
			assert.is_not_nil(summary.Categories["Household"])
			assert.is_not_nil(summary.Categories["Tenants"])
			assert.is_not_nil(summary.Categories["Crafting"])
			assert.is_not_nil(summary.Categories["Progression"])
		end)

		it("reports correct category totals", function()
			local summary = AchievementService.GetStatsSummary(player)
			assert.equals(2, summary.Categories["Building"].Total)
			assert.equals(2, summary.Categories["Household"].Total)
			assert.equals(2, summary.Categories["Tenants"].Total)
			assert.equals(2, summary.Categories["Crafting"].Total)
			assert.equals(2, summary.Categories["Progression"].Total)
		end)

		it("reports correct category unlocked counts after activity", function()
			AchievementService.RecordBuildPlaced(player, 150)  -- unlocks both building
			AchievementService.RecordLevelReached(player, 5)   -- unlocks level_5 only

			local summary = AchievementService.GetStatsSummary(player)
			assert.equals(2, summary.Categories["Building"].Unlocked)
			assert.equals(0, summary.Categories["Household"].Unlocked)
			assert.equals(0, summary.Categories["Tenants"].Unlocked)
			assert.equals(0, summary.Categories["Crafting"].Unlocked)
			assert.equals(1, summary.Categories["Progression"].Unlocked)
		end)

		it("reports correct category claimed counts", function()
			AchievementService.RecordBuildPlaced(player, 150)
			AchievementService.ClaimAchievement(player, "builder_novice")

			local summary = AchievementService.GetStatsSummary(player)
			assert.equals(1, summary.Categories["Building"].Claimed)
			assert.equals(0, summary.Categories["Household"].Claimed)
		end)

		it("reports 100% completion when all achievements unlocked", function()
			-- Unlock all 13 achievements
			AchievementService.RecordBuildPlaced(player, 150)         -- 2 building
			for _ = 1, 50 do
				AchievementService.RecordChoreCompleted(player)       -- 2 household
			end
			for _ = 1, 30 do
				AchievementService.RecordTenantHelpCompleted(player)  -- 2 tenant
			end
			for _ = 1, 40 do
				AchievementService.RecordCraftCompleted(player)       -- 2 crafting
			end
			AchievementService.RecordLevelReached(player, 12)         -- 2 progression
			for _ = 1, 7 do
				AchievementService.RecordDailyRewardClaimed(player)   -- daily_first + daily_week
			end
			AchievementService.RecordDailyRewardStreak(player, 14)    -- daily_streak_14

			local summary = AchievementService.GetStatsSummary(player)
			assert.equals(13, summary.UnlockedCount)
			assert.equals(100, summary.CompletionPercent)
		end)

		it("returns independent summaries per player", function()
			local player2 = { UserId = 42, Name = "Player2" }
			AchievementService.RecordBuildPlaced(player, 25)  -- unlock 1 for player

			local s1 = AchievementService.GetStatsSummary(player)
			local s2 = AchievementService.GetStatsSummary(player2)
			assert.equals(1, s1.UnlockedCount)
			assert.equals(0, s2.UnlockedCount)
			assert.equals(8, s1.CompletionPercent)
			assert.equals(0, s2.CompletionPercent)
		end)
	end)

	-- ========== Stat recording ==========

	describe("RecordBuildPlaced", function()
		it("increments BuildPlacements stat by 1 by default", function()
			AchievementService.RecordBuildPlaced(player)
			local snapshot = AchievementService.GetSnapshot(player)
			assert.equals(1, snapshot.Stats["BuildPlacements"])
		end)

		it("increments BuildPlacements stat by a custom quantity", function()
			AchievementService.RecordBuildPlaced(player, 10)
			local snapshot = AchievementService.GetSnapshot(player)
			assert.equals(10, snapshot.Stats["BuildPlacements"])
		end)

		it("treats nil quantity as 1", function()
			AchievementService.RecordBuildPlaced(player, nil)
			local snapshot = AchievementService.GetSnapshot(player)
			assert.equals(1, snapshot.Stats["BuildPlacements"])
		end)

		it("accumulates across multiple calls", function()
			AchievementService.RecordBuildPlaced(player, 5)
			AchievementService.RecordBuildPlaced(player, 3)
			local snapshot = AchievementService.GetSnapshot(player)
			assert.equals(8, snapshot.Stats["BuildPlacements"])
		end)
	end)

	describe("RecordChoreCompleted", function()
		it("increments ChoresCompleted stat", function()
			AchievementService.RecordChoreCompleted(player)
			AchievementService.RecordChoreCompleted(player)
			local snapshot = AchievementService.GetSnapshot(player)
			assert.equals(2, snapshot.Stats["ChoresCompleted"])
		end)
	end)

	describe("RecordTenantHelpCompleted", function()
		it("increments TenantHelpsCompleted stat", function()
			AchievementService.RecordTenantHelpCompleted(player)
			local snapshot = AchievementService.GetSnapshot(player)
			assert.equals(1, snapshot.Stats["TenantHelpsCompleted"])
		end)
	end)

	describe("RecordCraftCompleted", function()
		it("increments CraftingJobsCompleted stat", function()
			AchievementService.RecordCraftCompleted(player)
			local snapshot = AchievementService.GetSnapshot(player)
			assert.equals(1, snapshot.Stats["CraftingJobsCompleted"])
		end)
	end)

	describe("RecordLevelReached", function()
		it("records the highest level reached using overwrite-max semantics", function()
			AchievementService.RecordLevelReached(player, 3)
			local snapshot = AchievementService.GetSnapshot(player)
			assert.equals(3, snapshot.Stats["HighestLevelReached"])
		end)

		it("does not decrease level when a lower value is reported", function()
			AchievementService.RecordLevelReached(player, 8)
			AchievementService.RecordLevelReached(player, 3)
			local snapshot = AchievementService.GetSnapshot(player)
			assert.equals(8, snapshot.Stats["HighestLevelReached"])
		end)

		it("updates level when a higher value is reported", function()
			AchievementService.RecordLevelReached(player, 3)
			AchievementService.RecordLevelReached(player, 10)
			local snapshot = AchievementService.GetSnapshot(player)
			assert.equals(10, snapshot.Stats["HighestLevelReached"])
		end)
	end)

	-- ========== Auto-unlock at threshold ==========

	describe("auto-unlock", function()
		it("unlocks builder_novice when BuildPlacements reaches 25", function()
			AchievementService.RecordBuildPlaced(player, 25)
			local snapshot = AchievementService.GetSnapshot(player)
			local found = false
			for _, row in ipairs(snapshot.Achievements) do
				if row.Id == "builder_novice" then
					assert.is_true(row.IsUnlocked)
					assert.is_false(row.IsClaimed)
					assert.equals(25, row.CurrentValue)
					assert.equals(25, row.ProgressValue)
					found = true
				end
			end
			assert.is_true(found)
		end)

		it("does not unlock builder_novice below threshold", function()
			AchievementService.RecordBuildPlaced(player, 24)
			local snapshot = AchievementService.GetSnapshot(player)
			for _, row in ipairs(snapshot.Achievements) do
				if row.Id == "builder_novice" then
					assert.is_false(row.IsUnlocked)
					assert.equals(24, row.CurrentValue)
				end
			end
		end)

		it("unlocks builder_pro at 150 while builder_novice is already unlocked", function()
			AchievementService.RecordBuildPlaced(player, 150)
			local snapshot = AchievementService.GetSnapshot(player)
			assert.equals(2, snapshot.UnlockedCount) -- both building achievements
			for _, row in ipairs(snapshot.Achievements) do
				if row.Id == "builder_novice" or row.Id == "builder_pro" then
					assert.is_true(row.IsUnlocked)
				end
			end
		end)

		it("records unlock timestamp from clock", function()
			AchievementService.RecordBuildPlaced(player, 25)
			local snapshot = AchievementService.GetSnapshot(player)
			for _, row in ipairs(snapshot.Achievements) do
				if row.Id == "builder_novice" then
					assert.equals(currentTime, row.UnlockedAt)
				end
			end
		end)

		it("unlocks level_5 when level reaches 5 via overwrite-max", function()
			AchievementService.RecordLevelReached(player, 5)
			local snapshot = AchievementService.GetSnapshot(player)
			for _, row in ipairs(snapshot.Achievements) do
				if row.Id == "level_5" then
					assert.is_true(row.IsUnlocked)
				end
			end
		end)

		it("unlocks both level achievements when jumping to level 12", function()
			AchievementService.RecordLevelReached(player, 12)
			local snapshot = AchievementService.GetSnapshot(player)
			for _, row in ipairs(snapshot.Achievements) do
				if row.Id == "level_5" or row.Id == "level_12" then
					assert.is_true(row.IsUnlocked)
				end
			end
		end)
	end)

	-- ========== Claiming achievements ==========

	describe("ClaimAchievement", function()
		it("succeeds for an unlocked, unclaimed achievement", function()
			AchievementService.RecordBuildPlaced(player, 25)
			local ok, msg, data = AchievementService.ClaimAchievement(player, "builder_novice")
			assert.is_true(ok)
			assert.equals("Achievement claimed.", msg)
			assert.is_not_nil(data)
			assert.equals("builder_novice", data.AchievementId)
			assert.equals(150, data.RewardCash)
			assert.equals(40, data.RewardExperience)
		end)

		it("marks achievement as claimed in snapshot after claim", function()
			AchievementService.RecordBuildPlaced(player, 25)
			AchievementService.ClaimAchievement(player, "builder_novice")
			local snapshot = AchievementService.GetSnapshot(player)
			assert.equals(1, snapshot.ClaimedCount)
			for _, row in ipairs(snapshot.Achievements) do
				if row.Id == "builder_novice" then
					assert.is_true(row.IsClaimed)
					assert.equals(currentTime, row.ClaimedAt)
				end
			end
		end)

		it("credits cash reward into profile CurrencyState", function()
			AchievementService.RecordBuildPlaced(player, 25)
			AchievementService.ClaimAchievement(player, "builder_novice")
			local profile = AchievementService._GetTestProfile(player)
			assert.is_not_nil(profile.CurrencyState)
			assert.equals(150, profile.CurrencyState.Cash)
		end)

		it("rejects claiming an achievement that is not yet unlocked", function()
			local ok, msg = AchievementService.ClaimAchievement(player, "builder_novice")
			assert.is_false(ok)
			assert.equals("Achievement is not unlocked yet.", msg)
		end)

		it("rejects claiming an already claimed achievement", function()
			AchievementService.RecordBuildPlaced(player, 25)
			AchievementService.ClaimAchievement(player, "builder_novice")
			local ok, msg = AchievementService.ClaimAchievement(player, "builder_novice")
			assert.is_false(ok)
			assert.equals("Achievement already claimed.", msg)
		end)

		it("rejects claiming an unknown achievement id", function()
			local ok, msg = AchievementService.ClaimAchievement(player, "nonexistent_achievement")
			assert.is_false(ok)
			assert.equals("Achievement not found.", msg)
		end)

		it("rejects empty string achievement id", function()
			local ok, msg = AchievementService.ClaimAchievement(player, "")
			assert.is_false(ok)
			assert.equals("Invalid achievement id.", msg)
		end)

		it("rejects non-string achievement id", function()
			local ok, msg = AchievementService.ClaimAchievement(player, 123)
			assert.is_false(ok)
			assert.equals("Invalid achievement id.", msg)
		end)

		it("accumulates cash across multiple claims", function()
			AchievementService.RecordBuildPlaced(player, 150)
			AchievementService.ClaimAchievement(player, "builder_novice")
			AchievementService.ClaimAchievement(player, "builder_pro")
			local profile = AchievementService._GetTestProfile(player)
			assert.equals(650, profile.CurrencyState.Cash) -- 150 + 500
		end)
	end)

	-- ========== State initialization / normalization ==========

	describe("state normalization", function()
		it("initializes empty AchievementState from a blank profile", function()
			local snapshot = AchievementService.GetSnapshot(player)
			assert.is_not_nil(snapshot)
			assert.equals(0, snapshot.UnlockedCount)
		end)

		it("clamps negative stat values to zero", function()
			-- Directly manipulate test profile to inject bad data
			local profile = AchievementService._GetTestProfile(player)
			if not profile then
				-- Force profile creation
				AchievementService.GetSnapshot(player)
				profile = AchievementService._GetTestProfile(player)
			end
			profile.AchievementState = {
				Version = 1,
				Stats = { BuildPlacements = -10 },
				Unlocked = {},
				Claimed = {},
			}
			local snapshot = AchievementService.GetSnapshot(player)
			assert.equals(0, snapshot.Stats["BuildPlacements"])
		end)

		it("rounds fractional stat values to nearest integer", function()
			AchievementService.GetSnapshot(player) -- force profile creation
			local profile = AchievementService._GetTestProfile(player)
			profile.AchievementState = {
				Version = 1,
				Stats = { BuildPlacements = 24.7 },
				Unlocked = {},
				Claimed = {},
			}
			local snapshot = AchievementService.GetSnapshot(player)
			assert.equals(25, snapshot.Stats["BuildPlacements"])
		end)
	end)

	-- ========== Multi-player isolation ==========

	describe("multi-player isolation", function()
		it("tracks achievements independently per player", function()
			local player2 = { UserId = 2, Name = "Player2" }
			AchievementService.RecordBuildPlaced(player, 25)
			AchievementService.RecordChoreCompleted(player2)

			local snap1 = AchievementService.GetSnapshot(player)
			local snap2 = AchievementService.GetSnapshot(player2)

			assert.equals(25, snap1.Stats["BuildPlacements"])
			assert.is_nil(snap1.Stats["ChoresCompleted"])

			assert.is_nil(snap2.Stats["BuildPlacements"])
			assert.equals(1, snap2.Stats["ChoresCompleted"])
		end)

		it("does not unlock achievements for wrong player", function()
			local player2 = { UserId = 2, Name = "Player2" }
			AchievementService.RecordBuildPlaced(player, 25) -- unlocks builder_novice for player

			local snap2 = AchievementService.GetSnapshot(player2)
			assert.equals(0, snap2.UnlockedCount)
		end)
	end)

	-- ========== Multi-tier achievement behavior ==========

	describe("multi-tier achievements", function()
		it("only unlocks lower tier when stat is between thresholds", function()
			-- builder_novice = 25, builder_pro = 150
			AchievementService.RecordBuildPlaced(player, 30)
			local snapshot = AchievementService.GetSnapshot(player)
			assert.equals(1, snapshot.UnlockedCount) -- only novice
			for _, row in ipairs(snapshot.Achievements) do
				if row.Id == "builder_novice" then
					assert.is_true(row.IsUnlocked)
				end
				if row.Id == "builder_pro" then
					assert.is_false(row.IsUnlocked)
					assert.equals(30, row.CurrentValue)
				end
			end
		end)

		it("unlocks both tiers when stat exceeds higher threshold", function()
			AchievementService.RecordBuildPlaced(player, 200)
			local snapshot = AchievementService.GetSnapshot(player)
			for _, row in ipairs(snapshot.Achievements) do
				if row.Id == "builder_novice" or row.Id == "builder_pro" then
					assert.is_true(row.IsUnlocked)
				end
			end
		end)

		it("allows claiming each tier independently", function()
			AchievementService.RecordBuildPlaced(player, 200)

			local ok1, _, data1 = AchievementService.ClaimAchievement(player, "builder_novice")
			assert.is_true(ok1)
			assert.equals(150, data1.RewardCash)

			local ok2, _, data2 = AchievementService.ClaimAchievement(player, "builder_pro")
			assert.is_true(ok2)
			assert.equals(500, data2.RewardCash)

			local snapshot = AchievementService.GetSnapshot(player)
			assert.equals(2, snapshot.ClaimedCount)
		end)
	end)

	-- ========== Progress clamping ==========

	describe("progress display", function()
		it("clamps ProgressValue to TargetValue", function()
			AchievementService.RecordBuildPlaced(player, 50) -- exceeds 25 target for novice
			local snapshot = AchievementService.GetSnapshot(player)
			for _, row in ipairs(snapshot.Achievements) do
				if row.Id == "builder_novice" then
					-- Once unlocked, stat is snapped to target for clean display
					assert.is_true(row.ProgressValue <= row.TargetValue)
				end
			end
		end)
	end)

	-- ========== Notification integration ==========

	describe("notification integration", function()
		before_each(function()
			AchievementService._testNotifications = {}
		end)

		after_each(function()
			AchievementService._testNotifications = nil
		end)

		it("sends an unlock notification when an achievement is auto-unlocked", function()
			AchievementService.RecordBuildPlaced(player, 25) -- unlocks builder_novice
			local notifs = AchievementService._testNotifications
			assert.is_not_nil(notifs)
			assert.equals(1, #notifs)
			assert.equals("Achievement Unlocked!", notifs[1].Title)
			assert.equals("Achievement", notifs[1].Category)
			assert.is_not_nil(notifs[1].Metadata)
			assert.equals("builder_novice", notifs[1].Metadata.AchievementId)
			assert.equals("Blueprint Beginner", notifs[1].Metadata.AchievementName)
			assert.equals("Building", notifs[1].Metadata.Category)
			assert.equals("Unlocked", notifs[1].Metadata.Event)
		end)

		it("sends multiple unlock notifications when multiple achievements unlock at once", function()
			AchievementService.RecordBuildPlaced(player, 150) -- unlocks builder_novice AND builder_pro
			local notifs = AchievementService._testNotifications
			assert.is_not_nil(notifs)
			assert.equals(2, #notifs)

			local ids = {}
			for _, n in ipairs(notifs) do
				ids[n.Metadata.AchievementId] = true
				assert.equals("Achievement Unlocked!", n.Title)
				assert.equals("Unlocked", n.Metadata.Event)
			end
			assert.is_true(ids["builder_novice"])
			assert.is_true(ids["builder_pro"])
		end)

		it("does not send an unlock notification when stat is below threshold", function()
			AchievementService.RecordBuildPlaced(player, 10) -- below 25 threshold
			local notifs = AchievementService._testNotifications
			assert.equals(0, #notifs)
		end)

		it("sends a claim notification when an achievement is claimed", function()
			AchievementService.RecordBuildPlaced(player, 25)
			-- Clear the unlock notification
			AchievementService._testNotifications = {}

			AchievementService.ClaimAchievement(player, "builder_novice")
			local notifs = AchievementService._testNotifications
			assert.equals(1, #notifs)
			assert.equals("Achievement Claimed!", notifs[1].Title)
			assert.equals("Achievement", notifs[1].Category)
			assert.equals("Claimed", notifs[1].Metadata.Event)
			assert.equals("builder_novice", notifs[1].Metadata.AchievementId)
			assert.equals("Blueprint Beginner", notifs[1].Metadata.AchievementName)
			assert.equals(150, notifs[1].Metadata.RewardCash)
			assert.equals(40, notifs[1].Metadata.RewardExperience)
		end)

		it("includes reward text in claim notification body", function()
			AchievementService.RecordBuildPlaced(player, 25)
			AchievementService._testNotifications = {}

			AchievementService.ClaimAchievement(player, "builder_novice")
			local notifs = AchievementService._testNotifications
			assert.is_not_nil(notifs[1].Body)
			-- Body should mention cash and XP
			assert.truthy(string.find(notifs[1].Body, "150 Cash"))
			assert.truthy(string.find(notifs[1].Body, "40 XP"))
		end)

		it("does not send a claim notification when claim is rejected", function()
			-- Not unlocked yet
			AchievementService.ClaimAchievement(player, "builder_novice")
			local notifs = AchievementService._testNotifications
			assert.equals(0, #notifs)
		end)

		it("does not send a claim notification for double-claim", function()
			AchievementService.RecordBuildPlaced(player, 25)
			AchievementService.ClaimAchievement(player, "builder_novice")
			AchievementService._testNotifications = {}

			AchievementService.ClaimAchievement(player, "builder_novice")
			local notifs = AchievementService._testNotifications
			assert.equals(0, #notifs)
		end)

		it("does not send notifications when _testNotifications is nil", function()
			AchievementService._testNotifications = nil
			-- Should not error
			AchievementService.RecordBuildPlaced(player, 25)
			AchievementService.ClaimAchievement(player, "builder_novice")
			-- If we get here without error, notifications were silently skipped
			assert.is_nil(AchievementService._testNotifications)
		end)

		it("sends unlock notification with correct body text", function()
			AchievementService.RecordBuildPlaced(player, 25)
			local notifs = AchievementService._testNotifications
			assert.is_not_nil(notifs[1].Body)
			-- Body should contain the achievement name and description
			assert.truthy(string.find(notifs[1].Body, "Blueprint Beginner"))
			assert.truthy(string.find(notifs[1].Body, "Place 25 objects in build mode."))
		end)

		it("sends unlock notifications for level-based achievements", function()
			AchievementService.RecordLevelReached(player, 12) -- unlocks both level_5 and level_12
			local notifs = AchievementService._testNotifications
			assert.equals(2, #notifs)

			local ids = {}
			for _, n in ipairs(notifs) do
				ids[n.Metadata.AchievementId] = true
			end
			assert.is_true(ids["level_5"])
			assert.is_true(ids["level_12"])
		end)

		it("uses player UserId as PlayerId in notification", function()
			AchievementService.RecordBuildPlaced(player, 25)
			local notifs = AchievementService._testNotifications
			assert.equals(player.UserId, notifs[1].PlayerId)
		end)

		it("sends notifications independently per player", function()
			local player2 = { UserId = 88, Name = "Player2" }
			AchievementService.RecordBuildPlaced(player, 25)  -- unlock for player
			AchievementService.RecordBuildPlaced(player2, 25) -- unlock for player2

			local notifs = AchievementService._testNotifications
			assert.equals(2, #notifs)
			assert.equals(player.UserId, notifs[1].PlayerId)
			assert.equals(player2.UserId, notifs[2].PlayerId)
		end)

		it("handles claim notification for zero-XP achievements", function()
			AchievementService.RecordLevelReached(player, 5) -- level_5 has 0 XP reward
			AchievementService._testNotifications = {}

			AchievementService.ClaimAchievement(player, "level_5")
			local notifs = AchievementService._testNotifications
			assert.equals(1, #notifs)
			assert.equals("Claimed", notifs[1].Metadata.Event)
			assert.equals(350, notifs[1].Metadata.RewardCash)
			assert.equals(0, notifs[1].Metadata.RewardExperience)
			-- Body should mention Cash but not XP since XP is 0
			assert.truthy(string.find(notifs[1].Body, "350 Cash"))
		end)
	end)

	-- ========== Daily reward achievement recording ==========

	describe("RecordDailyRewardClaimed", function()
		it("increments DailyRewardsClaimed stat by 1", function()
			AchievementService.RecordDailyRewardClaimed(player)
			local snapshot = AchievementService.GetSnapshot(player)
			assert.equals(1, snapshot.Stats["DailyRewardsClaimed"])
		end)

		it("accumulates across multiple calls", function()
			for _ = 1, 5 do
				AchievementService.RecordDailyRewardClaimed(player)
			end
			local snapshot = AchievementService.GetSnapshot(player)
			assert.equals(5, snapshot.Stats["DailyRewardsClaimed"])
		end)

		it("unlocks daily_first after 1 claim", function()
			AchievementService.RecordDailyRewardClaimed(player)
			local snapshot = AchievementService.GetSnapshot(player)
			for _, row in ipairs(snapshot.Achievements) do
				if row.Id == "daily_first" then
					assert.is_true(row.IsUnlocked)
				end
			end
		end)

		it("does not unlock daily_week after only 3 claims", function()
			for _ = 1, 3 do
				AchievementService.RecordDailyRewardClaimed(player)
			end
			local snapshot = AchievementService.GetSnapshot(player)
			for _, row in ipairs(snapshot.Achievements) do
				if row.Id == "daily_week" then
					assert.is_false(row.IsUnlocked)
					assert.equals(3, row.ProgressValue)
				end
			end
		end)

		it("unlocks daily_week after 7 claims", function()
			for _ = 1, 7 do
				AchievementService.RecordDailyRewardClaimed(player)
			end
			local snapshot = AchievementService.GetSnapshot(player)
			for _, row in ipairs(snapshot.Achievements) do
				if row.Id == "daily_week" then
					assert.is_true(row.IsUnlocked)
				end
			end
		end)

		it("allows claiming daily_first reward", function()
			AchievementService.RecordDailyRewardClaimed(player)
			local ok, msg, data = AchievementService.ClaimAchievement(player, "daily_first")
			assert.is_true(ok)
			assert.equals(100, data.RewardCash)
			assert.equals(25, data.RewardExperience)
		end)
	end)

	describe("RecordDailyRewardStreak", function()
		it("records the longest streak using overwrite-max semantics", function()
			AchievementService.RecordDailyRewardStreak(player, 5)
			local snapshot = AchievementService.GetSnapshot(player)
			assert.equals(5, snapshot.Stats["DailyRewardLongestStreak"])
		end)

		it("does not decrease streak when a lower value is reported", function()
			AchievementService.RecordDailyRewardStreak(player, 10)
			AchievementService.RecordDailyRewardStreak(player, 3)
			local snapshot = AchievementService.GetSnapshot(player)
			assert.equals(10, snapshot.Stats["DailyRewardLongestStreak"])
		end)

		it("updates streak when a higher value is reported", function()
			AchievementService.RecordDailyRewardStreak(player, 5)
			AchievementService.RecordDailyRewardStreak(player, 14)
			local snapshot = AchievementService.GetSnapshot(player)
			assert.equals(14, snapshot.Stats["DailyRewardLongestStreak"])
		end)

		it("does not unlock daily_streak_14 below threshold", function()
			AchievementService.RecordDailyRewardStreak(player, 10)
			local snapshot = AchievementService.GetSnapshot(player)
			for _, row in ipairs(snapshot.Achievements) do
				if row.Id == "daily_streak_14" then
					assert.is_false(row.IsUnlocked)
					assert.equals(10, row.ProgressValue)
				end
			end
		end)

		it("unlocks daily_streak_14 when streak reaches 14", function()
			AchievementService.RecordDailyRewardStreak(player, 14)
			local snapshot = AchievementService.GetSnapshot(player)
			for _, row in ipairs(snapshot.Achievements) do
				if row.Id == "daily_streak_14" then
					assert.is_true(row.IsUnlocked)
				end
			end
		end)

		it("allows claiming daily_streak_14 reward", function()
			AchievementService.RecordDailyRewardStreak(player, 14)
			local ok, msg, data = AchievementService.ClaimAchievement(player, "daily_streak_14")
			assert.is_true(ok)
			assert.equals(750, data.RewardCash)
			assert.equals(200, data.RewardExperience)
		end)
	end)

	-- ========== Daily category filtering ==========

	describe("GetAchievementsByCategory for Daily", function()
		it("returns all three daily achievements for Daily category", function()
			local results = AchievementService.GetAchievementsByCategory("Daily")
			assert.equals(3, #results)
			assert.equals("daily_first", results[1].Id)
			assert.equals("daily_week", results[2].Id)
			assert.equals("daily_streak_14", results[3].Id)
			for _, row in ipairs(results) do
				assert.equals("Daily", row.Category)
			end
		end)

		it("matches Daily category case-insensitively", function()
			local results = AchievementService.GetAchievementsByCategory("daily")
			assert.equals(3, #results)
		end)
	end)

	-- ========== DailyRewardService integration ==========

	describe("DailyRewardService achievement integration", function()
		local DailyRewardService = assert(loadfile("src/Server/Services/DailyRewardService.luau"))()
		local HOUR = 3600

		before_each(function()
			AchievementService._ResetForTests()
			AchievementService._SetClock(function()
				return currentTime
			end)
			DailyRewardService._ResetForTests()
			DailyRewardService._SetClock(function()
				return currentTime
			end)
			DailyRewardService._SetAchievementService(AchievementService)
		end)

		after_each(function()
			DailyRewardService._SetClock(nil)
			DailyRewardService._SetAchievementService(nil)
		end)

		it("records DailyRewardsClaimed stat after a successful claim", function()
			DailyRewardService.ClaimReward(player)
			local snapshot = AchievementService.GetSnapshot(player)
			assert.equals(1, snapshot.Stats["DailyRewardsClaimed"])
		end)

		it("records DailyRewardLongestStreak after a successful claim", function()
			DailyRewardService.ClaimReward(player)
			local snapshot = AchievementService.GetSnapshot(player)
			assert.equals(1, snapshot.Stats["DailyRewardLongestStreak"])
		end)

		it("unlocks daily_first achievement on first daily reward claim", function()
			DailyRewardService.ClaimReward(player)
			local snapshot = AchievementService.GetSnapshot(player)
			for _, row in ipairs(snapshot.Achievements) do
				if row.Id == "daily_first" then
					assert.is_true(row.IsUnlocked)
				end
			end
		end)

		it("accumulates DailyRewardsClaimed across multiple claims", function()
			for day = 1, 3 do
				DailyRewardService.ClaimReward(player)
				if day < 3 then
					currentTime = currentTime + (21 * HOUR)
				end
			end
			local snapshot = AchievementService.GetSnapshot(player)
			assert.equals(3, snapshot.Stats["DailyRewardsClaimed"])
		end)

		it("unlocks daily_week after 7 daily reward claims", function()
			for day = 1, 7 do
				DailyRewardService.ClaimReward(player)
				if day < 7 then
					currentTime = currentTime + (21 * HOUR)
				end
			end
			local snapshot = AchievementService.GetSnapshot(player)
			for _, row in ipairs(snapshot.Achievements) do
				if row.Id == "daily_week" then
					assert.is_true(row.IsUnlocked)
				end
			end
		end)

		it("tracks longest streak via overwrite-max after streak resets", function()
			-- Build a 3-day streak
			for day = 1, 3 do
				DailyRewardService.ClaimReward(player)
				if day < 3 then
					currentTime = currentTime + (21 * HOUR)
				end
			end
			-- Let the streak expire (advance past 48h grace)
			currentTime = currentTime + (49 * HOUR)
			-- Start new streak (resets to 1)
			DailyRewardService.ClaimReward(player)

			local snapshot = AchievementService.GetSnapshot(player)
			-- Longest streak should still be 3 (overwrite-max won't decrease)
			assert.equals(3, snapshot.Stats["DailyRewardLongestStreak"])
		end)

		it("does not record achievements when AchievementService is not set", function()
			DailyRewardService._SetAchievementService(nil)
			DailyRewardService.ClaimReward(player)
			local snapshot = AchievementService.GetSnapshot(player)
			-- No DailyRewardsClaimed stat should exist
			assert.is_nil(snapshot.Stats["DailyRewardsClaimed"])
		end)
	end)
end)
