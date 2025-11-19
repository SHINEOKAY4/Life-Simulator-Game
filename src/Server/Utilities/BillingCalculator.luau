--!strict
-- ServerScriptService/Server/Utilities/BillingCalculator.lua

-- Calculate billing components from player state

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ItemFinder = require(ReplicatedStorage.Shared.Utilities.ItemFinder)
local TimeScale = require(ReplicatedStorage.Shared.Utilities.TimeScale)
local BillingConstants = require(ReplicatedStorage.Shared.Definitions.BillingConstants)

type PlotStateData = {
	UnlockedChunks: { { cx: number, cz: number } },
	PlacedObjects: { [string]: any },
}

local BillingCalculator = {}

-- Constants (tunable)
local COST_PER_CHUNK = 15 -- Base plot tax per unlocked chunk
local ELECTRICITY_RATE = 0.8 -- Currency charged per in-game kWh consumed
local WATER_RATE = 0.5 -- Currency charged per in-game gallon consumed
local INTERNET_BASE_FEE = 25 -- Flat fee if internet service is active
local INTERNET_DEVICE_FEE = 5 -- Additional fee per connected device
local BILLING_CYCLE_DURATION_SECONDS = math.max(1, BillingConstants.BillingCycleDurationSeconds or 1440)

function BillingCalculator.CalculatePlotTax(plotStateData: PlotStateData): number
	local unlockedChunks = plotStateData.UnlockedChunks or {}
	local chunkCount = #unlockedChunks

	-- Progressive scaling: first chunk free, then increasing cost
	if chunkCount <= 1 then
		return 0
	end

	local taxableChunks = chunkCount - 1
	-- Progressive rate: base + (chunks * scaling_factor)
	return math.floor(COST_PER_CHUNK * taxableChunks * (1 + taxableChunks * 0.1))
end

function BillingCalculator.CalculateElectricityCostFromUsage(energyConsumptionHours: number): number
	if
		typeof(energyConsumptionHours) ~= "number"
		or energyConsumptionHours <= 0
		or energyConsumptionHours ~= energyConsumptionHours
	then
		return 0
	end

	local cost = energyConsumptionHours * ELECTRICITY_RATE
	return math.floor(cost + 0.5)
end

function BillingCalculator.EstimateCycleElectricCost(plotStateData: PlotStateData): number
	local placedObjects = plotStateData.PlacedObjects or {}
	local totalEnergyConsumption = 0

	for _, placedObject in pairs(placedObjects) do
		local itemSpec = ItemFinder.FindItemById(placedObject.id)
		if itemSpec then
			local energyPerHour = itemSpec.EnergyConsumptionPerHour
			if typeof(energyPerHour) == "number" and energyPerHour > 0 then
				totalEnergyConsumption += energyPerHour
			end
		end
	end

	local secondsPerGameHour = TimeScale.GetSecondsPerFullDay() / 24
	if secondsPerGameHour <= 0 then
		secondsPerGameHour = 60
	end

	local billingHours = BILLING_CYCLE_DURATION_SECONDS / secondsPerGameHour
	if billingHours < 0 then
		billingHours = 0
	end
	local estimatedEnergy = totalEnergyConsumption * billingHours
	return BillingCalculator.CalculateElectricityCostFromUsage(estimatedEnergy)
end

function BillingCalculator.CalculateWaterCost(plotStateData: PlotStateData): number
	local placedObjects = plotStateData.PlacedObjects or {}
	local totalWaterConsumption = 0

	for _, placedObject in pairs(placedObjects) do
		local itemSpec = ItemFinder.FindItemById(placedObject.id)
		if itemSpec then
			local waterPerHour = itemSpec.WaterConsumptionPerHour
			if typeof(waterPerHour) == "number" and waterPerHour > 0 then
				totalWaterConsumption += waterPerHour
			end
		end
	end

	local secondsPerGameHour = TimeScale.GetSecondsPerFullDay() / 24
	if secondsPerGameHour <= 0 then
		secondsPerGameHour = 60
	end

	local billingHours = BILLING_CYCLE_DURATION_SECONDS / secondsPerGameHour
	if billingHours < 0 then
		billingHours = 0
	end

	local estimatedWater = totalWaterConsumption * billingHours
	return math.floor((estimatedWater * WATER_RATE) + 0.5)
end

function BillingCalculator.CalculateInternetCost(plotStateData: PlotStateData): number
	local placedObjects = plotStateData.PlacedObjects or {}
	local deviceCount = 0
	local hasInternetAccess = false

	for _, placedObject in pairs(placedObjects) do
		local itemSpec = ItemFinder.FindItemById(placedObject.id)
		if itemSpec then
			if itemSpec.RequiresInternet then
				deviceCount += 1
				hasInternetAccess = true
			end
			-- Some items might provide internet (like a router), but for now we assume service is needed if devices exist
		end
	end

	if not hasInternetAccess then
		return 0
	end

	return math.floor(INTERNET_BASE_FEE + (deviceCount * INTERNET_DEVICE_FEE))
end

return BillingCalculator
