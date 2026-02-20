-- Shared/Services/BadgeService.luau
-- Provides badge icon symbols and colors for achievement categories.
-- Works both in Roblox runtime and in headless Busted tests via loadfile().

-- UTF-8 encode a single Unicode codepoint for Lua 5.1 compatibility.
-- Luau supports \u{XXXX} natively, but standard Lua 5.1 does not.
local function utf8char(codepoint)
	if codepoint <= 0x7F then
		return string.char(codepoint)
	elseif codepoint <= 0x7FF then
		return string.char(
			0xC0 + math.floor(codepoint / 64),
			0x80 + (codepoint % 64)
		)
	elseif codepoint <= 0xFFFF then
		return string.char(
			0xE0 + math.floor(codepoint / 4096),
			0x80 + math.floor((codepoint % 4096) / 64),
			0x80 + (codepoint % 64)
		)
	elseif codepoint <= 0x10FFFF then
		return string.char(
			0xF0 + math.floor(codepoint / 262144),
			0x80 + math.floor((codepoint % 262144) / 4096),
			0x80 + math.floor((codepoint % 4096) / 64),
			0x80 + (codepoint % 64)
		)
	end
	return "?"
end

local ICONS = {
	Building    = utf8char(0x1F3D7),  -- construction crane
	Household   = utf8char(0x1F3E0),  -- house
	Tenants     = utf8char(0x1F465),  -- people silhouettes
	Crafting    = utf8char(0x1F528),  -- hammer
	Progression = utf8char(0x2B50),   -- star
	Default     = utf8char(0x1F3C6), -- trophy
}

local CATEGORY_BADGES = {
	Building = {
		Icon = ICONS.Building,
		Color = { R = 92, G = 160, B = 255 },
		Label = "Building",
	},
	Household = {
		Icon = ICONS.Household,
		Color = { R = 130, G = 214, B = 155 },
		Label = "Household",
	},
	Tenants = {
		Icon = ICONS.Tenants,
		Color = { R = 240, G = 180, B = 90 },
		Label = "Tenants",
	},
	Crafting = {
		Icon = ICONS.Crafting,
		Color = { R = 200, G = 140, B = 230 },
		Label = "Crafting",
	},
	Progression = {
		Icon = ICONS.Progression,
		Color = { R = 255, G = 210, B = 80 },
		Label = "Progression",
	},
}

local DEFAULT_BADGE = {
	Icon = ICONS.Default,
	Color = { R = 180, G = 180, B = 180 },
	Label = "General",
}

local BadgeService = {}

--- Returns the BadgeInfo for the given achievement category.
--- Falls back to a default trophy badge for unknown or invalid categories.
--- BadgeInfo shape: { Icon: string, Color: { R: number, G: number, B: number }, Label: string }
function BadgeService.GetBadgeForCategory(category)
	if type(category) ~= "string" or category == "" then
		return {
			Icon = DEFAULT_BADGE.Icon,
			Color = { R = DEFAULT_BADGE.Color.R, G = DEFAULT_BADGE.Color.G, B = DEFAULT_BADGE.Color.B },
			Label = DEFAULT_BADGE.Label,
		}
	end

	local badge = CATEGORY_BADGES[category]
	if not badge then
		return {
			Icon = DEFAULT_BADGE.Icon,
			Color = { R = DEFAULT_BADGE.Color.R, G = DEFAULT_BADGE.Color.G, B = DEFAULT_BADGE.Color.B },
			Label = DEFAULT_BADGE.Label,
		}
	end

	-- Return a fresh copy to prevent external mutation
	return {
		Icon = badge.Icon,
		Color = { R = badge.Color.R, G = badge.Color.G, B = badge.Color.B },
		Label = badge.Label,
	}
end

--- Returns all known category names that have badge definitions.
function BadgeService.GetCategories()
	local categories = {}
	for category in pairs(CATEGORY_BADGES) do
		categories[#categories + 1] = category
	end
	table.sort(categories)
	return categories
end

--- Returns true if the given category has a dedicated badge (not the fallback).
function BadgeService.HasBadge(category)
	if type(category) ~= "string" or category == "" then
		return false
	end
	return CATEGORY_BADGES[category] ~= nil
end

-- table.freeze is Luau-only; guard for Lua 5.1 compat in tests
if table.freeze then
	return table.freeze(BadgeService)
end
return BadgeService
