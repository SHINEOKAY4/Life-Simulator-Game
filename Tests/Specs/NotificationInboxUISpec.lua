--!strict
-- Tests/Specs/NotificationInboxUISpec.lua
-- Structural tests for the client-side NotificationInboxUI module and its integration wiring.
-- Validates file existence, API shape, packet references, and MainHUD / Main.client wiring.

local function readFile(path)
	local file = assert(io.open(path, "r"), "missing file: " .. path)
	local contents = file:read("*a")
	file:close()
	return contents
end

-- ── NotificationInboxUI file structure ────────────────────────────────────────

describe("NotificationInboxUI file structure", function()
	local src

	before_each(function()
		src = readFile("src/Client/UserInterface/NotificationInboxUI.luau")
	end)

	it("NotificationInboxUI.luau exists and is non-empty", function()
		assert.is_truthy(#src > 0)
	end)

	it("uses strict mode", function()
		assert.is_truthy(string.find(src, "--!strict", 1, true))
	end)

	it("requires NotificationPackets", function()
		assert.is_truthy(string.find(src, "NotificationPackets", 1, true))
	end)

	it("exposes Init()", function()
		assert.is_truthy(string.find(src, "NotificationInboxUI.Init", 1, true))
	end)

	it("exposes Toggle()", function()
		assert.is_truthy(string.find(src, "NotificationInboxUI.Toggle", 1, true))
	end)

	it("exposes SetVisible()", function()
		assert.is_truthy(string.find(src, "NotificationInboxUI.SetVisible", 1, true))
	end)

	it("subscribes to StateSnapshot for full sync", function()
		assert.is_truthy(string.find(src, "StateSnapshot", 1, true))
	end)

	it("subscribes to NotificationDelta for incremental updates", function()
		assert.is_truthy(string.find(src, "NotificationDelta", 1, true))
	end)

	it("caps displayed notifications at 20", function()
		assert.is_truthy(string.find(src, "MAX_DISPLAY", 1, true) or
			string.find(src, "20", 1, true))
	end)

	it("shows unread indicator dot per row", function()
		assert.is_truthy(string.find(src, "UnreadDot", 1, true))
	end)

	it("shows unread count badge", function()
		assert.is_truthy(string.find(src, "UnreadCount", 1, true) or
			string.find(src, "unreadCountLabel", 1, true))
	end)

	it("has a read-toggle per notification", function()
		assert.is_truthy(string.find(src, "ReadToggle", 1, true) or
			string.find(src, "toggleButton", 1, true))
	end)

	it("has a mark-all-read button", function()
		assert.is_truthy(string.find(src, "MarkAllRead", 1, true) or
			string.find(src, "markAllBtn", 1, true))
	end)

	it("shows an empty state label when no notifications exist", function()
		assert.is_truthy(string.find(src, "No notifications yet", 1, true))
	end)

	it("renders a scrollable notification list", function()
		assert.is_truthy(string.find(src, "NotificationList", 1, true))
	end)

	it("shows notification Title", function()
		assert.is_truthy(string.find(src, "TitleLabel", 1, true))
	end)

	it("shows notification Body", function()
		assert.is_truthy(string.find(src, "BodyLabel", 1, true))
	end)

	it("shows notification Category", function()
		assert.is_truthy(string.find(src, "Category", 1, true))
	end)

	it("shows notification Timestamp", function()
		assert.is_truthy(string.find(src, "Timestamp", 1, true))
	end)

	it("has an overlay close region", function()
		assert.is_truthy(string.find(src, "Overlay", 1, true))
	end)

	it("has a close button", function()
		assert.is_truthy(string.find(src, "CloseButton", 1, true))
	end)

	it("uses open/close animation tweens", function()
		assert.is_truthy(string.find(src, "OPEN_TWEEN", 1, true))
		assert.is_truthy(string.find(src, "CLOSE_TWEEN", 1, true))
	end)

	it("has applySnapshot local function to handle full queue", function()
		assert.is_truthy(string.find(src, "applySnapshot", 1, true))
	end)

	it("has applyDelta local function to handle incremental notification", function()
		assert.is_truthy(string.find(src, "applyDelta", 1, true))
	end)
end)

-- ── MainHUD wiring ─────────────────────────────────────────────────────────────

describe("MainHUD wiring for NotificationInboxUI", function()
	local src

	before_each(function()
		src = readFile("src/Client/UserInterface/MainHUD.luau")
	end)

	it("requires NotificationInboxUI", function()
		assert.is_truthy(string.find(src, "NotificationInboxUI", 1, true))
	end)

	it("creates a NotificationsButton", function()
		assert.is_truthy(string.find(src, "NotificationsButton", 1, true))
	end)

	it("wires Activated to NotificationInboxUI.Toggle", function()
		assert.is_truthy(string.find(src, "NotificationInboxUI.Toggle", 1, true))
	end)

	it("includes NotificationsButton in configureButtonVisuals loop", function()
		-- The list passed to the loop should include NotificationsButton
		assert.is_truthy(string.find(src, "NotificationsButton", 1, true))
		-- Verify it's in the same line as EmotesButton (part of the button list)
		local loopLine = string.match(src, "for _, button in ipairs%(%{[^}]+%}%)")
		assert.is_truthy(loopLine and string.find(loopLine, "NotificationsButton", 1, true))
	end)
end)

-- ── Main.client.luau wiring ────────────────────────────────────────────────────

describe("Main.client.luau wiring for NotificationInboxUI", function()
	local src

	before_each(function()
		src = readFile("src/Client/Main.client.luau")
	end)

	it("requires NotificationInboxUI", function()
		assert.is_truthy(string.find(src, "NotificationInboxUI", 1, true))
	end)

	it("calls NotificationInboxUI.Init in startup sequence", function()
		assert.is_truthy(string.find(src, "NotificationInboxUI.Init", 1, true))
	end)

	it("initializes NotificationInboxUI after EmoteUI (ordering check)", function()
		local emotePos = string.find(src, "EmoteUI.Init", 1, true)
		local notifPos = string.find(src, "NotificationInboxUI.Init", 1, true)
		assert.is_truthy(emotePos and notifPos)
		assert.is_true(notifPos > emotePos)
	end)
end)

-- ── NotificationPackets packet schema ─────────────────────────────────────────

describe("NotificationPackets schema used by NotificationInboxUI", function()
	local src

	before_each(function()
		src = readFile("src/Network/NotificationPackets.luau")
	end)

	it("NotificationPackets.luau exists and is non-empty", function()
		assert.is_truthy(#src > 0)
	end)

	it("defines StateSnapshot packet", function()
		assert.is_truthy(string.find(src, "StateSnapshot", 1, true))
	end)

	it("defines NotificationDelta packet", function()
		assert.is_truthy(string.find(src, "NotificationDelta", 1, true))
	end)

	it("payload includes Id field", function()
		assert.is_truthy(string.find(src, "Id", 1, true))
	end)

	it("payload includes Title field", function()
		assert.is_truthy(string.find(src, "Title", 1, true))
	end)

	it("payload includes Body field", function()
		assert.is_truthy(string.find(src, "Body", 1, true))
	end)

	it("payload includes Category field", function()
		assert.is_truthy(string.find(src, "Category", 1, true))
	end)

	it("payload includes Read field", function()
		assert.is_truthy(string.find(src, "Read", 1, true))
	end)

	it("payload includes Timestamp field", function()
		assert.is_truthy(string.find(src, "Timestamp", 1, true))
	end)
end)
