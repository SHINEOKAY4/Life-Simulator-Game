--!strict
-- ReplicatedStorage/Shared/Utilities/TraitUtils.luau
-- Aggregates per-trait modifiers for decay multipliers and autonomy scoring bias.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TraitConfig = require(ReplicatedStorage.Shared.Configurations.TraitConfig)

local TraitUtils = {}

type TraitProfile = TraitConfig.TraitProfile

local function resolveTrait(traitName: string): TraitProfile?
	return TraitConfig[traitName]
end

local function iterTraits(traits: { string }?): () -> (number?, string?)
	local list = traits or {}
	local index = 0
	return function()
		index += 1
		local value = list[index]
		if value ~= nil then
			return index, value
		end
		return nil, nil
	end
end

function TraitUtils.GetNeedDecayMultiplier(traits: { string }?, needName: string): number
	local multiplier = 1
	for _, traitName in iterTraits(traits) do
		if traitName then
			local profile = resolveTrait(traitName)
			local lookup = profile and profile.NeedDecayMultipliers
			local traitMultiplier = lookup and lookup[needName]
			if traitMultiplier ~= nil then
				multiplier *= traitMultiplier
			end
		end
	end
	return multiplier
end

function TraitUtils.GetNeedScoreBias(traits: { string }?, needName: string): number
	local bias = 0
	for _, traitName in iterTraits(traits) do
		if traitName then
			local profile = resolveTrait(traitName)
			local lookup = profile and profile.NeedScoreBias
			local traitBias = lookup and lookup[needName]
			if traitBias ~= nil then
				bias += traitBias
			end
		end
	end
	return bias
end

return TraitUtils
