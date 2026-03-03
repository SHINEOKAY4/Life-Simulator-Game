-- Tests/Specs/ResidentServiceSpec.lua
-- Structural + behavioral tests for ResidentService.
--
-- ResidentService depends on Roblox services (game:GetService, GoodSignal, etc.)
-- and cannot be loaded directly under busted. We:
--   1. Inline the pure-Lua helper logic and test it exhaustively.
--   2. Add source-level drift guards to verify record shape, map wiring,
--      eviction dispatch, and occupancy semantics.

local function readFile(path)
	local file = assert(io.open(path, "r"), "missing file: " .. path)
	local contents = file:read("*a")
	file:close()
	return contents
end

-- ====================================================================
-- Inline helpers replicated from ResidentService.luau
-- ====================================================================

-- Mirror of resolveTenantTransmissionId
local function resolveTenantTransmissionId(rawValue)
	if type(rawValue) == "string" then
		return rawValue
	end
	return ""
end

-- Mirror of cloneTable
local function cloneTable(value)
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for k, v in pairs(value) do
		copy[k] = cloneTable(v)
	end
	return copy
end

-- Mirror of stripAppearance
local function stripAppearance(residentSave)
	if type(residentSave) ~= "table" then
		return
	end
	residentSave.Appearance = nil
	residentSave.Age = nil
	residentSave.Gender = nil
	residentSave.Statistics = nil
end

-- Mirror of stripCareerData
local function stripCareerData(residentSave)
	if type(residentSave) ~= "table" then
		return
	end
	residentSave.Occupation = nil
	residentSave.CurrentCareerId = nil
	residentSave.CareerStreak = nil
	residentSave.AssignedShiftId = nil
end

-- Mirror of ensureHouseholdState
local function ensureHouseholdState(data)
	if data == nil then
		return nil
	end
	data.Tenants = data.Tenants or {}
	data.TenantsCount = data.TenantsCount or #data.Tenants
	return data
end

-- ====================================================================
-- Inline bidirectional tenant-resident map logic
-- (mirrors setTenantLinkInternal + clearTenantLinkByTenant/Resident)
-- ====================================================================

local function makeMaps()
	return {
		tenantToResident = {},
		residentToTenant = {},
	}
end

local function setTenantLink(maps, residentName, tenantId)
	local tenantMap = maps.tenantToResident
	local residentMap = maps.residentToTenant

	-- Clear previous tenant for this resident
	local previousTenant = residentMap[residentName]
	if previousTenant then
		tenantMap[previousTenant] = nil
	end
	residentMap[residentName] = nil

	if tenantId and tenantId ~= "" then
		-- Clear previous resident for this tenant
		local previousResident = tenantMap[tenantId]
		if previousResident then
			residentMap[previousResident] = nil
		end
		tenantMap[tenantId] = residentName
		residentMap[residentName] = tenantId
	end
end

local function clearLinkByTenant(maps, tenantId)
	local residentName = maps.tenantToResident[tenantId]
	maps.tenantToResident[tenantId] = nil
	if residentName then
		maps.residentToTenant[residentName] = nil
	end
end

local function clearLinkByResident(maps, residentName)
	local tenantId = maps.residentToTenant[residentName]
	maps.residentToTenant[residentName] = nil
	if tenantId then
		maps.tenantToResident[tenantId] = nil
	end
end

-- ====================================================================
-- Occupancy count math tests
-- ====================================================================

