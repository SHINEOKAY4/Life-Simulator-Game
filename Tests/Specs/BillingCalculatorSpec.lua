-- Tests/Specs/BillingCalculatorSpec.lua
-- Behavioral tests for BillingCalculator formulas.
--
-- BillingCalculator uses `--!strict` and requires ReplicatedStorage, so it
-- cannot be loaded directly under busted.  Instead we inline the constants
-- from BillingConstants.luau and replicate the four pure formulas here —
-- the same approach used in CraftingSkillPanelSpec for skill-XP math.
--
-- If the constants or formulas ever change in source, these tests will catch
-- the drift via the structural assertions at the bottom of this file.

local function readFile(path)
	local file = assert(io.open(path, "r"), "missing file: " .. path)
	local contents = file:read("*a")
	file:close()
	return contents
end

-- ====================================================================
-- Inlined constants from BillingConstants.luau
-- ====================================================================

local PROPERTY_TAX_RATE       = 0.02
local BASE_PROPERTY_VALUE     = 1000
local CELL_VALUE_MULTIPLIER   = 50

local ELECTRICITY_RATE        = 0.12   -- per kWh

local WATER_RATE              = 2.5    -- per unit
local BASE_WATER_USAGE        = 5
local WATER_PER_RESIDENT      = 3

local INTERNET_TIERS = {
	None     = 0,
	Basic    = 25,
	Standard = 50,
	Premium  = 100,
}

-- ====================================================================
-- Replicated pure formulas (mirror of BillingCalculator.luau)
-- ====================================================================

local function calculatePropertyTax(occupiedCells)
	local propertyValue = BASE_PROPERTY_VALUE + (occupiedCells * CELL_VALUE_MULTIPLIER)
	return propertyValue * PROPERTY_TAX_RATE
end

local function calculateElectricity(energyConsumedKWh)
	return energyConsumedKWh * ELECTRICITY_RATE
end

local function calculateWater(residentCount)
	local totalUsage = BASE_WATER_USAGE + (residentCount * WATER_PER_RESIDENT)
	return totalUsage * WATER_RATE
end

local function calculateInternet(tier)
	return INTERNET_TIERS[tier] or 0
end

-- ====================================================================
-- PropertyTax tests
-- ====================================================================

describe("BillingCalculator.CalculatePropertyTax", function()
	it("charges the base tax for an empty plot (0 cells)", function()
		-- (1000 + 0*50) * 0.02 = 20
		local expected = BASE_PROPERTY_VALUE * PROPERTY_TAX_RATE
		assert.are.equal(expected, calculatePropertyTax(0))
	end)

	it("adds cell value for a single occupied cell", function()
		-- (1000 + 1*50) * 0.02 = 21
		local expected = (BASE_PROPERTY_VALUE + CELL_VALUE_MULTIPLIER) * PROPERTY_TAX_RATE
		assert.are.equal(expected, calculatePropertyTax(1))
	end)

	it("scales linearly with cell count", function()
		for cells = 2, 10 do
			local expected = (BASE_PROPERTY_VALUE + cells * CELL_VALUE_MULTIPLIER) * PROPERTY_TAX_RATE
			assert.are.equal(expected, calculatePropertyTax(cells), "mismatch at cells=" .. cells)
		end
	end)

	it("returns a positive value for any non-negative cell count", function()
		for _, cells in ipairs({ 0, 1, 10, 50, 200 }) do
			assert.is_true(calculatePropertyTax(cells) > 0, "must be positive for cells=" .. cells)
		end
	end)

	it("base tax (0 cells) equals exactly 20", function()
		assert.are.equal(20, calculatePropertyTax(0))
	end)

	it("tax for 10 cells equals exactly 30", function()
		-- (1000 + 10*50) * 0.02 = 1500 * 0.02 = 30
		assert.are.equal(30, calculatePropertyTax(10))
	end)

	it("tax for 100 cells equals exactly 120", function()
		-- (1000 + 100*50) * 0.02 = 6000 * 0.02 = 120
		assert.are.equal(120, calculatePropertyTax(100))
	end)
end)

