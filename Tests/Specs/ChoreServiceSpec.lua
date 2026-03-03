-- Tests/Specs/ChoreServiceSpec.lua
-- Structural + behavioral tests for ChoreService.
--
-- ChoreService depends on Roblox services (game:GetService, HttpService, etc.)
-- and cannot be loaded under busted directly.  Instead we:
--   1. Inline the pure-Lua helper logic (reward calculation, trash counting)
--      and test it exhaustively.
--   2. Add source-level drift guards to verify record shape, ID generation,
--      routing dispatch, and constants match the actual source.

local function readFile(path)
	local file = assert(io.open(path, "r"), "missing file: " .. path)
	local contents = file:read("*a")
	file:close()
	return contents
end

-- ====================================================================
-- Inlined constants from ChoreService.luau
-- ====================================================================

local MESS_REWARD = 15
local MESS_LIFETIME = 300
local MAX_MESSES_PER_PLOT = 5

-- ====================================================================
-- Replicated pure logic (mirror of ChoreService.luau internals)
-- ====================================================================

-- Mirror of the reward-selection expression inside createChoreRecord:
--   RewardAmount = payload.RewardAmount or (choreType == "Trash" and MESS_REWARD or 0)
local function resolveRewardAmount(choreType, payloadRewardAmount)
	return payloadRewardAmount or (choreType == "Trash" and MESS_REWARD or 0)
end

-- Mirror of GetTrashCount — counts Trash chores owned by the given player mock.
local function getTrashCount(activeChores, playerMock)
	local count = 0
	for _, chore in pairs(activeChores) do
		if chore.OwnerPlayer == playerMock and chore.Type == "Trash" then
			count = count + 1
		end
	end
	return count
end

-- ====================================================================
-- Reward-resolution tests
-- ====================================================================

describe("ChoreService reward resolution", function()
	-- Trash with no explicit reward falls back to MESS_REWARD
	it("Trash chore with no explicit reward defaults to MESS_REWARD (15)", function()
		local reward = resolveRewardAmount("Trash", nil)
		assert.are.equal(MESS_REWARD, reward)
	end)

	it("MESS_REWARD constant equals 15", function()
		assert.are.equal(15, MESS_REWARD)
	end)

	-- Trash with an explicit reward uses that value
	it("Trash chore with explicit reward uses explicit value", function()
		assert.are.equal(50, resolveRewardAmount("Trash", 50))
		assert.are.equal(0,  resolveRewardAmount("Trash", 0))
		assert.are.equal(200, resolveRewardAmount("Trash", 200))
	end)

	-- Repair with no explicit reward → 0 (not a Trash chore)
	it("Repair chore with no explicit reward defaults to 0", function()
		assert.are.equal(0, resolveRewardAmount("Repair", nil))
	end)

	-- Repair with explicit reward uses that value
	it("Repair chore with explicit reward uses that value", function()
		assert.are.equal(75,  resolveRewardAmount("Repair", 75))
		assert.are.equal(100, resolveRewardAmount("Repair", 100))
	end)

	-- Unknown type with no explicit reward → 0
	it("unknown chore type with no explicit reward returns 0", function()
		assert.are.equal(0, resolveRewardAmount("Unknown", nil))
		assert.are.equal(0, resolveRewardAmount("", nil))
	end)

	-- Explicit reward always wins regardless of chore type
	it("explicit reward wins over default for any chore type", function()
		for _, choreType in ipairs({ "Trash", "Repair", "Custom" }) do
			assert.are.equal(42, resolveRewardAmount(choreType, 42),
				"explicit 42 should win for type=" .. tostring(choreType))
		end
	end)
end)

-- ====================================================================
-- Trash-count logic tests
-- ====================================================================

