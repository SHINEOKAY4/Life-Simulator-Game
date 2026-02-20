-- Server/Services/AchievementService.luau
-- Tracks achievement progress, persistence, and claim rewards.
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
local ReplicatedStorage = nil
local ServerScriptService = nil
local AchievementDefinitions = nil
local AchievementPackets = nil
local PlayerSession = nil
local CurrencyService = nil

if IS_ROBLOX then
	Players = game:GetService("Players")
	ReplicatedStorage = game:GetService("ReplicatedStorage")
	ServerScriptService = game:GetService("ServerScriptService")

	AchievementDefinitions = require(ReplicatedStorage.Shared.Definitions.AchievementDefinitions)
	AchievementPackets = require(ReplicatedStorage.Network.AchievementPackets)
	PlayerSession = require(ServerScriptService.Server.Services.PlayerSession)
	CurrencyService = require(ServerScriptService.Server.Services.CurrencyService)
end

-- ============ Inline definitions for test mode ============

local INLINE_DEFINITIONS = {
	{
		Id = "builder_novice",
		Name = "Blueprint Beginner",
		Description = "Place 25 objects in build mode.",
		Category = "Building",
		StatKey = "BuildPlacements",
		TargetValue = 25,
		SortOrder = 10,
		Rewards = { Cash = 150, Experience = 40 },
	},
	{
		Id = "builder_pro",
		Name = "Master Builder",
		Description = "Place 150 objects in build mode.",
		Category = "Building",
		StatKey = "BuildPlacements",
		TargetValue = 150,
		SortOrder = 11,
		Rewards = { Cash = 500, Experience = 120 },
	},
	{
		Id = "chores_starter",
		Name = "Clean Sweep",
		Description = "Complete 10 chores.",
		Category = "Household",
		StatKey = "ChoresCompleted",
		TargetValue = 10,
		SortOrder = 20,
		Rewards = { Cash = 225, Experience = 55 },
	},
	{
		Id = "chores_veteran",
		Name = "Caretaker",
		Description = "Complete 50 chores.",
		Category = "Household",
		StatKey = "ChoresCompleted",
		TargetValue = 50,
		SortOrder = 21,
		Rewards = { Cash = 800, Experience = 180 },
	},
	{
		Id = "tenant_help_first",
		Name = "Helping Hand",
		Description = "Resolve 5 tenant help requests.",
		Category = "Tenants",
		StatKey = "TenantHelpsCompleted",
		TargetValue = 5,
		SortOrder = 30,
		Rewards = { Cash = 250, Experience = 60 },
	},
	{
		Id = "tenant_help_expert",
		Name = "Beloved Landlord",
		Description = "Resolve 30 tenant help requests.",
		Category = "Tenants",
		StatKey = "TenantHelpsCompleted",
		TargetValue = 30,
		SortOrder = 31,
		Rewards = { Cash = 1200, Experience = 260 },
	},
	{
		Id = "crafting_novice",
		Name = "First Workshop",
		Description = "Complete 5 crafting jobs.",
		Category = "Crafting",
		StatKey = "CraftingJobsCompleted",
		TargetValue = 5,
		SortOrder = 40,
		Rewards = { Cash = 175, Experience = 70 },
	},
	{
		Id = "crafting_expert",
		Name = "Assembly Line",
		Description = "Complete 40 crafting jobs.",
		Category = "Crafting",
		StatKey = "CraftingJobsCompleted",
		TargetValue = 40,
		SortOrder = 41,
		Rewards = { Cash = 900, Experience = 280 },
	},
	{
		Id = "level_5",
		Name = "Up and Running",
		Description = "Reach player level 5.",
		Category = "Progression",
		StatKey = "HighestLevelReached",
		TargetValue = 5,
		SortOrder = 50,
		Rewards = { Cash = 350, Experience = 0 },
	},
	{
		Id = "level_12",
		Name = "Established Owner",
		Description = "Reach player level 12.",
		Category = "Progression",
		StatKey = "HighestLevelReached",
		TargetValue = 12,
		SortOrder = 51,
		Rewards = { Cash = 1400, Experience = 0 },
	},
}

