-- QuestService Behavior Tests (Luau-style)
-- This spec exercises the QuestService public API implemented in
-- src/Server/Services/QuestService.luau

local function safeRequireQuest()
    local QuestModule = nil
    local ok, mod = pcall(function()
        return require(script.Parent.Parent:FindFirstChild("QuestService") or script.Parent.Parent:FindFirstChild("QuestService.luau"))
    end)
    if ok and mod then
        return mod
    end
    local ok2, mod2 = pcall(function()
        return dofile("src/Server/Services/QuestService.luau")
    end)
    if ok2 and mod2 then
        return mod2
    end
    error("Unable to load QuestService module for tests")
end

local QuestService = safeRequireQuest()

local function run()
    local function assertEq(a, b, msg)
        if a ~= b then
            error((msg or "Assertion failed") .. ": expected " .. tostring(b) .. ", got " .. tostring(a))
        end
    end

    -- Init catalog and service
    QuestService.Init()

    -- Mock player
    local player = { UserId = 1, Name = "Tester" }

    -- Ensure we can fetch and inspect quests
    QuestService.RefreshPlayerStates(player)
    local states = QuestService.GetPlayerQuests(player)
    assertEq(states and states.quest_basic and states.quest_basic.State, "available", "quest_basic should be available initially")

    -- Start the first quest
    local ok, err = QuestService.StartQuest(player, "quest_basic")
    assertEq(ok, true, "Should start quest_basic: " .. tostring(err))
    states = QuestService.GetPlayerQuests(player)
    assertEq(states.quest_basic.State, "in_progress", "quest_basic should be in_progress after start")
    -- Progress the first objective partially
    local success, e = QuestService.ProgressObjective(player, "quest_basic", "collect_coins", 10)
    assertEq(success, true, e or "progress failed")
    -- Progress the second objective to completion via an explicit trigger
    QuestService.TriggerObjectiveEvent(player, "quest_basic", "visit_npc")
    states = QuestService.GetPlayerQuests(player)
    assertEq(states.quest_basic.State, "completed", "quest_basic should be completed after all objectives met")

    -- Claim rewards for the first quest
    local claimed, claimErr = QuestService.ClaimQuest(player, "quest_basic")
    assertEq(claimed, true, claimErr or nil)
    states = QuestService.GetPlayerQuests(player)
    assertEq(states.quest_basic.State, "claimed", "quest_basic should be claimed after reward")

    -- Access rewards log for the first quest
    local rewardsLog = QuestService.GetRewardsLog(player)
    assertEq(rewardsLog.quest_basic ~= nil, true, "RewardsLog should contain quest_basic rewards")

    -- Hydrate and test chain quest availability after completion of prerequisite
    QuestService.RefreshPlayerStates(player)
    local states2 = QuestService.GetPlayerQuests(player)
    -- quest_chain_2 depends on quest_basic; it should become available now
    assertEq(states2.quest_chain_2.State, "available", "quest_chain_2 should be available after completing prerequisites")

    -- Start chain quest2
    local ok2, err2 = QuestService.StartQuest(player, "quest_chain_2")
    assertEq(ok2, true, err2 or "start failed")
    local st2 = QuestService.GetPlayerQuests(player).quest_chain_2
    assertEq(st2.State, "in_progress", "quest_chain_2 should be in_progress after start")
    -- Complete its only objective
    QuestService.TriggerObjectiveEvent(player, "quest_chain_2", "place_chest")
    -- Since AutoClaim is true, it should auto-claim on completion
    st2 = QuestService.GetPlayerQuests(player).quest_chain_2
    assertEq(st2.State, "claimed", "quest_chain_2 should be auto-claimed on completion")
end

return { run = run }
