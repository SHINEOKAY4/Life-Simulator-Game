--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Players = game:GetService("Players")

local WeatherConfig = require(ReplicatedStorage.Shared.Configurations.WeatherConfig)
local WeatherPackets = require(ReplicatedStorage.Network.WeatherPackets)
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

	-- Replicate
	WeatherPackets.WeatherUpdate:Fire({
		Season = _currentState.Season,
		DayInSeason = _currentState.DayInSeason,
		WeatherType = _currentState.WeatherType,
		NextWeatherType = _currentState.NextWeatherType,
	})

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

	-- Sync new players
	Players.PlayerAdded:Connect(function(player)
		WeatherPackets.WeatherUpdate:FireClient(player, {
			Season = _currentState.Season,
			DayInSeason = _currentState.DayInSeason,
			WeatherType = _currentState.WeatherType,
			NextWeatherType = _currentState.NextWeatherType,
		})
	end)
end

function WeatherService.GetCurrentTemperature(): number
	local clockTime = TimeScale.GetClockTime()
	return WeatherConfig.CalculateOutdoorTemperature(_currentState.Season, _currentState.WeatherType, clockTime)
end

function WeatherService.GetState()
	return _currentState
end

return WeatherService
