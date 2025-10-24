--!strict
-- ServerScriptService/Server/Services/BillingService.lua

local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Players = game:GetService("Players")

local BillingPackets = require(ReplicatedStorage.Network.BillingPackets)
local PlayerSession = require(script.Parent.PlayerSession)
local PlotService = require(script.Parent.PlotService)
local CurrencyService = require(script.Parent.CurrencyService)
local BillingState = require(ServerScriptService.Server.Classes.BillingState)
local WorldUpdate = require(ServerScriptService.Server.Utilities.WorldUpdate)
local BillingCalculator = require(ServerScriptService.Server.Utilities.BillingCalculator)
local TimeScale = require(ReplicatedStorage.Shared.Utilities.TimeScale)

type OutstandingBreakdown = {
	PlotTax: number,
	Electric: number,
	Food: number,
}

type CurrencyStateData = {
	Cash: number,
	OutstandingBalance: number,
	[string]: number,
}

local BILLING_DURATION_SECONDS = 480
local BILLING_GRACE_PERIOD_SECONDS = 10
local CHECK_INTERVAL_SECONDS = 2
local BASE_CYCLE_CHARGE = 100

local CATEGORY_KEYS = { "PlotTax", "Electric", "Food" }

local BillingService = {}
local PlayerBillingStates: { [number]: BillingState.BillingState } = {}

local function resolveDueClockTime(billingState: BillingState.BillingState): number
	local serverNow = Workspace:GetServerTimeNow()
	local elapsed = billingState:GetElapsedSeconds()
	local cycleStartSeconds = serverNow - elapsed
	local dueServerSeconds = cycleStartSeconds + billingState.DurationSeconds
	return TimeScale.ClockTimeFromServerSeconds(dueServerSeconds)
end

local function sanitizeChargeAmount(amount: number): number
	if typeof(amount) ~= "number" or amount ~= amount then
		return 0
	end
	if amount <= 0 then
		return 0
	end
	local integerAmount = math.round(amount)
	if integerAmount < 0 then
		return 0
	end
	return integerAmount
end

type FoodUsageBucket = {
	Current: number,
	Pending: number,
	LastBilledCost: number,
}

local PlayerFoodUsage: { [number]: FoodUsageBucket } = {}

-- Forward declaration for use in RecordMealUsage
local broadcastBillingUpdate: (player: Player, billingState: BillingState.BillingState) -> ()

local function createEmptyBreakdown(): OutstandingBreakdown
	return {
		PlotTax = 0,
		Electric = 0,
		Food = 0,
	}
end

local function sumBreakdownAmounts(breakdown: OutstandingBreakdown): number
	return breakdown.PlotTax + breakdown.Electric + breakdown.Food
end

local function sanitizeBreakdown(breakdown: OutstandingBreakdown)
	for _, key in CATEGORY_KEYS do
		local value = breakdown[key]
		if typeof(value) ~= "number" or value ~= value or value < 0 then
			breakdown[key] = 0
		else
			breakdown[key] = sanitizeChargeAmount(value)
		end
	end
end

local function getOutstandingBreakdown(billingState: BillingState.BillingState): OutstandingBreakdown
	local save = billingState.Save
	local raw = save.OutstandingBreakdown
	if typeof(raw) ~= "table" then
		local newBreakdown = createEmptyBreakdown()
		save.OutstandingBreakdown = newBreakdown
		return newBreakdown
	end

	local breakdown = raw :: OutstandingBreakdown
	sanitizeBreakdown(breakdown)
	save.OutstandingBreakdown = breakdown
	return breakdown
end

local function clearOutstandingBreakdown(breakdown: OutstandingBreakdown)
	for _, key in CATEGORY_KEYS do
		breakdown[key] = 0
	end
end

local function addIntoBreakdown(target: OutstandingBreakdown, addition: OutstandingBreakdown)
	for _, key in CATEGORY_KEYS do
		local value = addition[key]
		if value > 0 then
			target[key] += value
		end
	end
end

local function applyOutstandingDeduction(breakdown: OutstandingBreakdown, amountPaid: number)
	local remaining = sanitizeChargeAmount(amountPaid)
	if remaining <= 0 then
		return
	end
	for _, key in CATEGORY_KEYS do
		if remaining <= 0 then
			break
		end
		local owed = breakdown[key]
		if owed > 0 then
			local reduction = math.min(owed, remaining)
			breakdown[key] = owed - reduction
			remaining -= reduction
		end
	end
