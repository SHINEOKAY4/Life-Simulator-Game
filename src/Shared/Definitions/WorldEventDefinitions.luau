-- WorldEventDefinitions: rotating world-event pool with per-event gameplay buffs.
-- WorldEventService picks one event per rotation cycle from this pool.
-- Compatible with both Roblox Luau runtime and Lua 5.1 test environment.
--
-- Each event has:
--   Id: string
--   Name: string
--   Description: string
--   Kind: string  -- event category (Celebration, Market, Social, Workshop, Competition, Community)
--   Buffs: { { Type: string, Value: number, Label: string } }
--
-- Buff Types: "XPMultiplier" | "CashMultiplier" | "CraftSpeedMultiplier" | "ChoreRewardMultiplier" | "TipMultiplier"

local EVENT_POOL = {
	{
		Id = "community_festival",
		Name = "Community Festival",
		Description = "Residents celebrate together! All income sources are boosted.",
		Kind = "Celebration",
		Buffs = {
			{ Type = "CashMultiplier", Value = 1.10, Label = "+10% Cash" },
		},
	},
	{
		Id = "builders_bazaar",
		Name = "Builder's Bazaar",
		Description = "A building supply expo is in town. Earn bonus XP for every placement.",
		Kind = "Market",
		Buffs = {
			{ Type = "XPMultiplier", Value = 1.20, Label = "+20% Build XP" },
		},
	},
	{
		Id = "tenant_appreciation_week",
		Name = "Tenant Appreciation Week",
		Description = "Happy tenants tip more generously this week.",
		Kind = "Social",
		Buffs = {
			{ Type = "TipMultiplier", Value = 1.30, Label = "+30% Tips" },
			{ Type = "CashMultiplier", Value = 1.05, Label = "+5% Cash" },
		},
	},
	{
		Id = "craft_fair",
		Name = "Craft Fair",
		Description = "Artisans gather to share techniques. Crafting is faster and more rewarding.",
		Kind = "Workshop",
		Buffs = {
			{ Type = "CraftSpeedMultiplier", Value = 1.25, Label = "+25% Craft Speed" },
			{ Type = "XPMultiplier", Value = 1.10, Label = "+10% XP" },
		},
	},
	{
		Id = "property_showcase",
		Name = "Property Showcase",
		Description = "Inspectors tour the neighborhood. All experience gains are amplified.",
		Kind = "Competition",
		Buffs = {
			{ Type = "XPMultiplier", Value = 1.25, Label = "+25% XP" },
		},
	},
	{
		Id = "neighborhood_cleanup",
		Name = "Neighborhood Cleanup",
		Description = "The community bands together to clean up. Chore rewards are boosted.",
		Kind = "Community",
		Buffs = {
			{ Type = "ChoreRewardMultiplier", Value = 1.30, Label = "+30% Chore Rewards" },
			{ Type = "XPMultiplier", Value = 1.10, Label = "+10% XP" },
		},
	},
}

-- Lookup tables
local byId = {}
for _, def in ipairs(EVENT_POOL) do
	byId[def.Id] = def
end

local WorldEventDefinitions = {
	EventPool = EVENT_POOL,
	ById = byId,
}

function WorldEventDefinitions.GetEvent(eventId)
	return byId[eventId]
end

function WorldEventDefinitions.GetBuffsForEvent(eventId)
	local def = byId[eventId]
	if not def then
		return {}
	end
	return def.Buffs
end

function WorldEventDefinitions.GetEventCount()
	return #EVENT_POOL
end

-- table.freeze is Luau-only; guard for Lua 5.1 test environment
if table.freeze then
	return table.freeze(WorldEventDefinitions)
end
return WorldEventDefinitions
