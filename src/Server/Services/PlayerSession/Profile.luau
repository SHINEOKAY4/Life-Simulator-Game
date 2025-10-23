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
		Cash = 0,
		OutstandingBalance = 0,
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
	BillingState = {
		lastPaymentTime = 0,
		BillingGraceActive = false,
		GraceElapsedSeconds = 0,
		OverduePayments = 0,
		CurrentCycleRecordedOverdue = false,
		CycleState = "Active",
		OutstandingBreakdown = {
			PlotTax = 0,
			Electric = 0,
			Food = 0,
		},
	},

	InventoryState = {},
}

return Profile