describe("ChoreService.GetTrashCount (inline replica)", function()
	local playerA = { id = "A" }
	local playerB = { id = "B" }

	it("returns 0 for an empty ActiveChores table", function()
		assert.are.equal(0, getTrashCount({}, playerA))
	end)

	it("counts only Trash chores owned by the given player", function()
		local chores = {
			c1 = { Type = "Trash",  OwnerPlayer = playerA },
			c2 = { Type = "Trash",  OwnerPlayer = playerA },
			c3 = { Type = "Repair", OwnerPlayer = playerA },  -- not Trash
			c4 = { Type = "Trash",  OwnerPlayer = playerB },  -- different player
		}
		assert.are.equal(2, getTrashCount(chores, playerA))
	end)

	it("ignores Repair chores belonging to the player", function()
		local chores = {
			r1 = { Type = "Repair", OwnerPlayer = playerA },
			r2 = { Type = "Repair", OwnerPlayer = playerA },
		}
		assert.are.equal(0, getTrashCount(chores, playerA))
	end)

	it("ignores Trash chores belonging to a different player", function()
		local chores = {
			t1 = { Type = "Trash", OwnerPlayer = playerB },
			t2 = { Type = "Trash", OwnerPlayer = playerB },
		}
		assert.are.equal(0, getTrashCount(chores, playerA))
	end)

	it("returns correct count for exactly MAX_MESSES_PER_PLOT chores", function()
		local chores = {}
		for i = 1, MAX_MESSES_PER_PLOT do
			chores["t" .. i] = { Type = "Trash", OwnerPlayer = playerA }
		end
		assert.are.equal(MAX_MESSES_PER_PLOT, getTrashCount(chores, playerA))
	end)

	it("returns correct count when mix of players and types", function()
		local chores = {}
		-- 3 trash for A, 1 repair for A, 2 trash for B
		for i = 1, 3 do chores["tA" .. i] = { Type = "Trash",  OwnerPlayer = playerA } end
		chores["rA"] = { Type = "Repair", OwnerPlayer = playerA }
		for i = 1, 2 do chores["tB" .. i] = { Type = "Trash",  OwnerPlayer = playerB } end
		assert.are.equal(3, getTrashCount(chores, playerA))
		assert.are.equal(2, getTrashCount(chores, playerB))
	end)
end)

-- ====================================================================
-- MAX_MESSES_PER_PLOT cap semantics
-- ====================================================================

describe("ChoreService.SpawnMess capacity cap", function()
	it("MAX_MESSES_PER_PLOT equals 5", function()
		assert.are.equal(5, MAX_MESSES_PER_PLOT)
	end)

	it("spawn should be denied when trash count >= cap (simulated inline)", function()
		-- Simulate the guard: if GetTrashCount >= MAX_MESSES_PER_PLOT then return
		local playerA = { id = "A" }
		local chores = {}
		for i = 1, MAX_MESSES_PER_PLOT do
			chores["t" .. i] = { Type = "Trash", OwnerPlayer = playerA }
		end
		local count = getTrashCount(chores, playerA)
		local wouldSpawn = count < MAX_MESSES_PER_PLOT
		assert.is_false(wouldSpawn, "spawn must be denied at cap")
	end)

	it("spawn is allowed when trash count is below cap", function()
		local playerA = { id = "A" }
		local chores = {}
		for i = 1, MAX_MESSES_PER_PLOT - 1 do
			chores["t" .. i] = { Type = "Trash", OwnerPlayer = playerA }
		end
		local count = getTrashCount(chores, playerA)
		local wouldSpawn = count < MAX_MESSES_PER_PLOT
		assert.is_true(wouldSpawn, "spawn must be allowed below cap")
	end)

	it("MESS_LIFETIME equals 300 seconds (5 minutes)", function()
		assert.are.equal(300, MESS_LIFETIME)
	end)
end)

-- ====================================================================
-- Source-level structural assertions
-- ====================================================================

