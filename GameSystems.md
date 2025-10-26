# Game Systems Overview

## Table of Contents

- [Core Systems](#core-systems)
  - [1. Plot System](#1-plot-system)
  - [2. Item & Station System](#2-item--station-system)
  - [3. Resident System](#3-resident-system)
  - [4. Data Persistence](#4-data-persistence)
- [Gameplay Systems](#gameplay-systems)
  - [5. Needs & Autonomy System](#5-needs--autonomy-system)
  - [6. Direct Action System](#6-direct-action-system)
  - [7. Career System](#7-career-system)
  - [8. Gig System](#8-gig-system)
  - [9. Shift Scheduler System](#9-shift-scheduler-system)
  - [10. Stat & Progression System](#10-stat--progression-system)
- [Economy Systems](#economy-systems)
  - [11. Currency System](#11-currency-system)
  - [12. Billing System](#12-billing-system)
  - [13. Payroll System](#13-payroll-system)
  - [14. Energy Usage Tracking](#14-energy-usage-tracking)
- [Player-Facing Systems](#player-facing-systems)
  - [15. Build/Placement UI System](#15-buildplacement-ui-system)
  - [16. HUD / Info System](#16-hud--info-system)
  - [17. Network Communication](#17-network-communication)
- [Infrastructure Systems](#infrastructure-systems)
  - [18. WorldUpdate System](#18-worldupdate-system)
  - [19. Time Scale System](#19-time-scale-system)
  - [20. Resident Collapse System](#20-resident-collapse-system)
  - [21. Resident Need Service](#21-resident-need-service)

---

## Core Systems

### 1. Plot System

- **Server Authority:** PlotService manages land ownership and grid state
- Grid-based placement with chunk unlocking system (5x5 cells per chunk)
- PlotState class tracks: unlocked chunks, cell occupancy, floor/roof/wall placement
- Compact save format: `UnlockedChunks` + `PlacedObjects` with metadata
- Station cache: `PlayerStations[userId][stationType][uniqueId]` for fast lookups
- Station versioning invalidates cache on build changes
- Integration: BuildService validates placement, WorldPlacer spawns models
- Location: `Server/Services/PlotService.luau`, `Server/Classes/PlotState/`

### 2. Item & Station System

- **Catalog-Driven:** Items defined in `Shared/Definitions/Items/`
- Station types: RestStation, CookStation, SocialStation, HygieneStation, FunStation
- Station properties: `stationType`, `maxOccupancy`, need effects, quality modifiers
- Occupancy management: tracks which residents are using stations
- Active override system: manual assignments, power outages, maintenance locks
- Item resolution: `ItemFinder.FindItemById()` for consistent lookups
- Handler registration: `DirectActionService.RegisterHandler()` for behaviors
- Location: `Shared/Definitions/Items/`, `Server/Modules/ResidentActionHandlers.luau`

### 3. Resident System

- **ResidentState Class:** Stateful wrapper for resident data (`Server/Classes/ResidentState.luau`)
- Core properties: Name, Age, Gender, Needs, Traits, Statistics, CurrentCareerId, CareerStreak
- ActionQueue: serialized action execution with cancel tokens
- Lifecycle tracking: `IsBusy`, `CurrentAction`, `CurrentOverride` flags
- Automation control: `AutoActionsEnabled`, `AutoJobEnabled`
- Signals: `ActionChanged`, `ActionCompleted`, `NeedsChanged`, `DestinationChanged`
- Model binding: attributes mirror need values for UI updates
- ResidentService: manages creation, deletion, spawning, persistence
- Location: `Server/Classes/ResidentState.luau`, `Server/Services/ResidentService.luau`

### 4. Data Persistence

- **PlayerSession Wrapper:** Encapsulates DataStore operations
- Custom DataStore package: auto-save, session locking, compression, retries
- Profile schema categories: `PlotState`, `HouseholdState`, `CurrencyState`, `GigState`, `BillingState`, `PayrollState`, `EnergyState`
- Blocking API: `PlayerSession.GetDataAwait(player, category)` - waits until ready
- Non-blocking API: `PlayerSession.TryGetData(player, category)` - returns nil if not ready
- Template reconciliation on first load ensures schema consistency
- Signals: `StateChanged`, `Saving`, `Saved` for lifecycle hooks
- Debug mode available for development logging
- Location: `Server/Services/PlayerSession/`, `ServerPackages/DataStore/`

---

## Gameplay Systems

### 5. Needs & Autonomy System

- **Five Core Needs:** Hunger, Energy, Hygiene, Social, Fun (0-100 scale)
- NeedConfig defines: decay rates per in-game hour, Low/Critical thresholds, hysteresis, cooldowns
- **ResidentAutonomyService:** Central decision-making loop (~1s intervals via WorldUpdate)
  - NeedEvaluator: scores needs, selects best station with availability check
  - StationManager: finds available stations, manages occupancy
  - FallbackActions: handles roaming, begging, job evaluation when no needs critical
  - ActionQueue: enqueues autonomous station actions with handler execution
- **Circadian Rhythm:** Night bias for Energy need (22:00-6:00 game time)
- Need decay: per-frame updates via ResidentNeedService, trait modifiers supported
- Emergency guards: critical need interrupts can cancel current actions
- Social coordination: multi-resident social interactions when shared stations available
- Location: `Server/Services/ResidentAutonomyService/`, `Shared/Configurations/NeedConfig.luau`

### 6. Direct Action System

- **Manual Override Pipeline:** Player clicks resident → assigns to station
- Workflow: disable autonomy → prepare resident (WaitUntilIdle) → queue `ManualOverride:*` action → re-enable autonomy on completion
- Station assignment validation: checks occupancy, power outages, resident availability
- Handler contract: `function(context, assignment)` with cancel token support
- Station occupancy tracking: prevents double-booking, enforces maxOccupancy limits
- Integration with collapse system: releases collapsed residents if Energy ≥ threshold
- Signals: `OverrideStarted`, `OverrideCompleted`, `OverrideFailed`
- Location: `Server/Services/DirectActionService.luau`

### 7. Career System

- **Resident Passive Income:** Shift-based work managed by CareerService
- Career definitions: requirements (stats), base pay/min, shift length
- Active shift tracking: `activeShiftsByUser[userId][residentName]`
- Energy depletion monitoring: forces shift end when Energy ≤ threshold
- Payout calculation: `basePay * moodMultiplier * streakMultiplier * momentumMultiplier`
- Streak system: +2% per consecutive successful shift (max +25%)
- Momentum boost: consumed from GigState when shift starts
- Integration with PayrollService: earnings recorded for batch payout
- Shift lifecycle: `StartShift()` → energy tracking → `EndShift()` → payroll recording
- Location: `Server/Services/CareerService.luau`, `Shared/Configurations/JobCatalog.luau`

### 8. Gig System

- **Player Active Income:** Short instanced challenges with cooldowns
- Gig types: Courier Sprint, Cafe Pop-Up, Debug Jam (tunable base payout + variance)
- Daily slot system: 3 slots refresh at dawn (in-game day boundary)
- Performance tiers: Bronze/Silver/Gold multiply final payout
- Momentum generation: successful gigs grant +10% career boost for 1 in-game hour
- Cooldown tracking: per-gig timers prevent spam (6-10 min real-time)
- Run lifecycle: `RequestStart` → player UI → `SubmitScore` → currency award + momentum
- GigState persistence: slots used, cooldowns, momentum expiry timestamp
- Location: `Server/Services/GigService.luau`, `Client/Modules/GigManager.luau`

### 9. Shift Scheduler System

- **Automated Shift Management:** Coordinates shift timing against accelerated game clock
- Shift templates: define start time, end time, duration from CareerShiftConfig
- Event types: Reminder (pre-shift warning), Start (auto clock-in), End (auto clock-out)
- Resident runtime tracking: active shifts, auto-managed flag, version control
- Event queue: scheduled events sorted by time for efficient processing
- Signals: `ShiftReminder`, `ShiftStartDue`, `ShiftEndDue`, `ShiftMissed`
- Cancellation support: events can be invalidated if resident state changes
- Integration: fires events consumed by CareerService for actual shift execution
- Location: `Server/Services/ShiftSchedulerService.luau`

### 10. Stat & Progression System

- **Four Core Stats:** Intelligence, Discipline, Fitness, Social (0-100 scale)
- Stat requirements: gate career eligibility (e.g., Junior Programmer requires Intelligence ≥ 4)
- Stat growth: currently via traits, future training stations planned
- Trait system: modifiers for need decay rates, stat bonuses (TraitConfig)
- Mood system: derived from recent need satisfaction, affects career payouts (±15% clamp)
- Career progression: higher stats unlock better-paying jobs
- Location: `Shared/Configurations/TraitConfig.luau`, `Shared/Utilities/TraitUtils.luau`

---

## Economy Systems

### 11. Currency System

- **Atomic Operations:** CurrencyService handles all currency changes
- Primary currency: Cash (stored in CurrencyState)
- Operations: `Add(player, currency, amount, source)`, `Remove(player, currency, amount, reason)`
- Rate limiting: prevents exploit spam (transaction throttling)
- Transaction logging: records currency sources ("Career", "Gig", "Begging")
- Attribute mirroring: player attributes sync for client UI
- Outstanding balance tracking: separate from cash for billing
- Location: `Server/Services/CurrencyService.luau`

### 12. Billing System

- **Recurring Bills:** 480s real-time cycle (8 minutes)
- Charge categories: Plot Tax, Electricity, Food Usage, Overdue Interest
- **BillingState:** Tracks cycle progression (Active → Grace → Overdue)
- Grace period: 10s buffer before overdue penalties
- Power outage system: disables energy stations when bills unpaid for too long
- Food usage tracking: incremental bucket system (Current + Pending during grace/overdue)
- EnergyUsageTracker integration: accumulates kWh consumed by powered stations
- Escalation: overdue count increments, triggers power shutoff after threshold
- Early payment window: bills can be paid up to 8 in-game hours before due
- Player notifications: real-time updates via BillingPackets
- Location: `Server/Services/BillingService.luau`, `Server/Classes/BillingState.luau`

### 13. Payroll System

- **Batch Payout:** Collects earnings over 4-hour real-time cycle
- **PayrollState Class:** Tracks recorded work time per resident
- Recording: CareerService calls `RecordWorkTime(player, residentName, seconds, jobId, payRate)`
- Payout calculation: `totalPayout = sum(workTime * adjustedPayRate)` across all residents
- Cycle lifecycle: earnings accumulate → payout trigger → clear earnings → reset cycle
- Clock time display: shows next payout in game time for player clarity
- Integration: deposits to CurrencyState via CurrencyService.Add()
- WorldUpdate subscription: 5s interval checks for cycle completion
- Location: `Server/Services/PayrollService.luau`, `Server/Classes/PayrollState.luau`

### 14. Energy Usage Tracking

- **Electricity Metering:** Tracks kWh consumed by powered stations
- Base load: sum of `energyPerHour` from all placed powered items
- Active load: dynamic addition during station use (cooking, lights, etc.)
- Accumulation: `(baseLoad + activeLoad) * deltaSeconds / 3600` per update
- Collection: billing cycle triggers `CollectUsage()` → resets accumulated energy
- Outage mode: stops accumulation when power cut off (billing overdue)
- Sync system: mirrors base load to client for UI display
- Persistence: `EnergyState` in player profile (AccumulatedEnergy, LastTimestamp)
- Location: `Server/Utilities/EnergyUsageTracker.luau`

---

## Player-Facing Systems

### 15. Build/Placement UI System

- **Client Ghost Preview:** PlotBuilder shows red/green placement validation
- Catalog browsing: filter by item type, display costs/requirements
- Placement modes: floors, walls, roofs, cell objects (furniture)
- Rotation support: 90° increments for directional items
- Actions: Place, Move, Rotate, Remove, Sell
- Server validation: BuildService checks plot state before spawning
- Delta replication: PlacementPackets broadcast changes to all clients
- Error feedback: shows rejection reasons (occupied, no funds, adjacency)
- Grid highlighting: shows chunk boundaries, unlockable regions
- Location: `Client/Modules/PlotBuilder.luau`, `Server/Services/BuildService/`

### 16. HUD / Info System

- **Main HUD Components:** Cash display, day/time, resident roster, needs panel
- Billing info: shows breakdown (plot tax, electric, food), time until due, overdue warnings
- Payroll display: pending earnings, next payout time
- Grace/overdue indicators: visual warnings when bills unpaid
- Resident needs: real-time bars for Hunger, Energy, Hygiene, Social, Fun
- Career status: current shift, earnings estimate, streak bonus
- Notification system: toasts for payouts, bill warnings, shift events
- Time display: accelerated game clock (24-hour format)
- Location: `Client/UserInterface/MainHUD.luau`, `Client/UserInterface/ResidentNeedsUI.luau`

### 17. Network Communication

- **Packet Library:** Custom typed remote system (`Packages/Packet`)
- Never use RemoteEvents/RemoteFunctions directly
- Packet definitions in `Network/*Packets.luau`:
  - ResidentsPackets: resident creation, deletion, station assignment, movement
  - PlacementPackets: plot claiming, chunk unlocking, object placement
  - JobPackets: career start/stop, shift management
  - GigPackets: gig start, score submission
  - BillingPackets: billing info requests, payment, breakdown updates
  - PayrollPackets: payroll info requests, payout notifications
- Request/response pattern: `.OnServerInvoke` for blocking calls
- Fire-and-forget pattern: `.OnServerEvent` / `.OnClientEvent` for broadcasts
- Serialization: automatic buffer packing with typed parameters
- Location: `src/Network/`, `Packages/Packet/`

---

## Infrastructure Systems

### 18. WorldUpdate System

- **Centralized Update Dispatcher:** Single Heartbeat drives multiple systems
- Subscription API: `WorldUpdate.Subscribe(name, intervalSeconds, callback)`
- Interval-based execution: accumulates deltaTime, fires when threshold met
- Systems using WorldUpdate:
  - ResidentAutonomyService (1.0s interval)
  - ResidentNeedService (0.25s interval)
  - BillingService (2s interval)
  - PayrollService (5s interval)
  - NeedEffects scheduler (1/30s for smooth need updates)
- Auto-disconnects when no active subscribers (performance optimization)
- Task management: `Unsubscribe()`, `IsSubscribed()`, `GetTaskCount()`, `ClearAll()`
- Location: `Server/Utilities/WorldUpdate.luau`

### 19. Time Scale System

- **Accelerated Game Clock:** In-game time runs faster than real-time
- Configuration: `SecondsPerFullDay` attribute on Lighting (default: varies by config)
- Clock conversion: `TimeScale.GetClockTime()` returns current hour (0-24)
- Delta conversion: `TimeScale.GameHoursFromRealDelta(seconds)` for need decay
- Day/night cycle: DayAndNight module syncs Lighting.ClockTime client-side
- Circadian hints: NeedConfig defines night start/end for sleep bias
- Billing/payroll use real-time; need decay uses game-time
- Integration: all systems requiring time awareness use TimeScale APIs
- Location: `Shared/Utilities/TimeScale.luau`, `Client/Modules/DayAndNight.luau`

### 20. Resident Collapse System

- **Energy Depletion Failsafe:** Auto-queues rest when Energy ≤ threshold
- Monitoring: connects to resident Energy need changes
- Collapse trigger: queues ground rest action when critical Energy detected
- Release check: `EnergyCollapseRelease()` validates Energy ≥ 4% before allowing interrupts
- Integration with DirectActionService: manual overrides blocked during collapse
- Refresh system: `ResidentCollapseService.Refresh()` syncs connections on resident changes
- Connection cleanup: per-resident listeners disconnected on removal
- Known issue: visual sync problem (resident doesn't stand up physically during interrupts)
- Location: `Server/Services/ResidentCollapseService.luau`

### 21. Resident Need Service

- **Need Decay Loop:** Updates all resident needs every 0.25s real-time
- Decay calculation: `GameHoursFromRealDelta(deltaTime) * DecayPerHour * TraitMultiplier`
- Trait integration: applies per-need decay modifiers from TraitUtils
- Pause support: respects `IsNeedDecayPaused()` and `IsNeedPaused(needName)`
- Autonomy trigger: calls `ResidentAutonomyService.TrySatisfyNeedsForResident()` after decay
- Resident snapshot: maintains active list, prunes disconnected players/residents
- Auto start/stop: manages WorldUpdate subscription based on resident count
- Per-need clamping: enforces Min/Max bounds from NeedConfig
- Location: `Server/Services/ResidentNeedService.luau`

---

## Additional Supporting Systems

### 22. Resident Movement & Pathfinding

- **ResidentMovement Utility:** Handles navigation to world positions/stations
- Humanoid.MoveTo with timeout and cancel token support
- Seat management: `TakeSeat()`, `LeaveSeat()` for station interactions
- Rest pose system: laying down on beds (different from seated)
- Destination tracking: `SetDestination()` for UI visualization
- Integration: used by autonomy, direct actions, and fallback behaviors
- Location: `Server/Utilities/ResidentMovement.luau`

### 23. Resident Chat System

- **Context-Aware Speech:** Generates chat bubbles for resident actions
- Action phrases: station-specific lines (eating, sleeping, socializing)
- Interrupt phrases: explains why action cancelled (critical need, manual override)
- Need urgency: different messages for Low vs Critical states
- Rate limiting: cooldown prevents spam
- Billboard display: fires packets to client for chat bubble UI
- Location: `Server/Utilities/ResidentChat.luau`, `Client/UserInterface/ResidentChatBubbles.luau`

### 24. Need Effects System

- **Real-Time Need Updates:** Smooth need changes during station use
- Effect types: instant (immediate adjustment), rate-based (per-hour change)
- Runtime scheduler: 30 FPS updates via WorldUpdate
- Emergency guards: monitors need thresholds, can interrupt actions
- Moodlet support: temporary need biases (planned for future)
- ShouldEnd callback: triggers when need reaches Max or custom condition
- Integration: consumed by ResidentActionHandlers during station behaviors
- Location: `Server/Utilities/NeedEffects.luau`

### 25. Job Listing Service

- **Job Board Management:** Periodically restocks available careers
- DataStore-backed: separate store for shared job listings
- Restock logic: regenerates listings when time threshold met
- Job filtering: by type (Profession, Gig), requirements, pay tier
- Template system: defines job pools, spawn weights, rotation schedules
- Singleton pattern: one board instance across all players
- Location: `Server/Services/JobListingService.luau`

### 26. Resident Action Handlers

- **Behavior Specification:** Defines how residents interact with stations
- Handler contract: `function(context, assignment)` with cancel token
- Behavior properties:
  - ApproachDistance: how close resident must be
  - MoveTimeoutSeconds: max time to reach station
  - UseSeat: whether to sit/lie on model
  - DurationSeconds: how long action lasts
  - ShouldEnd: custom completion condition
  - Effects: need adjustments (instant + rate-based)
  - Moodlets: temporary buffs (planned)
  - ChatPhrases: random lines during action
  - EmergencyGuards: interrupts for critical needs
- Station types: RestStation, CookStation, SocialStation, HygieneStation, FunStation
- Registration: `DirectActionService.RegisterHandler(stationType, handlerFunction)`
- Location: `Server/Modules/ResidentActionHandlers.luau`

### 27. World Placer

- **Model Instantiation:** Spawns physical objects into workspace
- Template cloning: from ReplicatedStorage catalog
- Position/rotation: aligns with grid coordinates
- Parent management: organizes under plot-specific folders
- Cleanup: handles deletion when objects removed
- Station model caching: stores references for occupancy tracking
- Integration: used by PlotService, BuildService for placement
- Location: `Server/Utilities/WorldPlacer.luau`

---

## System Initialization Order

Services initialize in this specific order in `Server/Main.server.luau`:

1. **ResidentService** - Must be first (provides resident state foundation)
2. **ShiftSchedulerService** - Shift timing infrastructure
3. **CareerService** - Career management (depends on residents)
4. **BillingService** - Billing cycle setup
5. **PayrollService** - Payroll cycle setup  
6. **GigService** - Gig system initialization
7. **PlotService** - Plot state management
8. **BuildService** - Build validation and placement
9. **ResidentAutonomyService** - Autonomy loop (depends on plots/stations)
10. **DirectActionService** - Manual override handlers
11. **ResidentNeedService** - Need decay loop
12. **ResidentCollapseService** - Collapse monitoring
13. **JobListingService** - Job board initialization + start

**Order matters:** Later services depend on earlier ones (e.g., autonomy needs plot/station infrastructure).

---

## Key System Interactions

### Resident Action Flow
1. **Need Decay** (ResidentNeedService) → drops need value
2. **Autonomy Evaluation** (ResidentAutonomyService) → detects low need
3. **Station Selection** (NeedEvaluator + StationManager) → finds available station
4. **Action Queuing** (ActionQueue) → enqueues station action
5. **Handler Execution** (ResidentActionHandlers) → movement + effects
6. **Need Effects** (NeedEffects) → smooth need restoration
7. **Action Completion** → releases station, returns to autonomy

### Career Shift Flow
1. **Shift Scheduler** → fires `ShiftStartDue` event
2. **CareerService** → calls `StartShift()`, validates resident readiness
3. **Energy Monitoring** → tracks Energy drain during shift
4. **Shift End** → triggered by scheduler or energy depletion
5. **Payout Calculation** → applies mood/streak/momentum multipliers
6. **Payroll Recording** → logs work time + adjusted pay rate
7. **Payroll Cycle** → batch payout every 4 hours

### Billing Cycle Flow
1. **BillingService Update** (every 2s) → checks cycle state
2. **Active State** → accumulates usage (energy, food)
3. **Due State** → calculates charges, adds to outstanding balance
4. **Grace State** → 10s buffer, pending food usage tracked separately
5. **Overdue State** → applies power outage, increments overdue count
6. **Payment** → player pays via UI, cycle resets, outage cleared

### Plot Placement Flow
1. **Client Preview** (PlotBuilder) → shows ghost with validation
2. **Placement Request** (PlacementPackets) → sent to server
3. **Build Validation** (BuildService) → checks plot state, ownership
4. **PlotState Update** → adds object to grid, marks cells occupied
5. **World Spawning** (WorldPlacer) → instantiates model in workspace
6. **Station Cache Update** (PlotService) → registers new station
7. **Delta Broadcast** (PlacementPackets) → replicates to all clients
8. **Client Rebuild** (PlotBuilder) → updates local world from delta

---

## Performance Considerations

- **WorldUpdate:** Single heartbeat drives all systems (reduced Heartbeat connections)
- **Station Caching:** Avoids repeated workspace traversals during autonomy
- **Resident Snapshot:** Pre-built list for need service (no per-frame lookups)
- **Delta Replication:** Only changes broadcast to clients, not full state
- **Action Queue Serialization:** One action at a time per resident (prevents action spam)
- **Interval Tuning:** Critical systems run faster (needs: 0.25s), less critical slower (billing: 2s)
- **Auto-Disconnect:** WorldUpdate stops heartbeat when no subscribers
- **Attribute Batching:** Need changes only update attributes when ≥1% difference

---

## Future System Expansions (Planned)

- **Aging System:** Toddler → Child → Teen → Adult → Elder progression
- **Relationship System:** Social connections between residents, family bonds
- **Training Stations:** Study desks, gyms for active stat growth
- **Advanced Careers:** Doctor, Engineer, Musician roles with higher requirements
- **Memorial System:** Tracks past residents, generational history
- **Rebirth System:** Prestige mechanics with inherited bonuses
- **Events System:** Random events (guests, emergencies, celebrations)
- **Multiplayer Social:** Visit other players' plots, inter-plot interactions