end

local function getFoodUsageBucket(player: Player): FoodUsageBucket
	local bucket = PlayerFoodUsage[player.UserId]
	if bucket == nil then
		bucket = {
			Current = 0,
			Pending = 0,
			LastBilledCost = 0,
		}
		PlayerFoodUsage[player.UserId] = bucket
	end
	return bucket
end

local function getCurrentFoodCost(player: Player, includePending: boolean?): number
	local bucket = PlayerFoodUsage[player.UserId]
	if not bucket then
		return 0
	end
	local totalUsage = bucket.Current
	if includePending then
		totalUsage += bucket.Pending
	end
	local cost = BillingCalculator.CalculateFoodCost(totalUsage)
	if typeof(cost) ~= "number" or cost ~= cost then
		return 0
	end
	return cost
end

local function computeCurrentCycleCharges(
	player: Player,
	plotStateData: any?,
	includePending: boolean?
): OutstandingBreakdown
	local charges = createEmptyBreakdown()
	local resolvedPlotState = plotStateData
	if resolvedPlotState == nil then
		resolvedPlotState = PlayerSession.GetData(player, "PlotState")
	end

	if typeof(resolvedPlotState) ~= "table" then
		charges.PlotTax = BASE_CYCLE_CHARGE
		charges.Food = sanitizeChargeAmount(getCurrentFoodCost(player, includePending))
		return charges
	end

	charges.PlotTax = sanitizeChargeAmount(BillingCalculator.CalculatePlotTax(resolvedPlotState))
	charges.Electric = sanitizeChargeAmount(BillingCalculator.CalculateElectricityCost(resolvedPlotState))
	charges.Food = sanitizeChargeAmount(getCurrentFoodCost(player, includePending))
	return charges
end

local function finalizeCurrentFoodUsage(player: Player)
	local bucket = PlayerFoodUsage[player.UserId]
	if not bucket then
		return
	end
	local billedCost = BillingCalculator.CalculateFoodCost(bucket.Current)
	bucket.LastBilledCost = billedCost
	bucket.Current = 0
end

local function finalizePendingFoodUsage(player: Player)
	local bucket = PlayerFoodUsage[player.UserId]
	if not bucket then
		return
	end
	-- Move pending to current and finalize it
	if bucket.Pending > 0 then
		bucket.Current += bucket.Pending
		bucket.Pending = 0
	end
	local billedCost = BillingCalculator.CalculateFoodCost(bucket.Current)
	bucket.LastBilledCost = billedCost
	bucket.Current = 0
end

local function rollPendingFoodUsage(player: Player)
	local bucket = PlayerFoodUsage[player.UserId]
	if not bucket then
		return
	end
	if bucket.Pending > 0 then
		bucket.Current += bucket.Pending
		bucket.Pending = 0
	end
	bucket.LastBilledCost = 0
end

local function resetFoodUsage(player: Player)
	PlayerFoodUsage[player.UserId] = nil
end

local function ensureCurrencyState(player: Player, currencyStateData: CurrencyStateData)
	if typeof(currencyStateData.Cash) ~= "number" or currencyStateData.Cash < 0 then
		currencyStateData.Cash = 0
		player:SetAttribute("Cash", 0)
	end
	if typeof(currencyStateData.OutstandingBalance) ~= "number" or currencyStateData.OutstandingBalance < 0 then
		currencyStateData.OutstandingBalance = 0
		player:SetAttribute("OutstandingBalance", 0)
	end
end

local function getCurrencyState(player: Player): CurrencyStateData?
	local currencyData = PlayerSession.GetData(player, "CurrencyState")
	if typeof(currencyData) ~= "table" then
		return nil
	end
	ensureCurrencyState(player, currencyData :: CurrencyStateData)
	return currencyData :: CurrencyStateData
end

