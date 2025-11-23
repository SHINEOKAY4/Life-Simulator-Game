--!strict
-- Player data schema template. Adding new categories here allows automatic reconciliation
-- when opening a player's DataStore (see PlayerSession service).

local Profile = {
	PlotState = {},
	HouseholdState = {
		TenantsCount = 0,
		Tenants = {}, -- {name, traits, needs}
	},
	CurrencyState = {
		-- CurrencyName: Balance
		Cash = 0,
		OutstandingBalance = 0,
	},
	ProgressionState = {
		Level = 1,
		Experience = 0,
		UnlockedItems = {},
	},
	TenantState = {
		Version = 1,
		LastOfferUnix = 0,
		OfferSequence = 0,
		PendingOffer = false,
		ActiveLease = false,
		ActiveLeases = {},
		OutstandingRent = 0,
		MailboxBalance = 0,
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
	EnergyState = {
		BaseLoad = 0,
		ActiveLoad = 0,
		AccumulatedEnergy = 0,
		LastTimestamp = 0,
		OutageActive = false,
	},
	InventoryState = {},
	TutorialState = {
		IsCompleted = false,
		Step = 0,
		HasReceivedStartingCash = false,
	},
	ReviewState = {
		Reviews = {},
	},
}

return Profile
