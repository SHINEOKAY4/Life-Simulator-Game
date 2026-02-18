-- ReputationService: social reputation trust tiers, rankings, and tier rewards.
-- Works both in Roblox runtime and in Busted tests loaded via loadfile().

local function hasRobloxRuntime()
	if type(game) ~= "userdata" and type(game) ~= "table" then
		return false
	end
	return pcall(function()
		return game:GetService("Players")
	end)
end

local function valueType(value)
	if type(typeof) == "function" then
		return typeof(value)
	end
	return type(value)
end

local function clamp(value, minimum, maximum)
	if value < minimum then
		return minimum
	end
	if value > maximum then
		return maximum
	end
	return value
end

local IS_ROBLOX = hasRobloxRuntime()
local Players = nil
local PlayerSession = nil
local CurrencyService = nil
local ReputationPackets = nil

if IS_ROBLOX then
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local ServerScriptService = game:GetService("ServerScriptService")
	Players = game:GetService("Players")

	ReputationPackets = require(ReplicatedStorage.Network.ReputationPackets)
	PlayerSession = require(ServerScriptService.Server.Services.PlayerSession)
	CurrencyService = require(ServerScriptService.Server.Services.CurrencyService)
end

local ReputationService = {}

local BASE_REPUTATION = 50
local MIN_REPUTATION = 0
local MAX_REPUTATION = 100
local MAX_RANKINGS = 10

local TRUST_TIERS = {
	{ Min = 0, Name = "Unknown", RewardMultiplier = 1.00, UnlockReward = 0 },
	{ Min = 25, Name = "Familiar", RewardMultiplier = 1.05, UnlockReward = 50 },
	{ Min = 50, Name = "Trusted", RewardMultiplier = 1.10, UnlockReward = 125 },
	{ Min = 75, Name = "Elite", RewardMultiplier = 1.20, UnlockReward = 250 },
}

local INTERACTION_RULES = {
	GreetResident = { MinTrustLevel = "Unknown", SuccessDelta = 2, FailureDelta = -1, NeutralDelta = 0 },
	TradeNegotiation = { MinTrustLevel = "Familiar", SuccessDelta = 4, FailureDelta = -3, NeutralDelta = 0 },
	ConflictMediation = { MinTrustLevel = "Trusted", SuccessDelta = 6, FailureDelta = -5, NeutralDelta = 0 },
}

local testStateByPlayerId = {}

local function getTierIndex(score)
	local index = 1
	for i = #TRUST_TIERS, 1, -1 do
		if score >= TRUST_TIERS[i].Min then
			index = i
			break
		end
	end
	return index
end