function BillingService.UpdateOutstandingBalance(
	player: Player,
	currencyStateData: CurrencyStateData,
	amount: number,
	billingState: BillingState.BillingState?
)
	local sanitizedAmount = sanitizeChargeAmount(amount)
	local resolvedBillingState = billingState or BillingService.GetBillingState(player)

	if resolvedBillingState then
		local breakdown = getOutstandingBreakdown(resolvedBillingState)
		local breakdownTotal = sumBreakdownAmounts(breakdown)

		if sanitizedAmount <= 0 then
			if breakdownTotal > 0 then
				clearOutstandingBreakdown(breakdown)
			end
			sanitizedAmount = 0
		else
			if breakdownTotal <= 0 then
				clearOutstandingBreakdown(breakdown)
				breakdown.Food = sanitizedAmount
			elseif breakdownTotal ~= sanitizedAmount then
				if breakdownTotal > sanitizedAmount then
					applyOutstandingDeduction(breakdown, breakdownTotal - sanitizedAmount)
				else
					breakdown.Food += sanitizedAmount - breakdownTotal
				end
			end
			sanitizedAmount = sumBreakdownAmounts(breakdown)
		end
	end

	if currencyStateData.OutstandingBalance ~= sanitizedAmount then
		CurrencyService.Set(player, "OutstandingBalance", sanitizedAmount, currencyStateData)
	else
		currencyStateData.OutstandingBalance = sanitizedAmount
	end
end

function BillingService.GetOutstandingBalance(currencyStateData: CurrencyStateData): number
	local outstanding = currencyStateData.OutstandingBalance
	if typeof(outstanding) ~= "number" or outstanding < 0 then
		outstanding = 0
	end
	return sanitizeChargeAmount(outstanding)
end

function BillingService.RecordMealUsage(player: Player, usageWeight: number?)
	if not player then
		return
	end
	local increment = usageWeight
	if typeof(increment) ~= "number" or increment ~= increment or increment <= 0 then
		increment = 1
	end
	local incrementValue = math.max(increment :: number, 0)
	if incrementValue <= 0 then
		return
	end
	local bucket = getFoodUsageBucket(player)
	local billingState = BillingService.GetBillingState(player)
	local isInGraceOrOverdue = billingState and (billingState:IsInGrace() or billingState:IsOverdue())

	if isInGraceOrOverdue then
		bucket.Pending += incrementValue
		-- Immediately broadcast billing update so UI reflects the new pending food charges
		if billingState then
			broadcastBillingUpdate(player, billingState)
		end
	else
		bucket.Current += incrementValue
	end
end

function BillingService.GetBaseCharge(player: Player): number
	local charges = computeCurrentCycleCharges(player, nil)
	return charges.PlotTax + charges.Electric + charges.Food
end

function BillingService.CalculateCycleCharge(player: Player, _currencyStateData: CurrencyStateData): number
	local charges = computeCurrentCycleCharges(player, nil)
	local baseCharge = sanitizeChargeAmount(charges.PlotTax + charges.Electric + charges.Food)
	local billingState = BillingService.GetBillingState(player)
	local outstandingTotal = 0
	if billingState then
		outstandingTotal = sumBreakdownAmounts(getOutstandingBreakdown(billingState))
	end
	return baseCharge + outstandingTotal
end

broadcastBillingUpdate = function(player: Player, billingState: BillingState.BillingState)
	local breakdown = BillingService.GetBillingBreakdown(player)
	local timeRemaining = billingState:GetTimeRemaining()
	local dueClockTime = resolveDueClockTime(billingState)

	-- Ensure values are valid numbers for packet transmission
	if typeof(timeRemaining) ~= "number" then
		timeRemaining = 0
	end
	if typeof(dueClockTime) ~= "number" then
		dueClockTime = 0
	end

	BillingPackets.BillingBreakdownUpdate:FireClient(player, {
		PlotTax = breakdown.PlotTax,
		Electric = breakdown.Electric,
		Food = breakdown.Food,
		OutstandingTotal = breakdown.OutstandingTotal,
		Total = breakdown.Total,
		DueClockTime = dueClockTime,
		TimeRemaining = timeRemaining,
	})
end

local function applyGraceState(player: Player, billingState: BillingState.BillingState)
	if player:GetAttribute("BillingGraceActive") == true then
		return
	end
	player:SetAttribute("BillingGraceActive", true)
	BillingService.OnGraceActivated(player, billingState)
end

local function clearGraceState(player: Player, billingState: BillingState.BillingState)
	if player:GetAttribute("BillingGraceActive") ~= true then
		return
	end
	player:SetAttribute("BillingGraceActive", false)
	BillingService.OnGraceCleared(player, billingState)
