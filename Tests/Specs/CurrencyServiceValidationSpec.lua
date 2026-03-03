-- Tests/Specs/CurrencyServiceValidationSpec.lua
-- Tests for the parameter-validation guards in CurrencyService.
--
-- CurrencyService depends on ReplicatedStorage and Roblox's Player type, so
-- it cannot be loaded under busted directly.  Instead we:
--   1. Inline EnsurePositiveInteger and the non-Player AssertParameters guards
--      (pure Lua, no Roblox deps) and test them exhaustively.
--   2. Add source-level drift guards to ensure the source still contains the
--      matching validation patterns.

local function readFile(path)
	local file = assert(io.open(path, "r"), "missing file: " .. path)
	local contents = file:read("*a")
	file:close()
	return contents
end

-- ======================================================================
-- Inlined validation helpers (mirror of CurrencyService.luau internals)
-- ======================================================================

local function EnsurePositiveInteger(amount, source)
	assert(type(amount) == "number", source .. ": amount must be a number")
	assert(amount == amount, source .. ": amount must be a valid number (not NaN)")
	assert(amount > -math.huge and amount < math.huge, source .. ": amount must be finite")
	assert(amount >= 0, source .. ": amount must be >= 0")
	assert(math.floor(amount) == amount, source .. ": amount must be an integer")
end

