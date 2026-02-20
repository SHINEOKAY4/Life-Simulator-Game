-- Tests/Specs/BadgeServiceSpec.lua
-- Tests for BadgeService (loaded via loadfile, no Roblox runtime)

local BadgeService = assert(loadfile("src/Shared/Services/BadgeService.luau"))()

describe("BadgeService", function()
	-- ========== GetBadgeForCategory ==========

	describe("GetBadgeForCategory", function()
		it("returns a badge with Icon, Color, and Label for Building", function()
			local badge = BadgeService.GetBadgeForCategory("Building")
			assert.is_not_nil(badge)
			assert.is_string(badge.Icon)
			assert.is_true(#badge.Icon > 0)
			assert.is_table(badge.Color)
			assert.is_number(badge.Color.R)
			assert.is_number(badge.Color.G)
			assert.is_number(badge.Color.B)
			assert.equals("Building", badge.Label)
		end)

		it("returns a badge for Household", function()
			local badge = BadgeService.GetBadgeForCategory("Household")
			assert.is_not_nil(badge)
			assert.equals("Household", badge.Label)
			assert.is_string(badge.Icon)
			assert.is_true(#badge.Icon > 0)
		end)

		it("returns a badge for Tenants", function()
			local badge = BadgeService.GetBadgeForCategory("Tenants")
			assert.is_not_nil(badge)
			assert.equals("Tenants", badge.Label)
			assert.is_string(badge.Icon)
		end)

		it("returns a badge for Crafting", function()
			local badge = BadgeService.GetBadgeForCategory("Crafting")
			assert.is_not_nil(badge)
			assert.equals("Crafting", badge.Label)
			assert.is_string(badge.Icon)
		end)

		it("returns a badge for Progression", function()
			local badge = BadgeService.GetBadgeForCategory("Progression")
			assert.is_not_nil(badge)
			assert.equals("Progression", badge.Label)
			assert.is_string(badge.Icon)
		end)

		it("returns unique icons for each known category", function()
			local categories = { "Building", "Household", "Tenants", "Crafting", "Progression" }
			local icons = {}
			for _, category in ipairs(categories) do
				local badge = BadgeService.GetBadgeForCategory(category)
				assert.is_nil(icons[badge.Icon], "duplicate icon for " .. category)
				icons[badge.Icon] = category
			end
		end)

		it("returns unique colors for each known category", function()
			local categories = { "Building", "Household", "Tenants", "Crafting", "Progression" }
			local colorKeys = {}
			for _, category in ipairs(categories) do
				local badge = BadgeService.GetBadgeForCategory(category)
				local key = string.format("%d-%d-%d", badge.Color.R, badge.Color.G, badge.Color.B)
				assert.is_nil(colorKeys[key], "duplicate color for " .. category)
				colorKeys[key] = category
			end
		end)

		it("returns a fallback badge for unknown category", function()
			local badge = BadgeService.GetBadgeForCategory("UnknownCategory")
			assert.is_not_nil(badge)
			assert.is_string(badge.Icon)
			assert.is_true(#badge.Icon > 0)
			assert.equals("General", badge.Label)
		end)

		it("returns a fallback badge for empty string", function()
			local badge = BadgeService.GetBadgeForCategory("")
			assert.is_not_nil(badge)
			assert.equals("General", badge.Label)
		end)

		it("returns a fallback badge for nil", function()
			local badge = BadgeService.GetBadgeForCategory(nil)
			assert.is_not_nil(badge)
			assert.equals("General", badge.Label)
		end)

		it("returns a fallback badge for non-string input", function()
			local badge = BadgeService.GetBadgeForCategory(123)
			assert.is_not_nil(badge)
			assert.equals("General", badge.Label)
		end)

		it("returns a fallback badge for boolean input", function()
			local badge = BadgeService.GetBadgeForCategory(true)
			assert.is_not_nil(badge)
			assert.equals("General", badge.Label)
		end)

		it("returns a fallback badge for table input", function()
			local badge = BadgeService.GetBadgeForCategory({})
			assert.is_not_nil(badge)
			assert.equals("General", badge.Label)
		end)

		it("returns fresh tables each call (no shared references)", function()
			local a = BadgeService.GetBadgeForCategory("Building")
			local b = BadgeService.GetBadgeForCategory("Building")
			assert.are_not.equal(a, b)
			assert.are_not.equal(a.Color, b.Color)
			assert.equals(a.Icon, b.Icon)
			assert.equals(a.Label, b.Label)
			assert.equals(a.Color.R, b.Color.R)
			assert.equals(a.Color.G, b.Color.G)
			assert.equals(a.Color.B, b.Color.B)
		end)

		it("returns fresh tables for fallback badge too", function()
			local a = BadgeService.GetBadgeForCategory("Unknown")
			local b = BadgeService.GetBadgeForCategory("Unknown")
			assert.are_not.equal(a, b)
			assert.are_not.equal(a.Color, b.Color)
		end)

		it("returns valid RGB values in 0-255 range for all categories", function()
			local categories = { "Building", "Household", "Tenants", "Crafting", "Progression" }
			for _, category in ipairs(categories) do
				local badge = BadgeService.GetBadgeForCategory(category)
				assert.is_true(badge.Color.R >= 0 and badge.Color.R <= 255,
					"R out of range for " .. category)
				assert.is_true(badge.Color.G >= 0 and badge.Color.G <= 255,
					"G out of range for " .. category)
				assert.is_true(badge.Color.B >= 0 and badge.Color.B <= 255,
					"B out of range for " .. category)
			end
		end)

		it("is case-sensitive for category names", function()
			local badge = BadgeService.GetBadgeForCategory("building")
			assert.equals("General", badge.Label) -- lowercase should not match

			local badge2 = BadgeService.GetBadgeForCategory("BUILDING")
			assert.equals("General", badge2.Label) -- uppercase should not match
		end)
	end)

	-- ========== GetCategories ==========

	describe("GetCategories", function()
		it("returns all 5 known categories", function()
			local categories = BadgeService.GetCategories()
			assert.is_table(categories)
			assert.equals(5, #categories)
		end)

		it("returns categories in sorted order", function()
			local categories = BadgeService.GetCategories()
			for i = 2, #categories do
				assert.is_true(categories[i - 1] <= categories[i],
					"categories not sorted: " .. categories[i - 1] .. " > " .. categories[i])
			end
		end)

		it("includes all expected category names", function()
			local categories = BadgeService.GetCategories()
			local set = {}
			for _, name in ipairs(categories) do
				set[name] = true
			end
			assert.is_true(set["Building"])
			assert.is_true(set["Household"])
			assert.is_true(set["Tenants"])
			assert.is_true(set["Crafting"])
			assert.is_true(set["Progression"])
		end)

		it("returns a fresh table each call", function()
			local a = BadgeService.GetCategories()
			local b = BadgeService.GetCategories()
			assert.are_not.equal(a, b)
		end)
	end)

	-- ========== HasBadge ==========

	describe("HasBadge", function()
		it("returns true for all known categories", function()
			local categories = { "Building", "Household", "Tenants", "Crafting", "Progression" }
			for _, category in ipairs(categories) do
				assert.is_true(BadgeService.HasBadge(category), "expected HasBadge true for " .. category)
			end
		end)

		it("returns false for unknown category", function()
			assert.is_false(BadgeService.HasBadge("UnknownCategory"))
		end)

		it("returns false for empty string", function()
			assert.is_false(BadgeService.HasBadge(""))
		end)

		it("returns false for nil", function()
			assert.is_false(BadgeService.HasBadge(nil))
		end)

		it("returns false for non-string input", function()
			assert.is_false(BadgeService.HasBadge(42))
		end)

		it("returns false for case-mismatched category", function()
			assert.is_false(BadgeService.HasBadge("building"))
			assert.is_false(BadgeService.HasBadge("CRAFTING"))
		end)
	end)
end)