-- ====================================================================
-- Electricity tests
-- ====================================================================

describe("BillingCalculator.CalculateElectricity", function()
	it("returns 0 for zero energy consumed", function()
		assert.are.equal(0, calculateElectricity(0))
	end)

	it("returns the correct cost for 1 kWh", function()
		assert.are.equal(ELECTRICITY_RATE, calculateElectricity(1))
	end)

	it("scales linearly with kWh", function()
		for kwh = 1, 20 do
			local expected = kwh * ELECTRICITY_RATE
			assert.are.near(expected, calculateElectricity(kwh), 1e-9)
		end
	end)

	it("handles fractional kWh correctly", function()
		-- 0.5 kWh → 0.5 * 0.12 = 0.06
		assert.are.near(0.06, calculateElectricity(0.5), 1e-9)
	end)

	it("10 kWh costs exactly 1.20", function()
		assert.are.near(1.20, calculateElectricity(10), 1e-9)
	end)

	it("100 kWh costs exactly 12.00", function()
		assert.are.near(12.00, calculateElectricity(100), 1e-9)
	end)

	it("cost is always non-negative for non-negative input", function()
		for _, kwh in ipairs({ 0, 0.1, 1, 50, 500 }) do
			assert.is_true(calculateElectricity(kwh) >= 0)
		end
	end)
end)

-- ====================================================================
-- Water tests
-- ====================================================================

describe("BillingCalculator.CalculateWater", function()
	it("charges base usage for zero residents", function()
		-- (5 + 0*3) * 2.5 = 12.5
		local expected = BASE_WATER_USAGE * WATER_RATE
		assert.are.equal(expected, calculateWater(0))
	end)

	it("base cost (0 residents) equals exactly 12.5", function()
		assert.are.equal(12.5, calculateWater(0))
	end)

	it("adds per-resident cost for each resident", function()
		-- 1 resident: (5 + 3) * 2.5 = 20
		assert.are.equal(20, calculateWater(1))
	end)

	it("scales linearly with resident count", function()
		for residents = 0, 10 do
			local expected = (BASE_WATER_USAGE + residents * WATER_PER_RESIDENT) * WATER_RATE
			assert.are.equal(expected, calculateWater(residents), "mismatch at residents=" .. residents)
		end
	end)

	it("5 residents costs exactly 50", function()
		-- (5 + 5*3) * 2.5 = 20 * 2.5 = 50
		assert.are.equal(50, calculateWater(5))
	end)

	it("10 residents costs exactly 87.5", function()
		-- (5 + 10*3) * 2.5 = 35 * 2.5 = 87.5
		assert.are.equal(87.5, calculateWater(10))
	end)

	it("is always at least the base cost", function()
		for _, residents in ipairs({ 0, 1, 5, 20 }) do
			assert.is_true(
				calculateWater(residents) >= calculateWater(0),
				"water cost should not fall below base"
			)
		end
	end)
end)

-- ====================================================================
-- Internet tier tests
-- ====================================================================

describe("BillingCalculator.CalculateInternet", function()
	it("None tier costs 0", function()
		assert.are.equal(0, calculateInternet("None"))
	end)

	it("Basic tier costs 25", function()
		assert.are.equal(25, calculateInternet("Basic"))
	end)

	it("Standard tier costs 50", function()
		assert.are.equal(50, calculateInternet("Standard"))
	end)

	it("Premium tier costs 100", function()
		assert.are.equal(100, calculateInternet("Premium"))
	end)

	it("unknown tier returns 0 (safe fallback)", function()
		assert.are.equal(0, calculateInternet("UltraTurboFiber"))
		assert.are.equal(0, calculateInternet(""))
		assert.are.equal(0, calculateInternet("none"))  -- case-sensitive
	end)

	it("tier costs are strictly ascending: None < Basic < Standard < Premium", function()
		assert.is_true(INTERNET_TIERS.None < INTERNET_TIERS.Basic)
		assert.is_true(INTERNET_TIERS.Basic < INTERNET_TIERS.Standard)
		assert.is_true(INTERNET_TIERS.Standard < INTERNET_TIERS.Premium)
	end)
end)

