-- Tests/Specs/MailboxPruneSpec.lua
-- Validates single-pass mailbox prune equivalence (Iter 8).
-- Combines structural checks on the TenantService source with pure-math
-- equivalence proofs that batched income produces the same balance as
-- per-lease income calls.

local function readFile(path)
	local file = assert(io.open(path, "r"), "missing file: " .. path)
	local contents = file:read("*a")
	file:close()
	return contents
end

-- Pure clamp logic mirrored from AttributeManager (no Roblox deps)
local MAX_MAILBOX_BALANCE = 4294967295

local function clampMailboxAmount(amount)
	if amount ~= amount then
		return 0
	end
	local rounded = math.floor(amount + 0.5)
	if rounded < 0 then
		return 0
	elseif rounded > MAX_MAILBOX_BALANCE then
		return MAX_MAILBOX_BALANCE
	end
	return rounded
end

-- Pure EnsureBalance mirrored from MailboxManager
local function ensureBalance(save)
	local rawValue = save.MailboxBalance
	local numeric = type(rawValue) == "number" and rawValue or 0
	return clampMailboxAmount(numeric)
end

-- Pure AddIncome mirrored from MailboxManager
local function addIncome(save, amount)
	if amount <= 0 then
		return ensureBalance(save)
	end
	local currentBalance = ensureBalance(save)
	local updatedBalance = clampMailboxAmount(currentBalance + amount)
	save.MailboxBalance = updatedBalance
	save.OutstandingRent = 0
	return updatedBalance
end

-- Pure income-rate mirrored from LeaseManager
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

-- ServiceLease income accumulation mirrored from LeaseManager
local function serviceLease(lease, deltaTime)
	local rate = getIncomePerSecond(lease)
	if rate <= 0 then
		return 0
	end
	local accumulated = (lease.AccruedRemainder or 0) + rate * deltaTime
	if accumulated <= 0 then
		return 0
	end
	local payout = math.floor(accumulated)
	-- note: don't mutate lease here so we can call both approaches on same data
	return payout, accumulated - payout
end

local function makeLease(tenantId, rent, interval, leaseEndUnix, accrued)
	return {
		TenantId = tenantId,
		TierId = "Basic",
		RentPerInterval = rent,
		RentIntervalSeconds = interval,
		LeaseEndUnix = leaseEndUnix or math.huge,
		NextDueUnix = 0,
		MissedPayments = 0,
		DepositHeld = 0,
		StartedUnix = 0,
		AccruedRemainder = accrued or 0,
		RentBoostPercent = 0,
		Traits = {},
		TenantName = "Tenant_" .. tenantId,
		NextReviewUnix = math.huge,
		RoomKey = "room1",
	}
end

-- ========================================
-- TESTS
-- ========================================

