# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

A Roblox life simulator game written in Luau (`.luau`). Players claim plots, build housing, manage tenants, and progress through seasonal events and quests. Rojo syncs the `src/` tree into Roblox Studio; the game is not runnable from the terminal.

## Commands

**Run all tests:**
```bash
./run_tests.sh
```

**Run a single spec:**
```bash
busted Tests/Specs/SomeSpec.lua
```
(Requires `luarocks` and `busted` installed; `run_tests.sh` sets up the path.)

**Lint Luau source:**
```bash
selene src/
```

**Sync to Roblox Studio (development):**
```bash
rojo serve
```

**Build docs:**
```bash
npm run build --prefix docs
```

Tools (`rojo`, `selene`) are managed by Aftman (`aftman.toml`); install via `aftman install`.

## Source Layout → Roblox Instance Tree

| Filesystem path | Roblox service |
|---|---|
| `src/Server/` | `ServerScriptService.Server` |
| `src/Client/` | `StarterPlayer.StarterPlayerScripts.Client` |
| `src/Shared/` | `ReplicatedStorage.Shared` |
| `src/Network/` | `ReplicatedStorage.Network` |
| `Packages/` | `ReplicatedStorage.Packages` |
| `ServerPackages/` | `ServerStorage.ServerPackages` |

## Architecture

### Startup

Both sides follow the same pattern: all modules are `require`d at the top of `Main.server.luau` / `Main.client.luau`, then each is initialized inside a `StartupDiagnostics:Boundary()` call that logs timing and surfaces errors. Service ordering in the startup sequence matters (e.g., `QuestService` before `DailyRewardService`).

### Server (`src/Server/`)

- **Services/** — One module per domain, each exposes an `Init()` function. Key ones:
  - `PlayerSession` — wraps the `DataStore` package from `ServerPackages`; provides `GetDataAwait`, `GetData`, `TryGetData`, `IsReady`. Player data schema lives in `PlayerSession/Profile.luau`.
  - `PlotService` — plot claiming, unlocking chunks, firing `PlotClaimed` signal.
  - `BuildService` — delegates placement mutations to action modules under `BuildService/Actions/`.
  - `TenantService` — lease management, mailbox, offers, room assignments; split into sub-managers under `TenantService/`.
  - `BillingService`, `ProgressionService`, `AchievementService`, `WorldEventService`, `SeasonalEventService`, `QuestService`, `DailyRewardService`.
- **Classes/** — Stateful objects: `PlotState` (chunked grid of placements, walls, floors, roofs) and `ResidentState`.
- **Utilities/** — Pure helpers: `PlotSerializationUtils`, `WorldPlacer`, `WorldUpdate`, `BillingCalculator`.

### Client (`src/Client/`)

- **ClientStores/** — Receive server state via packets and expose a query API. `PlotStateStore` is the most complex: it caches a `StateSnapshot`, builds lazy `LevelDerivedSnapshot` caches per floor level, and exposes room/floor/wall query APIs. Room data is server-authoritative and arrives via `RoomDataSync`.
- **Modules/** — One controller per feature. Each exposes `Init()` (or `Start()`). They consume packets and update UI.
- **UserInterface/** — UI modules, each exposes `Init()`.

### Shared (`src/Shared/`)

- **Configurations/** — BuildConstants, TenantConfig, WeatherConfig, etc.
- **Definitions/** — Catalog items (furniture, appliances, etc.), progression, crafting recipes, achievement/seasonal/world event definitions, tenant traits.
- **Utilities/** — Pure logic usable on both sides: `RoomCore` (flood fill), `Grid`, `PlacementBehavior`, `ItemFinder`, `StartupDiagnostics`, `RNGUtil`, etc.
- **Modules/** — Shim layer that re-exports from `Utilities/`, `Configurations/`, and `Definitions/`. These exist only for backwards compatibility with legacy paths (`ReplicatedStorage.Shared.Modules.*`). **Do not add new logic here** — add it to the canonical location and add a shim if needed.

### Network (`src/Network/`)

Each feature domain has a packet file (e.g., `PlacementPackets`, `TenantPackets`). Packets are defined using `require(ReplicatedStorage.Packages.Packet)`. The client preloads all packet modules at startup before any remotes can fire. When adding a new domain, add a packet file here and preload it in `Main.client.luau`.

## Key Conventions

- **Service modules** are singletons (plain tables with `Init()`). They do not return class instances.
- **`--!strict`** is used throughout server and shared code; keep new files consistent.
- **Player data** is accessed exclusively through `PlayerSession.GetDataAwait(player, "CategoryName")`. The profile schema in `Profile.luau` is the single source of truth — add new state categories there.
- **Room detection** is server-authoritative. The server runs `FloodFillCore`/`RoomCore` and pushes results via `RoomDataSync`. The client never re-derives rooms.
- **Build grid** uses a chunk system. The plot is divided into `ChunkColumns × ChunkRows` chunks, each `ChunkSizeInCells` per side. Cells use 1-based (X, Z) indexing.
- **Test files** use plain `.lua` (not `.luau`) and directly `loadfile()` Luau source to avoid the Roblox runtime dependency. Tests run under `busted` with standard `describe`/`it`/`assert` API.
