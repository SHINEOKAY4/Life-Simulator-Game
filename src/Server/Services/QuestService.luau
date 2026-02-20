--!strict
-- QuestService.luau
-- Lightweight Quest/Task system for players. This module provides:
--  - quest definitions with multiple objectives
--  - per-player progress tracking
--  - rewards (currency, XP, items) and simple quest chains via prerequisites
--  - quest states: locked, available, in_progress, completed, claimed
--  - auto-completion hooks (when all objectives are satisfied)
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

-- Local minimal config fallback if no global config is present.
local QuestsConfig = nil
if IS_ROBLOX then
    local ok, cfg = pcall(function()
        return require(game:GetService("ReplicatedStorage").Shared.Configurations.QuestsConfig)
    end)
    if ok and type(cfg) == "table" then
        QuestsConfig = cfg
    else
        QuestsConfig = nil
    end
end

local QuestService = {}

-- Type definitions (Luau export types not used to keep loadfile() compatibility)
-- Objective: { id: string, kind: string, target: any, progress?: number }
-- QuestDefinition: { id: string, name?: string, prerequisites?: {string},
--   objectives: {Objective}, rewards?: { Currency?, XP?, Items? }, AutoClaim?: boolean }
-- QuestState: { State: string, Progress: { [string]: number } }
-- PlayerQuestState: { [string]: QuestState }

-- Runtime storage (per player) for quick unit tests without DataStore integration
local PlayerQuests = {} -- [playerKey] -> PlayerQuestState

local function _getPlayerKey(player)
    return tostring(player and (player.UserId or player.Name) or "unknown")
end

-- The in-memory quest catalog (id -> QuestDefinition)
local QuestCatalog = {}

-- Simple in-memory log of rewards granted per player per quest (for tests/QA)
local RewardsLog = {}

-- Build a small default catalog if no config is provided. This keeps tests deterministic.
local function EnsureDefaultCatalog()
    if next(QuestCatalog) ~= nil then
        return
    end
    -- Simple chain of two quests to demonstrate prerequisites and multiple objectives
    QuestCatalog["quest_basic"] = {
        id = "quest_basic",
        name = "Starter Quest",
        prerequisites = {},
        objectives = {
            { id = "collect_coins", kind = "Collect", target = 10 },
            { id = "visit_npc", kind = "Talk", target = "OldMan" },
        },
        rewards = {
            Currency = { { Name = "Coins", Amount = 50 } },
            XP = 100,
            Items = { { DefId = "starter_badge", Quantity = 1 } },
        },
        AutoClaim = false,
    }
    QuestCatalog["quest_chain_2"] = {
        id = "quest_chain_2",
        name = "Further Trials",
        prerequisites = { "quest_basic" },
        objectives = {
            { id = "place_chest", kind = "Place", target = "Chest" },
        },
        rewards = {
            XP = 60,
            Currency = { { Name = "Coins", Amount = 20 } },
        },
        AutoClaim = true,
    }
end

local function loadCatalogIfNeeded()
    EnsureDefaultCatalog()
end

-- Helpers: get or create a player's quest state table
local function HydratePlayer(player)
    local key = _getPlayerKey(player)
    if PlayerQuests[tonumber(key) or key] == nil then
        PlayerQuests[tonumber(key) or key] = {}
        -- initialize for all quests: locked unless prerequisites satisfied
        for id, def in pairs(QuestCatalog) do
            local state = { State = "locked", Progress = {} }
            -- prerequisites check
            if def.prerequisites == nil or #def.prerequisites == 0 then
                state.State = "available"
            else
                state.State = "locked"
            end
            PlayerQuests[tonumber(key) or key][id] = state
        end
    end
    return PlayerQuests[tonumber(key) or key]
end

local function getStateForQuest(player, questId)
    local st = HydratePlayer(player)[questId]
    return st
end

local function ensureQuestExists(questId)
    loadCatalogIfNeeded()
    return QuestCatalog[questId]
end

local function evaluateQuestCompletion(state, quest)
    local allDone = true
    for _, o in ipairs(quest.objectives) do
        local progress = state.Progress[o.id] or 0
        local target = o.target
        if o.kind == "Place" or o.kind == "Talk" or o.kind == "Visit" then
            -- treat target as a threshold 1-based; progress increments with each trigger
            if type(target) == "number" then
                if progress < target then allDone = false end
            elseif type(target) == "string" then
                if progress < 1 then allDone = false end
            end
        elseif type(target) == "number" then
            if progress < target then allDone = false end
        else
            allDone = false
        end
        if not allDone then break end
    end
    return allDone
end

-- Public API
function QuestService.Init()
    loadCatalogIfNeeded()
    -- Listen for players joining to hydrate their quest state in a real environment
    if Players then
        Players.PlayerAdded:Connect(function(p)
            -- Initialize on-demand; tests may call manually too
            HydratePlayer(p)
        end)
    end
end

-- Recompute all quest states for a player based on prerequisites and current completion
function QuestService.RefreshPlayerStates(player)
    if not player then return end
    local catalog = QuestCatalog
    local key = _getPlayerKey(player)
    PlayerQuests[tonumber(key) or key] = PlayerQuests[tonumber(key) or key] or {}
    local pstate = PlayerQuests[tonumber(key) or key]
    for id, def in pairs(catalog) do
        local st = pstate[id]
        st = st or { State = "locked", Progress = {} }
        -- determine availability by prerequisites
        local prereqOk = true
        if def.prerequisites then
            for _, prereq in ipairs(def.prerequisites) do
                local prereqState = pstate[prereq] or { State = "locked" }
                if prereqState.State ~= "completed" and prereqState.State ~= "claimed" then
                    prereqOk = false
                    break
                end
            end
        end
        if prereqOk and (st.State == "locked" or st.State == nil) then
            st.State = "available"
        end
        pstate[id] = st
    end
