--!strict

export type AchievementReward = {
	Cash: number?,
	Experience: number?,
}

export type AchievementDefinition = {
	Id: string,
	Name: string,
	Description: string,
	Category: string,
	StatKey: string,
	TargetValue: number,
	SortOrder: number,
	Rewards: AchievementReward?,
}

local list: { AchievementDefinition } = {
	{
		Id = "builder_novice",
		Name = "Blueprint Beginner",
		Description = "Place 25 objects in build mode.",
		Category = "Building",
		StatKey = "BuildPlacements",
		TargetValue = 25,
		SortOrder = 10,
		Rewards = { Cash = 150, Experience = 40 },
	},
	{
		Id = "builder_pro",
		Name = "Master Builder",
		Description = "Place 150 objects in build mode.",
		Category = "Building",
		StatKey = "BuildPlacements",
		TargetValue = 150,
		SortOrder = 11,
		Rewards = { Cash = 500, Experience = 120 },
	},
	{
		Id = "chores_starter",
		Name = "Clean Sweep",
		Description = "Complete 10 chores.",
		Category = "Household",
		StatKey = "ChoresCompleted",
		TargetValue = 10,
		SortOrder = 20,
		Rewards = { Cash = 225, Experience = 55 },
	},
	{
		Id = "chores_veteran",
		Name = "Caretaker",
		Description = "Complete 50 chores.",
		Category = "Household",
		StatKey = "ChoresCompleted",
		TargetValue = 50,
		SortOrder = 21,
		Rewards = { Cash = 800, Experience = 180 },
	},
	{
		Id = "tenant_help_first",
		Name = "Helping Hand",
		Description = "Resolve 5 tenant help requests.",
		Category = "Tenants",
		StatKey = "TenantHelpsCompleted",
		TargetValue = 5,
		SortOrder = 30,
		Rewards = { Cash = 250, Experience = 60 },
	},
	{
		Id = "tenant_help_expert",
		Name = "Beloved Landlord",
		Description = "Resolve 30 tenant help requests.",
		Category = "Tenants",
		StatKey = "TenantHelpsCompleted",
		TargetValue = 30,
		SortOrder = 31,
		Rewards = { Cash = 1200, Experience = 260 },
	},
	{
		Id = "crafting_novice",
		Name = "First Workshop",
		Description = "Complete 5 crafting jobs.",
		Category = "Crafting",
		StatKey = "CraftingJobsCompleted",
		TargetValue = 5,
		SortOrder = 40,
		Rewards = { Cash = 175, Experience = 70 },
	},
	{
		Id = "crafting_expert",
		Name = "Assembly Line",
		Description = "Complete 40 crafting jobs.",
		Category = "Crafting",
		StatKey = "CraftingJobsCompleted",
		TargetValue = 40,
		SortOrder = 41,
		Rewards = { Cash = 900, Experience = 280 },
	},
	{
		Id = "level_5",
		Name = "Up and Running",
		Description = "Reach player level 5.",
		Category = "Progression",
		StatKey = "HighestLevelReached",
		TargetValue = 5,
		SortOrder = 50,
		Rewards = { Cash = 350, Experience = 0 },
	},
	{
		Id = "level_12",
		Name = "Established Owner",
		Description = "Reach player level 12.",
		Category = "Progression",
		StatKey = "HighestLevelReached",
		TargetValue = 12,
		SortOrder = 51,
		Rewards = { Cash = 1400, Experience = 0 },
	},
	{
		Id = "daily_first",
		Name = "First Check-In",
		Description = "Claim your first daily reward.",
		Category = "Daily",
		StatKey = "DailyRewardsClaimed",
		TargetValue = 1,
		SortOrder = 60,
		Rewards = { Cash = 100, Experience = 25 },
	},
	{
		Id = "daily_week",
		Name = "Weekly Regular",
		Description = "Claim 7 daily rewards.",
		Category = "Daily",
		StatKey = "DailyRewardsClaimed",
		TargetValue = 7,
		SortOrder = 61,
		Rewards = { Cash = 400, Experience = 100 },
	},
	{
		Id = "daily_streak_14",
		Name = "Fortnight Streak",
		Description = "Reach a 14-day daily reward streak.",
		Category = "Daily",
		StatKey = "DailyRewardLongestStreak",
		TargetValue = 14,
		SortOrder = 62,
		Rewards = { Cash = 750, Experience = 200 },
	},
}

local byId: { [string]: AchievementDefinition } = {}
for _, definition in ipairs(list) do
	byId[definition.Id] = definition
end

table.sort(list, function(a, b)
	if a.SortOrder == b.SortOrder then
		return a.Id < b.Id
	end
	return a.SortOrder < b.SortOrder
end)

local AchievementDefinitions = {
	List = list,
	ById = byId,
}

function AchievementDefinitions.GetById(achievementId: string): AchievementDefinition?
	return byId[achievementId]
end

return table.freeze(AchievementDefinitions)
