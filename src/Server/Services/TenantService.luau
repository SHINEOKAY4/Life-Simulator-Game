--!strict
-- Server/Services/TenantService.luau
-- Backend scheduler for tenant offers, leases, and rent payments.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local TenantConfig = require(ReplicatedStorage.Shared.Configurations.TenantConfig)
local TenantDefinitions = require(ReplicatedStorage.Shared.Definitions.TenantDefinitions)
local TenantTraits = require(ReplicatedStorage.Shared.Definitions.TenantTraits)
local MailboxPackets = require(ReplicatedStorage.Network.MailboxPackets)
local TenantPackets = require(ReplicatedStorage.Network.TenantPackets)
local ReviewPackets = require(ReplicatedStorage.Network.ReviewPackets)
local PlotFinder = require(ReplicatedStorage.Shared.Utilities.PlotFinder)
local PlayerSession = require(ServerScriptService.Server.Services.PlayerSession)
local PlotService = require(ServerScriptService.Server.Services.PlotService)
local CurrencyService = require(ServerScriptService.Server.Services.CurrencyService)
local ChoreService = require(ServerScriptService.Server.Services.ChoreService)
local WeatherService = require(ServerScriptService.Server.Services.WeatherService)
local TenantValuation = require(ServerScriptService.Server.Modules.TenantValuation)
local WorldUpdate = require(ServerScriptService.Server.Utilities.WorldUpdate)
local HttpService = game:GetService("HttpService")

type ValuationResult = TenantValuation.ValuationResult

local ValuationConfig = TenantConfig.Valuation
local OffersConfig = TenantConfig.Offers
local RentConfig = TenantConfig.Rent

local UPDATE_TASK_NAME = "TenantService"
local UPDATE_INTERVAL = 1
local INFINITE_LEASE_END = math.huge
local MIN_VALUATION_RETRY_SECONDS = 5
local MAX_VALUATION_RETRY_SECONDS = 90

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
	RentBoostPercent: number?,
	Traits: { string }?,
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
	AccruedRemainder: number?,
	RentBoostPercent: number?,
	Traits: { string }?,
	TenantName: string?,
	NextReviewUnix: number?,
}

type TenantStateSave = {
	Version: number?,
	LastOfferUnix: number?,
	OfferSequence: number?,
	PendingOffer: TenantOffer? | boolean?,
	ActiveLease: TenantLease? | boolean?, -- legacy single-slot lease field
	ActiveLeases: { [string]: TenantLease }?,
	OutstandingRent: number?,
	LastKnownScore: number?,
	MailboxBalance: number?,
}

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
}

local TenantService = {}
local RuntimeByUserId: { [number]: RuntimeState } = {}

local RESIDENTS_FOLDER_NAME = "Residents"
local MAILBOX_ATTRIBUTE_NAME = "MailboxBalance"
local PROPERTY_VALUE_ATTRIBUTE_NAME = "PropertyValue"
local MAX_MAILBOX_BALANCE = 4294967295
local MAX_PROPERTY_VALUE = MAX_MAILBOX_BALANCE
local INCOME_RATE_ATTRIBUTE_NAME = "TenantIncomePerSecond"

local function clampMailboxAmount(amount: number): number
	if amount ~= amount then
		return 0
	end
	if amount <= 0 then
		return 0
	end
	local clamped = math.floor(amount + 0.5)
	if clamped < 0 then
		clamped = 0
	elseif clamped > MAX_MAILBOX_BALANCE then
		clamped = MAX_MAILBOX_BALANCE
	end
	return clamped
end

local function findResidentsFolder(player: Player): Folder?
	local plotIndex = player:GetAttribute("OwnedPlotIndex")
	if typeof(plotIndex) ~= "number" then
		return nil
	end
	local plotModel = PlotFinder.FindPlot(plotIndex)
	if not plotModel then
		return nil
	end
	local folder = plotModel:FindFirstChild(RESIDENTS_FOLDER_NAME)
	if folder and folder:IsA("Folder") then
		return folder
	end
	return nil
end

