--!strict
-- Unit tests for WorldEventDefinitions and WorldEventService

local WorldEventDefinitions = assert(loadfile("src/Shared/Definitions/WorldEventDefinitions.luau"))()
local WorldEventService = assert(loadfile("src/Server/Services/WorldEventService.luau"))()

-- ====================================================================
-- WorldEventDefinitions tests
-- ====================================================================

describe("WorldEventDefinitions", function()
	it("has a non-empty EventPool", function()
		assert.is_true(#WorldEventDefinitions.EventPool >= 1)
	end)

	it("contains at least 6 events", function()
		assert.is_true(WorldEventDefinitions.GetEventCount() >= 6)
	end)

	it("each event has required fields", function()
		for _, def in ipairs(WorldEventDefinitions.EventPool) do
			assert.is_truthy(def.Id, "event must have Id")
			assert.is_truthy(def.Name, "event must have Name")
			assert.is_truthy(def.Description, "event must have Description")
			assert.is_truthy(def.Kind, "event must have Kind")
			assert.is_truthy(def.Buffs, "event must have Buffs table")
			assert.is_true(#def.Buffs >= 1, "event " .. def.Id .. " must have at least one buff")
		end
	end)

	it("each buff has Type, Value, and Label", function()
		for _, def in ipairs(WorldEventDefinitions.EventPool) do
			for _, buff in ipairs(def.Buffs) do
				assert.is_truthy(buff.Type, "buff must have Type")
				assert.is_true(type(buff.Value) == "number", "buff.Value must be a number")
				assert.is_true(buff.Value > 1.0, "buff.Value must be > 1.0 (it is a multiplier)")
				assert.is_truthy(buff.Label, "buff must have Label")
			end
		end
	end)

	it("all event IDs are unique", function()
		local seen = {}
		for _, def in ipairs(WorldEventDefinitions.EventPool) do
			assert.is_nil(seen[def.Id], "duplicate event Id: " .. def.Id)
			seen[def.Id] = true
		end
	end)

	it("ById lookup matches EventPool entries", function()
		for _, def in ipairs(WorldEventDefinitions.EventPool) do
			assert.equals(def, WorldEventDefinitions.ById[def.Id])
		end
	end)

	it("GetEvent returns correct definition", function()
		local fest = WorldEventDefinitions.GetEvent("community_festival")
		assert.is_not_nil(fest)
		assert.equals("Community Festival", fest.Name)
		assert.equals("Celebration", fest.Kind)
	end)

	it("GetEvent returns nil for unknown id", function()
		assert.is_nil(WorldEventDefinitions.GetEvent("nonexistent_event"))
	end)

	it("GetBuffsForEvent returns buffs for a valid event", function()
		local buffs = WorldEventDefinitions.GetBuffsForEvent("community_festival")
		assert.is_true(#buffs >= 1)
		assert.equals("CashMultiplier", buffs[1].Type)
	end)

	it("GetBuffsForEvent returns empty table for unknown event", function()
		local buffs = WorldEventDefinitions.GetBuffsForEvent("nonexistent")
		assert.is_true(#buffs == 0)
	end)

	it("includes diverse event Kinds", function()
		local kinds = {}
		for _, def in ipairs(WorldEventDefinitions.EventPool) do
			kinds[def.Kind] = true
		end
		-- Expect at least 4 distinct kinds
		local count = 0
		for _ in pairs(kinds) do
			count = count + 1
		end
		assert.is_true(count >= 4, "expected at least 4 distinct event kinds, got " .. count)
	end)

	it("includes events with multiple buffs", function()
		local hasMulti = false
		for _, def in ipairs(WorldEventDefinitions.EventPool) do
			if #def.Buffs > 1 then
				hasMulti = true
				break
			end
		end
		assert.is_true(hasMulti, "at least one event should have multiple buffs")
	end)
end)

-- ====================================================================
-- WorldEventService tests
-- ====================================================================

describe("WorldEventService", function()
	local currentTime

	before_each(function()
		currentTime = 1000000
		WorldEventService._ResetForTests()
		WorldEventService._SetClock(function()
			return currentTime
		end)
	end)

	after_each(function()
		WorldEventService._ResetForTests()
	end)

	-- ========== Rotation basics ==========

	describe("rotation lifecycle", function()
		it("starts with a placeholder rotation that expires immediately", function()
			-- After reset, ensureRotation will trigger on first query
			local snapshot = WorldEventService.GetStateSnapshot()
			assert.is_not_nil(snapshot)
			assert.is_truthy(snapshot.RotationId)
			assert.is_true(snapshot.RotationId ~= "placeholder", "rotation should be assigned a real ID")
		end)

		it("GetStateSnapshot returns ActiveEvents with exactly one event", function()
			local snapshot = WorldEventService.GetStateSnapshot()
			assert.is_true(#snapshot.ActiveEvents == 1)
		end)

		it("active event has all required fields", function()
			local snapshot = WorldEventService.GetStateSnapshot()
			local event = snapshot.ActiveEvents[1]
			assert.is_truthy(event.Id)
			assert.is_truthy(event.Name)
			assert.is_truthy(event.Description)
			assert.is_truthy(event.Kind)
			assert.is_true(type(event.StartsAt) == "number")
			assert.is_true(type(event.EndsAt) == "number")
			assert.is_truthy(event.Buffs)
			assert.is_true(#event.Buffs >= 1, "event must have at least one buff")
		end)

		it("active event buffs have Type, Value, and Label", function()
			local snapshot = WorldEventService.GetStateSnapshot()
			for _, buff in ipairs(snapshot.ActiveEvents[1].Buffs) do
				assert.is_truthy(buff.Type)
				assert.is_true(type(buff.Value) == "number")
				assert.is_truthy(buff.Label)
			end
		end)

		it("rotation endsAt is in the future", function()
			local snapshot = WorldEventService.GetStateSnapshot()
			assert.is_true(snapshot.RotationEndsAt > currentTime)
		end)

		it("rotation duration matches expected 2 hours", function()
			local snapshot = WorldEventService.GetStateSnapshot()
			local event = snapshot.ActiveEvents[1]
			assert.equals(2 * 60 * 60, event.EndsAt - event.StartsAt)
		end)

		it("same rotation is returned within the time window", function()
			local snap1 = WorldEventService.GetStateSnapshot()
			currentTime = currentTime + 100
			local snap2 = WorldEventService.GetStateSnapshot()
			assert.equals(snap1.RotationId, snap2.RotationId)
			assert.equals(snap1.ActiveEvents[1].Id, snap2.ActiveEvents[1].Id)
		end)

		it("new rotation is created after expiry", function()
			local snap1 = WorldEventService.GetStateSnapshot()
			local firstId = snap1.RotationId
			-- Fast-forward past rotation end
			currentTime = currentTime + WorldEventService._GetRotationDuration() + 1
			local snap2 = WorldEventService.GetStateSnapshot()
			assert.is_true(snap2.RotationId ~= firstId, "rotation should change after expiry")
		end)
	end)

	-- ========== No-repeat logic ==========

	describe("no-repeat event selection", function()
		it("avoids selecting the same event back-to-back", function()
			-- Force a deterministic RNG that always picks index 1
			WorldEventService._SetRng(function(min, max)
				return min
			end)

			local snap1 = WorldEventService.GetStateSnapshot()
			local firstEventId = snap1.ActiveEvents[1].Id

			-- Expire and get new rotation
			currentTime = currentTime + WorldEventService._GetRotationDuration() + 1
			WorldEventService._ForceExpire()
			local snap2 = WorldEventService.GetStateSnapshot()
			local secondEventId = snap2.ActiveEvents[1].Id

			assert.is_true(firstEventId ~= secondEventId,
				"should not repeat " .. firstEventId .. " back-to-back")
		end)

		it("tracks the last event ID", function()
			local snap = WorldEventService.GetStateSnapshot()
			assert.equals(snap.ActiveEvents[1].Id, WorldEventService._GetLastEventId())
		end)
	end)

	-- ========== Buff multiplier API ==========

	describe("GetBuffMultiplier", function()
		it("returns 1.0 for non-string buffType", function()
			assert.equals(1.0, WorldEventService.GetBuffMultiplier(nil))
			assert.equals(1.0, WorldEventService.GetBuffMultiplier(123))
		end)

		it("returns 1.0 for unknown buff type", function()
			-- Ensure rotation is active
			WorldEventService.GetStateSnapshot()
			assert.equals(1.0, WorldEventService.GetBuffMultiplier("NonExistentBuff"))
		end)

		it("returns correct multiplier for an active buff", function()
			-- Force a specific event: community_festival has CashMultiplier = 1.10
			WorldEventService._SetRng(function(min, max)
				-- Find index of community_festival in the pool
				for i, def in ipairs(WorldEventDefinitions.EventPool) do
					if def.Id == "community_festival" then
						-- Adjust for candidates list (which may exclude the last event)
						return min -- first candidate
					end
				end
				return min
			end)

			-- Force the active event to be community_festival by resetting
			WorldEventService._ResetForTests()
			WorldEventService._SetClock(function()
				return currentTime
			end)

			-- Make sure community_festival gets picked by using a RNG that picks
			-- the index that matches community_festival
			local targetIndex = 1
			for i, def in ipairs(WorldEventDefinitions.EventPool) do
				if def.Id == "community_festival" then
					targetIndex = i
					break
				end
			end
			WorldEventService._SetRng(function(min, max)
				if targetIndex >= min and targetIndex <= max then
					return targetIndex
				end
				return min
			end)

			local snap = WorldEventService.GetStateSnapshot()
			local eventId = snap.ActiveEvents[1].Id

			-- Get the expected buffs from the definition
			local def = WorldEventDefinitions.GetEvent(eventId)
			assert.is_not_nil(def, "active event should exist in definitions")
			for _, buff in ipairs(def.Buffs) do
				local mult = WorldEventService.GetBuffMultiplier(buff.Type)
				assert.equals(buff.Value, mult)
			end
		end)
	end)

	-- ========== GetActiveBuffs ==========

	describe("GetActiveBuffs", function()
		it("returns a non-empty table", function()
			WorldEventService.GetStateSnapshot() -- ensure rotation
			local buffs = WorldEventService.GetActiveBuffs()
			assert.is_true(#buffs >= 1)
		end)

		it("each buff has Type, Value, and Label", function()
			WorldEventService.GetStateSnapshot()
			local buffs = WorldEventService.GetActiveBuffs()
			for _, buff in ipairs(buffs) do
				assert.is_truthy(buff.Type)
				assert.is_true(type(buff.Value) == "number")
				assert.is_truthy(buff.Label)
			end
		end)
	end)

	-- ========== GetActiveEvent ==========

	describe("GetActiveEvent", function()
		it("returns an event after rotation starts", function()
			WorldEventService.GetStateSnapshot()
			local event = WorldEventService.GetActiveEvent()
			assert.is_not_nil(event)
			assert.is_truthy(event.Id)
			assert.is_truthy(event.Name)
			assert.is_truthy(event.Buffs)
		end)

		it("returned event matches the active rotation event", function()
			local snap = WorldEventService.GetStateSnapshot()
			local event = WorldEventService.GetActiveEvent()
			assert.equals(snap.ActiveEvents[1].Id, event.Id)
			assert.equals(snap.ActiveEvents[1].Name, event.Name)
		end)

		it("returns a defensive copy so callers cannot mutate active rotation state", function()
			WorldEventService.GetStateSnapshot()
			local event = WorldEventService.GetActiveEvent()
			assert.is_not_nil(event)
			assert.is_true(#event.Buffs >= 1)

			local buffType = event.Buffs[1].Type
			local originalValue = WorldEventService.GetBuffMultiplier(buffType)

			event.Buffs[1].Value = 999
			event.Name = "Mutated Client Value"

			assert.equals(originalValue, WorldEventService.GetBuffMultiplier(buffType))

			local freshEvent = WorldEventService.GetActiveEvent()
			assert.is_true(freshEvent.Name ~= "Mutated Client Value")
		end)
	end)

	-- ========== ForceExpire ==========

	describe("_ForceExpire", function()
		it("causes next query to generate a new rotation", function()
			local snap1 = WorldEventService.GetStateSnapshot()
			local id1 = snap1.RotationId
			WorldEventService._ForceExpire()
			currentTime = currentTime + 1
			local snap2 = WorldEventService.GetStateSnapshot()
			assert.is_true(snap2.RotationId ~= id1)
		end)
	end)
end)

-- ====================================================================
-- Structural tests: source-level verification
-- ====================================================================

describe("WorldEventService: source structure", function()
	local function readFile(path)
		local file = assert(io.open(path, "r"), "missing file: " .. path)
		local contents = file:read("*a")
		file:close()
		return contents
	end

	it("WorldEventService.luau uses hasRobloxRuntime guard", function()
		local src = readFile("src/Server/Services/WorldEventService.luau")
		assert.is_truthy(string.find(src, "hasRobloxRuntime", 1, true))
	end)

	it("WorldEventService.luau loads WorldEventDefinitions in both environments", function()
		local src = readFile("src/Server/Services/WorldEventService.luau")
		assert.is_truthy(string.find(src, "WorldEventDefinitions", 1, true))
	end)

	it("WorldEventService.luau exposes GetBuffMultiplier", function()
		local src = readFile("src/Server/Services/WorldEventService.luau")
		assert.is_truthy(string.find(src, "function WorldEventService.GetBuffMultiplier", 1, true))
	end)

	it("WorldEventService.luau exposes GetActiveBuffs", function()
		local src = readFile("src/Server/Services/WorldEventService.luau")
		assert.is_truthy(string.find(src, "function WorldEventService.GetActiveBuffs", 1, true))
	end)

	it("WorldEventService.luau exposes GetActiveEvent", function()
		local src = readFile("src/Server/Services/WorldEventService.luau")
		assert.is_truthy(string.find(src, "function WorldEventService.GetActiveEvent", 1, true))
	end)

	it("WorldEventService.luau implements no-repeat selection logic", function()
		local src = readFile("src/Server/Services/WorldEventService.luau")
		assert.is_truthy(string.find(src, "LastEventId", 1, true))
	end)

	it("WorldEventDefinitions.luau defines all 6 events", function()
		local src = readFile("src/Shared/Definitions/WorldEventDefinitions.luau")
		assert.is_truthy(string.find(src, "community_festival", 1, true))
		assert.is_truthy(string.find(src, "builders_bazaar", 1, true))
		assert.is_truthy(string.find(src, "tenant_appreciation_week", 1, true))
		assert.is_truthy(string.find(src, "craft_fair", 1, true))
		assert.is_truthy(string.find(src, "property_showcase", 1, true))
		assert.is_truthy(string.find(src, "neighborhood_cleanup", 1, true))
	end)

	it("WorldEventPackets.luau includes buff payload", function()
		local src = readFile("src/Network/WorldEventPackets.luau")
		assert.is_truthy(string.find(src, "buffPayload", 1, true))
		assert.is_truthy(string.find(src, "Buffs", 1, true))
	end)

	it("WorldEventController.luau exposes GetBuffMultiplier and GetActiveBuffs", function()
		local src = readFile("src/Client/Modules/WorldEventController.luau")
		assert.is_truthy(string.find(src, "function WorldEventController.GetBuffMultiplier", 1, true))
		assert.is_truthy(string.find(src, "function WorldEventController.GetActiveBuffs", 1, true))
		assert.is_truthy(string.find(src, "function WorldEventController.GetActiveEvent", 1, true))
	end)
end)
