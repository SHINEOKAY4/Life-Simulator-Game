-- Tests/Specs/CraftingSkillPanelSpec.lua
-- Validates crafting skill progression panel: XP math, skill summary payload shape,
-- and source-level wiring for packets, service handler, and UI module.

local function readFile(path)
	local f = io.open(path, "r")
	if not f then
		return nil
	end
	local content = f:read("*a")
	f:close()
	return content
end

-- Skill XP math replicated from CraftingService (pure Lua, no Roblox deps)
local SKILL_BASE_XP = 45
local SKILL_GROWTH = 1.24
local SKILL_MAX_LEVEL = 50

local function skillXpForLevel(level)
	if level <= 1 then
		return math.floor(SKILL_BASE_XP + 0.5)
	end
	return math.floor(SKILL_BASE_XP * (SKILL_GROWTH ^ (level - 1)) + 0.5)
end

local function computeSkillLevel(totalExperience)
	local level = 1
	local remaining = math.max(0, math.floor(totalExperience + 0.5))
	local requirement = skillXpForLevel(level)

	while level < SKILL_MAX_LEVEL and remaining >= requirement do
		remaining = remaining - requirement
		level = level + 1
		requirement = skillXpForLevel(level)
	end

	if level >= SKILL_MAX_LEVEL then
		remaining = 0
		requirement = 0
	end

	return level, remaining, requirement
end

local DEFAULT_SKILLS = { "Survival", "Carpentry", "Cooking", "Smithing" }

local function buildSkillSummary(skillsData)
	local skills = {}
	for _, skillId in ipairs(DEFAULT_SKILLS) do
		local entry = skillsData[skillId] or { Experience = 0 }
		local experience = entry.Experience or 0
		local level, xpIntoLevel, xpForNext = computeSkillLevel(experience)
		table.insert(skills, {
			SkillId = skillId,
			Level = level,
			Experience = experience,
			ExperienceIntoLevel = xpIntoLevel,
			ExperienceForNext = xpForNext,
		})
	end
	return skills
end

