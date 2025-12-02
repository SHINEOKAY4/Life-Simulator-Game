# Life Simulator - AI Coding Agent Instructions

## Project Overview
Life Simulator is a Roblox game built with a strict client-server architecture using Luau. Players manage plots, place objects, interact with residents/tenants, and simulate life activities. The codebase uses **Rojo** for project management and follows a packet-based networking pattern.

## Architecture Fundamentals

### Rojo Project Structure
- **Build tool**: Rojo 7.6.1 (managed via Aftman)
- **Build command**: `rojo build default.project.json -o Life-Simulator.rbxl`
- **Project file**: `default.project.json` defines how folders map to Roblox services
  - `src/Server` → ServerScriptService
  - `src/Client` → StarterPlayer.StarterPlayerScripts
  - `src/Shared` → ReplicatedStorage.Shared
  - `src/Network` → ReplicatedStorage.Network
  - `Packages` → ReplicatedStorage.Packages
  - `ServerPackages` → ServerStorage.ServerPackages

### Core Directory Organization

**Server** (`src/Server/`):
- `Services/` - Singleton modules with `Init()` or `Start()` methods, called from `Main.server.luau`
- `Classes/` - Stateful objects (e.g., `PlotState`, `ResidentState`, `BillingState`)
- `Modules/` - Shared server logic, often grouped by feature (e.g., `Chores/`)
- `Utilities/` - Server-only helper functions

**Client** (`src/Client/`):
- `Modules/` - Controllers that manage UI, interactions, and visual effects (suffix: `Controller`)
- `ClientStores/` - Client-side state managers (suffix: `Store`)
- `UserInterface/` - UI component modules
- `Utilities/` - Client-only helper functions

**Shared** (`src/Shared/`):
- `Definitions/` - Static data tables (e.g., `TenantDefinitions`, `MaterialDefinitions`, `Catalog/`)
- `Configurations/` - Game constants and config tables
- `Utilities/` - Pure functions usable on both client and server (e.g., `Grid`, `PlacementKey`, `ItemFinder`)

**Network** (`src/Network/`):
- Packet definition modules (suffix: `Packets`) using the custom `Packet` package

## Critical Patterns

### 1. Packet-Based Networking
All client-server communication uses the custom `Packet` library (in `Packages/Packet/`). **Never use RemoteEvents/RemoteFunctions directly.**

**Defining packets** (`src/Network/`):
```lua
local Packet = require(ReplicatedStorage.Packages.Packet)

-- One-way packet (server → client or client → server)
PlacementPackets.PlotStateUnlockDelta = Packet("PlotStateUnlockDelta", { Packet.NumberU16 })

-- Request-response packet
PlacementPackets.ClaimRequest = Packet("ClaimRequest", Packet.NumberU8):Response(Packet.Boolean8, Packet.StringLong)
```

**Server usage**:
```lua
-- Listen for client events
Packets.ClaimRequest.OnServerEvent:Connect(function(player: Player, plotIndex: number)
    local success, message = validateClaim(player, plotIndex)
    return success, message -- Automatic response
end)

-- Fire to specific client
Packets.PlotStateSync:FireClient(player, chunkInfo, unlocked, objects, mounts)
```

**Client usage**:
```lua
-- Fire to server and await response
local success, errorMsg = Packets.ClaimRequest:Fire(plotIndex)

-- Listen for server events
Packets.PlotStateUnlockDelta.OnClientEvent:Connect(function(unlockedChunkIds)
    -- Handle update
end)
```

**Preloading**: All packet modules in `src/Network/` must be required before any remotes fire. See `src/Client/Main.client.luau` for the preloading pattern.

### 2. Service Initialization Pattern
Server services are **singletons** with an `Init()` method (or `Start()` for background loops). Services are initialized in `Main.server.luau` in dependency order.

**Service template**:
```lua
local ServiceName = {}

function ServiceName.Init()
    -- Register packet listeners
    Packets.SomeRequest.OnServerEvent:Connect(handleRequest)
    
    -- Connect to other service signals
    PlotService.PlotClaimed:Connect(onPlotClaimed)
end

return ServiceName
```

### 3. State Management

