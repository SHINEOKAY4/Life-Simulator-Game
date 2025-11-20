--!strict
-- Shared/Definitions/TenantDefinitions.luau
-- Weighted tenant tier metadata used for prospect generation and rent tuning.

export type TenantTierDefinition = {
	Id: string,
	SpawnWeight: number,
	RentBoostPercent: number,
	Names: { string },
}

local TenantDefinitions = {}

local TIERS: { TenantTierDefinition } = {
	{
		Id = "Barebones",
		SpawnWeight = 45,
		RentBoostPercent = 0,
		Names = { "Maya", "Dion", "Rafi", "Emilia" },
	},
	{
		Id = "Cozy",
		SpawnWeight = 30,
		RentBoostPercent = 0.12,
		Names = { "June", "Kade", "Nisha", "Reid" },
	},
	{
		Id = "Upgraded",
		SpawnWeight = 18,
		RentBoostPercent = 0.22,
		Names = { "Sel", "Theo", "Vera" },
	},
	{
		Id = "Premium",
		SpawnWeight = 7,
		RentBoostPercent = 0.35,
		Names = { "Zuri", "Lena", "Atlas" },
	},
}

local TOTAL_WEIGHT = 0
local BY_ID: { [string]: TenantTierDefinition } = {}
for _, def in ipairs(TIERS) do
	TOTAL_WEIGHT += def.SpawnWeight
	BY_ID[def.Id] = def
end

local DEFAULT_TIER = TIERS[1]

function TenantDefinitions.GetDefinition(id: string): TenantTierDefinition?
	return BY_ID[id]
end

local function pickName(def: TenantTierDefinition, rng: Random): string
	local pool = def.Names
	if #pool == 0 then
		return "Tenant"
	end
	return pool[rng:NextInteger(1, #pool)]
end

function TenantDefinitions.GetRandomDefinition(
	randomObject: Random?,
	averageRating: number?
): (TenantTierDefinition, string)
	local rng = randomObject or Random.new()

	local dynamicWeights = {}
	local dynamicTotal = 0

	for _, def in ipairs(TIERS) do
		local weight = def.SpawnWeight

		if averageRating then
			if def.Id == "Premium" then
				if averageRating >= 4.5 then
					weight *= 4.0
				elseif averageRating >= 4.0 then
					weight *= 2.5
				elseif averageRating < 3.0 then
					weight *= 0.1
				end
			elseif def.Id == "Upgraded" then
				if averageRating >= 4.0 then
					weight *= 1.8
				elseif averageRating >= 3.5 then
					weight *= 1.2
				elseif averageRating < 2.5 then
					weight *= 0.4
				end
			elseif def.Id == "Cozy" then
				if averageRating >= 3.0 and averageRating < 4.0 then
					weight *= 1.2
				end
			elseif def.Id == "Barebones" then
				if averageRating < 2.0 then
					weight *= 3.0
				elseif averageRating < 3.0 then
					weight *= 1.5
				elseif averageRating >= 4.0 then
					weight *= 0.3
				end
			end
		end

		dynamicWeights[def.Id] = weight
		dynamicTotal += weight
	end

	local roll = rng:NextNumber() * dynamicTotal
	local running = 0
	for _, def in ipairs(TIERS) do
		running += dynamicWeights[def.Id] or 0
		if roll <= running then
			return def, pickName(def, rng)
		end
	end
	return DEFAULT_TIER, pickName(DEFAULT_TIER, rng)
end

function TenantDefinitions.Iter()
	return ipairs(TIERS)
end

return TenantDefinitions