end

local function applyOverdueState(
	player: Player,
	billingState: BillingState.BillingState,
	overdueCount: number,
	isNewState: boolean
)
	player:SetAttribute("BillingOverdueActive", true)
	player:SetAttribute("BillingOverdueCount", overdueCount)
	if isNewState then
		BillingService.OnOverdueTriggered(player, billingState, overdueCount)
	end
end

local function clearOverdueState(player: Player, billingState: BillingState.BillingState)
	if player:GetAttribute("BillingOverdueActive") ~= true then
		return
	end
	player:SetAttribute("BillingOverdueActive", false)
	BillingService.OnOverdueCleared(player, billingState)
end

function BillingService.AttemptCharge(player: Player, currencyStateData: CurrencyStateData, amountDue: number): boolean
	local billingState = BillingService.GetBillingState(player)
	local sanitizedAmount = sanitizeChargeAmount(amountDue)
	if sanitizedAmount <= 0 then
		BillingService.UpdateOutstandingBalance(player, currencyStateData, 0, billingState)
		return true
	end

	local availableCash = currencyStateData.Cash
	if availableCash <= 0 then
		BillingService.UpdateOutstandingBalance(player, currencyStateData, sanitizedAmount, billingState)
		return false
	end

	local outstandingBreakdown = nil
	if billingState then
		outstandingBreakdown = getOutstandingBreakdown(billingState)
	end
	local deductedAmount = math.min(availableCash, sanitizedAmount)
	if deductedAmount > 0 then
		if outstandingBreakdown then
			applyOutstandingDeduction(outstandingBreakdown, deductedAmount)
		end
		CurrencyService.Remove(player, "Cash", deductedAmount, currencyStateData)
	end

	local remainingOutstanding
	if outstandingBreakdown then
		remainingOutstanding = sumBreakdownAmounts(outstandingBreakdown)
	else
		remainingOutstanding = sanitizedAmount - deductedAmount
	end
	BillingService.UpdateOutstandingBalance(player, currencyStateData, remainingOutstanding, billingState)
	return remainingOutstanding == 0
end

function BillingService.CompleteCycle(
	player: Player,
	billingState: BillingState.BillingState,
	currencyStateData: CurrencyStateData
)
	billingState:ResetCycle()
	BillingService.UpdateOutstandingBalance(player, currencyStateData, 0, billingState)
	rollPendingFoodUsage(player)
	clearGraceState(player, billingState)
	clearOverdueState(player, billingState)
end

function BillingService.ProcessDue(
	player: Player,
	billingState: BillingState.BillingState,
	currencyStateData: CurrencyStateData
)
	local plotStateData = PlayerSession.GetData(player, "PlotState")
	local currentCharges = computeCurrentCycleCharges(player, plotStateData)
	local outstandingBreakdown = getOutstandingBreakdown(billingState)
	addIntoBreakdown(outstandingBreakdown, currentCharges)

	local totalDue = sumBreakdownAmounts(outstandingBreakdown)
	local normalizedTotal = sanitizeChargeAmount(totalDue)

	if normalizedTotal <= 0 then
		BillingService.CompleteCycle(player, billingState, currencyStateData)
		broadcastBillingUpdate(player, billingState)
		return
	end

	BillingService.UpdateOutstandingBalance(player, currencyStateData, normalizedTotal, billingState)
	finalizeCurrentFoodUsage(player)
	broadcastBillingUpdate(player, billingState)

	billingState:EnterGrace()
	applyGraceState(player, billingState)
end

function BillingService.ProcessGrace(
	player: Player,
	billingState: BillingState.BillingState,
	currencyStateData: CurrencyStateData
)
	local outstandingDue = BillingService.GetOutstandingBalance(currencyStateData)
	if outstandingDue <= 0 then
		BillingService.CompleteCycle(player, billingState, currencyStateData)
		broadcastBillingUpdate(player, billingState)
		return
	end

	if billingState:IsGraceExpired() then
		local enteredOverdue = billingState:EnterOverdue()
		if enteredOverdue then
			local overdueCount = billingState:IncrementOverdueCount()
			applyOverdueState(player, billingState, overdueCount, true)
			-- Broadcast overdue state change
			broadcastBillingUpdate(player, billingState)
		else
			applyOverdueState(player, billingState, billingState:GetOverdueCount(), false)
		end
		clearGraceState(player, billingState)
		return
	end