**Server-side state** (`src/Server/Classes/`):
- `PlotState` - Player's plot layout, rooms, placed objects, surface mounts. Backed by `DataStore` package.
  - Key methods: `Place()`, `Remove()`, `GetRoomAt()`, `RecalculateRooms()`
  - Supports multi-level buildings (levels tracked via `yLevel` property)
- `ResidentState` - NPCs living in player's plot
- `BillingState` - Player's financial state (rent, bills)

**Client-side state** (`src/Client/ClientStores/`):
- `PlotStateStore` - Client replica of server `PlotState`, synced via packets
  - Includes derived snapshots for room detection and placement validation
  - **Active level system**: Most operations occur on a single level at a time (`ActiveLevel`)
- `ResidentsStore`, `TenantStore` - Client replicas of server NPC data

### 4. Grid-Based Placement System
The `Grid` utility (`src/Shared/Utilities/Grid.luau`) converts between:
- **World coordinates** (3D studs)
- **Cell coordinates** (2D grid: `cellX`, `cellZ`)
- **Chunk coordinates** (grouped cells for progressive unlock)

**Key concepts**:
- `Facing`: `"North" | "East" | "South" | "West"` (diagonal facings also exist)
- `PlacementKey`: Unique string identifier for placed objects (format: `"cell_{cellX}_{cellZ}_level{level}"` for cell objects, custom for surface mounts)
- **Levels**: Buildings support multiple floors (`yLevel` or `Level` property). `0` is ground level.

### 5. Custom Packages

**GoodSignal** (`Packages/GoodSignal/`):
- RBXScriptSignal-compatible signal implementation
- Usage: `local signal = GoodSignal.new()`, `signal:Connect(fn)`, `signal:Fire(...)`

**DataStore** (`ServerPackages/DataStore/`):
- Wrapper around Roblox DataStore with automatic saving, locking, and versioning
- Constructor pattern: `DataStore.new(name, scope, key)` or `DataStore.hidden(...)` for non-player data
- API: `:Open(template)`, `:Read()`, `:Save()`, `:Close()`, `:Destroy()`
- Signals: `StateChanged`, `Saving`, `Saved`

**Soundtrack** (`Packages/Soundtrack/`):
- Music management system (used by `SoundtrackManager` module)

## Type Safety
Use `--!strict` at the top of all new files. Export types for reusability:
```lua
export type PlotState = {
    Grid: any,
    Save: SaveData,
    Place: (self: PlotState, ...) -> boolean,
    -- ...
}
```

## Common Workflows

### Adding a new feature
1. Define packets in `src/Network/{FeatureName}Packets.luau`
2. Create server service in `src/Server/Services/{FeatureName}Service.luau` with `Init()` method
3. Register service in `src/Server/Main.server.luau`
4. Create client controller in `src/Client/Modules/{FeatureName}Controller.luau`
5. Require controller in `src/Client/Main.client.luau`

### Querying placed objects
**Server**: Use `PlotState` methods like `:GetPlacementByKey()`, `:IterateObjects()`, `:GetSurfaceMountsByParent()`
**Client**: Use `PlotStateStore.GetPlacementSnapshot()`, `PlotStateStore.GetDerivedSnapshot()` for room/placement analysis

### Room detection
Rooms are automatically calculated by flood-fill algorithms in `PlotState/Rooms.luau`. Access via `:GetRoomAt(cellX, cellZ, level)` on server, or `PlotStateStore.GetRoomAt()` on client.

## Avoid These Mistakes
- **Never bypass the Packet system** - Don't create RemoteEvents manually
- **Don't mix server/client contexts** - `ReplicatedStorage.Shared` is the only truly shared code
- **Don't forget level context** - Most placement logic requires a `level` or `yLevel` parameter
- **Init() order matters** - Some services depend on others being initialized first (see `Main.server.luau` order)

## Reference Files
- Packet patterns: `src/Network/PlacementPackets.luau`, `Packages/Packet/init.luau`
- Service pattern: `src/Server/Services/PlotService.luau`
- State class: `src/Server/Classes/PlotState/init.luau`
- Client store: `src/Client/ClientStores/PlotStateStore.luau`
- Grid system: `src/Shared/Utilities/Grid.luau`
- Item lookup: `src/Shared/Utilities/ItemFinder.luau` (finds items from `Definitions/Catalog/`)
