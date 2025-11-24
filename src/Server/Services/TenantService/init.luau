--!strict
-- Server/Services/TenantService.luau
-- Backend scheduler for tenant offers, leases, and rent payments.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

-- Configurations
local TenantConfig = require(ReplicatedStorage.Shared.Configurations.TenantConfig)
local ValuationConfig = TenantConfig.Valuation
local OffersConfig = TenantConfig.Offers
local RentConfig = TenantConfig.Rent

-- Network
local MailboxPackets = require(ReplicatedStorage.Network.MailboxPackets)
local TenantPackets = require(ReplicatedStorage.Network.TenantPackets)

-- Services
local PlayerSession = require(ServerScriptService.Server.Services.PlayerSession)
local PlotService = require(ServerScriptService.Server.Services.PlotService)
local CurrencyService = require(ServerScriptService.Server.Services.CurrencyService)
local ReviewService = require(ServerScriptService.Server.Services.ReviewService)
local TenantHelpService = require(ServerScriptService.Server.Services.TenantHelpService)
local ResidentService = require(ServerScriptService.Server.Services.ResidentService)

-- Modules
local TenantValuation = require(ServerScriptService.Server.Modules.TenantValuation)
local RepairManager = require(ServerScriptService.Server.Modules.Chores.RepairManager)
local WorldUpdate = require(ServerScriptService.Server.Utilities.WorldUpdate)

-- TenantService Modules
local AttributeManager = require(script.AttributeManager)
local ValidationUtils = require(script.ValidationUtils)
local DataNormalization = require(script.DataNormalization)
local RoomManager = require(script.RoomManager)
local LeaseManager = require(script.LeaseManager)
local MailboxManager = require(script.MailboxManager)
local OfferManager = require(script.OfferManager)

type ValuationResult = any -- TenantValuation.ValuationResult
type TenantStateSave = DataNormalization.TenantStateSave

-- Re-export types for external use
export type TenantOffer = DataNormalization.TenantOffer
export type TenantLease = DataNormalization.TenantLease
export type TenantRoomRosterEntry = RoomManager.TenantRoomRosterEntry

-- Constants
local UPDATE_TASK_NAME = "TenantService"
local UPDATE_INTERVAL = 1
local MIN_VALUATION_RETRY_SECONDS = 5
local MAX_VALUATION_RETRY_SECONDS = 90
local rng = Random.new()

type RuntimeState = {
	Player: Player,
	Save: TenantStateSave,
	CurrencyState: { [string]: number }?,
	CachedValuation: ValuationResult?,
	ValuationRetrySeconds: number,
	LastPropertyValue: number,
	NextValuationUnix: number,
	NextOfferUnix: number,
	MailboxOwnedPlotConn: RBXScriptConnection?,
	TenantRooms: { [string]: any }?,
	TenantRoomDiagnostics: { [string]: RoomManager.TenantRoomDiagnostic }?,
}

local TenantService = {}
local RuntimeByUserId: { [number]: RuntimeState } = {}

-- Forward declarations for functions used out of order
local broadcastMailboxBalance, broadcastPropertyValue, broadcastTenantDelta, updateIncomeRateAttribute, concludeLease

-- ========================================
-- HELPER FUNCTIONS
-- ========================================

local function serverNow(): number
	return Workspace:GetServerTimeNow()
end

local function getRuntime(player: Player): RuntimeState?
	return RuntimeByUserId[player.UserId]
end

local function resolveCurrencyState(runtime: RuntimeState): { [string]: number }?
	if runtime.CurrencyState then
		return runtime.CurrencyState
	end

	local data = PlayerSession.TryGetData(runtime.Player, "CurrencyState")
	if not data then
		data = PlayerSession.GetDataAwait(runtime.Player, "CurrencyState")
	end

	runtime.CurrencyState = data
	return data
end

local function getAverageRating(player: Player): number?
	local reviewState = PlayerSession.GetData(player, "ReviewState")
	if not reviewState or not reviewState.Reviews or #reviewState.Reviews == 0 then
		return nil
	end

	local total = 0
	for _, review in ipairs(reviewState.Reviews) do
		total += (review.Rating or 0)
	end
	return total / #reviewState.Reviews
end

-- ========================================
-- ROOM MANAGEMENT
-- ========================================

