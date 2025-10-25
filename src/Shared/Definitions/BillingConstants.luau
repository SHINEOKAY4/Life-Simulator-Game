--!strict

local BillingConstants = {
	BillingCycleDurationSeconds = 1440,
	EarlyPaymentWindowSeconds = 480,
	PowerOutageOverrideKey = "BillingPowerOutage",
	OverdueInterestRate = 0.1,
	MinimumOverdueInterest = 25,
}

return BillingConstants