local function ensureResidentsFolder(player: Player): Folder?
	local folder = findResidentsFolder(player)
	if folder then
		return folder
	end
	local plotIndex = player:GetAttribute("OwnedPlotIndex")
	if typeof(plotIndex) ~= "number" then
		return nil
	end
	local plotModel = PlotFinder.FindPlot(plotIndex)
	if not plotModel then
		return nil
	end
	local created = Instance.new("Folder")
	created.Name = RESIDENTS_FOLDER_NAME
	created.Parent = plotModel
	return created
end

local function applyMailboxAttribute(player: Player, balance: number)
	local folder = ensureResidentsFolder(player)
	if folder then
		folder:SetAttribute(MAILBOX_ATTRIBUTE_NAME, balance)
	end
end

local function clampPropertyValue(value: number): number
	if value ~= value then
		return 0
	end
	local rounded = math.floor(value + 0.5)
	if rounded < 0 then
		return 0
	elseif rounded > MAX_PROPERTY_VALUE then
		return MAX_PROPERTY_VALUE
	end
	return rounded
end

local function applyPropertyValueAttribute(player: Player, value: number)
	local folder = ensureResidentsFolder(player)
	if folder then
		folder:SetAttribute(PROPERTY_VALUE_ATTRIBUTE_NAME, value)
	end
end

local function clearPropertyValueAttribute(player: Player)
	local folder = findResidentsFolder(player)
	if folder then
		folder:SetAttribute(PROPERTY_VALUE_ATTRIBUTE_NAME, nil)
	end
end

local function broadcastPropertyValue(runtime: RuntimeState, scoreValue: any?)
	local score = 0
	if typeof(scoreValue) == "number" then
		score = scoreValue
	else
		local lastKnownScore = runtime.Save.LastKnownScore
		if typeof(lastKnownScore) == "number" then
			score = lastKnownScore
		end
	end

	local propertyValue = clampPropertyValue(score)
	runtime.LastPropertyValue = propertyValue
	applyPropertyValueAttribute(runtime.Player, propertyValue)
end

local function broadcastMailboxBalance(runtime: RuntimeState)
	local rawValue = runtime.Save.MailboxBalance
	local numeric = if typeof(rawValue) == "number" then rawValue else 0
	local balance = clampMailboxAmount(numeric)
	runtime.Save.MailboxBalance = balance
	applyMailboxAttribute(runtime.Player, balance)
	MailboxPackets.BalanceUpdate:FireClient(runtime.Player, {
		Balance = balance,
	})
end

local function getLeaseIncomePerSecond(_runtime: RuntimeState, lease: TenantLease): number
	local interval = lease.RentIntervalSeconds
	if typeof(interval) ~= "number" or interval <= 0 then
		return 0
	end

	-- Use fixed rent from lease contract
	local rent = lease.RentPerInterval
	if typeof(rent) ~= "number" or rent <= 0 then
		return 0
	end

	return rent / interval
end

local function updateIncomeRateAttribute(runtime: RuntimeState)
	local leases = runtime.Save.ActiveLeases
	local totalRate = 0
	if typeof(leases) == "table" then
		for _, lease in pairs(leases) do
			totalRate += getLeaseIncomePerSecond(runtime, lease)
		end
	end
	if totalRate ~= totalRate or totalRate <= 0 then
		totalRate = 0
	end
	runtime.Player:SetAttribute(INCOME_RATE_ATTRIBUTE_NAME, totalRate)
end

local function addMailboxIncome(runtime: RuntimeState, amount: number)
	if amount <= 0 then
		return
	end
	local existing = runtime.Save.MailboxBalance
	local currentBalance = if typeof(existing) == "number" then existing else 0
	local updatedBalance = clampMailboxAmount(currentBalance + amount)
	if updatedBalance == currentBalance then
		return
	end
	runtime.Save.MailboxBalance = updatedBalance
	runtime.Save.OutstandingRent = 0
	broadcastMailboxBalance(runtime)
end

