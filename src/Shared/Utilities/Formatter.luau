--[[
    Formatter Module

    A lightweight, stateless collection of formatting utilities for Roblox games.
    This module exposes a set of pure functions that convert numbers, times,
    dates and lists into human‑readable strings. Each function accepts an
    optional configuration table to adjust behaviour without introducing
    unnecessary state. Typing information is provided through Luau's type
    annotations for improved tooling and static analysis.

    The module intentionally avoids abbreviating variable names and keeps
    implementation details private. Default behaviours follow sensible
    conventions but can be overridden on a per‑call basis. Functions never
    modify shared state and can be called concurrently without side effects.

    Examples:

        local Formatter = require(path.to.Formatter)

        -- Basic number formatting
        print(Formatter.formatNumber(1234567.89))             -- "1,234,567.89"
        print(Formatter.formatNumber(1234567.89, {useAbbreviation = true}))
        -- "1.23M"

        -- Currency formatting
        print(Formatter.formatCurrency(99.5, {currencySymbol = "$"}))
        -- "$99.50"

        -- Ordinal formatting
        print(Formatter.formatOrdinal(21))                    -- "21st"

        -- Time formatting
        print(Formatter.formatTime(75))                       -- "1:15"
        print(Formatter.formatTime(75, {showHoursIfZero = true}))
        -- "0:01:15"

        -- Duration formatting
        print(Formatter.formatDuration(3665))                 -- "1 hour, 1 minute and 5 seconds"
        print(Formatter.formatDuration(3665, {shortUnits = true}))
        -- "1 hr, 1 min and 5 sec"

        -- Date/time formatting using DateTime API
        local now = DateTime.now()
        print(Formatter.formatDateTime(now, "LL", {locale = "en-us", useLocalTime = true}))

        -- List formatting
        print(Formatter.formatList({"apple", "banana", "cherry"}))
        -- "apple, banana and cherry"

    See individual function documentation below for further details and
    configuration options.
--]]

local Formatter = {}
Formatter.__index = Formatter

--
-- Type declarations for configuration tables.
-- These declarations are exported so that consuming scripts can benefit
-- from type checking and autocomplete when using the module.

export type NumberFormatOptions = {
	useAbbreviation: boolean?, -- abbreviate large values (e.g. 1.2M)
	decimalPlaces: number?, -- digits after decimal; defaults depend on abbreviation
	abbreviations: { string }?, -- custom suffix list; default covers K→Dc
	useCommas: boolean?, -- insert thousands separators; defaults to true
}

export type CurrencyFormatOptions = {
	currencySymbol: string, -- required prefix (e.g. "$")
	decimalPlaces: number?, -- digits after decimal; defaults to 2
	useCommas: boolean?, -- insert commas; defaults to true
	useAbbreviation: boolean?, -- abbreviate currency values
	abbreviations: { string }?, -- custom suffix list for abbreviations
}

export type DurationFormatOptions = {
	units: { string }?, -- units to include; defaults {"day","hour","minute","second"}
	shortUnits: boolean?, -- use short labels ("hr","min"); defaults to false
	maxUnits: number?, -- maximum number of units to display
	separator: string?, -- separator between all but last two units; defaults to ", "
	lastSeparator: string?, -- separator before final unit; defaults to " and "
	zeroPad: boolean?, -- pad unit counts with leading zeros; defaults to false
}

export type ListFormatOptions = {
	separator: string?, -- separator for non‑final items; defaults to ", "
	lastSeparator: string?, -- separator before last item; defaults to " and "
}

export type DateTimeFormatOptions = {
	locale: string?, -- locale identifier; defaults to "en-us"
	useLocalTime: boolean?, -- interpret as local time (true) or UTC (false); defaults to true
}

-- Default abbreviations for large numbers (thousand → decillion).
local DEFAULT_ABBREVIATIONS = {
	"K",
	"M",
	"B",
	"T",
	"Qa",
	"Qi",
	"Sx",
	"Sp",
	"Oc",
	"No",
	"Dc",
}

-- Short labels for duration units.
local SHORT_UNIT_NAMES = {
	year = "yr",
	day = "d",
	hour = "hr",
	minute = "min",
	second = "sec",
	millisecond = "ms",
}

-- Seconds per unit (milliseconds expressed as fraction).
local UNIT_SECONDS = {
	year = 31536000,
	day = 86400,
	hour = 3600,
	minute = 60,
	second = 1,
	millisecond = 1 / 1000,
}

-- Remove trailing zeros and any dangling decimal point.
local function trimTrailingZeros(numberString: string): string
	if not string.find(numberString, ".", 1, true) then
		return numberString
	end
	local trimmed = numberString:gsub("0+$", "")
	trimmed = trimmed:gsub("%.$", "")
	return trimmed
end