local function getDefinitionsList()
	if IS_ROBLOX and AchievementDefinitions then
		return AchievementDefinitions.List
	end
	return INLINE_DEFINITIONS
end

local inlineById = {}
for _, def in ipairs(INLINE_DEFINITIONS) do
	inlineById[def.Id] = def
end

local function getDefinitionById(achievementId)
	if IS_ROBLOX and AchievementDefinitions then
		return AchievementDefinitions.GetById(achievementId)
	end
	return inlineById[achievementId]
end

-- ============ Constants ============

local CURRENT_VERSION = 1

-- ============ Service ============

local AchievementService = {}

-- Configurable clock for tests
local clockFn = os.time

local function now()
	if IS_ROBLOX then
		return game:GetService("Workspace"):GetServerTimeNow()
	end
	return clockFn()
end

local function asWholePositive(value)
	if type(value) ~= "number" or value ~= value or value < 0 then
		return 0
	end
	return math.max(0, math.floor(value + 0.5))
end

local function ensureState(profile)
	local state = profile.AchievementState
	if type(state) ~= "table" then
		state = {}
		profile.AchievementState = state
	end

	if type(state.Version) ~= "number" then
		state.Version = CURRENT_VERSION
	end
	if type(state.Stats) ~= "table" then
		state.Stats = {}
	end
	if type(state.Unlocked) ~= "table" then
		state.Unlocked = {}
	end
	if type(state.Claimed) ~= "table" then
		state.Claimed = {}
	end

	for statKey, value in pairs(state.Stats) do
		state.Stats[statKey] = asWholePositive(value)
	end
	for achievementId, value in pairs(state.Unlocked) do
		state.Unlocked[achievementId] = asWholePositive(value)
	end
	for achievementId, value in pairs(state.Claimed) do
		state.Claimed[achievementId] = asWholePositive(value)
	end

	return state
end

local function definitionProgress(state, definition)
	local current = asWholePositive(state.Stats[definition.StatKey])
	local target = math.max(1, asWholePositive(definition.TargetValue))
	local progress = math.min(current, target)
	local isUnlocked = state.Unlocked[definition.Id] ~= nil or current >= target
	local isClaimed = state.Claimed[definition.Id] ~= nil
	return current, progress, target, isUnlocked, isClaimed
end

local function buildSnapshotFromState(state)
	local list = getDefinitionsList()
	local rows = {}
	local unlockedCount = 0
	local claimedCount = 0

	for _, definition in ipairs(list) do
		local current, progress, target, isUnlocked, isClaimed = definitionProgress(state, definition)
		if isUnlocked then
			unlockedCount = unlockedCount + 1
		end
		if isClaimed then
			claimedCount = claimedCount + 1
		end

		rows[#rows + 1] = {
			Id = definition.Id,
			Name = definition.Name,
			Description = definition.Description,
			Category = definition.Category,
			StatKey = definition.StatKey,
			CurrentValue = current,
			ProgressValue = progress,
			TargetValue = target,
			IsUnlocked = isUnlocked,
			IsClaimed = isClaimed,
			SortOrder = definition.SortOrder,
			Rewards = definition.Rewards or {},
			UnlockedAt = state.Unlocked[definition.Id] or 0,
			ClaimedAt = state.Claimed[definition.Id] or 0,
		}
	end

	return {
		Achievements = rows,
		UnlockedCount = unlockedCount,
		ClaimedCount = claimedCount,
		TotalCount = #list,
		Stats = state.Stats,
	}
end

