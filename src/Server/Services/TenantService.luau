--!strict
-- Server/Services/TenantService.luau
-- Backend scheduler for tenant offers, leases, and rent payments.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local TenantConfig = require(ReplicatedStorage.Shared.Configurations.TenantConfig)
local PlayerSession = require(ServerScriptService.Server.Services.PlayerSession)
local PlotService = require(ServerScriptService.Server.Services.PlotService)
local CurrencyService = require(ServerScriptService.Server.Services.CurrencyService)
local TenantValuation = require(ServerScriptService.Server.Modules.TenantValuation)
local WorldUpdate = require(ServerScriptService.Server.Utilities.WorldUpdate)

type ValuationResult = TenantValuation.ValuationResult

local ValuationConfig = TenantConfig.Valuation
local OffersConfig = TenantConfig.Offers
local RentConfig = TenantConfig.Rent

local UPDATE_TASK_NAME = "TenantService"
local UPDATE_INTERVAL = 2

local rng = Random.new()

export type TenantOffer = {
	OfferId: string,
	TierId: string,
	RentPerInterval: number,
	Deposit: number,
	LeaseSeconds: number,
	RentIntervalSeconds: number,
	TenantName: string,
	CreatedUnix: number,
	ExpiresUnix: number,
	Score: number,
}

export type TenantLease = {
	TenantId: string,
	TierId: string,
	RentPerInterval: number,
	RentIntervalSeconds: number,
	LeaseEndUnix: number,
	NextDueUnix: number,
	MissedPayments: number,
	DepositHeld: number,
	StartedUnix: number,
}

type TenantStateSave = {
	Version: number?,
	LastOfferUnix: number?,
	OfferSequence: number?,
	PendingOffer: TenantOffer? | boolean?,
	ActiveLease: TenantLease? | boolean?,
	OutstandingRent: number?,
	LastKnownScore: number?,
}

type RuntimeState = {
	Player: Player,
	Save: TenantStateSave,
	CurrencyState: { [string]: number }?,
	CachedValuation: ValuationResult?,
	NextValuationUnix: number,
	NextOfferUnix: number,
}

local TenantService = {}
local RuntimeByUserId: { [number]: RuntimeState } = {}

local function serverNow(): number
	return Workspace:GetServerTimeNow()
end

local function scheduleNextOffer(runtime: RuntimeState, anchorTime: number?)
	local now = anchorTime or serverNow()
	local minDelay = OffersConfig.MinIntervalSeconds
	local maxDelay = OffersConfig.MaxIntervalSeconds
	local delay = minDelay
	if maxDelay > minDelay then
		delay += rng:NextNumber(0, maxDelay - minDelay)
	end
	runtime.NextOfferUnix = now + delay
end

local function resolveCurrencyState(runtime: RuntimeState): { [string]: number }?
	local cached = runtime.CurrencyState
	if cached then
		return cached
	end

	local player = runtime.Player
	local data = PlayerSession.TryGetData(player, "CurrencyState")
	if not data then
		data = PlayerSession.GetDataAwait(player, "CurrencyState")
	end

	runtime.CurrencyState = data
	return data
end

local function sanitizeOffer(save: TenantStateSave, now: number)
	local pending = save.PendingOffer
	if typeof(pending) ~= "table" then
		save.PendingOffer = nil
		return
	end

	pending.RentIntervalSeconds = pending.RentIntervalSeconds or RentConfig.IntervalSeconds
	pending.LeaseSeconds = pending.LeaseSeconds or OffersConfig.DefaultLease.MaxSeconds
	pending.Deposit = pending.Deposit or math.floor((pending.RentPerInterval or 0) * RentConfig.DepositPercent + 0.5)
	pending.ExpiresUnix = pending.ExpiresUnix or (now + OffersConfig.OfferLifetimeSeconds)
end

local function sanitizeLease(save: TenantStateSave, now: number)
	local lease = save.ActiveLease
	if typeof(lease) ~= "table" then
		save.ActiveLease = nil
		return
	end

	lease.RentIntervalSeconds = lease.RentIntervalSeconds or RentConfig.IntervalSeconds
	lease.NextDueUnix = lease.NextDueUnix or (now + lease.RentIntervalSeconds)
	lease.LeaseEndUnix = lease.LeaseEndUnix
		or (now + math.max(OffersConfig.DefaultLease.MaxSeconds, lease.RentIntervalSeconds))
	lease.MissedPayments = lease.MissedPayments or 0
	lease.DepositHeld = lease.DepositHeld or 0
	lease.StartedUnix = lease.StartedUnix or now
end

