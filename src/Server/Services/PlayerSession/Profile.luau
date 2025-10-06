--!strict
-- Player data schema template. Adding new categories here allows automatic reconciliation
-- when opening a player's DataStore (see PlayerSession service).

local Profile = {
	PlotState = {},
	HouseholdState = {
		MaxResidents = 4, -- Default max residents per player; can be increased via in-game purchases later
		Residents = {}, -- {name, age, occupation, gender, traits, needs}
	},
}

return Profile
