--!strict
-- Tests/Specs/TradeSpec.lua
-- Unit tests for TradeService

local TradeService = assert(loadfile("src/Server/Services/TradeService.luau"))()

describe("TradeService", function()
	before_each(function()
		TradeService._ResetForTests()
		TradeService._SetClock(function() return 1000 end)
		TradeService._SetItemValidator(nil)
		TradeService._SetTransferExecutor(nil)
		TradeService._SetNotificationSink(nil)
	end)

	-- ============ RequestTrade ============

	describe("RequestTrade", function()
		it("should create a pending trade between two players", function()
			local tradeId, err = TradeService.RequestTrade(1, 2, {"itemA"}, {"itemB"})
			assert.is_not_nil(tradeId)
			assert.is_nil(err)

			local trade = TradeService.GetTrade(tradeId)
			assert.is_not_nil(trade)
			assert.equals("Pending", trade.status)
			assert.equals(1, trade.initiator.playerId)
			assert.equals(2, trade.recipient.playerId)
			assert.same({"itemA"}, trade.initiator.itemIds)
			assert.same({"itemB"}, trade.recipient.itemIds)
		end)

		it("should reject self-trade", function()
			local tradeId, err = TradeService.RequestTrade(1, 1, {"itemA"}, {"itemB"})
			assert.is_nil(tradeId)
			assert.equals("SelfTrade", err)
		end)

		it("should reject nil initiator", function()
			local tradeId, err = TradeService.RequestTrade(nil, 2, {"itemA"}, {})
			assert.is_nil(tradeId)
			assert.equals("InvalidPlayer", err)
		end)

		it("should reject nil recipient", function()
			local tradeId, err = TradeService.RequestTrade(1, nil, {"itemA"}, {})
			assert.is_nil(tradeId)
			assert.equals("InvalidPlayer", err)
		end)

		it("should reject non-table initiator items", function()
			local tradeId, err = TradeService.RequestTrade(1, 2, nil, {})
			assert.is_nil(tradeId)
			assert.equals("InvalidItems", err)
		end)

		it("should reject non-table recipient items", function()
			local tradeId, err = TradeService.RequestTrade(1, 2, {}, "not-table")
			assert.is_nil(tradeId)
			assert.equals("InvalidItems", err)
		end)

		it("should reject when both item lists are empty", function()
			local tradeId, err = TradeService.RequestTrade(1, 2, {}, {})
			assert.is_nil(tradeId)
			assert.equals("NoItems", err)
		end)

		it("should allow trade with only initiator items", function()
			local tradeId, err = TradeService.RequestTrade(1, 2, {"itemA"}, {})
			assert.is_not_nil(tradeId)
			assert.is_nil(err)
		end)

		it("should allow trade with only recipient items", function()
			local tradeId, err = TradeService.RequestTrade(1, 2, {}, {"itemB"})
			assert.is_not_nil(tradeId)
			assert.is_nil(err)
		end)

		it("should reject duplicate pending trade between same pair", function()
			local tradeId1, _ = TradeService.RequestTrade(1, 2, {"itemA"}, {"itemB"})
			assert.is_not_nil(tradeId1)

			local tradeId2, err = TradeService.RequestTrade(1, 2, {"itemC"}, {"itemD"})
			assert.is_nil(tradeId2)
			assert.equals("DuplicatePending", err)
		end)

		it("should fire TradeRequested signal", function()
			local firedInit, firedRecip, firedId
			TradeService.TradeRequested:Connect(function(initId, recipId, tradeId)
				firedInit = initId
				firedRecip = recipId
				firedId = tradeId
			end)

			local tradeId = TradeService.RequestTrade(10, 20, {"x"}, {"y"})
			assert.equals(10, firedInit)
			assert.equals(20, firedRecip)
			assert.equals(tradeId, firedId)
		end)

		it("should notify recipient when trade is requested", function()
			local sent = {}
			TradeService._SetNotificationSink(function(playerId, title, body, metadata)
				table.insert(sent, {
					playerId = playerId,
					title = title,
					body = body,
					metadata = metadata,
				})
			end)

			local tradeId = TradeService.RequestTrade(10, 20, {"x"}, {"y"})
			assert.equals(1, #sent)
			assert.equals(20, sent[1].playerId)
			assert.equals("New Trade Offer", sent[1].title)
			assert.equals(tradeId, sent[1].metadata.TradeId)
			assert.equals("Requested", sent[1].metadata.Event)
		end)

		it("should reject when item validator fails", function()
			TradeService._SetItemValidator(function(playerId, itemIds)
				if playerId == 1 then
					return false, "Item not found"
				end
				return true, nil
			end)

			local tradeId, err = TradeService.RequestTrade(1, 2, {"badItem"}, {"goodItem"})
			assert.is_nil(tradeId)
			assert.equals("ItemValidationFailed", err)
		end)
	end)

	-- ============ AcceptTrade ============

	describe("AcceptTrade", function()
		it("should complete a valid trade", function()
			local tradeId = TradeService.RequestTrade(1, 2, {"itemA"}, {"itemB"})
			local ok, err = TradeService.AcceptTrade(tradeId, 2)
			assert.is_true(ok)
			assert.is_nil(err)

			local trade = TradeService.GetTrade(tradeId)
			assert.equals("Completed", trade.status)
			assert.is_not_nil(trade.resolvedAt)
		end)

		it("should reject accept by non-recipient", function()
			local tradeId = TradeService.RequestTrade(1, 2, {"itemA"}, {"itemB"})
			local ok, err = TradeService.AcceptTrade(tradeId, 1)
			assert.is_false(ok)
			assert.equals("NotParticipant", err)
		end)

		it("should reject accept on non-existent trade", function()
			local ok, err = TradeService.AcceptTrade("nonexistent", 2)
			assert.is_false(ok)
			assert.equals("TradeNotFound", err)
		end)

		it("should reject double accept", function()
			local tradeId = TradeService.RequestTrade(1, 2, {"itemA"}, {"itemB"})
			TradeService.AcceptTrade(tradeId, 2)
			local ok, err = TradeService.AcceptTrade(tradeId, 2)
			assert.is_false(ok)
			assert.equals("AlreadyResolved", err)
		end)

		it("should fire TradeAccepted and TradeCompleted signals", function()
			local acceptedFired = false
			local completedFired = false
			TradeService.TradeAccepted:Connect(function()
				acceptedFired = true
			end)
			TradeService.TradeCompleted:Connect(function()
				completedFired = true
			end)

			local tradeId = TradeService.RequestTrade(1, 2, {"itemA"}, {"itemB"})
			TradeService.AcceptTrade(tradeId, 2)
			assert.is_true(acceptedFired)
			assert.is_true(completedFired)
		end)

		it("should notify both players when trade completes", function()
			local sent = {}
			TradeService._SetNotificationSink(function(playerId, title, body, metadata)
				table.insert(sent, {
					playerId = playerId,
					title = title,
					body = body,
					metadata = metadata,
				})
			end)

			local tradeId = TradeService.RequestTrade(1, 2, {"itemA"}, {"itemB"})
			TradeService.AcceptTrade(tradeId, 2)

			assert.equals(3, #sent) -- request + completion to each side
			assert.equals(1, sent[2].playerId)
			assert.equals(2, sent[3].playerId)
			assert.equals("Trade Completed", sent[2].title)
			assert.equals("Trade Completed", sent[3].title)
			assert.equals("Completed", sent[2].metadata.Event)
			assert.equals("Completed", sent[3].metadata.Event)
		end)

		it("should call transfer executor on accept", function()
			local transfers = {}
			TradeService._SetTransferExecutor(function(fromId, toId, itemIds)
				table.insert(transfers, {from = fromId, to = toId, items = itemIds})
				return true, nil
			end)

			local tradeId = TradeService.RequestTrade(1, 2, {"itemA", "itemB"}, {"itemC"})
			TradeService.AcceptTrade(tradeId, 2)

			assert.equals(2, #transfers)
			-- First transfer: initiator -> recipient
			assert.equals(1, transfers[1].from)
			assert.equals(2, transfers[1].to)
			assert.same({"itemA", "itemB"}, transfers[1].items)
			-- Second transfer: recipient -> initiator
			assert.equals(2, transfers[2].from)
			assert.equals(1, transfers[2].to)
			assert.same({"itemC"}, transfers[2].items)
		end)

		it("should fail and rollback if second transfer fails", function()
			local callCount = 0
			TradeService._SetTransferExecutor(function(fromId, toId, itemIds)
				callCount = callCount + 1
				if callCount == 2 then
					return false, "Inventory full"
				end
				return true, nil
			end)

			local tradeId = TradeService.RequestTrade(1, 2, {"itemA"}, {"itemB"})
			local ok, err = TradeService.AcceptTrade(tradeId, 2)
			assert.is_false(ok)
			assert.equals("InventoryFull", err)
			-- 3 calls: first transfer, second (failed), rollback
			assert.equals(3, callCount)
		end)

		it("should reject accept on expired trade", function()
			TradeService._SetExpirySeconds(10)
			local currentTime = 1000
			TradeService._SetClock(function() return currentTime end)

			local tradeId = TradeService.RequestTrade(1, 2, {"itemA"}, {"itemB"})

			-- Advance time past expiry
			currentTime = 1020
			local ok, err = TradeService.AcceptTrade(tradeId, 2)
			assert.is_false(ok)
			assert.equals("AlreadyResolved", err)

			local trade = TradeService.GetTrade(tradeId)
			assert.equals("Expired", trade.status)
		end)

		it("should re-validate initiator items at accept time", function()
			local tradeId = TradeService.RequestTrade(1, 2, {"itemA"}, {"itemB"})

			-- Now set validator to reject initiator items
			TradeService._SetItemValidator(function(playerId, itemIds)
				if playerId == 1 then
					return false, "Item consumed"
				end
				return true, nil
			end)

			local ok, err = TradeService.AcceptTrade(tradeId, 2)
			assert.is_false(ok)
			assert.equals("ItemValidationFailed", err)
		end)
	end)

	-- ============ DeclineTrade ============

	describe("DeclineTrade", function()
		it("should decline a pending trade", function()
			local tradeId = TradeService.RequestTrade(1, 2, {"itemA"}, {"itemB"})
			local ok, err = TradeService.DeclineTrade(tradeId, 2)
			assert.is_true(ok)
			assert.is_nil(err)

			local trade = TradeService.GetTrade(tradeId)
			assert.equals("Declined", trade.status)
		end)

		it("should reject decline by non-recipient", function()
			local tradeId = TradeService.RequestTrade(1, 2, {"itemA"}, {"itemB"})
			local ok, err = TradeService.DeclineTrade(tradeId, 1)
			assert.is_false(ok)
			assert.equals("NotParticipant", err)
		end)

		it("should reject decline on already resolved trade", function()
			local tradeId = TradeService.RequestTrade(1, 2, {"itemA"}, {"itemB"})
			TradeService.DeclineTrade(tradeId, 2)
			local ok, err = TradeService.DeclineTrade(tradeId, 2)
			assert.is_false(ok)
			assert.equals("AlreadyResolved", err)
		end)

		it("should fire TradeDeclined signal", function()
			local declinedFired = false
			TradeService.TradeDeclined:Connect(function()
				declinedFired = true
			end)

			local tradeId = TradeService.RequestTrade(1, 2, {"itemA"}, {"itemB"})
			TradeService.DeclineTrade(tradeId, 2)
			assert.is_true(declinedFired)
		end)

		it("should notify initiator when trade is declined", function()
			local sent = {}
			TradeService._SetNotificationSink(function(playerId, title, body, metadata)
				table.insert(sent, {
					playerId = playerId,
					title = title,
					body = body,
					metadata = metadata,
				})
			end)

			local tradeId = TradeService.RequestTrade(1, 2, {"itemA"}, {"itemB"})
			TradeService.DeclineTrade(tradeId, 2)

			assert.equals(2, #sent) -- request + decline
			assert.equals(1, sent[2].playerId)
			assert.equals("Trade Declined", sent[2].title)
			assert.equals("Declined", sent[2].metadata.Event)
			assert.equals(tradeId, sent[2].metadata.TradeId)
		end)
	end)

	-- ============ CancelTrade ============

	describe("CancelTrade", function()
		it("should cancel a pending trade by initiator", function()
			local tradeId = TradeService.RequestTrade(1, 2, {"itemA"}, {"itemB"})
			local ok, err = TradeService.CancelTrade(tradeId, 1)
			assert.is_true(ok)
			assert.is_nil(err)

			local trade = TradeService.GetTrade(tradeId)
			assert.equals("Cancelled", trade.status)
		end)

		it("should reject cancel by non-initiator", function()
			local tradeId = TradeService.RequestTrade(1, 2, {"itemA"}, {"itemB"})
			local ok, err = TradeService.CancelTrade(tradeId, 2)
			assert.is_false(ok)
			assert.equals("NotParticipant", err)
		end)

		it("should fire TradeCancelled signal", function()
			local cancelledFired = false
			TradeService.TradeCancelled:Connect(function()
				cancelledFired = true
			end)

			local tradeId = TradeService.RequestTrade(1, 2, {"itemA"}, {"itemB"})
			TradeService.CancelTrade(tradeId, 1)
			assert.is_true(cancelledFired)
		end)

		it("should notify recipient when trade is cancelled", function()
			local sent = {}
			TradeService._SetNotificationSink(function(playerId, title, body, metadata)
				table.insert(sent, {
					playerId = playerId,
					title = title,
					body = body,
					metadata = metadata,
				})
			end)

			local tradeId = TradeService.RequestTrade(1, 2, {"itemA"}, {"itemB"})
			TradeService.CancelTrade(tradeId, 1)

			assert.equals(2, #sent) -- request + cancel
			assert.equals(2, sent[2].playerId)
			assert.equals("Trade Cancelled", sent[2].title)
			assert.equals("Cancelled", sent[2].metadata.Event)
			assert.equals(tradeId, sent[2].metadata.TradeId)
		end)
	end)

	-- ============ GetPendingTradesForPlayer ============

	describe("GetPendingTradesForPlayer", function()
		it("should return pending incoming trades for a player", function()
			TradeService.RequestTrade(1, 2, {"a"}, {"b"})
			TradeService.RequestTrade(3, 2, {"c"}, {"d"})

			local pending = TradeService.GetPendingTradesForPlayer(2)
			assert.equals(2, #pending)
		end)

		it("should not return resolved trades", function()
			local tradeId = TradeService.RequestTrade(1, 2, {"a"}, {"b"})
			TradeService.DeclineTrade(tradeId, 2)

			local pending = TradeService.GetPendingTradesForPlayer(2)
			assert.equals(0, #pending)
		end)

		it("should not return expired trades", function()
			TradeService._SetExpirySeconds(10)
			local currentTime = 1000
			TradeService._SetClock(function() return currentTime end)

			TradeService.RequestTrade(1, 2, {"a"}, {"b"})
			currentTime = 1020

			local pending = TradeService.GetPendingTradesForPlayer(2)
			assert.equals(0, #pending)
		end)

		it("should return empty for player with no trades", function()
			local pending = TradeService.GetPendingTradesForPlayer(99)
			assert.equals(0, #pending)
		end)
	end)

	-- ============ GetOutgoingTrades ============

	describe("GetOutgoingTrades", function()
		it("should return outgoing pending trades", function()
			TradeService.RequestTrade(1, 2, {"a"}, {"b"})
			TradeService.RequestTrade(1, 3, {"c"}, {"d"})

			local outgoing = TradeService.GetOutgoingTrades(1)
			assert.equals(2, #outgoing)
		end)

		it("should not include completed trades", function()
			local tradeId = TradeService.RequestTrade(1, 2, {"a"}, {"b"})
			TradeService.AcceptTrade(tradeId, 2)

			local outgoing = TradeService.GetOutgoingTrades(1)
			assert.equals(0, #outgoing)
		end)
	end)

	-- ============ Allow new trade after previous resolved ============

	describe("Trade lifecycle", function()
		it("should allow new trade after previous was declined", function()
			local tradeId1 = TradeService.RequestTrade(1, 2, {"a"}, {"b"})
			TradeService.DeclineTrade(tradeId1, 2)

			local tradeId2, err = TradeService.RequestTrade(1, 2, {"c"}, {"d"})
			assert.is_not_nil(tradeId2)
			assert.is_nil(err)
		end)

		it("should allow new trade after previous was cancelled", function()
			local tradeId1 = TradeService.RequestTrade(1, 2, {"a"}, {"b"})
			TradeService.CancelTrade(tradeId1, 1)

			local tradeId2, err = TradeService.RequestTrade(1, 2, {"c"}, {"d"})
			assert.is_not_nil(tradeId2)
			assert.is_nil(err)
		end)

		it("should allow new trade after previous was completed", function()
			local tradeId1 = TradeService.RequestTrade(1, 2, {"a"}, {"b"})
			TradeService.AcceptTrade(tradeId1, 2)

			local tradeId2, err = TradeService.RequestTrade(1, 2, {"c"}, {"d"})
			assert.is_not_nil(tradeId2)
			assert.is_nil(err)
		end)
	end)
end)