local function hydrateRuntime(player: Player): RuntimeState?
	local tenantSave = PlayerSession.GetDataAwait(player, "TenantState")
	if not tenantSave then
		return nil
	end

	local now = serverNow()
	sanitizeOffer(tenantSave, now)
	sanitizeLease(tenantSave, now)
	if typeof(tenantSave.LastOfferUnix) ~= "number" then
		tenantSave.LastOfferUnix = 0
	end
	if typeof(tenantSave.OfferSequence) ~= "number" then
		tenantSave.OfferSequence = 0
	end
	if typeof(tenantSave.OutstandingRent) ~= "number" then
		tenantSave.OutstandingRent = 0
	end
	if typeof(tenantSave.Version) ~= "number" then
		tenantSave.Version = 1
	end

	local currencyState = PlayerSession.TryGetData(player, "CurrencyState")
	if not currencyState then
		currencyState = PlayerSession.GetDataAwait(player, "CurrencyState")
	end

	local runtime: RuntimeState = {
		Player = player,
		Save = tenantSave,
		CurrencyState = currencyState,
		CachedValuation = nil,
		NextValuationUnix = 0,
		NextOfferUnix = now + OffersConfig.MinIntervalSeconds,
	}

	RuntimeByUserId[player.UserId] = runtime
	return runtime
end

local function concludeLease(runtime: RuntimeState, reason: string)
	local lease = runtime.Save.ActiveLease
	if typeof(lease) ~= "table" then
		return
	end

	runtime.Save.ActiveLease = nil
	lease.LeaseEndUnix = serverNow()

	local deposit = lease.DepositHeld or 0
	if deposit > 0 and reason ~= "Evicted" then
		local currencyState = resolveCurrencyState(runtime)
		if currencyState then
			CurrencyService.Add(runtime.Player, "Cash", deposit, currencyState, { Source = "TenantDeposit" })
		end
	end

	scheduleNextOffer(runtime)
end

