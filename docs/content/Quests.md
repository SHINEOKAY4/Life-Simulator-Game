---
title: Quest API
---

# Quest API

A lightweight quest/task system for the Life-Simulator-Game Roblox Luau project.

## Overview

- Quests are defined with multiple objectives and can form chains via prerequisites.
- Per-player progress is tracked in-memory (suitable for scripts/tests) and can be wired to DataStore in production.
- Rewards support currency, XP, and items. Some quests can auto-claim on completion.

## Core Concepts

- `QuestDefinition`: single quest description with an `id`, objectives, and rewards.
- `Objective`: single target to complete (`Collect`, `Place`, `Talk`, `Visit`, and similar).
- `State`: one of `locked`, `available`, `in_progress`, `completed`, `claimed`.

## API Surface (`src/Server/Services/QuestService.luau`)

- `QuestService.Init()`: initialize catalog and hook into player events
- `QuestService.GetPlayerQuests(player) -> { [questId]: { State, Progress } }`
- `QuestService.StartQuest(player, questId) -> (boolean, string?)`
- `QuestService.ProgressObjective(player, questId, objectiveId, delta) -> (boolean, string?)`
- `QuestService.ReportItemCollected(player, questId, itemDefId, qty) -> (boolean, string?)`
- `QuestService.TriggerObjectiveEvent(player, questId, objectiveId) -> (boolean, string?)`
- `QuestService.ClaimQuest(player, questId) -> (boolean, string?)`
- `QuestService.GetRewardsLog(player) -> { [questId]: rewards }`

## Design Notes

- The system favors a readable, test-friendly in-memory state model.
- In production, wire persistence into `PlayerSession`/`DataStore` and route rewards through `CurrencyService`, `ProgressionService`, and `InventoryService`.

## Usage Examples

- Start a quest for a player when prerequisites are met.
- Progress an objective by triggering a gameplay event (for example, talking to an NPC).
- On completion, either auto-claim or call `ClaimQuest` to grant rewards.
