--!strict
-- ServerScriptService/Server/Services/ProgressionService.luau
-- Centralized leveling and XP tracking used by build, chores, and tenant interactions.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local ProgressionConfig = require(ReplicatedStorage.Shared.Configurations.ProgressionConfig)
local ProgressionPackets = require(ReplicatedStorage.Network.ProgressionPackets)
local PlayerSession = require(ServerScriptService.Server.Services.PlayerSession)

export type ProgressionState = {
	Level: number,
	Experience: number,
	UnlockedItems: { [string]: boolean }?,
}

type UnlockMap = { [string]: boolean }

local ProgressionService = {}
local RuntimeUnlockCache: { [number]: UnlockMap } = {}

local function resolveRequiredLevel(spec: { [string]: any }?): number
	if typeof(spec) ~= "table" then
		return 1
	end
	local required = spec.RequiredLevel
	if typeof(required) ~= "number" then
		return 1
	end
	if required ~= required or required < 1 then
		return 1
	end
	return math.floor(required + 0.5)
end

local function xpForLevel(level: number): number
	local base = ProgressionConfig.BaseExperience
	local growth = ProgressionConfig.GrowthFactor
	if level <= 1 then
		return math.floor(base + 0.5)
	end
	return math.floor(base * (growth ^ (level - 1)) + 0.5)
end

local function computeProgress(totalXp: number): (number, number, number)
	local level = 1
	local remaining = math.max(0, totalXp)
	local nextRequirement = xpForLevel(level)
	local maxLevel = ProgressionConfig.MaxLevel or 50

	while level < maxLevel and remaining >= nextRequirement do
		remaining -= nextRequirement
		level += 1
		nextRequirement = xpForLevel(level)
	end

	if level >= maxLevel then
		remaining = 0
		nextRequirement = 0
	end

	return level, remaining, nextRequirement
end

local function applyUnlocksForLevel(state: ProgressionState, targetLevel: number): { string }
	local unlocks: { string } = {}
	local map = state.UnlockedItems
	if typeof(map) ~= "table" then
		map = {}
		state.UnlockedItems = map
	end

	local unlockCatalog = ProgressionConfig.UnlocksByLevel
	if typeof(unlockCatalog) ~= "table" then
		return unlocks
	end

	for requiredLevel = 1, targetLevel do
		local ids = unlockCatalog[requiredLevel]
		if typeof(ids) == "table" then
			for _, itemId in ipairs(ids) do
				if typeof(itemId) == "string" and itemId ~= "" and map[itemId] ~= true then
					map[itemId] = true
					unlocks[#unlocks + 1] = itemId
				end
			end
		end
	end

	return unlocks
end

local function syncAttributes(player: Player, level: number, totalXp: number, xpIntoLevel: number, xpForNext: number)
	player:SetAttribute("PlayerLevel", level)
	player:SetAttribute("PlayerExperience", totalXp)
	player:SetAttribute("PlayerXPIntoLevel", xpIntoLevel)
	player:SetAttribute("PlayerXPForNext", xpForNext)
end

local function hydrateState(player: Player): ProgressionState?
	local state = PlayerSession.GetDataAwait(player, "ProgressionState") :: ProgressionState?
	if not state then
		return nil
	end

	if typeof(state.Level) ~= "number" then
		state.Level = 1
	end
	if typeof(state.Experience) ~= "number" then
		state.Experience = 0
	end
	if typeof(state.UnlockedItems) ~= "table" then
		state.UnlockedItems = {}
	end

	local level, xpIntoLevel, xpForNext = computeProgress(state.Experience)
	state.Level = level
	applyUnlocksForLevel(state, level)
	RuntimeUnlockCache[player.UserId] = state.UnlockedItems
	syncAttributes(player, level, state.Experience, xpIntoLevel, xpForNext)

	return state
end

local function broadcastProgression(
	player: Player,
	state: ProgressionState,
	delta: number,
	reason: string,
	newUnlocks: { string }
)
	local level, xpIntoLevel, xpForNext = computeProgress(state.Experience)
	ProgressionPackets.ProgressionUpdate:FireClient(player, {
		Level = level,
		ExperienceTotal = state.Experience,
		ExperienceIntoLevel = xpIntoLevel,
		ExperienceForNext = xpForNext,
		Delta = delta,
		Reason = reason,
		UnlockedItemIds = newUnlocks,
	})
end

function ProgressionService.GetLevel(player: Player): number
	local attr = player:GetAttribute("PlayerLevel")
	if typeof(attr) == "number" then
		return attr
	end
	local state = hydrateState(player)
	return state and state.Level or 1
end

function ProgressionService.CanPlaceItem(
	player: Player,
	itemSpec: { [string]: any }?,
	itemId: string?
): (boolean, string?)
	local state = hydrateState(player)
	if not state then
		return false, "Progression data unavailable."
	end
	local requiredLevel = resolveRequiredLevel(itemSpec)
	local currentLevel = select(1, computeProgress(state.Experience))
	state.Level = currentLevel
	local unlockedMap = RuntimeUnlockCache[player.UserId]
	if unlockedMap and itemId and unlockedMap[itemId] then
		return true, nil
	end
	if currentLevel < requiredLevel then
		return false, string.format("Reach level %d to place this item.", requiredLevel)
	end
	return true, nil
end

function ProgressionService.AwardExperience(player: Player, amount: number, reason: string): number
	if amount <= 0 then
		return ProgressionService.GetLevel(player)
	end

	local state = hydrateState(player)
	if not state then
		return 1
	end

	local previousLevel = select(1, computeProgress(state.Experience))
	state.Experience += math.floor(amount + 0.5)
	local level, xpIntoLevel, xpForNext = computeProgress(state.Experience)
	state.Level = level

	local newUnlocks = if level > previousLevel then applyUnlocksForLevel(state, level) else {}
	RuntimeUnlockCache[player.UserId] = state.UnlockedItems
	syncAttributes(player, level, state.Experience, xpIntoLevel, xpForNext)
	broadcastProgression(player, state, amount, reason, newUnlocks)

	return level
end

local function computePlacementReward(spec: { [string]: any }?, quantity: number?): number
	local rewards = ProgressionConfig.ActionRewards
	local base = rewards.BuildPlacementBase or 0
	local perUnit = rewards.BuildPlacementPerCell or 0
	local premiumBonus = rewards.PremiumPlacementBonus or 0

	local units = if typeof(quantity) == "number" and quantity > 0 then math.floor(quantity + 0.5) else 1
	local total = base + perUnit * units

	if spec and typeof(spec.Cost) == "number" and spec.Cost >= 1200 then
		total += premiumBonus
	end

	return math.max(1, math.floor(total + 0.5))
end

function ProgressionService.RecordBuildPlacement(player: Player, itemSpec: { [string]: any }?, quantity: number?)
	local reward = computePlacementReward(itemSpec, quantity)
	ProgressionService.AwardExperience(player, reward, "BuildPlacement")
end

function ProgressionService.RecordChoreCompletion(player: Player)
	local rewards = ProgressionConfig.ActionRewards
	ProgressionService.AwardExperience(player, rewards.ChoreCompleted or 10, "ChoreCompleted")
end

function ProgressionService.RecordTenantHelped(player: Player)
	local rewards = ProgressionConfig.ActionRewards
	ProgressionService.AwardExperience(player, rewards.TenantHelped or 15, "TenantHelped")
end

function ProgressionService.Init()
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

return ProgressionService
