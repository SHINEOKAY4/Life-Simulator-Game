--!strict
-- Shared/Configurations/TenantConfig.luau
-- Central tuning table for property valuation, tenant offer cadence, and rent enforcement.

export type ScoreTier = {
	Id: string,
	MinScore: number,
	RentMultiplier: number,
}

export type LeaseWindow = {
	MinSeconds: number,
	MaxSeconds: number,
}

export type ValuationConfig = {
	RefreshIntervalSeconds: number,
	ChunkValue: number,
	CostWeight: number,
	DecorWeight: number,
	MinimumRent: number,
	RentPerPoint: number,
	DefaultTierId: string,
	ScoreTiers: { ScoreTier },
	AmenityWeights: { [string]: number },
	AmenitySoftCaps: { [string]: number },
	ExcessAmenityMultiplier: number,
	TagWeights: { [string]: number },
	DiminishingReturnFactor: number,
	VarietyBonusPerCategory: number,
	ThemeSynergyBonus: number,
	LuxuryThreshold: number,
	LuxuryBonusMultiplier: number,
}

export type OffersConfig = {
	MinIntervalSeconds: number,
	MaxIntervalSeconds: number,
	CooldownSeconds: number,
	OfferLifetimeSeconds: number,
	RentVariancePercent: number,
	LeaseDurations: { [string]: LeaseWindow },
	DefaultLease: LeaseWindow,
	NamePool: { string },
}

export type RentConfig = {
	IntervalSeconds: number,
	GraceSeconds: number,
	MaxMissedPayments: number,
	DepositPercent: number,
	LateFeePercent: number,
}

export type TenantConfig = {
	Valuation: ValuationConfig,
	Offers: OffersConfig,
	Rent: RentConfig,
}

local Valuation: ValuationConfig = {
	RefreshIntervalSeconds = 30,
	ChunkValue = 150,
	CostWeight = 0.35,
	DecorWeight = 0.25,
	MinimumRent = 40,
	RentPerPoint = 0.12,
	DefaultTierId = "Barebones",
	ScoreTiers = {
		{ Id = "Barebones", MinScore = 0, RentMultiplier = 0.85 },
		{ Id = "Cozy", MinScore = 600, RentMultiplier = 1.0 },
		{ Id = "Upgraded", MinScore = 1200, RentMultiplier = 1.12 },
		{ Id = "Premium", MinScore = 1900, RentMultiplier = 1.28 },
	},
	AmenityWeights = {
		RestStation = 150,
		HygieneStation = 120,
		FunStation = 115,
		ComfortStation = 90,
		SocialStation = 80,
		SkillStation = 100,
	},
	AmenitySoftCaps = {
		RestStation = 2,
		HygieneStation = 1,
		FunStation = 2,
		ComfortStation = 2,
	},
	ExcessAmenityMultiplier = 0.4,
	TagWeights = {
		Luxury = 35,
		Comfort = 25,
		Basic = 5,
		Modern = 15,
		Outdoor = 12,
		Utility = 10,
	},
	DiminishingReturnFactor = 0.85, -- Each subsequent item of same ID is worth 85% of previous
	VarietyBonusPerCategory = 0.05, -- +5% score per unique amenity category present
	ThemeSynergyBonus = 0.15, -- +15% score if >50% of decor shares a theme
	LuxuryThreshold = 500, -- Items costing more than this get a bonus
	LuxuryBonusMultiplier = 1.2, -- 20% bonus for luxury items
}

local Offers: OffersConfig = {
	MinIntervalSeconds = 180,
	MaxIntervalSeconds = 320,
	CooldownSeconds = 90,
	OfferLifetimeSeconds = 180,
	RentVariancePercent = 0.08,
	LeaseDurations = {
		Barebones = { MinSeconds = 600, MaxSeconds = 900 },
		Cozy = { MinSeconds = 900, MaxSeconds = 1200 },
		Upgraded = { MinSeconds = 1200, MaxSeconds = 1500 },
		Premium = { MinSeconds = 1500, MaxSeconds = 1800 },
	},
	DefaultLease = { MinSeconds = 900, MaxSeconds = 1200 },
	NamePool = {
		"Maya",
		"Dion",
		"Rafi",
		"Emilia",
		"June",
		"Kade",
		"Nisha",
		"Reid",
		"Sel",
		"Theo",
		"Vera",
		"Zuri",
	},
}

local Rent: RentConfig = {
	IntervalSeconds = 360,
	GraceSeconds = 120,
	MaxMissedPayments = 2,
	DepositPercent = 0.6,
	LateFeePercent = 0.05,
}

local TenantConfig: TenantConfig = {
	Valuation = Valuation,
	Offers = Offers,
	Rent = Rent,
}

return TenantConfig