local function clearMailboxAttribute(player: Player)
	local folder = findResidentsFolder(player)
	if folder then
		folder:SetAttribute(MAILBOX_ATTRIBUTE_NAME, nil)
	end
	clearPropertyValueAttribute(player)
	local runtime = RuntimeByUserId[player.UserId]
	if runtime then
		runtime.LastPropertyValue = 0
	end
end

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
	if pending.LeaseSeconds == nil then
		pending.LeaseSeconds = OffersConfig.DefaultLease.MaxSeconds
	end
	if pending.Deposit == nil then
		pending.Deposit = math.floor((pending.RentPerInterval or 0) * RentConfig.DepositPercent + 0.5)
	end
	pending.ExpiresUnix = pending.ExpiresUnix or (now + OffersConfig.OfferLifetimeSeconds)
end

local function sanitizeLeaseEntry(lease: TenantLease, now: number)
	lease.RentIntervalSeconds = lease.RentIntervalSeconds or RentConfig.IntervalSeconds
	lease.NextDueUnix = lease.NextDueUnix or (now + (lease.RentIntervalSeconds or RentConfig.IntervalSeconds))
	lease.LeaseEndUnix = lease.LeaseEndUnix or INFINITE_LEASE_END
	lease.MissedPayments = lease.MissedPayments or 0
	lease.DepositHeld = lease.DepositHeld or 0
	lease.StartedUnix = lease.StartedUnix or now
	lease.AccruedRemainder = lease.AccruedRemainder or 0
	lease.NextReviewUnix = lease.NextReviewUnix or (now + (lease.RentIntervalSeconds or RentConfig.IntervalSeconds) * 3)
end

local function ensureActiveLeases(save: TenantStateSave, now: number): { [string]: TenantLease }
	local leases = save.ActiveLeases
	if typeof(leases) ~= "table" then
		leases = {}
		save.ActiveLeases = leases
	end
	local resolved = leases :: { [string]: TenantLease }

	local legacy = save.ActiveLease
	if typeof(legacy) == "table" then
		local tenantId = legacy.TenantId
		if not tenantId or resolved[tenantId] then
			tenantId = string.format("LegacyTenant-%d", math.floor(now))
		end
		legacy.TenantId = tenantId
		resolved[tenantId] = legacy
	else
		save.ActiveLease = nil
	end
	save.ActiveLease = nil

	for tenantId, lease in pairs(resolved) do
		if typeof(lease) ~= "table" then
			resolved[tenantId] = nil :: any
		else
			lease.TenantId = lease.TenantId or tenantId
			sanitizeLeaseEntry(lease, now)
		end
	end

	return resolved
end

local function getActiveLeases(runtime: RuntimeState): { [string]: TenantLease }
	local leases = runtime.Save.ActiveLeases
	if typeof(leases) ~= "table" then
		leases = {}
		runtime.Save.ActiveLeases = leases
	end
	return leases :: { [string]: TenantLease }
end

local function broadcastActiveTenants(runtime: RuntimeState)
	local leases = getActiveLeases(runtime)
	local payload = {}
	for _, lease in pairs(leases) do
		table.insert(payload, {
			TenantId = lease.TenantId,
			Name = lease.TenantName or "Unknown",
			TierId = lease.TierId,
			Traits = lease.Traits or {},
			Rent = lease.RentPerInterval,
			RentInterval = lease.RentIntervalSeconds,
			Boost = lease.RentBoostPercent or 0,
		})
	end
	TenantPackets.ActiveTenantsSync:FireClient(runtime.Player, {
		UserId = runtime.Player.UserId,
		Tenants = payload,
	})
end

local function broadcastTenantDelta(runtime: RuntimeState, tenantId: string, lease: TenantLease?)
	local tenantData = nil
	if lease then
		tenantData = {
			{
				TenantId = lease.TenantId,
				Name = lease.TenantName or "Unknown",
				TierId = lease.TierId,
				Traits = lease.Traits or {},
				Rent = lease.RentPerInterval,
				RentInterval = lease.RentIntervalSeconds,
				Boost = lease.RentBoostPercent or 0,
			},
		}
	end
	TenantPackets.TenantDelta:FireClient(runtime.Player, {
		UserId = runtime.Player.UserId,
		TenantId = tenantId,
		TenantData = tenantData,
	})
