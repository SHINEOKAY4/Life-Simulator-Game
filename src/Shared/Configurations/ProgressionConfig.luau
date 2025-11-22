--!strict
-- Shared/Configurations/ProgressionConfig.luau
-- Tunables for player progression, experience sources, and catalog unlock milestones.

local ProgressionConfig = {
	-- Level curve uses a simple exponential ramp. Required XP for each level is:
	-- BaseExperience * GrowthFactor^(level-1)
	BaseExperience = 90,
	GrowthFactor = 1.25,
	MaxLevel = 50,

	ActionRewards = {
		-- Flat XP given for finishing chores.
		ChoreCompleted = 35,
		-- XP for responding to a tenant's help request.
		TenantHelped = 80,
		-- Base XP for any single placement plus a per-cell kicker for floors/roofs/walls.
		BuildPlacementBase = 10,
		BuildPlacementPerCell = 2,
		-- Small bonus for premium fixtures that cost more or take more effort to place.
		PremiumPlacementBonus = 15,
	},

	-- Unlock map is consulted when a player levels up; items listed for a level are
	-- marked as unlocked and mirrored to the client for celebration toasts.
	UnlocksByLevel = {
		[2] = { "GlassPane", "FlatRoofEdge", "GlassCoffeeTable" },
		[3] = { "StandardBed", "FlatRoofCap", "KitchenCounter" },
		[4] = { "Bathtub", "Refridgerator", "FlatScreenTelevision" },
		[5] = { "Computer", "WoodenDoor", "CeilingFan" },
	},
}

return table.freeze(ProgressionConfig)
