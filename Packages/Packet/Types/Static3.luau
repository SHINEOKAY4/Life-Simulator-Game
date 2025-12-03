-- Static3: Season and WeatherType enums for weather system
-- Encodes 9 total values in 1 byte instead of 4-6 bytes per string
return {
	-- Seasons (indices 1-4)
	"Spring",
	"Summer",
	"Autumn",
	"Winter",
	-- Weather types (indices 5-9)
	"Sunny",
	"Rainy",
	"Stormy",
	"Snowy",
	"Cloudy",
}
