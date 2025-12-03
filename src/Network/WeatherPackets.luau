--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Packet = require(ReplicatedStorage.Packages.Packet)

local WeatherPackets = {
	-- Server sends current weather state to clients (on join or change)
	-- Args: { Season, DayInSeason, WeatherType, NextWeatherType }
	WeatherUpdate = Packet("WeatherUpdate", {
		Season = Packet.Static3,
		DayInSeason = Packet.NumberU8,
		WeatherType = Packet.Static3,
		NextWeatherType = Packet.Static3, -- For forecast
	}),
}

return WeatherPackets
