--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BillingConstants = require(ReplicatedStorage.Shared.Definitions.BillingConstants)

local Constants = {}

Constants.StationKindLabels = {
	RestStation = "bed",
	CookStation = "kitchen",
	MealStation = "meal table",
	SocialStation = "hangout",
	HygieneStation = "sink",
	FunStation = "fun spot",
	FoodStorage = "storage",
}

Constants.StationNeedMap = {
	CookStation = "Hunger",
	MealStation = "Hunger",
	RestStation = "Energy",
	HygieneStation = "Hygiene",
	SocialStation = "Social",
	FunStation = "Fun",
	FoodStorage = "Hunger",
}

Constants.POWER_OUTAGE_OVERRIDE = BillingConstants.PowerOutageOverrideKey or "BillingPowerOutage"
Constants.POWER_OUTAGE_MESSAGE = "Power is out. Energy stations are offline."

return Constants
