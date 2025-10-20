--!strict
-- ServerScriptService/Server/Services/EconomyCycleService.luau
-- Handles recurring household bills on a fixed cadence.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local TimeScale = require(ReplicatedStorage.Shared.Utilities.TimeScale)
local PlayerSession = require(ServerScriptService.Server.Services.PlayerSession)
local CurrencyService = require(ServerScriptService.Server.Services.CurrencyService)
local PlotService = require(ServerScriptService.Server.Services.PlotService)
local ResidentService = require(ServerScriptService.Server.Services.ResidentService)
local WorldUpdate = require(ServerScriptService.Server.Utilities.WorldUpdate)

local EconomyCycleService = {}

local UPDATE_INTERVAL_SECONDS = 5
local BILLING_TRIGGER_HOUR = 9 -- 9 AM in-game time
local BILLING_PERIOD_DAYS = 4
local PAYROLL_PAYOUT_HOUR = 20 -- 8 PM in-game time

local BASE_PLOT_CHARGE = 120
local PER_CHUNK_CHARGE = 18
local PER_RESIDENT_CHARGE = 35
local CASH_CURRENCY = "Cash"

local lastBillingByUser: {
	[number]: {
		Day: number,
		Charge: number,
		Collected: number,
		Outstanding: number,
		Breakdown: { Base: number, Chunks: number, Residents: number },
	},
} =
	{}

local function ensurePayrollState(state: any?)
	if typeof(state) ~= "table" then
		return nil
	end
	if typeof(state.PendingAmount) ~= "number" then
		state.PendingAmount = 0
	end
	if typeof(state.LastPayoutDay) ~= "number" then
		state.LastPayoutDay = -1
	end
	return state
end

local function ensureEconomyState(state: any?)
	if typeof(state) ~= "table" then
		return nil
	end
	if typeof(state.LastBillingDay) ~= "number" then
		state.LastBillingDay = -BILLING_PERIOD_DAYS
	end
	if typeof(state.OutstandingBills) ~= "number" then
		state.OutstandingBills = 0
	end
	if state.OutstandingBills < 0 then
		state.OutstandingBills = 0
	else
		state.OutstandingBills = math.floor(state.OutstandingBills + 0.5)
	end
	return state
end

local function countUnlockedChunks(player: Player): number
	local runtimeState = PlotService.GetState(player)
	if runtimeState and typeof(runtimeState.Save) == "table" then
		local chunks = runtimeState.Save.UnlockedChunks
		if typeof(chunks) == "table" then
			return #chunks
		end
	end
	local plotData = PlayerSession.TryGetData(player, "PlotState")
	if typeof(plotData) == "table" and typeof(plotData.UnlockedChunks) == "table" then
		return #plotData.UnlockedChunks
	end
	return 0
end

local function countResidents(player: Player): number
	local activeResidents = ResidentService.GetResidents(player)
	if typeof(activeResidents) == "table" then
		local count = 0
		for _ in pairs(activeResidents) do
			count += 1
		end
		if count > 0 then
			return count
		end
	end
	local household = PlayerSession.TryGetData(player, "HouseholdState")
	if typeof(household) == "table" then
		local residentCount = household.ResidentsCount
		if typeof(residentCount) == "number" then
			return residentCount
		end
		local residentsList = household.Residents
		if typeof(residentsList) == "table" then
			return #residentsList
		end
	end
	return 0
end

local function computeBillingCharge(player: Player)
	local chunkCount = countUnlockedChunks(player)
	local residentCount = countResidents(player)
	local baseCharge = BASE_PLOT_CHARGE
	local chunkCharge = chunkCount * PER_CHUNK_CHARGE
	local residentCharge = residentCount * PER_RESIDENT_CHARGE
	local total = math.max(0, math.floor(baseCharge + chunkCharge + residentCharge + 0.5))
	return total, {
		Base = baseCharge,
		Chunks = chunkCharge,
		Residents = residentCharge,
	}
end

