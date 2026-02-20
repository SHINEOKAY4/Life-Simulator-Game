-- TradeService: cross-player inventory trading with validation.
-- Uses the same dual-environment loader pattern as FriendService so tests
-- can run standalone under Busted without Roblox engine stubs.
--
-- NOTE: Luau type annotations are intentionally omitted so this file
-- can be loaded via plain loadfile() in the Busted test runner.

--==============================[ Environment ]==============================

local function ensureTaskSpawn()
	local function spawnImpl(executable, ...)
		if type(executable) == "thread" then
			local ok, err = coroutine.resume(executable, ...)
			if not ok then
				error(err, 0)
			end
			return executable
		end

		local thread = coroutine.create(executable)
		local ok, err = coroutine.resume(thread, ...)
		if not ok then
			error(err, 0)
		end
		return thread
	end

	if type(task) ~= "table" then
		_G.task = {
			spawn = spawnImpl,
		}
		return
	end

	if type(task.spawn) ~= "function" then
		task.spawn = spawnImpl
	end
end

local function loadGoodSignal()
	local ok, signalModule

	if type(game) == "userdata" or type(game) == "table" then
		ok, signalModule = pcall(function()
			local replicatedStorage = game:GetService("ReplicatedStorage")
			return require(replicatedStorage.Packages.GoodSignal)
		end)
		if ok and signalModule then
			return signalModule
		end
	end

	ensureTaskSpawn()
	ok, signalModule = pcall(function()
		return assert(loadfile("Packages/GoodSignal/init.luau"))()
	end)
	if ok and signalModule then
		return signalModule
	end

	error("TradeService failed to load GoodSignal")
end

local GoodSignal = loadGoodSignal()

--==============================[ Types ]==============================
-- TradeStatus: "Pending" | "Accepted" | "Declined" | "Cancelled" | "Completed" | "Expired"
-- ErrCode: "InvalidPlayer" | "SelfTrade" | "NoItems" | "TradeNotFound"
--          | "NotParticipant" | "AlreadyResolved" | "ItemValidationFailed"
--          | "InventoryFull" | "DuplicatePending"
--
-- TradeOffer = { playerId, itemIds = { string } }
-- TradeRequest = { tradeId, initiator: TradeOffer, recipient: TradeOffer,
--                  status: TradeStatus, createdAt: number, resolvedAt: number? }

--==============================[ Module ]==============================

local TradeService = {
	TradeRequested = GoodSignal.new(),
	TradeAccepted = GoodSignal.new(),
	TradeDeclined = GoodSignal.new(),
	TradeCancelled = GoodSignal.new(),
	TradeCompleted = GoodSignal.new(),
}

-- Internal state
local tradeCounter = 0
local trades = {}

-- Pending trade index: recipientId -> { tradeId -> true }
local pendingByRecipient = {}

-- Pending trade index: initiatorId -> { tradeId -> true }
local pendingByInitiator = {}

-- Trade expiry in seconds (default 120s)
local TRADE_EXPIRY_SECONDS = 120

-- Pluggable clock for testing
local clockFn = nil

local function now()
	if clockFn then
		return clockFn()
	end
	if type(workspace) == "userdata" then
		return workspace:GetServerTimeNow()
	end
	return os.time()
end

-- Pluggable item validator: (playerId, itemIds) -> boolean, errMsg?
-- In production this checks the real inventory; tests can override.
local itemValidator = nil

local function validateItems(playerId, itemIds)
	if itemValidator then
		return itemValidator(playerId, itemIds)
	end
	-- Default: accept any non-empty list
	if #itemIds == 0 then
		return false, "No items offered"
	end
	return true, nil
end

-- Pluggable transfer executor: (fromId, toId, itemIds) -> boolean, errMsg?
local transferExecutor = nil

local function executeTransfer(fromId, toId, itemIds)
	if transferExecutor then
		return transferExecutor(fromId, toId, itemIds)
	end
	return true, nil
end

local function newTradeId()
	tradeCounter = tradeCounter + 1
	return "trade_" .. tostring(tradeCounter)
end

local function isValidId(id)
	return id ~= nil
end

local function addPendingIndex(map, key, tradeId)
	if not map[key] then
		map[key] = {}
	end
	map[key][tradeId] = true
end

local function removePendingIndex(map, key, tradeId)
	if map[key] then
		map[key][tradeId] = nil
		if next(map[key]) == nil then
			map[key] = nil
		end
	end
end

local function cleanupPending(trade)
	removePendingIndex(pendingByRecipient, trade.recipient.playerId, trade.tradeId)
	removePendingIndex(pendingByInitiator, trade.initiator.playerId, trade.tradeId)
