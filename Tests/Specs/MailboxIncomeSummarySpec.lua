-- Tests/Specs/MailboxIncomeSummarySpec.lua
-- Tests for mailbox income summary: income rate calculations and packet payload shape.
-- LeaseManager.luau uses Luau type aliases that Lua 5.1 cannot parse, so the core
-- income-rate math is replicated inline for testing purposes.

-- Income logic mirrored from LeaseManager (pure math, no Roblox deps)
local function getIncomePerSecond(lease)
	local interval = lease.RentIntervalSeconds
	if type(interval) ~= "number" or interval <= 0 then
		return 0
	end
	local rent = lease.RentPerInterval
	if type(rent) ~= "number" or rent <= 0 then
		return 0
	end
	return rent / interval
end

local function calculateTotalIncomeRate(leases)
	if type(leases) ~= "table" then
		return 0
	end
	local totalRate = 0
	for _, lease in pairs(leases) do
		totalRate = totalRate + getIncomePerSecond(lease)
	end
	if totalRate ~= totalRate or totalRate <= 0 then
		return 0
	end
	return totalRate
end

-- Next-tick logic mirrored from TenantService.broadcastIncomeSummary
local function calculateNextRentTick(leases)
	if type(leases) ~= "table" then
		return 0
	end
	local minTick = math.huge
	for _, lease in pairs(leases) do
		local rate = getIncomePerSecond(lease)
		if rate > 0 then
			local accrued = type(lease.AccruedRemainder) == "number" and lease.AccruedRemainder or 0
			local remaining = 1.0 - accrued
			if remaining <= 0 then
				return 0
			end
			local tickIn = remaining / rate
			if tickIn < minTick then
				minTick = tickIn
			end
		end
	end
	if minTick == math.huge then
		return 0
	end
	return math.max(0, math.floor(minTick + 0.5))
end

-- Minimal lease factory for testing
local function makeLease(rent, interval, accrued)
	return {
		TenantId = "T1",
		TierId = "Basic",
		RentPerInterval = rent,
		RentIntervalSeconds = interval,
		LeaseEndUnix = math.huge,
		NextDueUnix = 0,
		MissedPayments = 0,
		DepositHeld = 0,
		StartedUnix = 0,
		AccruedRemainder = accrued or 0,
		RentBoostPercent = 0,
		Traits = {},
		TenantName = "TestTenant",
		NextReviewUnix = 0,
		RoomKey = "room1",
	}
end

describe("MailboxIncomeSummary", function()
	describe("income rate per second", function()
		it("returns rent/interval for a valid lease", function()
			assert.equals(1, getIncomePerSecond(makeLease(60, 60)))
		end)

		it("returns fractional rate correctly", function()
			local rate = getIncomePerSecond(makeLease(100, 400))
			assert.is_true(math.abs(rate - 0.25) < 0.001)
		end)

		it("returns 0 for zero interval", function()
			assert.equals(0, getIncomePerSecond(makeLease(100, 0)))
		end)

		it("returns 0 for zero rent", function()
			assert.equals(0, getIncomePerSecond(makeLease(0, 60)))
		end)

		it("returns 0 for negative interval", function()
			assert.equals(0, getIncomePerSecond(makeLease(100, -10)))
		end)
	end)

	describe("total income rate across leases", function()
		it("returns 0 for nil leases", function()
			assert.equals(0, calculateTotalIncomeRate(nil))
		end)

		it("returns 0 for empty lease table", function()
			assert.equals(0, calculateTotalIncomeRate({}))
		end)

		it("sums rates from multiple leases", function()
			local leases = {
				t1 = makeLease(60, 60),
				t2 = makeLease(120, 60),
				t3 = makeLease(30, 60),
			}
			local total = calculateTotalIncomeRate(leases)
			assert.is_true(math.abs(total - 3.5) < 0.001)
		end)

		it("ignores leases with zero rate", function()
			local leases = {
				active = makeLease(60, 60),
				inactive = makeLease(0, 60),
			}
			local total = calculateTotalIncomeRate(leases)
			assert.is_true(math.abs(total - 1.0) < 0.001)
		end)
	end)

	describe("next rent tick calculation", function()
		it("returns 0 when no leases", function()
			assert.equals(0, calculateNextRentTick({}))
		end)

		it("returns 0 when accrued remainder makes remaining at or below 0", function()
			local leases = { t1 = makeLease(60, 60, 1.0) }
			assert.equals(0, calculateNextRentTick(leases))
		end)

		it("computes seconds to next drip from accrued remainder", function()
			-- 1/sec; accrued=0.1; remaining=0.9; tickIn=0.9 -> floor(1.4)=1
			local leases = { t1 = makeLease(60, 60, 0.1) }
			assert.equals(1, calculateNextRentTick(leases))
		end)

		it("rounds near-zero remaining to 0", function()
			-- 1/sec; accrued=0.8; remaining=0.2; tickIn=0.2 -> floor(0.7)=0
			local leases = { t1 = makeLease(60, 60, 0.8) }
			assert.equals(0, calculateNextRentTick(leases))
		end)

		it("picks the minimum tick across multiple leases", function()
			-- Lease A: 1/sec, accrued=0.0 -> remaining=1.0 -> tickIn=1 -> 1 sec
			-- Lease B: 2/sec, accrued=0.5 -> remaining=0.5 -> tickIn=0.25 -> 0 sec
			local leases = {
				a = makeLease(60, 60, 0.0),
				b = makeLease(120, 60, 0.5),
			}
			assert.equals(0, calculateNextRentTick(leases))
		end)
	end)

	describe("IncomeSummary packet payload shape", function()
		it("assembles a valid payload table", function()
			local leases = { t1 = makeLease(120, 60, 0.0) }
			local payload = {
				Balance = 500,
				IncomePerSecond = calculateTotalIncomeRate(leases),
				NextRentTick = calculateNextRentTick(leases),
			}
			assert.equals(500, payload.Balance)
			assert.is_true(math.abs(payload.IncomePerSecond - 2.0) < 0.001)
			-- accrued=0, remaining=1.0, rate=2/sec -> tickIn=0.5 -> floor(1.0)=1
			assert.equals(1, payload.NextRentTick)
			assert.equals("number", type(payload.Balance))
			assert.equals("number", type(payload.IncomePerSecond))
			assert.equals("number", type(payload.NextRentTick))
		end)

		it("produces zeros when no active leases", function()
			local payload = {
				Balance = 0,
				IncomePerSecond = calculateTotalIncomeRate({}),
				NextRentTick = calculateNextRentTick({}),
			}
			assert.equals(0, payload.IncomePerSecond)
			assert.equals(0, payload.NextRentTick)
		end)
	end)
end)
