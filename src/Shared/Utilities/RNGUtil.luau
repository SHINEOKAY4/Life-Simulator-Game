--!strict

local RNGUtil = {}

local DEFAULT_RANDOM = Random.new()

local function resolveRandom(randomObject: Random?): Random
	if randomObject ~= nil then
		return randomObject
	end

	return DEFAULT_RANDOM
end

function RNGUtil.NextInteger(minValue: number, maxValue: number, randomObject: Random?): number
	assert(minValue <= maxValue, "minValue must be <= maxValue")
	return resolveRandom(randomObject):NextInteger(minValue, maxValue)
end

function RNGUtil.NextNumber(minValue: number, maxValue: number?, randomObject: Random?): number
	local rng = resolveRandom(randomObject)
	if maxValue == nil then
		return rng:NextNumber() * minValue
	end

	assert(minValue <= maxValue, "minValue must be <= maxValue")
	return rng:NextNumber(minValue, maxValue)
end

function RNGUtil.PickRandom<T>(items: { T }, randomObject: Random?): T
	assert(#items > 0, "items must not be empty")
	local index = RNGUtil.NextInteger(1, #items, randomObject)
	return items[index]
end

function RNGUtil.Shuffle<T>(items: { T }, randomObject: Random?): { T }
	local shuffled = table.clone(items)
	local rng = resolveRandom(randomObject)

	for index = #shuffled, 2, -1 do
		local swapIndex = rng:NextInteger(1, index)
		shuffled[index], shuffled[swapIndex] = shuffled[swapIndex], shuffled[index]
	end

	return shuffled
end

type WeightedEntry<T> = { value: T, weight: number }

function RNGUtil.PickWeighted<T>(items: { WeightedEntry<T> }, randomObject: Random?): T
	assert(#items > 0, "items must not be empty")

	local totalWeight = 0
	for _, item in ipairs(items) do
		assert(item.weight >= 0, "weight must be >= 0")
		totalWeight += item.weight
	end

	assert(totalWeight > 0, "at least one item must have positive weight")

	local target = RNGUtil.NextNumber(0, totalWeight, randomObject)
	local runningWeight = 0
	for _, item in ipairs(items) do
		runningWeight += item.weight
		if target <= runningWeight then
			return item.value
		end
	end

	return items[#items].value
end

-- Legacy aliases used by old scripts.
RNGUtil.RandomInt = RNGUtil.NextInteger
RNGUtil.RandomFloat = RNGUtil.NextNumber
RNGUtil.Choose = RNGUtil.PickRandom
RNGUtil.WeightedChoose = RNGUtil.PickWeighted

return RNGUtil
