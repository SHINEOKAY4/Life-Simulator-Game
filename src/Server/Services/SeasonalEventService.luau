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
local SeasonalEventPackets = nil
local AchievementService = nil
if IS_ROBLOX then
	Players = game:GetService("Players")
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local ServerScriptService = game:GetService("ServerScriptService")
	SeasonalEventPackets = require(ReplicatedStorage.Network.SeasonalEventPackets)
	AchievementService = require(ServerScriptService.Server.Services.AchievementService)
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
local activeDistributionsByPlayerKey = {}

-- Notification sink (injectable for tests)
local notificationSink = nil
local weatherServiceRef = nil
local weatherInitToken = 0

-- Achievement recording helper: forwards to AchievementService in Roblox,
-- or to an injectable sink in test mode.
local achievementSink = nil

local function recordAchievementSeasonalChallenge(player)
	if IS_ROBLOX and AchievementService then
		AchievementService.RecordSeasonalChallengeCompleted(player)
	elseif achievementSink then
		achievementSink(player, "SeasonalChallengesCompleted", 1)
	end
end

local function recordAchievementSeasonCompleted(player, totalSeasonsCompleted)
	if IS_ROBLOX and AchievementService then
		AchievementService.RecordSeasonCompleted(player, totalSeasonsCompleted)
	elseif achievementSink then
		achievementSink(player, "SeasonsCompleted", totalSeasonsCompleted)
	end
end

local function pushSeasonTransition(player, result)
	if not IS_ROBLOX or not SeasonalEventPackets then
		return
	end
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return
	end
	if type(result) ~= "table" then
		return
	end

	SeasonalEventPackets.SeasonTransitioned:FireClient(player, {
		PreviousSeason = tostring(result.PreviousSeason or ""),
		NewSeason = tostring(result.NewSeason or ""),
		SeasonName = tostring(result.SeasonName or ""),
		SeasonsCompleted = math.max(0, math.floor(tonumber(result.SeasonsCompleted) or 0)),
		WasTransition = result.WasTransition == true,
	})
end

local function pushChallengeCompleted(player, challenge)
	if not IS_ROBLOX or not SeasonalEventPackets then
		return
	end
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return
	end
	if type(challenge) ~= "table" then
		return
	end

	SeasonalEventPackets.ChallengeCompleted:FireClient(player, {
		Id = tostring(challenge.Id or ""),
		Name = tostring(challenge.Name or ""),
		Description = tostring(challenge.Description or ""),
		StatKey = tostring(challenge.StatKey or ""),
		CurrentValue = math.max(0, math.floor(tonumber(challenge.CurrentValue) or 0)),
		TargetValue = math.max(0, math.floor(tonumber(challenge.TargetValue) or 0)),
		Completed = challenge.Completed == true,
		RewardCash = math.max(0, math.floor(tonumber(challenge.RewardCash) or 0)),
		RewardExperience = math.max(0, math.floor(tonumber(challenge.RewardExperience) or 0)),
	})
end

-- Injectable reward executor (swapped in tests to simulate failures)
local rewardExecutor = nil

local function defaultRewardExecutor(playerId, cashAmount, xpAmount, source)
	-- In Roblox this would call CurrencyService.Add / ProgressionService.AwardExperience.
	-- Returns true on success, false + error on failure.
	return true, nil
end

local function executeReward(playerId, cashAmount, xpAmount, source)
	local executor = rewardExecutor or defaultRewardExecutor
	return executor(playerId, cashAmount, xpAmount, source)
