-- SeasonalEventService: manages per-player seasonal challenge progress,
-- buff application, season transitions, and milestone rewards.
-- Works both in Roblox runtime and in Busted tests loaded via loadfile().

local function hasRobloxRuntime()
	if type(game) ~= "userdata" and type(game) ~= "table" then
		return false
	end
	return pcall(function()
		return game:GetService("Players")
	end)
end

local IS_ROBLOX = hasRobloxRuntime()
local Players = nil
if IS_ROBLOX then
	Players = game:GetService("Players")
end

-- ============ Inline definitions for test mode ============

local SEASONS = {
	{
		Id = "Spring",
		Name = "Spring Bloom",
		Description = "Renewal and growth. Building rewards are increased.",
		DurationDays = 5,
		Buffs = {
			{ Type = "XPMultiplier", Value = 1.15, Label = "+15% Build XP" },
		},
		Challenges = {
			{
				Id = "spring_builder",
				Name = "Spring Construction",
				Description = "Place 20 objects during Spring.",
				StatKey = "SeasonalBuildPlacements",
				TargetValue = 20,
				RewardCash = 300,
				RewardExperience = 75,
			},
			{
				Id = "spring_green",
				Name = "Green Thumb",
				Description = "Complete 8 chores during Spring.",
				StatKey = "SeasonalChoresCompleted",
				TargetValue = 8,
				RewardCash = 200,
				RewardExperience = 50,
			},
		},
	},
	{
		Id = "Summer",
		Name = "Summer Heat",
		Description = "Peak season for tenants. Rental income is boosted.",
		DurationDays = 5,
		Buffs = {
			{ Type = "CashMultiplier", Value = 1.20, Label = "+20% Rental Income" },
		},
		Challenges = {
			{
				Id = "summer_landlord",
				Name = "Summer Landlord",
				Description = "Help 6 tenants during Summer.",
				StatKey = "SeasonalTenantHelps",
				TargetValue = 6,
				RewardCash = 350,
				RewardExperience = 80,
			},
			{
				Id = "summer_crafter",
				Name = "Beat the Heat",
				Description = "Complete 5 crafting jobs during Summer.",
				StatKey = "SeasonalCraftingJobs",
				TargetValue = 5,
				RewardCash = 250,
				RewardExperience = 60,
			},
		},
	},
	{
		Id = "Autumn",
		Name = "Autumn Harvest",
		Description = "Crafting efficiency increases. Prepare for Winter.",
		DurationDays = 5,
		Buffs = {
			{ Type = "CraftSpeedMultiplier", Value = 1.25, Label = "+25% Craft Speed" },
		},
		Challenges = {
			{
				Id = "autumn_crafter",
				Name = "Harvest Workshop",
				Description = "Complete 10 crafting jobs during Autumn.",
				StatKey = "SeasonalCraftingJobs",
				TargetValue = 10,
				RewardCash = 400,
				RewardExperience = 90,
			},
			{
				Id = "autumn_trader",
				Name = "Fall Market",
				Description = "Complete 3 trades during Autumn.",
				StatKey = "SeasonalTradesCompleted",
				TargetValue = 3,
				RewardCash = 300,
				RewardExperience = 70,
			},
		},
	},
	{
		Id = "Winter",
		Name = "Winter Chill",
		Description = "Harsh conditions test your property. Repair bonuses active.",
		DurationDays = 5,
		Buffs = {
			{ Type = "XPMultiplier", Value = 1.20, Label = "+20% Repair XP" },
		},
		Challenges = {
			{
				Id = "winter_repair",
				Name = "Winter Maintenance",
				Description = "Complete 12 chores during Winter.",
				StatKey = "SeasonalChoresCompleted",
				TargetValue = 12,
				RewardCash = 450,
				RewardExperience = 100,
			},
			{
				Id = "winter_warmth",
				Name = "Keep Warm",
				Description = "Help 4 tenants during Winter.",
				StatKey = "SeasonalTenantHelps",
				TargetValue = 4,
				RewardCash = 275,
				RewardExperience = 65,
			},
		},
	},
}

local MILESTONES = {
	{ SeasonsCompleted = 4, BonusCash = 500, BonusExperience = 120, Label = "First Year" },
	{ SeasonsCompleted = 8, BonusCash = 1000, BonusExperience = 250, Label = "Seasoned Veteran" },
	{ SeasonsCompleted = 20, BonusCash = 2500, BonusExperience = 600, Label = "All-Weather Pro" },
}

