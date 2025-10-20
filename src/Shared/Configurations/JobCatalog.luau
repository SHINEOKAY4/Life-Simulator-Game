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
	Type: "Gig" | "Profession",
	Description: string,
	BasePay: number,
	PayUnit: "Run" | "Minute",
	MoodAffectsPay: boolean,
	Highlight: string?,
	Requirements: { Requirement },
	Rarity: JobRarity,
	CooldownSeconds: number?,
	Variance: number?,
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
	{
		Id = "CourierSprint",
		Name = "Courier Sprint",
		Type = "Gig",
		Description = "Dash parcels across town under a ticking timer. Rhythm prompts keep you moving.",
		BasePay = 28,
		PayUnit = "Run",
		MoodAffectsPay = true,
		Highlight = "Fitness-focused gig with burst payouts and short cooldowns.",
		Requirements = {},
		Rarity = "Common",
		CooldownSeconds = 8 * 60,
		Variance = 6,
	},
	{
		Id = "CafePopUp",
		Name = "Cafe Pop-Up",
		Type = "Gig",
		Description = "Host a pop-up barista bar and keep conversations flowing at peak hours.",
		BasePay = 24,
		PayUnit = "Run",
		MoodAffectsPay = true,
		Highlight = "Quick service loop that rewards social timing and charm.",
		Requirements = {},
		Rarity = "Common",
		CooldownSeconds = 6 * 60,
		Variance = 4,
	},
	{
		Id = "DebugJam",
		Name = "Debug Jam",
		Type = "Gig",
		Description = "Solve rapid-fire pattern puzzles to squash bugs before the demo build ships.",
		BasePay = 32,
		PayUnit = "Run",
		MoodAffectsPay = true,
		Highlight = "High-intensity challenge for analytical players chasing bigger payouts.",
		Requirements = {},
		Rarity = "Uncommon",
		CooldownSeconds = 10 * 60,
		Variance = 8,
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
