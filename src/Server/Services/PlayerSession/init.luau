--!strict

local ServerStorage = game:GetService("ServerStorage")
local Players = game:GetService("Players")

local DataStore = require(ServerStorage.ServerPackages.DataStore)
local Profile = require(script.Profile)
local Debug = require(script.Debug)
local Config = require(script.Configuration)

type DataStoreObject = DataStore.DataStore

local STORE_NAME = Config.STORE_NAME
local SCOPE = Config.SCOPE
local RETRY_TIMEOUT = Config.TIMEOUT
local DEBUG_ENABLED = Config.DEBUG

local function StateChanged(_state, dataStore)
	-- Continually attempt to open until ready (stops if State becomes nil)
	while dataStore.State == false do
		if dataStore:Open(Profile) ~= DataStore.Response.Success then
			task.wait(4)
		end
	end
end

local function StoreAwait(player: Player): DataStoreObject?
	local start = os.clock()
	local key = tostring(player.UserId)

	-- Try to find the player's open DataStore (returns nil if not created/open yet)
	local dataStore: DataStoreObject? = DataStore.find(STORE_NAME, SCOPE, key)

	-- Wait until the DataStore object exists in memory
	while not dataStore do
		-- Player left, or timed out → bail
		if not player.Parent or (os.clock() - start) >= RETRY_TIMEOUT then
			return nil
		end
		task.wait(0.1) -- Small poll delay; no event for store creation
		dataStore = DataStore.find(STORE_NAME, SCOPE, key)
	end

	assert(dataStore ~= nil, "DataStore object unexpectedly nil after wait loop in StoreAwait")

	-- Wait until the store is fully open (State == true means ready to use)
	while dataStore.State ~= true do
		-- Store destroyed → exit
		if dataStore.State == nil then
			return nil
		end
		-- Player left → exit
		if not player.Parent then
			return nil
		end
		-- Wait for next state change (pcall guards if the signal is gone)
		local ok = pcall(function()
			dataStore.StateChanged:Wait()
		end)
		if not ok then
			return nil
		end
	end

	return dataStore
end

local function OnPlayerAdded(player: Player)
	local key = tostring(player.UserId)

	local dataStore = DataStore.new(STORE_NAME, SCOPE, key)
	dataStore.Player = player -- Useful to pass to other modules; avoids extra PlayerAdded hooks
	dataStore.StateChanged:Connect(StateChanged)

	if DEBUG_ENABLED then
		Debug.Enabled(dataStore, Config.DEBUGOPTIONS)
	end

	-- Kick off initial open
	StateChanged(dataStore.State, dataStore)
end

local function OnPlayerRemoving(player: Player)
	local key = tostring(player.UserId)
	local dataStore = DataStore.find(STORE_NAME, SCOPE, key)
	if dataStore ~= nil then
		dataStore:Destroy()
	end
end

local PlayerSession = {}

--[=[
	Await the player’s data to be loaded.

	Blocks until the underlying DataStore for `player` is created and opened, or
	until the player leaves / timeout occurs. If `category` is provided, returns
	only that slice; otherwise returns the full runtime data table.

	@param player Player -- Target player.
	@param category string? -- Optional category key within the profile schema.
	@return any? -- Full runtime table or category slice, or nil on timeout/unavailable.
]=]
function PlayerSession.GetDataAwait(player: Player, category: string?)
	assert(typeof(player) == "Instance", "Player argument must be a player instance.")
	if category ~= nil then
		assert(typeof(category) == "string", "Category must be a string when provided.")
	end

	local dataStore = StoreAwait(player)
	if not dataStore then
		warn(("[PlayerSession.GetDataAwait] Timed out or store unavailable for %s"):format(player.Name))
		return nil
	end

	local runtimeData = dataStore.Value
	if not runtimeData then
		warn(("[PlayerSession.GetDataAwait] No runtime data found for %s"):format(tostring(player)))
		return nil
	end

	if category then
		if not Profile[category] then
			warn(
				("[PlayerSession.GetDataAwait] Unknown category '%s' for %s"):format(
					tostring(category),
					tostring(player)
				)
			)
			return nil
		end
		if runtimeData[category] == nil then
			warn(
				("[PlayerSession.GetDataAwait] Missing runtime data for category '%s' on %s"):format(
					tostring(category),
					tostring(player)
				)
			)
			return nil
		end
	end

	return category and runtimeData[category] or runtimeData
