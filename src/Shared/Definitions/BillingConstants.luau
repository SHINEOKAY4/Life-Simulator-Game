--!strict

local BillingConstants = {
	BillingCycleDurationSeconds = 960,
	EarlyPaymentWindowSeconds = 480,
	PowerOutageOverrideKey = "BillingPowerOutage",
	WaterShutoffOverrideKey = "BillingWaterShutoff",
	InternetDisconnectOverrideKey = "BillingInternetDisconnect",
	OverdueInterestRate = 0.1,
	MinimumOverdueInterest = 25,
}

return BillingConstants