end

local function isExpired(trade)
	return trade.status == "Pending" and (now() - trade.createdAt) > TRADE_EXPIRY_SECONDS
end

--==============================[ API ]==============================

--- Create a new trade request from initiator to recipient.
--- Both sides declare the items they want to trade.
function TradeService.RequestTrade(initiatorId, recipientId, initiatorItemIds, recipientItemIds)
	if not isValidId(initiatorId) then
		return nil, "InvalidPlayer"
	end
	if not isValidId(recipientId) then
		return nil, "InvalidPlayer"
	end
	if initiatorId == recipientId then
		return nil, "SelfTrade"
	end
	if #initiatorItemIds == 0 and #recipientItemIds == 0 then
		return nil, "NoItems"
	end

	-- Check for duplicate pending trade between same pair
	local existingPending = pendingByInitiator[initiatorId]
	if existingPending then
		for tradeId, _ in pairs(existingPending) do
			local t = trades[tradeId]
			if t and t.status == "Pending" and t.recipient.playerId == recipientId then
				if not isExpired(t) then
					return nil, "DuplicatePending"
				end
			end
		end
	end

	-- Validate initiator items
	if #initiatorItemIds > 0 then
		local ok, err = validateItems(initiatorId, initiatorItemIds)
		if not ok then
			return nil, "ItemValidationFailed"
		end
	end

	local tradeId = newTradeId()
	local trade = {
		tradeId = tradeId,
		initiator = {
			playerId = initiatorId,
			itemIds = {unpack(initiatorItemIds)},
		},
		recipient = {
			playerId = recipientId,
			itemIds = {unpack(recipientItemIds)},
		},
		status = "Pending",
		createdAt = now(),
		resolvedAt = nil,
	}

	trades[tradeId] = trade
	addPendingIndex(pendingByRecipient, recipientId, tradeId)
	addPendingIndex(pendingByInitiator, initiatorId, tradeId)

	TradeService.TradeRequested:Fire(initiatorId, recipientId, tradeId)
	return tradeId, nil
end

--- Accept a pending trade. Validates both sides then executes item transfers.
function TradeService.AcceptTrade(tradeId, acceptingPlayerId)
	local trade = trades[tradeId]
	if not trade then
		return false, "TradeNotFound"
	end
	if trade.recipient.playerId ~= acceptingPlayerId then
		return false, "NotParticipant"
	end
	if trade.status ~= "Pending" then
		return false, "AlreadyResolved"
	end
	if isExpired(trade) then
		trade.status = "Expired"
		trade.resolvedAt = now()
		cleanupPending(trade)
		return false, "AlreadyResolved"
	end

	-- Validate recipient items at accept time
	if #trade.recipient.itemIds > 0 then
		local ok, err = validateItems(trade.recipient.playerId, trade.recipient.itemIds)
		if not ok then
			return false, "ItemValidationFailed"
		end
	end

	-- Re-validate initiator items (may have been consumed since request)
	if #trade.initiator.itemIds > 0 then
		local ok, err = validateItems(trade.initiator.playerId, trade.initiator.itemIds)
		if not ok then
			return false, "ItemValidationFailed"
		end
	end

	-- Execute transfers: initiator items -> recipient
	if #trade.initiator.itemIds > 0 then
		local ok, err = executeTransfer(
			trade.initiator.playerId,
			trade.recipient.playerId,
			trade.initiator.itemIds
		)
		if not ok then
			return false, "InventoryFull"
		end
	end

	-- Execute transfers: recipient items -> initiator
	if #trade.recipient.itemIds > 0 then
		local ok, err = executeTransfer(
			trade.recipient.playerId,
			trade.initiator.playerId,
			trade.recipient.itemIds
		)
		if not ok then
			-- Rollback first transfer
			if #trade.initiator.itemIds > 0 then
				executeTransfer(
					trade.recipient.playerId,
					trade.initiator.playerId,
					trade.initiator.itemIds
				)
			end
			return false, "InventoryFull"
		end
	end

	trade.status = "Completed"
	trade.resolvedAt = now()
	cleanupPending(trade)

	TradeService.TradeAccepted:Fire(trade.initiator.playerId, trade.recipient.playerId, tradeId)
	TradeService.TradeCompleted:Fire(trade.initiator.playerId, trade.recipient.playerId, tradeId)
	return true, nil
end

