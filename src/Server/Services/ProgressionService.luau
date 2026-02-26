-- ServerScriptService/Server/Services/ProgressionService.luau
-- Centralized leveling and XP tracking used by build, chores, and tenant interactions.
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
local ProgressionConfig = nil
local ProgressionPackets = nil
local PlayerSession = nil
local AchievementService = nil

if IS_ROBLOX then
	Players = game:GetService("Players")
	ReplicatedStorage = game:GetService("ReplicatedStorage")
	ServerScriptService = game:GetService("ServerScriptService")

	ProgressionConfig = require(ReplicatedStorage.Shared.Configurations.ProgressionConfig)
	ProgressionPackets = require(ReplicatedStorage.Network.ProgressionPackets)
	PlayerSession = require(ServerScriptService.Server.Services.PlayerSession)
	AchievementService = require(ServerScriptService.Server.Services.AchievementService)
end

-- ============ Inline config for test mode ============

local INLINE_CONFIG = {
	BaseExperience = 90,
	GrowthFactor = 1.25,
	MaxLevel = 50,

	ActionRewards = {
		ChoreCompleted = 35,
		TenantHelped = 80,
		BuildPlacementBase = 10,
		BuildPlacementPerCell = 2,
		PremiumPlacementBonus = 15,
	},

	UnlocksByLevel = {
		[2] = { "GlassPane", "FlatRoofEdge", "GlassCoffeeTable" },
		[3] = { "StandardBed", "FlatRoofCap", "KitchenCounter" },
		[4] = { "Bathtub", "Refridgerator", "FlatScreenTelevision" },
		[5] = { "Computer", "WoodenDoor", "CeilingFan" },
	},
}

local function getConfig()
	if IS_ROBLOX and ProgressionConfig then
		return ProgressionConfig
	end
	return INLINE_CONFIG
end

-- ============ Service state ============

local ProgressionService = {}

local testProfiles = {}
local RuntimeUnlockCache = {}

-- Injectable achievement sink for test mode (replaces AchievementService.RecordLevelReached)
local achievementSink = nil

-- ============ Test Mode state ============

-- External XP multiplier (e.g. from SeasonalEventService buffs)
-- In Roblox, this is queried from SeasonalEventService per-player.
-- In test mode, this injectable function replaces the real service call.
local externalMultiplierFn = nil -- function(player) -> number (1.0 = no buff)

-- Cooldown tracking: maps "UserId:action" -> os.clock() of last execution
local cooldownTimestamps = {}
local COOLDOWN_DURATION = 1.0 -- seconds between repeated actions

local function getXpMultiplier(player)
	-- Try injectable sink first (test mode)
	if externalMultiplierFn then
		local ok, result = pcall(externalMultiplierFn, player)
		if ok and type(result) == "number" and result > 0 then
			return result
		end
		return 1.0
	end
	-- In Roblox, query SeasonalEventService directly
	if IS_ROBLOX then
		local ok, SeasonalEventService = pcall(function()
			return require(game:GetService("ServerScriptService").Server.Services.SeasonalEventService)
		end)
		if ok and SeasonalEventService and SeasonalEventService.GetBuffMultiplier then
			local multOk, mult = pcall(SeasonalEventService.GetBuffMultiplier, player, "XPMultiplier")
			if multOk and type(mult) == "number" and mult > 0 then
				return mult
			end
		end
	end
	return 1.0
end

-- ============ Internal helpers ============

local function resolveRequiredLevel(spec)
	if type(spec) ~= "table" then
		return 1
	end
	local required = spec.RequiredLevel
	if type(required) ~= "number" then
		return 1
	end
	if required ~= required or required < 1 then
		return 1
	end
	return math.floor(required + 0.5)
end

local function xpForLevel(level)
	local config = getConfig()
	local base = config.BaseExperience
	local growth = config.GrowthFactor
	if level <= 1 then
		return math.floor(base + 0.5)
	end
	return math.floor(base * (growth ^ (level - 1)) + 0.5)
end

local function computeProgress(totalXp)
	local config = getConfig()
	local level = 1
	local remaining = math.max(0, totalXp)
	local nextRequirement = xpForLevel(level)
	local maxLevel = config.MaxLevel or 50

	while level < maxLevel and remaining >= nextRequirement do
		remaining = remaining - nextRequirement
		level = level + 1
		nextRequirement = xpForLevel(level)
	end

	if level >= maxLevel then
		remaining = 0
		nextRequirement = 0
	end

	return level, remaining, nextRequirement
end