local SEASON_ORDER = { "Spring", "Summer", "Autumn", "Winter" }
local SEASON_COUNT = #SEASON_ORDER

-- Build lookup tables
local seasonById = {}
for _, season in ipairs(SEASONS) do
	seasonById[season.Id] = season
end

local challengeById = {}
for _, season in ipairs(SEASONS) do
	for _, challenge in ipairs(season.Challenges) do
		challengeById[challenge.Id] = challenge
	end
end

-- ============ Service ============

local SeasonalEventService = {}

-- Configurable clock for tests
local clockFn = os.time

local function getTime()
	return clockFn()
end

-- Internal state per player (keyed by playerId string) for test mode
local testStateByPlayerId = {}
local trackedTestPlayersByKey = {}

-- Notification sink (injectable for tests)
local notificationSink = nil
local weatherServiceRef = nil
local weatherInitToken = 0

local function ensureStateShape(state)
	if type(state.CurrentSeason) ~= "string" then
		state.CurrentSeason = "Spring"
	end
	if type(state.SeasonStartTime) ~= "number" then
		state.SeasonStartTime = 0
	end
	state.SeasonStartTime = math.max(math.floor(state.SeasonStartTime + 0.5), 0)

	if type(state.SeasonsCompleted) ~= "number" then
		state.SeasonsCompleted = 0
	end
	state.SeasonsCompleted = math.max(math.floor(state.SeasonsCompleted + 0.5), 0)

	if type(state.ChallengeProgress) ~= "table" then
		state.ChallengeProgress = {}
	end
	if type(state.CompletedChallenges) ~= "table" then
		state.CompletedChallenges = {}
	end
	if type(state.ClaimedMilestones) ~= "table" then
		state.ClaimedMilestones = {}
	end
	if type(state.TotalChallengesCompleted) ~= "number" then
		state.TotalChallengesCompleted = 0
	end
	state.TotalChallengesCompleted = math.max(math.floor(state.TotalChallengesCompleted + 0.5), 0)

	if type(state.TotalSeasonalCashEarned) ~= "number" then
		state.TotalSeasonalCashEarned = 0
	end
	state.TotalSeasonalCashEarned = math.max(math.floor(state.TotalSeasonalCashEarned + 0.5), 0)

	if type(state.TotalSeasonalExperienceEarned) ~= "number" then
		state.TotalSeasonalExperienceEarned = 0
	end
	state.TotalSeasonalExperienceEarned = math.max(math.floor(state.TotalSeasonalExperienceEarned + 0.5), 0)
end

local function ensureTestState(playerId)
	local key = tostring(playerId)
	local state = testStateByPlayerId[key]
	if not state then
		state = {
			CurrentSeason = "Spring",
			SeasonStartTime = 0,
			SeasonsCompleted = 0,
			ChallengeProgress = {},
			CompletedChallenges = {},
			ClaimedMilestones = {},
			TotalChallengesCompleted = 0,
			TotalSeasonalCashEarned = 0,
			TotalSeasonalExperienceEarned = 0,
		}
		testStateByPlayerId[key] = state
	end
	ensureStateShape(state)
	return state
end

local function getStateForPlayer(player)
	if player == nil then
		return nil
	end
	if not IS_ROBLOX then
		trackedTestPlayersByKey[tostring(player)] = player
	end
	return ensureTestState(player)
end

local function sendNotification(playerId, title, body, metadata)
	if SeasonalEventService._testNotifications then
		table.insert(SeasonalEventService._testNotifications, {
			PlayerId = playerId,
			Title = title,
			Body = body,
			Metadata = metadata or {},
		})
	end
	if notificationSink then
		notificationSink(playerId, title, body, metadata)
	end
end

local function getSeasonDef(seasonId)
	return seasonById[seasonId]
end

local function getNextSeason(seasonId)
	for i = 1, SEASON_COUNT do
		if SEASON_ORDER[i] == seasonId then
			local nextIndex = (i % SEASON_COUNT) + 1
			return SEASON_ORDER[nextIndex]
		end
	end
	return "Spring"
end

local function getMilestoneForCount(count)
	for _, milestone in ipairs(MILESTONES) do
		if milestone.SeasonsCompleted == count then
			return milestone
		end
	end
	return nil
end