--- Decline a pending trade.
function TradeService.DeclineTrade(tradeId, decliningPlayerId)
	local trade = trades[tradeId]
	if not trade then
		return false, "TradeNotFound"
	end
	if trade.recipient.playerId ~= decliningPlayerId then
		return false, "NotParticipant"
	end
	if trade.status ~= "Pending" then
		return false, "AlreadyResolved"
	end

	trade.status = "Declined"
	trade.resolvedAt = now()
	cleanupPending(trade)

	TradeService.TradeDeclined:Fire(trade.initiator.playerId, trade.recipient.playerId, tradeId)
	return true, nil
end

--- Cancel a pending trade (only the initiator can cancel).
function TradeService.CancelTrade(tradeId, cancellingPlayerId)
	local trade = trades[tradeId]
	if not trade then
		return false, "TradeNotFound"
	end
	if trade.initiator.playerId ~= cancellingPlayerId then
		return false, "NotParticipant"
	end
	if trade.status ~= "Pending" then
		return false, "AlreadyResolved"
	end

	trade.status = "Cancelled"
	trade.resolvedAt = now()
	cleanupPending(trade)

	TradeService.TradeCancelled:Fire(trade.initiator.playerId, trade.recipient.playerId, tradeId)
	return true, nil
end

--- Get a trade by id.
function TradeService.GetTrade(tradeId)
	return trades[tradeId]
end

--- Get all pending trades where playerId is the recipient.
function TradeService.GetPendingTradesForPlayer(playerId)
	local out = {}
	local pending = pendingByRecipient[playerId]
	if not pending then
		return out
	end
	for tradeId, _ in pairs(pending) do
		local t = trades[tradeId]
		if t and t.status == "Pending" and not isExpired(t) then
			table.insert(out, t)
		end
	end
	return out
end

--- Get all pending trades initiated by playerId.
function TradeService.GetOutgoingTrades(playerId)
	local out = {}
	local pending = pendingByInitiator[playerId]
	if not pending then
		return out
	end
	for tradeId, _ in pairs(pending) do
		local t = trades[tradeId]
		if t and t.status == "Pending" and not isExpired(t) then
			table.insert(out, t)
		end
	end
	return out
end

--==============================[ Test Hooks ]==============================

