--!strict
-- QuestService.luau
-- Lightweight Quest/Task system for players. This module provides:
--  - quest definitions with multiple objectives
--  - per-player progress tracking
--  - rewards (currency, XP, items) and simple quest chains via prerequisites
--  - quest states: locked, available, in_progress, completed, claimed
--  - auto-completion hooks (when all objectives are satisfied)

local Players = game:GetService("Players")

-- Local minimal config fallback if no global config is present.
local QuestsConfig = nil
do
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

-- Types for better tooling (not strictly required at runtime)
export type Objective = {
    id: string,
    kind: string, -- e.g. "Collect", "Place", "Talk", "Visit"
    target: any,  -- number for quantitative goals, string for named targets
    progress?: number,
}

export type QuestDefinition = {
    id: string,
    name?: string,
    prerequisites?: { string }?, -- quest ids that must be completed before available
    objectives: { Objective },
    rewards?: {
        Currency?: { Name: string, Amount: number }[],
        XP?: number,
        Items?: { DefId: string, Quantity: number }[],
    },
    AutoClaim?: boolean, -- if true, reward is granted and quest is marked claimed immediately on completion
}

export type QuestState = {
    State: string, -- one of: "locked", "available", "in_progress", "completed", "claimed"
    Progress: { [string]: number }, -- objectiveId -> progress
}

type PlayerQuestState = { [string]: QuestState }

-- Runtime storage (per player) for quick unit tests without DataStore integration
local PlayerQuests: { [number]: PlayerQuestState } = {}

local function _getPlayerKey(player: any): string
    return tostring(player and (player.UserId or player.Name) or "unknown")
end

-- The in-memory quest catalog (id -> QuestDefinition)
local QuestCatalog: { [string]: QuestDefinition } = {}

-- Simple in-memory log of rewards granted per player per quest (for tests/QA)
local RewardsLog: { [number]: { [string]: any } } = {}

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
local function HydratePlayer(player: any): { [string]: QuestState }
    local key = _getPlayerKey(player)
    if PlayerQuests[tonumber(key) or key] == nil then
        PlayerQuests[tonumber(key) or key] = {}
        -- initialize for all quests: locked unless prerequisites satisfied
        for id, def in pairs(QuestCatalog) do
            local state: QuestState = { State = "locked", Progress = {} }
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

local function getStateForQuest(player: any, questId: string): QuestState?
    local st = HydratePlayer(player)[questId]
    return st
end

local function ensureQuestExists(questId: string): QuestDefinition?
    loadCatalogIfNeeded()
    return QuestCatalog[questId]
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
function QuestService.RefreshPlayerStates(player: any)
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
function QuestService.GetPlayerQuests(player: any): { [string]: QuestState }?
    if not player then return nil end
    return HydratePlayer(player)
end

-- Get the rewards log for a player (for tests/QA)
function QuestService.GetRewardsLog(player: any): { [string]: any }?
    if not player then return nil end
    local key = _getPlayerKey(player)
    return RewardsLog[key] or {}
end

-- Start a quest if it is available
function QuestService.StartQuest(player: any, questId: string): boolean, string?
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
function QuestService.ProgressObjective(player: any, questId: string, objectiveId: string, delta: number): boolean, string?
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
function QuestService.ReportItemCollected(player: any, questId: string, itemDefId: string, qty: number): boolean, string?
    local quest = ensureQuestExists(questId)
    if not quest then return false, "UnknownQuest" end
    local state = getStateForQuest(player, questId)
    if not state or state.State ~= "in_progress" then return false, "NotInProgress" end
    -- find any Collect objective for this itemDefId
    local progressed = false
    for _, o in ipairs(quest.objectives) do
        if o.kind == "Collect" and o.target == itemDefId then
            state.Progress[o.id] = (state.Progress[o.id] or 0) + (qty or 1)
            progressed = true
        end
    end
    if not progressed then
        return false, "NoMatchingObjective"
    end
    -- Re-run completion check
    return QuestService.ProgressObjective(player, questId, quest.objectives[1].id, 0) -- trigger completion check without extra progress
        or true, nil
end

-- Place/Talk/Visit helpers: callers can signal a trigger by objective id
function QuestService.TriggerObjectiveEvent(player: any, questId: string, objectiveId: string): boolean, string?
    -- simply bump progress by 1 for the given objective
    return QuestService.ProgressObjective(player, questId, objectiveId, 1)
end

-- Claim rewards for a completed quest
function QuestService.ClaimQuest(player: any, questId: string): boolean, string?
    local quest = ensureQuestExists(questId)
    if not quest then return false, "UnknownQuest" end
    local state = getStateForQuest(player, questId)
    if not state or state.State ~= "completed" then return false, "NotCompletable" end
    -- Reward application is stubbed for testability: we log rewards instead of mutating
    if quest.Rewards then
        local rewards = quest.Rewards
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

return QuestService
