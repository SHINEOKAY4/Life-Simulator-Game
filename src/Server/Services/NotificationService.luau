-- NotificationService: centralized in-game notification system.
-- Queues, prioritizes, and dispatches player notifications from any service.
-- Works both in Roblox runtime and in Busted tests loaded via loadfile().

local function hasRobloxRuntime()
	if type(game) ~= "userdata" and type(game) ~= "table" then
		return false
	end
	return pcall(function()
		return game:GetService("Players")
	end)
end

local function clamp(value, minimum, maximum)
	if value < minimum then
		return minimum
	end
	if value > maximum then
		return maximum
	end
	return value
end

local IS_ROBLOX = hasRobloxRuntime()

-- Notification categories with default priorities and display durations (seconds)
local CATEGORIES = {
	Achievement = { Priority = 4, Duration = 8, Icon = "achievement" },
	Quest = { Priority = 3, Duration = 6, Icon = "quest" },
	Trade = { Priority = 3, Duration = 6, Icon = "trade" },
	Reputation = { Priority = 2, Duration = 5, Icon = "reputation" },
	Billing = { Priority = 3, Duration = 7, Icon = "billing" },
	Social = { Priority = 1, Duration = 5, Icon = "social" },
	System = { Priority = 5, Duration = 10, Icon = "system" },
	Reward = { Priority = 2, Duration = 5, Icon = "reward" },
}

local MAX_HISTORY = 50
local MAX_QUEUE_SIZE = 20

local NotificationService = {}

-- Internal state per player (keyed by playerId string)
local stateByPlayerId = {}

-- Configurable clock for tests
local clockFn = os.time

local function getTime()
	return clockFn()
end

local function ensurePlayerState(playerId)
	local key = tostring(playerId)
	local state = stateByPlayerId[key]
	if not state then
		state = {
			Queue = {},      -- pending notifications (sorted by priority desc, then time asc)
			History = {},    -- delivered notifications (most recent first)
			ReadIds = {},    -- set of notification IDs the player has marked as read
			NextId = 1,      -- monotonic notification ID counter
		}
		stateByPlayerId[key] = state
	end
	return state
end

local function generateId(state)
	local id = state.NextId
	state.NextId = id + 1
	return id
end

local function validateCategory(category)
	if type(category) ~= "string" then
		return nil
	end
	return CATEGORIES[category]
end