end

function BillingService.ProcessOverdue(
	player: Player,
	billingState: BillingState.BillingState,
	currencyStateData: CurrencyStateData
)
	local outstandingDue = BillingService.GetOutstandingBalance(currencyStateData)
	if outstandingDue <= 0 then
		BillingService.CompleteCycle(player, billingState, currencyStateData)
		broadcastBillingUpdate(player, billingState)
		return
	end
end

function BillingService.PayBill(player: Player): (boolean, string)
	local billingState = BillingService.GetBillingState(player)
	if not billingState then
		return false, "Billing is not ready."
	end

	local currencyStateData = getCurrencyState(player)
	if not currencyStateData then
		return false, "Currency data unavailable."
	end

	local breakdown = BillingService.GetBillingBreakdown(player)
	local totalDue = breakdown.Total

	if totalDue <= 0 then
		return false, "No bill to pay."
	end

	local availableCash = currencyStateData.Cash
	if availableCash < totalDue then
		local shortfall = totalDue - availableCash
		return false, string.format("Need $%d more cash.", shortfall)
	end

	-- Finalize all food usage including pending when paying during grace/overdue
	if billingState:IsInGrace() or billingState:IsOverdue() then
		finalizePendingFoodUsage(player)
	else
		finalizeCurrentFoodUsage(player)
	end

	CurrencyService.Remove(player, "Cash", totalDue, currencyStateData)
	BillingService.CompleteCycle(player, billingState, currencyStateData)
	broadcastBillingUpdate(player, billingState)
	return true, "Bill paid in full."
end

function BillingService.OnGraceActivated(_player: Player, _billingState: BillingState.BillingState) end

function BillingService.OnGraceCleared(_player: Player, _billingState: BillingState.BillingState) end

function BillingService.OnOverdueTriggered(
	_player: Player,
	_billingState: BillingState.BillingState,
	_overdueCount: number
)
end

function BillingService.OnOverdueCleared(_player: Player, _billingState: BillingState.BillingState) end

local function ensureBillingState(player: Player)
	local playerIdentifier = player.UserId
	if PlayerBillingStates[playerIdentifier] then
		return
	end

	local billingStateData = PlayerSession.GetDataAwait(player, "BillingState")
	local billingState = BillingState.new(BILLING_DURATION_SECONDS, BILLING_GRACE_PERIOD_SECONDS, billingStateData)
	PlayerBillingStates[playerIdentifier] = billingState

	local currencyStateData = PlayerSession.GetDataAwait(player, "CurrencyState")
	if typeof(currencyStateData) == "table" then
		ensureCurrencyState(player, currencyStateData :: CurrencyStateData)
		BillingService.UpdateOutstandingBalance(
			player,
			currencyStateData :: CurrencyStateData,
			(currencyStateData :: CurrencyStateData).OutstandingBalance,
			billingState
		)
	end

	if billingState:IsInGrace() then
		applyGraceState(player, billingState)
	elseif billingState:IsOverdue() then
		local overdueCount = billingState:GetOverdueCount()
		applyOverdueState(player, billingState, overdueCount, false)
	else
		clearGraceState(player, billingState)
		clearOverdueState(player, billingState)
	end
end

function BillingService.Init()
	PlotService.PlotClaimed:Connect(function(player: Player, _plotState)
		ensureBillingState(player)
	end)

	PlotService.PlotUnclaimed:Connect(function(player: Player, _plotIndex)
		BillingService.Remove(player)
	end)

	BillingPackets.RequestBillingInfo.OnServerInvoke = function(player: Player)
		local breakdown = BillingService.GetBillingBreakdown(player)
		local billingState = BillingService.GetBillingState(player)
		local timeRemaining = 0
		local dueClockTime = 0
		if billingState then
			timeRemaining = billingState:GetTimeRemaining()
			dueClockTime = resolveDueClockTime(billingState)
		end

		-- Ensure values are valid numbers for packet transmission
		if typeof(timeRemaining) ~= "number" then
			timeRemaining = 0
		end
		if typeof(dueClockTime) ~= "number" then
			dueClockTime = 0
		end

		return {
			PlotTax = breakdown.PlotTax,
			Electric = breakdown.Electric,
			Food = breakdown.Food,
			OutstandingTotal = breakdown.OutstandingTotal,
			Total = breakdown.Total,
			DueClockTime = dueClockTime,
			TimeRemaining = timeRemaining,
		}
	end

	BillingPackets.PayBillRequest.OnServerInvoke = function(player: Player)
		local success, message = BillingService.PayBill(player)
		return success, message or ""
	end
	Players.PlayerRemoving:Connect(function(player: Player)
		BillingService.Remove(player)
	end)

	for _, player in ipairs(Players:GetPlayers()) do
		if player:GetAttribute("OwnedPlotIndex") ~= nil then
			ensureBillingState(player)
		end
	end

	BillingService.Start()
