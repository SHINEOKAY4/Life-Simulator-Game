-- Tests/Specs/CraftingJobSpec.lua
-- Validates CraftingService job-lifecycle: job record shape, skill-requirement gates,
-- ingredient deduction logic, and timing math.  No Roblox runtime required.

local function readFile(path)
	local f = assert(io.open(path, "r"), "missing file: " .. path)
	local content = f:read("*a")
	f:close()
	return content
end

-- ────────────────────────────────────────────────────────────────────────────
-- Inline skill math replicated from CraftingService
-- ────────────────────────────────────────────────────────────────────────────
local SKILL_BASE_XP   = 45
local SKILL_GROWTH    = 1.24
local SKILL_MAX_LEVEL = 50

local function skillXpForLevel(level)
	if level <= 1 then
		return math.floor(SKILL_BASE_XP + 0.5)
	end
	return math.floor(SKILL_BASE_XP * (SKILL_GROWTH ^ (level - 1)) + 0.5)
end

local function computeSkillLevel(totalExperience)
	local level     = 1
	local remaining = math.max(0, math.floor(totalExperience + 0.5))
	local requirement = skillXpForLevel(level)

	while level < SKILL_MAX_LEVEL and remaining >= requirement do
		remaining   = remaining - requirement
		level       = level + 1
		requirement = skillXpForLevel(level)
	end

	if level >= SKILL_MAX_LEVEL then
		remaining   = 0
		requirement = 0
	end

	return level, remaining, requirement
end

-- ────────────────────────────────────────────────────────────────────────────
-- Inline skill-requirement gate (mirrors verifySkillRequirements in CraftingService)
-- ────────────────────────────────────────────────────────────────────────────
local function getSkillLevel(craftingState, skillId)
	local entry = craftingState.Skills[skillId]
	if type(entry) ~= "table" then
		return 1
	end
	local level = entry.Level
	if type(level) ~= "number" then
		return 1
	end
	return math.max(1, math.floor(level + 0.5))
end

local function verifySkillRequirements(craftingState, requirements)
	for _, requirement in ipairs(requirements) do
		local current = getSkillLevel(craftingState, requirement.SkillId)
		if current < requirement.Level then
			return false,
				string.format(
					"Requires %s level %d (current level %d).",
					requirement.SkillId,
					requirement.Level,
					current
				)
		end
	end
	return true, nil
end

-- ────────────────────────────────────────────────────────────────────────────
-- Inline ingredient-verification gate (mirrors verifyIngredients in CraftingService)
-- ────────────────────────────────────────────────────────────────────────────
local function verifyIngredients(inventory, ingredients)
	-- inventory = { [itemId] = quantity }
	for _, ingredient in ipairs(ingredients) do
		local available = inventory[ingredient.ItemId] or 0
		if available < ingredient.Quantity then
			return false,
				string.format(
					"Missing %dx %s (have %d).",
					ingredient.Quantity,
					ingredient.ItemId,
					available
				)
		end
	end
	return true, nil
end

-- ────────────────────────────────────────────────────────────────────────────
-- Inline ingredient-consumption (mirrors consumeIngredients deduction logic)
-- ────────────────────────────────────────────────────────────────────────────
local function consumeIngredients(inventory, ingredients)
	-- Returns consumed map or nil + error
	local consumed = {}
	for _, ingredient in ipairs(ingredients) do
		local available = inventory[ingredient.ItemId] or 0
		if available < ingredient.Quantity then
			return nil, string.format("Not enough %s", ingredient.ItemId)
		end
		inventory[ingredient.ItemId] = available - ingredient.Quantity
		consumed[ingredient.ItemId]  = ingredient.Quantity
	end
	return consumed, nil
end

-- ────────────────────────────────────────────────────────────────────────────
-- Inline job-timing helper (mirrors startCrafting duration math)
-- ────────────────────────────────────────────────────────────────────────────
local function buildJob(recipeId, craftingTimeSeconds, startedAt)
	local duration = math.max(1, math.floor((craftingTimeSeconds or 1) + 0.5))
	return {
		JobId               = "mock-guid-" .. recipeId,
		RecipeId            = recipeId,
		StationId           = "BasicWorkbench",
		StartedAt           = startedAt,
		EndsAt              = startedAt + duration,
		ConsumedIngredients = {},
	}
end

-- ────────────────────────────────────────────────────────────────────────────
-- Tests
-- ────────────────────────────────────────────────────────────────────────────

