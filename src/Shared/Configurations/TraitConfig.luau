--!strict
-- ReplicatedStorage/Shared/Configurations/TraitConfig.luau
-- Defines trait-driven modifiers used by the resident autonomy and need systems.

export type TraitProfile = {
	NeedDecayMultipliers: { [string]: number }?,
	NeedScoreBias: { [string]: number }?,
}

local TraitConfig: { [string]: TraitProfile } = {
	Balanced = {
		NeedDecayMultipliers = {},
		NeedScoreBias = {},
	},
	Energetic = {
		NeedDecayMultipliers = {
			Energy = 0.85,
		},
		NeedScoreBias = {
			Fun = 0.1,
		},
	},
	Socialite = {
		NeedDecayMultipliers = {
			Social = 0.75,
		},
		NeedScoreBias = {
			Social = 0.3,
		},
	},
	Neat = {
		NeedDecayMultipliers = {
			Hygiene = 0.8,
		},
		NeedScoreBias = {
			Hygiene = 0.15,
		},
	},
	NightOwl = {
		NeedDecayMultipliers = {
			Energy = 1.1,
		},
		NeedScoreBias = {
			Energy = -0.15,
		},
	},
	Lazy = {
		NeedDecayMultipliers = {
			Energy = 1.2, -- Gets tired faster
		},
		NeedScoreBias = {
			Energy = 0.2, -- Wants to sleep/sit sooner
			Fun = -0.1, -- Less interested in active fun
		},
	},
	Playful = {
		NeedDecayMultipliers = {
			Fun = 1.5, -- Gets bored faster
		},
		NeedScoreBias = {
			Fun = 0.25, -- Prioritizes fun
		},
	},
}

return TraitConfig