-- Partial AssertParameters: validates currencyName and data (no Player check).
local function AssertCurrencyNameAndData(currencyName, data, source)
	assert(type(currencyName) == "string", source .. ": currencyName must be a string")
	assert(#currencyName > 0, source .. ": currencyName must be non-empty")
	assert(type(data) == "table", source .. ": data must be a table {[string]: number}")
end

-- Helper: expect a function to throw containing the given substring.
local function expectError(fn, substr)
	local ok, err = pcall(fn)
	assert.is_false(ok, "expected error containing: " .. tostring(substr))
	assert.is_truthy(
		string.find(tostring(err), substr, 1, true),
		"error '" .. tostring(err) .. "' should contain '" .. substr .. "'"
	)
end

-- ======================================================================
-- EnsurePositiveInteger tests
-- ======================================================================

describe("CurrencyService.EnsurePositiveInteger", function()
	-- ---- valid inputs ----

	it("accepts zero", function()
		assert.has_no.errors(function()
			EnsurePositiveInteger(0, "test")
		end)
	end)

	it("accepts positive integers", function()
		for _, v in ipairs({ 1, 10, 100, 9999 }) do
			assert.has_no.errors(function()
				EnsurePositiveInteger(v, "test")
			end)
		end
	end)

	-- ---- negative amounts ----

	it("rejects negative amounts", function()
		expectError(function() EnsurePositiveInteger(-1, "src") end, "amount must be >= 0")
	end)

	it("rejects large negative amounts", function()
		expectError(function() EnsurePositiveInteger(-100, "src") end, "amount must be >= 0")
	end)

	it("rejects -0.5", function()
		expectError(function() EnsurePositiveInteger(-0.5, "src") end, "amount must be >= 0")
	end)

	-- ---- NaN ----

	it("rejects NaN", function()
		local nan = 0/0
		expectError(function() EnsurePositiveInteger(nan, "src") end, "not NaN")
	end)

	-- ---- Infinity ----

	it("rejects positive Infinity", function()
		expectError(function() EnsurePositiveInteger(math.huge, "src") end, "must be finite")
	end)

	it("rejects negative Infinity", function()
		expectError(function() EnsurePositiveInteger(-math.huge, "src") end, "must be finite")
	end)

	-- ---- non-integers ----

	it("rejects 0.5 (non-integer)", function()
		expectError(function() EnsurePositiveInteger(0.5, "src") end, "must be an integer")
	end)

	it("rejects 1.1 (non-integer)", function()
		expectError(function() EnsurePositiveInteger(1.1, "src") end, "must be an integer")
	end)

	it("rejects 99.9 (non-integer)", function()
		expectError(function() EnsurePositiveInteger(99.9, "src") end, "must be an integer")
	end)

	-- ---- error message format ----

	it("includes source prefix in error messages", function()
		local ok, err = pcall(function() EnsurePositiveInteger(-1, "CurrencyService.Add") end)
		assert.is_false(ok)
		assert.is_truthy(string.find(tostring(err), "CurrencyService.Add", 1, true))
	end)

	it("error for negative includes '>= 0' substring", function()
		expectError(function() EnsurePositiveInteger(-5, "x") end, ">= 0")
	end)

	it("error for NaN includes 'NaN' substring", function()
		expectError(function() EnsurePositiveInteger(0/0, "x") end, "NaN")
	end)

	it("error for Inf includes 'finite' substring", function()
		expectError(function() EnsurePositiveInteger(1/0, "x") end, "finite")
	end)

	it("error for non-integer includes 'integer' substring", function()
		expectError(function() EnsurePositiveInteger(3.14, "x") end, "integer")
	end)
end)

-- ======================================================================
-- AssertParameters (currencyName + data guards)
-- ======================================================================

describe("CurrencyService.AssertParameters (currencyName + data)", function()
	it("accepts valid string currencyName and table data", function()
		assert.has_no.errors(function()
			AssertCurrencyNameAndData("Coins", {}, "test")
		end)
	end)

	it("rejects nil currencyName (not a string)", function()
		expectError(function()
			AssertCurrencyNameAndData(nil, {}, "src")
		end, "currencyName must be a string")
	end)

	it("rejects numeric currencyName", function()
		expectError(function()
			AssertCurrencyNameAndData(42, {}, "src")
		end, "currencyName must be a string")
	end)

	it("rejects empty-string currencyName", function()
		expectError(function()
			AssertCurrencyNameAndData("", {}, "src")
		end, "currencyName must be non-empty")
	end)

	it("rejects nil data", function()
		expectError(function()
			AssertCurrencyNameAndData("Coins", nil, "src")
		end, "data must be a table")
	end)

	it("rejects string data", function()
		expectError(function()
			AssertCurrencyNameAndData("Coins", "oops", "src")
		end, "data must be a table")
	end)

	it("includes source prefix in error messages", function()
		local ok, err = pcall(function()
			AssertCurrencyNameAndData("", {}, "CurrencyService.Add")
		end)
		assert.is_false(ok)
		assert.is_truthy(string.find(tostring(err), "CurrencyService.Add", 1, true))
	end)
end)

-- ======================================================================
-- Source-level drift guards
-- ======================================================================

describe("CurrencyService source drift guard", function()
	local src

	before_each(function()
		src = readFile("src/Server/Services/CurrencyService.luau")
	end)

	it("defines EnsurePositiveInteger", function()
		assert.is_truthy(string.find(src, "EnsurePositiveInteger", 1, true))
	end)

	it("defines AssertParameters", function()
		assert.is_truthy(string.find(src, "AssertParameters", 1, true))
	end)

	it("guards amount >= 0", function()
		assert.is_truthy(string.find(src, "amount >= 0", 1, true))
	end)

	it("guards NaN with 'amount == amount'", function()
		assert.is_truthy(string.find(src, "amount == amount", 1, true))
	end)

	it("guards Infinity with math.huge", function()
		assert.is_truthy(string.find(src, "math.huge", 1, true))
	end)

	it("guards non-integer with math.floor", function()
		assert.is_truthy(string.find(src, "math.floor", 1, true))
	end)

	it("checks currencyName is a string", function()
		assert.is_truthy(string.find(src, "currencyName", 1, true))
	end)

	it("checks #currencyName > 0 for non-empty", function()
		assert.is_truthy(string.find(src, "#currencyName > 0", 1, true))
	end)

	it("checks data is a table", function()
		assert.is_truthy(string.find(src, 'typeof%(data%) == "table"', 1, false))
	end)

	it("checks player IsA Player", function()
		assert.is_truthy(string.find(src, 'IsA("Player")', 1, true))
	end)
end)
