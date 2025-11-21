--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Packet = require(ReplicatedStorage.Packages.Packet)

local WeatherPackets = {
	-- Server sends current weather state to clients (on join or change)
	-- Args: { Season, DayInSeason, WeatherType, NextWeatherType }
	WeatherUpdate = Packet("WeatherUpdate", {
		Season = Packet.String,
		DayInSeason = Packet.NumberU8,
		WeatherType = Packet.String,
		NextWeatherType = Packet.String, -- For forecast
	}),
}

return WeatherPackets