describe("CraftingSkillPanel", function()
	describe("skill XP math", function()
		it("level 1 requires 45 XP", function()
			assert.equals(45, skillXpForLevel(1))
		end)

		it("new player starts at level 1 with 0 XP into level", function()
			local level, xpInto, xpForNext = computeSkillLevel(0)
			assert.equals(1, level)
			assert.equals(0, xpInto)
			assert.equals(45, xpForNext)
		end)

		it("exactly 45 XP advances to level 2", function()
			local level, xpInto, xpForNext = computeSkillLevel(45)
			assert.equals(2, level)
			assert.equals(0, xpInto)
			-- level 2 cost = floor(45 * 1.24^1 + 0.5) = floor(56.3) = 56
			assert.equals(56, xpForNext)
		end)

		it("partial XP into a level is tracked correctly", function()
			-- 60 total: 45 used for Lv1, 15 remaining into Lv2 (costs 56)
			local level, xpInto, xpForNext = computeSkillLevel(60)
			assert.equals(2, level)
			assert.equals(15, xpInto)
			assert.equals(56, xpForNext)
		end)

		it("crossing two level thresholds: 101 XP reaches level 3 at 0 into level", function()
			-- Lv1=45, Lv2=56 => 45+56=101 brings player to Lv3 with 0 XP into it
			local level, xpInto = computeSkillLevel(101)
			assert.equals(3, level)
			assert.equals(0, xpInto)
		end)

		it("XP requirement grows each level", function()
			local prev = skillXpForLevel(1)
			for lvl = 2, 10 do
				local curr = skillXpForLevel(lvl)
				assert.is_true(
					curr > prev,
					string.format("Lv%d cost should exceed Lv%d", lvl, lvl - 1)
				)
				prev = curr
			end
		end)

		it("max level caps XP remainder and next-level requirement at 0", function()
			-- Reaching Lv50 with 1.24x exponential growth requires ~5.7M XP;
			-- 10M guarantees the cap is hit.
			local level, xpInto, xpForNext = computeSkillLevel(10000000)
			assert.equals(SKILL_MAX_LEVEL, level)
			assert.equals(0, xpInto)
			assert.equals(0, xpForNext)
		end)
	end)

	describe("skill summary payload", function()
		it("includes all four default skills", function()
			local summary = buildSkillSummary({})
			assert.equals(4, #summary)
		end)

		it("each entry has the required fields with correct types", function()
			local summary = buildSkillSummary({})
			for _, entry in ipairs(summary) do
				assert.equals("string", type(entry.SkillId))
				assert.equals("number", type(entry.Level))
				assert.equals("number", type(entry.Experience))
				assert.equals("number", type(entry.ExperienceIntoLevel))
				assert.equals("number", type(entry.ExperienceForNext))
			end
		end)

		it("defaults missing skill data to level 1 with 0 XP", function()
			local summary = buildSkillSummary({})
			for _, entry in ipairs(summary) do
				assert.equals(1, entry.Level)
				assert.equals(0, entry.Experience)
				assert.equals(0, entry.ExperienceIntoLevel)
			end
		end)

		it("correctly reflects XP gains for a specific skill", function()
			local summary = buildSkillSummary({ Survival = { Experience = 60 } })
			local survival
			for _, entry in ipairs(summary) do
				if entry.SkillId == "Survival" then
					survival = entry
					break
				end
			end
			assert.is_not_nil(survival)
			assert.equals(2, survival.Level)
			assert.equals(15, survival.ExperienceIntoLevel)
			assert.equals(56, survival.ExperienceForNext)
		end)

		it("other skills are unaffected when one skill has XP", function()
			local summary = buildSkillSummary({ Survival = { Experience = 200 } })
			for _, entry in ipairs(summary) do
				if entry.SkillId ~= "Survival" then
					assert.equals(1, entry.Level)
					assert.equals(0, entry.Experience)
				end
			end
		end)

		it("SkillId values match the four default skill names", function()
			local summary = buildSkillSummary({})
			local ids = {}
			for _, entry in ipairs(summary) do
				ids[entry.SkillId] = true
			end
			assert.is_truthy(ids["Survival"])
			assert.is_truthy(ids["Carpentry"])
			assert.is_truthy(ids["Cooking"])
			assert.is_truthy(ids["Smithing"])
		end)
	end)

	describe("packet and source wiring", function()
		it("GetSkillSummary packet is defined in CraftingPackets", function()
			local src = readFile("src/Network/CraftingPackets.luau")
			assert.is_truthy(src)
			assert.is_truthy(string.find(src, "GetSkillSummary", 1, true))
		end)

		it("SkillSummaryUpdated packet is defined in CraftingPackets", function()
			local src = readFile("src/Network/CraftingPackets.luau")
			assert.is_truthy(src)
			assert.is_truthy(string.find(src, "SkillSummaryUpdated", 1, true))
		end)

		it("CraftingService registers GetSkillSummary handler", function()
			local src = readFile("src/Server/Services/CraftingService.luau")
			assert.is_truthy(src)
			assert.is_truthy(string.find(src, "GetSkillSummary", 1, true))
		end)

		it("CraftingService fires SkillSummaryUpdated after craft completion", function()
			local src = readFile("src/Server/Services/CraftingService.luau")
			assert.is_truthy(src)
			assert.is_truthy(string.find(src, "SkillSummaryUpdated", 1, true))
		end)

		it("CraftingService fires SkillSummaryUpdated before CraftCompleted in completeCraftingJob", function()
			local src = readFile("src/Server/Services/CraftingService.luau")
			assert.is_truthy(src)
			local updatedPos = string.find(src, "SkillSummaryUpdated", 1, true)
			local completedPos = string.find(src, "CraftCompleted:FireClient", 1, true)
			assert.is_truthy(updatedPos)
			assert.is_truthy(completedPos)
			assert.is_true(updatedPos < completedPos)
		end)

		it("CraftingSkillPanel source file exists and is non-trivial", function()
			local src = readFile("src/Client/UserInterface/CraftingSkillPanel.luau")
			assert.is_truthy(src)
			assert.is_true(#src > 200)
		end)

		it("CraftingSkillPanel exposes Init function", function()
			local src = readFile("src/Client/UserInterface/CraftingSkillPanel.luau")
			assert.is_truthy(src)
			assert.is_truthy(string.find(src, "CraftingSkillPanel.Init", 1, true))
		end)

		it("CraftingSkillPanel exposes SetVisible function", function()
			local src = readFile("src/Client/UserInterface/CraftingSkillPanel.luau")
			assert.is_truthy(src)
			assert.is_truthy(string.find(src, "CraftingSkillPanel.SetVisible", 1, true))
		end)

		it("CraftingSkillPanel listens to SkillSummaryUpdated for real-time updates", function()
			local src = readFile("src/Client/UserInterface/CraftingSkillPanel.luau")
			assert.is_truthy(src)
			assert.is_truthy(string.find(src, "SkillSummaryUpdated", 1, true))
		end)

		it("CraftingSkillPanel calls GetSkillSummary to fetch initial data", function()
			local src = readFile("src/Client/UserInterface/CraftingSkillPanel.luau")
			assert.is_truthy(src)
			assert.is_truthy(string.find(src, "GetSkillSummary", 1, true))
		end)

		it("Main.client.luau requires CraftingSkillPanel", function()
			local src = readFile("src/Client/Main.client.luau")
			assert.is_truthy(src)
			assert.is_truthy(string.find(src, "CraftingSkillPanel", 1, true))
		end)

		it("Main.client.luau initialises CraftingSkillPanel", function()
			local src = readFile("src/Client/Main.client.luau")
			assert.is_truthy(src)
			assert.is_truthy(string.find(src, "CraftingSkillPanel.Init", 1, true))
		end)
	end)
end)
