--!strict
-- Player data schema template. Adding new categories here allows automatic reconciliation
-- when opening a player's DataStore (see PlayerSession service).

local Profile = {
	PlotState = {},
	HouseholdState = {
		ResidentsCount = 0,
		MaxResidents = 4, -- Default max residents per player; can be increased via in-game purchases later
		Residents = {}, -- {name, age, occupation, gender, traits, needs}
	},
	CurrencyState = {
		-- CurrencyName: Balance
	},
	GigState = {
		SlotsUsedToday = 0,
		LastRefreshDay = 0,
		Cooldowns = {},
		MomentumBoost = {
			Amount = 0,
			ExpiresAt = 0,
		},
	},
	EconomyState = {
		LastBillingDay = -4,
		OutstandingBills = 0,
	},
	PayrollState = {
		PendingAmount = 0,
		LastPayoutDay = -1,
	},
	InventoryState = {},
}

return Profile