end

function BillingService.Start()
	if WorldUpdate.IsSubscribed("BillingService") then
		return
	end
	WorldUpdate.Subscribe("BillingService", CHECK_INTERVAL_SECONDS, function(deltaSeconds: number)
		BillingService.UpdateBilling(deltaSeconds)
	end)
end

function BillingService.UpdateBilling(deltaSeconds: number)
	for playerIdentifier, billingState in pairs(PlayerBillingStates) do
		local player = Players:GetPlayerByUserId(playerIdentifier)
		if player == nil then
			continue
		end

		local currencyStateData = getCurrencyState(player)
		if not currencyStateData then
			continue
		end

		billingState:Update(deltaSeconds)

		if billingState:IsInGrace() then
			BillingService.ProcessGrace(player, billingState, currencyStateData)
		elseif billingState:IsOverdue() then
			BillingService.ProcessOverdue(player, billingState, currencyStateData)
		elseif billingState:IsDue() then
			BillingService.ProcessDue(player, billingState, currencyStateData)
		end
	end
end

function BillingService.GetBillingState(player: Player): BillingState.BillingState?
	return PlayerBillingStates[player.UserId]
end

function BillingService.GetBillingBreakdown(player: Player): {
	PlotTax: number,
	Electric: number,
	Food: number,
	Total: number,
	OutstandingTotal: number,
}
	local plotStateData = PlayerSession.GetData(player, "PlotState")
	local billingState = BillingService.GetBillingState(player)
	local currencyStateData = getCurrencyState(player)

	local outstandingBreakdown = if billingState then getOutstandingBreakdown(billingState) else createEmptyBreakdown()

	if not billingState and currencyStateData then
		local outstandingBalance = BillingService.GetOutstandingBalance(currencyStateData)
		if outstandingBalance > 0 then
			outstandingBreakdown.Food = outstandingBalance
		end
	end
	local outstandingTotal = sumBreakdownAmounts(outstandingBreakdown)

	-- Include pending food charges if in grace or overdue
	local includePendingFood = billingState and (billingState:IsInGrace() or billingState:IsOverdue())
	local currentCharges = computeCurrentCycleCharges(player, plotStateData, includePendingFood)
	local includeCurrentCycle = outstandingTotal <= 0

	local plotTotal = sanitizeChargeAmount(outstandingBreakdown.PlotTax)
	local electricTotal = sanitizeChargeAmount(outstandingBreakdown.Electric)
	local foodTotal = sanitizeChargeAmount(outstandingBreakdown.Food)

	if includeCurrentCycle then
		plotTotal += sanitizeChargeAmount(currentCharges.PlotTax)
		electricTotal += sanitizeChargeAmount(currentCharges.Electric)
		foodTotal += sanitizeChargeAmount(currentCharges.Food)
	else
		-- When bill is outstanding, add pending food costs to the outstanding food total
		if includePendingFood then
			local pendingFoodCost = sanitizeChargeAmount(currentCharges.Food)
			foodTotal += pendingFoodCost
		end
	end

	local totalDue = plotTotal + electricTotal + foodTotal

	return {
		PlotTax = plotTotal,
		Electric = electricTotal,
		Food = foodTotal,
		Total = totalDue,
		OutstandingTotal = sanitizeChargeAmount(outstandingTotal),
	}
end

function BillingService.Remove(player: Player)
	local billingState = PlayerBillingStates[player.UserId]
	if not billingState then
		return
	end
	clearGraceState(player, billingState)
	clearOverdueState(player, billingState)
	PlayerBillingStates[player.UserId] = nil
	resetFoodUsage(player)
end

return BillingService
