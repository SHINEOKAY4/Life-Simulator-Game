--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local WeatherConfig = require(ReplicatedStorage.Shared.Configurations.WeatherConfig)
local TimeScale = require(ReplicatedStorage.Shared.Utilities.TimeScale)
local WorldUpdate = require(ServerScriptService.Server.Utilities.WorldUpdate)

local WeatherService = {}

type WeatherState = {
	Season: WeatherConfig.Season,
	DayInSeason: number,
	WeatherType: WeatherConfig.WeatherType,
	NextWeatherType: WeatherConfig.WeatherType,
	LastDayIndex: number,
}

local _currentState: WeatherState = {
	Season = "Spring",
	DayInSeason = 1,
	WeatherType = "Sunny",
	NextWeatherType = "Sunny",
	LastDayIndex = -1,
}

-- Create ReplicatedStorage folder for weather state (auto-replicates to clients)
local weatherFolder = ReplicatedStorage:FindFirstChild("WeatherState")
if not weatherFolder then
	weatherFolder = Instance.new("Folder")
	weatherFolder.Name = "WeatherState"
	weatherFolder.Parent = ReplicatedStorage
end

local function getOrCreateValue(name: string, valueType: string, default: any): StringValue | NumberValue
	local existing = weatherFolder:FindFirstChild(name)
	if existing then
		return existing :: any
	end
	local value = Instance.new(valueType :: any)
	value.Name = name
	value.Value = default
	value.Parent = weatherFolder
	return value :: any
end

local seasonValue = getOrCreateValue("Season", "StringValue", "Spring") :: StringValue
local dayValue = getOrCreateValue("DayInSeason", "NumberValue", 1) :: NumberValue
local weatherValue = getOrCreateValue("WeatherType", "StringValue", "Sunny") :: StringValue
local nextWeatherValue = getOrCreateValue("NextWeatherType", "StringValue", "Sunny") :: StringValue

local function pickWeatherForSeason(season: WeatherConfig.Season): WeatherConfig.WeatherType
	local weights = WeatherConfig.WeatherWeights[season]
	local totalWeight = 0
	for _, weight in pairs(weights) do
		totalWeight += weight
	end

	local roll = math.random() * totalWeight
	local current = 0
	for weather, weight in pairs(weights) do
		current += weight
		if roll <= current then
			return weather :: WeatherConfig.WeatherType
		end
	end
	return "Sunny"
end

local function updateWeatherState()
	local dayIndex = TimeScale.GetDayIndex()
	if dayIndex == _currentState.LastDayIndex then
		return
	end

	local season: WeatherConfig.Season, dayInSeason = WeatherConfig.GetSeasonFromDay(dayIndex)

	-- If it's a new day, shift next weather to current, and pick a new next
	-- Or if it's the first run, pick both

	local newWeather: WeatherConfig.WeatherType = _currentState.NextWeatherType
	local nextSeason: WeatherConfig.Season, _ = WeatherConfig.GetSeasonFromDay(dayIndex + 1)
	local nextWeather: WeatherConfig.WeatherType = pickWeatherForSeason(nextSeason)

	if _currentState.LastDayIndex == -1 then
		-- First initialization
		newWeather = pickWeatherForSeason(season)
		nextWeather = pickWeatherForSeason(nextSeason)
	end

	_currentState.Season = season
	_currentState.DayInSeason = dayInSeason
	_currentState.WeatherType = newWeather
	_currentState.NextWeatherType = nextWeather
	_currentState.LastDayIndex = dayIndex

	-- Replicate via Value objects (automatic, zero packets)
	seasonValue.Value = season
	dayValue.Value = dayInSeason
	weatherValue.Value = newWeather
	nextWeatherValue.Value = nextWeather

	print(
		string.format(
			"[WeatherService] Day %d (%s Day %d): %s -> Forecast: %s",
			dayIndex,
			season,
			dayInSeason,
			newWeather,
			nextWeather
		)
	)
end

function WeatherService.Start()
	-- Initialize state
	updateWeatherState()

	-- Check for day changes every 5 seconds (real time)
	-- In-game day is 24 minutes (1440s), so 5s is plenty frequent
	WorldUpdate.Subscribe("WeatherService", 5, function(_dt)
		updateWeatherState()
	end)

	-- No PlayerAdded sync needed - Value objects replicate automatically!
end

function WeatherService.GetCurrentTemperature(): number
	local clockTime = TimeScale.GetClockTime()
	return WeatherConfig.CalculateOutdoorTemperature(_currentState.Season, _currentState.WeatherType, clockTime)
end

function WeatherService.GetState()
	return _currentState
end

return WeatherService
