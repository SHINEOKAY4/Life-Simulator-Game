--!strict
-- Billing calculations utility

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local BillingConstants = require(ReplicatedStorage.Shared.Definitions.BillingConstants)

local BillingCalculator = {}

-- Calculate property tax based on plot occupancy
function BillingCalculator.CalculatePropertyTax(occupiedCells: number): number
	local propertyValue = BillingConstants.BasePropertyValue + (occupiedCells * BillingConstants.CellValueMultiplier)
	return propertyValue * BillingConstants.PropertyTaxRate
end

-- Calculate electricity cost from energy consumption (in kWh)
function BillingCalculator.CalculateElectricity(energyConsumedKWh: number): number
	return energyConsumedKWh * BillingConstants.ElectricityRatePerKWh
end

-- Calculate water cost based on resident count
function BillingCalculator.CalculateWater(residentCount: number): number
	local totalUsage = BillingConstants.BaseWaterUsage + (residentCount * BillingConstants.WaterPerResident)
	return totalUsage * BillingConstants.WaterRatePerUnit
end

-- Get internet cost for current tier
function BillingCalculator.CalculateInternet(tier: string): number
	return BillingConstants.InternetTiers[tier] or 0
end

return BillingCalculator