local function composeOffer(runtime: RuntimeState, valuation: ValuationResult, now: number): TenantOffer
	local rent = valuation.RentEstimate
	local variance = OffersConfig.RentVariancePercent
	if variance > 0 then
		rent *= (1 + variance * rng:NextNumber(-1, 1))
	end

	rent = math.max(ValuationConfig.MinimumRent, math.floor(rent + 0.5))
	local tierId = valuation.TierId
	local leaseWindow = OffersConfig.LeaseDurations[tierId] or OffersConfig.DefaultLease
	local leaseSeconds = math.floor(rng:NextNumber(leaseWindow.MinSeconds, leaseWindow.MaxSeconds))
	if leaseSeconds < RentConfig.IntervalSeconds then
		leaseSeconds = RentConfig.IntervalSeconds * 2
	end

	local namePool = OffersConfig.NamePool
	local tenantName = namePool[1] or "Tenant"
	if #namePool > 0 then
		tenantName = namePool[rng:NextInteger(1, #namePool)]
	end

	local offerId = string.format("%d-%d", runtime.Player.UserId, (runtime.Save.OfferSequence or 0) + 1)

	return {
		OfferId = offerId,
		TierId = tierId,
		RentPerInterval = rent,
		Deposit = math.floor(rent * RentConfig.DepositPercent + 0.5),
		LeaseSeconds = leaseSeconds,
		RentIntervalSeconds = RentConfig.IntervalSeconds,
		TenantName = tenantName,
		CreatedUnix = now,
		ExpiresUnix = now + OffersConfig.OfferLifetimeSeconds,
		Score = valuation.Score,
	}
end

local function startLease(runtime: RuntimeState, offer: TenantOffer, now: number)
	local lease: TenantLease = {
		TenantId = offer.OfferId,
		TierId = offer.TierId,
		RentPerInterval = offer.RentPerInterval,
		RentIntervalSeconds = offer.RentIntervalSeconds,
		LeaseEndUnix = now + offer.LeaseSeconds,
		NextDueUnix = now + offer.RentIntervalSeconds,
		MissedPayments = 0,
		DepositHeld = offer.Deposit,
		StartedUnix = now,
	}

	runtime.Save.ActiveLease = lease
	local currencyState = resolveCurrencyState(runtime)
	if currencyState and lease.DepositHeld > 0 then
		CurrencyService.Add(runtime.Player, "Cash", lease.DepositHeld, currencyState, { Source = "TenantDeposit" })
	end

	scheduleNextOffer(runtime, now + OffersConfig.CooldownSeconds)
end

local function settleOutstanding(runtime: RuntimeState)
	local outstanding = runtime.Save.OutstandingRent
	if not outstanding or outstanding <= 0 then
		return
	end

	local currencyState = resolveCurrencyState(runtime)
	if not currencyState then
		return
	end

	local balance = currencyState.Cash or 0
	if balance <= 0 then
		return
	end

	local payment = math.min(balance, outstanding)
	if payment <= 0 then
		return
	end

	CurrencyService.Remove(runtime.Player, "Cash", payment, currencyState)
	runtime.Save.OutstandingRent = math.max(0, outstanding - payment)
end

local function serviceLease(runtime: RuntimeState, now: number)
	local lease = runtime.Save.ActiveLease
	if typeof(lease) ~= "table" then
		return
	end

	if lease.LeaseEndUnix <= now then
		concludeLease(runtime, "Complete")
		return
	end

	settleOutstanding(runtime)

	local nextDue = lease.NextDueUnix
	if nextDue > now then
		return
	end

	local currencyState = resolveCurrencyState(runtime)
	if not currencyState then
		lease.NextDueUnix = now + RentConfig.GraceSeconds
		return
	end

	local balance = currencyState.Cash or 0
	local rentAmount = lease.RentPerInterval
	if rentAmount <= 0 then
		lease.NextDueUnix = now + lease.RentIntervalSeconds
		return
	end

	if balance >= rentAmount then
		CurrencyService.Remove(runtime.Player, "Cash", rentAmount, currencyState)
		lease.NextDueUnix = now + lease.RentIntervalSeconds
		lease.MissedPayments = 0
	else
		lease.MissedPayments += 1
		runtime.Save.OutstandingRent = (runtime.Save.OutstandingRent or 0) + rentAmount
		if lease.MissedPayments >= RentConfig.MaxMissedPayments then
			concludeLease(runtime, "Evicted")
		else
			lease.NextDueUnix = now + RentConfig.GraceSeconds
		end
	end
end

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
		runtime.NextValuationUnix = now + 5
		return
	end

	local valuation = TenantValuation.Evaluate(plotState)
	if not valuation then
		runtime.NextValuationUnix = now + 5
		return
	end

	runtime.CachedValuation = valuation
	runtime.Save.LastKnownScore = valuation.Score
	runtime.NextValuationUnix = now + ValuationConfig.RefreshIntervalSeconds
end

local function tryExpireOffer(runtime: RuntimeState, now: number)
	local pending = runtime.Save.PendingOffer
	if typeof(pending) ~= "table" then
		return
	end

	if pending.ExpiresUnix > now then
		return
	end

	runtime.Save.PendingOffer = nil
	scheduleNextOffer(runtime)
end

local function tryGenerateOffer(runtime: RuntimeState, now: number)
	if runtime.Save.ActiveLease then
		return
	end

	if typeof(runtime.Save.PendingOffer) == "table" then
		return
	end

	if runtime.NextOfferUnix > now then
		return
	end

	local valuation = runtime.CachedValuation
	if not valuation then
		return
	end

	local offer = composeOffer(runtime, valuation, now)
	runtime.Save.PendingOffer = offer
	local sequence = runtime.Save.OfferSequence or 0
	sequence += 1
	runtime.Save.OfferSequence = sequence
	runtime.Save.LastOfferUnix = now
	runtime.NextOfferUnix = now + OffersConfig.CooldownSeconds
end

local function stepTenants(_dt: number)
	local now = serverNow()
	for userId, runtime in pairs(RuntimeByUserId) do
		if not runtime.Player.Parent then
			RuntimeByUserId[userId] = nil
		else
			refreshValuation(runtime, now)
			tryExpireOffer(runtime, now)
			tryGenerateOffer(runtime, now)
			serviceLease(runtime, now)
		end
	end
end

function TenantService.GetPendingOffer(player: Player): TenantOffer?
	local runtime = RuntimeByUserId[player.UserId]
	if not runtime then
		return nil
	end

	local pending = runtime.Save.PendingOffer
	if typeof(pending) ~= "table" then
		return nil
	end

	return table.clone(pending)
end

function TenantService.GetActiveLease(player: Player): TenantLease?
	local runtime = RuntimeByUserId[player.UserId]
	if not runtime then
		return nil
	end

	local lease = runtime.Save.ActiveLease
	if typeof(lease) ~= "table" then
		return nil
	end

	return table.clone(lease)
end

function TenantService.AcceptOffer(player: Player): boolean
	local runtime = RuntimeByUserId[player.UserId]
	if not runtime then
		return false
	end

	if runtime.Save.ActiveLease then
		return false
	end

	local pending = runtime.Save.PendingOffer
	if typeof(pending) ~= "table" then
		return false
	end

	runtime.Save.PendingOffer = nil
	startLease(runtime, pending, serverNow())
	return true
end

function TenantService.DeclineOffer(player: Player): boolean
	local runtime = RuntimeByUserId[player.UserId]
	if not runtime then
		return false
	end

	if typeof(runtime.Save.PendingOffer) ~= "table" then
		return false
	end

	runtime.Save.PendingOffer = nil
	scheduleNextOffer(runtime)
	return true
end

function TenantService.GetValuation(player: Player): ValuationResult?
	local runtime = RuntimeByUserId[player.UserId]
	if not runtime or not runtime.CachedValuation then
		return nil
	end

	return runtime.CachedValuation
end

local function onPlayerAdded(player: Player)
	task.defer(function()
		if not player.Parent then
			return
		end
		hydrateRuntime(player)
	end)
end

local function onPlayerRemoving(player: Player)
	RuntimeByUserId[player.UserId] = nil
end

function TenantService.Init()
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in ipairs(Players:GetPlayers()) do
		onPlayerAdded(player)
	end

	WorldUpdate.Subscribe(UPDATE_TASK_NAME, UPDATE_INTERVAL, stepTenants)
end

return TenantService