end

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
	if type(state.ClaimedChallengeRewards) ~= "table" then
		state.ClaimedChallengeRewards = {}
	end
	if type(state.ClaimedMilestoneRewards) ~= "table" then
		state.ClaimedMilestoneRewards = {}
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

	if type(state.TotalCashDistributed) ~= "number" then
		state.TotalCashDistributed = 0
	end
	state.TotalCashDistributed = math.max(math.floor(state.TotalCashDistributed + 0.5), 0)

	if type(state.TotalExperienceDistributed) ~= "number" then
		state.TotalExperienceDistributed = 0
	end
	state.TotalExperienceDistributed = math.max(math.floor(state.TotalExperienceDistributed + 0.5), 0)
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
			ClaimedChallengeRewards = {},
			ClaimedMilestoneRewards = {},
			TotalChallengesCompleted = 0,
			TotalSeasonalCashEarned = 0,
			TotalSeasonalExperienceEarned = 0,
			TotalCashDistributed = 0,
			TotalExperienceDistributed = 0,
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
		-- Record season completion toward seasonal achievements
		recordAchievementSeasonCompleted(player, state.SeasonsCompleted)
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

	pushSeasonTransition(player, result)

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

				-- Record toward seasonal achievements
				recordAchievementSeasonalChallenge(player)

				pushChallengeCompleted(player, {
					Id = challenge.Id,
					Name = challenge.Name,
					Description = challenge.Description,
					StatKey = challenge.StatKey,
					CurrentValue = math.min(progress, challenge.TargetValue),
					TargetValue = challenge.TargetValue,
					Completed = true,
					RewardCash = challenge.RewardCash,
					RewardExperience = challenge.RewardExperience,
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
		local rewardClaimed = state.ClaimedChallengeRewards[challenge.Id] == true
		table.insert(challengeStatus, {
			Id = challenge.Id,
			Name = challenge.Name,
			Description = challenge.Description,
			StatKey = challenge.StatKey,
			CurrentValue = progress,
			TargetValue = challenge.TargetValue,
			Completed = completed,
			RewardClaimed = rewardClaimed,
			RewardCash = challenge.RewardCash,
			RewardExperience = challenge.RewardExperience,
		})
	end

	local claimedMilestonesCount = 0
	for _ in pairs(state.ClaimedMilestones) do
		claimedMilestonesCount = claimedMilestonesCount + 1
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
		TotalCashDistributed = state.TotalCashDistributed,
		TotalExperienceDistributed = state.TotalExperienceDistributed,
		SeasonStartTime = state.SeasonStartTime,
		ClaimedMilestonesCount = claimedMilestonesCount,
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

--[=[
	Claim the reward for a completed seasonal challenge. Validates that the
	challenge exists, belongs to the current season, is completed, and hasn't
	already had its reward claimed. Distributes cash and XP via the reward
	executor, rolling back state on failure.

	@param player any -- Player identifier
	@param challengeId string -- Challenge identifier to claim
	@return table? -- Claim result, or nil on failure
	@return string? -- Error string on failure
]=]
function SeasonalEventService.ClaimChallengeReward(player, challengeId)
	if player == nil then
		return nil, "InvalidPlayer"
	end
	if type(challengeId) ~= "string" or #challengeId == 0 then
		return nil, "InvalidChallengeId"
	end

	local state = getStateForPlayer(player)
	if not state then
		return nil, "PlayerNotFound"
	end

	-- Validate the challenge exists and belongs to the current season
	local seasonDef = getSeasonDef(state.CurrentSeason)
	if not seasonDef then
		return nil, "InvalidSeason"
	end

	local challengeDef = nil
	for _, challenge in ipairs(seasonDef.Challenges) do
		if challenge.Id == challengeId then
			challengeDef = challenge
			break
		end
	end

	if not challengeDef then
		return nil, "ChallengeNotInSeason"
	end

	-- Validate the challenge is completed
	if not state.CompletedChallenges[challengeId] then
		return nil, "ChallengeNotCompleted"
	end

	-- Validate the reward hasn't already been claimed
	if state.ClaimedChallengeRewards[challengeId] then
		return nil, "RewardAlreadyClaimed"
	end

	local cashReward = challengeDef.RewardCash
	local xpReward = challengeDef.RewardExperience

	-- Execute the reward distribution
	local ok, execErr = executeReward(player, cashReward, xpReward, "SeasonalChallenge:" .. challengeId)
	if not ok then
		-- Distribution failed: do NOT mark as claimed, state is unchanged
		return nil, "DistributionFailed"
	end

	-- Mark as claimed and update distributed totals
	state.ClaimedChallengeRewards[challengeId] = true
	state.TotalCashDistributed = state.TotalCashDistributed + cashReward
	state.TotalExperienceDistributed = state.TotalExperienceDistributed + xpReward

	-- Send notification
	sendNotification(player, "Reward Claimed!", string.format(
		"%s: +$%d, +%d XP distributed",
		challengeDef.Name, cashReward, xpReward
	), {
		Source = "SeasonalEventService",
		ChallengeId = challengeId,
		Season = state.CurrentSeason,
		Type = "RewardClaimed",
	})

	return {
		ChallengeId = challengeId,
		ChallengeName = challengeDef.Name,
		CashDistributed = cashReward,
		ExperienceDistributed = xpReward,
		TotalCashDistributed = state.TotalCashDistributed,
		TotalExperienceDistributed = state.TotalExperienceDistributed,
	}, nil
end

--[=[
	Claim a seasonal milestone reward. Validates that the milestone exists,
	has been reached, and hasn't already had its reward claimed.

	@param player any -- Player identifier
	@param seasonsCompleted number -- The milestone threshold to claim (e.g. 4, 8, 20)
	@return table? -- Claim result, or nil on failure
	@return string? -- Error string on failure
]=]
function SeasonalEventService.ClaimMilestoneReward(player, seasonsCompleted)
	if player == nil then
		return nil, "InvalidPlayer"
	end
	if type(seasonsCompleted) ~= "number" then
		return nil, "InvalidMilestoneCount"
	end
	seasonsCompleted = math.floor(seasonsCompleted + 0.5)

	local state = getStateForPlayer(player)
	if not state then
		return nil, "PlayerNotFound"
	end

	-- Validate the milestone exists
	local milestone = getMilestoneForCount(seasonsCompleted)
	if not milestone then
		return nil, "MilestoneNotFound"
	end

	-- Validate the player has reached this milestone
	if state.SeasonsCompleted < seasonsCompleted then
		return nil, "MilestoneNotReached"
	end

	-- Validate the milestone hasn't been claimed (as reward)
	local milestoneKey = tostring(seasonsCompleted)
	if state.ClaimedMilestoneRewards[milestoneKey] then
		return nil, "RewardAlreadyClaimed"
	end

	local cashReward = milestone.BonusCash
	local xpReward = milestone.BonusExperience

	-- Execute the reward distribution
	local ok, execErr = executeReward(player, cashReward, xpReward, "SeasonalMilestone:" .. milestoneKey)
	if not ok then
		return nil, "DistributionFailed"
	end

	-- Mark as claimed and update distributed totals
	state.ClaimedMilestoneRewards[milestoneKey] = true
	state.TotalCashDistributed = state.TotalCashDistributed + cashReward
	state.TotalExperienceDistributed = state.TotalExperienceDistributed + xpReward

	-- Send notification
	sendNotification(player, "Milestone Reward!", string.format(
		"%s: +$%d, +%d XP distributed",
		milestone.Label, cashReward, xpReward
	), {
		Source = "SeasonalEventService",
		Milestone = milestoneKey,
		Type = "MilestoneRewardClaimed",
	})

	return {
		MilestoneLabel = milestone.Label,
		SeasonsRequired = seasonsCompleted,
		CashDistributed = cashReward,
		ExperienceDistributed = xpReward,
		TotalCashDistributed = state.TotalCashDistributed,
		TotalExperienceDistributed = state.TotalExperienceDistributed,
	}, nil
end

--[=[
	Distribute all pending (unclaimed) rewards for a player in a single batch.
	This includes completed-but-unclaimed challenge rewards and reached-but-
	unclaimed milestone rewards. Uses all-or-nothing semantics: if any single
	reward distribution fails, all previously distributed rewards in this batch
	are rolled back and the function returns an error.

	@param player any -- Player identifier
	@return table? -- Distribution summary, or nil on failure
	@return string? -- Error string on failure
]=]
function SeasonalEventService.DistributeSeasonRewards(player)
	if player == nil then
		return nil, "InvalidPlayer"
	end

	local playerKey = tostring(player)
	if activeDistributionsByPlayerKey[playerKey] then
		return nil, "DistributionInProgress"
	end
	activeDistributionsByPlayerKey[playerKey] = true

	local function finish(result, err)
		activeDistributionsByPlayerKey[playerKey] = nil
		return result, err
	end

	local state = getStateForPlayer(player)
	if not state then
		return finish(nil, "PlayerNotFound")
	end

	local seasonDef = getSeasonDef(state.CurrentSeason)
	if not seasonDef then
		return finish(nil, "InvalidSeason")
	end

	-- Collect all pending challenge rewards
	local pendingChallenges = {}
	for _, challenge in ipairs(seasonDef.Challenges) do
		if state.CompletedChallenges[challenge.Id] and not state.ClaimedChallengeRewards[challenge.Id] then
			table.insert(pendingChallenges, challenge)
		end
	end

	-- Collect all pending milestone rewards
	local pendingMilestones = {}
	for _, milestone in ipairs(MILESTONES) do
		local key = tostring(milestone.SeasonsCompleted)
		if state.SeasonsCompleted >= milestone.SeasonsCompleted
			and state.ClaimedMilestones[key]
			and not state.ClaimedMilestoneRewards[key] then
			table.insert(pendingMilestones, milestone)
		end
	end

	-- Nothing to distribute
	if #pendingChallenges == 0 and #pendingMilestones == 0 then
		return finish({
			ChallengesDistributed = 0,
			MilestonesDistributed = 0,
			TotalCashDistributed = 0,
			TotalExperienceDistributed = 0,
			Details = {},
		}, nil)
	end

	-- Distribute rewards one by one, tracking what was granted for rollback
	local distributed = {} -- { { type, id, cash, xp } }
	local totalCash = 0
	local totalXP = 0

	-- Distribute challenge rewards
	for _, challenge in ipairs(pendingChallenges) do
		local ok, execErr = executeReward(
			player, challenge.RewardCash, challenge.RewardExperience,
			"SeasonalChallenge:" .. challenge.Id
		)
		if not ok then
			-- Rollback all previously distributed rewards in this batch
			for i = #distributed, 1, -1 do
				local entry = distributed[i]
				-- Reverse the reward: execute a negative grant (via reversal executor)
				executeReward(player, -entry.cash, -entry.xp, "Rollback:" .. entry.id)
				-- Unmark as claimed
				if entry.rewardType == "challenge" then
					state.ClaimedChallengeRewards[entry.id] = nil
				elseif entry.rewardType == "milestone" then
					state.ClaimedMilestoneRewards[entry.id] = nil
				end
				state.TotalCashDistributed = state.TotalCashDistributed - entry.cash
				state.TotalExperienceDistributed = state.TotalExperienceDistributed - entry.xp
			end
			return finish(nil, "DistributionFailed")
		end

		state.ClaimedChallengeRewards[challenge.Id] = true
		state.TotalCashDistributed = state.TotalCashDistributed + challenge.RewardCash
		state.TotalExperienceDistributed = state.TotalExperienceDistributed + challenge.RewardExperience
		totalCash = totalCash + challenge.RewardCash
		totalXP = totalXP + challenge.RewardExperience
		table.insert(distributed, {
			rewardType = "challenge",
			id = challenge.Id,
			name = challenge.Name,
			cash = challenge.RewardCash,
			xp = challenge.RewardExperience,
		})
	end

	-- Distribute milestone rewards
	for _, milestone in ipairs(pendingMilestones) do
		local key = tostring(milestone.SeasonsCompleted)
		local ok, execErr = executeReward(
			player, milestone.BonusCash, milestone.BonusExperience,
			"SeasonalMilestone:" .. key
		)
		if not ok then
			-- Rollback all previously distributed rewards in this batch
			for i = #distributed, 1, -1 do
				local entry = distributed[i]
				executeReward(player, -entry.cash, -entry.xp, "Rollback:" .. entry.id)
				if entry.rewardType == "challenge" then
					state.ClaimedChallengeRewards[entry.id] = nil
				elseif entry.rewardType == "milestone" then
					state.ClaimedMilestoneRewards[entry.id] = nil
				end
				state.TotalCashDistributed = state.TotalCashDistributed - entry.cash
				state.TotalExperienceDistributed = state.TotalExperienceDistributed - entry.xp
			end
			return finish(nil, "DistributionFailed")
		end

		state.ClaimedMilestoneRewards[key] = true
		state.TotalCashDistributed = state.TotalCashDistributed + milestone.BonusCash
		state.TotalExperienceDistributed = state.TotalExperienceDistributed + milestone.BonusExperience
		totalCash = totalCash + milestone.BonusCash
		totalXP = totalXP + milestone.BonusExperience
		table.insert(distributed, {
			rewardType = "milestone",
			id = key,
			name = milestone.Label,
			cash = milestone.BonusCash,
			xp = milestone.BonusExperience,
		})
	end

	-- Build details list
	local details = {}
	for _, entry in ipairs(distributed) do
		table.insert(details, {
			Type = entry.rewardType,
			Id = entry.id,
			Name = entry.name,
			CashDistributed = entry.cash,
			ExperienceDistributed = entry.xp,
		})
	end

	-- Send summary notification
	local challengeCount = 0
	local milestoneCount = 0
	for _, entry in ipairs(distributed) do
		if entry.rewardType == "challenge" then
			challengeCount = challengeCount + 1
		else
			milestoneCount = milestoneCount + 1
		end
	end

	sendNotification(player, "Rewards Distributed!", string.format(
		"%d reward(s) distributed: +$%d, +%d XP",
		#distributed, totalCash, totalXP
	), {
		Source = "SeasonalEventService",
		Type = "BatchDistribution",
		ChallengesDistributed = challengeCount,
		MilestonesDistributed = milestoneCount,
	})

	return finish({
		ChallengesDistributed = challengeCount,
		MilestonesDistributed = milestoneCount,
		TotalCashDistributed = totalCash,
		TotalExperienceDistributed = totalXP,
		Details = details,
	}, nil)
end

--[=[
	Get the list of pending (unclaimed) rewards for a player.

	@param player any -- Player identifier
	@return table? -- Pending rewards summary, or nil
]=]
function SeasonalEventService.GetPendingRewards(player)
	if player == nil then
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

	local pendingChallenges = {}
	for _, challenge in ipairs(seasonDef.Challenges) do
		if state.CompletedChallenges[challenge.Id] and not state.ClaimedChallengeRewards[challenge.Id] then
			table.insert(pendingChallenges, {
				Id = challenge.Id,
				Name = challenge.Name,
				RewardCash = challenge.RewardCash,
				RewardExperience = challenge.RewardExperience,
			})
		end
	end

	local pendingMilestones = {}
	for _, milestone in ipairs(MILESTONES) do
		local key = tostring(milestone.SeasonsCompleted)
		if state.SeasonsCompleted >= milestone.SeasonsCompleted
			and state.ClaimedMilestones[key]
			and not state.ClaimedMilestoneRewards[key] then
			table.insert(pendingMilestones, {
				SeasonsRequired = milestone.SeasonsCompleted,
				Label = milestone.Label,
				BonusCash = milestone.BonusCash,
				BonusExperience = milestone.BonusExperience,
			})
		end
	end

	return {
		Challenges = pendingChallenges,
		Milestones = pendingMilestones,
		TotalPendingCash = (function()
			local total = 0
			for _, c in ipairs(pendingChallenges) do total = total + c.RewardCash end
			for _, m in ipairs(pendingMilestones) do total = total + m.BonusCash end
			return total
		end)(),
		TotalPendingExperience = (function()
			local total = 0
			for _, c in ipairs(pendingChallenges) do total = total + c.RewardExperience end
			for _, m in ipairs(pendingMilestones) do total = total + m.BonusExperience end
			return total
		end)(),
	}
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
	if IS_ROBLOX and SeasonalEventPackets then
		SeasonalEventPackets.GetSeasonStatus.OnServerInvoke = function(player)
			return SeasonalEventService.GetStatus(player)
		end

		SeasonalEventPackets.ClaimChallengeReward.OnServerInvoke = function(player, data)
			local challengeId = data and data.ChallengeId or ""
			local result, err = SeasonalEventService.ClaimChallengeReward(player, challengeId)
			if not result then
				return {
					Success = false,
					CashDistributed = 0,
					ExperienceDistributed = 0,
					RewardName = "",
					ErrorMessage = err or "Unknown",
				}
			end
			return {
				Success = true,
				CashDistributed = result.CashDistributed,
				ExperienceDistributed = result.ExperienceDistributed,
				RewardName = result.ChallengeName,
				ErrorMessage = "",
			}
		end

		SeasonalEventPackets.ClaimMilestoneReward.OnServerInvoke = function(player, data)
			local seasonsCompleted = data and data.SeasonsCompleted or 0
			local result, err = SeasonalEventService.ClaimMilestoneReward(player, seasonsCompleted)
			if not result then
				return {
					Success = false,
					CashDistributed = 0,
					ExperienceDistributed = 0,
					RewardName = "",
					ErrorMessage = err or "Unknown",
				}
			end
			return {
				Success = true,
				CashDistributed = result.CashDistributed,
				ExperienceDistributed = result.ExperienceDistributed,
				RewardName = result.MilestoneLabel,
				ErrorMessage = "",
			}
		end

		SeasonalEventPackets.DistributeAllRewards.OnServerInvoke = function(player)
			local result, err = SeasonalEventService.DistributeSeasonRewards(player)
			if not result then
				return {
					Success = false,
					CashDistributed = 0,
					ExperienceDistributed = 0,
					RewardName = "",
					ErrorMessage = err or "Unknown",
				}
			end
			return {
				Success = true,
				CashDistributed = result.TotalCashDistributed,
				ExperienceDistributed = result.TotalExperienceDistributed,
				RewardName = string.format("%d rewards", result.ChallengesDistributed + result.MilestonesDistributed),
				ErrorMessage = "",
			}
		end
	end

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
	activeDistributionsByPlayerKey = {}
	SeasonalEventService._testNotifications = {}
	weatherServiceRef = nil
	weatherInitToken = weatherInitToken + 1
	rewardExecutor = nil
	achievementSink = nil
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

function SeasonalEventService._SetRewardExecutor(fn)
	if type(fn) == "function" then
		rewardExecutor = fn
	else
		rewardExecutor = nil
	end
end

function SeasonalEventService._SetAchievementSink(fn)
	if type(fn) == "function" then
		achievementSink = fn
	else
		achievementSink = nil
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
