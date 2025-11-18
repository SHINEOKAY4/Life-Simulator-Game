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
	ChunkValue = 250,
	CostWeight = 0.35,
	DecorWeight = 0.25,
	MinimumRent = 120,
	RentPerPoint = 0.65,
	DefaultTierId = "Barebones",
	ScoreTiers = {
		{ Id = "Barebones", MinScore = 0, RentMultiplier = 0.85 },
		{ Id = "Cozy", MinScore = 600, RentMultiplier = 1.0 },
		{ Id = "Upgraded", MinScore = 1200, RentMultiplier = 1.12 },
		{ Id = "Premium", MinScore = 1900, RentMultiplier = 1.28 },
	},
	AmenityWeights = {
		RestStation = 180,
		HygieneStation = 140,
		FunStation = 135,
		ComfortStation = 110,
		SocialStation = 100,
		SkillStation = 115,
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
	IntervalSeconds = 300,
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