local function ensureTenantRooms(runtime: RuntimeState): { [string]: any }?
	local plotState = PlotService.GetState(runtime.Player)
	if not plotState then
		runtime.TenantRooms = nil
		runtime.TenantRoomDiagnostics = nil
		return nil
	end

	local rooms, diagnostics = RoomManager.CollectRooms(plotState)
	runtime.TenantRooms = rooms
	runtime.TenantRoomDiagnostics = diagnostics

	local leases = DataNormalization.EnsureActiveLeases(runtime.Save, serverNow(), RentConfig.IntervalSeconds)
	local assignments = DataNormalization.EnsureRoomAssignments(runtime.Save)

	RoomManager.ReconcileAssignments(leases, rooms, assignments, function(tenantId)
		concludeLease(runtime, tenantId, "NoRoom")
	end)

	return rooms
end

local function resolveRoomSelection(runtime: RuntimeState, preferredRoomKey: string?): (string?, string?)
	local rooms = ensureTenantRooms(runtime)
	if not rooms or not next(rooms) then
		return nil, "Build an enclosed bedroom with a bed before inviting tenants."
	end

	local diagnostics = runtime.TenantRoomDiagnostics or {}
	local assignments = DataNormalization.EnsureRoomAssignments(runtime.Save)

	local normalizedPreferred = RoomManager.NormalizeRoomKey(preferredRoomKey)
	if normalizedPreferred then
		local targetRoom = rooms[normalizedPreferred]
		if not targetRoom then
			local diag = diagnostics[normalizedPreferred]
			if diag and not diag.Ready then
				return nil, RoomManager.GetFirstIssueReason({ [normalizedPreferred] = diag })
			end
			return nil, "Selected room is no longer available."
		end

		local capacity = math.max(targetRoom.TenantCapacity or 0, 0)
		if capacity <= 0 then
			return nil, "Room does not meet tenant requirements."
		end

		local used = math.clamp(math.floor((assignments[normalizedPreferred] or 0) + 0.5), 0, capacity)
		if used >= capacity then
			return nil, "Selected room is already full."
		end

		return normalizedPreferred, nil
	end

	local fallback = RoomManager.FindAvailableRoom(rooms, assignments)
	if not fallback then
		return nil, "All tenant rooms are occupied."
	end

	return fallback, nil
end

-- ========================================
-- LEASE LIFECYCLE
-- ========================================

function concludeLease(runtime: RuntimeState, tenantId: string, reason: string)
	local leases = DataNormalization.EnsureActiveLeases(runtime.Save, serverNow(), RentConfig.IntervalSeconds)
	local lease = leases[tenantId]
	if not lease then
		return
	end

	local assignments = DataNormalization.EnsureRoomAssignments(runtime.Save)
	RoomManager.ReleaseRoomAssignment(lease, assignments)

	ReviewService.RecordTenantReview(runtime.Player, lease, reason)

	leases[tenantId] = nil
	lease.LeaseEndUnix = serverNow()
	TenantHelpService.RemoveRequestsForTenant(runtime.Player, tenantId, "TenantLeft")

	-- Unlink resident
	local residentName = ResidentService.GetResidentNameByTenantId(runtime.Player, tenantId)
	if residentName then
		ResidentService.DeleteResident(runtime.Player, residentName)
	else
		ResidentService.ClearTenantLink(runtime.Player, tenantId)
	end

	-- Return deposit if not evicted
	local deposit = lease.DepositHeld or 0
	if deposit > 0 and reason ~= "Evicted" then
		local currencyState = resolveCurrencyState(runtime)
		if currencyState then
			CurrencyService.Add(runtime.Player, "Cash", deposit, currencyState, { Source = "TenantDeposit" })
		end
	end

	updateIncomeRateAttribute(runtime)
	runtime.NextOfferUnix = OfferManager.ScheduleNextOffer(runtime.Save, serverNow(), OffersConfig, rng)
	broadcastTenantDelta(runtime, tenantId, nil)
end