--[=[
	Set the active season for a player. Resets seasonal challenge progress
	and increments seasons completed if transitioning from a previous season.

	@param player any -- Player identifier
	@param seasonId string -- Season to transition to ("Spring", "Summer", "Autumn", "Winter")
	@return table? -- Transition result, or nil on failure
	@return string? -- Error string on failure
]=]
function SeasonalEventService.TransitionSeason(player, seasonId)
	if player == nil then
		return nil, "InvalidPlayer"
	end

	local seasonDef = getSeasonDef(seasonId)
	if not seasonDef then
		return nil, "InvalidSeason"
	end

	local state = getStateForPlayer(player)
	if not state then
		return nil, "PlayerNotFound"
	end

	local previousSeason = state.CurrentSeason
	local isFirstSeason = state.SeasonStartTime == 0
	local wasTransition = previousSeason ~= seasonId or isFirstSeason

	-- If transitioning from a real previous season, increment completed count
	if not isFirstSeason and previousSeason ~= seasonId then
		state.SeasonsCompleted = state.SeasonsCompleted + 1
	end

	-- Reset seasonal challenge progress for the new season
	state.CurrentSeason = seasonId
	state.SeasonStartTime = getTime()
	state.ChallengeProgress = {}
	state.CompletedChallenges = {}

	-- Check for milestone
	local milestone = getMilestoneForCount(state.SeasonsCompleted)
	local milestoneUnlocked = nil
	if milestone and not state.ClaimedMilestones[tostring(milestone.SeasonsCompleted)] then
		state.ClaimedMilestones[tostring(milestone.SeasonsCompleted)] = true
		state.TotalSeasonalCashEarned = state.TotalSeasonalCashEarned + milestone.BonusCash
		state.TotalSeasonalExperienceEarned = state.TotalSeasonalExperienceEarned + milestone.BonusExperience
		milestoneUnlocked = milestone
	end

	local result = {
		PreviousSeason = previousSeason,
		NewSeason = seasonId,
		SeasonName = seasonDef.Name,
		SeasonsCompleted = state.SeasonsCompleted,
		WasTransition = wasTransition,
		MilestoneUnlocked = milestoneUnlocked and milestoneUnlocked.Label or nil,
		Buffs = seasonDef.Buffs,
		Challenges = seasonDef.Challenges,
	}

	-- Send notification for season transition
	if wasTransition then
		local notifBody = string.format("%s has begun! %s", seasonDef.Name, seasonDef.Description)
		if milestoneUnlocked then
			notifBody = notifBody .. string.format(" Milestone: %s!", milestoneUnlocked.Label)
		end
		sendNotification(player, "Season Change: " .. seasonDef.Name, notifBody, {
			Source = "SeasonalEventService",
			Season = seasonId,
			SeasonsCompleted = state.SeasonsCompleted,
		})
	end

	return result, nil
end

--[=[
	Record progress toward a seasonal challenge stat.

	@param player any -- Player identifier
	@param statKey string -- The challenge stat key to increment
	@param amount number? -- Amount to add (default 1)
	@return table? -- Updated challenge info if any challenge completed, or nil
]=]
function SeasonalEventService.RecordProgress(player, statKey, amount)
	if player == nil then
		return nil
	end
	if type(statKey) ~= "string" or #statKey == 0 then
		return nil
	end

	local state = getStateForPlayer(player)
	if not state then
		return nil
	end

	local increment = 1
	if type(amount) == "number" and amount > 0 then
		increment = math.max(1, math.floor(amount + 0.5))
	end

	-- Increment the stat
	local current = state.ChallengeProgress[statKey] or 0
	state.ChallengeProgress[statKey] = current + increment

	-- Check if any challenges for the current season are now completed
	local seasonDef = getSeasonDef(state.CurrentSeason)
	if not seasonDef then
		return nil
	end

	local newlyCompleted = {}
	for _, challenge in ipairs(seasonDef.Challenges) do
		if challenge.StatKey == statKey and not state.CompletedChallenges[challenge.Id] then
			local progress = state.ChallengeProgress[challenge.StatKey] or 0
			if progress >= challenge.TargetValue then
				state.CompletedChallenges[challenge.Id] = true
				state.TotalChallengesCompleted = state.TotalChallengesCompleted + 1
				state.TotalSeasonalCashEarned = state.TotalSeasonalCashEarned + challenge.RewardCash
				state.TotalSeasonalExperienceEarned = state.TotalSeasonalExperienceEarned + challenge.RewardExperience

				table.insert(newlyCompleted, {
					ChallengeId = challenge.Id,
					ChallengeName = challenge.Name,
					RewardCash = challenge.RewardCash,
					RewardExperience = challenge.RewardExperience,
				})

				-- Send notification
				sendNotification(player, "Challenge Complete!", string.format(
					"%s: +$%d, +%d XP",
					challenge.Name, challenge.RewardCash, challenge.RewardExperience
				), {
					Source = "SeasonalEventService",
					ChallengeId = challenge.Id,
					Season = state.CurrentSeason,
				})
			end
		end
	end

	if #newlyCompleted > 0 then
		return newlyCompleted
	end
	return nil