describe("ResidentService occupancy count math (inline)", function()
	it("empty tenants list yields count 0", function()
		local data = ensureHouseholdState({ Tenants = {} })
		assert.are.equal(0, #data.Tenants)
	end)

	it("TenantsCount matches list length on normalisation", function()
		local data = ensureHouseholdState({ Tenants = { { Name = "Alice" }, { Name = "Bob" } } })
		data.TenantsCount = #data.Tenants
		assert.are.equal(2, data.TenantsCount)
	end)

	it("adding a resident increments occupancy count", function()
		local tenants = {}
		tenants[#tenants + 1] = { Name = "Alice" }
		assert.are.equal(1, #tenants)
		tenants[#tenants + 1] = { Name = "Bob" }
		assert.are.equal(2, #tenants)
	end)

	it("removing a resident decrements occupancy count", function()
		local tenants = { { Name = "Alice" }, { Name = "Bob" } }
		table.remove(tenants, 1)
		assert.are.equal(1, #tenants)
	end)

	it("ensureHouseholdState initialises nil Tenants to empty table", function()
		local data = ensureHouseholdState({})
		assert.are.same({}, data.Tenants)
	end)

	it("ensureHouseholdState propagates non-nil TenantsCount", function()
		local data = ensureHouseholdState({ Tenants = { { Name = "X" } }, TenantsCount = 7 })
		-- Already set, should not overwrite
		assert.are.equal(7, data.TenantsCount)
	end)

	it("ensureHouseholdState returns nil when data is nil", function()
		assert.is_nil(ensureHouseholdState(nil))
	end)
end)

-- ====================================================================
-- Bidirectional tenant-resident map tests
-- ====================================================================

describe("ResidentService bidirectional tenant-resident map (inline)", function()
	it("setTenantLink records both directions", function()
		local maps = makeMaps()
		setTenantLink(maps, "Alice", "tenant-001")
		assert.are.equal("tenant-001", maps.residentToTenant["Alice"])
		assert.are.equal("Alice", maps.tenantToResident["tenant-001"])
	end)

	it("setTenantLink with nil clears both directions", function()
		local maps = makeMaps()
		setTenantLink(maps, "Alice", "tenant-001")
		setTenantLink(maps, "Alice", nil)
		assert.is_nil(maps.residentToTenant["Alice"])
		assert.is_nil(maps.tenantToResident["tenant-001"])
	end)

	it("setTenantLink with empty string clears both directions", function()
		local maps = makeMaps()
		setTenantLink(maps, "Alice", "tenant-001")
		setTenantLink(maps, "Alice", "")
		assert.is_nil(maps.residentToTenant["Alice"])
		assert.is_nil(maps.tenantToResident["tenant-001"])
	end)

	it("reassigning a resident removes old tenant mapping", function()
		local maps = makeMaps()
		setTenantLink(maps, "Alice", "tenant-001")
		setTenantLink(maps, "Alice", "tenant-002")
		-- Old tenant no longer maps to Alice
		assert.is_nil(maps.tenantToResident["tenant-001"])
		-- New tenant maps to Alice
		assert.are.equal("Alice", maps.tenantToResident["tenant-002"])
		assert.are.equal("tenant-002", maps.residentToTenant["Alice"])
	end)

	it("reassigning a tenant removes old resident mapping", function()
		local maps = makeMaps()
		setTenantLink(maps, "Alice", "tenant-001")
		setTenantLink(maps, "Bob", "tenant-001")
		-- Alice no longer holds tenant-001
		assert.is_nil(maps.residentToTenant["Alice"])
		-- Bob now holds tenant-001
		assert.are.equal("Bob", maps.tenantToResident["tenant-001"])
		assert.are.equal("tenant-001", maps.residentToTenant["Bob"])
	end)

	it("clearLinkByTenant removes both directions", function()
		local maps = makeMaps()
		setTenantLink(maps, "Alice", "tenant-001")
		clearLinkByTenant(maps, "tenant-001")
		assert.is_nil(maps.tenantToResident["tenant-001"])
		assert.is_nil(maps.residentToTenant["Alice"])
	end)

	it("clearLinkByResident removes both directions", function()
		local maps = makeMaps()
		setTenantLink(maps, "Alice", "tenant-001")
		clearLinkByResident(maps, "Alice")
		assert.is_nil(maps.residentToTenant["Alice"])
		assert.is_nil(maps.tenantToResident["tenant-001"])
	end)

	it("clearLinkByTenant is a no-op for unknown tenantId", function()
		local maps = makeMaps()
		-- Should not raise an error
		clearLinkByTenant(maps, "nonexistent")
		assert.is_nil(maps.tenantToResident["nonexistent"])
	end)

	it("multiple residents can hold different tenant links independently", function()
		local maps = makeMaps()
		setTenantLink(maps, "Alice", "t-001")
		setTenantLink(maps, "Bob", "t-002")
		setTenantLink(maps, "Carol", "t-003")
		assert.are.equal("t-001", maps.residentToTenant["Alice"])
		assert.are.equal("t-002", maps.residentToTenant["Bob"])
		assert.are.equal("t-003", maps.residentToTenant["Carol"])
		assert.are.equal("Alice", maps.tenantToResident["t-001"])
		assert.are.equal("Bob", maps.tenantToResident["t-002"])
		assert.are.equal("Carol", maps.tenantToResident["t-003"])
	end)
end)

-- ====================================================================
-- resolveTenantTransmissionId tests
-- ====================================================================

describe("ResidentService resolveTenantTransmissionId (inline)", function()
	it("passes through a valid string", function()
		assert.are.equal("tenant-abc", resolveTenantTransmissionId("tenant-abc"))
	end)

	it("returns empty string for nil", function()
		assert.are.equal("", resolveTenantTransmissionId(nil))
	end)

	it("returns empty string for a number", function()
		assert.are.equal("", resolveTenantTransmissionId(42))
	end)

	it("returns empty string for a boolean", function()
		assert.are.equal("", resolveTenantTransmissionId(true))
	end)

	it("returns empty string for a table", function()
		assert.are.equal("", resolveTenantTransmissionId({}))
	end)

	it("returns empty string for an empty string (no, passes through)", function()
		-- Empty string is still a string
		assert.are.equal("", resolveTenantTransmissionId(""))
	end)
end)

-- ====================================================================
-- cloneTable deep-copy tests
-- ====================================================================

describe("ResidentService cloneTable (inline)", function()
	it("returns primitives unchanged", function()
		assert.are.equal(42, cloneTable(42))
		assert.are.equal("hello", cloneTable("hello"))
		assert.are.equal(true, cloneTable(true))
		assert.is_nil(cloneTable(nil))
	end)

	it("produces a distinct table for shallow copies", function()
		local src = { x = 1 }
		local copy = cloneTable(src)
		assert.are_not.equal(src, copy)
		assert.are.equal(1, copy.x)
	end)

	it("deep-clones nested tables so inner mutations do not affect original", function()
		local src = { inner = { value = 10 } }
		local copy = cloneTable(src)
		copy.inner.value = 99
		assert.are.equal(10, src.inner.value)
	end)

	it("deep-clones arrays correctly", function()
		local src = { 10, 20, 30 }
		local copy = cloneTable(src)
		copy[1] = 999
		assert.are.equal(10, src[1])
		assert.are.equal(20, copy[2])
	end)
end)

-- ====================================================================
-- stripAppearance / stripCareerData tests
-- ====================================================================

describe("ResidentService stripAppearance (inline)", function()
	it("removes Appearance, Age, Gender, Statistics keys", function()
		local resident = {
			Name = "Alice",
			Appearance = { hair = "brown" },
			Age = 25,
			Gender = "Female",
			Statistics = { charm = 5 },
			Traits = { "Neat" },
		}
		stripAppearance(resident)
		assert.is_nil(resident.Appearance)
		assert.is_nil(resident.Age)
		assert.is_nil(resident.Gender)
		assert.is_nil(resident.Statistics)
		-- Does not remove other keys
		assert.are.equal("Alice", resident.Name)
		assert.are.same({ "Neat" }, resident.Traits)
	end)

	it("is a no-op for non-table values", function()
		-- Should not raise
		stripAppearance("notatable")
		stripAppearance(nil)
	end)
end)

describe("ResidentService stripCareerData (inline)", function()
	it("removes Occupation, CurrentCareerId, CareerStreak, AssignedShiftId", function()
		local resident = {
			Name = "Bob",
			Occupation = "Chef",
			CurrentCareerId = "career-1",
			CareerStreak = 3,
			AssignedShiftId = "shift-morning",
			Traits = { "Ambitious" },
		}
		stripCareerData(resident)
		assert.is_nil(resident.Occupation)
		assert.is_nil(resident.CurrentCareerId)
		assert.is_nil(resident.CareerStreak)
		assert.is_nil(resident.AssignedShiftId)
		assert.are.equal("Bob", resident.Name)
	end)

	it("is a no-op for non-table values", function()
		stripCareerData(nil)
		stripCareerData(false)
	end)
end)

-- ====================================================================
-- Name deduplication logic (inline mirror of load loop)
-- ====================================================================

describe("ResidentService name deduplication on load (inline)", function()
	local function filterDuplicates(incoming)
		local seenNames = {}
		local filtered = {}
		for _, entry in ipairs(incoming) do
			if type(entry) == "table" and type(entry.Name) == "string" and entry.Name ~= "" then
				if not seenNames[entry.Name] then
					seenNames[entry.Name] = true
					filtered[#filtered + 1] = entry
				end
			end
		end
		return filtered
	end

	it("passes through unique residents", function()
		local incoming = {
			{ Name = "Alice" },
			{ Name = "Bob" },
			{ Name = "Carol" },
		}
		local result = filterDuplicates(incoming)
		assert.are.equal(3, #result)
	end)

	it("drops duplicate names, keeping the first occurrence", function()
		local incoming = {
			{ Name = "Alice", version = 1 },
			{ Name = "Bob" },
			{ Name = "Alice", version = 2 },
		}
		local result = filterDuplicates(incoming)
		assert.are.equal(2, #result)
		assert.are.equal(1, result[1].version)
	end)

	it("skips entries with empty names", function()
		local incoming = {
			{ Name = "" },
			{ Name = "Bob" },
		}
		local result = filterDuplicates(incoming)
		assert.are.equal(1, #result)
		assert.are.equal("Bob", result[1].Name)
	end)

	it("skips entries with non-string names", function()
		local incoming = {
			{ Name = 42 },
			{ Name = "Carol" },
		}
		local result = filterDuplicates(incoming)
		assert.are.equal(1, #result)
		assert.are.equal("Carol", result[1].Name)
	end)
end)

-- ====================================================================
-- Structural drift guards
-- ====================================================================

describe("ResidentService source wiring (structural)", function()
	local serviceSrc
	local tenantSrc

	before_each(function()
		serviceSrc = readFile("src/Server/Services/ResidentService.luau")
		tenantSrc = readFile("src/Server/Services/TenantService/init.luau")
	end)

	-- Map tables
	it("declares PlayersResidents, NameToIndexMap, TenantToResidentMap, ResidentToTenantMap", function()
		assert.is_truthy(string.find(serviceSrc, "PlayersResidents", 1, true))
		assert.is_truthy(string.find(serviceSrc, "NameToIndexMap", 1, true))
		assert.is_truthy(string.find(serviceSrc, "TenantToResidentMap", 1, true))
		assert.is_truthy(string.find(serviceSrc, "ResidentToTenantMap", 1, true))
	end)

	-- Occupancy guard
	it("keeps TenantsCount in sync with Tenants list length", function()
		assert.is_truthy(string.find(serviceSrc, "data%.TenantsCount%s*=", 1, false))
		assert.is_truthy(string.find(serviceSrc, "#data%.Tenants", 1, false))
	end)

	-- Duplicate guard on load
	it("uses a seenNames table to filter duplicates on load", function()
		assert.is_truthy(string.find(serviceSrc, "seenNames", 1, true))
	end)

	-- Career / appearance stripping before network
	it("strips appearance and career data on load and create", function()
		assert.is_truthy(string.find(serviceSrc, "stripCareerData", 1, true))
		assert.is_truthy(string.find(serviceSrc, "stripAppearance", 1, true))
	end)

	-- ResidentState wrapping
	it("wraps each loaded entry in a ResidentState object", function()
		assert.is_truthy(string.find(serviceSrc, "ResidentState.new", 1, true))
	end)

	-- Delete path calls Destroy
	it("DeleteResident calls Destroy on the ResidentState object", function()
		assert.is_truthy(string.find(serviceSrc, "resident:Destroy()", 1, true))
	end)

	-- Delete path rebuilds index map after removal
	it("DeleteResident rebuilds NameToIndexMap after table.remove", function()
		assert.is_truthy(string.find(serviceSrc, "table%.remove%(data%.Tenants", 1, false))
		assert.is_truthy(string.find(serviceSrc, "NameToIndexMap%[userId%]%s*=%s*{}", 1, false))
	end)

	-- PlayerResidentsChanged signal fired on mutations
	it("fires PlayerResidentsChanged signal on Load, Create, and Delete", function()
		local count = 0
		local pos = 1
		while true do
			local s = string.find(serviceSrc, "PlayerResidentsChanged:Fire", pos, true)
			if not s then
				break
			end
			count = count + 1
			pos = s + 1
		end
		assert.is_true(count >= 3, "Expected at least 3 PlayerResidentsChanged:Fire calls, got " .. count)
	end)

	-- Eviction wiring in TenantService
	it("TenantService concludes lease with 'Evicted' reason on EvictTenant", function()
		assert.is_truthy(string.find(tenantSrc, "concludeLease", 1, true))
		assert.is_truthy(string.find(tenantSrc, '"Evicted"', 1, true))
	end)

	-- Deposit not returned on eviction
	it("TenantService withholds deposit when reason is 'Evicted'", function()
		assert.is_truthy(string.find(tenantSrc, 'reason%s*~=%s*"Evicted"', 1, false))
	end)

	-- Resident unlinked when tenant concludes lease
	it("TenantService unlinks or deletes resident when lease concludes", function()
		assert.is_truthy(string.find(tenantSrc, "ResidentService.DeleteResident", 1, true))
		assert.is_truthy(string.find(tenantSrc, "ResidentService.ClearTenantLink", 1, true))
	end)

	-- Eviction request is exposed via packet
	it("EvictTenantRequest packet handler is wired in TenantService.Init", function()
		assert.is_truthy(string.find(tenantSrc, "EvictTenantRequest.OnServerInvoke", 1, true))
	end)
end)