local function processBillingCycle(player: Player, economyState: any, targetDay: number, currencyState: any?)
	local charge, breakdown = computeBillingCharge(player)
	local outstanding = math.max(0, economyState.OutstandingBills or 0)
	local totalDue = math.max(0, math.floor(outstanding + charge + 0.5))
	economyState.OutstandingBills = totalDue
	economyState.LastBillingDay = targetDay

	local collected = 0
	local beforeBalance = 0
	if currencyState and typeof(currencyState) == "table" and totalDue > 0 then
		beforeBalance = currencyState[CASH_CURRENCY] or 0
		local resultingBalance = CurrencyService.Remove(player, CASH_CURRENCY, totalDue, currencyState)
		collected = math.max(0, beforeBalance - resultingBalance)
	end

	local remaining = math.max(0, totalDue - collected)
	economyState.OutstandingBills = remaining
	lastBillingByUser[player.UserId] = {
		Day = targetDay,
		Charge = charge,
		Collected = collected,
		Outstanding = remaining,
		Breakdown = breakdown,
	}

	if charge > 0 or collected > 0 or remaining > 0 then
		print(
			string.format(
				"[EconomyCycle] Billing processed for %s: charge=$%d collected=$%d outstanding=$%d (day %d)",
				player.Name,
				charge,
				collected,
				remaining,
				targetDay
			)
		)
	end
end

local function handleBilling(
	player: Player,
	economyState: any,
	dayIndex: number,
	secondsIntoDay: number,
	billingTriggerSeconds: number,
	currencyState: any?
)
	if economyState.LastBillingDay > dayIndex then
		economyState.LastBillingDay = dayIndex - BILLING_PERIOD_DAYS
	end

	while economyState.LastBillingDay + BILLING_PERIOD_DAYS < dayIndex do
		local targetDay = economyState.LastBillingDay + BILLING_PERIOD_DAYS
		processBillingCycle(player, economyState, targetDay, currencyState)
	end

	if economyState.LastBillingDay + BILLING_PERIOD_DAYS <= dayIndex and secondsIntoDay >= billingTriggerSeconds then
		processBillingCycle(player, economyState, dayIndex, currencyState)
	end
end

local function processPayroll(
	player: Player,
	payrollState: any,
	currencyState: any?,
	dayIndex: number,
	secondsIntoDay: number,
	payrollTriggerSeconds: number
)
	local pending = math.max(0, math.floor((payrollState.PendingAmount or 0) + 0.5))
	if pending <= 0 then
		return
	end
	local lastDay = tonumber(payrollState.LastPayoutDay) or -1
	local reachedTrigger = dayIndex > lastDay and secondsIntoDay >= payrollTriggerSeconds
	local missedPreviousDay = dayIndex > lastDay + 1
	local shouldPay = reachedTrigger or missedPreviousDay
	if not shouldPay then
		return
	end
	if currencyState == nil then
		warn(string.format("[EconomyCycle] Missing CurrencyState for payroll deposit (%s)", player.Name))
		return
	end
	CurrencyService.Add(player, CASH_CURRENCY, pending, currencyState)
	payrollState.PendingAmount = 0
	payrollState.LastPayoutDay = dayIndex
	print(string.format("[EconomyCycle] Payroll deposited for %s: amount=$%d (day %d)", player.Name, pending, dayIndex))
end

local function step()
	local players = Players:GetPlayers()
	if #players == 0 then
		return
	end

	local secondsPerDay = TimeScale.GetSecondsPerFullDay()
	local billingTriggerSeconds = math.floor(secondsPerDay * (BILLING_TRIGGER_HOUR / 24))
	local payrollTriggerSeconds = math.floor(secondsPerDay * (PAYROLL_PAYOUT_HOUR / 24))
	local dayIndex = TimeScale.GetDayIndex()
	local secondsIntoDay = TimeScale.GetSecondsIntoDay()

	for _, player in ipairs(players) do
		local currencyState = PlayerSession.TryGetData(player, "CurrencyState")
		local economyState = ensureEconomyState(PlayerSession.TryGetData(player, "EconomyState"))
		if economyState then
			handleBilling(player, economyState, dayIndex, secondsIntoDay, billingTriggerSeconds, currencyState)
		end
		local payrollState = ensurePayrollState(PlayerSession.TryGetData(player, "PayrollState"))
		if payrollState then
			processPayroll(player, payrollState, currencyState, dayIndex, secondsIntoDay, payrollTriggerSeconds)
		end
	end
end

function EconomyCycleService.Init()
	lastBillingByUser = {}
	Players.PlayerRemoving:Connect(function(player)
		lastBillingByUser[player.UserId] = nil
	end)
end

function EconomyCycleService.Start()
	if WorldUpdate.IsSubscribed("EconomyCycleTick") then
		return
	end
	WorldUpdate.Subscribe("EconomyCycleTick", UPDATE_INTERVAL_SECONDS, function(_dt)
		step()
	end)
end

function EconomyCycleService.GetLastBillingSummary(player: Player)
	return lastBillingByUser[player.UserId]
end

return EconomyCycleService