describe("MailboxPrune single-pass equivalence", function()
	-- Structural checks on the actual source
	describe("structural: serviceLease uses single-pass pattern", function()
		local src

		before_each(function()
			src = readFile("src/Server/Services/TenantService/init.luau")
		end)

		it("collects expired IDs in an expiredIds list", function()
			assert.is_truthy(
				string.find(src, "expiredIds", 1, true),
				"serviceLease should collect expired lease IDs into an expiredIds list"
			)
		end)

		it("accumulates totalIncome across active leases", function()
			assert.is_truthy(
				string.find(src, "totalIncome", 1, true),
				"serviceLease should accumulate income in a totalIncome variable"
			)
		end)

		it("applies income in a single batch after the loop", function()
			local loopEnd = string.find(src, "-- Apply accumulated income", 1, true)
			assert.is_truthy(loopEnd, "single-batch income application comment should exist")
			local afterLoop = string.sub(src, loopEnd, loopEnd + 200)
			assert.is_truthy(
				string.find(afterLoop, "totalIncome > 0", 1, true),
				"should guard on totalIncome > 0 before applying"
			)
			assert.is_truthy(
				string.find(afterLoop, "AddIncome", 1, true),
				"should call AddIncome once with accumulated total"
			)
		end)

		it("concludes expired leases after iteration completes", function()
			local concludeSection = string.find(src, "-- Conclude expired leases after iteration", 1, true)
			assert.is_truthy(concludeSection, "post-iteration conclude comment should exist")
			local afterSection = string.sub(src, concludeSection, concludeSection + 200)
			assert.is_truthy(
				string.find(afterSection, "concludeLease", 1, true),
				"should call concludeLease for each expired tenant"
			)
		end)

		it("does not call broadcastMailboxBalance inside the main lease loop", function()
			-- Find the single-pass loop (between "Single pass" and "Apply accumulated")
			local loopStart = string.find(src, "-- Single pass:", 1, true)
			local loopEnd = string.find(src, "-- Apply accumulated income", 1, true)
			assert.is_truthy(loopStart and loopEnd, "single-pass loop boundaries should exist")
			local loopBody = string.sub(src, loopStart, loopEnd)
			assert.is_falsy(
				string.find(loopBody, "broadcastMailboxBalance", 1, true),
				"broadcastMailboxBalance should NOT appear inside the lease loop"
			)
		end)
	end)

	-- Pure math: batched income equals sum of per-lease income
	describe("income accumulation equivalence", function()
		it("batched AddIncome matches sequential per-lease calls", function()
			local amounts = { 5, 12, 3, 8, 1 }

			-- Sequential: call AddIncome for each amount
			local seqSave = { MailboxBalance = 100, OutstandingRent = 0 }
			for _, amount in ipairs(amounts) do
				addIncome(seqSave, amount)
			end

			-- Batched: sum amounts then call AddIncome once
			local batchSave = { MailboxBalance = 100, OutstandingRent = 0 }
			local total = 0
			for _, amount in ipairs(amounts) do
				total = total + amount
			end
			addIncome(batchSave, total)

			assert.equals(seqSave.MailboxBalance, batchSave.MailboxBalance)
		end)

		it("batched result matches for fractional amounts", function()
			local amounts = { 0.7, 1.3, 2.5 }

			local seqSave = { MailboxBalance = 50, OutstandingRent = 0 }
			for _, amount in ipairs(amounts) do
				addIncome(seqSave, amount)
			end

			local batchSave = { MailboxBalance = 50, OutstandingRent = 0 }
			local total = 0
			for _, amount in ipairs(amounts) do
				total = total + amount
			end
			addIncome(batchSave, total)

			assert.equals(seqSave.MailboxBalance, batchSave.MailboxBalance)
		end)

		it("zero income does not change balance", function()
			local save = { MailboxBalance = 200, OutstandingRent = 0 }
			local before = save.MailboxBalance
			addIncome(save, 0)
			assert.equals(before, save.MailboxBalance)
		end)

		it("negative income does not change balance", function()
			local save = { MailboxBalance = 200, OutstandingRent = 0 }
			local before = save.MailboxBalance
			addIncome(save, -10)
			assert.equals(before, save.MailboxBalance)
		end)
	end)

	-- Expired lease partitioning
	describe("expired lease partitioning", function()
		it("separates expired and active leases correctly", function()
			local now = 1000
			local leases = {
				active1 = makeLease("active1", 60, 60, 2000),
				active2 = makeLease("active2", 120, 60, 1500),
				expired1 = makeLease("expired1", 30, 60, 500),
				expired2 = makeLease("expired2", 90, 60, 999),
				boundary = makeLease("boundary", 45, 60, 1000), -- LeaseEndUnix == now → expired
			}

			local expiredIds = {}
			local activeIds = {}
			for tenantId, lease in pairs(leases) do
				if lease.LeaseEndUnix <= now then
					table.insert(expiredIds, tenantId)
				else
					table.insert(activeIds, tenantId)
				end
			end

			table.sort(expiredIds)
			table.sort(activeIds)

			assert.equals(3, #expiredIds)
			assert.equals(2, #activeIds)
			assert.same({ "boundary", "expired1", "expired2" }, expiredIds)
			assert.same({ "active1", "active2" }, activeIds)
		end)

		it("returns no expired when all leases are active", function()
			local now = 1000
			local leases = {
				a = makeLease("a", 60, 60, 2000),
				b = makeLease("b", 60, 60, 3000),
			}

			local hasExpired = false
			for _, lease in pairs(leases) do
				if lease.LeaseEndUnix <= now then
					hasExpired = true
					break
				end
			end

			assert.is_false(hasExpired)
		end)

		it("accumulates income only from active leases", function()
			local now = 1000
			local deltaTime = 10
			local leases = {
				active = makeLease("active", 60, 60, 2000, 0),
				expired = makeLease("expired", 120, 60, 500, 0),
			}

			local totalIncome = 0
			for _, lease in pairs(leases) do
				if lease.LeaseEndUnix > now then
					local payout = serviceLease(lease, deltaTime)
					totalIncome = totalIncome + payout
				end
			end

			-- Only active lease: rate=1/sec, deltaTime=10 → accumulated=10 → payout=10
			assert.equals(10, totalIncome)
		end)
	end)

	-- End-to-end mailbox state after prune
	describe("mailbox state after single-pass prune", function()
		it("preserves mailbox balance for mixed expired/active leases", function()
			local now = 1000
			local deltaTime = 5
			local leases = {
				a = makeLease("a", 120, 60, 2000, 0),  -- active, rate=2/sec
				b = makeLease("b", 60, 60, 2000, 0.5), -- active, rate=1/sec, accrued=0.5
				c = makeLease("c", 60, 60, 800, 0),    -- expired
			}
			local save = { MailboxBalance = 100, OutstandingRent = 0 }

			-- Simulate old approach: per-lease AddIncome
			local oldSave = { MailboxBalance = 100, OutstandingRent = 0 }
			for _, lease in pairs(leases) do
				if lease.LeaseEndUnix > now then
					local payout = serviceLease(lease, deltaTime)
					if payout > 0 then
						addIncome(oldSave, payout)
					end
				end
			end

			-- Simulate new approach: accumulated AddIncome
			local totalIncome = 0
			for _, lease in pairs(leases) do
				if lease.LeaseEndUnix > now then
					local payout = serviceLease(lease, deltaTime)
					totalIncome = totalIncome + payout
				end
			end
			if totalIncome > 0 then
				addIncome(save, totalIncome)
			end

			assert.equals(oldSave.MailboxBalance, save.MailboxBalance)
		end)

		it("mailbox unchanged when all leases expired", function()
			local now = 1000
			local leases = {
				x = makeLease("x", 60, 60, 500, 0),
				y = makeLease("y", 90, 60, 800, 0),
			}
			local save = { MailboxBalance = 42, OutstandingRent = 0 }

			local totalIncome = 0
			for _, lease in pairs(leases) do
				if lease.LeaseEndUnix > now then
					local payout = serviceLease(lease, 5)
					totalIncome = totalIncome + payout
				end
			end
			if totalIncome > 0 then
				addIncome(save, totalIncome)
			end

			assert.equals(42, save.MailboxBalance)
		end)
	end)
end)
