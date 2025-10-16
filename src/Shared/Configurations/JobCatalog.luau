--!strict
-- ReplicatedStorage/Shared/Configurations/JobCatalog.lua

export type Requirement = {
	Stat: string,
	Level: number,
}

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
}

local Jobs: { JobEntry } = {
	{
		Id = "CafeCrew",
		Name = "Cafe Crew",
		Type = "Profession",
		Description = "Keep the neighborhood cafe humming. Prep orders, keep the counter tidy, and make every guest feel welcome.",
		BasePay = 18,
		PayUnit = "Minute",
		MoodAffectsPay = true,
		Highlight = "Stable shifts with gentle discipline growth.",
		Requirements = {
			{ Stat = "Discipline", Level = 1 },
		},
	},
	{
		Id = "OfficeAssistant",
		Name = "Office Assistant",
		Type = "Profession",
		Description = "Support the office team by filing paperwork, routing calls, and keeping tasks on schedule.",
		BasePay = 24,
		PayUnit = "Minute",
		MoodAffectsPay = true,
		Highlight = "Great stepping stone for focused, detail-oriented residents.",
		Requirements = {
			{ Stat = "Intelligence", Level = 2 },
			{ Stat = "Discipline", Level = 1 },
		},
	},
	{
		Id = "CourierGig",
		Name = "Courier Run",
		Type = "Gig",
		Description = "Pick up parcels across town and deliver them quick. Routes change daily, so stay sharp.",
		BasePay = 25,
		PayUnit = "Run",
		MoodAffectsPay = true,
		Highlight = "Always available, solid baseline cash, performance varies with route length.",
		Requirements = {},
	},
	{
		Id = "JuniorProgrammer",
		Name = "Junior Programmer",
		Type = "Profession",
		Description = "Squash bugs, review code, and learn from senior engineers while shipping real features.",
		BasePay = 36,
		PayUnit = "Minute",
		MoodAffectsPay = true,
		Highlight = "High-paying role for residents who invest in study habits.",
		Requirements = {
			{ Stat = "Intelligence", Level = 4 },
			{ Stat = "Discipline", Level = 2 },
		},
	},
	{
		Id = "FitnessTrainer",
		Name = "Fitness Trainer",
		Type = "Profession",
		Description = "Coach clients through workouts, track their gains, and keep energy high on the floor.",
		BasePay = 34,
		PayUnit = "Minute",
		MoodAffectsPay = true,
		Highlight = "Mood and social presence shine in this active career.",
		Requirements = {
			{ Stat = "Fitness", Level = 4 },
			{ Stat = "Social", Level = 2 },
		},
	},
}

return {
	Jobs = Jobs,
}
