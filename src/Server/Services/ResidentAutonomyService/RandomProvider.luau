--!strict

local RandomProvider = {}

local sharedRandom = Random.new()

function RandomProvider.get(): Random
	return sharedRandom
end

return RandomProvider
