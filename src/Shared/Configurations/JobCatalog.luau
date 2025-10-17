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
}

export type JobRarityWeights = { [JobRarity]: number }

local Jobs: { JobEntry } = {
	-- Common offerings
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
		Rarity = "Common",
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
		Rarity = "Common",
	},
	{
		Id = "DogWalkerGig",
		Name = "Dog Walker",
		Type = "Gig",
		Description = "Pick up neighborhood pups and keep them moving while owners are away.",
		BasePay = 20,
		PayUnit = "Run",
		MoodAffectsPay = true,
		Highlight = "Short routes with steady tips for reliable walkers.",
		Requirements = {
			{ Stat = "Fitness", Level = 1 },
		},
		Rarity = "Common",
	},
	{
		Id = "GroceryClerk",
		Name = "Grocery Clerk",
		Type = "Profession",
		Description = "Stock shelves, help shoppers, and keep the aisles organized.",
		BasePay = 19,
		PayUnit = "Minute",
		MoodAffectsPay = true,
		Highlight = "Great for disciplined residents building routine.",
		Requirements = {
			{ Stat = "Discipline", Level = 1 },
		},
		Rarity = "Common",
	},
	{
		Id = "NightSecurity",
		Name = "Night Security",
		Type = "Profession",
		Description = "Patrol local businesses after hours and respond quickly to alerts.",
		BasePay = 22,
		PayUnit = "Minute",
		MoodAffectsPay = true,
		Highlight = "Overnight shifts favor vigilant, steady residents.",
		Requirements = {
			{ Stat = "Discipline", Level = 1 },
			{ Stat = "Fitness", Level = 1 },
		},
		Rarity = "Common",
	},
	{
		Id = "HomeCleanerGig",
		Name = "Home Cleaning",
		Type = "Gig",
		Description = "Tidy homes, polish surfaces, and reset living spaces for busy clients.",
		BasePay = 23,
		PayUnit = "Run",
		MoodAffectsPay = true,
		Highlight = "Reliable payout for detail-driven cleaners.",
		Requirements = {
			{ Stat = "Discipline", Level = 1 },
		},
		Rarity = "Common",
	},
	{
		Id = "CommunityGardenerGig",
		Name = "Community Gardener",
		Type = "Gig",
		Description = "Maintain shared green spaces, water beds, and keep the flowers thriving.",
		BasePay = 21,
		PayUnit = "Run",
		MoodAffectsPay = true,
		Highlight = "Perfect for outdoorsy residents with steady hands.",
		Requirements = {
			{ Stat = "Fitness", Level = 1 },
			{ Stat = "Discipline", Level = 1 },
		},
		Rarity = "Common",
	},
	{
		Id = "StreetVendor",
		Name = "Street Vendor",
		Type = "Gig",
		Description = "Set up pop-up stalls, pitch products, and delight passersby.",
		BasePay = 24,
		PayUnit = "Run",
		MoodAffectsPay = true,
		Highlight = "Energetic socializers can turn charm into extra sales.",
		Requirements = {
			{ Stat = "Social", Level = 1 },
		},
		Rarity = "Common",
	},

	-- Uncommon opportunities
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
		Rarity = "Uncommon",
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
		Rarity = "Uncommon",
	},
	{
		Id = "SousChef",
		Name = "Sous Chef",
		Type = "Profession",
		Description = "Prep ingredients, manage the line, and keep plates flowing during dinner rush.",
		BasePay = 30,
		PayUnit = "Minute",
		MoodAffectsPay = true,
		Highlight = "Demands precision and stamina in a fast kitchen.",
		Requirements = {
			{ Stat = "Discipline", Level = 2 },
			{ Stat = "Creativity", Level = 1 },
		},
		Rarity = "Uncommon",
	},
	{
		Id = "Bookkeeper",
		Name = "Bookkeeper",
		Type = "Profession",
		Description = "Balance ledgers, reconcile invoices, and advise small businesses on daily finances.",
		BasePay = 32,
		PayUnit = "Minute",
		MoodAffectsPay = true,
		Highlight = "Steady pay for detail-oriented number crunchers.",
		Requirements = {
			{ Stat = "Intelligence", Level = 3 },
			{ Stat = "Discipline", Level = 2 },
		},
		Rarity = "Uncommon",
	},
	{
		Id = "EventCoordinator",
		Name = "Event Coordinator",
		Type = "Profession",
		Description = "Plan community events, keep vendors aligned, and solve issues on the fly.",
		BasePay = 28,
		PayUnit = "Minute",
		MoodAffectsPay = true,
		Highlight = "Rewards social planners who keep cool under pressure.",
		Requirements = {
			{ Stat = "Social", Level = 3 },
			{ Stat = "Discipline", Level = 2 },
		},
		Rarity = "Uncommon",
	},
	{
		Id = "Lifeguard",
		Name = "Lifeguard",
		Type = "Profession",
		Description = "Oversee pool safety, perform rescues, and maintain facility readiness.",
		BasePay = 29,
		PayUnit = "Minute",
		MoodAffectsPay = true,
		Highlight = "Strong swimmers with quick reflexes thrive here.",
		Requirements = {
			{ Stat = "Fitness", Level = 3 },
			{ Stat = "Discipline", Level = 2 },
		},
		Rarity = "Uncommon",
	},
	{
		Id = "LabAssistant",
		Name = "Lab Assistant",
		Type = "Profession",
		Description = "Prepare experiments, log findings, and keep research stations sterile.",
		BasePay = 33,
		PayUnit = "Minute",
		MoodAffectsPay = true,
		Highlight = "Hands-on role for analytical residents pursuing science.",
		Requirements = {
			{ Stat = "Intelligence", Level = 3 },
			{ Stat = "Discipline", Level = 2 },
		},
		Rarity = "Uncommon",
	},

	-- Rare careers
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
		Rarity = "Rare",
	},
	{
		Id = "FinancialAnalyst",
		Name = "Financial Analyst",
		Type = "Profession",
		Description = "Model portfolios, brief clients, and spot trends before the market moves.",
		BasePay = 42,
		PayUnit = "Minute",
		MoodAffectsPay = true,
		Highlight = "Rewards sharp math skills and steady discipline.",
		Requirements = {
			{ Stat = "Intelligence", Level = 5 },
			{ Stat = "Discipline", Level = 4 },
		},
		Rarity = "Rare",
	},
	{
		Id = "UrbanPlanner",
		Name = "Urban Planner",
		Type = "Profession",
		Description = "Map neighborhood growth, analyze traffic patterns, and guide city zoning meetings.",
		BasePay = 44,
		PayUnit = "Minute",
		MoodAffectsPay = true,
		Highlight = "Strategic thinkers shape the city's future foundations.",
		Requirements = {
			{ Stat = "Intelligence", Level = 5 },
			{ Stat = "Creativity", Level = 3 },
		},
		Rarity = "Rare",
	},
	{
		Id = "RoboticsEngineer",
		Name = "Robotics Engineer",
		Type = "Profession",
		Description = "Design autonomous systems, prototype bots, and fine-tune control software.",
		BasePay = 48,
		PayUnit = "Minute",
		MoodAffectsPay = true,
		Highlight = "High-skill role demanding top-tier intelligence and discipline.",
		Requirements = {
			{ Stat = "Intelligence", Level = 6 },
			{ Stat = "Discipline", Level = 4 },
		},
		Rarity = "Rare",
	},

	-- Elite placements
	{
		Id = "ChiefScientist",
		Name = "Chief Scientist",
		Type = "Profession",
		Description = "Lead breakthrough research teams, secure funding, and steer long-term discovery.",
		BasePay = 58,
		PayUnit = "Minute",
		MoodAffectsPay = true,
		Highlight = "Prestigious position for the city's brightest minds.",
		Requirements = {
			{ Stat = "Intelligence", Level = 7 },
			{ Stat = "Discipline", Level = 5 },
			{ Stat = "Creativity", Level = 4 },
		},
		Rarity = "Elite",
	},
	{
		Id = "CelebrityChef",
		Name = "Celebrity Chef",
		Type = "Profession",
		Description = "Host televised cooking segments, design signature menus, and wow elite patrons.",
		BasePay = 55,
		PayUnit = "Minute",
		MoodAffectsPay = true,
		Highlight = "High-status role where creativity and discipline meet fame.",
		Requirements = {
			{ Stat = "Creativity", Level = 6 },
			{ Stat = "Discipline", Level = 4 },
			{ Stat = "Social", Level = 4 },
		},
		Rarity = "Elite",
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