local function startLease(
	runtime: RuntimeState,
	offer: TenantOffer,
	now: number,
	preferredRoomKey: string?
): (string?, string?)
	local roomKey, roomErr = resolveRoomSelection(runtime, preferredRoomKey)
	if not roomKey then
		return nil, roomErr or "No tenant-ready rooms available."
	end

	local leases = DataNormalization.EnsureActiveLeases(runtime.Save, now, RentConfig.IntervalSeconds)
	local assignments = DataNormalization.EnsureRoomAssignments(runtime.Save)
	local lease = LeaseManager.CreateLease(offer, roomKey, now)
	local tenantId = LeaseManager.AssignLease(leases, lease, assignments)

	runtime.NextOfferUnix =
		OfferManager.ScheduleNextOffer(runtime.Save, now + OffersConfig.CooldownSeconds, OffersConfig, rng)
	updateIncomeRateAttribute(runtime)
	broadcastTenantDelta(runtime, tenantId, lease)

	return tenantId, nil
end

local function serviceLease(runtime: RuntimeState, now: number, deltaTime: number)
	local leases = runtime.Save.ActiveLeases
	if typeof(leases) ~= "table" or not next(leases) then
		return
	end

	MailboxManager.SettleOutstanding(runtime.Save)

	for tenantId, lease in pairs(leases) do
		if lease.LeaseEndUnix <= now then
			concludeLease(runtime, tenantId, "Complete")
		else
			LeaseManager.ServiceLease(lease, now, deltaTime, function(amount)
				local updatedBalance = MailboxManager.AddIncome(runtime.Save, amount)
				broadcastMailboxBalance(runtime, updatedBalance)
			end, function()
				ReviewService.RecordTenantReview(runtime.Player, lease, "Periodic")
			end)
		end
	end
end

-- ========================================
-- ATTRIBUTE BROADCASTING
-- ========================================

function broadcastMailboxBalance(runtime: RuntimeState, balance: number?)
	local finalBalance = balance or MailboxManager.EnsureBalance(runtime.Save)
	runtime.Save.MailboxBalance = finalBalance
	AttributeManager.SetMailboxBalance(runtime.Player, finalBalance)
	MailboxPackets.BalanceUpdate:FireClient(runtime.Player, { Balance = finalBalance })
end

function broadcastPropertyValue(runtime: RuntimeState, scoreValue: any?)
	local score = if typeof(scoreValue) == "number" then scoreValue else (runtime.Save.LastKnownScore or 0)
	local propertyValue = AttributeManager.ClampPropertyValue(score)
	runtime.LastPropertyValue = propertyValue
	AttributeManager.SetPropertyValue(runtime.Player, propertyValue)
end

function updateIncomeRateAttribute(runtime: RuntimeState)
	local leases = runtime.Save.ActiveLeases
	local totalRate = LeaseManager.CalculateTotalIncomeRate(leases)
	AttributeManager.SetIncomeRate(runtime.Player, totalRate)
end

function broadcastTenantDelta(runtime: RuntimeState, tenantId: string, lease: TenantLease?)
	local tenantData = LeaseManager.BuildSingleClientPayload(lease)
	TenantPackets.TenantDelta:FireClient(runtime.Player, {
		UserId = runtime.Player.UserId,
		TenantId = tenantId,
		TenantData = tenantData,
	})
end

local function broadcastActiveTenants(runtime: RuntimeState)
	local leases = DataNormalization.EnsureActiveLeases(runtime.Save, serverNow(), RentConfig.IntervalSeconds)
	local payload = LeaseManager.BuildClientPayload(leases)
	TenantPackets.ActiveTenantsSync:FireClient(runtime.Player, {
		UserId = runtime.Player.UserId,
		Tenants = payload,
	})
end

-- ========================================
-- VALUATION & OFFERS
-- ========================================

local function refreshValuation(runtime: RuntimeState, now: number)
	if runtime.NextValuationUnix > now then
		return
	end

	local plotState = PlotService.GetState(runtime.Player)
	if not plotState then
		local savedPlot = PlayerSession.TryGetData(runtime.Player, "PlotState")
		if savedPlot then
			plotState = { Save = savedPlot }
		end
	end

	if not plotState then
		local retry =
			math.clamp(runtime.ValuationRetrySeconds * 2, MIN_VALUATION_RETRY_SECONDS, MAX_VALUATION_RETRY_SECONDS)
		runtime.ValuationRetrySeconds = retry
		runtime.NextValuationUnix = now + retry
		return
	end

	local avgRating = getAverageRating(runtime.Player)
	local valuation = TenantValuation.Evaluate(plotState, avgRating)
	if not valuation then
		local retry =
			math.clamp(runtime.ValuationRetrySeconds * 2, MIN_VALUATION_RETRY_SECONDS, MAX_VALUATION_RETRY_SECONDS)
		runtime.ValuationRetrySeconds = retry
		runtime.NextValuationUnix = now + retry
		return
	end

	runtime.CachedValuation = valuation
	runtime.Save.LastKnownScore = valuation.Score
	broadcastPropertyValue(runtime, valuation.Score)
	runtime.NextValuationUnix = now + ValuationConfig.RefreshIntervalSeconds
	runtime.ValuationRetrySeconds = MIN_VALUATION_RETRY_SECONDS
