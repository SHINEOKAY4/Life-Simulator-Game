-- DailyRewardService: daily login reward system with streak tracking,
-- cooldown enforcement, milestone bonuses, and notification integration.
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
local PlayerSession = nil
local CurrencyService = nil
local NotificationService = nil
local DailyRewardDefinitions = nil
local DailyRewardPackets = nil

if IS_ROBLOX then
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local ServerScriptService = game:GetService("ServerScriptService")
	Players = game:GetService("Players")

	DailyRewardDefinitions = require(ReplicatedStorage.Shared.Definitions.DailyRewardDefinitions)
	DailyRewardPackets = require(ReplicatedStorage.Network.DailyRewardPackets)
	PlayerSession = require(ServerScriptService.Server.Services.PlayerSession)
	CurrencyService = require(ServerScriptService.Server.Services.CurrencyService)
	NotificationService = require(ServerScriptService.Server.Services.NotificationService)
end

-- ============ Inline definitions for test mode ============

local REWARDS = {
	{ Day = 1, Cash = 50, Experience = 15, Label = "Welcome Back" },
	{ Day = 2, Cash = 75, Experience = 20, Label = "Getting Started" },
	{ Day = 3, Cash = 100, Experience = 30, Label = "Momentum" },
	{ Day = 4, Cash = 125, Experience = 35, Label = "Rolling" },
	{ Day = 5, Cash = 175, Experience = 45, Label = "Dedicated" },
	{ Day = 6, Cash = 225, Experience = 55, Label = "Committed" },
	{ Day = 7, Cash = 350, Experience = 80, Label = "Full Week" },
}

local MILESTONES = {
	{ StreakRequired = 7, BonusCash = 200, BonusExperience = 50, Label = "First Full Week" },
	{ StreakRequired = 14, BonusCash = 500, BonusExperience = 100, Label = "Two Week Streak" },
	{ StreakRequired = 30, BonusCash = 1200, BonusExperience = 250, Label = "Monthly Dedication" },
}

local CLAIM_COOLDOWN_SECONDS = 20 * 60 * 60  -- 20 hours
local STREAK_GRACE_SECONDS = 48 * 60 * 60    -- 48 hours
local CYCLE_LENGTH = #REWARDS

local function getRewardForStreak(streak)
	if IS_ROBLOX and DailyRewardDefinitions then
		return DailyRewardDefinitions.GetRewardForStreak(streak)
	end
	local dayIndex = ((streak - 1) % CYCLE_LENGTH) + 1
	return REWARDS[dayIndex]
end

local function getMilestoneForStreak(streak)
	if IS_ROBLOX and DailyRewardDefinitions then
		return DailyRewardDefinitions.GetMilestoneForStreak(streak)
	end
	for _, milestone in ipairs(MILESTONES) do
		if milestone.StreakRequired == streak then
			return milestone
		end
	end
	return nil
end

-- ============ Service ============

local DailyRewardService = {}

-- Configurable clock for tests
local clockFn = os.time

local function getTime()
	return clockFn()
end

-- Internal state per player (keyed by playerId string) for test mode
local testStateByPlayerId = {}

local function ensureStateShape(state)
	if type(state.CurrentStreak) ~= "number" then
		state.CurrentStreak = 0
	end
	state.CurrentStreak = math.max(math.floor(state.CurrentStreak + 0.5), 0)

	if type(state.LongestStreak) ~= "number" then
		state.LongestStreak = 0
	end
	state.LongestStreak = math.max(math.floor(state.LongestStreak + 0.5), 0)

	if type(state.LastClaimTime) ~= "number" then
		state.LastClaimTime = 0
	end
	state.LastClaimTime = math.max(math.floor(state.LastClaimTime + 0.5), 0)

	if type(state.TotalClaimed) ~= "number" then
		state.TotalClaimed = 0
	end
	state.TotalClaimed = math.max(math.floor(state.TotalClaimed + 0.5), 0)

	if type(state.TotalCashEarned) ~= "number" then
		state.TotalCashEarned = 0
	end
	state.TotalCashEarned = math.max(math.floor(state.TotalCashEarned + 0.5), 0)

	if type(state.TotalExperienceEarned) ~= "number" then
		state.TotalExperienceEarned = 0
	end
	state.TotalExperienceEarned = math.max(math.floor(state.TotalExperienceEarned + 0.5), 0)

	if type(state.MilestonesClaimed) ~= "table" then
		state.MilestonesClaimed = {}
	end
end

