--!strict
-- Shared/Utilities/ComfortRating.luau
-- Calculates comprehensive comfort rating based on furniture quality and temperature
--
-- This module is used for player-facing UI feedback (ProfileUI comfort rating).
-- It is SEPARATE from TenantValuation, which uses its own scoring system
-- for rent calculations based on amenity weights and tags.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ItemFinder = require(ReplicatedStorage.Shared.Utilities.ItemFinder)

local ComfortRating = {}

-- Temperature comfort scoring
local IDEAL_TEMP_MIN = 18
local IDEAL_TEMP_MAX = 24
local COMFORTABLE_RANGE = 3 -- ±3°C from ideal still comfortable
local TEMPERATURE_WEIGHT = 0.3 -- 30% of overall comfort score

-- Furniture quality scoring
local FURNITURE_WEIGHT = 0.7 -- 70% of overall comfort score

-- Default comfort scores by quality tier
local DEFAULT_COMFORT_SCORES = {
	Basic = 1,
	Standard = 2,
	Premium = 3,
	Luxury = 4,
}

-- Scale factors for different furniture types
local FURNITURE_TYPE_SCALES = {
	Bed = 1.5, -- Beds are most important for comfort
	Seating = 1.0,
	Bath = 1.2,
	Table = 0.5, -- Tables contribute less to comfort
}

export type ComfortComponents = {
	FurnitureScore: number,
	TemperatureScore: number,
	TotalScore: number,
	FurnitureBreakdown: { [string]: number },
}

-- Calculate temperature comfort score (0-100)
local function calculateTemperatureScore(averageTemperature: number): number
	local idealMid = (IDEAL_TEMP_MIN + IDEAL_TEMP_MAX) / 2
	local deviation = math.abs(averageTemperature - idealMid)
	local comfortableMax = (IDEAL_TEMP_MAX - IDEAL_TEMP_MIN) / 2 + COMFORTABLE_RANGE

	if deviation <= comfortableMax then
		-- Within comfortable range: linear falloff from 100 to 60
		local ratio = deviation / comfortableMax
		return 100 - (ratio * 40)
	else
		-- Outside comfortable range: exponential penalty
		local excessDeviation = deviation - comfortableMax
		local penalty = math.min(excessDeviation * 3, 60)
		return math.max(0, 60 - penalty)
	end
end

-- Extract comfort score from item specification
local function getItemComfortScore(spec: { [string]: any }): number
	-- Check for explicit ComfortScore field
	if typeof(spec.ComfortScore) == "number" then
		return spec.ComfortScore
	end

	-- Infer from tags if not explicit
	local tags = spec.Tags
	if typeof(tags) ~= "table" then
		return 0
	end

	-- Check quality tags
	for _, tag in ipairs(tags) do
		if tag == "Luxury" then
			return DEFAULT_COMFORT_SCORES.Luxury
		elseif tag == "Premium" then
			return DEFAULT_COMFORT_SCORES.Premium
		elseif tag == "Comfort" then
			return DEFAULT_COMFORT_SCORES.Standard
		elseif tag == "Basic" then
			return DEFAULT_COMFORT_SCORES.Basic
		end
	end

	return 0
end

-- Determine furniture type from item specification
local function getFurnitureType(spec: { [string]: any }): string?
	local tags = spec.Tags
	if typeof(tags) ~= "table" then
		return nil
	end

	for _, tag in ipairs(tags) do
		if FURNITURE_TYPE_SCALES[tag] then
			return tag
		end
	end

	return nil
end

-- Calculate furniture comfort score from placed items
local function calculateFurnitureScore(
	placedItems: { [string]: { id: string } },
	residentCount: number,
	tenantCount: number
): (number, { [string]: number })
	local breakdown: { [string]: number } = {}
	local totalComfort = 0
	local itemCounts: { [string]: number } = {}

	-- Accumulate comfort from all furniture
	for _, record in pairs(placedItems) do
		local itemId = record.id
		if typeof(itemId) ~= "string" or itemId == "" then
			continue
		end

		local spec = ItemFinder.FindItemById(itemId)
		if not spec then
			continue
		end

		local comfortScore = getItemComfortScore(spec)
		if comfortScore <= 0 then
			continue
		end

		-- Apply type scale
		local furnitureType = getFurnitureType(spec)
		local scale = if furnitureType then (FURNITURE_TYPE_SCALES[furnitureType] or 1.0) else 1.0

		-- Apply diminishing returns for duplicate items
		local count = (itemCounts[itemId] or 0) + 1
		itemCounts[itemId] = count
		local diminishingFactor = math.pow(0.85, count - 1)

		local contribution = comfortScore * scale * diminishingFactor
		totalComfort += contribution

		-- Track breakdown by type
		local categoryKey = furnitureType or "Other"
		breakdown[categoryKey] = (breakdown[categoryKey] or 0) + contribution
	end

	-- Normalize based on occupancy
	local occupancy = math.max(1, residentCount + tenantCount)
	local targetComfort = occupancy * 8 -- Target: 8 comfort points per occupant
	local normalizedScore = math.clamp((totalComfort / targetComfort) * 100, 0, 100)

	return normalizedScore, breakdown
end

-- Calculate overall comfort rating
function ComfortRating.Calculate(
	placedItems: { [string]: { id: string } },
	averageTemperature: number?,
	residentCount: number?,
	tenantCount: number?
): ComfortComponents
	local residents = residentCount or 0
	local tenants = tenantCount or 0

	-- Calculate furniture component
	local furnitureScore, breakdown = calculateFurnitureScore(placedItems, residents, tenants)

	-- Calculate temperature component
	local temperatureScore = 50 -- Default to neutral if no temperature provided
	if typeof(averageTemperature) == "number" then
		temperatureScore = calculateTemperatureScore(averageTemperature)
	end

	-- Weighted average
	local totalScore = (furnitureScore * FURNITURE_WEIGHT) + (temperatureScore * TEMPERATURE_WEIGHT)

	return {
		FurnitureScore = furnitureScore,
		TemperatureScore = temperatureScore,
		TotalScore = totalScore,
		FurnitureBreakdown = breakdown,
	}
end

-- Convert 0-100 score to 0-5 star rating
function ComfortRating.ScoreToStars(score: number): number
	return math.clamp((score / 100) * 5, 0, 5)
end

-- Get a descriptive note based on score
function ComfortRating.GetScoreNote(score: number): string
	if score >= 85 then
		return "Residents can spread out in supreme comfort."
	elseif score >= 70 then
		return "Comfortable setup with quality furnishings."
	elseif score >= 55 then
		return "A few more comfort items would help."
	elseif score >= 35 then
		return "Add better seating and beds for relief."
	else
		return "Urgent: residents lack basic comfort amenities."
	end
end

return ComfortRating