--- Roblox server Init: register packet handlers.
--- Only called from Main.server.luau; tests never call this.
function TradeService.Init()
	-- Guard: only initialise when running inside the Roblox engine.
	if type(game) ~= "userdata" then
		return
	end

	local Players = game:GetService("Players")
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local TradePackets = require(ReplicatedStorage.Network.TradePackets)

	-- Helper to serialise a trade for the client
	local function serialiseTrade(trade, forRecipient)
		local initiatorPlayer = Players:GetPlayerByUserId(trade.initiator.playerId)
		local recipientPlayer = Players:GetPlayerByUserId(trade.recipient.playerId)
		return {
			TradeId = trade.tradeId,
			InitiatorUserId = trade.initiator.playerId,
			InitiatorName = initiatorPlayer and initiatorPlayer.Name or ("Player " .. tostring(trade.initiator.playerId)),
			RecipientUserId = trade.recipient.playerId,
			RecipientName = recipientPlayer and recipientPlayer.Name or ("Player " .. tostring(trade.recipient.playerId)),
			InitiatorItems = trade.initiator.itemIds,
			RequestedItems = trade.recipient.itemIds,
			Status = trade.status,
			CreatedAt = trade.createdAt,
		}
	end

	-- GetTradeData: return incoming + outgoing trades for the requesting player
	TradePackets.GetTradeData.OnServerInvoke = function(player)
		local incoming = TradeService.GetPendingTradesForPlayer(player.UserId)
		local outgoing = TradeService.GetOutgoingTrades(player.UserId)

		local incomingPayload = {}
		for _, trade in ipairs(incoming) do
			table.insert(incomingPayload, serialiseTrade(trade, true))
		end

		local outgoingPayload = {}
		for _, trade in ipairs(outgoing) do
			table.insert(outgoingPayload, serialiseTrade(trade, false))
		end

		return true, "", {
			Incoming = incomingPayload,
			Outgoing = outgoingPayload,
		}
	end

	-- RequestTrade
	TradePackets.RequestTrade.OnServerInvoke = function(player, recipientUserId, initiatorItemIds, recipientItemIds)
		if typeof(recipientUserId) ~= "number" then
			return false, "Invalid recipient.", nil
		end
		local initItems = type(initiatorItemIds) == "table" and initiatorItemIds or {}
		local recipItems = type(recipientItemIds) == "table" and recipientItemIds or {}

		local tradeId, err = TradeService.RequestTrade(
			player.UserId,
			recipientUserId,
			initItems,
			recipItems
		)
		if not tradeId then
			return false, err or "Trade request failed.", nil
		end

		-- Notify recipient
		local recipientPlayer = Players:GetPlayerByUserId(recipientUserId)
		if recipientPlayer then
			TradePackets.TradeIncoming:FireClient(recipientPlayer, {
				TradeId = tradeId,
				InitiatorName = player.Name,
				InitiatorUserId = player.UserId,
				InitiatorItems = initItems,
				RequestedItems = recipItems,
			})
		end

		return true, "Trade request sent.", { TradeId = tradeId }
	end

	-- AcceptTrade
	TradePackets.AcceptTrade.OnServerInvoke = function(player, tradeId)
		if typeof(tradeId) ~= "string" or tradeId == "" then
			return false, "Invalid trade id."
		end
		local ok, err = TradeService.AcceptTrade(tradeId, player.UserId)
		if not ok then
			return false, err or "Accept failed."
		end

		-- Notify initiator
		local trade = TradeService.GetTrade(tradeId)
		if trade then
			local initiator = Players:GetPlayerByUserId(trade.initiator.playerId)
			if initiator then
				TradePackets.TradeResolved:FireClient(initiator, {
					TradeId = tradeId,
					Status = "Completed",
					Message = player.Name .. " accepted your trade!",
				})
			end
		end

		return true, "Trade completed!"
	end

	-- DeclineTrade
	TradePackets.DeclineTrade.OnServerInvoke = function(player, tradeId)
		if typeof(tradeId) ~= "string" or tradeId == "" then
			return false, "Invalid trade id."
		end
		local ok, err = TradeService.DeclineTrade(tradeId, player.UserId)
		if not ok then
			return false, err or "Decline failed."
		end

		local trade = TradeService.GetTrade(tradeId)
		if trade then
			local initiator = Players:GetPlayerByUserId(trade.initiator.playerId)
			if initiator then
				TradePackets.TradeResolved:FireClient(initiator, {
					TradeId = tradeId,
					Status = "Declined",
					Message = player.Name .. " declined your trade.",
				})
			end
		end

		return true, "Trade declined."
	end

	-- CancelTrade
	TradePackets.CancelTrade.OnServerInvoke = function(player, tradeId)
		if typeof(tradeId) ~= "string" or tradeId == "" then
			return false, "Invalid trade id."
		end
		local ok, err = TradeService.CancelTrade(tradeId, player.UserId)
		if not ok then
			return false, err or "Cancel failed."
		end

		local trade = TradeService.GetTrade(tradeId)
		if trade then
			local recipient = Players:GetPlayerByUserId(trade.recipient.playerId)
			if recipient then
				TradePackets.TradeResolved:FireClient(recipient, {
					TradeId = tradeId,
					Status = "Cancelled",
					Message = "Trade was cancelled.",
				})
			end
		end

		return true, "Trade cancelled."
	end

	-- Cleanup on player leaving
	Players.PlayerRemoving:Connect(function(player)
		-- Cancel all outgoing pending trades for this player
		local outgoing = TradeService.GetOutgoingTrades(player.UserId)
		for _, trade in ipairs(outgoing) do
			TradeService.CancelTrade(trade.tradeId, player.UserId)
		end
		-- Decline all incoming pending trades for this player
		local incoming = TradeService.GetPendingTradesForPlayer(player.UserId)
		for _, trade in ipairs(incoming) do
			TradeService.DeclineTrade(trade.tradeId, player.UserId)
		end
	end)
end

--- Reset all state (for testing only).
function TradeService._ResetForTests()
	tradeCounter = 0
	trades = {}
	pendingByRecipient = {}
	pendingByInitiator = {}

	TradeService.TradeRequested:DisconnectAll()
	TradeService.TradeAccepted:DisconnectAll()
	TradeService.TradeDeclined:DisconnectAll()
	TradeService.TradeCancelled:DisconnectAll()
	TradeService.TradeCompleted:DisconnectAll()

	TradeService.TradeRequested = GoodSignal.new()
	TradeService.TradeAccepted = GoodSignal.new()
	TradeService.TradeDeclined = GoodSignal.new()
	TradeService.TradeCancelled = GoodSignal.new()
	TradeService.TradeCompleted = GoodSignal.new()

	clockFn = nil
	itemValidator = nil
	transferExecutor = nil
end

--- Override the clock function (for testing).
function TradeService._SetClock(fn)
	clockFn = fn
end

--- Override the item validator (for testing).
function TradeService._SetItemValidator(fn)
	itemValidator = fn
end

--- Override the transfer executor (for testing).
function TradeService._SetTransferExecutor(fn)
	transferExecutor = fn
end

--- Set the trade expiry duration in seconds (for testing).
function TradeService._SetExpirySeconds(seconds)
	TRADE_EXPIRY_SECONDS = seconds
end

return TradeService