end

-- Get a player's current state table for all quests (for tests/diagnostics)
function QuestService.GetPlayerQuests(player)
    if not player then return nil end
    return HydratePlayer(player)
end

-- Get the rewards log for a player (for tests/QA)
function QuestService.GetRewardsLog(player)
    if not player then return nil end
    local key = _getPlayerKey(player)
    return RewardsLog[key] or {}
end

-- Start a quest if it is available
function QuestService.StartQuest(player, questId)
    local quest = ensureQuestExists(questId)
    if not quest then
        return false, "UnknownQuest"
    end
    local state = getStateForQuest(player, questId) or { State = "locked", Progress = {} }
    if state.State ~= "available" then
        return false, "QuestNotAvailable"
    end
    state.State = "in_progress"
    -- initialize progress entries for objectives
    for _, obj in ipairs(quest.objectives) do
        if state.Progress[obj.id] == nil then
            state.Progress[obj.id] = 0
        end
    end
    -- Save back
    local key = _getPlayerKey(player)
    local pstore = PlayerQuests[tonumber(key) or key] or {}
    pstore[questId] = state
    PlayerQuests[tonumber(key) or key] = pstore
    return true
end

-- Generic progress update for an objective by numeric delta
function QuestService.ProgressObjective(player, questId, objectiveId, delta)
    if delta < 0 then delta = 0 end
    local quest = ensureQuestExists(questId)
    if not quest then return false, "UnknownQuest" end
    local state = getStateForQuest(player, questId)
    if not state or state.State ~= "in_progress" then return false, "NotInProgress" end
    local objExists = false
    for _, o in ipairs(quest.objectives) do if o.id == objectiveId then objExists = true; break end end
    if not objExists then return false, "UnknownObjective" end

    state.Progress[objectiveId] = (state.Progress[objectiveId] or 0) + delta

    -- Check each objective completion against its target
    local allDone = evaluateQuestCompletion(state, quest)

    -- If all objectives are completed, auto-complete if configured or mark completed
    if allDone then
        state.State = "completed"
        -- if quest has auto-claim, immediately award rewards and mark claimed
        if quest.AutoClaim == true then
            QuestService.ClaimQuest(player, questId)
        end
    end

    -- Persist
    local key = _getPlayerKey(player)
    local pstore = PlayerQuests[tonumber(key) or key] or {}
    pstore[questId] = state
    PlayerQuests[tonumber(key) or key] = pstore
    return true
end

-- Report a produced item collection for an objective
function QuestService.ReportItemCollected(player, questId, itemDefId, qty)
    local quest = ensureQuestExists(questId)
    if not quest then return false, "UnknownQuest" end
    local state = getStateForQuest(player, questId)
    if not state or state.State ~= "in_progress" then return false, "NotInProgress" end
    -- find any Collect objective for this itemDefId
    local progressed = false
    for _, o in ipairs(quest.objectives) do
        local target = o.target
        local matchesCollectTarget = o.kind == "Collect" and (
            type(target) == "number" -- generic count-based collect objective
            or target == itemDefId -- explicit item id target
            or (type(target) == "table" and target.DefId == itemDefId)
        )
        if matchesCollectTarget then
            state.Progress[o.id] = (state.Progress[o.id] or 0) + (qty or 1)
            progressed = true
        end
    end
    if not progressed then
        return false, "NoMatchingObjective"
    end

    if evaluateQuestCompletion(state, quest) then
        state.State = "completed"
        if quest.AutoClaim == true then
            QuestService.ClaimQuest(player, questId)
        end
    end

    local key = _getPlayerKey(player)
    local pstore = PlayerQuests[tonumber(key) or key] or {}
    pstore[questId] = state
    PlayerQuests[tonumber(key) or key] = pstore
    return true
end

-- Place/Talk/Visit helpers: callers can signal a trigger by objective id
function QuestService.TriggerObjectiveEvent(player, questId, objectiveId)
    -- simply bump progress by 1 for the given objective
    return QuestService.ProgressObjective(player, questId, objectiveId, 1)
end

-- Claim rewards for a completed quest
function QuestService.ClaimQuest(player, questId)
    local quest = ensureQuestExists(questId)
    if not quest then return false, "UnknownQuest" end
    local state = getStateForQuest(player, questId)
    if not state or state.State ~= "completed" then return false, "NotCompletable" end
    -- Reward application is stubbed for testability: we log rewards instead of mutating
    if quest.rewards then
        local rewards = quest.rewards
        local key = _getPlayerKey(player)
        RewardsLog[key] = RewardsLog[key] or {}
        RewardsLog[key][questId] = rewards
    end
    state.State = "claimed"
    -- Persist
    local key = _getPlayerKey(player)
    local pstore = PlayerQuests[tonumber(key) or key] or {}
    pstore[questId] = state
    PlayerQuests[tonumber(key) or key] = pstore
    return true
end

-- Reset all runtime state for test isolation.
function QuestService._ResetForTests()
    PlayerQuests = {}
    QuestCatalog = {}
    RewardsLog = {}
end

return QuestService