end

--[=[
	Get the current seasonal event status for a player.

	@param player any -- Player identifier
	@return table? -- Season status snapshot, or nil
]=]
function SeasonalEventService.GetStatus(player)
	local state = getStateForPlayer(player)
	if not state then
		return nil
	end

	local seasonDef = getSeasonDef(state.CurrentSeason)
	if not seasonDef then
		return nil
	end

	-- Build challenge progress list
	local challengeStatus = {}
	for _, challenge in ipairs(seasonDef.Challenges) do
		local progress = state.ChallengeProgress[challenge.StatKey] or 0
		local completed = state.CompletedChallenges[challenge.Id] == true
		table.insert(challengeStatus, {
			Id = challenge.Id,
			Name = challenge.Name,
			Description = challenge.Description,
			StatKey = challenge.StatKey,
			CurrentValue = progress,
			TargetValue = challenge.TargetValue,
			Completed = completed,
			RewardCash = challenge.RewardCash,
			RewardExperience = challenge.RewardExperience,
		})
	end

	return {
		CurrentSeason = state.CurrentSeason,
		SeasonName = seasonDef.Name,
		SeasonDescription = seasonDef.Description,
		Buffs = seasonDef.Buffs,
		Challenges = challengeStatus,
		SeasonsCompleted = state.SeasonsCompleted,
		TotalChallengesCompleted = state.TotalChallengesCompleted,
		TotalSeasonalCashEarned = state.TotalSeasonalCashEarned,
		TotalSeasonalExperienceEarned = state.TotalSeasonalExperienceEarned,
		SeasonStartTime = state.SeasonStartTime,
	}
end

--[=[
	Get the active buffs for a player's current season.

	@param player any -- Player identifier
	@return table -- Array of active buff descriptors
]=]
function SeasonalEventService.GetActiveBuffs(player)
	local state = getStateForPlayer(player)
	if not state then
		return {}
	end

	local seasonDef = getSeasonDef(state.CurrentSeason)
	if not seasonDef then
		return {}
	end

	-- Return a copy
	local buffs = {}
	for _, buff in ipairs(seasonDef.Buffs) do
		table.insert(buffs, {
			Type = buff.Type,
			Value = buff.Value,
			Label = buff.Label,
		})
	end
	return buffs
end

--[=[
	Get a specific buff multiplier value for the player's current season.
	Returns 1.0 if no matching buff is active (no modification).

	@param player any -- Player identifier
	@param buffType string -- Buff type to look up ("XPMultiplier", "CashMultiplier", etc.)
	@return number -- The multiplier value (1.0 = no buff)
]=]
function SeasonalEventService.GetBuffMultiplier(player, buffType)
	if player == nil or type(buffType) ~= "string" then
		return 1.0
	end

	local state = getStateForPlayer(player)
	if not state then
		return 1.0
	end

	local seasonDef = getSeasonDef(state.CurrentSeason)
	if not seasonDef then
		return 1.0
	end

	for _, buff in ipairs(seasonDef.Buffs) do
		if buff.Type == buffType then
			return buff.Value
		end
	end

	return 1.0
end

--[=[
	Get the challenge progress for a specific challenge in the current season.

	@param player any -- Player identifier
	@param challengeId string -- Challenge identifier
	@return table? -- Progress info, or nil if not in current season
]=]
function SeasonalEventService.GetChallengeProgress(player, challengeId)
	if player == nil or type(challengeId) ~= "string" then
		return nil
	end

	local state = getStateForPlayer(player)
	if not state then
		return nil
	end

	local seasonDef = getSeasonDef(state.CurrentSeason)
	if not seasonDef then
		return nil
	end

	for _, challenge in ipairs(seasonDef.Challenges) do
		if challenge.Id == challengeId then
			local progress = state.ChallengeProgress[challenge.StatKey] or 0
			return {
				Id = challenge.Id,
				Name = challenge.Name,
				CurrentValue = progress,
				TargetValue = challenge.TargetValue,
				Completed = state.CompletedChallenges[challenge.Id] == true,
			}
		end
	end

	return nil
end

--[=[
	Get the next season in the cycle after the player's current season.

	@param player any -- Player identifier
	@return string? -- Next season ID, or nil
]=]
function SeasonalEventService.GetNextSeason(player)
	local state = getStateForPlayer(player)
	if not state then
		return nil
	end
	return getNextSeason(state.CurrentSeason)
