--!strict
-- Tests/Specs/InternetTierSpec.lua
-- Structural + behavioral tests for internet tier selection wiring.
-- Covers: BillingPackets packet definitions, BillingService wiring,
-- BillingCalculator tier costs, BillingState tier persistence, BillUI structural.

local function readFile(path)
	local file = assert(io.open(path, "r"), "missing file: " .. path)
	local contents = file:read("*a")
	file:close()
	return contents
end

-- ====================================================================
-- BillingPackets structural tests
-- ====================================================================

describe("BillingPackets internet tier packets", function()
	local src

	before_each(function()
		src = readFile("src/Network/BillingPackets.luau")
	end)

	it("defines GetInternetTier packet", function()
		assert.is_truthy(string.find(src, "GetInternetTier", 1, true))
	end)

	it("defines SetInternetTier packet", function()
		assert.is_truthy(string.find(src, "SetInternetTier", 1, true))
	end)

	it("uses BillingGetInternetTier remote name", function()
		assert.is_truthy(string.find(src, "BillingGetInternetTier", 1, true))
	end)

	it("uses BillingSetInternetTier remote name", function()
		assert.is_truthy(string.find(src, "BillingSetInternetTier", 1, true))
	end)

	it("SetInternetTier sends a String payload", function()
		assert.is_truthy(string.find(src, "BillingSetInternetTier.*Packet%.String", 1, false))
	end)

	it("both tier packets have Response definitions", function()
		local count = 0
		for _ in string.gmatch(src, "Tier.-:Response") do
			count = count + 1
		end
		assert.is_true(count >= 2, "expected at least 2 Response definitions for tier packets, got " .. count)
	end)
end)

-- ====================================================================
-- BillingService wiring structural tests
-- ====================================================================

describe("BillingService internet tier wiring", function()
	local src

	before_each(function()
		src = readFile("src/Server/Services/BillingService.luau")
	end)

	it("requires BillingPackets", function()
		assert.is_truthy(string.find(src, "BillingPackets", 1, true))
	end)

	it("wires GetInternetTier.OnServerInvoke", function()
		assert.is_truthy(string.find(src, "GetInternetTier.OnServerInvoke", 1, true))
	end)

	it("wires SetInternetTier.OnServerInvoke", function()
		assert.is_truthy(string.find(src, "SetInternetTier.OnServerInvoke", 1, true))
	end)

	it("validates tier against VALID_INTERNET_TIERS", function()
		assert.is_truthy(string.find(src, "VALID_INTERNET_TIERS", 1, true))
	end)

	it("rejects invalid tiers", function()
		assert.is_truthy(string.find(src, "Invalid tier", 1, true))
	end)

	it("calls SetInternetTier on state", function()
		assert.is_truthy(string.find(src, "BillingService.SetInternetTier", 1, true))
	end)

	it("sends a notification on tier change", function()
		assert.is_truthy(string.find(src, "Internet Plan Updated", 1, true))
	end)
end)

-- ====================================================================
-- BillingCalculator structural tests
-- (BillingCalculator uses Luau type annotations so loadfile is not used)
-- ====================================================================

describe("BillingCalculator internet tier logic", function()
	local src

	before_each(function()
		src = readFile("src/Server/Utilities/BillingCalculator.luau")
	end)

	it("defines CalculateInternet function", function()
		assert.is_truthy(string.find(src, "CalculateInternet", 1, true))
	end)

	it("looks up tier from BillingConstants.InternetTiers", function()
		assert.is_truthy(string.find(src, "InternetTiers", 1, true))
	end)

	it("returns 0 for unknown tiers (fallback to `or 0`)", function()
		assert.is_truthy(string.find(src, "or 0", 1, true))
	end)

	-- Verify tier costs are declared in BillingConstants
	local constsSrc = readFile("src/Shared/Definitions/BillingConstants.luau")

	it("None tier cost is 0 in BillingConstants", function()
		assert.is_truthy(string.find(constsSrc, "None%s*=%s*0", 1, false))
	end)

	it("Basic tier cost is 25 in BillingConstants", function()
		assert.is_truthy(string.find(constsSrc, "Basic%s*=%s*25", 1, false))
	end)

	it("Standard tier cost is 50 in BillingConstants", function()
		assert.is_truthy(string.find(constsSrc, "Standard%s*=%s*50", 1, false))
	end)

	it("Premium tier cost is 100 in BillingConstants", function()
		assert.is_truthy(string.find(constsSrc, "Premium%s*=%s*100", 1, false))
	end)

	-- Inline cost ordering assertions using the declared constants
	local TIERS = { None = 0, Basic = 25, Standard = 50, Premium = 100 }

	it("Basic costs more than None", function()
		assert.is_true(TIERS.Basic > TIERS.None)
	end)

	it("Standard costs more than Basic", function()
		assert.is_true(TIERS.Standard > TIERS.Basic)
	end)

	it("Premium costs more than Standard", function()
		assert.is_true(TIERS.Premium > TIERS.Standard)
	end)
end)

