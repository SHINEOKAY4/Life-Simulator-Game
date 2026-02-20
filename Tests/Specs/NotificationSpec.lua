--!strict
-- Tests/Specs/NotificationSpec.lua
-- Unit tests for NotificationService

local NotificationService = assert(loadfile("src/Server/Services/NotificationService.luau"))()

describe("NotificationService", function()
	local clockTime

	before_each(function()
		NotificationService._ResetForTests()
		clockTime = 1000
		NotificationService._SetClock(function() return clockTime end)
	end)

	-- ============ Send ============

	describe("Send", function()
		it("should create a notification with correct fields", function()
			local notif, err = NotificationService.Send("player1", "Quest", "New Quest", "Go explore the forest")
			assert.is_nil(err)
			assert.is_not_nil(notif)
			assert.equals(1, notif.Id)
			assert.equals("Quest", notif.Category)
			assert.equals("New Quest", notif.Title)
			assert.equals("Go explore the forest", notif.Body)
			assert.equals("quest", notif.Icon)
			assert.equals(3, notif.Priority)
			assert.equals(6, notif.Duration)
			assert.equals(1000, notif.Timestamp)
			assert.is_false(notif.Read)
		end)

		it("should reject nil player", function()
			local notif, err = NotificationService.Send(nil, "Quest", "Title", "Body")
			assert.is_nil(notif)
			assert.equals("InvalidPlayer", err)
		end)

		it("should reject empty title", function()
			local notif, err = NotificationService.Send("player1", "Quest", "", "Body")
			assert.is_nil(notif)
			assert.equals("InvalidTitle", err)
		end)

		it("should reject non-string title", function()
			local notif, err = NotificationService.Send("player1", "Quest", 123, "Body")
			assert.is_nil(notif)
			assert.equals("InvalidTitle", err)
		end)

		it("should reject non-string body", function()
			local notif, err = NotificationService.Send("player1", "Quest", "Title", nil)
			assert.is_nil(notif)
			assert.equals("InvalidBody", err)
		end)

		it("should reject invalid category", function()
			local notif, err = NotificationService.Send("player1", "FakeCategory", "Title", "Body")
			assert.is_nil(notif)
			assert.equals("InvalidCategory", err)
		end)

		it("should assign monotonically increasing IDs", function()
			local n1 = NotificationService.Send("player1", "Quest", "A", "a")
			local n2 = NotificationService.Send("player1", "Quest", "B", "b")
			local n3 = NotificationService.Send("player1", "Quest", "C", "c")
			assert.equals(1, n1.Id)
			assert.equals(2, n2.Id)
			assert.equals(3, n3.Id)
		end)

		it("should store metadata when provided", function()
			local notif = NotificationService.Send("player1", "Trade", "Trade Offer", "You got an offer", {
				TradeId = "abc123",
				FromPlayer = "player2",
			})
			assert.is_not_nil(notif)
			assert.equals("abc123", notif.Metadata.TradeId)
			assert.equals("player2", notif.Metadata.FromPlayer)
		end)

		it("should default metadata to empty table when not provided", function()
			local notif = NotificationService.Send("player1", "Quest", "Title", "Body")
			assert.is_not_nil(notif)
			assert.same({}, notif.Metadata)
		end)

		it("should isolate notifications between players", function()
			NotificationService.Send("player1", "Quest", "P1 Quest", "For player 1")
			NotificationService.Send("player2", "Quest", "P2 Quest", "For player 2")
			assert.equals(1, NotificationService.GetQueueSize("player1"))
			assert.equals(1, NotificationService.GetQueueSize("player2"))
		end)
	end)

	-- ============ Priority Ordering ============

	describe("Priority ordering", function()
		it("should order queue by priority descending", function()
			NotificationService.Send("player1", "Social", "Low", "Low priority")      -- Priority 1
			NotificationService.Send("player1", "System", "High", "System message")    -- Priority 5
			NotificationService.Send("player1", "Quest", "Medium", "Quest update")     -- Priority 3

			local top = NotificationService.PeekNext("player1")
			assert.equals("System", top.Category)
			assert.equals("High", top.Title)
		end)

		it("should preserve FIFO within same priority", function()
			clockTime = 100
			NotificationService.Send("player1", "Quest", "First", "First quest")
			clockTime = 200
			NotificationService.Send("player1", "Quest", "Second", "Second quest")

			local first = NotificationService.PopNext("player1")
			assert.equals("First", first.Title)
			local second = NotificationService.PopNext("player1")
			assert.equals("Second", second.Title)
		end)
	end)

	-- ============ PopNext ============

	describe("PopNext", function()
		it("should remove and return the highest priority notification", function()
			NotificationService.Send("player1", "Social", "Low", "Low")
			NotificationService.Send("player1", "Achievement", "High", "High")

			local popped = NotificationService.PopNext("player1")
			assert.equals("High", popped.Title)
			assert.equals(1, NotificationService.GetQueueSize("player1"))
		end)

		it("should return nil on empty queue", function()
			local result = NotificationService.PopNext("player1")
			assert.is_nil(result)
		end)

		it("should return nil for nil player", function()
			local result = NotificationService.PopNext(nil)
			assert.is_nil(result)
		end)

		it("should move popped notification to history", function()
			NotificationService.Send("player1", "Quest", "Test", "Test body")
			NotificationService.PopNext("player1")

			local history = NotificationService.GetHistory("player1")
			assert.equals(1, #history)
			assert.equals("Test", history[1].Title)
		end)
	end)

	-- ============ PeekNext ============

	describe("PeekNext", function()
		it("should not remove the notification from queue", function()
			NotificationService.Send("player1", "Quest", "Peek Test", "Body")

			local peeked = NotificationService.PeekNext("player1")
			assert.equals("Peek Test", peeked.Title)
			assert.equals(1, NotificationService.GetQueueSize("player1"))
		end)

		it("should return nil for nil player", function()
			assert.is_nil(NotificationService.PeekNext(nil))
		end)
	end)

	-- ============ GetQueueSize ============

	describe("GetQueueSize", function()
		it("should return 0 for new player", function()
			assert.equals(0, NotificationService.GetQueueSize("newPlayer"))
		end)

		it("should return 0 for nil player", function()
			assert.equals(0, NotificationService.GetQueueSize(nil))
		end)

		it("should track count accurately after sends and pops", function()
			NotificationService.Send("player1", "Quest", "A", "a")
			NotificationService.Send("player1", "Quest", "B", "b")
			assert.equals(2, NotificationService.GetQueueSize("player1"))

			NotificationService.PopNext("player1")
			assert.equals(1, NotificationService.GetQueueSize("player1"))
		end)
	end)

	-- ============ Broadcast ============

	describe("Broadcast", function()
		it("should send notification to multiple players", function()
			local count = NotificationService.Broadcast(
				{"p1", "p2", "p3"},
				"System",
				"Maintenance",
				"Server restart in 5 minutes"
			)
			assert.equals(3, count)
			assert.equals(1, NotificationService.GetQueueSize("p1"))
			assert.equals(1, NotificationService.GetQueueSize("p2"))
			assert.equals(1, NotificationService.GetQueueSize("p3"))
		end)

		it("should return 0 for non-table input", function()
			local count = NotificationService.Broadcast(nil, "System", "Title", "Body")
			assert.equals(0, count)
		end)

		it("should return 0 for empty player list", function()
			local count = NotificationService.Broadcast({}, "System", "Title", "Body")
			assert.equals(0, count)
		end)
	end)

	-- ============ History ============

	describe("GetHistory", function()
		it("should return empty array for new player", function()
			local history = NotificationService.GetHistory("newPlayer")
			assert.equals(0, #history)
		end)

		it("should return empty array for nil player", function()
			local history = NotificationService.GetHistory(nil)
			assert.equals(0, #history)
		end)

		it("should return history in most-recent-first order", function()
			clockTime = 100
			NotificationService.Send("player1", "Social", "First", "a")
			clockTime = 200
			NotificationService.Send("player1", "Social", "Second", "b")

			-- Pop both (they're same priority, so FIFO: First then Second)
			NotificationService.PopNext("player1")
			NotificationService.PopNext("player1")

			local history = NotificationService.GetHistory("player1")
			assert.equals(2, #history)
			-- Second was popped last, so it's most recent in history
			assert.equals("Second", history[1].Title)
			assert.equals("First", history[2].Title)
		end)

		it("should respect limit parameter", function()
			for i = 1, 5 do
				NotificationService.Send("player1", "Social", "N" .. i, "body")
			end
			for _ = 1, 5 do
				NotificationService.PopNext("player1")
			end

			local limited = NotificationService.GetHistory("player1", 3)
			assert.equals(3, #limited)
		end)

		it("should return a copy, not the internal array", function()
			NotificationService.Send("player1", "Quest", "Test", "body")
			NotificationService.PopNext("player1")

			local h1 = NotificationService.GetHistory("player1")
			local h2 = NotificationService.GetHistory("player1")
			assert.are_not.equal(h1, h2) -- Different table references
			assert.equals(h1[1].Title, h2[1].Title) -- Same content
		end)
	end)

	-- ============ MarkAsRead ============

	describe("MarkAsRead", function()
		it("should mark a queued notification as read", function()
			local notif = NotificationService.Send("player1", "Quest", "Test", "body")
			assert.is_false(notif.Read)

			local success = NotificationService.MarkAsRead("player1", notif.Id)
			assert.is_true(success)

			local peeked = NotificationService.PeekNext("player1")
			assert.is_true(peeked.Read)
		end)

		it("should mark a history notification as read", function()
			local notif = NotificationService.Send("player1", "Quest", "Test", "body")
			NotificationService.PopNext("player1")

			local success = NotificationService.MarkAsRead("player1", notif.Id)
			assert.is_true(success)

			local history = NotificationService.GetHistory("player1")
			assert.is_true(history[1].Read)
		end)

		it("should return false for non-existent ID", function()
			local success = NotificationService.MarkAsRead("player1", 999)
			assert.is_false(success)
		end)

		it("should return false for nil player or nil ID", function()
			assert.is_false(NotificationService.MarkAsRead(nil, 1))
			assert.is_false(NotificationService.MarkAsRead("player1", nil))
		end)
	end)

	-- ============ GetUnreadCount ============

	describe("GetUnreadCount", function()
		it("should count unread notifications across queue and history", function()
			NotificationService.Send("player1", "Quest", "A", "a")
			NotificationService.Send("player1", "Quest", "B", "b")
			assert.equals(2, NotificationService.GetUnreadCount("player1"))

			-- Pop one to history - still unread
			NotificationService.PopNext("player1")
			assert.equals(2, NotificationService.GetUnreadCount("player1"))

			-- Mark the history one as read
			local history = NotificationService.GetHistory("player1")
			NotificationService.MarkAsRead("player1", history[1].Id)
			assert.equals(1, NotificationService.GetUnreadCount("player1"))
		end)

		it("should return 0 for nil player", function()
			assert.equals(0, NotificationService.GetUnreadCount(nil))
		end)
	end)

	-- ============ ClearAll ============

	describe("ClearAll", function()
		it("should remove all notifications for a player", function()
			NotificationService.Send("player1", "Quest", "A", "a")
			NotificationService.Send("player1", "Quest", "B", "b")
			NotificationService.PopNext("player1")

			NotificationService.ClearAll("player1")
			assert.equals(0, NotificationService.GetQueueSize("player1"))
			assert.equals(0, #NotificationService.GetHistory("player1"))
		end)

		it("should not affect other players", function()
			NotificationService.Send("player1", "Quest", "P1", "a")
			NotificationService.Send("player2", "Quest", "P2", "b")

			NotificationService.ClearAll("player1")
			assert.equals(0, NotificationService.GetQueueSize("player1"))
			assert.equals(1, NotificationService.GetQueueSize("player2"))
		end)
	end)

	-- ============ PopAll ============

	describe("PopAll", function()
		it("should return all queued notifications in priority order", function()
			NotificationService.Send("player1", "Social", "Low", "low")
			NotificationService.Send("player1", "System", "High", "high")
			NotificationService.Send("player1", "Quest", "Mid", "mid")

			local all = NotificationService.PopAll("player1")
			assert.equals(3, #all)
			assert.equals("System", all[1].Category)
			assert.equals("Quest", all[2].Category)
			assert.equals("Social", all[3].Category)

			assert.equals(0, NotificationService.GetQueueSize("player1"))
			assert.equals(3, #NotificationService.GetHistory("player1"))
		end)

		it("should return empty array for nil player", function()
			local result = NotificationService.PopAll(nil)
			assert.equals(0, #result)
		end)

		it("should return empty array for player with no notifications", function()
			local result = NotificationService.PopAll("emptyPlayer")
			assert.equals(0, #result)
		end)
	end)

	-- ============ GetCategories ============

	describe("GetCategories", function()
		it("should return all category definitions", function()
			local cats = NotificationService.GetCategories()
			assert.is_not_nil(cats.Achievement)
			assert.is_not_nil(cats.Quest)
			assert.is_not_nil(cats.Trade)
			assert.is_not_nil(cats.Reputation)
			assert.is_not_nil(cats.Billing)
			assert.is_not_nil(cats.Social)
			assert.is_not_nil(cats.System)
			assert.is_not_nil(cats.Reward)
		end)

		it("should return a copy that cannot mutate internal state", function()
			local cats1 = NotificationService.GetCategories()
			cats1.Achievement.Priority = 999
			local cats2 = NotificationService.GetCategories()
			assert.equals(4, cats2.Achievement.Priority)
		end)
	end)

	-- ============ Queue Size Limit ============

	describe("Queue size limit", function()
		it("should cap the queue at 20 notifications", function()
			for i = 1, 25 do
				NotificationService.Send("player1", "Social", "N" .. i, "body " .. i)
			end
			assert.equals(20, NotificationService.GetQueueSize("player1"))
		end)
	end)

	-- ============ _SetClock ============

	describe("_SetClock", function()
		it("should use custom clock for timestamps", function()
			clockTime = 5000
			local notif = NotificationService.Send("player1", "Quest", "Timed", "body")
			assert.equals(5000, notif.Timestamp)
		end)
	end)
end)
