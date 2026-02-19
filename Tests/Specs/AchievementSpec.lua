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
			assert.equals(10, snapshot.TotalCount)
			assert.equals(0, snapshot.UnlockedCount)
			assert.equals(0, snapshot.ClaimedCount)
			assert.equals(10, #snapshot.Achievements)
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
end)