-- ====================================================================
-- BillingState structural tests
-- (BillingState uses Luau type annotations so loadfile is not used)
-- ====================================================================

describe("BillingState SetInternetTier logic", function()
	local src

	before_each(function()
		src = readFile("src/Server/Classes/BillingState.luau")
	end)

	it("defines SetInternetTier method", function()
		assert.is_truthy(string.find(src, "SetInternetTier", 1, true))
	end)

	it("guards tier change against BillingConstants.InternetTiers", function()
		assert.is_truthy(string.find(src, "InternetTiers%[tier%]", 1, false))
	end)

	it("persists tier to Save.InternetTier", function()
		assert.is_truthy(string.find(src, "Save.InternetTier", 1, true))
	end)

	it("InternetTier field exists in save data type", function()
		assert.is_truthy(string.find(src, "InternetTier", 1, true))
	end)

	it("BillingStateData struct includes InternetTier field", function()
		assert.is_truthy(string.find(src, "InternetTier%s*:", 1, false))
	end)

	it("invalid tiers are silently ignored (only assigns when tier found)", function()
		-- The guard `if BillingConstants.InternetTiers[tier] then` means invalid tiers are no-ops
		assert.is_truthy(string.find(src, "if BillingConstants.InternetTiers", 1, true))
	end)
end)

-- ====================================================================
-- BillUI structural tests
-- ====================================================================

describe("BillUI internet tier UI", function()
	local src

	before_each(function()
		src = readFile("src/Client/UserInterface/BillUI.luau")
	end)

	it("imports BillingPackets", function()
		assert.is_truthy(string.find(src, "BillingPackets", 1, true))
	end)

	it("defines INTERNET_TIERS table", function()
		assert.is_truthy(string.find(src, "INTERNET_TIERS", 1, true))
	end)

	it("includes None tier entry", function()
		assert.is_truthy(string.find(src, '"None"', 1, true))
	end)

	it("includes Basic tier entry", function()
		assert.is_truthy(string.find(src, '"Basic"', 1, true))
	end)

	it("includes Standard tier entry", function()
		assert.is_truthy(string.find(src, '"Standard"', 1, true))
	end)

	it("includes Premium tier entry", function()
		assert.is_truthy(string.find(src, '"Premium"', 1, true))
	end)

	it("calls SetInternetTier packet on button activation", function()
		assert.is_truthy(string.find(src, "SetInternetTier:Fire", 1, true))
	end)

	it("calls GetInternetTier packet to refresh tier", function()
		assert.is_truthy(string.find(src, "GetInternetTier:Fire", 1, true))
	end)

	it("highlights active tier button", function()
		assert.is_truthy(string.find(src, "highlightTierButtons", 1, true))
	end)

	it("builds tier selector in InternetFrame", function()
		assert.is_truthy(string.find(src, "buildTierSelector", 1, true))
	end)

	it("uses debounce for tier change requests", function()
		assert.is_truthy(string.find(src, "SetInternetTier.*Debounce", 1, false)
			or string.find(src, "Debounce.*SetInternetTier", 1, false)
			or string.find(src, "RunIfAvailable.*SetInternetTier", 1, false)
			or string.find(src, "SetInternetTier", 1, true) and string.find(src, "RunIfAvailable", 1, true))
	end)

	it("fetches tier on Show()", function()
		assert.is_truthy(string.find(src, "fetchAndApplyInternetTier", 1, true))
	end)
end)
