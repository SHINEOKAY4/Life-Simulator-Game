--!strict
-- Server/Modules/TenantValuation.luau
-- Scores a player's plot using catalog metadata to derive baseline rent suggestions.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TenantConfig = require(ReplicatedStorage.Shared.Configurations.TenantConfig)
local ItemFinder = require(ReplicatedStorage.Shared.Utilities.ItemFinder)

export type ScoreTier = TenantConfig.ScoreTier
export type ValuationBreakdown = {
	ChunkCount: number,
	BasePlotScore: number,
	AmenityScore: number,
	CostScore: number,
	DecorScore: number,
	AmenityDetails: { [string]: number },
	AmenityCounts: { [string]: number },
}

export type ValuationResult = {
	Score: number,
	TierId: string,
	Tier: ScoreTier,
	RentEstimate: number,
	Breakdown: ValuationBreakdown,
}

local Valuation = TenantConfig.Valuation
local ScoreTiers = Valuation.ScoreTiers
local TagWeights = Valuation.TagWeights
local AmenityWeights = Valuation.AmenityWeights
local AmenitySoftCaps = Valuation.AmenitySoftCaps
local ExcessAmenityMultiplier = Valuation.ExcessAmenityMultiplier
local CostWeight = Valuation.CostWeight
local DecorWeight = Valuation.DecorWeight
local ChunkValue = Valuation.ChunkValue
local RentPerPoint = Valuation.RentPerPoint
local MinimumRent = Valuation.MinimumRent
local DefaultTierId = Valuation.DefaultTierId

local TenantValuation = {}

local function countUnlockedChunks(saveData: any): number
	local unlocked = saveData and saveData.UnlockedChunks
	if typeof(unlocked) ~= "table" then
		return 0
	end
	return #unlocked
end

local function normalizeOccupancy(spec: { [string]: any }): number
	local occupancy = spec.maxOccupancy or spec.MaxOccupancy
	if typeof(occupancy) ~= "number" or occupancy <= 0 then
		return 1
	end
	return math.clamp(math.floor(occupancy + 0.5), 1, 8)
end

local function getLeaseTier(score: number): ScoreTier
	local currentTier: ScoreTier = ScoreTiers[1]
	for _, tier in ipairs(ScoreTiers) do
		if score >= tier.MinScore then
			currentTier = tier
		else
			break
		end
	end
	return currentTier
end

local function accumulateTags(spec: { [string]: any }): number
	local tags = spec.Tags
	if typeof(tags) ~= "table" then
		return 0
	end

	local total = 0
	for _, tagName in ipairs(tags) do
		local weight = TagWeights[tagName]
		if weight then
			total += weight
		end
	end

	return total
end

function TenantValuation.Evaluate(plotState: any): ValuationResult?
	if typeof(plotState) ~= "table" then
		return nil
	end

	local save = plotState.Save
	if typeof(save) ~= "table" then
		return nil
	end

	local chunkCount = countUnlockedChunks(save)
	local basePlotScore = chunkCount * ChunkValue
	local amenityScore = 0
	local costScore = 0
	local decorScoreRaw = 0
	local amenityDetails: { [string]: number } = {}
	local amenityCounts: { [string]: number } = {}

	local placedObjects = save.PlacedObjects
	if typeof(placedObjects) == "table" then
		for _, placed in placedObjects do
			local itemId = typeof(placed) == "table" and placed.id or nil
			if itemId then
				local spec = ItemFinder.FindItemById(itemId)
				if spec then
					local stationType = spec.StationType
					if typeof(stationType) == "string" and stationType ~= "" then
						local weight = AmenityWeights[stationType]
						if weight then
							local occupancy = normalizeOccupancy(spec)
							local softCap = AmenitySoftCaps[stationType]
							local currentCount = amenityCounts[stationType] or 0
							local multiplier = 1
							if softCap and currentCount >= softCap then
								multiplier = ExcessAmenityMultiplier
							end

							amenityCounts[stationType] = currentCount + occupancy
							local contribution = weight * occupancy * multiplier
							amenityScore += contribution
							amenityDetails[stationType] = (amenityDetails[stationType] or 0) + contribution
						end
					end

					local cost = spec.Cost
					if typeof(cost) ~= "number" or cost <= 0 then
						cost = 0
					end
					costScore += cost * CostWeight

					decorScoreRaw += accumulateTags(spec)
				end
			end
		end
	end

	local decorScore = decorScoreRaw * DecorWeight
	local totalScore = basePlotScore + amenityScore + costScore + decorScore

	local tier = getLeaseTier(totalScore)
	local tierId = tier and tier.Id or DefaultTierId

	local rentBaseline = totalScore * RentPerPoint
	if rentBaseline < MinimumRent then
		rentBaseline = MinimumRent
	end

	if tier then
		rentBaseline *= tier.RentMultiplier
	end

	rentBaseline = math.floor(rentBaseline + 0.5)

	local breakdown: ValuationBreakdown = {
		ChunkCount = chunkCount,
		BasePlotScore = basePlotScore,
		AmenityScore = amenityScore,
		CostScore = costScore,
		DecorScore = decorScore,
		AmenityDetails = amenityDetails,
		AmenityCounts = amenityCounts,
	}

	return {
		Score = totalScore,
		TierId = tierId,
		Tier = tier,
		RentEstimate = rentBaseline,
		Breakdown = breakdown,
	}
end

return TenantValuation