local function ensureTestState(playerId)
	local key = tostring(playerId)
	local state = testStateByPlayerId[key]
	if not state then
		state = {
			CurrentStreak = 0,
			LongestStreak = 0,
			LastClaimTime = 0,
			TotalClaimed = 0,
			TotalCashEarned = 0,
			TotalExperienceEarned = 0,
			MilestonesClaimed = {},
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
	if IS_ROBLOX and type(player) == "userdata" then
		local state = PlayerSession.TryGetData(player, "DailyRewardState")
		if not state then
			state = PlayerSession.GetData(player, "DailyRewardState")
		end
		if state then
			ensureStateShape(state)
		end
		return state
	end
	return ensureTestState(player)
end

local function computeStreakStatus(state, now)
	local timeSinceClaim = now - state.LastClaimTime

	-- First-ever claim (no previous claim)
	if state.LastClaimTime == 0 then
		return {
			CanClaim = true,
			IsFirstClaim = true,
			StreakAlive = false,
			TimeSinceClaim = 0,
			SecondsUntilClaim = 0,
		}
	end

	-- Streak expired (missed the grace window)
	if timeSinceClaim > STREAK_GRACE_SECONDS then
		return {
			CanClaim = true,
			IsFirstClaim = false,
			StreakAlive = false,
			TimeSinceClaim = timeSinceClaim,
			SecondsUntilClaim = 0,
		}
	end

	-- Still in cooldown
	if timeSinceClaim < CLAIM_COOLDOWN_SECONDS then
		return {
			CanClaim = false,
			IsFirstClaim = false,
			StreakAlive = true,
			TimeSinceClaim = timeSinceClaim,
			SecondsUntilClaim = CLAIM_COOLDOWN_SECONDS - timeSinceClaim,
		}
	end

	-- Within grace period and past cooldown: can claim and streak is alive
	return {
		CanClaim = true,
		IsFirstClaim = false,
		StreakAlive = true,
		TimeSinceClaim = timeSinceClaim,
		SecondsUntilClaim = 0,
	}
end

local function sendNotification(playerId, title, body, metadata)
	if IS_ROBLOX and NotificationService then
		NotificationService.Send(playerId, "Reward", title, body, metadata)
		return
	end
	-- In test mode, store notifications for verification
	if DailyRewardService._testNotifications then
		table.insert(DailyRewardService._testNotifications, {
			PlayerId = playerId,
			Title = title,
			Body = body,
			Metadata = metadata or {},
		})
	end
end

--[=[
	Get the current daily reward status for a player.

	@param player any -- Player instance (Roblox) or test identifier
	@return table? -- Status snapshot, or nil if player data unavailable
]=]
function DailyRewardService.GetStatus(player)
	local state = getStateForPlayer(player)
	if not state then
		return nil
	end

	local now = getTime()
	local status = computeStreakStatus(state, now)

	local nextStreak = state.CurrentStreak + 1
	if not status.StreakAlive and not status.IsFirstClaim then
		nextStreak = 1  -- streak will reset
	end

	local nextReward = getRewardForStreak(nextStreak)
	local milestone = getMilestoneForStreak(nextStreak)
	local milestoneAlreadyClaimed = false
	if milestone then
		milestoneAlreadyClaimed = state.MilestonesClaimed[tostring(milestone.StreakRequired)] == true
	end

	return {
		CurrentStreak = state.CurrentStreak,
		LongestStreak = state.LongestStreak,
		TotalClaimed = state.TotalClaimed,
		TotalCashEarned = state.TotalCashEarned,
		TotalExperienceEarned = state.TotalExperienceEarned,
		CanClaim = status.CanClaim,
		SecondsUntilClaim = status.SecondsUntilClaim,
		NextReward = nextReward,
		NextStreak = nextStreak,
		PendingMilestone = (milestone and not milestoneAlreadyClaimed) and milestone or nil,
	}
end

--[=[
	Attempt to claim the daily reward for a player.

	@param player any -- Player instance (Roblox) or test identifier
	@return table? -- Claim result, or nil on failure
	@return string? -- Error string on failure
]=]
function DailyRewardService.ClaimReward(player)
	local state = getStateForPlayer(player)
	if not state then
		return nil, "PlayerNotFound"
	end

	local now = getTime()
	local status = computeStreakStatus(state, now)

	if not status.CanClaim then
		return nil, "CooldownActive"
	end

	-- Determine new streak
	local newStreak
	if status.IsFirstClaim or not status.StreakAlive then
		newStreak = 1
	else
		newStreak = state.CurrentStreak + 1
	end

	-- Get the reward for this streak day
	local reward = getRewardForStreak(newStreak)
	local cashReward = reward.Cash
	local xpReward = reward.Experience

	-- Check for milestone bonus
	local milestone = getMilestoneForStreak(newStreak)
	local milestoneBonus = nil
	if milestone and not state.MilestonesClaimed[tostring(milestone.StreakRequired)] then
		milestoneBonus = milestone
		cashReward = cashReward + milestone.BonusCash
		xpReward = xpReward + milestone.BonusExperience
		state.MilestonesClaimed[tostring(milestone.StreakRequired)] = true
	end

	-- Update state
	state.CurrentStreak = newStreak
	state.LastClaimTime = now
	state.TotalClaimed = state.TotalClaimed + 1
	state.TotalCashEarned = state.TotalCashEarned + cashReward
	state.TotalExperienceEarned = state.TotalExperienceEarned + xpReward

	if newStreak > state.LongestStreak then
		state.LongestStreak = newStreak
	end

	-- Grant rewards in Roblox
	if IS_ROBLOX and CurrencyService then
		local currencyState = PlayerSession.TryGetData(player, "CurrencyState")
		if not currencyState then
			currencyState = PlayerSession.GetData(player, "CurrencyState")
		end
		if currencyState then
			CurrencyService.Add(player, "Cash", cashReward, currencyState, { Source = "DailyReward" })
		end
	end

	-- Build result
	local result = {
		Streak = newStreak,
		DayLabel = reward.Label,
		CashEarned = cashReward,
		ExperienceEarned = xpReward,
		MilestoneUnlocked = milestoneBonus and milestoneBonus.Label or nil,
		LongestStreak = state.LongestStreak,
		StreakReset = (status.IsFirstClaim or not status.StreakAlive) and newStreak == 1,
	}

	-- Send notification
	local playerId = player
	if IS_ROBLOX and type(player) == "userdata" then
		playerId = player.UserId
	end

	local notifTitle = string.format("Day %d Reward!", newStreak)
	local notifBody = string.format("%s: +$%d, +%d XP", reward.Label, cashReward, xpReward)
	if milestoneBonus then
		notifBody = notifBody .. string.format(" | Milestone: %s!", milestoneBonus.Label)
	end
	sendNotification(playerId, notifTitle, notifBody, {
		Source = "DailyRewardService",
		Streak = newStreak,
		Cash = cashReward,
		Experience = xpReward,
	})

	return result, nil
end

--[=[
	Get the reward preview for a specific streak day (1-indexed, wraps via cycle).

	@param streakDay number -- The streak day to preview
	@return table -- Reward details for that day
]=]
function DailyRewardService.PreviewReward(streakDay)
	local day = math.max(1, math.floor(tonumber(streakDay) or 1))
	local reward = getRewardForStreak(day)
	local milestone = getMilestoneForStreak(day)

	return {
		Day = day,
		CycleDay = ((day - 1) % CYCLE_LENGTH) + 1,
		Cash = reward.Cash,
		Experience = reward.Experience,
		Label = reward.Label,
		Milestone = milestone,
	}
end

-- ============ Init (Roblox) ============

function DailyRewardService.Init()
	if not IS_ROBLOX then
		return
	end

	DailyRewardPackets.GetDailyRewardStatus.OnServerInvoke = function(player)
		return DailyRewardService.GetStatus(player)
	end

	DailyRewardPackets.ClaimDailyReward.OnServerInvoke = function(player)
		return DailyRewardService.ClaimReward(player)
	end

	-- Auto-show status when player joins
	Players.PlayerAdded:Connect(function(player)
		task.defer(function()
			local status = DailyRewardService.GetStatus(player)
			if status and status.CanClaim then
				sendNotification(player.UserId, "Daily Reward Available!", "Your daily reward is ready to claim.", {
					Source = "DailyRewardService",
					AutoPrompt = true,
				})
			end
		end)
	end)
end

-- ============ Test Hooks ============

function DailyRewardService._ResetForTests()
	testStateByPlayerId = {}
	DailyRewardService._testNotifications = {}
end

function DailyRewardService._SetClock(fn)
	if type(fn) == "function" then
		clockFn = fn
	else
		clockFn = os.time
	end
end

function DailyRewardService._GetConstants()
	return {
		ClaimCooldownSeconds = CLAIM_COOLDOWN_SECONDS,
		StreakGraceSeconds = STREAK_GRACE_SECONDS,
		CycleLength = CYCLE_LENGTH,
	}
end

-- Initialize test notifications table
DailyRewardService._testNotifications = {}

return DailyRewardService