end

local function hydrateRuntime(player: Player): RuntimeState?
	local tenantSave = PlayerSession.GetDataAwait(player, "TenantState")
	if not tenantSave then
		return nil
	end

	local existingRuntime = RuntimeByUserId[player.UserId]
	if existingRuntime and existingRuntime.MailboxOwnedPlotConn then
		existingRuntime.MailboxOwnedPlotConn:Disconnect()
		existingRuntime.MailboxOwnedPlotConn = nil
	end

	local now = serverNow()
	sanitizeOffer(tenantSave, now)
	ensureActiveLeases(tenantSave, now)
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
	local mailboxBalance = tenantSave.MailboxBalance
	if typeof(mailboxBalance) ~= "number" then
		tenantSave.MailboxBalance = 0
	else
		tenantSave.MailboxBalance = clampMailboxAmount(mailboxBalance)
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
		ValuationRetrySeconds = MIN_VALUATION_RETRY_SECONDS,
		LastPropertyValue = 0,
		NextValuationUnix = 0,
		NextOfferUnix = now + OffersConfig.MinIntervalSeconds,
		MailboxOwnedPlotConn = nil,
	}

	RuntimeByUserId[player.UserId] = runtime
	runtime.MailboxOwnedPlotConn = player:GetAttributeChangedSignal("OwnedPlotIndex"):Connect(function()
		task.defer(function()
			local active = RuntimeByUserId[player.UserId]
			if active == runtime then
				broadcastMailboxBalance(runtime)
				broadcastPropertyValue(runtime)
			end
		end)
	end)
	updateIncomeRateAttribute(runtime)
	broadcastPropertyValue(runtime)
	broadcastActiveTenants(runtime)

	task.defer(function()
		local active = RuntimeByUserId[player.UserId]
		if active == runtime then
			broadcastMailboxBalance(runtime)
			broadcastPropertyValue(runtime)
		end
	end)
	return runtime
end