end

local function tryExpireOffer(runtime: RuntimeState, now: number)
	if OfferManager.IsOfferExpired(runtime.Save.PendingOffer, now) then
		runtime.Save.PendingOffer = nil
		runtime.NextOfferUnix = OfferManager.ScheduleNextOffer(runtime.Save, now, OffersConfig, rng)
	end
end

local function tryGenerateOffer(runtime: RuntimeState, now: number)
	if OfferManager.HasPendingOffer(runtime.Save) or runtime.NextOfferUnix > now then
		return
	end

	local rooms = ensureTenantRooms(runtime)
	local assignments = DataNormalization.EnsureRoomAssignments(runtime.Save)
	local _, availableRooms = RoomManager.CountAvailability(rooms, assignments)

	if availableRooms <= 0 then
		runtime.NextOfferUnix = now + OffersConfig.CooldownSeconds
		return
	end

	local valuation = runtime.CachedValuation
	if not valuation then
		return
	end

	local config = {
		OffersConfig = OffersConfig,
		ValuationConfig = ValuationConfig,
		RentConfig = RentConfig,
	}

	local avgRating = getAverageRating(runtime.Player)
	local offer = OfferManager.ComposeOffer(
		valuation,
		avgRating,
		runtime.Save.OfferSequence or 0,
		runtime.Player.UserId,
		now,
		config,
		rng
	)

	runtime.Save.PendingOffer = offer
	runtime.Save.OfferSequence = (runtime.Save.OfferSequence or 0) + 1
	runtime.Save.LastOfferUnix = now
	runtime.NextOfferUnix = now + OffersConfig.CooldownSeconds
end

-- ========================================
-- RUNTIME INITIALIZATION
-- ========================================

local function hydrateRuntime(player: Player): RuntimeState?
	local tenantSave = PlayerSession.GetDataAwait(player, "TenantState")
	if not tenantSave then
		return nil
	end

	local existingRuntime = RuntimeByUserId[player.UserId]
	if existingRuntime and existingRuntime.MailboxOwnedPlotConn then
		existingRuntime.MailboxOwnedPlotConn:Disconnect()
	end

	local now = serverNow()
	DataNormalization.SanitizeOffer(tenantSave.PendingOffer, now, RentConfig, OffersConfig)
	DataNormalization.EnsureActiveLeases(tenantSave, now, RentConfig.IntervalSeconds)
	DataNormalization.EnsureRoomAssignments(tenantSave)

	-- Ensure numeric defaults
	tenantSave.LastOfferUnix = ValidationUtils.EnsureNumber(tenantSave.LastOfferUnix, 0)
	tenantSave.OfferSequence = ValidationUtils.EnsureNumber(tenantSave.OfferSequence, 0)
	tenantSave.OutstandingRent = ValidationUtils.EnsureNumber(tenantSave.OutstandingRent, 0)
	tenantSave.Version = ValidationUtils.EnsureNumber(tenantSave.Version, 1)
	tenantSave.MailboxBalance =
		AttributeManager.ClampMailboxAmount(ValidationUtils.EnsureNumber(tenantSave.MailboxBalance, 0))

	local currencyState = PlayerSession.TryGetData(player, "CurrencyState")
		or PlayerSession.GetDataAwait(player, "CurrencyState")

	local runtime: RuntimeState = {
		Player = player,
		Save = tenantSave,
		CurrencyState = currencyState,
		CachedValuation = nil,
		ValuationRetrySeconds = MIN_VALUATION_RETRY_SECONDS,
		LastPropertyValue = 0,
		NextValuationUnix = 0,
		NextOfferUnix = now + OffersConfig.MinIntervalSeconds,
		MailboxOwnedPlotConn = nil,
		TenantRooms = nil,
	}

	RuntimeByUserId[player.UserId] = runtime

	runtime.MailboxOwnedPlotConn = player:GetAttributeChangedSignal("OwnedPlotIndex"):Connect(function()
		task.defer(function()
			if RuntimeByUserId[player.UserId] == runtime then
				broadcastMailboxBalance(runtime)
				broadcastPropertyValue(runtime)
			end
		end)
	end)

	updateIncomeRateAttribute(runtime)
	broadcastPropertyValue(runtime)
	broadcastActiveTenants(runtime)

	task.defer(function()
		if RuntimeByUserId[player.UserId] == runtime then
			broadcastMailboxBalance(runtime)
			broadcastPropertyValue(runtime)
		end
	end)

	TenantHelpService.RegisterPlayer(player)
	return runtime
