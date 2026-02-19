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