local function generateReview(runtime: RuntimeState, lease: TenantLease, reason: string)
	-- Simple rating logic
	local rating = math.random(3, 5)
	if lease.MissedPayments > 0 then
		rating = math.max(1, rating - 1)
	end

	-- Cleanliness impact
	local trashCount = ChoreService.GetTrashCount(runtime.Player)
	if trashCount > 0 then
		-- 1 star penalty for every 2 pieces of trash, minimum 1 star penalty if any trash exists
		local penalty = math.max(1, math.floor(trashCount / 2))
		rating = math.max(1, rating - penalty)
	end

	-- Temperature impact
	local plotState = PlotService.GetState(runtime.Player)
	local totalTemp, roomCount = 0, 0
	if plotState then
		for level = 0, plotState.MaxFloorLevel do
			for _, room in ipairs(plotState:GetRoomsForLevel(level)) do
				if room.CellCount > 0 and room.InsulationScore > 0.2 then
					totalTemp += room.CurrentTemperature
					roomCount += 1
				end
			end
		end
	end

	local avgTemp = if roomCount > 0 then totalTemp / roomCount else WeatherService.GetCurrentTemperature()
	local tempConfig = TenantConfig.Temperature
	local tempPenalty = 0
	local tempComment = nil

	if avgTemp < tempConfig.IdealMin then
		if avgTemp < tempConfig.FreezingThreshold then
			tempPenalty = 2
			tempComment = "It's absolutely freezing in here! Turn on the heat!"
		else
			tempPenalty = 1
			tempComment = "A bit too cold for my taste."
		end
	elseif avgTemp > tempConfig.IdealMax then
		if avgTemp > tempConfig.OverheatThreshold then
			tempPenalty = 2
			tempComment = "It's like a sauna in here! Unbearable heat."
		else
			tempPenalty = 1
			tempComment = "It's too hot inside. Do you have AC?"
		end
	end
	rating = math.clamp(rating - tempPenalty, 1, 5)

	if reason == "Evicted" then
		rating = 1
	end

	local comments = {
		[5] = {
			"Loved living here! Everything was perfect.",
			"Amazing place, highly recommend!",
			"Best landlord ever.",
			"So cozy and nice.",
		},
		[4] = { "Great place, would recommend.", "Nice and cozy.", "Good value for money.", "Pretty solid stay." },
		[3] = { "It was okay. Nothing special.", "Decent place to stay.", "Could be better.", "Average experience." },
		[2] = { "Had some issues, but it was cheap.", "Not the best experience.", "Needs improvement.", "Meh." },
		[1] = {
			"Terrible experience. Do not rent here.",
			"Avoid at all costs.",
			"Worst place ever.",
			"I was kicked out!",
		},
	}

	local pool = comments[rating] or comments[3]

	if tempComment and rating <= 3 then
		pool = { tempComment }
	elseif trashCount > 0 and rating <= 3 then
		local trashComments = {
			"The place was a dump! Trash everywhere.",
			"Disgusting. Garbage all over the floor.",
			"I can't believe I lived in such filth.",
			"Smelled terrible. Clean up your property!",
		}
		pool = trashComments
	end

	local comment = pool[rng:NextInteger(1, #pool)]

	local review = {
		Id = HttpService:GenerateGUID(false),
		TenantName = lease.TenantName or "Unknown Tenant",
		Rating = rating,
		Comment = comment,
		Timestamp = serverNow(),
		Traits = lease.Traits or {},
	}

	local reviewState = PlayerSession.GetData(runtime.Player, "ReviewState")
	if reviewState and reviewState.Reviews then
		table.insert(reviewState.Reviews, 1, review)
		-- Keep last 50 reviews
		if #reviewState.Reviews > 50 then
			table.remove(reviewState.Reviews)
		end

		ReviewPackets.NewReview:FireClient(runtime.Player, {
			Review = review,
		})
	end
end

local function concludeLease(runtime: RuntimeState, tenantId: string, reason: string)
	local leases = getActiveLeases(runtime)
	local lease = leases[tenantId]
	if not lease then
		return
	end

	generateReview(runtime, lease, reason)

	leases[tenantId] = nil
	lease.LeaseEndUnix = serverNow()

	local deposit = lease.DepositHeld or 0
	if deposit > 0 and reason ~= "Evicted" then
		local currencyState = resolveCurrencyState(runtime)
		if currencyState then
			CurrencyService.Add(runtime.Player, "Cash", deposit, currencyState, { Source = "TenantDeposit" })
		end
	end

	updateIncomeRateAttribute(runtime)
	scheduleNextOffer(runtime)
	broadcastTenantDelta(runtime, tenantId, nil)
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

local function composeOffer(runtime: RuntimeState, valuation: ValuationResult, now: number): TenantOffer
	local avgRating = getAverageRating(runtime.Player)
	local tierDefinition, tenantName = TenantDefinitions.GetRandomDefinition(rng, avgRating)
	local baseRent = valuation.RentEstimate
	local variance = OffersConfig.RentVariancePercent
	if variance > 0 then
		baseRent *= (1 + variance * rng:NextNumber(-1, 1))
	end
	baseRent = math.max(ValuationConfig.MinimumRent, math.floor(baseRent + 0.5))
	local rentMultiplier = 1 + (tierDefinition.RentBoostPercent or 0)

	-- Roll traits
	local traitCount = rng:NextInteger(1, 4)
	local traits = TenantTraits.RollTraits(rng, traitCount)
	for _, traitId in ipairs(traits) do
		local trait = TenantTraits.GetTrait(traitId)
		if trait and trait.Effects and trait.Effects.RentMultiplier then
			rentMultiplier *= trait.Effects.RentMultiplier
		end
	end

	local rent = math.max(ValuationConfig.MinimumRent, math.floor(baseRent * rentMultiplier + 0.5))

	local offerId = string.format("%d-%d", runtime.Player.UserId, (runtime.Save.OfferSequence or 0) + 1)

	return {
		OfferId = offerId,
		TierId = tierDefinition.Id,
		RentPerInterval = rent,
		Deposit = 0,
		LeaseSeconds = 0,
		RentIntervalSeconds = RentConfig.IntervalSeconds,
		TenantName = tenantName,
		RentBoostPercent = tierDefinition.RentBoostPercent or 0,
		CreatedUnix = now,
		ExpiresUnix = now + OffersConfig.OfferLifetimeSeconds,
		Score = valuation.Score,
		Traits = traits,
	}
end

local function startLease(runtime: RuntimeState, offer: TenantOffer, now: number): string
	local leases = getActiveLeases(runtime)
	local uniqueId = offer.OfferId
	local suffix = 1
	while leases[uniqueId] do
		suffix += 1
		uniqueId = string.format("%s-%d", offer.OfferId, suffix)
	end

	local lease: TenantLease = {
		TenantId = uniqueId,
		TierId = offer.TierId,
		RentPerInterval = offer.RentPerInterval,
		RentIntervalSeconds = offer.RentIntervalSeconds,
		LeaseEndUnix = INFINITE_LEASE_END,
		NextDueUnix = now + offer.RentIntervalSeconds,
		MissedPayments = 0,
		DepositHeld = offer.Deposit,
		StartedUnix = now,
		AccruedRemainder = 0,
		RentBoostPercent = offer.RentBoostPercent or 0,
		Traits = offer.Traits,
		TenantName = offer.TenantName,
		NextReviewUnix = now + offer.RentIntervalSeconds * 3,
	}

	leases[uniqueId] = lease
	scheduleNextOffer(runtime, now + OffersConfig.CooldownSeconds)
	updateIncomeRateAttribute(runtime)
	broadcastTenantDelta(runtime, uniqueId, lease)
	return uniqueId
end

local function settleOutstanding(runtime: RuntimeState)
	if runtime.Save.OutstandingRent and runtime.Save.OutstandingRent ~= 0 then
		runtime.Save.OutstandingRent = 0
	end
end

local function serviceLeaseEntry(runtime: RuntimeState, lease: TenantLease, now: number, dt: number)
	if dt <= 0 then
		return
	end
	local rate = getLeaseIncomePerSecond(runtime, lease)
	if rate <= 0 then
		lease.AccruedRemainder = 0
		lease.NextDueUnix = now + lease.RentIntervalSeconds
		return
	end

	local accumulated = (lease.AccruedRemainder or 0) + rate * dt
	if accumulated <= 0 then
		lease.AccruedRemainder = 0
		lease.NextDueUnix = now + lease.RentIntervalSeconds
		lease.MissedPayments = 0
		return
	end
	if accumulated < 0 then
		accumulated = 0
	end

	local payout = math.floor(accumulated)
	lease.AccruedRemainder = accumulated - payout
	lease.NextDueUnix = now + lease.RentIntervalSeconds
	lease.MissedPayments = 0

	if payout > 0 then
		addMailboxIncome(runtime, payout)
	end

	-- Periodic Review Check
	if lease.NextReviewUnix and now >= lease.NextReviewUnix then
		generateReview(runtime, lease, "Periodic")
		lease.NextReviewUnix = now + (lease.RentIntervalSeconds or RentConfig.IntervalSeconds) * 3
	end
end

local function serviceLease(runtime: RuntimeState, now: number, dt: number)
	local leases = runtime.Save.ActiveLeases
	if typeof(leases) ~= "table" then
		return
	end

	if not next(leases) then
		return
	end

	settleOutstanding(runtime)

	for tenantId, lease in pairs(leases) do
		if lease.LeaseEndUnix <= now then
			concludeLease(runtime, tenantId, "Complete")
		else
			serviceLeaseEntry(runtime, lease, now, dt)
		end
	end
end

local function collectMailbox(runtime: RuntimeState): (boolean, number, string)
	local rawBalance = runtime.Save.MailboxBalance
	local balance = if typeof(rawBalance) == "number" then rawBalance else 0
	if balance <= 0 then
		runtime.Save.MailboxBalance = 0
		broadcastMailboxBalance(runtime)
		return false, 0, "Mailbox is empty."
	end

	local currencyState = resolveCurrencyState(runtime)
	if not currencyState then
		return false, 0, "Unable to access currency data."
	end

	local payout = clampMailboxAmount(balance)
	if payout <= 0 then
		runtime.Save.MailboxBalance = 0
		broadcastMailboxBalance(runtime)
		return false, 0, "Mailbox is empty."
	end

	runtime.Save.MailboxBalance = 0
	broadcastMailboxBalance(runtime)
	CurrencyService.Add(runtime.Player, "Cash", payout, currencyState, {
		Source = "TenantMailbox",
	})
	return true, payout, "Collected rent from mailbox."
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
		local retry = math.clamp(runtime.ValuationRetrySeconds * 2, MIN_VALUATION_RETRY_SECONDS, MAX_VALUATION_RETRY_SECONDS)
		runtime.ValuationRetrySeconds = retry
		runtime.NextValuationUnix = now + retry
		return
	end

	local avgRating = getAverageRating(runtime.Player)
	local valuation = TenantValuation.Evaluate(plotState, avgRating)
	if not valuation then
		local retry = math.clamp(runtime.ValuationRetrySeconds * 2, MIN_VALUATION_RETRY_SECONDS, MAX_VALUATION_RETRY_SECONDS)
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

local function stepTenants(dt: number)
	local now = serverNow()
	for userId, runtime in pairs(RuntimeByUserId) do
		if not runtime.Player.Parent then
			RuntimeByUserId[userId] = nil
		else
			refreshValuation(runtime, now)
			tryExpireOffer(runtime, now)
			tryGenerateOffer(runtime, now)
			serviceLease(runtime, now, dt)
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

function TenantService.GetActiveLeases(player: Player): { [string]: TenantLease }?
	local runtime: RuntimeState? = RuntimeByUserId[player.UserId]
	if not runtime then
		runtime = hydrateRuntime(player)
	end
	local resolvedRuntime: RuntimeState? = runtime
	if not resolvedRuntime then
		return nil
	end

	local leases = resolvedRuntime.Save.ActiveLeases
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

function TenantService.AcceptOffer(player: Player): boolean
	local runtime = RuntimeByUserId[player.UserId]
	if not runtime then
		return false
	end

	local pending = runtime.Save.PendingOffer
	if typeof(pending) ~= "table" then
		return false
	end

	runtime.Save.PendingOffer = nil
	local success = TenantService.BeginLeaseFromOffer(player, pending)
	return success
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

function TenantService.GenerateProspectOffer(player: Player): TenantOffer?
	local runtime: RuntimeState? = RuntimeByUserId[player.UserId]
	if not runtime then
		runtime = hydrateRuntime(player)
	end
	if not runtime then
		return nil
	end
	local resolvedRuntime: RuntimeState = runtime
	refreshValuation(resolvedRuntime, serverNow())
	local valuation = resolvedRuntime.CachedValuation
	if not valuation then
		return nil
	end
	local now = serverNow()
	local offer = composeOffer(resolvedRuntime, valuation, now)
	local sequence = resolvedRuntime.Save.OfferSequence or 0
	sequence += 1
	resolvedRuntime.Save.OfferSequence = sequence
	resolvedRuntime.Save.LastOfferUnix = now
	resolvedRuntime.NextOfferUnix = math.max(resolvedRuntime.NextOfferUnix, now + OffersConfig.CooldownSeconds)
	return offer
end

function TenantService.BeginLeaseFromOffer(player: Player, offer: TenantOffer): (boolean, string?, string?)
	local runtime: RuntimeState? = RuntimeByUserId[player.UserId]
	if not runtime then
		runtime = hydrateRuntime(player)
	end
	if not runtime then
		return false, "Tenant data unavailable.", nil
	end
	local resolvedRuntime: RuntimeState = runtime
	local tenantId = startLease(resolvedRuntime, offer, serverNow())
	resolvedRuntime.Save.LastOfferUnix = serverNow()
	return true, nil, tenantId
end

function TenantService.EvictTenant(player: Player, tenantId: string): (boolean, string?)
	if type(tenantId) ~= "string" or tenantId == "" then
		return false, "Invalid tenant id."
	end

	local runtime: RuntimeState? = RuntimeByUserId[player.UserId]
	if not runtime then
		runtime = hydrateRuntime(player)
	end
	if not runtime then
		return false, "Tenant data unavailable."
	end

	local leases = getActiveLeases(runtime)
	local lease = leases[tenantId]
	if not lease then
		return false, "Tenant not found."
	end

	concludeLease(runtime, tenantId, "Evicted")
	return true, nil
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
	local runtime = RuntimeByUserId[player.UserId]
	if runtime and runtime.MailboxOwnedPlotConn then
		runtime.MailboxOwnedPlotConn:Disconnect()
		runtime.MailboxOwnedPlotConn = nil
	end
	RuntimeByUserId[player.UserId] = nil
	player:SetAttribute(INCOME_RATE_ATTRIBUTE_NAME, 0)
	clearMailboxAttribute(player)
end

function TenantService.Init()
	MailboxPackets.CollectRequest.OnServerInvoke = function(player: Player)
		local runtime: RuntimeState? = RuntimeByUserId[player.UserId]
		if not runtime then
			runtime = hydrateRuntime(player)
		end
		local resolvedRuntime: RuntimeState? = runtime
		if not resolvedRuntime then
			return false, 0, "Mailbox unavailable."
		end

		local success, amount, message = collectMailbox(resolvedRuntime)
		if success then
			MailboxPackets.CollectionEffect:FireClient(player, {
				Amount = amount,
			})
		else
			MailboxPackets.CollectionEffect:FireClient(player, {
				Amount = 0,
			})
		end
		return success, amount, message
	end

	PlotService.PlotClaimed:Connect(function(player: Player)
		local runtime: RuntimeState? = RuntimeByUserId[player.UserId]
		if not runtime then
			runtime = hydrateRuntime(player)
		end
		local resolvedRuntime: RuntimeState? = runtime
		if not resolvedRuntime then
			return
		end
		task.defer(function()
			local active = RuntimeByUserId[player.UserId]
			if active == resolvedRuntime then
				broadcastMailboxBalance(resolvedRuntime)
				broadcastPropertyValue(resolvedRuntime)
			end
		end)
	end)

	PlotService.PlotUnclaimed:Connect(function(player: Player)
		clearMailboxAttribute(player)
	end)

	TenantPackets.EvictTenantRequest.OnServerInvoke = function(player: Player, tenantId: string)
		local success, message = TenantService.EvictTenant(player, tenantId)
		return success, message or ""
	end

	TenantPackets.GetTenantDetails.OnServerInvoke = function(player: Player, tenantId: string)
		local leases = TenantService.GetActiveLeases(player)
		if not leases then
			return {
				TenantId = "",
				Name = "Not Found",
				TierId = "",
				Rent = 0,
				RentInterval = 0,
				Boost = 0,
				Traits = {},
				Rating = 0,
			}
		end
		local lease = leases[tenantId]
		if not lease then
			return {
				TenantId = "",
				Name = "Not Found",
				TierId = "",
				Rent = 0,
				RentInterval = 0,
				Boost = 0,
				Traits = {},
				Rating = 0,
			}
		end

		return {
			TenantId = lease.TenantId,
			Name = lease.TenantName or "Unknown",
			TierId = lease.TierId,
			Rent = lease.RentPerInterval,
			RentInterval = lease.RentIntervalSeconds,
			Boost = lease.RentBoostPercent or 0,
			Traits = lease.Traits or {},
			Rating = 0,
		}
	end

	ReviewPackets.GetReviewsRequest.OnServerInvoke = function(player: Player)
		local reviewState = PlayerSession.GetData(player, "ReviewState")
		if not reviewState or not reviewState.Reviews then
			return {}
		end
		return reviewState.Reviews
	end

	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in ipairs(Players:GetPlayers()) do
		onPlayerAdded(player)
	end

	WorldUpdate.Subscribe(UPDATE_TASK_NAME, UPDATE_INTERVAL, stepTenants)
end

return TenantService