end

-- ========================================
-- MAIN UPDATE LOOP
-- ========================================

local function stepTenants(deltaTime: number)
	local now = serverNow()
	for userId, runtime in pairs(RuntimeByUserId) do
		if not runtime.Player.Parent then
			RuntimeByUserId[userId] = nil
		else
			refreshValuation(runtime, now)
			tryExpireOffer(runtime, now)
			tryGenerateOffer(runtime, now)
			serviceLease(runtime, now, deltaTime)
		end
	end
end

-- ========================================
-- PUBLIC API
-- ========================================

function TenantService.GetRoomAvailabilityReport(player: Player): (number, number, string?)
	local runtime = getRuntime(player) or hydrateRuntime(player)
	if not runtime then
		return 0, 0, "Tenant data unavailable."
	end

	local rooms = ensureTenantRooms(runtime)
	local assignments = DataNormalization.EnsureRoomAssignments(runtime.Save)
	local total, available = RoomManager.CountAvailability(rooms, assignments)
	local reason = if total <= 0 then RoomManager.GetFirstIssueReason(runtime.TenantRoomDiagnostics) else nil
	return total, available, reason
end

function TenantService.GetRoomAvailability(player: Player): (number, number)
	local total, available = TenantService.GetRoomAvailabilityReport(player)
	return total, available
end

function TenantService.GetTenantRoomRoster(player: Player): ({ TenantRoomRosterEntry }, number, number)
	local runtime = getRuntime(player) or hydrateRuntime(player)
	if not runtime then
		return {}, 0, 0
	end

	local rooms = ensureTenantRooms(runtime)
	if not rooms then
		return {}, 0, 0
	end

	local assignments = DataNormalization.EnsureRoomAssignments(runtime.Save)
	local total, available = RoomManager.CountAvailability(rooms, assignments)
	return RoomManager.BuildRoster(rooms, assignments), total, available
end

function TenantService.GetRoomDiagnostics(player: Player)
	local runtime = getRuntime(player) or hydrateRuntime(player)
	if not runtime then
		return {} :: { [number]: { [string]: any } }
	end

	ensureTenantRooms(runtime)
	local diagnostics = runtime.TenantRoomDiagnostics or {}
	local assignments = DataNormalization.EnsureRoomAssignments(runtime.Save)
	local defaultLevel: number = (runtime.Player:GetAttribute("PlotLevel") or 0) :: number

	return RoomManager.BuildDiagnostics(diagnostics, assignments, defaultLevel)
end

function TenantService.GetPendingOffer(player: Player): TenantOffer?
	local runtime = getRuntime(player)
	if not runtime or typeof(runtime.Save.PendingOffer) ~= "table" then
		return nil
	end
	return table.clone(runtime.Save.PendingOffer)
end

function TenantService.GetActiveLeases(player: Player): { [string]: TenantLease }?
	local runtime = getRuntime(player) or hydrateRuntime(player)
	if not runtime then
		return nil
	end

	local leases = runtime.Save.ActiveLeases
	if typeof(leases) ~= "table" then
		return {}
	end

	local cloned: { [string]: TenantLease } = {}
	for tenantId, lease in pairs(leases) do
		cloned[tenantId] = table.clone(lease)
	end
	return cloned
end

function TenantService.GetActiveLease(player: Player): TenantLease?
	local leases = TenantService.GetActiveLeases(player)
	if not leases then
		return nil
	end
	for _, lease in pairs(leases) do
		return lease
	end
	return nil