-- Insert comma separators into the integer part of a number.
local function addCommas(numberString: string): string
	local sign, integerPart, fractionalPart = numberString:match("^([%-]?)(%d+)(%.?%d*)$")
	if not integerPart then
		return numberString
	end
	local reversed = integerPart:reverse()
	local withCommas = reversed:gsub("(%d%d%d)", "%1,")
	withCommas = withCommas:reverse():gsub("^,", "")
	return sign .. withCommas .. fractionalPart
end

-- Join a list of parts with appropriate separators.
local function joinWithSeparators(items: { string }, separator: string, lastSeparator: string): string
	local count = #items
	if count == 0 then
		return ""
	elseif count == 1 then
		return items[1]
	elseif count == 2 then
		return items[1] .. lastSeparator .. items[2]
	else
		local combined = table.concat(items, separator, 1, count - 2)
		combined = combined .. separator .. items[count - 1] .. lastSeparator .. items[count]
		return combined
	end
end

-- Format a number with optional abbreviation, decimal places and commas.
function Formatter.formatNumber(numberValue: number, options: NumberFormatOptions?): string
	if numberValue == nil then
		return ""
	end
	local numericValue = tonumber(numberValue)
	if numericValue == nil then
		return tostring(numberValue)
	end
	if numericValue ~= numericValue then
		return "NaN"
	end
	if numericValue == math.huge then
		return "∞"
	elseif numericValue == -math.huge then
		return "-∞"
	end
	local useAbbreviation = options and options.useAbbreviation or false
	local decimalPlaces = options and options.decimalPlaces
	local abbreviations = options and options.abbreviations or DEFAULT_ABBREVIATIONS
	local useCommas = true
	if options and options.useCommas ~= nil then
		useCommas = options.useCommas
	end
	if decimalPlaces == nil then
		decimalPlaces = useAbbreviation and 1 or 2
	end
	local signPrefix = ""
	if numericValue < 0 then
		signPrefix = "-"
		numericValue = -numericValue
	end
	if useAbbreviation and numericValue >= 1000 then
		local scaledValue = numericValue
		local suffixIndex = 0
		while scaledValue >= 1000 and suffixIndex < #abbreviations do
			scaledValue = scaledValue / 1000
			suffixIndex += 1
		end
		local formatString = "%." .. tostring(decimalPlaces) .. "f"
		local formatted = string.format(formatString, scaledValue)
		formatted = trimTrailingZeros(formatted)
		local suffix = abbreviations[suffixIndex] or ""
		return signPrefix .. formatted .. suffix
	else
		local formatString = "%." .. tostring(decimalPlaces) .. "f"
		local formatted = string.format(formatString, numericValue)
		formatted = trimTrailingZeros(formatted)
		if useCommas then
			formatted = addCommas(formatted)
		end
		return signPrefix .. formatted
	end
end

-- Format a number as currency with a required currencySymbol.
function Formatter.formatCurrency(amount: number, options: CurrencyFormatOptions): string
	if not options or not options.currencySymbol then
		error("formatCurrency requires a currencySymbol in the options table", 2)
	end
	local currencySymbol = options.currencySymbol
	local useAbbreviation = options.useAbbreviation or false
	local decimalPlaces = options.decimalPlaces
	local abbreviations = options.abbreviations or DEFAULT_ABBREVIATIONS
	local useCommas = true
	if options.useCommas ~= nil then
		useCommas = options.useCommas
	end
	if decimalPlaces == nil then
		decimalPlaces = 2
	end
	local formattedNumber = Formatter.formatNumber(amount, {
		useAbbreviation = useAbbreviation,
		decimalPlaces = decimalPlaces,
		abbreviations = abbreviations,
		useCommas = useCommas,
	})
	return currencySymbol .. formattedNumber
end

-- Convert an integer to its ordinal string (e.g. 1 → 1st).
function Formatter.formatOrdinal(value: number): string
	local integerPart = math.floor(math.abs(value))
	local suffix
	local lastTwo = integerPart % 100
	if lastTwo == 11 or lastTwo == 12 or lastTwo == 13 then
		suffix = "th"
	else
		local lastDigit = integerPart % 10
		if lastDigit == 1 then
			suffix = "st"
		elseif lastDigit == 2 then
			suffix = "nd"
		elseif lastDigit == 3 then
			suffix = "rd"
		else
			suffix = "th"
		end
	end
	return tostring(value) .. suffix
end