end

--[=[
	Non-blocking getter for player runtime data.

	Returns `nil` if the store isn’t found/open, if no runtime data is present,
	or if the requested category is unknown/missing.

	@param player Player -- Target player.
	@param category string? -- Optional category key.
	@return any? -- Full runtime table or category slice; `nil` if not ready/invalid.
]=]
function PlayerSession.GetData(player: Player, category: string?)
	assert(typeof(player) == "Instance", "Player argument must be a player instance.")
	if category ~= nil then
		assert(typeof(category) == "string", "Category must be a string when provided.")
	end

	local key = tostring(player.UserId)
	local dataStore = DataStore.find(STORE_NAME, SCOPE, key)
	if not dataStore then
		warn(("[PlayerSession.GetData] Timed out or store unavailable for %s"):format(player.Name))
		return nil
	end

	local runtimeData = dataStore.Value
	if not runtimeData then
		warn(("[PlayerSession.GetData] No runtime data found for %s"):format(tostring(player)))
		return nil
	end

	if category then
		if not Profile[category] then
			warn(("[PlayerSession.GetData] Unknown category '%s' for %s"):format(tostring(category), tostring(player)))
			return nil
		end
		if runtimeData[category] == nil then
			warn(
				("[PlayerSession.GetData] Missing runtime data for category '%s' on %s"):format(
					tostring(category),
					tostring(player)
				)
			)
			return nil
		end
	end

	return category and runtimeData[category] or runtimeData
end

--[=[
	Find the store object without guarantees.

	Returns the underlying DataStore object for `player` if it exists in memory,
	or `nil` if it doesn’t exist yet or is not created/open.

	@param player Player -- Target player.
	@return DataStoreObject? -- Store object or nil.
]=]
function PlayerSession.GetStore(player: Player): DataStoreObject?
	assert(typeof(player) == "Instance", "Player argument must be a player instance.")
	local key = tostring(player.UserId)
	return DataStore.find(STORE_NAME, SCOPE, key)
end

--[=[
	Await the store object to be ready (open).

	Blocks until the DataStore for `player` exists and is open. May still return
	`nil` if the player leaves or timeout occurs.

	@param player Player -- Target player.
	@return DataStoreObject? -- Open store object or nil on timeout/leave.
]=]
function PlayerSession.GetStoreAwait(player: Player): DataStoreObject?
	assert(typeof(player) == "Instance", "Player argument must be a player instance.")
	return StoreAwait(player)
end

--[=[
	Fast readiness check (non-blocking).

	Checks whether the player’s store is present, open, and has a runtime value.
	If `category` is provided, also checks that the category exists on the value.

	@param player Player -- Target player.
	@param category string? -- Optional category key.
	@return boolean -- True if ready (and category present when requested).
]=]
function PlayerSession.IsReady(player: Player, category: string?): boolean
	assert(typeof(player) == "Instance" and player:IsA("Player"), "Player expected")
	if category ~= nil then
		assert(typeof(category) == "string", "Category must be a string when provided.")
	end

	local key = tostring(player.UserId)
	local store = DataStore.find(STORE_NAME, SCOPE, key)
	if not store or store.State ~= true then
		return false
	end
	local data = store.Value
	if not data then
		return false
	end
	if category then
		return data[category] ~= nil
	end
	return true
end

--[=[
	Quiet, non-blocking getter.

	Returns `nil` without warnings if the player/session isn’t ready or the
	requested category is missing.

	@param player Player -- Target player.
	@param category string? -- Optional category key.
	@return any? -- Full runtime table or category slice; `nil` if not ready.
]=]
function PlayerSession.TryGetData(player: Player, category: string?)
	if not PlayerSession.IsReady(player, category) then
		return nil
	end
	return PlayerSession.GetData(player, category)
end

--[=[
	Clear (unset) the player’s runtime data value in the open store.

	No-op if the store can’t be awaited (player left / timeout). Does not
	delete persistent data; this only clears the in-memory runtime `Value`.

	@param player Player -- Target player.
]=]
function PlayerSession.ClearData(player: Player)
	local dataStore = PlayerSession.GetStoreAwait(player)
	if not dataStore then
		return
	end
	dataStore.Value = nil
end

Players.PlayerAdded:Connect(OnPlayerAdded)
Players.PlayerRemoving:Connect(OnPlayerRemoving)

return PlayerSession
