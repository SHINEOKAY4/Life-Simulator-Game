--!strict
-- Server/Services/TenantService/DataNormalization.luau
-- Sanitizes and normalizes tenant save data structures

local ValidationUtils = require(script.Parent.ValidationUtils)

local INFINITE_LEASE_END = math.huge

local DataNormalization = {}

export type TenantOffer = {
	OfferId: string,
	TierId: string,
	RentPerInterval: number,
	Deposit: number,
	LeaseSeconds: number,
	RentIntervalSeconds: number,
	TenantName: string,
	CreatedUnix: number,
	ExpiresUnix: number,
	Score: number,
	RentBoostPercent: number?,
	Traits: { string }?,
}

export type TenantLease = {
	TenantId: string,
	TierId: string,
	RentPerInterval: number,
	RentIntervalSeconds: number,
	LeaseEndUnix: number,
	NextDueUnix: number,
	MissedPayments: number,
	DepositHeld: number,
	StartedUnix: number,
	AccruedRemainder: number?,
	RentBoostPercent: number?,
	Traits: { string }?,
	TenantName: string?,
	NextReviewUnix: number?,
	RoomKey: string?,
}

export type TenantStateSave = {
	Version: number?,
	LastOfferUnix: number?,
	OfferSequence: number?,
	PendingOffer: TenantOffer? | boolean?,
	ActiveLease: TenantLease? | boolean?,
	ActiveLeases: { [string]: TenantLease }?,
	OutstandingRent: number?,
	LastKnownScore: number?,
	MailboxBalance: number?,
	RoomAssignments: { [string]: number }?,
}

export type RoomAssignmentMap = { [string]: number }

function DataNormalization.SanitizeOffer(offer: any, now: number, rentConfig: any, offersConfig: any)
	if typeof(offer) ~= "table" then
		return
	end
	offer.RentIntervalSeconds = ValidationUtils.EnsureNumber(offer.RentIntervalSeconds, rentConfig.IntervalSeconds)
	offer.LeaseSeconds = ValidationUtils.EnsureNumber(offer.LeaseSeconds, offersConfig.DefaultLease.MaxSeconds)
	offer.Deposit = ValidationUtils.EnsureNumber(
		offer.Deposit,
		math.floor((offer.RentPerInterval or 0) * rentConfig.DepositPercent + 0.5)
	)
	offer.ExpiresUnix = ValidationUtils.EnsureNumber(offer.ExpiresUnix, now + offersConfig.OfferLifetimeSeconds)
end

function DataNormalization.SanitizeLease(lease: TenantLease, now: number, rentIntervalSeconds: number)
	lease.RentIntervalSeconds = ValidationUtils.EnsureNumber(lease.RentIntervalSeconds, rentIntervalSeconds)
	lease.NextDueUnix = ValidationUtils.EnsureNumber(lease.NextDueUnix, now + lease.RentIntervalSeconds)
	lease.LeaseEndUnix = ValidationUtils.EnsureNumber(lease.LeaseEndUnix, INFINITE_LEASE_END)
	lease.MissedPayments = ValidationUtils.EnsureNumber(lease.MissedPayments, 0)
	lease.DepositHeld = ValidationUtils.EnsureNumber(lease.DepositHeld, 0)
	lease.StartedUnix = ValidationUtils.EnsureNumber(lease.StartedUnix, now)
	lease.AccruedRemainder = ValidationUtils.EnsureNumber(lease.AccruedRemainder, 0)
	lease.NextReviewUnix = ValidationUtils.EnsureNumber(lease.NextReviewUnix, now + lease.RentIntervalSeconds * 3)
end

function DataNormalization.EnsureActiveLeases(
	save: TenantStateSave,
	now: number,
	rentIntervalSeconds: number
): { [string]: TenantLease }
	local leases = ValidationUtils.EnsureTable(save.ActiveLeases, {})
	save.ActiveLeases = leases
	local resolved = leases :: { [string]: TenantLease }

	-- Migrate legacy single-lease format
	local legacy = save.ActiveLease
	if typeof(legacy) == "table" then
		local tenantId = legacy.TenantId
		if not tenantId or resolved[tenantId] then
			tenantId = string.format("LegacyTenant-%d", math.floor(now))
		end
		legacy.TenantId = tenantId
		resolved[tenantId] = legacy
		save.ActiveLease = nil
	end

	-- Sanitize all leases
	for tenantId, lease in resolved do
		if typeof(lease) ~= "table" then
			resolved[tenantId] = nil :: any
		else
			lease.TenantId = lease.TenantId or tenantId
			DataNormalization.SanitizeLease(lease, now, rentIntervalSeconds)
		end
	end

	return resolved
end

function DataNormalization.EnsureRoomAssignments(save: TenantStateSave): RoomAssignmentMap
	local assignments = ValidationUtils.EnsureTable(save.RoomAssignments, {})
	save.RoomAssignments = assignments

	for key, count in pairs(assignments) do
		if not ValidationUtils.EnsureString(key, nil) or not ValidationUtils.IsValidNumber(count, 1) then
			assignments[key] = nil :: any
		else
			assignments[key] = math.floor(count + 0.5)
		end
	end

	return assignments :: RoomAssignmentMap
end

return DataNormalization
