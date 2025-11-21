--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local WeatherConfig = require(ReplicatedStorage.Shared.Configurations.WeatherConfig)
local WeatherPackets = require(ReplicatedStorage.Network.WeatherPackets)
local TimeScale = require(ReplicatedStorage.Shared.Utilities.TimeScale)

local WeatherController = {}

local _currentState = {
	Season = "Spring" :: WeatherConfig.Season,
	DayInSeason = 1,
	WeatherType = "Sunny" :: WeatherConfig.WeatherType,
	NextWeatherType = "Sunny" :: WeatherConfig.WeatherType,
}

function WeatherController.Start()
	WeatherPackets.WeatherUpdate.OnClientEvent:Connect(function(data)
		_currentState.Season = data.Season :: WeatherConfig.Season
		_currentState.DayInSeason = data.DayInSeason
		_currentState.WeatherType = data.WeatherType :: WeatherConfig.WeatherType
		_currentState.NextWeatherType = data.NextWeatherType :: WeatherConfig.WeatherType

		-- TODO: Update visuals (skybox, particles)
		print(string.format("[WeatherController] Updated: %s, %s", _currentState.Season, _currentState.WeatherType))
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
