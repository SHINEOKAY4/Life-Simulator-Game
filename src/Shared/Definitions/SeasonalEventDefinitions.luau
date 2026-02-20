--!strict
-- SeasonalEventDefinitions: per-season gameplay modifiers, XP/cash multipliers,
-- themed challenges, and seasonal milestone rewards.
-- Seasons are aligned with WeatherConfig (Spring/Summer/Autumn/Winter).

export type SeasonId = "Spring" | "Summer" | "Autumn" | "Winter"

export type SeasonalBuff = {
	Type: string, -- "XPMultiplier" | "CashMultiplier" | "CraftSpeedMultiplier"
	Value: number,
	Label: string,
}

export type SeasonalChallenge = {
	Id: string,
	Name: string,
	Description: string,
	StatKey: string,
	TargetValue: number,
	RewardCash: number,
	RewardExperience: number,
}

export type SeasonalMilestone = {
	SeasonsCompleted: number,
	BonusCash: number,
	BonusExperience: number,
	Label: string,
}

export type SeasonDefinition = {
	Id: SeasonId,
	Name: string,
	Description: string,
	DurationDays: number,
	Buffs: { SeasonalBuff },
	Challenges: { SeasonalChallenge },
}

-- Each season lasts 5 in-game days (matches WeatherConfig.DaysPerSeason).
local SEASONS: { SeasonDefinition } = {
	{
		Id = "Spring",
		Name = "Spring Bloom",
		Description = "Renewal and growth. Building rewards are increased.",
		DurationDays = 5,
		Buffs = {
			{ Type = "XPMultiplier", Value = 1.15, Label = "+15% Build XP" },
		},
		Challenges = {
			{
				Id = "spring_builder",
				Name = "Spring Construction",
				Description = "Place 20 objects during Spring.",
				StatKey = "SeasonalBuildPlacements",
				TargetValue = 20,
				RewardCash = 300,
				RewardExperience = 75,
			},
			{
				Id = "spring_green",
				Name = "Green Thumb",
				Description = "Complete 8 chores during Spring.",
				StatKey = "SeasonalChoresCompleted",
				TargetValue = 8,
				RewardCash = 200,
				RewardExperience = 50,
			},
		},
	},
	{
		Id = "Summer",
		Name = "Summer Heat",
		Description = "Peak season for tenants. Rental income is boosted.",
		DurationDays = 5,
		Buffs = {
			{ Type = "CashMultiplier", Value = 1.20, Label = "+20% Rental Income" },
		},
		Challenges = {
			{
				Id = "summer_landlord",
				Name = "Summer Landlord",
				Description = "Help 6 tenants during Summer.",
				StatKey = "SeasonalTenantHelps",
				TargetValue = 6,
				RewardCash = 350,
				RewardExperience = 80,
			},
			{
				Id = "summer_crafter",
				Name = "Beat the Heat",
				Description = "Complete 5 crafting jobs during Summer.",
				StatKey = "SeasonalCraftingJobs",
				TargetValue = 5,
				RewardCash = 250,
				RewardExperience = 60,
			},
		},
	},
	{
		Id = "Autumn",
		Name = "Autumn Harvest",
		Description = "Crafting efficiency increases. Prepare for Winter.",
		DurationDays = 5,
		Buffs = {
			{ Type = "CraftSpeedMultiplier", Value = 1.25, Label = "+25% Craft Speed" },
		},
		Challenges = {
			{
				Id = "autumn_crafter",
				Name = "Harvest Workshop",
				Description = "Complete 10 crafting jobs during Autumn.",
				StatKey = "SeasonalCraftingJobs",
				TargetValue = 10,
				RewardCash = 400,
				RewardExperience = 90,
			},
			{
				Id = "autumn_trader",
				Name = "Fall Market",
				Description = "Complete 3 trades during Autumn.",
				StatKey = "SeasonalTradesCompleted",
				TargetValue = 3,
				RewardCash = 300,
				RewardExperience = 70,
			},
		},
	},
	{
		Id = "Winter",
		Name = "Winter Chill",
		Description = "Harsh conditions test your property. Repair bonuses active.",
		DurationDays = 5,
		Buffs = {
			{ Type = "XPMultiplier", Value = 1.20, Label = "+20% Repair XP" },
		},
		Challenges = {
			{
				Id = "winter_repair",
				Name = "Winter Maintenance",
				Description = "Complete 12 chores during Winter.",
				StatKey = "SeasonalChoresCompleted",
				TargetValue = 12,
				RewardCash = 450,
				RewardExperience = 100,
			},
			{
				Id = "winter_warmth",
				Name = "Keep Warm",
				Description = "Help 4 tenants during Winter.",
				StatKey = "SeasonalTenantHelps",
				TargetValue = 4,
				RewardCash = 275,
				RewardExperience = 65,
			},
		},
	},
}

-- Milestones awarded once when the player completes N full seasonal cycles.
local MILESTONES: { SeasonalMilestone } = {
	{ SeasonsCompleted = 4, BonusCash = 500, BonusExperience = 120, Label = "First Year" },
	{ SeasonsCompleted = 8, BonusCash = 1000, BonusExperience = 250, Label = "Seasoned Veteran" },
	{ SeasonsCompleted = 20, BonusCash = 2500, BonusExperience = 600, Label = "All-Weather Pro" },
}

local byId: { [string]: SeasonDefinition } = {}
for _, season in ipairs(SEASONS) do
	byId[season.Id] = season
end

local challengeById: { [string]: SeasonalChallenge } = {}
for _, season in ipairs(SEASONS) do
	for _, challenge in ipairs(season.Challenges) do
		challengeById[challenge.Id] = challenge
	end
end

local SeasonalEventDefinitions = {
	Seasons = SEASONS,
	Milestones = MILESTONES,
	ById = byId,
	ChallengeById = challengeById,
}

function SeasonalEventDefinitions.GetSeason(seasonId: string): SeasonDefinition?
	return byId[seasonId]
end

function SeasonalEventDefinitions.GetChallenge(challengeId: string): SeasonalChallenge?
	return challengeById[challengeId]
end

function SeasonalEventDefinitions.GetMilestoneForCount(seasonsCompleted: number): SeasonalMilestone?
	for _, milestone in ipairs(MILESTONES) do
		if milestone.SeasonsCompleted == seasonsCompleted then
			return milestone
		end
	end
	return nil
end

function SeasonalEventDefinitions.GetBuffsForSeason(seasonId: string): { SeasonalBuff }
	local season = byId[seasonId]
	if not season then
		return {}
	end
	return season.Buffs
end

function SeasonalEventDefinitions.GetChallengesForSeason(seasonId: string): { SeasonalChallenge }
	local season = byId[seasonId]
	if not season then
		return {}
	end
	return season.Challenges
end

return table.freeze(SeasonalEventDefinitions)