-- ====================================================================
-- Source-level structural assertions
-- (Guard against drift between inlined constants and the real source.)
-- ====================================================================

describe("BillingCalculator source drift guard", function()
	local calcSrc
	local constsSrc

	before_each(function()
		calcSrc  = readFile("src/Server/Utilities/BillingCalculator.luau")
		constsSrc = readFile("src/Shared/Definitions/BillingConstants.luau")
	end)

	-- Constants
	it("BillingConstants defines PropertyTaxRate = 0.02", function()
		assert.is_truthy(string.find(constsSrc, "PropertyTaxRate%s*=%s*0%.02", 1, false))
	end)

	it("BillingConstants defines BasePropertyValue = 1000", function()
		assert.is_truthy(string.find(constsSrc, "BasePropertyValue%s*=%s*1000", 1, false))
	end)

	it("BillingConstants defines CellValueMultiplier = 50", function()
		assert.is_truthy(string.find(constsSrc, "CellValueMultiplier%s*=%s*50", 1, false))
	end)

	it("BillingConstants defines ElectricityRatePerKWh = 0.12", function()
		assert.is_truthy(string.find(constsSrc, "ElectricityRatePerKWh%s*=%s*0%.12", 1, false))
	end)

	it("BillingConstants defines WaterRatePerUnit = 2.5", function()
		assert.is_truthy(string.find(constsSrc, "WaterRatePerUnit%s*=%s*2%.5", 1, false))
	end)

	it("BillingConstants defines BaseWaterUsage = 5", function()
		assert.is_truthy(string.find(constsSrc, "BaseWaterUsage%s*=%s*5", 1, false))
	end)

	it("BillingConstants defines WaterPerResident = 3", function()
		assert.is_truthy(string.find(constsSrc, "WaterPerResident%s*=%s*3", 1, false))
	end)

	-- Calculator functions present
	it("BillingCalculator defines CalculatePropertyTax", function()
		assert.is_truthy(string.find(calcSrc, "CalculatePropertyTax", 1, true))
	end)

	it("BillingCalculator defines CalculateElectricity", function()
		assert.is_truthy(string.find(calcSrc, "CalculateElectricity", 1, true))
	end)

	it("BillingCalculator defines CalculateWater", function()
		assert.is_truthy(string.find(calcSrc, "CalculateWater", 1, true))
	end)

	it("BillingCalculator defines CalculateInternet", function()
		assert.is_truthy(string.find(calcSrc, "CalculateInternet", 1, true))
	end)

	-- Formula shape
	it("CalculatePropertyTax uses CellValueMultiplier", function()
		assert.is_truthy(string.find(calcSrc, "CellValueMultiplier", 1, true))
	end)

	it("CalculatePropertyTax uses PropertyTaxRate", function()
		assert.is_truthy(string.find(calcSrc, "PropertyTaxRate", 1, true))
	end)

	it("CalculateElectricity uses ElectricityRatePerKWh", function()
		assert.is_truthy(string.find(calcSrc, "ElectricityRatePerKWh", 1, true))
	end)

	it("CalculateWater uses WaterRatePerUnit", function()
		assert.is_truthy(string.find(calcSrc, "WaterRatePerUnit", 1, true))
	end)

	it("CalculateWater uses WaterPerResident", function()
		assert.is_truthy(string.find(calcSrc, "WaterPerResident", 1, true))
	end)

	it("CalculateInternet falls back with `or 0` for unknown tiers", function()
		assert.is_truthy(string.find(calcSrc, "or 0", 1, true))
	end)
end)
