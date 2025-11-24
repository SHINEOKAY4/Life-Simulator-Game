--!strict
-- Server/Services/TenantService/LeaseManager.luau
-- Manages tenant lease lifecycle: creation, servicing, termination

local DataNormalization = require(script.Parent.DataNormalization)

type TenantLease = DataNormalization.TenantLease
type TenantOffer = DataNormalization.TenantOffer
type RoomAssignmentMap = DataNormalization.RoomAssignmentMap

local INFINITE_LEASE_END = math.huge

local LeaseManager = {}

function LeaseManager.GetIncomePerSecond(lease: TenantLease): number
	local interval = lease.RentIntervalSeconds
	if typeof(interval) ~= "number" or interval <= 0 then
		return 0
	end

	local rent = lease.RentPerInterval
	if typeof(rent) ~= "number" or rent <= 0 then
		return 0
	end

	return rent / interval
end

function LeaseManager.CalculateTotalIncomeRate(leases: { [string]: TenantLease }?): number
	if typeof(leases) ~= "table" then
		return 0
	end

	local totalRate = 0
	for _, lease in pairs(leases) do
		totalRate += LeaseManager.GetIncomePerSecond(lease)
	end

	if totalRate ~= totalRate or totalRate <= 0 then -- NaN check
		return 0
	end

	return totalRate
end

function LeaseManager.ServiceLease(
	lease: TenantLease,
	now: number,
	deltaTime: number,
	onIncome: (amount: number) -> (),
	onReview: () -> ()
)
	if deltaTime <= 0 then
		return
	end

	local rate = LeaseManager.GetIncomePerSecond(lease)
	if rate <= 0 then
		lease.AccruedRemainder = 0
		lease.NextDueUnix = now + lease.RentIntervalSeconds
		return
	end

	local accumulated = (lease.AccruedRemainder or 0) + rate * deltaTime
	if accumulated <= 0 then
		lease.AccruedRemainder = 0
		lease.NextDueUnix = now + lease.RentIntervalSeconds
		lease.MissedPayments = 0
		return
	end

	local payout = math.floor(accumulated)
	lease.AccruedRemainder = accumulated - payout
	lease.NextDueUnix = now + lease.RentIntervalSeconds
	lease.MissedPayments = 0

	if payout > 0 then
		onIncome(payout)
	end

	-- Periodic Review Check
	if lease.NextReviewUnix and now >= lease.NextReviewUnix then
		onReview()
		lease.NextReviewUnix = now + (lease.RentIntervalSeconds or 0) * 3
	end
end

function LeaseManager.CreateLease(offer: TenantOffer, roomKey: string, now: number): TenantLease
	return {
		TenantId = offer.OfferId,
		TierId = offer.TierId,
		RentPerInterval = offer.RentPerInterval,
		RentIntervalSeconds = offer.RentIntervalSeconds,
		LeaseEndUnix = INFINITE_LEASE_END,
		NextDueUnix = now + offer.RentIntervalSeconds,
		MissedPayments = 0,
		DepositHeld = offer.Deposit,
		StartedUnix = now,
		AccruedRemainder = 0,
		RentBoostPercent = offer.RentBoostPercent or 0,
		Traits = offer.Traits,
		TenantName = offer.TenantName,
		NextReviewUnix = now + offer.RentIntervalSeconds * 3,
		RoomKey = roomKey,
	}
end

function LeaseManager.AssignLease(
	leases: { [string]: TenantLease },
	lease: TenantLease,
	assignments: RoomAssignmentMap
): string
	local uniqueId = lease.TenantId
	local suffix = 1
	while leases[uniqueId] do
		suffix += 1
		uniqueId = string.format("%s-%d", lease.TenantId, suffix)
	end

	lease.TenantId = uniqueId
	leases[uniqueId] = lease

	-- Increment room assignment
	if lease.RoomKey then
		local current = assignments[lease.RoomKey] or 0
		assignments[lease.RoomKey] = current + 1
	end

	return uniqueId
end

function LeaseManager.BuildClientPayload(leases: { [string]: TenantLease }): { any }
	local payload = {}
	for _, lease in pairs(leases) do
		payload[#payload + 1] = {
			TenantId = lease.TenantId,
			Name = lease.TenantName or "Unknown",
			TierId = lease.TierId,
			Traits = lease.Traits or {},
			Rent = lease.RentPerInterval,
			RentInterval = lease.RentIntervalSeconds,
			Boost = lease.RentBoostPercent or 0,
			RoomKey = lease.RoomKey or "",
		}
	end
	return payload
end

function LeaseManager.BuildSingleClientPayload(lease: TenantLease?): { any }
	if not lease then
		return {}
	end
	return {
		{
			TenantId = lease.TenantId,
			Name = lease.TenantName or "Unknown",
			TierId = lease.TierId,
			Traits = lease.Traits or {},
			Rent = lease.RentPerInterval,
			RentInterval = lease.RentIntervalSeconds,
			Boost = lease.RentBoostPercent or 0,
			RoomKey = lease.RoomKey or "",
		},
	}
end

return LeaseManager
