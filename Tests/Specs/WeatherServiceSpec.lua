-- Tests/Specs/WeatherServiceSpec.lua
-- Inline spec for weather selection weights and season structure.

local function readFile(path)
	local file = assert(io.open(path, "r"), "missing file: " .. path)
	local contents = file:read("*a")
	file:close()
	return contents
end

local SEASONS = { "Spring", "Summer", "Autumn", "Winter" }
local DAYS_PER_SEASON = 5

local WEATHER_TYPES = { "Sunny", "Cloudy", "Rainy", "Stormy", "Snowy" }

local WEATHER_WEIGHTS = {
	Spring = { Sunny = 50, Cloudy = 30, Rainy = 20, Stormy = 0, Snowy = 0 },
	Summer = { Sunny = 70, Cloudy = 20, Rainy = 5, Stormy = 5, Snowy = 0 },
	Autumn = { Sunny = 30, Cloudy = 40, Rainy = 25, Stormy = 5, Snowy = 0 },
	Winter = { Sunny = 30, Cloudy = 30, Rainy = 0, Stormy = 0, Snowy = 40 },
}

local SEASON_TEMPERATURES = {
	Spring = { Min = 10, Max = 20 },
	Summer = { Min = 20, Max = 35 },
	Autumn = { Min = 5, Max = 15 },
	Winter = { Min = -5, Max = 5 },
}

local function pickWeatherForSeason(season)
	local weights = WEATHER_WEIGHTS[season]
	local totalWeight = 0
	for _, weight in pairs(weights) do
		totalWeight = totalWeight + weight
	end

	local roll = math.random() * totalWeight
	local current = 0
	for weather, weight in pairs(weights) do
		current = current + weight
		if roll <= current then
			return weather
		end
	end
	return "Sunny"
end

local function getSeasonFromDay(dayIndex)
	local seasonIndex = math.floor(dayIndex / DAYS_PER_SEASON) % #SEASONS
	local dayInSeason = dayIndex % DAYS_PER_SEASON
	return SEASONS[seasonIndex + 1], dayInSeason + 1
end

local function assertSeasonConfig(season)
	local weights = WEATHER_WEIGHTS[season]
	assert.are.equal("table", type(weights), "missing weights for " .. season)

	local totalWeight = 0
	for _, weather in ipairs(WEATHER_TYPES) do
		local weight = weights[weather]
		assert.are.equal("number", type(weight), "missing weight for " .. season .. ":" .. weather)
		totalWeight = totalWeight + weight
	end
	assert.is_true(totalWeight > 0, "total weight must be positive for " .. season)

	local temps = SEASON_TEMPERATURES[season]
	assert.are.equal("table", type(temps), "missing temperature range for " .. season)
	assert.are.equal("number", type(temps.Min))
	assert.are.equal("number", type(temps.Max))
	assert.is_true(temps.Min <= temps.Max, "min must be <= max for " .. season)

	local allowed = {}
	for weather, _ in pairs(weights) do
		allowed[weather] = true
	end

	for _ = 1, 25 do
		local result = pickWeatherForSeason(season)
		assert.is_true(allowed[result], "unexpected weather " .. tostring(result) .. " for " .. season)
	end
end

describe("WeatherService pickWeatherForSeason (inline)", function()
	it("Spring weights yield only valid weather types", function()
		assertSeasonConfig("Spring")
	end)

	it("Summer weights yield only valid weather types", function()
		assertSeasonConfig("Summer")
	end)

	it("Autumn weights yield only valid weather types", function()
		assertSeasonConfig("Autumn")
	end)

	it("Winter weights yield only valid weather types", function()
		assertSeasonConfig("Winter")
	end)
end)

describe("WeatherConfig season cycling (inline)", function()
	it("cycles Spring -> Summer -> Autumn -> Winter -> Spring", function()
		local cycle = {}
		for dayIndex = 0, DAYS_PER_SEASON * #SEASONS do
			local season, dayInSeason = getSeasonFromDay(dayIndex)
			assert.is_true(dayInSeason >= 1 and dayInSeason <= DAYS_PER_SEASON)
			if dayInSeason == 1 then
				table.insert(cycle, season)
			end
		end
		assert.are.equal("Spring,Summer,Autumn,Winter,Spring", table.concat(cycle, ","))
	end)
end)

describe("WeatherConfig season order (structural)", function()
	local configSrc

	before_each(function()
		configSrc = readFile("src/Shared/Configurations/WeatherConfig.luau")
	end)

	it("declares Seasons in Spring -> Summer -> Autumn -> Winter order", function()
		assert.is_truthy(
			string.find(
				configSrc,
				"Seasons%s*=%s*{%s*\"Spring\"%s*,%s*\"Summer\"%s*,%s*\"Autumn\"%s*,%s*\"Winter\"%s*}",
				1,
				false
			)
		)
	end)
end)

describe("WeatherService state structure (structural)", function()
	local serviceSrc

	before_each(function()
		serviceSrc = readFile("src/Server/Services/WeatherService.luau")
	end)

	it("WeatherState defines the core fields", function()
		for _, field in ipairs({ "Season", "DayInSeason", "WeatherType", "NextWeatherType", "LastDayIndex" }) do
			assert.is_truthy(string.find(serviceSrc, field .. "%s*:", 1, false))
		end
	end)

	it("_currentState initializes all fields", function()
		assert.is_truthy(string.find(serviceSrc, "Season%s*=%s*\"Spring\"", 1, false))
		assert.is_truthy(string.find(serviceSrc, "DayInSeason%s*=%s*1", 1, false))
		assert.is_truthy(string.find(serviceSrc, "WeatherType%s*=%s*\"Sunny\"", 1, false))
		assert.is_truthy(string.find(serviceSrc, "NextWeatherType%s*=%s*\"Sunny\"", 1, false))
		assert.is_truthy(string.find(serviceSrc, "LastDayIndex%s*=%s*%-1", 1, false))
	end)

	it("pickWeatherForSeason uses weights and math.random", function()
		assert.is_truthy(string.find(serviceSrc, "WeatherConfig%.WeatherWeights", 1, false))
		assert.is_truthy(string.find(serviceSrc, "math%.random", 1, false))
		assert.is_truthy(string.find(serviceSrc, "return%s+\"Sunny\"", 1, false))
	end)
end)
