--!strict
local WeatherConfig = {}

export type Season = "Spring" | "Summer" | "Autumn" | "Winter"
export type WeatherType = "Sunny" | "Rainy" | "Stormy" | "Snowy" | "Cloudy"

WeatherConfig.Seasons = { "Spring", "Summer", "Autumn", "Winter" } :: { Season }
WeatherConfig.DaysPerSeason = 5 -- Short seasons for gameplay loop

-- Base temperature ranges per season (Celsius)
WeatherConfig.SeasonTemperatures = {
	Spring = { Min = 10, Max = 20 },
	Summer = { Min = 20, Max = 35 },
	Autumn = { Min = 5, Max = 15 },
	Winter = { Min = -5, Max = 5 },
}

-- Weather modifiers (offset in degrees)
WeatherConfig.WeatherModifiers = {
	Sunny = 2,
	Cloudy = -1,
	Rainy = -3,
	Stormy = -5,
	Snowy = -5, -- Only applies if temp is low enough, but acts as a modifier
}

-- Probability weights for weather per season
WeatherConfig.WeatherWeights = {
	Spring = { Sunny = 50, Cloudy = 30, Rainy = 20, Stormy = 0, Snowy = 0 },
	Summer = { Sunny = 70, Cloudy = 20, Rainy = 5, Stormy = 5, Snowy = 0 },
	Autumn = { Sunny = 30, Cloudy = 40, Rainy = 25, Stormy = 5, Snowy = 0 },
	Winter = { Sunny = 30, Cloudy = 30, Rainy = 0, Stormy = 0, Snowy = 40 },
}

-- Shared math to calculate outdoor temperature based on state and time
function WeatherConfig.CalculateOutdoorTemperature(season: Season, weather: WeatherType, clockTime: number): number
	local range = WeatherConfig.SeasonTemperatures[season]
	if not range then
		return 20
	end -- Fallback

	-- Daily cycle: Coldest at 4am, Hottest at 2pm (14:00)
	-- Cosine wave shifted
	-- Peak at 14, Trough at 2 (or 4)
	-- cos(0) = 1. We want 1 at 14.
	-- (clockTime - 14) / 24 * 2pi

	local radian = ((clockTime - 14) / 24) * (math.pi * 2)
	local cycleFactor = math.cos(radian) -- 1 at 14:00, -1 at 02:00

	-- Map -1..1 to Min..Max
	-- Average temp
	local avg = (range.Min + range.Max) / 2
	local amplitude = (range.Max - range.Min) / 2

	local baseTemp = avg + (cycleFactor * amplitude)

	-- Apply weather modifier
	local modifier = WeatherConfig.WeatherModifiers[weather] or 0

	return baseTemp + modifier
end

function WeatherConfig.GetSeasonFromDay(dayIndex: number): (Season, number)
	-- dayIndex is 0-based total days
	local seasonIndex = math.floor(dayIndex / WeatherConfig.DaysPerSeason) % #WeatherConfig.Seasons
	local dayInSeason = dayIndex % WeatherConfig.DaysPerSeason

	return WeatherConfig.Seasons[seasonIndex + 1], dayInSeason + 1
end

return WeatherConfig
