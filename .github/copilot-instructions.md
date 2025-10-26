# Life Simulator - Roblox Game Architecture

## Philosophy & Standards
- Prioritize **elegant, maintainable, readable code** over clever solutions
- Avoid pcalls except for DataStore operations, HTTP requests, and external API calls
- Prefer event-driven patterns over polling loops
- Follow strict type annotations (`--!strict`) throughout codebase
- Server authority for all gameplay logic; clients display only

## Project Structure (Rojo)

```
src/
├── Server/           # ServerScriptService - game logic authority
│   ├── Services/     # Singleton services (PlotService, ResidentService, etc.)
│   ├── Classes/      # Stateful objects (ResidentState, PlotState, ActionQueue)
│   ├── Modules/      # ResidentActionHandlers (behavior specs)
│   └── Utilities/    # Helpers (ResidentMovement, WorldPlacer, etc.)
├── Client/           # StarterPlayerScripts - UI and visuals only
│   ├── Modules/      # Client-side managers (PlotBuilder, ObjectSelector)
│   ├── ClientStores/ # Replicated state caches (PlotStateStore, ResidentsStore)
│   └── UserInterface/ # UI components (MainHUD, ResidentRoster, etc.)
├── Shared/           # ReplicatedStorage - definitions, utilities, configs
│   ├── Configurations/ # NeedConfig, CareerShiftConfig, JobCatalog, TraitConfig
│   ├── Definitions/  # Static game data (items, billing constants)
│   └── Utilities/    # ItemFinder, PlotFinder, TimeScale, TraitUtils
└── Network/          # ReplicatedStorage - Packet definitions (typed remotes)
    ├── ResidentsPackets.luau    # Resident creation/deletion/sync
    ├── PlacementPackets.luau    # Plot claiming/building/unlocking
    ├── JobPackets.luau          # Career management
    ├── GigPackets.luau          # Player gig system
    └── BillingPackets.luau      # Payment/billing info
```

## Core Architectural Patterns

### 1. **Network Communication: Packet Library**
- **Never use RemoteEvents/RemoteFunctions directly** - use `Packages/Packet` for all client-server communication
- Define packets in `src/Network/*Packets.luau` with typed parameters:
  ```lua
  ResidentsPackets.AddResidentRequest = Packet("CreateResidentRequest", {
      Name = Packet.String,
      Gender = Packet.String,
  }):Response(Packet.Boolean8, Packet.StringLong)
  ```
- Server: `Packet.OnServerInvoke` (request/response) or `OnServerEvent` (fire-and-forget)
- Client: `Packet:Fire()` or `Packet.OnClientEvent:Connect()`

### 2. **Resident Lifecycle & Autonomy System**
- **ResidentState** (`Server/Classes/ResidentState.luau`): Stateful object wrapping resident data
  - Owns `ActionQueue` (serialized action execution)
  - Maintains `CancelToken` for interrupting actions
  - Tracks `IsBusy`, `CurrentAction`, `CurrentOverride` (manual vs autonomous)
- **ResidentAutonomyService** (`Server/Services/ResidentAutonomyService/`):
  - Runs evaluation loop via `WorldUpdate.Subscribe()` (~0.8s intervals)
  - `NeedEvaluator` scores needs (Hunger, Energy, etc.) and picks best station
  - `FallbackActions` handles roaming, begging, job evaluation when no needs critical
  - `ActionQueue.enqueueNeedAction()` assigns station and queues handler execution
- **DirectActionService**: Manual player overrides (click resident → assign station)
  - Disables autonomy, prepares resident (`WaitUntilIdle`), queues `ManualOverride:*` action
  - Re-enables autonomy after action completes

### 3. **Station & Occupancy Management**
- **PlotService** maintains `PlayerStations` cache: `[userId][stationType][uniqueId] = StationRecord`
  - `StationRecord`: `{ Id, Residents, Occupied, Model, ActiveOverride }`
  - `GetStationsForPlayer()` returns versioned cache (invalidates on build changes)
- **StationManager** (`ResidentAutonomyService/StationManager.luau`):
  - `findAvailableStation()` filters by occupancy (`maxOccupancy`), power outage overrides
  - `releaseStationOccupancy()` cleans up resident from station after action ends
- **ResidentActionHandlers** (`Server/Modules/ResidentActionHandlers.luau`):
  - Registers behavior specs per station type (RestStation, CookStation, etc.)
  - Defines: approach distance, duration, effects (need deltas), moodlets, chat phrases
  - Handles seated vs lying (rest pose) stations, emergency guards (critical need interrupts)

### 4. **Plot Building & Placement**
- **PlotState** (`Server/Classes/PlotState/`): Grid-based state machine
  - Tracks unlocked chunks, cell occupancy, floor/roof/wall placement
  - Validation methods: `CanPlaceWall`, `CanPlaceCellObject`, `HasAdjacentUnlocked`
  - Saves compact: `{ UnlockedChunks = {{cx, cz}, ...}, PlacedObjects = {[key] = {id, cellX, cellZ, facing, Metadata}, ...} }`