-- Format a number of seconds into a clock‑style string (H:MM:SS or M:SS).
function Formatter.formatTime(
	seconds: number,
	options: { showHoursIfZero: boolean?, includeMilliseconds: boolean?, padHours: boolean? }?
): string
	if seconds == nil then
		return ""
	end
	local totalMilliseconds = seconds * 1000
	local isNegative = totalMilliseconds < 0
	if isNegative then
		totalMilliseconds = -totalMilliseconds
	end
	local truncatedMilliseconds = math.floor(totalMilliseconds + 0.5)
	local totalSeconds = math.floor(truncatedMilliseconds / 1000)
	local milliseconds = truncatedMilliseconds % 1000
	local hours = math.floor(totalSeconds / 3600)
	local minutes = math.floor((totalSeconds % 3600) / 60)
	local secs = totalSeconds % 60
	local showHoursIfZero = false
	local includeMilliseconds = false
	local padHours = false
	if options then
		if options.showHoursIfZero ~= nil then
			showHoursIfZero = options.showHoursIfZero
		end
		if options.includeMilliseconds ~= nil then
			includeMilliseconds = options.includeMilliseconds
		end
		if options.padHours ~= nil then
			padHours = options.padHours
		end
	end
	local components = {}
	if hours > 0 or showHoursIfZero then
		if padHours then
			table.insert(components, string.format("%02d", hours))
		else
			table.insert(components, tostring(hours))
		end
		table.insert(components, string.format("%02d", minutes))
		table.insert(components, string.format("%02d", secs))
	else
		table.insert(components, tostring(minutes))
		table.insert(components, string.format("%02d", secs))
	end
	local result = table.concat(components, ":")
	if includeMilliseconds then
		result = result .. string.format(".%03d", milliseconds)
	end
	if isNegative then
		result = "-" .. result
	end
	return result
end

-- Format a duration (seconds) into a human‑readable sentence of units.
function Formatter.formatDuration(durationSeconds: number, options: DurationFormatOptions?): string
	if durationSeconds == nil then
		return ""
	end
	local isNegative = durationSeconds < 0
	local remaining = math.abs(durationSeconds)
	local units = (options and options.units) or { "day", "hour", "minute", "second" }
	local shortUnits = options and options.shortUnits or false
	local maxUnits = options and options.maxUnits
	local separator = options and options.separator or ", "
	local lastSeparator = options and options.lastSeparator or " and "
	local zeroPad = options and options.zeroPad or false
	local components = {}
	local displayedCount = 0
	for _, unitName in ipairs(units) do
		local unitSeconds = UNIT_SECONDS[unitName]
		if unitSeconds then
			local count
			if unitName == "millisecond" then
				local totalMillis = math.floor(remaining * 1000 + 0.5)
				count = totalMillis % 1000
				remaining = math.floor(totalMillis / 1000)
			else
				count = math.floor(remaining / unitSeconds)
				remaining = remaining % unitSeconds
			end
			if count > 0 then
				local label
				if shortUnits then
					label = SHORT_UNIT_NAMES[unitName] or unitName
				else
					if count == 1 then
						label = unitName
					else
						label = unitName .. "s"
					end
				end
				local valueString
				if zeroPad and displayedCount > 0 then
					valueString = string.format("%02d", count)
				else
					valueString = tostring(count)
				end
				table.insert(components, valueString .. " " .. label)
				displayedCount += 1
				if maxUnits and displayedCount >= maxUnits then
					break
				end
			end
		end
	end
	local result
	if #components == 0 then
		if table.find(units, "second") then
			local label = shortUnits and (SHORT_UNIT_NAMES["second"] or "second") or "seconds"
			result = "0 " .. label
		else
			result = ""
		end
	elseif #components == 1 then
		result = components[1]
	else
		result = joinWithSeparators(components, separator, lastSeparator)
	end
	if isNegative and result ~= "" then
		result = "-" .. result
	end
	return result
end

-- Format a DateTime or Unix timestamp according to Roblox's DateTime API.
function Formatter.formatDateTime(value: any, formatString: string, options: DateTimeFormatOptions?): string
	if not formatString or formatString == "" then
		return ""
	end
	local dt
	local valueType = typeof(value)
	if valueType == "DateTime" then
		dt = value
	elseif valueType == "number" then
		dt = DateTime.fromUnixTimestamp(value)
	else
		dt = DateTime.now()
	end
	local locale = "en-us"
	local useLocalTime = true
	if options then
		if options.locale ~= nil then
			locale = options.locale
		end
		if options.useLocalTime ~= nil then
			useLocalTime = options.useLocalTime
		end
	end
	local ok, result
	if useLocalTime then
		ok, result = pcall(function()
			return dt:FormatLocalTime(formatString, locale)
		end)
	else
		ok, result = pcall(function()
			return dt:FormatUniversalTime(formatString, locale)
		end)
	end
	if ok and type(result) == "string" then
		return result
	else
		return ""
	end
end

-- Format a list of strings into a human‑readable sentence.
function Formatter.formatList(items: { string }, options: ListFormatOptions?): string
	if not items or #items == 0 then
		return ""
	end
	local separator = ", "
	local lastSeparator = " and "
	if options then
		if options.separator ~= nil then
			separator = options.separator
		end
		if options.lastSeparator ~= nil then
			lastSeparator = options.lastSeparator
		end
	end
	return joinWithSeparators(items, separator, lastSeparator)
end

-- Select singular or plural form based on a count, with optional custom plural.
function Formatter.pluralize(singularWord: string, count: number, pluralWord: string?): string
	if math.abs(count) == 1 then
		return singularWord
	else
		return pluralWord or (singularWord .. "s")
	end
end

return Formatter
