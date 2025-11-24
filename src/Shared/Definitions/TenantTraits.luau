--!strict
-- Shared/Definitions/TenantTraits.luau

export type TraitEffect = {
	TipMultiplier: number?,
	RentMultiplier: number?,
	NeedDecayMultipliers: { [string]: number }?,
	DissatisfactionMultiplier: number?,
}

export type TenantTraitDefinition = {
	Id: string,
	Name: string,
	Description: string,
	Weight: number,
	Effects: TraitEffect?,
	DisplayColor: Color3?,
}

local TenantTraits = {}

local TRAITS: { TenantTraitDefinition } = {
	{
		Id = "Generous",
		Name = "Generous",
		Description = "Tips 25% more when satisfied.",
		Weight = 18,
		Effects = { TipMultiplier = 1.25 },
		DisplayColor = Color3.fromRGB(100, 255, 100),
	},
	{
		Id = "Stingy",
		Name = "Stingy",
		Description = "Tips 25% less.",
		Weight = 18,
		Effects = { TipMultiplier = 0.75 },
		DisplayColor = Color3.fromRGB(255, 100, 100),
	},
	{
		Id = "HighRoller",
		Name = "High Roller",
		Description = "Tips 50% more!",
		Weight = 6,
		Effects = { TipMultiplier = 1.5 },
		DisplayColor = Color3.fromRGB(100, 255, 100),
	},
	{
		Id = "Cheapskate",
		Name = "Cheapskate",
		Description = "Tips 50% less.",
		Weight = 6,
		Effects = { TipMultiplier = 0.5 },
		DisplayColor = Color3.fromRGB(255, 100, 100),
	},
	{
		Id = "Investor",
		Name = "Investor",
		Description = "Pays 10% more rent for premium service.",
		Weight = 6,
		Effects = { RentMultiplier = 1.1 },
		DisplayColor = Color3.fromRGB(100, 255, 100),
	},
	{
		Id = "Negotiator",
		Name = "Negotiator",
		Description = "Haggles 8% off their rent.",
		Weight = 10,
		Effects = { RentMultiplier = 0.92 },
		DisplayColor = Color3.fromRGB(255, 140, 120),
	},
	{
		Id = "PromptPayer",
		Name = "Prompt Payer",
		Description = "Adds an extra 5% rent to guarantee on-time payments.",
		Weight = 10,
		Effects = { RentMultiplier = 1.05 },
		DisplayColor = Color3.fromRGB(140, 255, 180),
	},
	{
		Id = "CouponClipper",
		Name = "Coupon Clipper",
		Description = "Expects 5% off rent and tips a little less.",
		Weight = 10,
		Effects = { RentMultiplier = 0.95, TipMultiplier = 0.9 },
		DisplayColor = Color3.fromRGB(255, 180, 120),
	},
	{
		Id = "Easygoing",
		Name = "Easygoing",
		Description = "Rarely complains—dissatisfaction builds half as fast.",
		Weight = 8,
		Effects = { DissatisfactionMultiplier = 0.5 },
		DisplayColor = Color3.fromRGB(100, 255, 160),
	},
	{
		Id = "Perfectionist",
		Name = "Perfectionist",
		Description = "Notices every flaw; dissatisfaction builds 40% faster.",
		Weight = 8,
		Effects = { DissatisfactionMultiplier = 1.4 },
		DisplayColor = Color3.fromRGB(255, 120, 120),
	},
	{
		Id = "BigSpender",
		Name = "Big Spender",
		Description = "Drops 35% more in tips whenever amenities shine.",
		Weight = 5,
		Effects = { TipMultiplier = 1.35 },
		DisplayColor = Color3.fromRGB(120, 255, 200),
	},
	{
		Id = "TightBudget",
		Name = "Tight Budget",
		Description = "Tips 20% less but otherwise keeps a low profile.",
		Weight = 7,
		Effects = { TipMultiplier = 0.8 },
		DisplayColor = Color3.fromRGB(255, 160, 160),
	},
}

local TOTAL_WEIGHT = 0
local BY_ID: { [string]: TenantTraitDefinition } = {}

for _, trait in ipairs(TRAITS) do
	TOTAL_WEIGHT += trait.Weight
	BY_ID[trait.Id] = trait
end

function TenantTraits.GetTrait(id: string): TenantTraitDefinition?
	return BY_ID[id]
end

function TenantTraits.RollTraits(rng: Random, count: number?): { string }
	local amount = count or 1
	local result = {}
	local available = table.clone(TRAITS)
	local currentWeight = TOTAL_WEIGHT

	-- Simple weighted selection without replacement
	for _ = 1, amount do
		if #available == 0 then
			break
		end

		local roll = rng:NextNumber() * currentWeight
		local running = 0
		local selectedIndex = -1

		for idx, trait in ipairs(available) do
			running += trait.Weight
			if roll <= running then
				selectedIndex = idx
				break
			end
		end

		if selectedIndex == -1 then
			selectedIndex = #available
		end -- Fallback

		local selected = available[selectedIndex]
		table.insert(result, selected.Id)

		-- Remove selected to avoid duplicates
		currentWeight -= selected.Weight
		table.remove(available, selectedIndex)
	end

	return result
end

return TenantTraits
