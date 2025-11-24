--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local WeatherConfig = require(ReplicatedStorage.Shared.Configurations.WeatherConfig)
local TimeScale = require(ReplicatedStorage.Shared.Utilities.TimeScale)

local WeatherController = {}

local _currentState = {
	Season = "Spring" :: WeatherConfig.Season,
	DayInSeason = 1,
	WeatherType = "Sunny" :: WeatherConfig.WeatherType,
	NextWeatherType = "Sunny" :: WeatherConfig.WeatherType,
}

function WeatherController.Start()
	-- Read weather state from ReplicatedStorage Value objects (auto-replicated, zero packets)
	local weatherFolder = ReplicatedStorage:WaitForChild("WeatherState", 10)
	if not weatherFolder then
		warn("[WeatherController] WeatherState folder not found in ReplicatedStorage")
		return
	end

	local seasonValue = weatherFolder:WaitForChild("Season", 5) :: StringValue
	local dayValue = weatherFolder:WaitForChild("DayInSeason", 5) :: NumberValue
	local weatherValue = weatherFolder:WaitForChild("WeatherType", 5) :: StringValue
	local nextWeatherValue = weatherFolder:WaitForChild("NextWeatherType", 5) :: StringValue

	if not (seasonValue and dayValue and weatherValue and nextWeatherValue) then
		warn("[WeatherController] Missing weather Value objects")
		return
	end

	-- Initialize from current values
	_currentState.Season = seasonValue.Value :: WeatherConfig.Season
	_currentState.DayInSeason = dayValue.Value
	_currentState.WeatherType = weatherValue.Value :: WeatherConfig.WeatherType
	_currentState.NextWeatherType = nextWeatherValue.Value :: WeatherConfig.WeatherType

	-- Listen for changes
	seasonValue.Changed:Connect(function(value)
		_currentState.Season = value :: WeatherConfig.Season
		print(string.format("[WeatherController] Season changed: %s", value))
	end)

	dayValue.Changed:Connect(function(value)
		_currentState.DayInSeason = value
	end)

	weatherValue.Changed:Connect(function(value)
		_currentState.WeatherType = value :: WeatherConfig.WeatherType
		print(string.format("[WeatherController] Weather changed: %s", value))
	end)

	nextWeatherValue.Changed:Connect(function(value)
		_currentState.NextWeatherType = value :: WeatherConfig.WeatherType
	end)
end

function WeatherController.GetCurrentTemperature(): number
	local clockTime = TimeScale.GetClockTime()
	return WeatherConfig.CalculateOutdoorTemperature(_currentState.Season, _currentState.WeatherType, clockTime)
end

function WeatherController.GetState()
	return _currentState
end

return WeatherController