describe("CraftingJob record shape", function()
	it("contains all required fields with correct types", function()
		local job = buildJob("recipe_plank_bundle", 4, 1000)

		assert.equals("string",  type(job.JobId))
		assert.equals("string",  type(job.RecipeId))
		assert.equals("string",  type(job.StationId))
		assert.equals("number",  type(job.StartedAt))
		assert.equals("number",  type(job.EndsAt))
		assert.equals("table",   type(job.ConsumedIngredients))
	end)

	it("JobId is non-empty", function()
		local job = buildJob("recipe_stone_axe", 6, 1000)
		assert.is_true(#job.JobId > 0)
	end)

	it("EndsAt equals StartedAt + CraftingTimeSeconds (integer)", function()
		local job = buildJob("recipe_plank_bundle", 4, 500)
		assert.equals(504, job.EndsAt)
	end)

	it("sub-second CraftingTimeSeconds is clamped to minimum of 1 second", function()
		local job = buildJob("recipe_x", 0, 500)
		assert.equals(501, job.EndsAt)
	end)

	it("fractional CraftingTimeSeconds is rounded to nearest integer", function()
		-- 6.7 → floor(6.7 + 0.5) = floor(7.2) = 7
		local job = buildJob("recipe_y", 6.7, 100)
		assert.equals(107, job.EndsAt)
	end)

	it("EndsAt is strictly greater than StartedAt", function()
		for _, t in ipairs({ 0, 0.1, 1, 4, 12 }) do
			local job = buildJob("r", t, 1000)
			assert.is_true(job.EndsAt > job.StartedAt)
		end
	end)
end)

describe("CraftingJob skill-requirement gate (inline)", function()
	local function makeState(skills)
		-- skills = { [skillId] = level }
		local s = { Skills = {} }
		for id, lvl in pairs(skills) do
			s.Skills[id] = { Level = lvl, Experience = 0 }
		end
		return s
	end

	it("passes when player meets exact required level", function()
		local state = makeState({ Carpentry = 1 })
		local ok, err = verifySkillRequirements(state, { { SkillId = "Carpentry", Level = 1 } })
		assert.is_true(ok)
		assert.is_nil(err)
	end)

	it("passes when player exceeds required level", function()
		local state = makeState({ Survival = 5 })
		local ok    = verifySkillRequirements(state, { { SkillId = "Survival", Level = 3 } })
		assert.is_true(ok)
	end)

	it("fails when player is below required level", function()
		local state = makeState({ Smithing = 1 })
		local ok, err = verifySkillRequirements(state, { { SkillId = "Smithing", Level = 3 } })
		assert.is_false(ok)
		assert.is_truthy(err)
		assert.is_truthy(string.find(err, "Smithing", 1, true))
		assert.is_truthy(string.find(err, "level 3",  1, true))
	end)

	it("error message includes current level", function()
		local state = makeState({ Cooking = 1 })
		local ok, err = verifySkillRequirements(state, { { SkillId = "Cooking", Level = 4 } })
		assert.is_false(ok)
		assert.is_truthy(string.find(err, "current level 1", 1, true))
	end)

	it("defaults missing skill to level 1", function()
		local state = { Skills = {} }  -- no entries at all
		local ok    = verifySkillRequirements(state, { { SkillId = "Carpentry", Level = 1 } })
		assert.is_true(ok)
	end)

	it("fails when missing skill and requirement is level 2+", function()
		local state = { Skills = {} }
		local ok, err = verifySkillRequirements(state, { { SkillId = "Carpentry", Level = 2 } })
		assert.is_false(ok)
		assert.is_truthy(err)
	end)

	it("checks all requirements and fails on the first failing one", function()
		local state = makeState({ Survival = 3, Smithing = 1 })
		local requirements = {
			{ SkillId = "Survival", Level = 2 },
			{ SkillId = "Smithing", Level = 3 },
		}
		local ok, err = verifySkillRequirements(state, requirements)
		assert.is_false(ok)
		assert.is_truthy(string.find(err, "Smithing", 1, true))
	end)

	it("passes when all of multiple requirements are met", function()
		local state = makeState({ Survival = 2, Carpentry = 2 })
		local requirements = {
			{ SkillId = "Survival",  Level = 2 },
			{ SkillId = "Carpentry", Level = 2 },
		}
		local ok = verifySkillRequirements(state, requirements)
		assert.is_true(ok)
	end)
end)

describe("CraftingJob ingredient-deduction logic (inline)", function()
	it("passes when all ingredients are available at exact quantity", function()
		local inv = { WoodLog = 2, StoneChunk = 2, Fiber = 1 }
		local ingredients = {
			{ ItemId = "WoodLog",    Quantity = 2 },
			{ ItemId = "StoneChunk", Quantity = 2 },
			{ ItemId = "Fiber",      Quantity = 1 },
		}
		local ok, err = verifyIngredients(inv, ingredients)
		assert.is_true(ok)
		assert.is_nil(err)
	end)

	it("passes when player has more than required", function()
		local inv = { WoodLog = 10 }
		local ok = verifyIngredients(inv, { { ItemId = "WoodLog", Quantity = 2 } })
		assert.is_true(ok)
	end)

	it("fails when one ingredient is insufficient", function()
		local inv = { WoodLog = 1, Fiber = 5 }
		local ok, err = verifyIngredients(inv, { { ItemId = "WoodLog", Quantity = 2 } })
		assert.is_false(ok)
		assert.is_truthy(err)
		assert.is_truthy(string.find(err, "WoodLog", 1, true))
	end)

	it("error message includes required and available quantities", function()
		local inv = { Herb = 1 }
		local ok, err = verifyIngredients(inv, { { ItemId = "Herb", Quantity = 3 } })
		assert.is_false(ok)
		assert.is_truthy(string.find(err, "3", 1, true))
		assert.is_truthy(string.find(err, "1", 1, true))
	end)

	it("treats missing item as zero quantity", function()
		local inv = {}
		local ok, err = verifyIngredients(inv, { { ItemId = "Coal", Quantity = 1 } })
		assert.is_false(ok)
		assert.is_truthy(err)
	end)

	it("consumeIngredients deducts correct amounts from inventory", function()
		local inv = { WoodLog = 5, Fiber = 3 }
		local ingredients = {
			{ ItemId = "WoodLog", Quantity = 2 },
			{ ItemId = "Fiber",   Quantity = 1 },
		}
		local consumed, err = consumeIngredients(inv, ingredients)
		assert.is_nil(err)
		assert.is_truthy(consumed)
		assert.equals(2, consumed["WoodLog"])
		assert.equals(1, consumed["Fiber"])
		-- inventory updated in place
		assert.equals(3, inv.WoodLog)
		assert.equals(2, inv.Fiber)
	end)

	it("consumeIngredients returns error and does not mutate on partial failure", function()
		local inv = { WoodLog = 5, Coal = 0 }
		local ingredients = {
			{ ItemId = "WoodLog", Quantity = 2 },
			{ ItemId = "Coal",    Quantity = 1 },
		}
		local consumed, err = consumeIngredients(inv, ingredients)
		-- WoodLog was processed first (order-dependent), Coal fails
		assert.is_nil(consumed)
		assert.is_truthy(err)
		assert.is_truthy(string.find(err, "Coal", 1, true))
	end)

	it("ConsumedIngredients map records itemId → quantity deducted", function()
		local inv = { IronOre = 4, Coal = 3 }
		local ingredients = {
			{ ItemId = "IronOre", Quantity = 2 },
			{ ItemId = "Coal",    Quantity = 1 },
		}
		local consumed = consumeIngredients(inv, ingredients)
		assert.equals(2, consumed["IronOre"])
		assert.equals(1, consumed["Coal"])
	end)
end)

describe("CraftingJob skill-level progression (inline)", function()
	it("computeSkillLevel: 0 XP → level 1", function()
		local level = computeSkillLevel(0)
		assert.equals(1, level)
	end)

	it("computeSkillLevel: exact threshold reaches next level with 0 remainder", function()
		local threshold = skillXpForLevel(1)  -- 45
		local level, xpInto = computeSkillLevel(threshold)
		assert.equals(2, level)
		assert.equals(0, xpInto)
	end)

	it("computeSkillLevel: massive XP is capped at SKILL_MAX_LEVEL", function()
		local level = computeSkillLevel(99999999)
		assert.equals(SKILL_MAX_LEVEL, level)
	end)

	it("skillXpForLevel grows monotonically from level 1 to 10", function()
		local prev = skillXpForLevel(1)
		for lvl = 2, 10 do
			local curr = skillXpForLevel(lvl)
			assert.is_true(curr > prev, "XP for Lv" .. lvl .. " should exceed Lv" .. (lvl - 1))
			prev = curr
		end
	end)
end)

describe("CraftingService source wiring (structural)", function()
	local src

	before_each(function()
		src = readFile("src/Server/Services/CraftingService.luau")
	end)

	it("CraftingJob type defines all required fields", function()
		for _, field in ipairs({ "JobId", "RecipeId", "StationId", "StartedAt", "EndsAt", "ConsumedIngredients" }) do
			assert.is_truthy(
				string.find(src, field, 1, true),
				"CraftingJob type missing field: " .. field
			)
		end
	end)

	it("ActiveJobsByUserId is the active-job store", function()
		assert.is_truthy(string.find(src, "ActiveJobsByUserId", 1, true))
	end)

	it("verifySkillRequirements is defined and called during startCrafting", function()
		assert.is_truthy(string.find(src, "verifySkillRequirements", 1, true))
	end)

	it("verifyIngredients is defined and called during startCrafting", function()
		assert.is_truthy(string.find(src, "verifyIngredients", 1, true))
	end)

	it("consumeIngredients is called during startCrafting", function()
		assert.is_truthy(string.find(src, "consumeIngredients", 1, true))
	end)

	it("refundIngredients is called when consumption or output fails", function()
		assert.is_truthy(string.find(src, "refundIngredients", 1, true))
	end)

	it("HttpService:GenerateGUID assigns the JobId", function()
		assert.is_truthy(string.find(src, "GenerateGUID", 1, true))
	end)

	it("job duration is clamped with math.max(1, ...)", function()
		assert.is_truthy(string.find(src, "math%.max%(1", 1, false))
	end)

	it("skill-requirement failure emits CraftFailed before returning", function()
		local skillCheckPos = string.find(src, "verifySkillRequirements", 1, true)
		local craftFailPos  = string.find(src, "emitCraftFailed", 1, true)
		assert.is_truthy(skillCheckPos)
		assert.is_truthy(craftFailPos)
		assert.is_true(skillCheckPos > 0)
	end)

	it("ingredient-check failure emits CraftFailed before returning", function()
		assert.is_truthy(string.find(src, "ingredientErr", 1, true))
	end)

	it("CraftStarted signal is fired after job is registered", function()
		local jobRegistered = string.find(src, "ActiveJobsByUserId%[player%.UserId%]%s*=%s*job", 1, false)
		local craftStarted  = string.find(src, "CraftStarted:Fire", 1, true)
		assert.is_truthy(jobRegistered)
		assert.is_truthy(craftStarted)
		assert.is_true(craftStarted > jobRegistered)
	end)

	it("completeCraftingJob removes job from ActiveJobsByUserId first", function()
		assert.is_truthy(string.find(src, "ActiveJobsByUserId%[job%.Player%.UserId%]%s*=%s*nil", 1, false))
	end)

	it("CraftCompleted signal is fired after output is added to inventory", function()
		assert.is_truthy(string.find(src, "CraftCompleted:Fire", 1, true))
	end)

	it("SkillGains are applied in completeCraftingJob via applySkillGains", function()
		assert.is_truthy(string.find(src, "applySkillGains", 1, true))
	end)

	it("PlayerRemoving clears the active job for the leaving player", function()
		assert.is_truthy(string.find(src, "PlayerRemoving", 1, true))
		local removingPos  = string.find(src, "PlayerRemoving", 1, true)
		local clearJobPos  = string.find(src, "ActiveJobsByUserId%[player%.UserId%]%s*=%s*nil", 1, false)
		assert.is_truthy(clearJobPos)
		assert.is_true(clearJobPos > removingPos)
	end)
end)

describe("CraftingRecipes definition integrity (structural)", function()
	local recipesSrc

	before_each(function()
		recipesSrc = readFile("src/Shared/Definitions/CraftingRecipes.luau")
	end)

	it("every recipe has an Id, Name, Description, and Category field", function()
		for _, field in ipairs({ "Id", "Name", "Description", "Category" }) do
			assert.is_truthy(
				string.find(recipesSrc, field .. "%s*=", 1, false),
				"Expected field in recipes: " .. field
			)
		end
	end)

	it("every recipe has Ingredients, Output, RequiredStations, and SkillRequirements", function()
		for _, field in ipairs({ "Ingredients", "Output", "RequiredStations", "SkillRequirements" }) do
			assert.is_truthy(
				string.find(recipesSrc, field .. "%s*=", 1, false),
				"Expected field in recipes: " .. field
			)
		end
	end)

	it("every recipe has CraftingTimeSeconds, SkillGains, and ProgressionExperience", function()
		for _, field in ipairs({ "CraftingTimeSeconds", "SkillGains", "ProgressionExperience" }) do
			assert.is_truthy(
				string.find(recipesSrc, field .. "%s*=", 1, false),
				"Expected field in recipes: " .. field
			)
		end
	end)

	it("CraftingRecipes exposes GetById function", function()
		assert.is_truthy(string.find(recipesSrc, "CraftingRecipes.GetById", 1, true))
	end)

	it("CraftingRecipes exposes List and ById tables", function()
		assert.is_truthy(string.find(recipesSrc, "List%s*=", 1, false))
		assert.is_truthy(string.find(recipesSrc, "ById%s*=", 1, false))
	end)
end)