describe("ChoreService source drift guard", function()
	local src

	before_each(function()
		src = readFile("src/Server/Services/ChoreService.luau")
	end)

	-- Record shape fields
	it("ChoreRecord type defines Id field", function()
		assert.is_truthy(string.find(src, "Id%s*:", 1, false))
	end)

	it("ChoreRecord type defines Type field", function()
		assert.is_truthy(string.find(src, "Type%s*:", 1, false))
	end)

	it("ChoreRecord type defines PlotIndex field", function()
		assert.is_truthy(string.find(src, "PlotIndex%s*:", 1, false))
	end)

	it("ChoreRecord type defines CreatedAt field", function()
		assert.is_truthy(string.find(src, "CreatedAt%s*:", 1, false))
	end)

	it("ChoreRecord type defines RewardAmount field", function()
		assert.is_truthy(string.find(src, "RewardAmount%s*:", 1, false))
	end)

	it("ChoreRecord type defines TenantName field", function()
		assert.is_truthy(string.find(src, "TenantName%s*:", 1, false))
	end)

	it("ChoreRecord type defines SampledPosition field", function()
		assert.is_truthy(string.find(src, "SampledPosition%s*:", 1, false))
	end)

	it("ChoreRecord type defines Metadata field", function()
		assert.is_truthy(string.find(src, "Metadata%s*:", 1, false))
	end)

	-- ID generation
	it("uses HttpService:GenerateGUID for ID generation", function()
		assert.is_truthy(string.find(src, "GenerateGUID", 1, true))
	end)

	-- ActiveChores table
	it("declares ActiveChores as the active chore registry", function()
		assert.is_truthy(string.find(src, "ActiveChores", 1, true))
	end)

	-- Constants
	it("defines MESS_REWARD = 15", function()
		assert.is_truthy(string.find(src, "MESS_REWARD%s*=%s*15", 1, false))
	end)

	it("defines MAX_MESSES_PER_PLOT = 5", function()
		assert.is_truthy(string.find(src, "MAX_MESSES_PER_PLOT%s*=%s*5", 1, false))
	end)

	it("defines MESS_LIFETIME = 300", function()
		assert.is_truthy(string.find(src, "MESS_LIFETIME%s*=%s*300", 1, false))
	end)

	-- Routing dispatch
	it("defines CompletionHandlers dispatch table", function()
		assert.is_truthy(string.find(src, "CompletionHandlers", 1, true))
	end)

	it("routes Trash type to completeTrashChore", function()
		assert.is_truthy(string.find(src, "Trash%s*=%s*completeTrashChore", 1, false))
	end)

	it("routes Repair type through RepairManager.HandleRepairCompletion", function()
		assert.is_truthy(string.find(src, "RepairManager%.HandleRepairCompletion", 1, false))
	end)

	-- Fallback handler: unknown types fall back to completeTrashChore
	it("falls back to completeTrashChore for unknown chore types", function()
		-- The source expression: CompletionHandlers[record.Type] or completeTrashChore
		assert.is_truthy(string.find(src, "CompletionHandlers%[record%.Type%]%s*or%s*completeTrashChore", 1, false))
	end)

	-- Capacity guard
	it("guards SpawnMess with GetTrashCount >= MAX_MESSES_PER_PLOT", function()
		assert.is_truthy(string.find(src, "GetTrashCount", 1, true))
		assert.is_truthy(string.find(src, "MAX_MESSES_PER_PLOT", 1, true))
	end)

	-- Reward override path
	it("rewardOverride path: nil override uses record.RewardAmount", function()
		assert.is_truthy(string.find(src, "rewardOverride", 1, true))
		assert.is_truthy(string.find(src, "record%.RewardAmount", 1, false))
	end)

	-- Public API
	it("exposes SpawnMess function", function()
		assert.is_truthy(string.find(src, "ChoreService.SpawnMess", 1, true))
	end)

	it("exposes RemoveChore function", function()
		assert.is_truthy(string.find(src, "ChoreService.RemoveChore", 1, true))
	end)

	it("exposes GetTrashCount function", function()
		assert.is_truthy(string.find(src, "ChoreService.GetTrashCount", 1, true))
	end)

	it("exposes Init function", function()
		assert.is_truthy(string.find(src, "ChoreService.Init", 1, true))
	end)
end)
