--!strict
-- Behavioral tests for TenantService validation utilities

local ValidationUtils = assert(loadfile("src/Server/Services/TenantService/ValidationUtils.luau"))()

describe("TenantService ValidationUtils", function()
	describe("EnsureNumber", function()
		it("returns input when value is numeric", function()
			assert.equals(42, ValidationUtils.EnsureNumber(42, 10))
		end)

		it("falls back for non-numeric values", function()
			assert.equals(10, ValidationUtils.EnsureNumber("42", 10))
			assert.equals(10, ValidationUtils.EnsureNumber(nil, 10))
		end)
	end)

	describe("EnsureString", function()
		it("keeps non-empty strings", function()
			assert.equals("RoomA", ValidationUtils.EnsureString("RoomA", "fallback"))
		end)

		it("uses fallback for empty/non-string values", function()
			assert.equals("fallback", ValidationUtils.EnsureString("", "fallback"))
			assert.equals("fallback", ValidationUtils.EnsureString(7, "fallback"))
			assert.is_nil(ValidationUtils.EnsureString(nil, nil))
		end)
	end)

	describe("EnsureTable", function()
		it("returns original table by reference", function()
			local input = { RoomA = 1 }
			local output = ValidationUtils.EnsureTable(input, { fallback = true })
			assert.equals(input, output)
			output.RoomA = 2
			assert.equals(2, input.RoomA)
		end)

		it("returns fallback or empty table for invalid input", function()
			local fallback = { RoomB = 3 }
			assert.equals(fallback, ValidationUtils.EnsureTable("bad", fallback))
			local output = ValidationUtils.EnsureTable(nil, nil)
			assert.is_true(type(output) == "table")
			assert.is_nil(next(output))
		end)
	end)

	describe("IsValidNumber", function()
		it("accepts numbers that meet minValue", function()
			assert.is_true(ValidationUtils.IsValidNumber(5, 1))
			assert.is_true(ValidationUtils.IsValidNumber(0, nil))
		end)

		it("rejects non-numbers and values below minValue", function()
			assert.is_false(ValidationUtils.IsValidNumber("5", 1))
			assert.is_false(ValidationUtils.IsValidNumber(-1, 0))
		end)
	end)
end)
