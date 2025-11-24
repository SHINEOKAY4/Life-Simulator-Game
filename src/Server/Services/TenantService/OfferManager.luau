--!strict
-- Server/Services/TenantService/OfferManager.luau
-- Manages offer generation, scheduling, and composition

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TenantDefinitions = require(ReplicatedStorage.Shared.Definitions.TenantDefinitions)
local TenantTraits = require(ReplicatedStorage.Shared.Definitions.TenantTraits)
local DataNormalization = require(script.Parent.DataNormalization)

type TenantOffer = DataNormalization.TenantOffer
type ValuationResult = any

local OfferManager = {}

function OfferManager.ComposeOffer(
	valuation: ValuationResult,
	averageRating: number?,
	offerSequence: number,
	userId: number,
	now: number,
	config: { OffersConfig: any, ValuationConfig: any, RentConfig: any },
	rng: Random
): TenantOffer
	local tierDefinition, tenantName = TenantDefinitions.GetRandomDefinition(rng, averageRating)

	local baseRent = valuation.RentEstimate
	local variance = config.OffersConfig.RentVariancePercent
	if variance > 0 then
		baseRent *= (1 + variance * rng:NextNumber(-1, 1))
	end
	baseRent = math.max(config.ValuationConfig.MinimumRent, math.floor(baseRent + 0.5))

	local rentMultiplier = 1 + (tierDefinition.RentBoostPercent or 0)

	-- Roll traits and apply their rent multipliers
	local traitCount = rng:NextInteger(1, 4)
	local traits = TenantTraits.RollTraits(rng, traitCount)
	for _, traitId in ipairs(traits) do
		local trait = TenantTraits.GetTrait(traitId)
		if trait and trait.Effects and trait.Effects.RentMultiplier then
			rentMultiplier *= trait.Effects.RentMultiplier
		end
	end

	local rent = math.max(config.ValuationConfig.MinimumRent, math.floor(baseRent * rentMultiplier + 0.5))
	local offerId = string.format("%d-%d", userId, offerSequence + 1)

	return {
		OfferId = offerId,
		TierId = tierDefinition.Id,
		RentPerInterval = rent,
		Deposit = 0,
		LeaseSeconds = 0,
		RentIntervalSeconds = config.RentConfig.IntervalSeconds,
		TenantName = tenantName,
		RentBoostPercent = tierDefinition.RentBoostPercent or 0,
		CreatedUnix = now,
		ExpiresUnix = now + config.OffersConfig.OfferLifetimeSeconds,
		Score = valuation.Score,
		Traits = traits,
	}
end

function OfferManager.ScheduleNextOffer(_save: any, now: number, offersConfig: any, rng: Random): number
	local minDelay = offersConfig.MinIntervalSeconds
	local maxDelay = offersConfig.MaxIntervalSeconds
	local delay = minDelay
	if maxDelay > minDelay then
		delay += rng:NextNumber(0, maxDelay - minDelay)
	end
	return now + delay
end

function OfferManager.IsOfferExpired(offer: any?, now: number): boolean
	if typeof(offer) ~= "table" then
		return false
	end
	return offer.ExpiresUnix <= now
end

function OfferManager.HasPendingOffer(save: any): boolean
	return typeof(save.PendingOffer) == "table"
end

return OfferManager
