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
		Weight = 20,
		Effects = { TipMultiplier = 1.25 },
		DisplayColor = Color3.fromRGB(100, 255, 100),
	},
	{
		Id = "Stingy",
		Name = "Stingy",
		Description = "Tips 25% less.",
		Weight = 20,
		Effects = { TipMultiplier = 0.75 },
		DisplayColor = Color3.fromRGB(255, 100, 100),
	},
	{
		Id = "HighRoller",
		Name = "High Roller",
		Description = "Tips 50% more!",
		Weight = 5,
		Effects = { TipMultiplier = 1.5 },
		DisplayColor = Color3.fromRGB(100, 255, 100),
	},
	{
		Id = "Cheapskate",
		Name = "Cheapskate",
		Description = "Tips 50% less.",
		Weight = 5,
		Effects = { TipMultiplier = 0.5 },
		DisplayColor = Color3.fromRGB(255, 100, 100),
	},
	{
		Id = "Negotiator",
		Name = "Negotiator",
		Description = "Pays 5% less rent.",
		Weight = 15,
		Effects = { RentMultiplier = 0.95 },
		DisplayColor = Color3.fromRGB(255, 100, 100),
	},
	{
		Id = "Investor",
		Name = "Investor",
		Description = "Pays 10% more rent.",
		Weight = 5,
		Effects = { RentMultiplier = 1.1 },
		DisplayColor = Color3.fromRGB(100, 255, 100),
	},
	{
		Id = "CleanFreak",
		Name = "Clean Freak",
		Description = "Hygiene decays 50% faster.",
		Weight = 10,
		Effects = { NeedDecayMultipliers = { Hygiene = 1.5 } },
		DisplayColor = Color3.fromRGB(255, 100, 100),
	},
	{
		Id = "Slob",
		Name = "Slob",
		Description = "Hygiene decays 30% slower.",
		Weight = 10,
		Effects = { NeedDecayMultipliers = { Hygiene = 0.7 } },
		DisplayColor = Color3.fromRGB(100, 255, 100),
	},
	{
		Id = "Glutton",
		Name = "Glutton",
		Description = "Hunger decays 50% faster.",
		Weight = 10,
		Effects = { NeedDecayMultipliers = { Hunger = 1.5 } },
		DisplayColor = Color3.fromRGB(255, 100, 100),
	},
	{
		Id = "Ascetic",
		Name = "Ascetic",
		Description = "Hunger decays 30% slower.",
		Weight = 10,
		Effects = { NeedDecayMultipliers = { Hunger = 0.7 } },
		DisplayColor = Color3.fromRGB(100, 255, 100),
	},
	{
		Id = "Socialite",
		Name = "Socialite",
		Description = "Social needs decay 50% faster.",
		Weight = 10,
		Effects = { NeedDecayMultipliers = { Social = 1.5 } },
		DisplayColor = Color3.fromRGB(255, 100, 100),
	},
	{
		Id = "Loner",
		Name = "Loner",
		Description = "Social needs decay 30% slower.",
		Weight = 10,
		Effects = { NeedDecayMultipliers = { Social = 0.7 } },
		DisplayColor = Color3.fromRGB(100, 255, 100),
	},
	{
		Id = "Karen",
		Name = "Demanding",
		Description = "Gets dissatisfied twice as fast.",
		Weight = 5,
		Effects = { DissatisfactionMultiplier = 2.0 },
		DisplayColor = Color3.fromRGB(255, 100, 100),
	},
	{
		Id = "Chill",
		Name = "Chill",
		Description = "Gets dissatisfied half as fast.",
		Weight = 5,
		Effects = { DissatisfactionMultiplier = 0.5 },
		DisplayColor = Color3.fromRGB(100, 255, 100),
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
