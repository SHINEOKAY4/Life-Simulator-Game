--!strict
-- Debug.lua
-- Lightweight logging hooks for your DataStore wrapper.
-- Connects to store signals (StateChanged, Saving, Saved, AttemptsChanged) and prints human-readable lines.
-- Returns a cleanup function so you can disconnect all listeners cleanly.

local ServerStorage = game:GetService("ServerStorage")
local HttpService = game:GetService("HttpService")

local DataStore = require(ServerStorage.ServerPackages.DataStore)

local Debug = {}

-- Configuration for how logs should look and how much data to include.
export type DebugOptions = {
	tag: string?, -- Optional label included in every log line, e.g. "PlayerSession"
	includeTimestamp: boolean?, -- If true, prefix each line with [seconds] from os.clock()
	includeValue: boolean?, -- If true, include the value payloads from Saving/Saved
	maxValueCharacters: number?, -- If set, truncate included value text to this many characters
}

-- Build a readable label for a store:
-- - If the Player is attached and still in-game, show "DisplayName (UserId)"
-- - Otherwise fall back to "<Id>:<Key>" so the line is still identifiable
local function buildStoreLabel(store: any): string
	local player = store.Player
	if player and player.Parent then
		return string.format("%s (%d)", player.DisplayName, player.UserId)
	end
	local idText = (store.Id and tostring(store.Id)) or "?"
	local keyText = (store.Key and tostring(store.Key)) or "?"
	return string.format("%s:%s", idText, keyText)
end

-- Convert an arbitrary value to a short, log-friendly string.
-- Tables are JSON-encoded (guarded by pcall in case of cyclic data); everything else is tostring().
-- Optionally truncate to keep lines compact.
local function formatValue(value: any, maxCharacters: number?): string
	local text: string
	if typeof(value) == "table" then
		local ok, json = pcall(HttpService.JSONEncode, HttpService, value)
		text = ok and json or "<table>"
	else
		text = tostring(value)
	end
	if maxCharacters and #text > maxCharacters then
		text = string.sub(text, 1, maxCharacters) .. "…"
	end
	return text
end

-- Build a consistent prefix such as:
--   [123.456] [INFO] [PlayerSession]
-- Timestamp and tag are optional and controlled by options.
local function buildLogPrefix(options: DebugOptions?, level: "INFO" | "WARN"): string
	local parts = {}
	if options and options.includeTimestamp then
		table.insert(parts, string.format("[%.3f]", os.clock()))
	end
	table.insert(parts, "[" .. level .. "]")
	if options and options.tag then
		table.insert(parts, "[" .. options.tag .. "]")
	end
	return table.concat(parts, "")
end

-- Connects all debug signals for a given store and starts printing.
-- Returns: function() -> ()  A cleanup function that disconnects all connections.
-- Usage:
--   local disconnect = Debug.Enabled(store, { tag = "PlayerSession", includeTimestamp = true, includeValue = true, maxValueCharacters = 200 })
--   ...
--   disconnect() -- when you no longer want logs
function Debug.Enabled(store: any, options: DebugOptions?): () -> ()
	local storeLabel = buildStoreLabel(store)
	local includeValue = options and options.includeValue == true
	local maxChars = options and options.maxValueCharacters

	-- Fires when the store transitions state:
	--   true      -> open and usable
	--   false     -> closed (attempts to reopen elsewhere)
	--   nil       -> destroyed
	local stateChangedConnection = store.StateChanged:Connect(function(state: boolean?)
		if state == nil then
			warn(buildLogPrefix(options, "WARN"), " StateChanged ", storeLabel, " -> destroyed")
		else
			print(buildLogPrefix(options, "INFO"), " StateChanged ", storeLabel, " -> ", tostring(state))
		end
	end)

	-- Fires right before a save attempt. Value is included only if requested.
	local savingConnection = store.Saving:Connect(function(currentValue: any)
		local valueText = includeValue and (" " .. formatValue(currentValue, maxChars)) or ""
		print(buildLogPrefix(options, "INFO"), " Saving ", storeLabel, valueText)
	end)

	-- Fires after a save attempt:
	--   Response "Saved" -> success (optionally prints the saved value)
	--   Response "Error" -> failure (prints the error message)
	--   Other responses  -> informational (printed at INFO)
	local savedConnection = store.Saved:Connect(function(response: string, responseData: any)
		if response == DataStore.Response.Saved then
			local valueText = includeValue and (" " .. formatValue(responseData, maxChars)) or ""
			print(buildLogPrefix(options, "INFO"), " Saved ", storeLabel, valueText)
		elseif response == DataStore.Response.Error then
			warn(buildLogPrefix(options, "WARN"), " Error ", storeLabel, " ", tostring(responseData))
		else
			local valueText = includeValue and (" " .. formatValue(responseData, maxChars)) or ""
			print(buildLogPrefix(options, "INFO"), " ", response, " ", storeLabel, valueText)
		end
	end)

	-- Locking watchdog: attempts remaining before the store gives up reopening.
	local attemptsChangedConnection = store.AttemptsChanged:Connect(function(attemptsRemaining: number)
		warn(buildLogPrefix(options, "WARN"), " AttemptsChanged ", storeLabel, " -> ", attemptsRemaining)
	end)

	-- Cleanup function so tests/teleports can disconnect cleanly.
	return function()
		if stateChangedConnection.Connected then
			stateChangedConnection:Disconnect()
		end
		if savingConnection.Connected then
			savingConnection:Disconnect()
		end
		if savedConnection.Connected then
			savedConnection:Disconnect()
		end
		if attemptsChangedConnection.Connected then
			attemptsChangedConnection:Disconnect()
		end
	end
end

return Debug
