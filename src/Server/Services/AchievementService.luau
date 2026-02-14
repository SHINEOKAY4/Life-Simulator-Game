--!strict
-- Server/Services/AchievementService.luau
-- Tracks achievement progress, persistence, and claim rewards.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local AchievementDefinitions = require(ReplicatedStorage.Shared.Definitions.AchievementDefinitions)
local AchievementPackets = require(ReplicatedStorage.Network.AchievementPackets)
local PlayerSession = require(ServerScriptService.Server.Services.PlayerSession)
local CurrencyService = require(ServerScriptService.Server.Services.CurrencyService)

type AchievementDefinition = {
	Id: string,
	Name: string,
	Description: string,
	Category: string,
	StatKey: string,
	TargetValue: number,
	SortOrder: number,
	Rewards: { Cash: number?, Experience: number? }?,
}

type AchievementState = {
	Version: number,
	Stats: { [string]: number },
	Unlocked: { [string]: number },
	Claimed: { [string]: number },
}

local CURRENT_VERSION = 1

local AchievementService = {}

local function now(): number
	return Workspace:GetServerTimeNow()
end

local function asWholePositive(value: any): number
	if typeof(value) ~= "number" or value ~= value or value < 0 then
		return 0
	end
	return math.max(0, math.floor(value + 0.5))
end

local function ensureState(profile: { [string]: any }): AchievementState
	local state = profile.AchievementState
	if typeof(state) ~= "table" then
		state = {}
		profile.AchievementState = state
	end

	if typeof(state.Version) ~= "number" then
		state.Version = CURRENT_VERSION
	end
	if typeof(state.Stats) ~= "table" then
		state.Stats = {}
	end
	if typeof(state.Unlocked) ~= "table" then
		state.Unlocked = {}
	end
	if typeof(state.Claimed) ~= "table" then
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

	return state :: AchievementState
end

local function definitionProgress(state: AchievementState, definition: AchievementDefinition)
	local current = asWholePositive(state.Stats[definition.StatKey])
	local target = math.max(1, asWholePositive(definition.TargetValue))
	local progress = math.min(current, target)
	local isUnlocked = state.Unlocked[definition.Id] ~= nil or current >= target
	local isClaimed = state.Claimed[definition.Id] ~= nil
	return current, progress, target, isUnlocked, isClaimed
end

local function buildSnapshotFromState(state: AchievementState): { [string]: any }
	local rows = table.create(#AchievementDefinitions.List)
	local unlockedCount = 0
	local claimedCount = 0

	for _, definition in ipairs(AchievementDefinitions.List) do
		local current, progress, target, isUnlocked, isClaimed = definitionProgress(state, definition)
		if isUnlocked then
			unlockedCount += 1
		end
		if isClaimed then
			claimedCount += 1
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
		TotalCount = #AchievementDefinitions.List,
		Stats = state.Stats,
	}
end

local function sendSnapshot(player: Player, state: AchievementState)
	AchievementPackets.SnapshotUpdated:FireClient(player, buildSnapshotFromState(state))
end

local function getStateForPlayer(player: Player, shouldAwait: boolean): AchievementState?
	local profile = if shouldAwait then PlayerSession.GetDataAwait(player) else PlayerSession.GetData(player)
	if typeof(profile) ~= "table" then
		return nil
	end
	return ensureState(profile)
end

local function getProgressionService()
	local module = require(ServerScriptService.Server.Services.ProgressionService)
	return module
end

local function tryUnlockDefinition(
	player: Player,
	state: AchievementState,
	definition: AchievementDefinition,
	unlockedIds: { string }
)
	local _, _, target, isUnlocked, _ = definitionProgress(state, definition)
	if isUnlocked and state.Unlocked[definition.Id] == nil then
		state.Unlocked[definition.Id] = now()
		unlockedIds[#unlockedIds + 1] = definition.Id
		AchievementPackets.AchievementUnlocked:FireClient(player, {
			AchievementId = definition.Id,
			UnlockedAt = state.Unlocked[definition.Id],
		})
	end
	-- Snap to target for cleaner displays once unlocked.
	if isUnlocked then
		local current = asWholePositive(state.Stats[definition.StatKey])
		if current < target then
			state.Stats[definition.StatKey] = target
		end
	end
end

local function applyStatDelta(player: Player, statKey: string, delta: number, overwriteMaxValue: boolean?)
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

	local unlockedIds: { string } = {}
	for _, definition in ipairs(AchievementDefinitions.List) do
		if definition.StatKey == statKey then
			tryUnlockDefinition(player, state, definition, unlockedIds)
		end
	end

	sendSnapshot(player, state)
end

function AchievementService.GetSnapshot(player: Player): { [string]: any }?
	local state = getStateForPlayer(player, false)
	if not state then
		return nil
	end
	return buildSnapshotFromState(state)
end

function AchievementService.RecordBuildPlaced(player: Player, quantity: number?)
	local increment = if typeof(quantity) == "number" and quantity > 0 then asWholePositive(quantity) else 1
	applyStatDelta(player, "BuildPlacements", increment)
end

function AchievementService.RecordChoreCompleted(player: Player)
	applyStatDelta(player, "ChoresCompleted", 1)
end

function AchievementService.RecordTenantHelpCompleted(player: Player)
	applyStatDelta(player, "TenantHelpsCompleted", 1)
end

function AchievementService.RecordCraftCompleted(player: Player)
	applyStatDelta(player, "CraftingJobsCompleted", 1)
end

function AchievementService.RecordLevelReached(player: Player, level: number)
	applyStatDelta(player, "HighestLevelReached", level, true)
end

local function claimAchievement(player: Player, achievementId: string): (boolean, string, any)
	if typeof(achievementId) ~= "string" or achievementId == "" then
		return false, "Invalid achievement id.", nil
	end

	local definition = AchievementDefinitions.GetById(achievementId)
	if not definition then
		return false, "Achievement not found.", nil
	end

	local profile = PlayerSession.GetData(player)
	if typeof(profile) ~= "table" then
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
		local currencyState = profile.CurrencyState
		if typeof(currencyState) ~= "table" then
			profile.CurrencyState = {}
			currencyState = profile.CurrencyState
		end
		CurrencyService.Add(player, "Cash", rewardCash, currencyState, {
			Source = "Achievement:" .. definition.Id,
		})
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

local function handleGetSnapshot(player: Player): (boolean, string, any)
	local state = getStateForPlayer(player, true)
	if not state then
		return false, "Profile unavailable.", nil
	end
	return true, "", buildSnapshotFromState(state)
end

function AchievementService.Init()
	AchievementPackets.GetSnapshot.OnServerInvoke = function(player: Player)
		return handleGetSnapshot(player)
	end

	AchievementPackets.ClaimAchievement.OnServerInvoke = function(player: Player, achievementId: string)
		return claimAchievement(player, achievementId)
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
				if typeof(levelValue) == "number" then
					applyStatDelta(player, "HighestLevelReached", levelValue, true)
				else
					sendSnapshot(player, state)
				end
			end
		end)
	end)
end

return AchievementService
