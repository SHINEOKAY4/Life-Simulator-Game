-- Structural checks for ClientResidentMovement seat acquisition loop backoff (Iter 5)
local function readFile(path)
	local file = assert(io.open(path, "r"), "missing file: " .. path)
	local contents = file:read("*a")
	file:close()
	return contents
end

describe("ClientResidentMovement seat acquisition backoff", function()
	local src

	before_each(function()
		src = readFile("src/Client/Modules/ClientResidentMovement.luau")
	end)

	it("defines SEAT_CHECK_INTERVAL constant", function()
		assert.is_truthy(
			string.find(src, "SEAT_CHECK_INTERVAL", 1, true),
			"SEAT_CHECK_INTERVAL constant must be defined"
		)
	end)

	it("SEAT_CHECK_INTERVAL is a positive number <= 0.1 (bounded, not per-frame)", function()
		local value = string.match(src, "SEAT_CHECK_INTERVAL%s*=%s*([%d%.]+)")
		assert.is_truthy(value, "SEAT_CHECK_INTERVAL must have a numeric value")
		local n = tonumber(value)
		assert.is_truthy(n, "SEAT_CHECK_INTERVAL value must parse as number")
		assert.is_true(n > 0, "SEAT_CHECK_INTERVAL must be positive")
		assert.is_true(n <= 0.1, "SEAT_CHECK_INTERVAL must be <= 0.1 (not per-frame)")
	end)

	it("waitForSeatAvailability uses task.wait(SEAT_CHECK_INTERVAL) not Heartbeat", function()
		local fnStart = string.find(src, "function waitForSeatAvailability", 1, true)
		assert.is_truthy(fnStart, "waitForSeatAvailability must exist")
		local fnBody = string.sub(src, fnStart, fnStart + 600)
		assert.is_truthy(
			string.find(fnBody, "task.wait(SEAT_CHECK_INTERVAL)", 1, true),
			"waitForSeatAvailability must use task.wait(SEAT_CHECK_INTERVAL)"
		)
		assert.is_falsy(
			string.find(fnBody, "Heartbeat:Wait()", 1, true),
			"waitForSeatAvailability must not poll every heartbeat"
		)
	end)

	it("attemptSeat uses task.wait(SEAT_CHECK_INTERVAL) not Heartbeat", function()
		local fnStart = string.find(src, "function attemptSeat", 1, true)
		assert.is_truthy(fnStart, "attemptSeat must exist")
		local fnBody = string.sub(src, fnStart, fnStart + 500)
		assert.is_truthy(
			string.find(fnBody, "task.wait(SEAT_CHECK_INTERVAL)", 1, true),
			"attemptSeat must use task.wait(SEAT_CHECK_INTERVAL)"
		)
		assert.is_falsy(
			string.find(fnBody, "Heartbeat:Wait()", 1, true),
			"attemptSeat must not poll every heartbeat"
		)
	end)

	it("SeatResident retry attempt count is bounded (max 2 attempts)", function()
		local fnStart = string.find(src, "function ClientResidentMovement.SeatResident", 1, true)
		assert.is_truthy(fnStart, "SeatResident must exist")
		local fnBody = string.sub(src, fnStart, fnStart + 2000)
		-- Count calls to attemptSeat: bounded at 2 retries
		local count = 0
		local pos = 1
		while true do
			local found = string.find(fnBody, "attemptSeat(", pos, true)
			if not found then
				break
			end
			count = count + 1
			pos = found + 1
		end
		assert.is_true(count >= 2, "SeatResident should call attemptSeat at least twice (initial + 1 retry)")
		assert.is_true(count <= 3, "SeatResident should not call attemptSeat more than 3 times (bounded)")
	end)
end)
