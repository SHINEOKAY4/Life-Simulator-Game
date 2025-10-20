--!strict
-- ReplicatedStorage/Shared/Utilities/TraitUtils.luau
-- Aggregates per-trait modifiers for decay multipliers and autonomy scoring bias.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TraitConfig = require(ReplicatedStorage.Shared.Configurations.TraitConfig)

local TraitUtils = {}

type TraitProfile = TraitConfig.TraitProfile

function TraitUtils.GetNeedDecayMultiplier(traits: { string }?, needName: string): number
	if not traits then
		return 1
	end
	
	local multiplier = 1
	for i = 1, #traits do
		local traitName = traits[i]
		local profile = TraitConfig[traitName]
		if profile then
			local lookup = profile.NeedDecayMultipliers
			if lookup then
				local traitMultiplier = lookup[needName]
				if traitMultiplier ~= nil then
					multiplier *= traitMultiplier
				end
			end
		end
	end
	return multiplier
end

function TraitUtils.GetNeedScoreBias(traits: { string }?, needName: string): number
	if not traits then
		return 0
	end
	
	local bias = 0
	for i = 1, #traits do
		local traitName = traits[i]
		local profile = TraitConfig[traitName]
		if profile then
			local lookup = profile.NeedScoreBias
			if lookup then
				local traitBias = lookup[needName]
				if traitBias ~= nil then
					bias += traitBias
				end
			end
		end
	end
	return bias
end

return TraitUtils
