--!strict
-- ServerScriptService/Server/Utilities/BillingCalculator.lua

-- Calculate billing components from player state

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ItemFinder = require(ReplicatedStorage.Shared.Utilities.ItemFinder)

type PlotStateData = {
	UnlockedChunks: { { cx: number, cz: number } },
	PlacedObjects: { [string]: any },
}

local BillingCalculator = {}

-- Constants (tunable)
local COST_PER_CHUNK = 15 -- Base plot tax per unlocked chunk
local ELECTRICITY_RATE = 0.8 -- Cost multiplier for energy consumption
local FOOD_COST_PER_USAGE = 12 -- Currency charged per successful cook interaction

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

function BillingCalculator.CalculateElectricityCost(plotStateData: PlotStateData): number
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

	-- Calculate cost for the billing cycle duration (8 minutes = 0.133 hours)
	local billingHours = 8 / 60 -- 480 seconds = 8 minutes
	local cost = totalEnergyConsumption * billingHours * ELECTRICITY_RATE

	return math.floor(cost + 0.5)
end

function BillingCalculator.CalculateFoodCost(usageCount: number): number
	if typeof(usageCount) ~= "number" or usageCount <= 0 or usageCount ~= usageCount then
		return 0
	end

	local normalizedUsage = math.max(0, usageCount)
	local rawCost = normalizedUsage * FOOD_COST_PER_USAGE
	return math.floor(rawCost + 0.5)
end

function BillingCalculator.GetCookStationCount(plotStateData: PlotStateData): number
	local placedObjects = plotStateData.PlacedObjects or {}
	local cookStationCount = 0

	for _, placedObject in pairs(placedObjects) do
		local itemSpec = ItemFinder.FindItemById(placedObject.id)
		if itemSpec and itemSpec.StationType == "CookStation" then
			cookStationCount += 1
		end
	end

	return cookStationCount
end

BillingCalculator.FOOD_COST_PER_USAGE = FOOD_COST_PER_USAGE

return BillingCalculator
