--!strict
-- Server/Modules/TenantValuation.luau
-- Scores a player's plot using catalog metadata to derive baseline rent suggestions.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local TenantConfig = require(ReplicatedStorage.Shared.Configurations.TenantConfig)
local ItemFinder = require(ReplicatedStorage.Shared.Utilities.ItemFinder)
local ComfortRating = require(ReplicatedStorage.Shared.Utilities.ComfortRating)
local ResidentService = require(ServerScriptService.Server.Services.ResidentService)

export type ScoreTier = TenantConfig.ScoreTier
export type ValuationBreakdown = {
	ChunkCount: number,
	BasePlotScore: number,
	AmenityScore: number,
	CostScore: number,
	DecorScore: number,
	ComfortScore: number,
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
local ComfortWeight = Valuation.ComfortWeight
local ChunkValue = Valuation.ChunkValue
local RentPerPoint = Valuation.RentPerPoint
local MinimumRent = Valuation.MinimumRent
local DefaultTierId = Valuation.DefaultTierId
local DiminishingReturnFactor = Valuation.DiminishingReturnFactor or 0.85
local VarietyBonusPerCategory = Valuation.VarietyBonusPerCategory or 0.05
local ThemeSynergyBonus = Valuation.ThemeSynergyBonus or 0.15
local LuxuryThreshold = Valuation.LuxuryThreshold or 500
local LuxuryBonusMultiplier = Valuation.LuxuryBonusMultiplier or 1.2
local ReviewScoreMultiplier = 0.1 -- +/- 10% per star deviation from 3

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

local function accumulateTags(spec: { [string]: any }, tagCounts: { [string]: number }): number
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
		tagCounts[tagName] = (tagCounts[tagName] or 0) + 1
	end

	return total
end

local function getAverageRoomTemperature(plotState: any): number?
	if typeof(plotState) ~= "table" or typeof(plotState.GetRoomsForLevel) ~= "function" then
		return nil
	end

	local totalTemp = 0
	local roomCount = 0
	local maxLevel = plotState.MaxFloorLevel or 0

	for level = 0, maxLevel do
		local rooms = plotState:GetRoomsForLevel(level)
		if rooms then
			for _, room in ipairs(rooms) do
				if room.CellCount > 0 and room.InsulationScore > 0.2 then
					if typeof(room.CurrentTemperature) == "number" then
						totalTemp += room.CurrentTemperature
						roomCount += 1
					end
				end
			end
		end
	end

	if roomCount == 0 then
		return nil
	end

	return totalTemp / roomCount
end

function TenantValuation.Evaluate(plotState: any, averageReviewScore: number?, player: Player?): ValuationResult?
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
	local itemCountsById: { [string]: number } = {}
	local tagCounts: { [string]: number } = {}
	local totalDecorItems = 0

	local placedObjects = save.PlacedObjects
	if typeof(placedObjects) == "table" then
		for _, placed in placedObjects do
			local itemId = typeof(placed) == "table" and placed.id or nil
			if itemId then
				local spec = ItemFinder.FindItemById(itemId)
				if spec then
					-- Track item counts for diminishing returns
					local currentItemCount = itemCountsById[itemId] or 0
					itemCountsById[itemId] = currentItemCount + 1

					-- Calculate diminishing return multiplier for this specific instance
					-- 1st item: 1.0
					-- 2nd item: 0.85
					-- 3rd item: 0.7225
					local diminishingMult = math.pow(DiminishingReturnFactor, currentItemCount)

					local stationType = spec.StationType
					if typeof(stationType) == "string" and stationType ~= "" then
						local weight = AmenityWeights[stationType]
						if weight then
							local occupancy = normalizeOccupancy(spec)
							-- Soft caps are now handled by diminishing returns per item ID + category variety bonus
							-- But we keep soft cap logic for "bulk" spam of different items in same category if needed
							-- For now, let's rely on diminishing returns per item ID primarily,
							-- and maybe a lighter category soft cap if needed.
							-- The original code had a hard multiplier step down.
							-- Let's keep the original soft cap logic as a "Category Saturation" check on top of item diminishing returns.

							local softCap = AmenitySoftCaps[stationType]
							local currentCategoryCount = amenityCounts[stationType] or 0
							local categoryMult = 1
							if softCap and currentCategoryCount >= softCap then
								categoryMult = ExcessAmenityMultiplier
							end

							amenityCounts[stationType] = currentCategoryCount + occupancy

							-- Combined multiplier: Item Diminishing * Category Saturation
							local finalMult = diminishingMult * categoryMult

							local contribution = weight * occupancy * finalMult
							amenityScore += contribution
							amenityDetails[stationType] = (amenityDetails[stationType] or 0) + contribution
						end
					end

					local cost = spec.Cost
					if typeof(cost) ~= "number" or cost <= 0 then
						cost = 0
					end

					-- Luxury Bonus
					local luxuryMult = 1
					if cost >= LuxuryThreshold then
						luxuryMult = LuxuryBonusMultiplier
					end

					costScore += (cost * CostWeight * luxuryMult)

					local decorValue = accumulateTags(spec, tagCounts)
					decorScoreRaw += (decorValue * diminishingMult)
					if decorValue > 0 then
						totalDecorItems += 1
					end
				end
			end
		end
	end

	-- Variety Bonus
	local uniqueCategories = 0
	for _, count in pairs(amenityCounts) do
		if count > 0 then
			uniqueCategories += 1
		end
	end
	local varietyMultiplier = 1 + (uniqueCategories * VarietyBonusPerCategory)

	-- Theme Synergy Bonus
	local synergyMultiplier = 1
	if totalDecorItems > 0 then
		local maxTagCount = 0
		for _, count in pairs(tagCounts) do
			if count > maxTagCount then
				maxTagCount = count
			end
		end

		local synergyRatio = maxTagCount / totalDecorItems
		if synergyRatio >= 0.5 then
			synergyMultiplier = 1 + ThemeSynergyBonus
		end
	end

	local decorScore = decorScoreRaw * DecorWeight

	-- Apply global multipliers to relevant sections
	amenityScore *= varietyMultiplier
	decorScore *= synergyMultiplier

	-- Calculate Comfort Score (furniture quality + temperature)
	local comfortScore = 0
	local avgTemp = getAverageRoomTemperature(plotState)

	-- Count residents and tenants for occupancy
	local residentCount = 0
	local tenantCount = 0
	if player then
		local residents = ResidentService.GetResidents(player)
		if residents then
			for _ in pairs(residents) do
				residentCount += 1
			end
		end
		-- TenantService would create circular dependency, so we estimate based on plot size
		tenantCount = math.floor(chunkCount / 3) -- Rough estimate: 1 tenant per 3 chunks
	end

	-- Convert PlacedObjects to format expected by ComfortRating
	local placedItemsForComfort: { [string]: { id: string } } = {}
	if typeof(placedObjects) == "table" then
		for key, placed in placedObjects do
			if typeof(placed) == "table" and placed.id then
				placedItemsForComfort[key] = { id = placed.id }
			end
		end
	end

	local comfortComponents = ComfortRating.Calculate(placedItemsForComfort, avgTemp, residentCount, tenantCount)
	comfortScore = comfortComponents.TotalScore * ComfortWeight

	local totalScore = basePlotScore + amenityScore + costScore + decorScore + comfortScore

	local tier = getLeaseTier(totalScore)
	local tierId = tier and tier.Id or DefaultTierId

	local rentBaseline = totalScore * RentPerPoint
	if rentBaseline < MinimumRent then
		rentBaseline = MinimumRent
	end

	if tier then
		rentBaseline *= tier.RentMultiplier
	end

	-- Apply Review Score Multiplier
	-- Default to 3 stars (neutral) if no score provided
	local rating = averageReviewScore or 3
	local reviewMult = 1 + (rating - 3) * ReviewScoreMultiplier
	-- Clamp to reasonable bounds (e.g. 0.5x to 1.5x)
	reviewMult = math.clamp(reviewMult, 0.5, 1.5)
	rentBaseline *= reviewMult

	rentBaseline = math.floor(rentBaseline + 0.5)

	local breakdown: ValuationBreakdown = {
		ChunkCount = chunkCount,
		BasePlotScore = basePlotScore,
		AmenityScore = amenityScore,
		CostScore = costScore,
		DecorScore = decorScore,
		ComfortScore = comfortScore,
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
