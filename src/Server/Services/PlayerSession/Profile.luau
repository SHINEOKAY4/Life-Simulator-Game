--!strict
-- Player data schema template. Adding new categories here allows automatic reconciliation
-- when opening a player's DataStore (see PlayerSession service).

local Profile = {
	PlotState = {},
	HouseholdState = {
		ResidentsCount = 0,
		MaxResidents = 4, -- Default max residents per player; can be increased via in-game purchases later
		Residents = {}, -- {name, age, gender, traits, needs}
	},
	CurrencyState = {
		-- CurrencyName: Balance
		Cash = 0,
		OutstandingBalance = 0,
	},
	WorldEventState = {
		RotationId = "",
		RotationEndsAt = 0,
		ActiveEvents = {},
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
			Interest = 0,
		},
	},
	KitchenState = {
		Version = 1,
		Seeded = false,
		Ingredients = {},
		Meals = {},
		LastCookedAt = 0,
		Containers = {},
	},
	EnergyState = {
		BaseLoad = 0,
		ActiveLoad = 0,
		AccumulatedEnergy = 0,
		LastTimestamp = 0,
		OutageActive = false,
	},
	InventoryState = {},
}

return Profile
