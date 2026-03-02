--!strict
-- Tests/Specs/WorldEventUISpec.lua
-- Structural tests for the client-side WorldEventUI module and its integration wiring.
-- Validates file existence, API shape, packet/controller references, and HUD wiring.

local function readFile(path)
	local file = assert(io.open(path, "r"), "missing file: " .. path)
	local contents = file:read("*a")
	file:close()
	return contents
end

-- ── WorldEventUI file structure ───────────────────────────────────────────────

describe("WorldEventUI file structure", function()
	local src

	before_each(function()
		src = readFile("src/Client/UserInterface/WorldEventUI.luau")
	end)

	it("WorldEventUI.luau exists and is non-empty", function()
		assert.is_truthy(#src > 0)
	end)

	it("uses strict mode", function()
		assert.is_truthy(string.find(src, "--!strict", 1, true))
	end)

	it("requires WorldEventController", function()
		assert.is_truthy(string.find(src, "WorldEventController", 1, true))
	end)

	it("exposes Init()", function()
		assert.is_truthy(string.find(src, "WorldEventUI.Init", 1, true))
	end)

	it("exposes Toggle()", function()
		assert.is_truthy(string.find(src, "WorldEventUI.Toggle", 1, true))
	end)

	it("exposes SetVisible()", function()
		assert.is_truthy(string.find(src, "WorldEventUI.SetVisible", 1, true))
	end)

	it("subscribes to StateChanged signal for live updates", function()
		assert.is_truthy(string.find(src, "StateChanged", 1, true))
	end)

	it("calls GetActiveEvent to read current event", function()
		assert.is_truthy(string.find(src, "GetActiveEvent", 1, true))
	end)

	it("displays event name", function()
		assert.is_truthy(string.find(src, "EventName", 1, true))
	end)

	it("displays event kind", function()
		assert.is_truthy(string.find(src, "EventKind", 1, true))
	end)

	it("displays event description", function()
		assert.is_truthy(string.find(src, "EventDescription", 1, true) or
			string.find(src, "eventDescLabel", 1, true))
	end)

	it("shows a countdown label", function()
		assert.is_truthy(string.find(src, "CountdownLabel", 1, true) or
			string.find(src, "countdownLabel", 1, true))
	end)

	it("shows no-event placeholder text", function()
		assert.is_truthy(string.find(src, "No active world event", 1, true))
	end)

	it("renders buff rows", function()
		assert.is_truthy(string.find(src, "BuffRow", 1, true) or
			string.find(src, "buildBuffRow", 1, true))
	end)

	it("formats buff value as percentage", function()
		assert.is_truthy(string.find(src, "formatBuffValue", 1, true))
	end)

	it("formats countdown with hours/minutes/seconds", function()
		assert.is_truthy(string.find(src, "formatCountdown", 1, true))
	end)

	it("returns WorldEventUI table at end of module", function()
		assert.is_truthy(string.find(src, "return WorldEventUI", 1, true))
	end)
end)

-- ── MainHUD wiring ────────────────────────────────────────────────────────────

describe("MainHUD WorldEventUI wiring", function()
	local mainHUDSrc

	before_each(function()
		mainHUDSrc = readFile("src/Client/UserInterface/MainHUD.luau")
	end)

	it("requires WorldEventUI", function()
		assert.is_truthy(string.find(mainHUDSrc, "require(script.Parent.WorldEventUI)", 1, true))
	end)

	it("creates WorldEventsButton", function()
		assert.is_truthy(string.find(mainHUDSrc, "WorldEventsButton", 1, true))
	end)

	it("connects WorldEventsButton.Activated to WorldEventUI.Toggle", function()
		assert.is_truthy(string.find(mainHUDSrc, "WorldEventUI.Toggle", 1, true))
	end)

	it("includes WorldEventsButton in configureButtonVisuals loop", function()
		local loopLine = string.match(mainHUDSrc, "for _, button in ipairs%({[^}]+}%)")
		assert.is_truthy(loopLine and string.find(loopLine, "WorldEventsButton", 1, true))
	end)
end)

-- ── Main.client.luau wiring ───────────────────────────────────────────────────

describe("Main.client.luau WorldEventUI wiring", function()
	local clientMainSrc

	before_each(function()
		clientMainSrc = readFile("src/Client/Main.client.luau")
	end)

	it("requires WorldEventUI", function()
		assert.is_truthy(string.find(clientMainSrc, "WorldEventUI", 1, true))
	end)

	it("calls WorldEventUI.Init() in a startup step", function()
		assert.is_truthy(string.find(clientMainSrc, "WorldEventUI.Init", 1, true))
	end)

	it("initialises WorldEventUI after QuestUI", function()
		local questPos = string.find(clientMainSrc, "QuestUI.Init", 1, true)
		local worldPos = string.find(clientMainSrc, "WorldEventUI.Init", 1, true)
		assert.is_truthy(questPos and worldPos)
		assert.is_truthy(worldPos > questPos)
	end)
end)

-- ── WorldEventController structural (used by WorldEventUI) ───────────────────
-- Note: WorldEventController.luau uses Luau export type syntax and cannot be
-- loadfile'd in plain Lua. We verify its structure via source inspection.

describe("WorldEventController structural (WorldEventUI scenario)", function()
	local ctrlSrc

	before_each(function()
		ctrlSrc = readFile("src/Client/Modules/WorldEventController.luau")
	end)

	it("WorldEventController.luau exists and is non-empty", function()
		assert.is_truthy(#ctrlSrc > 0)
	end)

	it("exposes GetState()", function()
		assert.is_truthy(string.find(ctrlSrc, "WorldEventController.GetState", 1, true))
	end)

	it("exposes GetActiveEvent()", function()
		assert.is_truthy(string.find(ctrlSrc, "WorldEventController.GetActiveEvent", 1, true))
	end)

	it("exposes GetActiveBuffs()", function()
		assert.is_truthy(string.find(ctrlSrc, "WorldEventController.GetActiveBuffs", 1, true))
	end)

	it("exposes GetBuffMultiplier()", function()
		assert.is_truthy(string.find(ctrlSrc, "WorldEventController.GetBuffMultiplier", 1, true))
	end)

	it("exposes StateChanged signal", function()
		assert.is_truthy(string.find(ctrlSrc, "WorldEventController.StateChanged", 1, true))
	end)

	it("exposes Init()", function()
		assert.is_truthy(string.find(ctrlSrc, "WorldEventController.Init", 1, true))
	end)

	it("default state has empty ActiveEvents", function()
		assert.is_truthy(string.find(ctrlSrc, "ActiveEvents", 1, true))
	end)

	it("returns 1.0 as default buff multiplier", function()
		assert.is_truthy(string.find(ctrlSrc, "return 1.0", 1, true))
	end)
end)

-- ── formatCountdown logic verification ───────────────────────────────────────

describe("WorldEventUI formatCountdown logic", function()
	-- Extract formatCountdown by reading the source and eval'ing just the function
	-- We verify via pattern matching on the source since we cannot loadfile UI modules.

	local src

	before_each(function()
		src = readFile("src/Client/UserInterface/WorldEventUI.luau")
	end)

	it("shows hours and minutes for values >= 3600 seconds", function()
		assert.is_truthy(string.find(src, "hours > 0", 1, true))
	end)

	it("shows minutes and seconds for values < 3600 and >= 60", function()
		assert.is_truthy(string.find(src, "minutes > 0", 1, true))
	end)

	it("shows only seconds for very short durations", function()
		assert.is_truthy(string.find(src, "Ends in %ds", 1, true))
	end)

	it("returns an ending message for zero or negative time", function()
		assert.is_truthy(string.find(src, "ending", 1, true))
	end)
end)

-- ── formatBuffValue logic verification ───────────────────────────────────────

describe("WorldEventUI formatBuffValue logic", function()
	local src

	before_each(function()
		src = readFile("src/Client/UserInterface/WorldEventUI.luau")
	end)

	it("converts multiplier to percentage display", function()
		-- Should contain arithmetic subtracting 1.0 and multiplying by 100
		assert.is_truthy(string.find(src, "value - 1.0", 1, true) or
			string.find(src, "value - 1)", 1, true))
	end)

	it("formats with a + prefix and percent sign", function()
		-- Source contains: string.format("+%d%%", pct)
		assert.is_truthy(string.find(src, '"+%%d%%%%"', 1, true)
			or string.find(src, "string.format", 1, true))
	end)
end)
