--!strict
-- ResidentDebug.lua
-- Lightweight debugging utilities for resident autonomy, movement, and station actions.

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GoodSignal = require(ReplicatedStorage.Packages.GoodSignal)

export type DebugLevel = "INFO" | "WARN" | "ERROR"

export type DebugEntry = {
	Time: number,
	Channel: string,
	Message: string,
	Metadata: { [string]: any }?,
	Level: DebugLevel,
}

local ResidentDebug = {}

local MAX_HISTORY = 200
local MAX_METADATA_DEPTH = 3
local MAX_METADATA_ENTRIES = 25
local TraceSignal = GoodSignal.new()

local channelEnabled: { [string]: boolean } = {}
local history: { [string]: { DebugEntry } } = {}
local globalEnabled = false

local function getBucket(channel: string)
	local bucket = history[channel]
	if not bucket then
		bucket = {}
		history[channel] = bucket
	end
	return bucket
end

local function shouldPrint(channel: string): boolean
	if globalEnabled then
		return true
	end
	return channelEnabled[channel] == true
end

local function sanitizeMetadata(value: any, depth: number): any
	if depth >= MAX_METADATA_DEPTH then
		return "<max-depth>"
	end
	local valueType = typeof(value)
	if valueType == "table" then
		local result: { [string]: any } = {}
		local count = 0
		for key, inner in pairs(value) do
			count += 1
			if count > MAX_METADATA_ENTRIES then
				result["..."] = string.format("+%d entries", count - MAX_METADATA_ENTRIES)
				break
			end
			result[tostring(key)] = sanitizeMetadata(inner, depth + 1)
		end
		return result
	elseif valueType == "Instance" then
		local fullName = value:GetFullName()
		if typeof(fullName) == "string" then
			return fullName
		end
		return string.format("<%s>", value.ClassName)
	elseif valueType == "Vector3" then
		return string.format("Vector3(%.2f, %.2f, %.2f)", value.X, value.Y, value.Z)
	elseif valueType == "CFrame" then
		local position = value.Position
		return string.format("CFrame(%.2f, %.2f, %.2f)", position.X, position.Y, position.Z)
	elseif valueType == "Color3" then
		return string.format("Color3(%.2f, %.2f, %.2f)", value.R, value.G, value.B)
	elseif valueType == "UDim2" then
		return string.format(
			"UDim2({%.2f, %.2f}, {%.2f, %.2f})",
			value.X.Scale,
			value.X.Offset,
			value.Y.Scale,
			value.Y.Offset
		)
	elseif valueType == "EnumItem" then
		return value.Name
	elseif valueType == "function" then
		return "<function>"
	elseif valueType == "thread" then
		return "<thread>"
	end
	return value
end

local function metadataToString(metadata: { [string]: any }?): string?
	if not metadata then
		return nil
	end
	local sanitized = sanitizeMetadata(metadata, 0)
	local encoded = HttpService:JSONEncode(sanitized)
	if typeof(encoded) == "string" then
		return encoded
	end
	return tostring(sanitized)
end

--- Enables or disables a debugging channel. Disabled channels continue to record
--- history but avoid printing to output.
function ResidentDebug.SetChannelEnabled(channel: string, enabled: boolean)
	channelEnabled[channel] = enabled
end

function ResidentDebug.EnableChannel(channel: string)
	ResidentDebug.SetChannelEnabled(channel, true)
end

function ResidentDebug.DisableChannel(channel: string)
	ResidentDebug.SetChannelEnabled(channel, false)
end

function ResidentDebug.SetGlobalEnabled(enabled: boolean)
	globalEnabled = enabled
end

function ResidentDebug.IsChannelEnabled(channel: string): boolean
	return shouldPrint(channel)
end

function ResidentDebug.GetHistory(channel: string): { DebugEntry }
	local bucket = history[channel]
	if not bucket then
		return {}
	end
	local copy = table.clone(bucket)
	for index, entry in ipairs(copy) do
		copy[index] = table.clone(entry)
	end
	return copy
end

function ResidentDebug.ClearHistory(channel: string?)
	if channel then
		history[channel] = nil
		return
	end
	table.clear(history)
end

function ResidentDebug.GetTraceSignal()
	return TraceSignal
end

function ResidentDebug.Trace(channel: string, message: string, metadata: { [string]: any }?, level: DebugLevel?)
	local now = DateTime.now()
	local entry: DebugEntry = {
		Time = now.UnixTimestampMillis,
		Channel = channel,
		Message = message,
		Metadata = metadata,
		Level = (level or "INFO") :: DebugLevel,
	}
	local bucket = getBucket(channel)
	bucket[#bucket + 1] = entry
	if #bucket > MAX_HISTORY then
		table.remove(bucket, 1)
	end
	TraceSignal:Fire(entry)
	if shouldPrint(channel) then
		local timeStamp = now:FormatLocalTime("HH:mm:ss", "24Hour")
		local prefix = string.format("[ResidentDebug][%s][%s][%s]", channel, entry.Level, timeStamp)
		print(string.format("%s %s", prefix, message))
		local metaString = metadataToString(metadata)
		if metaString then
			print(metaString)
		end
	end
end

function ResidentDebug.Warn(channel: string, message: string, metadata: { [string]: any }?)
	ResidentDebug.Trace(channel, message, metadata, "WARN")
end

function ResidentDebug.Error(channel: string, message: string, metadata: { [string]: any }?)
	ResidentDebug.Trace(channel, message, metadata, "ERROR")
end

function ResidentDebug.DumpHistory(channel: string?, limit: number?)
	local results: { DebugEntry }
	if channel then
		results = ResidentDebug.GetHistory(channel)
	else
		results = {}
		for _, entries in pairs(history) do
			for _, entry in ipairs(entries) do
				results[#results + 1] = entry
			end
		end
		table.sort(results, function(a, b)
			return a.Time < b.Time
		end)
	end
	local maxEntries = limit or #results
	for index = math.max(1, #results - maxEntries + 1), #results do
		local entry = results[index]
		local timeStamp = DateTime.fromUnixTimestampMillis(entry.Time):FormatLocalTime("HH:mm:ss", "24Hour")
		local prefix = string.format("[ResidentDebug][%s][%s][%s]", entry.Channel, entry.Level, timeStamp)
		print(string.format("%s %s", prefix, entry.Message))
		local metaString = metadataToString(entry.Metadata)
		if metaString then
			print(metaString)
		end
	end
end

return ResidentDebug
