--!strict
-- Shared configuration for build-system wide constants

local BuildConstants = {
	-- Vertical spacing between consecutive floor levels, in studs.
	FloorHeightStuds = 12,
	-- Default lift applied to roof items above the floor plane, in studs.
	RoofLiftStuds = 12,
	-- Base cost for the first plot expansion
	ExpansionBaseCost = 2500,
	-- Cost increase per previously unlocked chunk
	ExpansionCostIncrement = 1500,
}

return BuildConstants