local function insertSorted(queue, notification)
	-- Higher priority first; within same priority, earlier timestamp first (FIFO)
	local inserted = false
	for i = 1, #queue do
		if notification.Priority > queue[i].Priority then
			table.insert(queue, i, notification)
			inserted = true
			break
		end
		if notification.Priority == queue[i].Priority and notification.Timestamp < queue[i].Timestamp then
			table.insert(queue, i, notification)
			inserted = true
			break
		end
	end
	if not inserted then
		table.insert(queue, notification)
	end

	-- Trim queue if it exceeds max size (drop lowest priority / oldest)
	while #queue > MAX_QUEUE_SIZE do
		table.remove(queue, #queue)
	end
end

local function addToHistory(state, notification)
	-- Most recent first
	table.insert(state.History, 1, notification)
	-- Trim history
	while #state.History > MAX_HISTORY do
		table.remove(state.History, #state.History)
	end
end

--[=[
	Send a notification to a specific player.

	@param playerId any -- Player identifier (UserId or test string)
	@param category string -- Notification category (must be a key of CATEGORIES)
	@param title string -- Short title text
	@param body string -- Longer description text
	@param metadata table? -- Optional extra data (source service, item IDs, etc.)
	@return table? -- The created notification, or nil on invalid input
	@return string? -- Error string on failure
]=]
function NotificationService.Send(playerId, category, title, body, metadata)
	if playerId == nil then
		return nil, "InvalidPlayer"
	end
	if type(title) ~= "string" or #title == 0 then
		return nil, "InvalidTitle"
	end
	if type(body) ~= "string" then
		return nil, "InvalidBody"
	end

	local catDef = validateCategory(category)
	if not catDef then
		return nil, "InvalidCategory"
	end

	local state = ensurePlayerState(playerId)
	local id = generateId(state)

	local notification = {
		Id = id,
		Category = category,
		Title = title,
		Body = body,
		Icon = catDef.Icon,
		Priority = catDef.Priority,
		Duration = catDef.Duration,
		Timestamp = getTime(),
		Read = false,
		Metadata = metadata or {},
	}

	insertSorted(state.Queue, notification)
	return notification, nil
end

--[=[
	Send a notification to multiple players at once.

	@param playerIds table -- Array of player identifiers
	@param category string -- Notification category
	@param title string -- Short title text
	@param body string -- Longer description text
	@param metadata table? -- Optional extra data
	@return number -- Count of successfully sent notifications
]=]
function NotificationService.Broadcast(playerIds, category, title, body, metadata)
	if type(playerIds) ~= "table" then
		return 0
	end

	local count = 0
	for _, playerId in ipairs(playerIds) do
		local notif, err = NotificationService.Send(playerId, category, title, body, metadata)
		if notif then
			count = count + 1
		end
	end
	return count
end

--[=[
	Pop the next (highest priority) notification from a player's queue.
	Moves it to history.

	@param playerId any -- Player identifier
	@return table? -- The notification, or nil if queue is empty
]=]
function NotificationService.PopNext(playerId)
	if playerId == nil then
		return nil
	end

	local state = ensurePlayerState(playerId)
	if #state.Queue == 0 then
		return nil
	end

	local notification = table.remove(state.Queue, 1)
	addToHistory(state, notification)
	return notification
end

--[=[
	Peek at the next notification without removing it.

	@param playerId any -- Player identifier
	@return table? -- The next notification, or nil
]=]
function NotificationService.PeekNext(playerId)
	if playerId == nil then
		return nil
	end

	local state = ensurePlayerState(playerId)
	if #state.Queue == 0 then
		return nil
	end

	return state.Queue[1]
end

--[=[
	Get the current queue size for a player.

	@param playerId any -- Player identifier
	@return number -- Number of pending notifications
]=]
function NotificationService.GetQueueSize(playerId)
	if playerId == nil then
		return 0
	end

	local state = ensurePlayerState(playerId)
	return #state.Queue
end

--[=[
	Get the notification history for a player.

	@param playerId any -- Player identifier
	@param limit number? -- Max entries to return (default: all)
	@return table -- Array of past notifications (most recent first)
]=]
function NotificationService.GetHistory(playerId, limit)
	if playerId == nil then
		return {}
	end

	local state = ensurePlayerState(playerId)
	if not limit or limit >= #state.History then
		-- Return a shallow copy
		local copy = {}
		for i, n in ipairs(state.History) do
			copy[i] = n
		end
		return copy
	end

	local result = {}
	local cap = clamp(limit, 0, #state.History)
	for i = 1, cap do
		result[i] = state.History[i]
	end
	return result
end

--[=[
	Mark a notification as read by its ID.

	@param playerId any -- Player identifier
	@param notificationId number -- The notification ID
	@return boolean -- True if the notification was found and marked
]=]
function NotificationService.MarkAsRead(playerId, notificationId)
	if playerId == nil or notificationId == nil then
		return false
	end

	local state = ensurePlayerState(playerId)

	-- Check queue
	for _, n in ipairs(state.Queue) do
		if n.Id == notificationId then
			n.Read = true
			state.ReadIds[notificationId] = true
			return true
		end
	end

	-- Check history
	for _, n in ipairs(state.History) do
		if n.Id == notificationId then
			n.Read = true
			state.ReadIds[notificationId] = true
			return true
		end
	end

	return false
end

--[=[
	Get the count of unread notifications (queue + history).

	@param playerId any -- Player identifier
	@return number -- Unread count
]=]
function NotificationService.GetUnreadCount(playerId)
	if playerId == nil then
		return 0
	end

	local state = ensurePlayerState(playerId)
	local count = 0

	for _, n in ipairs(state.Queue) do
		if not n.Read then
			count = count + 1
		end
	end

	for _, n in ipairs(state.History) do
		if not n.Read then
			count = count + 1
		end
	end

	return count
end

--[=[
	Clear all notifications (queue + history) for a player.

	@param playerId any -- Player identifier
]=]
function NotificationService.ClearAll(playerId)
	if playerId == nil then
		return
	end

	local key = tostring(playerId)
	stateByPlayerId[key] = nil
end

--[=[
	Get all available notification categories and their configuration.

	@return table -- Category definitions
]=]
function NotificationService.GetCategories()
	-- Return a copy to prevent external mutation
	local copy = {}
	for name, def in pairs(CATEGORIES) do
		copy[name] = {
			Priority = def.Priority,
			Duration = def.Duration,
			Icon = def.Icon,
		}
	end
	return copy
end

--[=[
	Pop all notifications from queue at once (e.g. for batch display).
	Moves all to history.

	@param playerId any -- Player identifier
	@return table -- Array of notifications in priority order
]=]
function NotificationService.PopAll(playerId)
	if playerId == nil then
		return {}
	end

	local state = ensurePlayerState(playerId)
	local result = {}

	while #state.Queue > 0 do
		local notification = table.remove(state.Queue, 1)
		addToHistory(state, notification)
		table.insert(result, notification)
	end

	return result
end

-- ============ Init (Roblox) ============

function NotificationService.Init()
	if not IS_ROBLOX then
		return
	end
	-- Roblox-specific packet registration would go here
end

-- ============ Test Hooks ============

function NotificationService._ResetForTests()
	stateByPlayerId = {}
end

function NotificationService._SetClock(fn)
	if type(fn) == "function" then
		clockFn = fn
	else
		clockFn = os.time
	end
end

return NotificationService