local function buildAchievementRow(state, definition)
	local current, progress, target, isUnlocked, isClaimed = definitionProgress(state, definition)
	return {
		Id = definition.Id,
		Name = definition.Name,
		Description = definition.Description,
		Category = definition.Category,
		StatKey = definition.StatKey,
		CurrentValue = current,
		ProgressValue = progress,
		TargetValue = target,
		IsUnlocked = isUnlocked,
		IsClaimed = isClaimed,
		SortOrder = definition.SortOrder,
		Rewards = definition.Rewards or {},
		UnlockedAt = state.Unlocked[definition.Id] or 0,
		ClaimedAt = state.Claimed[definition.Id] or 0,
	}
end

-- ============ Test-mode state management ============

local testProfiles = {}

local function sendSnapshot(player, state)
	if IS_ROBLOX and AchievementPackets then
		AchievementPackets.SnapshotUpdated:FireClient(player, buildSnapshotFromState(state))
	end
	-- In test mode, snapshots are ignored (callers inspect state directly)
end

local function getStateForPlayer(player, shouldAwait)
	if IS_ROBLOX then
		local profile
		if shouldAwait then
			profile = PlayerSession.GetDataAwait(player)
		else
			profile = PlayerSession.GetData(player)
		end
		if type(profile) ~= "table" then
			return nil
		end
		return ensureState(profile)
	end

	-- Test mode: use in-memory profiles keyed by UserId
	if player == nil then
		return nil
	end
	local key = tostring(player.UserId or player)
	local profile = testProfiles[key]
	if not profile then
		profile = {}
		testProfiles[key] = profile
	end
	return ensureState(profile)
end

local function getProfileForPlayer(player)
	if IS_ROBLOX then
		return PlayerSession.GetData(player)
	end
	if player == nil then
		return nil
	end
	local key = tostring(player.UserId or player)
	local profile = testProfiles[key]
	if not profile then
		profile = {}
		testProfiles[key] = profile
	end
	return profile
end

local function getProgressionService()
	if IS_ROBLOX then
		local module = require(ServerScriptService.Server.Services.ProgressionService)
		return module
	end
	-- Test mode stub: no-op
	return {
		AwardExperience = function() end,
	}
end

