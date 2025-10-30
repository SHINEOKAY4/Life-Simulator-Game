--!strict
-- ReplicatedStorage/Shared/Configurations/JobCatalog.lua

export type Requirement = {
	Stat: string,
	Level: number,
}

export type JobRarity = "Common" | "Uncommon" | "Rare" | "Elite"

export type JobEntry = {
	Id: string,
	Name: string,
	Type: "Profession",
	Description: string,
	BasePay: number,
	PayUnit: "Minute",
	MoodAffectsPay: boolean,
	Highlight: string?,
	Requirements: { Requirement },
	Rarity: JobRarity,
}

export type JobRarityWeights = { [JobRarity]: number }

local Jobs: { JobEntry } = {
	{
		Id = "CafeCrew",
		Name = "Cafe Crew",
		Type = "Profession",
		Description = "Keep the neighborhood cafe humming with warm service and tidy prep.",
		BasePay = 18,
		PayUnit = "Minute",
		MoodAffectsPay = true,
		Highlight = "Stable entry-level shifts that reward consistent discipline.",
		Requirements = {
			{ Stat = "Discipline", Level = 0 },
		},
		Rarity = "Common",
	},
	{
		Id = "OfficeAssistant",
		Name = "Office Assistant",
		Type = "Profession",
		Description = "Support the office team by routing calls, filing paperwork, and keeping tasks on schedule.",
		BasePay = 24,
		PayUnit = "Minute",
		MoodAffectsPay = true,
		Highlight = "Great stepping stone for focused, detail-oriented residents.",
		Requirements = {
			{ Stat = "Intelligence", Level = 2 },
			{ Stat = "Discipline", Level = 1 },
		},
		Rarity = "Uncommon",
	},
	{
		Id = "JuniorProgrammer",
		Name = "Junior Programmer",
		Type = "Profession",
		Description = "Squash bugs, learn from seniors, and help ship real features in a friendly studio.",
		BasePay = 36,
		PayUnit = "Minute",
		MoodAffectsPay = true,
		Highlight = "High-paying role for residents who invest in study habits.",
		Requirements = {
			{ Stat = "Intelligence", Level = 4 },
			{ Stat = "Discipline", Level = 2 },
		},
		Rarity = "Rare",
	},
	{
		Id = "FitnessTrainer",
		Name = "Fitness Trainer",
		Type = "Profession",
		Description = "Coach clients through workouts, log their gains, and keep energy high on the floor.",
		BasePay = 34,
		PayUnit = "Minute",
		MoodAffectsPay = true,
		Highlight = "Mood and social presence shine in this active career.",
		Requirements = {
			{ Stat = "Fitness", Level = 4 },
			{ Stat = "Social", Level = 2 },
		},
		Rarity = "Uncommon",
	},
}

local RarityWeights: JobRarityWeights = {
	Common = 60,
	Uncommon = 25,
	Rare = 12,
	Elite = 3,
}

local JobsByRarity: { [JobRarity]: { JobEntry } } = {
	Common = {},
	Uncommon = {},
	Rare = {},
	Elite = {},
}

for _, job in Jobs do
	table.insert(JobsByRarity[job.Rarity], job)
end

return {
	Jobs = Jobs,
	JobsByRarity = JobsByRarity,
	RarityWeights = RarityWeights,
}
