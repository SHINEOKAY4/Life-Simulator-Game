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
}

return TraitConfig