end

function TenantService.AcceptOffer(player: Player): (boolean, string?)
	local runtime = getRuntime(player)
	if not runtime or typeof(runtime.Save.PendingOffer) ~= "table" then
		return false, "No pending offer."
	end

	local pending = runtime.Save.PendingOffer
	runtime.Save.PendingOffer = nil
	local success, message = TenantService.BeginLeaseFromOffer(player, pending)
	return success, message
end

function TenantService.DeclineOffer(player: Player): boolean
	local runtime = getRuntime(player)
	if not runtime or typeof(runtime.Save.PendingOffer) ~= "table" then
		return false
	end

	runtime.Save.PendingOffer = nil
	runtime.NextOfferUnix = OfferManager.ScheduleNextOffer(runtime.Save, serverNow(), OffersConfig, rng)
	return true
end

function TenantService.GetValuation(player: Player): ValuationResult?
	local runtime = getRuntime(player)
	return if runtime then runtime.CachedValuation else nil
end

function TenantService.GenerateProspectOffer(player: Player): TenantOffer?
	local runtime = getRuntime(player) or hydrateRuntime(player)
	if not runtime then
		return nil
	end

	local now = serverNow()
	refreshValuation(runtime, now)

	local valuation = runtime.CachedValuation
	if not valuation then
		return nil
	end

	local config = {
		OffersConfig = OffersConfig,
		ValuationConfig = ValuationConfig,
		RentConfig = RentConfig,
	}

	local avgRating = getAverageRating(runtime.Player)
	local offer = OfferManager.ComposeOffer(
		valuation,
		avgRating,
		runtime.Save.OfferSequence or 0,
		runtime.Player.UserId,
		now,
		config,
		rng
	)

	runtime.Save.OfferSequence = (runtime.Save.OfferSequence or 0) + 1
	runtime.Save.LastOfferUnix = now
	runtime.NextOfferUnix = math.max(runtime.NextOfferUnix, now + OffersConfig.CooldownSeconds)

	return offer
end

function TenantService.BeginLeaseFromOffer(
	player: Player,
	offer: TenantOffer,
	preferredRoomKey: string?
): (boolean, string?, string?)
	local runtime = getRuntime(player) or hydrateRuntime(player)
	if not runtime then
		return false, "Tenant data unavailable.", nil
	end

	local tenantId, leaseErr = startLease(runtime, offer, serverNow(), preferredRoomKey)
	if not tenantId then
		return false, leaseErr or "Unable to allocate room for tenant.", nil
	end

	runtime.Save.LastOfferUnix = serverNow()
	return true, nil, tenantId
end

function TenantService.EvictTenant(player: Player, tenantId: string): (boolean, string?)
	if type(tenantId) ~= "string" or tenantId == "" then
		return false, "Invalid tenant id."
	end

	local runtime = getRuntime(player) or hydrateRuntime(player)
	if not runtime then
		return false, "Tenant data unavailable."
	end

	local leases = DataNormalization.EnsureActiveLeases(runtime.Save, serverNow(), RentConfig.IntervalSeconds)
	if not leases[tenantId] then
		return false, "Tenant not found."
	end

	concludeLease(runtime, tenantId, "Evicted")
	return true, nil
end

-- ========================================
-- INITIALIZATION
-- ========================================

