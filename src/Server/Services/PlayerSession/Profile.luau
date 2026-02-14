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
		LastBillTime = 0,
		UnpaidTime = nil,
		CurrentCycle = {
			PropertyTax = 0,
			Electricity = 0,
			Water = 0,
			Internet = 0,
		},
		InternetTier = "None",
	},
	EnergyState = {
		BaseLoad = 0,
		ActiveLoad = 0,
		AccumulatedEnergy = 0,
		LastTimestamp = 0,
		OutageActive = false,
	},
	InventoryState = {},
	CraftingState = {
		Skills = {},
		StarterResourcesGranted = false,
	},
	TutorialState = {
		IsCompleted = false,
		Step = 0,
		HasReceivedStartingCash = false,
	},
	ReviewState = {
		Reviews = {},
	},
	AchievementState = {
		Version = 1,
		Stats = {},
		Unlocked = {},
		Claimed = {},
	},
}

return Profile