end

--[=[
	Get all available season definitions.

	@return table -- Array of season definitions
]=]
function SeasonalEventService.GetAllSeasons()
	local result = {}
	for _, season in ipairs(SEASONS) do
		table.insert(result, {
			Id = season.Id,
			Name = season.Name,
			Description = season.Description,
			DurationDays = season.DurationDays,
			BuffCount = #season.Buffs,
			ChallengeCount = #season.Challenges,
		})
	end
	return result
end

--[=[
	Get milestone info for a given completion count.

	@param count number -- Number of seasons completed
	@return table? -- Milestone info or nil
]=]
function SeasonalEventService.GetMilestoneForCount(count)
	return getMilestoneForCount(count)
end

local function getActivePlayers()
	if IS_ROBLOX and Players then
		return Players:GetPlayers()
	end

	local players = {}
	for _, player in pairs(trackedTestPlayersByKey) do
		table.insert(players, player)
	end
	return players
end

--[=[
	Apply a weather-driven season change to all active players.

	@param seasonId string -- Weather season ID
	@return number -- Number of transitioned players
	@return string? -- Error string when season is invalid
]=]
function SeasonalEventService.HandleWeatherSeasonChanged(seasonId)
	if not getSeasonDef(seasonId) then
		return 0, "InvalidSeason"
	end

	local transitioned = 0
	for _, player in ipairs(getActivePlayers()) do
		local result = SeasonalEventService.TransitionSeason(player, seasonId)
		if result then
			transitioned = transitioned + 1
		end
	end

	return transitioned, nil
end

-- ============ Init (Roblox/Test wiring) ============

function SeasonalEventService.Init(weatherService)
	weatherInitToken = weatherInitToken + 1
	local initToken = weatherInitToken

	weatherServiceRef = weatherService
	if not weatherServiceRef and IS_ROBLOX then
		local ok, resolvedWeatherService = pcall(function()
			local ServerScriptService = game:GetService("ServerScriptService")
			return require(ServerScriptService.Server.Services.WeatherService)
		end)
		if ok then
			weatherServiceRef = resolvedWeatherService
		end
	end

	if not weatherServiceRef then
		return
	end

	local weatherState = nil
	if type(weatherServiceRef.GetState) == "function" then
		local ok, state = pcall(weatherServiceRef.GetState)
		if ok and type(state) == "table" then
			weatherState = state
		end
	end
	if weatherState and type(weatherState.Season) == "string" then
		SeasonalEventService.HandleWeatherSeasonChanged(weatherState.Season)
	end

	if type(weatherServiceRef.SubscribeSeasonChanged) == "function" then
		weatherServiceRef.SubscribeSeasonChanged("SeasonalEventService", function(newSeason)
			-- Ignore stale callbacks if Init is called again.
			if initToken ~= weatherInitToken then
				return
			end
			if type(newSeason) ~= "string" then
				return
			end
			SeasonalEventService.HandleWeatherSeasonChanged(newSeason)
		end)
	end

	if IS_ROBLOX and Players then
		Players.PlayerAdded:Connect(function(player)
			task.defer(function()
				if initToken ~= weatherInitToken then
					return
				end
				local currentSeason = "Spring"
				if type(weatherServiceRef.GetState) == "function" then
					local ok, state = pcall(weatherServiceRef.GetState)
					if ok and type(state) == "table" and type(state.Season) == "string" then
						currentSeason = state.Season
					end
				end
				SeasonalEventService.TransitionSeason(player, currentSeason)
			end)
		end)
	end
end

-- ============ Test Hooks ============

function SeasonalEventService._ResetForTests()
	testStateByPlayerId = {}
	trackedTestPlayersByKey = {}
	SeasonalEventService._testNotifications = {}
	weatherServiceRef = nil
	weatherInitToken = weatherInitToken + 1
end

function SeasonalEventService._SetClock(fn)
	if type(fn) == "function" then
		clockFn = fn
	else
		clockFn = os.time
	end
end

function SeasonalEventService._SetNotificationSink(fn)
	if type(fn) == "function" then
		notificationSink = fn
	else
		notificationSink = nil
	end
end

function SeasonalEventService._GetConstants()
	return {
		SeasonOrder = SEASON_ORDER,
		SeasonCount = SEASON_COUNT,
		Milestones = MILESTONES,
	}
end

-- Initialize test notifications table
SeasonalEventService._testNotifications = {}

return SeasonalEventService
