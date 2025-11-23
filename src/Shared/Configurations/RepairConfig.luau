--!strict
-- ReplicatedStorage/Shared/Configurations/RepairConfig.luau
-- Central tuning knobs for the break/repair mechanic.

export type DefaultProfile = {
	BaseIntervalSeconds: number,
	IntervalJitterPercent: number,
	SeverityMin: number,
	SeverityMax: number,
	RewardMultiplier: number,
	MinReward: number,
	MaxReward: number,
	CompletionDistance: number,
	PromptHoldSeconds: number,
}

export type TagProfile = {
	IntervalScale: number?,
	RewardScale: number?,
	SeverityBoost: number?,
}

local RepairConfig = {
	UpdateIntervalSeconds = 4.5,
	MaxBreaksPerStep = 2,
	DefaultProfile = {
		BaseIntervalSeconds = 420,
		IntervalJitterPercent = 0.35,
		SeverityMin = 0.35,
		SeverityMax = 0.85,
		RewardMultiplier = 0.045,
		MinReward = 20,
		MaxReward = 180,
		CompletionDistance = 12,
		PromptHoldSeconds = 1.25,
	},
	TagProfiles = {
		Appliance = {
			IntervalScale = 0.8,
			RewardScale = 1.25,
			SeverityBoost = 0.05,
		},
		Electronics = {
			IntervalScale = 0.9,
			RewardScale = 1.1,
		},
		Utility = {
			IntervalScale = 0.85,
			RewardScale = 1.3,
			SeverityBoost = 0.08,
		},
	},
}

return RepairConfig
