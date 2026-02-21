-- Tests/Specs/ProgressionSpec.lua
-- Behavioral tests for ProgressionService (loaded via loadfile, no Roblox runtime)

local ProgressionService = assert(loadfile("src/Server/Services/ProgressionService.luau"))()

describe("ProgressionService", function()
	local player
	local achievementCalls

	before_each(function()
		ProgressionService._ResetForTests()
		ProgressionService._testBroadcasts = {}
		achievementCalls = {}
		ProgressionService._SetAchievementSink(function(p, level)
			achievementCalls[#achievementCalls + 1] = { Player = p, Level = level }
		end)
		player = { UserId = 1, Name = "TestPlayer", _attributes = {} }
	end)

	-- ========== XP Curve ==========

	describe("XP curve", function()
		it("requires BaseExperience (90) XP for level 1", function()
			local xp = ProgressionService._XpForLevel(1)
			assert.equals(90, xp)
		end)

		it("grows exponentially with GrowthFactor 1.25", function()
			local xp1 = ProgressionService._XpForLevel(1)
			local xp2 = ProgressionService._XpForLevel(2)
			local xp3 = ProgressionService._XpForLevel(3)
			assert.equals(90, xp1)
			-- 90 * 1.25^1 = 112.5 -> 113
			assert.equals(113, xp2)
			-- 90 * 1.25^2 = 140.625 -> 141
			assert.equals(141, xp3)
		end)

		it("returns same value for level 0 and level 1", function()
			local xp0 = ProgressionService._XpForLevel(0)
			local xp1 = ProgressionService._XpForLevel(1)
			assert.equals(xp1, xp0)
		end)
	end)

	-- ========== computeProgress ==========

	describe("_ComputeProgress", function()
		it("returns level 1 for zero XP", function()
			local level, xpInto, xpForNext = ProgressionService._ComputeProgress(0)
			assert.equals(1, level)
			assert.equals(0, xpInto)
			assert.equals(90, xpForNext)
		end)

		it("stays level 1 with partial XP", function()
			local level, xpInto, xpForNext = ProgressionService._ComputeProgress(50)
			assert.equals(1, level)
			assert.equals(50, xpInto)
			assert.equals(90, xpForNext)
		end)

		it("reaches level 2 at exactly 90 XP", function()
			local level, xpInto, xpForNext = ProgressionService._ComputeProgress(90)
			assert.equals(2, level)
			assert.equals(0, xpInto)
			assert.equals(113, xpForNext)
		end)

		it("reaches level 3 at 90+113=203 XP", function()
			local level, xpInto, xpForNext = ProgressionService._ComputeProgress(203)
			assert.equals(3, level)
			assert.equals(0, xpInto)
			assert.equals(141, xpForNext)
		end)

		it("handles negative XP gracefully", function()
			local level, xpInto, xpForNext = ProgressionService._ComputeProgress(-100)
			assert.equals(1, level)
			assert.equals(0, xpInto)
			assert.equals(90, xpForNext)
		end)

		it("caps at MaxLevel (50)", function()
			-- Give an absurdly large amount of XP
			local level, xpInto, xpForNext = ProgressionService._ComputeProgress(999999999)
			assert.equals(50, level)
			assert.equals(0, xpInto)
			assert.equals(0, xpForNext)
		end)
	end)

	-- ========== Placement Reward Calculation ==========

	describe("_ComputePlacementReward", function()
		it("returns base + 1 cell for nil spec and nil quantity", function()
			local reward = ProgressionService._ComputePlacementReward(nil, nil)
			-- base=10, perCell=2, units=1 -> 10 + 2*1 = 12
			assert.equals(12, reward)
		end)

		it("scales with quantity", function()
			local reward = ProgressionService._ComputePlacementReward(nil, 5)
			-- 10 + 2*5 = 20
			assert.equals(20, reward)
		end)

		it("adds premium bonus for expensive items (Cost >= 1200)", function()
			local reward = ProgressionService._ComputePlacementReward({ Cost = 1200 }, 1)
			-- 10 + 2*1 + 15 = 27
			assert.equals(27, reward)
		end)

		it("does not add premium bonus for cheap items", function()
			local reward = ProgressionService._ComputePlacementReward({ Cost = 500 }, 1)
			-- 10 + 2*1 = 12
			assert.equals(12, reward)
		end)

		it("returns at least 1", function()
			local reward = ProgressionService._ComputePlacementReward(nil, 0)
			assert.is_true(reward >= 1)
		end)

		it("rounds fractional quantity to nearest integer", function()
			local reward = ProgressionService._ComputePlacementReward(nil, 3.7)
			-- quantity rounds to 4 -> 10 + 2*4 = 18
			assert.equals(18, reward)
		end)
	end)

	-- ========== GetLevel ==========

	describe("GetLevel", function()
		it("returns 1 for a brand new player", function()
			local level = ProgressionService.GetLevel(player)
			assert.equals(1, level)
		end)

		it("returns cached attribute if present", function()
			player._attributes.PlayerLevel = 7
			local level = ProgressionService.GetLevel(player)
			assert.equals(7, level)
		end)

		it("hydrates from state when no attribute exists", function()
			-- Award some XP first, then clear attributes to force re-hydration
			ProgressionService.AwardExperience(player, 90, "test")
			player._attributes = {}
			local level = ProgressionService.GetLevel(player)
			assert.equals(2, level)
		end)
	end)

	-- ========== AwardExperience ==========

	describe("AwardExperience", function()
		it("returns level 1 for zero XP award", function()
			local level = ProgressionService.AwardExperience(player, 0, "nothing")
			assert.equals(1, level)
		end)

		it("returns level 1 for negative XP award", function()
			local level = ProgressionService.AwardExperience(player, -50, "penalty")
			assert.equals(1, level)
		end)

		it("awards XP and increases level", function()
			local level = ProgressionService.AwardExperience(player, 90, "BuildPlacement")
			assert.equals(2, level)
		end)

		it("accumulates XP across multiple awards", function()
			ProgressionService.AwardExperience(player, 45, "first")
			local level = ProgressionService.AwardExperience(player, 45, "second")
			assert.equals(2, level)
		end)

		it("rounds fractional XP to nearest integer", function()
			ProgressionService.AwardExperience(player, 89.6, "almost")
			local profile = ProgressionService._GetTestProfile(player)
			assert.equals(90, profile.Experience)
		end)

		it("syncs player attributes after award", function()
			ProgressionService.AwardExperience(player, 50, "test")
			assert.equals(1, player._attributes.PlayerLevel)
			assert.equals(50, player._attributes.PlayerExperience)
			assert.equals(50, player._attributes.PlayerXPIntoLevel)
			assert.equals(90, player._attributes.PlayerXPForNext)
		end)

		it("broadcasts progression update to client", function()
			ProgressionService.AwardExperience(player, 50, "BuildPlacement")
			assert.equals(1, #ProgressionService._testBroadcasts)
			local bc = ProgressionService._testBroadcasts[1]
			assert.equals(player, bc.Player)
			assert.equals(1, bc.Payload.Level)
			assert.equals(50, bc.Payload.ExperienceTotal)
			assert.equals(50, bc.Payload.Delta)
			assert.equals("BuildPlacement", bc.Payload.Reason)
		end)

		it("calls achievement sink with new level", function()
			ProgressionService.AwardExperience(player, 90, "test")
			local found = false
			for _, call in ipairs(achievementCalls) do
				if call.Player == player and call.Level == 2 then
					found = true
				end
			end
			assert.is_true(found)
		end)

		it("returns 1 for nil player", function()
			local level = ProgressionService.AwardExperience(nil, 100, "test")
			assert.equals(1, level)
		end)
	end)

	-- ========== Level-Up Unlocks ==========

	describe("Level-up unlocks", function()
		it("unlocks level 2 items on reaching level 2", function()
			ProgressionService.AwardExperience(player, 90, "test")
			local profile = ProgressionService._GetTestProfile(player)
			assert.is_true(profile.UnlockedItems["GlassPane"] == true)
			assert.is_true(profile.UnlockedItems["FlatRoofEdge"] == true)
			assert.is_true(profile.UnlockedItems["GlassCoffeeTable"] == true)
		end)

		it("does not unlock level 3 items at level 2", function()
			ProgressionService.AwardExperience(player, 90, "test")
			local profile = ProgressionService._GetTestProfile(player)
			assert.is_nil(profile.UnlockedItems["StandardBed"])
		end)

		it("unlocks levels 2 through 5 items when jumping to level 5", function()
			-- Need enough XP to get to level 5
			-- Level 1: 90, Level 2: 113, Level 3: 141, Level 4: 176 -> total = 520
			ProgressionService.AwardExperience(player, 520, "mega_boost")
			local profile = ProgressionService._GetTestProfile(player)
			-- Level 2 items
			assert.is_true(profile.UnlockedItems["GlassPane"] == true)
			-- Level 3 items
			assert.is_true(profile.UnlockedItems["StandardBed"] == true)
			-- Level 4 items
			assert.is_true(profile.UnlockedItems["Bathtub"] == true)
			-- Level 5 items
			assert.is_true(profile.UnlockedItems["Computer"] == true)
		end)

		it("reports new unlocks in broadcast payload", function()
			ProgressionService.AwardExperience(player, 90, "test")
			assert.equals(1, #ProgressionService._testBroadcasts)
			local unlocked = ProgressionService._testBroadcasts[1].Payload.UnlockedItemIds
			assert.is_true(#unlocked > 0)
			-- Check for at least one level 2 unlock
			local foundGlassPane = false
			for _, id in ipairs(unlocked) do
				if id == "GlassPane" then
					foundGlassPane = true
				end
			end
			assert.is_true(foundGlassPane)
		end)

		it("does not re-unlock items on subsequent XP awards at same level", function()
			ProgressionService.AwardExperience(player, 90, "first")
			ProgressionService._testBroadcasts = {}
			-- Award more XP that doesn't cause another level-up
			ProgressionService.AwardExperience(player, 10, "small")
			local unlocked = ProgressionService._testBroadcasts[1].Payload.UnlockedItemIds
			assert.equals(0, #unlocked)
		end)
	end)

	-- ========== CanPlaceItem ==========

	describe("CanPlaceItem", function()
		it("allows items with no required level", function()
			local ok, err = ProgressionService.CanPlaceItem(player, nil, nil)
			assert.is_true(ok)
			assert.is_nil(err)
		end)

		it("allows items with RequiredLevel 1", function()
			local ok, err = ProgressionService.CanPlaceItem(player, { RequiredLevel = 1 }, "BasicWall")
			assert.is_true(ok)
			assert.is_nil(err)
		end)

		it("rejects items above current level", function()
			local ok, err = ProgressionService.CanPlaceItem(player, { RequiredLevel = 5 }, "Computer")
			assert.is_false(ok)
			assert.is_not_nil(err)
			assert.truthy(string.find(err, "level 5"))
		end)

		it("allows items at exact current level", function()
			ProgressionService.AwardExperience(player, 90, "test") -- Level 2
			local ok, err = ProgressionService.CanPlaceItem(player, { RequiredLevel = 2 }, "GlassPane")
			assert.is_true(ok)
			assert.is_nil(err)
		end)

		it("allows previously unlocked items by ID", function()
			-- Level up to 2 to unlock GlassPane
			ProgressionService.AwardExperience(player, 90, "test")
			-- GlassPane should be in RuntimeUnlockCache and pass even with a spec check
			local ok, err = ProgressionService.CanPlaceItem(player, { RequiredLevel = 2 }, "GlassPane")
			assert.is_true(ok)
			assert.is_nil(err)
		end)

		it("returns false with message for nil player", function()
			local ok, err = ProgressionService.CanPlaceItem(nil, nil, nil)
			assert.is_false(ok)
			assert.equals("Progression data unavailable.", err)
		end)

		it("handles non-table itemSpec gracefully", function()
			local ok, _ = ProgressionService.CanPlaceItem(player, "notatable", nil)
			assert.is_true(ok)
		end)

		it("handles NaN RequiredLevel gracefully", function()
			local ok, _ = ProgressionService.CanPlaceItem(player, { RequiredLevel = 0/0 }, nil)
			assert.is_true(ok)
		end)

		it("handles negative RequiredLevel gracefully", function()
			local ok, _ = ProgressionService.CanPlaceItem(player, { RequiredLevel = -3 }, nil)
			assert.is_true(ok)
		end)
	end)

	-- ========== RecordBuildPlacement ==========

	describe("RecordBuildPlacement", function()
		it("awards XP for a basic placement", function()
			ProgressionService.RecordBuildPlacement(player, nil, nil)
			local profile = ProgressionService._GetTestProfile(player)
			assert.equals(12, profile.Experience) -- base=10 + perCell=2*1
		end)

		it("awards more XP for multi-cell placements", function()
			ProgressionService.RecordBuildPlacement(player, nil, 10)
			local profile = ProgressionService._GetTestProfile(player)
			assert.equals(30, profile.Experience) -- 10 + 2*10
		end)

		it("awards premium bonus for expensive items", function()
			ProgressionService.RecordBuildPlacement(player, { Cost = 1500 }, 1)
			local profile = ProgressionService._GetTestProfile(player)
			assert.equals(27, profile.Experience) -- 10 + 2*1 + 15
		end)

		it("broadcasts with reason BuildPlacement", function()
			ProgressionService.RecordBuildPlacement(player, nil, 1)
			assert.equals(1, #ProgressionService._testBroadcasts)
			assert.equals("BuildPlacement", ProgressionService._testBroadcasts[1].Payload.Reason)
		end)
	end)

	-- ========== RecordChoreCompletion ==========

	describe("RecordChoreCompletion", function()
		it("awards ChoreCompleted XP (35)", function()
			ProgressionService.RecordChoreCompletion(player)
			local profile = ProgressionService._GetTestProfile(player)
			assert.equals(35, profile.Experience)
		end)

		it("broadcasts with reason ChoreCompleted", function()
			ProgressionService.RecordChoreCompletion(player)
			assert.equals(1, #ProgressionService._testBroadcasts)
			assert.equals("ChoreCompleted", ProgressionService._testBroadcasts[1].Payload.Reason)
		end)

		it("accumulates across multiple chore completions", function()
			ProgressionService.RecordChoreCompletion(player)
			ProgressionService.RecordChoreCompletion(player)
			ProgressionService.RecordChoreCompletion(player)
			local profile = ProgressionService._GetTestProfile(player)
			assert.equals(105, profile.Experience) -- 35 * 3
		end)
	end)

	-- ========== RecordTenantHelped ==========

	describe("RecordTenantHelped", function()
		it("awards TenantHelped XP (80)", function()
			ProgressionService.RecordTenantHelped(player)
			local profile = ProgressionService._GetTestProfile(player)
			assert.equals(80, profile.Experience)
		end)

		it("broadcasts with reason TenantHelped", function()
			ProgressionService.RecordTenantHelped(player)
			assert.equals(1, #ProgressionService._testBroadcasts)
			assert.equals("TenantHelped", ProgressionService._testBroadcasts[1].Payload.Reason)
		end)

		it("two tenant helps award 160 XP total", function()
			ProgressionService.RecordTenantHelped(player)
			ProgressionService.RecordTenantHelped(player)
			local profile = ProgressionService._GetTestProfile(player)
			assert.equals(160, profile.Experience)
		end)
	end)

	-- ========== Multi-player isolation ==========

	describe("Multi-player isolation", function()
		local player2

		before_each(function()
			player2 = { UserId = 2, Name = "TestPlayer2", _attributes = {} }
		end)

		it("maintains separate state per player", function()
			ProgressionService.AwardExperience(player, 200, "test")
			ProgressionService.AwardExperience(player2, 50, "test")
			local p1 = ProgressionService._GetTestProfile(player)
			local p2 = ProgressionService._GetTestProfile(player2)
			assert.equals(200, p1.Experience)
			assert.equals(50, p2.Experience)
		end)

		it("does not share unlock state between players", function()
			ProgressionService.AwardExperience(player, 90, "test") -- level 2
			ProgressionService.GetLevel(player2) -- hydrate player2's profile
			local p1 = ProgressionService._GetTestProfile(player)
			local p2 = ProgressionService._GetTestProfile(player2)
			assert.is_true(p1.UnlockedItems["GlassPane"] == true)
			assert.is_nil(p2.UnlockedItems["GlassPane"])
		end)
	end)

	-- ========== _ResetForTests ==========

	describe("_ResetForTests", function()
		it("clears all player data", function()
			ProgressionService.AwardExperience(player, 500, "test")
			ProgressionService._ResetForTests()
			ProgressionService._testBroadcasts = {}
			ProgressionService._SetAchievementSink(function(p, level)
				achievementCalls[#achievementCalls + 1] = { Player = p, Level = level }
			end)
			local profile = ProgressionService._GetTestProfile(player)
			assert.is_nil(profile)
		end)

		it("clears achievement sink", function()
			ProgressionService._ResetForTests()
			-- After reset, no achievement sink should be set
			-- Award XP - should not error even without sink
			ProgressionService._testBroadcasts = {}
			local level = ProgressionService.AwardExperience(player, 90, "test")
			assert.equals(2, level)
		end)
	end)

	-- ========== _GetTestProfile ==========

	describe("_GetTestProfile", function()
		it("returns nil for nil player", function()
			local profile = ProgressionService._GetTestProfile(nil)
			assert.is_nil(profile)
		end)

		it("returns nil for unknown player before any interaction", function()
			local unknown = { UserId = 999, Name = "Unknown" }
			local profile = ProgressionService._GetTestProfile(unknown)
			assert.is_nil(profile)
		end)

		it("returns profile after XP award", function()
			ProgressionService.AwardExperience(player, 50, "test")
			local profile = ProgressionService._GetTestProfile(player)
			assert.is_not_nil(profile)
			assert.equals(50, profile.Experience)
			assert.equals(1, profile.Level)
		end)
	end)

	-- ========== Init in test mode ==========

	describe("Init", function()
		it("does not error when called in test mode", function()
			assert.has_no_errors(function()
				ProgressionService.Init()
			end)
		end)
	end)

	-- ========== End-to-end progression scenario ==========

	describe("End-to-end scenario", function()
		it("player progresses through multiple levels via mixed actions", function()
			-- Start fresh at level 1
			assert.equals(1, ProgressionService.GetLevel(player))

			-- Complete a few chores (35 XP each)
			ProgressionService.RecordChoreCompletion(player) -- 35
			ProgressionService.RecordChoreCompletion(player) -- 70
			assert.equals(1, ProgressionService.GetLevel(player))

			-- Help a tenant (80 XP) -> total = 150, should be level 2 (need 90)
			ProgressionService.RecordTenantHelped(player)
			assert.equals(2, ProgressionService.GetLevel(player))

			-- Verify level 2 unlocks present
			local profile = ProgressionService._GetTestProfile(player)
			assert.is_true(profile.UnlockedItems["GlassPane"] == true)

			-- Place some builds
			ProgressionService.RecordBuildPlacement(player, nil, 5) -- 10+2*5=20 -> total=170
			ProgressionService.RecordBuildPlacement(player, { Cost = 1500 }, 3) -- 10+2*3+15=31 -> total=201

			-- After 201 XP: level 1 needs 90, level 2 needs 113 -> 203 for level 3
			-- We have 201, still level 2
			assert.equals(2, ProgressionService.GetLevel(player))

			-- One more small award to cross into level 3
			ProgressionService.AwardExperience(player, 2, "nudge") -- total = 203
			assert.equals(3, ProgressionService.GetLevel(player))

			-- Level 3 unlocks should now be present
			profile = ProgressionService._GetTestProfile(player)
			assert.is_true(profile.UnlockedItems["StandardBed"] == true)
			assert.is_true(profile.UnlockedItems["FlatRoofCap"] == true)
			assert.is_true(profile.UnlockedItems["KitchenCounter"] == true)

			-- Can place a level 3 item
			local ok, _ = ProgressionService.CanPlaceItem(player, { RequiredLevel = 3 }, "StandardBed")
			assert.is_true(ok)

			-- Cannot place a level 5 item
			local blocked, msg = ProgressionService.CanPlaceItem(player, { RequiredLevel = 5 }, "Computer")
			assert.is_false(blocked)
			assert.truthy(string.find(msg, "level 5"))
		end)
	end)
end)