local function ensureStateShape(state)
	if type(state.ReputationScore) ~= "number" then
		state.ReputationScore = BASE_REPUTATION
	end
	state.ReputationScore = clamp(math.floor(state.ReputationScore + 0.5), MIN_REPUTATION, MAX_REPUTATION)

	if type(state.HighestTierUnlocked) ~= "number" then
		state.HighestTierUnlocked = getTierIndex(state.ReputationScore)
	end
	state.HighestTierUnlocked = clamp(math.floor(state.HighestTierUnlocked + 0.5), 1, #TRUST_TIERS)

	if type(state.LifetimeRewards) ~= "number" then
		state.LifetimeRewards = 0
	end
	state.LifetimeRewards = math.max(math.floor(state.LifetimeRewards + 0.5), 0)
end

local function getTierIndexByName(name)
	local target = tostring(name or "")
	for index, tier in ipairs(TRUST_TIERS) do
		if tier.Name == target then
			return index
		end
	end
	return 1
end

local function ensureTestState(playerId)
	local key = tostring(playerId)
	local state = testStateByPlayerId[key]
	if not state then
		state = {
			ReputationScore = BASE_REPUTATION,
			HighestTierUnlocked = getTierIndex(BASE_REPUTATION),
			LifetimeRewards = 0,
		}
		testStateByPlayerId[key] = state
	end
	ensureStateShape(state)
	return state
end

local function getStateForPlayer(player)
	if IS_ROBLOX and valueType(player) == "Instance" and player:IsA("Player") then
		local state = PlayerSession.TryGetData(player, "ReputationState")
		if not state then
			state = PlayerSession.GetData(player, "ReputationState")
		end
		if not state then
			state = PlayerSession.GetDataAwait(player, "ReputationState")
		end
		if state then
			ensureStateShape(state)
		end
		return state
	end
	return ensureTestState(player)
end

local function buildSnapshot(state)
	local tierIndex = getTierIndex(state.ReputationScore)
	local tier = TRUST_TIERS[tierIndex]
	local nextTier = TRUST_TIERS[tierIndex + 1]
	local pointsToNext = 0
	local nextTierName = "MAX"
	if nextTier then
		nextTierName = nextTier.Name
		pointsToNext = math.max(nextTier.Min - state.ReputationScore, 0)
	end

	return {
		ReputationScore = state.ReputationScore,
		TrustLevel = tier.Name,
		RewardMultiplier = tier.RewardMultiplier,
		NextTrustLevel = nextTierName,
		PointsToNextLevel = pointsToNext,
	}
end

local function buildRankingEntries(localPlayerId)
	local entries = {}

	if IS_ROBLOX then
		for _, player in ipairs(Players:GetPlayers()) do
			local state = getStateForPlayer(player)
			if state then
				table.insert(entries, {
					PlayerId = player.UserId,
					PlayerName = player.Name,
					Score = state.ReputationScore,
					TrustLevel = TRUST_TIERS[getTierIndex(state.ReputationScore)].Name,
				})
			end
		end
	else
		for playerId, state in pairs(testStateByPlayerId) do
			ensureStateShape(state)
			table.insert(entries, {
				PlayerId = playerId,
				PlayerName = tostring(playerId),
				Score = state.ReputationScore,
				TrustLevel = TRUST_TIERS[getTierIndex(state.ReputationScore)].Name,
			})
		end
	end

	table.sort(entries, function(a, b)
		if a.Score == b.Score then
			return a.PlayerName < b.PlayerName
		end
		return a.Score > b.Score
	end)

	local rankings = {}
	local playerRank = 0
	for index, entry in ipairs(entries) do
		if tostring(entry.PlayerId) == tostring(localPlayerId) then
			playerRank = index
		end
		if index <= MAX_RANKINGS then
			table.insert(rankings, {
				Rank = index,
				PlayerName = entry.PlayerName,
				ReputationScore = entry.Score,
				TrustLevel = entry.TrustLevel,
				IsLocalPlayer = tostring(entry.PlayerId) == tostring(localPlayerId),
			})
		end
	end

	return rankings, playerRank
end

local function grantTierRewards(player, state, oldTierIndex, newTierIndex)
	if newTierIndex <= oldTierIndex then
		return 0
	end

	local highestUnlocked = state.HighestTierUnlocked
	if newTierIndex <= highestUnlocked then
		return 0
	end

	local reward = 0
	for i = highestUnlocked + 1, newTierIndex do
		reward = reward + TRUST_TIERS[i].UnlockReward
	end

	if reward > 0 then
		state.HighestTierUnlocked = newTierIndex
		state.LifetimeRewards = state.LifetimeRewards + reward

		if IS_ROBLOX and valueType(player) == "Instance" and player:IsA("Player") then
			local currencyState = PlayerSession.TryGetData(player, "CurrencyState")
			if not currencyState then
				currencyState = PlayerSession.GetData(player, "CurrencyState")
			end
			if currencyState then
				CurrencyService.Add(player, "Cash", reward, currencyState, { Source = "ReputationTierReward" })
			end
		end
	end

	return reward
end

local function pushUpdate(player)
	if not IS_ROBLOX then
		return
	end
	local payload = ReputationService.GetReputationData(player)
	if payload then
		ReputationPackets.ReputationUpdated:FireClient(player, payload)
	end
end

function ReputationService.GetTrustLevel(score)
	local sanitized = clamp(math.floor((tonumber(score) or 0) + 0.5), MIN_REPUTATION, MAX_REPUTATION)
	return TRUST_TIERS[getTierIndex(sanitized)].Name
end

function ReputationService.GetRewardMultiplier(score)
	local sanitized = clamp(math.floor((tonumber(score) or 0) + 0.5), MIN_REPUTATION, MAX_REPUTATION)
	return TRUST_TIERS[getTierIndex(sanitized)].RewardMultiplier
end

function ReputationService.GetReputationData(player)
	local state = getStateForPlayer(player)
	if not state then
		return nil
	end

	local playerId = nil
	if IS_ROBLOX and valueType(player) == "Instance" and player:IsA("Player") then
		playerId = player.UserId
	else
		playerId = player
	end

	local rankings, playerRank = buildRankingEntries(playerId)
	return {
		Snapshot = buildSnapshot(state),
		Rankings = rankings,
		PlayerRank = playerRank,
		LifetimeRewards = state.LifetimeRewards,
	}
end

function ReputationService.AdjustReputation(player, amount, reason)
	local state = getStateForPlayer(player)
	if not state then
		return nil
	end

	local delta = tonumber(amount) or 0
	delta = math.floor(delta + 0.5)

	local oldScore = state.ReputationScore
	local newScore = clamp(oldScore + delta, MIN_REPUTATION, MAX_REPUTATION)
	local oldTier = getTierIndex(oldScore)
	local newTier = getTierIndex(newScore)

	state.ReputationScore = newScore
	local rewardEarned = grantTierRewards(player, state, oldTier, newTier)

	if IS_ROBLOX then
		for _, otherPlayer in ipairs(Players:GetPlayers()) do
			pushUpdate(otherPlayer)
		end
	end

	return {
		Reason = reason or "",
		ScoreDelta = newScore - oldScore,
		NewScore = newScore,
		TrustLevel = TRUST_TIERS[newTier].Name,
		RewardEarned = rewardEarned,
	}
end

function ReputationService.ProcessReviewOutcome(player, rating, reason)
	local numericRating = tonumber(rating) or 0
	if numericRating <= 0 then
		return nil
	end

	local delta = (numericRating - 3) * 6
	if reason == "Evicted" then
		delta = delta - 6
	elseif reason == "Complete" and numericRating >= 4 then
		delta = delta + 2
	end

	return ReputationService.AdjustReputation(player, delta, "TenantReview")
end

function ReputationService.CanPerformInteraction(player, interactionType)
	local state = getStateForPlayer(player)
	if not state then
		return false, nil
	end

	local rule = INTERACTION_RULES[interactionType]
	if not rule then
		return false, {
			Reason = "UnknownInteraction",
		}
	end

	local currentTierIndex = getTierIndex(state.ReputationScore)
	local requiredTierIndex = getTierIndexByName(rule.MinTrustLevel)
	local allowed = currentTierIndex >= requiredTierIndex
	return allowed, {
		CurrentTrustLevel = TRUST_TIERS[currentTierIndex].Name,
		RequiredTrustLevel = TRUST_TIERS[requiredTierIndex].Name,
	}
end

function ReputationService.ProcessInteraction(player, interactionType, outcome, reason)
	local state = getStateForPlayer(player)
	if not state then
		return nil, "PlayerNotFound"
	end

	local rule = INTERACTION_RULES[interactionType]
	if not rule then
		return nil, "UnknownInteraction"
	end

	local allowed, gate = ReputationService.CanPerformInteraction(player, interactionType)
	if not allowed then
		return {
			Applied = false,
			Reason = "TrustTooLow",
			InteractionType = interactionType,
			RequiredTrustLevel = gate.RequiredTrustLevel,
			CurrentTrustLevel = gate.CurrentTrustLevel,
			ScoreDelta = 0,
		}, nil
	end

	local normalizedOutcome = string.lower(tostring(outcome or "neutral"))
	local delta = rule.NeutralDelta or 0
	if normalizedOutcome == "success" then
		local multiplier = TRUST_TIERS[getTierIndex(state.ReputationScore)].RewardMultiplier
		delta = math.floor((rule.SuccessDelta or 0) * multiplier + 0.5)
	elseif normalizedOutcome == "failure" then
		delta = rule.FailureDelta or 0
	end

	if delta == 0 then
		return {
			Applied = false,
			Reason = "NoChange",
			InteractionType = interactionType,
			RequiredTrustLevel = gate.RequiredTrustLevel,
			CurrentTrustLevel = gate.CurrentTrustLevel,
			ScoreDelta = 0,
		}, nil
	end

	local updateReason = reason
	if updateReason == nil then
		updateReason = string.format("Interaction:%s:%s", interactionType, normalizedOutcome)
	end
	local result = ReputationService.AdjustReputation(player, delta, updateReason)
	if not result then
		return nil, "AdjustFailed"
	end

	return {
		Applied = true,
		InteractionType = interactionType,
		RequiredTrustLevel = gate.RequiredTrustLevel,
		CurrentTrustLevel = result.TrustLevel,
		ScoreDelta = result.ScoreDelta,
		NewScore = result.NewScore,
		RewardEarned = result.RewardEarned,
	}, nil
end

function ReputationService.Init()
	if not IS_ROBLOX then
		return
	end

	ReputationPackets.GetReputationRequest.OnServerInvoke = function(player)
		return ReputationService.GetReputationData(player)
	end

	Players.PlayerAdded:Connect(function(player)
		task.defer(function()
			pushUpdate(player)
		end)
	end)
end

function ReputationService._ResetForTests()
	testStateByPlayerId = {}
end

return ReputationService
