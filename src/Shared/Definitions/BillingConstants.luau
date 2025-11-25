--!strict
-- Billing system configuration constants

local BillingConstants = {
	-- Billing cycle in real seconds (e.g., 1440 = 24 minutes)
	CycleDurationSeconds = 1440,

	-- Grace period before consequences (e.g., 360 = 6 minutes)
	GracePeriodSeconds = 240,

	-- Enforcement attribute
	PowerOutageAttribute = "PowerOutageActive",

	-- Property Tax: Based on property value
	-- Formula: PropertyValue * TaxRate
	PropertyTaxRate = 0.02, -- 2% of property value per cycle
	BasePropertyValue = 1000, -- Base value for empty plot
	CellValueMultiplier = 50, -- Value added per occupied cell

	-- Electricity: Based on power consumption
	-- Formula: EnergyConsumed (kWh) * RatePerKWh
	ElectricityRatePerKWh = 0.12, -- Cost per kilowatt-hour

	-- Water: Based on water consumption
	-- Formula: WaterUnits * RatePerUnit
	WaterRatePerUnit = 2.5, -- Cost per water unit
	BaseWaterUsage = 5, -- Base water consumption per cycle
	WaterPerResident = 3, -- Additional water per resident per cycle

	-- Internet: Tiered subscription (stub for now)
	InternetTiers = {
		None = 0,
		Basic = 25,
		Standard = 50,
		Premium = 100,
	},

	-- Payment attributes for client-server communication
	BillDueAttribute = "BillDue",
	PropertyTaxAttribute = "PropertyTax",
	ElectricityAttribute = "Electricity",
	WaterAttribute = "Water",
	InternetAttribute = "Internet",
	TotalBillAttribute = "TotalBill",
}

return BillingConstants