local function applyUnlocksForLevel(state, targetLevel)
	local config = getConfig()
	local unlocks = {}
	local map = state.UnlockedItems
	if type(map) ~= "table" then
		map = {}
		state.UnlockedItems = map
	end

	local unlockCatalog = config.UnlocksByLevel
	if type(unlockCatalog) ~= "table" then
		return unlocks
	end

	for requiredLevel = 1, targetLevel do
		local ids = unlockCatalog[requiredLevel]
		if type(ids) == "table" then
			for _, itemId in ipairs(ids) do
				if type(itemId) == "string" and itemId ~= "" and map[itemId] ~= true then
					map[itemId] = true
					unlocks[#unlocks + 1] = itemId
				end
			end
		end
	end

	return unlocks
end

local function syncAttributes(player, level, totalXp, xpIntoLevel, xpForNext)
	if IS_ROBLOX then
		player:SetAttribute("PlayerLevel", level)
		player:SetAttribute("PlayerExperience", totalXp)
		player:SetAttribute("PlayerXPIntoLevel", xpIntoLevel)
		player:SetAttribute("PlayerXPForNext", xpForNext)
	else
		-- Test mode: store attributes on a table attached to the player mock
		if type(player) == "table" then
			if not player._attributes then
				player._attributes = {}
			end
			player._attributes.PlayerLevel = level
			player._attributes.PlayerExperience = totalXp
			player._attributes.PlayerXPIntoLevel = xpIntoLevel
			player._attributes.PlayerXPForNext = xpForNext
		end
	end
end

local function recordAchievementLevel(player, level)
	if IS_ROBLOX and AchievementService then
		AchievementService.RecordLevelReached(player, level)
		return
	end
	-- Test mode: call injectable sink if provided
	if achievementSink then
		achievementSink(player, level)
	end
end

local function getStateForPlayer(player)
	if IS_ROBLOX then
		local state = PlayerSession.GetDataAwait(player, "ProgressionState")
		if not state then
			return nil
		end
		if type(state.Level) ~= "number" then
			state.Level = 1
		end
		if type(state.Experience) ~= "number" then
			state.Experience = 0
		end
		if type(state.UnlockedItems) ~= "table" then
			state.UnlockedItems = {}
		end
		return state
	end

	-- Test mode: in-memory profiles keyed by UserId
	if player == nil then
		return nil
	end
	local key = tostring(player.UserId or player)
	local profile = testProfiles[key]
	if not profile then
		profile = {
			Level = 1,
			Experience = 0,
			UnlockedItems = {},
		}
		testProfiles[key] = profile
	end
	if type(profile.Level) ~= "number" then
		profile.Level = 1
	end
	if type(profile.Experience) ~= "number" then
		profile.Experience = 0
	end
	if type(profile.UnlockedItems) ~= "table" then
		profile.UnlockedItems = {}
	end
	return profile
end

local function hydrateState(player)
	local state = getStateForPlayer(player)
	if not state then
		return nil
	end

	local level, xpIntoLevel, xpForNext = computeProgress(state.Experience)
	state.Level = level
	applyUnlocksForLevel(state, level)

	local userId = player and player.UserId
	if userId then
		RuntimeUnlockCache[userId] = state.UnlockedItems
	end

	syncAttributes(player, level, state.Experience, xpIntoLevel, xpForNext)
	recordAchievementLevel(player, level)

	return state
end

local function broadcastProgression(player, state, delta, reason, newUnlocks)
	local level, xpIntoLevel, xpForNext = computeProgress(state.Experience)

	local payload = {
		Level = level,
		ExperienceTotal = state.Experience,
		ExperienceIntoLevel = xpIntoLevel,
		ExperienceForNext = xpForNext,
		Delta = delta,
		Reason = reason,
		UnlockedItemIds = newUnlocks,
	}

	if IS_ROBLOX and ProgressionPackets then
		ProgressionPackets.ProgressionUpdate:FireClient(player, payload)
		return
	end

	-- Test mode: capture broadcasts for test assertions
	if ProgressionService._testBroadcasts then
		table.insert(ProgressionService._testBroadcasts, {
			Player = player,
			Payload = payload,
		})
	end
end

-- ============ Public API ============

function ProgressionService.GetLevel(player)
	if IS_ROBLOX then
		local attr = player:GetAttribute("PlayerLevel")
		if type(attr) == "number" then
			return attr
		end
	else
		-- Test mode: check stored attributes
		if type(player) == "table" and player._attributes then
			local attr = player._attributes.PlayerLevel
			if type(attr) == "number" then
				return attr
			end
		end
	end

	local state = hydrateState(player)
	return state and state.Level or 1
end

function ProgressionService.CanPlaceItem(player, itemSpec, itemId)
	local state = hydrateState(player)
	if not state then
		return false, "Progression data unavailable."
	end
	local requiredLevel = resolveRequiredLevel(itemSpec)
	local currentLevel = computeProgress(state.Experience)
	state.Level = currentLevel

	local userId = player and player.UserId
	local unlockedMap = userId and RuntimeUnlockCache[userId]
	if unlockedMap and itemId and unlockedMap[itemId] then
		return true, nil
	end
	if currentLevel < requiredLevel then
		return false, string.format("Reach level %d to place this item.", requiredLevel)
	end
	return true, nil
end

function ProgressionService.AwardExperience(player, amount, reason)
	if amount <= 0 then
		return ProgressionService.GetLevel(player)
	end

	local state = hydrateState(player)
	if not state then
		return 1
	end

	-- Apply seasonal/external XP multiplier
	local effectiveAmount = amount * getXpMultiplier(player)

	local previousLevel = computeProgress(state.Experience)
	state.Experience = state.Experience + math.floor(effectiveAmount + 0.5)
	local level, xpIntoLevel, xpForNext = computeProgress(state.Experience)
	state.Level = level

	local newUnlocks = {}
	if level > previousLevel then
		newUnlocks = applyUnlocksForLevel(state, level)
	end

	local userId = player and player.UserId
	if userId then
		RuntimeUnlockCache[userId] = state.UnlockedItems
	end

	syncAttributes(player, level, state.Experience, xpIntoLevel, xpForNext)
	broadcastProgression(player, state, effectiveAmount, reason, newUnlocks)
	recordAchievementLevel(player, level)

	return level
end

local function computePlacementReward(spec, quantity)
	local config = getConfig()
	local rewards = config.ActionRewards
	local base = rewards.BuildPlacementBase or 0
	local perUnit = rewards.BuildPlacementPerCell or 0
	local premiumBonus = rewards.PremiumPlacementBonus or 0

	local units = 1
	if type(quantity) == "number" and quantity > 0 then
		units = math.floor(quantity + 0.5)
	end
	local total = base + perUnit * units

	if spec and type(spec.Cost) == "number" and spec.Cost >= 1200 then
		total = total + premiumBonus
	end

	return math.max(1, math.floor(total + 0.5))
end

function ProgressionService.RecordBuildPlacement(player, itemSpec, quantity)
	local reward = computePlacementReward(itemSpec, quantity)
	ProgressionService.AwardExperience(player, reward, "BuildPlacement")
end

function ProgressionService.RecordChoreCompletion(player)
	local config = getConfig()
	local rewards = config.ActionRewards
	ProgressionService.AwardExperience(player, rewards.ChoreCompleted or 10, "ChoreCompleted")
end

function ProgressionService.RecordTenantHelped(player)
	local config = getConfig()
	local rewards = config.ActionRewards
	ProgressionService.AwardExperience(player, rewards.TenantHelped or 15, "TenantHelped")
end

function ProgressionService.Init()
	if not IS_ROBLOX then
		return
	end

	Players.PlayerAdded:Connect(function(player)
		task.defer(function()
			if player.Parent then
				hydrateState(player)
			end
		end)
	end)

	Players.PlayerRemoving:Connect(function(player)
		RuntimeUnlockCache[player.UserId] = nil
	end)

	for _, player in ipairs(Players:GetPlayers()) do
		task.defer(function()
			if player.Parent then
				hydrateState(player)
			end
		end)
	end
end

-- ============ Exported helpers for testing ============

-- Expose xpForLevel and computeProgress so tests can validate the XP curve
function ProgressionService._XpForLevel(level)
	return xpForLevel(level)
end

function ProgressionService._ComputeProgress(totalXp)
	return computeProgress(totalXp)
end

function ProgressionService._ComputePlacementReward(spec, quantity)
	return computePlacementReward(spec, quantity)
end

-- ============ Test Hooks ============

function ProgressionService._ResetForTests()
	testProfiles = {}
	RuntimeUnlockCache = {}
	achievementSink = nil
	externalMultiplierFn = nil
	cooldownTimestamps = {}
	ProgressionService._testBroadcasts = nil
end

function ProgressionService._SetAchievementSink(fn)
	if type(fn) == "function" then
		achievementSink = fn
	else
		achievementSink = nil
	end
end

function ProgressionService._GetTestProfile(player)
	if player == nil then
		return nil
	end
	local key = tostring(player.UserId or player)
	return testProfiles[key]
end

function ProgressionService._SetExternalMultiplier(fn)
	if type(fn) == "function" then
		externalMultiplierFn = fn
	else
		externalMultiplierFn = nil
	end
end

return ProgressionService
