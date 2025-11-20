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
│   ├── Services/     # Singleton services (PlotService, ResidentService, TenantService, etc.)
│   ├── Classes/      # Stateful objects (ResidentState, PlotState, ActionQueue)
│   ├── Modules/      # ResidentActionHandlers, TenantValuation
│   └── Utilities/    # Helpers (ResidentMovement, WorldPlacer, WorldUpdate)
├── Client/           # StarterPlayerScripts - UI and visuals only
│   ├── Modules/      # Client-side managers (PlotBuilder, ObjectSelector)
│   ├── ClientStores/ # Replicated state caches (PlotStateStore, ResidentsStore)
│   └── UserInterface/ # UI components (MainHUD, ResidentRoster, etc.)
├── Shared/           # ReplicatedStorage - definitions, utilities, configs
│   ├── Configurations/ # NeedConfig, TenantConfig, JobCatalog
│   ├── Definitions/  # Static game data (items, billing constants, tenant traits)
│   └── Utilities/    # ItemFinder, PlotFinder, TimeScale, TraitUtils
└── Network/          # ReplicatedStorage - Packet definitions (typed remotes)
    ├── ResidentsPackets.luau    # Resident creation/deletion/sync
    ├── PlacementPackets.luau    # Plot claiming/building/unlocking
    ├── TenantPackets.luau       # Tenant offers/evictions
    ├── ChorePackets.luau        # Interactive tasks (messes/repairs)
    └── BillingPackets.luau      # Payment/billing info
```

## Core Architectural Patterns

### 1. **Network Communication: Packet Library**
- **Library**: Custom typed networking library (similar to ByteNet) located in `Packages/Packet`.
- **Definitions**: All packets are defined in `src/Network/*.luau`.
- **Syntax**: `Packet("Name", {Args}):Response({Returns})`.
- **Client Usage**:
  - **Send**: `MyPacket:Fire(args)` (yields if response defined).
  - **Receive**: `MyPacket.OnClientEvent:Connect(function(args) ... end)`.
- **Server Usage**:
  - **Send**: `MyPacket:FireClient(player, args)`.
  - **Receive**: `MyPacket.OnServerEvent:Connect(function(player, args) ... end)`.
  - **Handle Request**: `MyPacket.OnServerInvoke = function(player, args) ... end`.

### 2. **Resident AI & Autonomy**
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
  - Profile schema in `PlayerSession/Profile.luau`: `PlotState`, `HouseholdState`, `CurrencyState`, `InventoryState`, `TenantState`
  - **Always use `PlayerSession.GetDataAwait(player, "Category")`** - blocks until DataStore ready
  - **Non-blocking**: `PlayerSession.TryGetData(player, "Category")` returns nil if not ready
- **DataStore wrapper** features:
  - Auto-save intervals, manual `dataStore:Save()`, session locking (prevents multi-server corruption)
  - Reconciles template on first load, handles retries, exposes signals (`Saving`, `Saved`, `StateChanged`)

### 6. **Tenant System & Economy**
- **TenantService** (`Server/Services/TenantService.luau`):
  - Manages `TenantState` (Offers, ActiveLeases, MailboxBalance).
  - **Valuation**: `TenantValuation` scores the plot to determine rent offers.
  - **Mailbox**: Rent accumulates in `MailboxBalance`. Visuals use Attributes on a `Residents` folder in the plot model.
  - **Resident Link**: Residents can be linked to Tenants via `ResidentService` (`TenantToResidentMap`), implying the resident *is* the tenant.
- **BillingService**: Recurring bills (tax, electricity) tracked via `BillingState`.
- **ChoreService**: Spawns interactive tasks (trash/repairs) for active income.

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
- **WorldUpdate Loops**: `ResidentAutonomyService` and `TenantService` all use `WorldUpdate.Subscribe`. Ensure new loops are performant.
- **Time scales**: In-game time (`TimeScale.GetClockTime()`) vs real-time (`os.clock()`). Needs decay per in-game hour; billing/regrow cycles use real-time.
