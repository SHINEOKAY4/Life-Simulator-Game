-- Tests/Specs/BillingServiceCycleSpec.lua
-- Inline spec for BillingService billing cycle boundaries and structural wiring.

local function readFile(path)
	local file = assert(io.open(path, "r"), "missing file: " .. path)
	local contents = file:read("*a")
	file:close()
	return contents
end

-- ====================================================================
-- Inline constants replicated from BillingConstants.luau
-- ====================================================================

local CYCLE_DURATION_SECONDS = 1440
local GRACE_PERIOD_SECONDS = 240

-- ====================================================================
-- Inline boundary checks (mirror of BillingService/BillingState logic)
-- ====================================================================

local function isCycleDue(elapsedSeconds, cycleDurationSeconds)
	return elapsedSeconds >= cycleDurationSeconds
end

local function isGracePeriodExpired(unpaidDurationSeconds, gracePeriodSeconds)
	return unpaidDurationSeconds >= gracePeriodSeconds
end

-- ====================================================================
-- Boundary math tests
-- ====================================================================

describe("BillingService cycle boundary math (inline)", function()
	it("does not process a cycle before the duration elapses", function()
		assert.is_false(isCycleDue(CYCLE_DURATION_SECONDS - 1, CYCLE_DURATION_SECONDS))
	end)

	it("processes a cycle at the exact duration boundary", function()
		assert.is_true(isCycleDue(CYCLE_DURATION_SECONDS, CYCLE_DURATION_SECONDS))
	end)

	it("processes a cycle after the duration boundary", function()
		assert.is_true(isCycleDue(CYCLE_DURATION_SECONDS + 5, CYCLE_DURATION_SECONDS))
	end)
end)

describe("BillingService grace-period boundary math (inline)", function()
	it("does not expire before the grace period threshold", function()
		assert.is_false(isGracePeriodExpired(GRACE_PERIOD_SECONDS - 1, GRACE_PERIOD_SECONDS))
	end)

	it("expires at the grace period threshold", function()
		assert.is_true(isGracePeriodExpired(GRACE_PERIOD_SECONDS, GRACE_PERIOD_SECONDS))
	end)

	it("expires after the grace period threshold", function()
		assert.is_true(isGracePeriodExpired(GRACE_PERIOD_SECONDS + 10, GRACE_PERIOD_SECONDS))
	end)
end)

-- ====================================================================
-- Structural drift guards
-- ====================================================================

describe("BillingService source wiring (structural)", function()
	local serviceSrc
	local stateSrc
	local constantsSrc

	before_each(function()
		serviceSrc = readFile("src/Server/Services/BillingService.luau")
		stateSrc = readFile("src/Server/Classes/BillingState.luau")
		constantsSrc = readFile("src/Shared/Definitions/BillingConstants.luau")
	end)

	it("defines CycleDurationSeconds and GracePeriodSeconds constants", function()
		assert.is_truthy(string.find(constantsSrc, "CycleDurationSeconds%s*=%s*1440", 1, false))
		assert.is_truthy(string.find(constantsSrc, "GracePeriodSeconds%s*=%s*240", 1, false))
	end)

	it("guards billing cycle using elapsed time against CycleDurationSeconds", function()
		assert.is_truthy(string.find(serviceSrc, "GetElapsedSeconds", 1, false))
		assert.is_truthy(string.find(serviceSrc, "CycleDurationSeconds", 1, false))
		assert.is_truthy(
			string.find(serviceSrc, "elapsed%s*<%s*BillingConstants%.CycleDurationSeconds", 1, false)
		)
	end)

	it("marks bills unpaid and flags bill due when the cycle completes", function()
		assert.is_truthy(string.find(serviceSrc, "MarkUnpaid", 1, false))
		assert.is_truthy(string.find(serviceSrc, "BillDueAttribute", 1, false))
	end)

	it("wires power outage attribute for enforcement", function()
		assert.is_truthy(
			string.find(serviceSrc, "GetAttribute%(%s*BillingConstants%.PowerOutageAttribute", 1, false)
		)
		assert.is_truthy(
			string.find(serviceSrc, "SetAttribute%(%s*BillingConstants%.PowerOutageAttribute", 1, false)
		)
	end)

	it("BillingState grace period uses >= comparison", function()
		assert.is_truthy(string.find(stateSrc, "GetUnpaidDuration", 1, false))
		assert.is_truthy(string.find(stateSrc, ">=%s*gracePeriodSeconds", 1, false))
	end)

	it("payment settlement resets cycle and clears bill/outage flags", function()
		assert.is_truthy(string.find(serviceSrc, "billingState:ResetCycle", 1, false))
		assert.is_truthy(
			string.find(serviceSrc, "SetAttribute%(%s*BillingConstants%.BillDueAttribute%s*,%s*false", 1, false)
		)
		assert.is_truthy(
			string.find(serviceSrc, "SetAttribute%(%s*BillingConstants%.PowerOutageAttribute%s*,%s*false", 1, false)
		)
	end)
end)