- **BuildService** (`Server/Services/BuildService/`): Server authority for placement
  - Validates requests via `PlotService.GetState()`, updates grid, spawns world models via `WorldPlacer`
  - Fires delta packets (`PlacementPackets.PlotStateDelta`) for client replication
- **Client PlotBuilder** (`Client/Modules/PlotBuilder.luau`): Ghost preview + input handling
  - Listens to delta packets, rebuilds local world, validates placement client-side (red/green preview)

### 5. **Data Persistence: PlayerSession & DataStore Wrapper**
- **PlayerSession** (`Server/Services/PlayerSession/`):
  - Wraps `ServerPackages/DataStore` (custom session manager with auto-save, locking, compression)
  - Profile schema in `PlayerSession/Profile.luau`: `PlotState`, `HouseholdState`, `CurrencyState`, etc.
  - **Always use `PlayerSession.GetDataAwait(player, "Category")`** - blocks until DataStore ready
  - **Non-blocking**: `PlayerSession.TryGetData(player, "Category")` returns nil if not ready
- **DataStore wrapper** features:
  - Auto-save intervals, manual `dataStore:Save()`, session locking (prevents multi-server corruption)
  - Reconciles template on first load, handles retries, exposes signals (`Saving`, `Saved`, `StateChanged`)

### 6. **Career vs Gig Duality**
- **Careers** (resident passive income): `CareerService` + `JobListingService`
  - Residents auto-work shifts when `AutoJobEnabled`, earn hourly pay scaled by mood/stats/momentum
  - Shift lifecycle: `StartShift()` → tracks energy decay → `EndShift()` → payout via `PayrollService`
- **Gigs** (player active income): `GigService` (not yet fully implemented)
  - Player-controlled minigames with cooldowns, daily slot limits, performance tiers (Bronze/Silver/Gold)
  - Successful gigs grant `MomentumBoost` (+10% career payout for 1 in-game hour)

### 7. **Billing & Economy**
- **BillingService** (`Server/Services/BillingService.luau`):
  - Recurring bills every 480s real-time: plot tax, electricity (tracked via `EnergyUsageTracker`), food usage
  - Grace period → overdue → power outage escalation (disables energy stations)
  - `BillingState` class tracks cycle state, grace elapsed, overdue count
- **CurrencyService**: Atomic currency operations, rate limiting, transaction logging
  - `AddCurrency(player, amount, source)` / `DeductCurrency(player, amount, reason)`

## Key Workflows

### Adding a New Station Type
1. Define item in `Shared/Definitions/Items/` with `stationType`, `maxOccupancy`, effects
2. Register handler in `Server/Modules/ResidentActionHandlers.luau`:
   ```lua
   DirectActionService.RegisterHandler("NewStationType", function(context, assignment)
       -- Behavior: movement, seating, effects, chat, end conditions
   end)
   ```
3. Add to `ResidentAutonomyService/State.luau`: `NeedToStationType`, evaluation order
4. Update `NeedConfig.luau` if introducing new need

### Debugging Residents
- Enable channels in `Server/Main.server.luau`:
  ```lua
  local _ResidentDebug = require(ServerScriptService.Server.Utilities.ResidentDebug)
  _ResidentDebug.SetChannelEnabled("Movement", true)
  _ResidentDebug.SetChannelEnabled("Action", true)
  ```
- Check `ResidentState` attributes: `CurrentAction`, `IsBusy`, need values mirrored to model attributes

### Build & Run
- **Rojo**: `rojo serve` (default.project.json) → Roblox Studio sync plugin
- **Aftman**: Toolchain manager (rojo version in aftman.toml)
- **Selene**: Linter configured for `std = "roblox"` (selene.toml)

## Critical "Gotchas"
- **ActionQueue is serial**: Residents execute one action at a time. Queueing multiple actions requires understanding `EnqueueAction()` and `CancelToken` propagation.
- **Station versioning**: `PlotService.GetStationVersion()` invalidates cache on build changes. Always refresh cache when evaluating needs after placement.
- **Manual override disables autonomy**: `DirectActionService.AssignStationToResident()` calls `DisableAutomation()` - must re-enable after action completes.
- **Collapse system**: `ResidentCollapseService` auto-queues rest when Energy ≤ threshold. Interrupting requires `EnergyCollapseRelease()` check.
- **Time scales**: In-game time (`TimeScale.GetClockTime()`) vs real-time (`os.clock()`). Needs decay per in-game hour; billing cycles use real-time.

## Related Docs
- [GameDesign.md](../GameDesign.md) - Career/gig split, progression spine, economy tuning
- [GameSystems.md](../GameSystems.md) - High-level system descriptions
- [TODO.md](../TODO.md) - Active work items and known issues