function TenantService.Init()
	-- Setup TenantHelpService integration
	TenantHelpService.Init({
		GetActiveLeases = function(player: Player)
			local runtime = getRuntime(player)
			if not runtime then
				return nil
			end
			local leases = DataNormalization.EnsureActiveLeases(runtime.Save, serverNow(), RentConfig.IntervalSeconds)
			local simplified: { [string]: any } = {}
			for tenantId, lease in pairs(leases) do
				simplified[tenantId] = {
					TenantId = lease.TenantId,
					TenantName = lease.TenantName,
				}
			end
			return simplified
		end,
		AddMailboxIncome = function(player: Player, amount: number)
			local runtime = getRuntime(player)
			if runtime then
				local updatedBalance = MailboxManager.AddIncome(runtime.Save, amount)
				broadcastMailboxBalance(runtime, updatedBalance)
			end
		end,
	})

	-- Setup RepairManager occupancy resolver
	RepairManager.SetOccupancyResolver(function(player: Player)
		local runtime = getRuntime(player)
		if not runtime then
			return nil
		end
		return DataNormalization.EnsureRoomAssignments(runtime.Save)
	end)

	-- Mailbox collection request
	MailboxPackets.CollectRequest.OnServerInvoke = function(player: Player)
		local runtime = getRuntime(player) or hydrateRuntime(player)
		if not runtime then
			return false, 0, "Mailbox unavailable."
		end

		local currencyState = resolveCurrencyState(runtime)
		local success, amount, message = MailboxManager.Collect(runtime.Save, CurrencyService, player, currencyState)

		if success then
			broadcastMailboxBalance(runtime, 0)
		end

		MailboxPackets.CollectionEffect:FireClient(player, { Amount = if success then amount else 0 })
		return success, amount, message
	end

	-- Plot claim/unclaim events
	PlotService.PlotClaimed:Connect(function(player: Player)
		local runtime = getRuntime(player) or hydrateRuntime(player)
		if runtime then
			task.defer(function()
				if getRuntime(player) == runtime then
					broadcastMailboxBalance(runtime)
					broadcastPropertyValue(runtime)
				end
			end)
		end
	end)

	PlotService.PlotUnclaimed:Connect(function(player: Player)
		AttributeManager.ClearMailbox(player)
	end)

	-- Tenant packet handlers
	TenantPackets.RequestTenantRooms.OnServerInvoke = function(player: Player)
		local rooms, total, available = TenantService.GetTenantRoomRoster(player)
		return {
			UserId = player.UserId,
			TotalCapacity = total,
			Available = available,
			Rooms = rooms,
		}
	end

	TenantPackets.RequestRoomDiagnostics.OnServerInvoke = function(player: Player)
		return {
			UserId = player.UserId,
			Rooms = TenantService.GetRoomDiagnostics(player),
		}
	end

	TenantPackets.RequestActiveTenants.OnServerInvoke = function(player: Player)
		local runtime = getRuntime(player) or hydrateRuntime(player)
		if not runtime then
			return { UserId = player.UserId, Tenants = {} }
		end
		local leases = DataNormalization.EnsureActiveLeases(runtime.Save, serverNow(), RentConfig.IntervalSeconds)
		return {
			UserId = player.UserId,
			Tenants = LeaseManager.BuildClientPayload(leases),
		}
	end

	TenantPackets.EvictTenantRequest.OnServerInvoke = function(player: Player, tenantId: string)
		local success, message = TenantService.EvictTenant(player, tenantId)
		return success, message or ""
	end

	TenantPackets.GetTenantDetails.OnServerInvoke = function(player: Player, tenantId: string)
		local leases = TenantService.GetActiveLeases(player)
		if not leases or not leases[tenantId] then
			return {
				TenantId = "",
				Name = "Not Found",
				TierId = "",
				Rent = 0,
				RentInterval = 0,
				Boost = 0,
				Traits = {},
				Rating = 0,
				RoomKey = "",
			}
		end

		local lease = leases[tenantId]
		return {
			TenantId = lease.TenantId,
			Name = lease.TenantName or "Unknown",
			TierId = lease.TierId,
			Rent = lease.RentPerInterval,
			RentInterval = lease.RentIntervalSeconds,
			Boost = lease.RentBoostPercent or 0,
			Traits = lease.Traits or {},
			Rating = 0,
			RoomKey = lease.RoomKey or "",
		}
	end

	-- Player lifecycle
	local function onPlayerAdded(player: Player)
		task.defer(function()
			if player.Parent then
				hydrateRuntime(player)
			end
		end)
	end

	local function onPlayerRemoving(player: Player)
		local runtime = getRuntime(player)
		if runtime and runtime.MailboxOwnedPlotConn then
			runtime.MailboxOwnedPlotConn:Disconnect()
		end
		RuntimeByUserId[player.UserId] = nil
		AttributeManager.ClearIncomeRate(player)
		TenantHelpService.UnregisterPlayer(player)
		AttributeManager.ClearMailbox(player)
	end

	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in ipairs(Players:GetPlayers()) do
		onPlayerAdded(player)
	end

	WorldUpdate.Subscribe(UPDATE_TASK_NAME, UPDATE_INTERVAL, stepTenants)
end

return TenantService
