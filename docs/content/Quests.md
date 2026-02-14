# Quest API

A lightweight Quest/Task system for the Life-Simulator-Game Roblox Luau project.

Overview
- Quests are defined with multiple objectives and can form chains via prerequisites.
- Per-player progress is tracked in-memory (suitable for scripts/tests) and can be wired to DataStore in a real game.
- Rewards support currency, XP, and items. Some quests can auto-claim upon completion.

Core Concepts
- QuestDefinition: a single quest description with an id, objectives, and rewards.
- Objective: a single target to complete (Collect, Place, Talk, Visit, etc.).
- State: one of locked, available, in_progress, completed, claimed.

API surface (src/Server/Services/QuestService.luau)
- QuestService.Init(): initialize catalog and hook into player events
- QuestService.GetPlayerQuests(player) -> { [questId]: { State, Progress } }
- QuestService.StartQuest(player, questId) -> (boolean, string?)
- QuestService.ProgressObjective(player, questId, objectiveId, delta) -> (boolean, string?)
- QuestService.ReportItemCollected(player, questId, itemDefId, qty) -> (boolean, string?)
- QuestService.TriggerObjectiveEvent(player, questId, objectiveId) -> (boolean, string?)
- QuestService.ClaimQuest(player, questId) -> (boolean, string?)
- QuestService.GetRewardsLog(player) -> { questId: rewards }

Design notes
- The system favors a readable, test-friendly approach with in-memory state. In production, you would hook into PlayerSession/DataStore to persist quest progress, and route rewards through CurrencyService, ProgressionService, and InventoryService.

Usage examples
- Start a quest for a player when prerequisites are met.
- Progress an objective by triggering an event (e.g., player talks to an NPC).
- On completion, either auto-claim or call ClaimQuest to grant rewards.