local function tryUnlockDefinition(player, state, definition, unlockedIds)
	local _, _, target, isUnlocked, _ = definitionProgress(state, definition)
	if isUnlocked and state.Unlocked[definition.Id] == nil then
		state.Unlocked[definition.Id] = now()
		unlockedIds[#unlockedIds + 1] = definition.Id
		if IS_ROBLOX and AchievementPackets then
			AchievementPackets.AchievementUnlocked:FireClient(player, {
				AchievementId = definition.Id,
				UnlockedAt = state.Unlocked[definition.Id],
			})
		end
	end
	-- Snap to target for cleaner displays once unlocked.
	if isUnlocked then
		local current = asWholePositive(state.Stats[definition.StatKey])
		if current < target then
			state.Stats[definition.StatKey] = target
		end
	end
end

local function applyStatDelta(player, statKey, delta, overwriteMaxValue)
	if delta == 0 then
		return
	end
	local state = getStateForPlayer(player, false)
	if not state then
		return
	end

	local oldValue = asWholePositive(state.Stats[statKey])
	local newValue = oldValue
	if overwriteMaxValue then
		newValue = math.max(oldValue, asWholePositive(delta))
	else
		newValue = math.max(0, oldValue + asWholePositive(delta))
	end
	if newValue == oldValue then
		return
	end

	state.Stats[statKey] = newValue

	local unlockedIds = {}
	for _, definition in ipairs(getDefinitionsList()) do
		if definition.StatKey == statKey then
			tryUnlockDefinition(player, state, definition, unlockedIds)
		end
	end

	sendSnapshot(player, state)
end

-- ============ Public API ============

function AchievementService.GetSnapshot(player)
	local state = getStateForPlayer(player, false)
	if not state then
		return nil
	end
	return buildSnapshotFromState(state)
end

function AchievementService.GetUnlockedAndInProgress(player)
	local state = getStateForPlayer(player, false)
	if not state then
		return nil
	end

	local unlocked = {}
	local inProgress = {}

	for _, definition in ipairs(getDefinitionsList()) do
		local row = buildAchievementRow(state, definition)
		if row.IsUnlocked then
			unlocked[#unlocked + 1] = row
		elseif row.ProgressValue > 0 then
			inProgress[#inProgress + 1] = row
		end
	end

	return {
		Unlocked = unlocked,
		InProgress = inProgress,
		UnlockedCount = #unlocked,
		InProgressCount = #inProgress,
	}
end

--- Returns unlocked achievements that have not been claimed yet.
--- Returns nil if player has no profile/state.
function AchievementService.GetClaimableAchievements(player)
	local state = getStateForPlayer(player, false)
	if not state then
		return nil
	end

	local claimable = {}
	for _, definition in ipairs(getDefinitionsList()) do
		local row = buildAchievementRow(state, definition)
		if row.IsUnlocked and not row.IsClaimed then
			claimable[#claimable + 1] = row
		end
	end

	return {
		Claimable = claimable,
		ClaimableCount = #claimable,
	}
end

--- Returns the static definition metadata for the given achievement, or nil
--- if the ID is invalid or unknown.  The returned table contains:
---   Id, Name, Description, Category, StatKey, TargetValue, SortOrder, Rewards
function AchievementService.GetAchievementMetadata(achievementId)
	if type(achievementId) ~= "string" or achievementId == "" then
		return nil
	end

	local definition = getDefinitionById(achievementId)
	if not definition then
		return nil
	end

	return {
		Id = definition.Id,
		Name = definition.Name,
		Description = definition.Description,
		Category = definition.Category,
		StatKey = definition.StatKey,
		TargetValue = definition.TargetValue,
		SortOrder = definition.SortOrder,
		Rewards = definition.Rewards or {},
	}
end

--- Returns a list of static achievement definition metadata entries for a
--- category. Returns an empty list for invalid/unknown categories.
function AchievementService.GetAchievementsByCategory(category)
	if type(category) ~= "string" or category == "" then
		return {}
	end

	local results = {}
	for _, definition in ipairs(getDefinitionsList()) do
		if definition.Category == category then
			results[#results + 1] = {
				Id = definition.Id,
				Name = definition.Name,
				Description = definition.Description,
				Category = definition.Category,
				StatKey = definition.StatKey,
				TargetValue = definition.TargetValue,
				SortOrder = definition.SortOrder,
				Rewards = definition.Rewards or {},
			}
		end
	end
	return results
end

function AchievementService.GetAchievementProgress(player, achievementId)
	if type(achievementId) ~= "string" or achievementId == "" then
		return nil
	end

	local definition = getDefinitionById(achievementId)
	if not definition then
		return nil
	end

	local state = getStateForPlayer(player, false)
	if not state then
		return nil
	end

	local current, progress, target, isUnlocked, isClaimed = definitionProgress(state, definition)
	return progress
end

--- Returns a dictionary mapping every achievement ID to its clamped progress
--- value for the given player, or nil if the player has no profile.
--- Example: { builder_novice = 10, builder_pro = 10, chores_starter = 0, ... }
function AchievementService.GetPlayerAchievements(player)
	local state = getStateForPlayer(player, false)
	if not state then
		return nil
	end

	local result = {}
	for _, definition in ipairs(getDefinitionsList()) do
		local _, progress = definitionProgress(state, definition)
		result[definition.Id] = progress
	end
	return result
end

function AchievementService.RecordBuildPlaced(player, quantity)
	local increment
	if type(quantity) == "number" and quantity > 0 then
		increment = asWholePositive(quantity)
	else
		increment = 1
	end
	applyStatDelta(player, "BuildPlacements", increment)
end

function AchievementService.RecordChoreCompleted(player)
	applyStatDelta(player, "ChoresCompleted", 1)
end

function AchievementService.RecordTenantHelpCompleted(player)
	applyStatDelta(player, "TenantHelpsCompleted", 1)
end

function AchievementService.RecordCraftCompleted(player)
	applyStatDelta(player, "CraftingJobsCompleted", 1)
end

function AchievementService.RecordLevelReached(player, level)
	applyStatDelta(player, "HighestLevelReached", level, true)
end

function AchievementService.ClaimAchievement(player, achievementId)
	if type(achievementId) ~= "string" or achievementId == "" then
		return false, "Invalid achievement id.", nil
	end

	local definition = getDefinitionById(achievementId)
	if not definition then
		return false, "Achievement not found.", nil
	end

	local profile = getProfileForPlayer(player)
	if type(profile) ~= "table" then
		return false, "Profile unavailable.", nil
	end
	local state = ensureState(profile)

	local _, _, _, isUnlocked, isClaimed = definitionProgress(state, definition)
	if not isUnlocked then
		return false, "Achievement is not unlocked yet.", nil
	end
	if isClaimed then
		return false, "Achievement already claimed.", nil
	end

	local rewards = definition.Rewards or {}
	local rewardCash = asWholePositive(rewards.Cash)
	local rewardExperience = asWholePositive(rewards.Experience)

	if rewardCash > 0 then
		if IS_ROBLOX then
			local currencyState = profile.CurrencyState
			if type(currencyState) ~= "table" then
				profile.CurrencyState = {}
				currencyState = profile.CurrencyState
			end
			CurrencyService.Add(player, "Cash", rewardCash, currencyState, {
				Source = "Achievement:" .. definition.Id,
			})
		else
			-- Test mode: track cash in profile directly
			local currencyState = profile.CurrencyState
			if type(currencyState) ~= "table" then
				profile.CurrencyState = {}
				currencyState = profile.CurrencyState
			end
			currencyState.Cash = (currencyState.Cash or 0) + rewardCash
		end
	end
	if rewardExperience > 0 then
		getProgressionService().AwardExperience(player, rewardExperience, "Achievement:" .. definition.Id)
	end

	state.Claimed[definition.Id] = now()
	sendSnapshot(player, state)

	return true, "Achievement claimed.", {
		AchievementId = definition.Id,
		RewardCash = rewardCash,
		RewardExperience = rewardExperience,
	}
end

local function handleGetSnapshot(player)
	local state = getStateForPlayer(player, true)
	if not state then
		return false, "Profile unavailable.", nil
	end
	return true, "", buildSnapshotFromState(state)
end

function AchievementService.Init()
	if not IS_ROBLOX then
		return
	end

	AchievementPackets.GetSnapshot.OnServerInvoke = function(player)
		return handleGetSnapshot(player)
	end

	AchievementPackets.ClaimAchievement.OnServerInvoke = function(player, achievementId)
		return AchievementService.ClaimAchievement(player, achievementId)
	end

	Players.PlayerAdded:Connect(function(player)
		task.defer(function()
			if not player.Parent then
				return
			end
			local state = getStateForPlayer(player, true)
			if state then
				-- Ensure level-based achievements hydrate against current level.
				local levelValue = player:GetAttribute("PlayerLevel")
				if type(levelValue) == "number" then
					applyStatDelta(player, "HighestLevelReached", levelValue, true)
				else
					sendSnapshot(player, state)
				end
			end
		end)
	end)
end

-- ============ Test Hooks ============

function AchievementService._ResetForTests()
	testProfiles = {}
	clockFn = os.time
end

function AchievementService._SetClock(fn)
	if type(fn) == "function" then
		clockFn = fn
	else
		clockFn = os.time
	end
end

function AchievementService._GetTestProfile(player)
	if player == nil then
		return nil
	end
	local key = tostring(player.UserId or player)
	return testProfiles[key]
end

return AchievementService
