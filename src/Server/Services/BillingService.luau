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
local ResidentService = require(script.Parent.ResidentService)
local BillingState = require(ServerScriptService.Server.Classes.BillingState)
local WorldUpdate = require(ServerScriptService.Server.Utilities.WorldUpdate)
local BillingCalculator = require(ServerScriptService.Server.Utilities.BillingCalculator)
local EnergyUsageTracker = require(ServerScriptService.Server.Utilities.EnergyUsageTracker)
local BillingConstants = require(ReplicatedStorage.Shared.Definitions.BillingConstants)
local ItemFinder = require(ReplicatedStorage.Shared.Utilities.ItemFinder)
local TimeScale = require(ReplicatedStorage.Shared.Utilities.TimeScale)
local StationManager = require(ServerScriptService.Server.Services.ResidentAutonomyService.StationManager)

type OutstandingBreakdown = {
	PlotTax: number,
	Electric: number,
	Interest: number,
}

type CurrencyStateData = {
	Cash: number,
	OutstandingBalance: number,
	[string]: number,
}

local BILLING_DURATION_SECONDS = math.max(1, BillingConstants.BillingCycleDurationSeconds or 1440)
local BILLING_GRACE_PERIOD_SECONDS = 10
local EARLY_PAYMENT_WINDOW_SECONDS =
	math.clamp(BillingConstants.EarlyPaymentWindowSeconds or 480, 0, BILLING_DURATION_SECONDS)
local CHECK_INTERVAL_SECONDS = 2
local BASE_CYCLE_CHARGE = 100
local POWER_OUTAGE_OVERRIDE = BillingConstants.PowerOutageOverrideKey or "BillingPowerOutage"
local EARLY_PAYMENT_WINDOW_HOURS =
	math.max(1, math.floor(TimeScale.GameHoursFromRealDelta(EARLY_PAYMENT_WINDOW_SECONDS) + 0.5))

local CATEGORY_KEYS = { "PlotTax", "Electric" }
local OUTSTANDING_KEYS = { "PlotTax", "Electric", "Interest" }

local rawInterestRate = BillingConstants.OverdueInterestRate
local OVERDUE_INTEREST_RATE = if typeof(rawInterestRate) == "number" then math.max(0, rawInterestRate) else 0.1

local rawMinimumInterest = BillingConstants.MinimumOverdueInterest
local MINIMUM_OVERDUE_INTEREST = if typeof(rawMinimumInterest) == "number"
	then math.max(0, math.round(rawMinimumInterest))
	else 25

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

local energyStationCache: { [string]: boolean } = {}

local function isEnergyConsumingStationId(itemId: string?): boolean
	if typeof(itemId) ~= "string" or itemId == "" then
		return false
	end

	local cached = energyStationCache[itemId]
	if cached ~= nil then
		return cached
	end

	local itemSpec = ItemFinder.FindItemById(itemId)
	local result = false
	if itemSpec then
		local energyPerHour = itemSpec.EnergyConsumptionPerHour
		if typeof(energyPerHour) == "number" and energyPerHour > 0 then
			result = true
		end
	end

	energyStationCache[itemId] = result
	return result
end

local function enforcePowerOutage(player: Player)
	local stationCache = PlotService.GetStationsForPlayer(player)
	for _, stationScope in pairs(stationCache) do
		for _, station in pairs(stationScope) do
			if isEnergyConsumingStationId(station.Id) then
				local occupants: { string } = {}
				if typeof(station.Residents) == "table" then
					for _, residentName in ipairs(station.Residents) do
						if typeof(residentName) == "string" and residentName ~= "" then
							occupants[#occupants + 1] = residentName
						end
					end
				end

				for _, residentName in ipairs(occupants) do
					StationManager.releaseStationOccupancy(station, residentName)
					local residentState = ResidentService.GetResident(player, residentName)
					if residentState then
						local cancelAction = residentState.CancelCurrentAction
						if typeof(cancelAction) == "function" then
							cancelAction(residentState, "PowerOutage")
						end
						local clearOverride = residentState.ClearManualOverrideState
						if typeof(clearOverride) == "function" then
							clearOverride(residentState)
						end
						local enableAutomation = residentState.EnableAutomation
						if typeof(enableAutomation) == "function" then
							enableAutomation(residentState)
						end
					end
				end

				station.ActiveOverride = POWER_OUTAGE_OVERRIDE
			end
		end
	end
end

local function clearPowerOutage(player: Player)
	local stationCache = PlotService.GetStationsForPlayer(player)
	for _, stationScope in pairs(stationCache) do
		for _, station in pairs(stationScope) do
			if station.ActiveOverride == POWER_OUTAGE_OVERRIDE then
				station.ActiveOverride = nil
			end
		end
	end
end

local broadcastBillingUpdate: (player: Player, billingState: BillingState.BillingState) -> ()

local function createEmptyBreakdown(): OutstandingBreakdown
	return {
		PlotTax = 0,
		Electric = 0,
		Interest = 0,
	}
end

local function sumBreakdownAmounts(breakdown: OutstandingBreakdown): number
	return breakdown.PlotTax + breakdown.Electric + breakdown.Interest
end

local function sanitizeBreakdown(breakdown: OutstandingBreakdown)
	for _, key in OUTSTANDING_KEYS do
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
	for _, key in OUTSTANDING_KEYS do
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
	for _, key in OUTSTANDING_KEYS do
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

local function computeOverdueInterestAmount(outstandingDue: number): number
	local sanitizedOutstanding = sanitizeChargeAmount(outstandingDue)
	if sanitizedOutstanding <= 0 then
		return 0
	end

	local interestFromRate = math.round(sanitizedOutstanding * OVERDUE_INTEREST_RATE)
	local resolvedMinimum = MINIMUM_OVERDUE_INTEREST
	local interest = interestFromRate
	if interest < resolvedMinimum then
		interest = resolvedMinimum
	end
	return sanitizeChargeAmount(interest)
end

local function applyOverdueInterestCharge(
	player: Player,
	billingState: BillingState.BillingState,
	currencyStateData: CurrencyStateData
): number
	local breakdown = getOutstandingBreakdown(billingState)
	local outstandingBefore = sumBreakdownAmounts(breakdown)
	local interest = computeOverdueInterestAmount(outstandingBefore)
	if interest <= 0 then
		return 0
	end

	breakdown.Interest += interest
	local updatedOutstanding = sumBreakdownAmounts(breakdown)
	BillingService.UpdateOutstandingBalance(player, currencyStateData, updatedOutstanding, billingState)
	return interest
end

local function computeCurrentCycleCharges(player: Player, plotStateData: any?): OutstandingBreakdown
	local charges = createEmptyBreakdown()
	local resolvedPlotState = plotStateData
	if resolvedPlotState == nil then
		resolvedPlotState = PlayerSession.GetData(player, "PlotState")
	end

	if typeof(resolvedPlotState) ~= "table" then
		charges.PlotTax = BASE_CYCLE_CHARGE
	else
		charges.PlotTax = sanitizeChargeAmount(BillingCalculator.CalculatePlotTax(resolvedPlotState))
	end

	return charges
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
				breakdown.PlotTax = sanitizedAmount
			elseif breakdownTotal ~= sanitizedAmount then
				if breakdownTotal > sanitizedAmount then
					applyOutstandingDeduction(breakdown, breakdownTotal - sanitizedAmount)
				else
					breakdown.PlotTax += sanitizedAmount - breakdownTotal
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

function BillingService.GetBaseCharge(player: Player): number
	local charges = computeCurrentCycleCharges(player, nil)
	return charges.PlotTax + charges.Electric
end

function BillingService.CalculateCycleCharge(player: Player, _currencyStateData: CurrencyStateData): number
	local plotStateData = PlayerSession.GetData(player, "PlotState")
	local charges = computeCurrentCycleCharges(player, plotStateData)
	if typeof(plotStateData) == "table" then
		charges.Electric = sanitizeChargeAmount(BillingCalculator.EstimateCycleElectricCost(plotStateData))
	end
	local baseCharge = sanitizeChargeAmount(charges.PlotTax + charges.Electric)
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
		Overdue = breakdown.Overdue,
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
	if player:GetAttribute("BillingOverdueActive") == true then
		EnergyUsageTracker.SetOutage(player, true)
		player:SetAttribute("BillingPowerOutageActive", true)
		enforcePowerOutage(player)
		return
	end

	EnergyUsageTracker.SetOutage(player, true)
	player:SetAttribute("BillingOverdueActive", true)
	player:SetAttribute("BillingOverdueCount", overdueCount)
	player:SetAttribute("BillingPowerOutageActive", true)
	enforcePowerOutage(player)
	if isNewState then
		BillingService.OnOverdueTriggered(player, billingState, overdueCount)
	end
end

local function clearOverdueState(player: Player, billingState: BillingState.BillingState)
	player:SetAttribute("BillingPowerOutageActive", false)
	clearPowerOutage(player)
	if player:GetAttribute("BillingOverdueActive") ~= true then
		return
	end
	player:SetAttribute("BillingOverdueActive", false)
	EnergyUsageTracker.SetOutage(player, false)
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
	EnergyUsageTracker.ResetAccumulated(player)
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

	local consumedEnergy = EnergyUsageTracker.CollectUsage(player)
	local electricCost = BillingCalculator.CalculateElectricityCostFromUsage(consumedEnergy)
	if electricCost <= 0 then
		local baseLoad = EnergyUsageTracker.GetBaseLoad(player)
		local activeLoad = EnergyUsageTracker.GetActiveLoad(player)
		if baseLoad > 0 and activeLoad > 0 and typeof(plotStateData) == "table" then
			electricCost = BillingCalculator.EstimateCycleElectricCost(plotStateData)
		end
	end
	currentCharges.Electric = sanitizeChargeAmount(electricCost)

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
			local _interestApplied = applyOverdueInterestCharge(player, billingState, currencyStateData)
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

	local isInGrace = billingState:IsInGrace()
	local isOverdue = billingState:IsOverdue()
	if not isInGrace and not isOverdue then
		local timeRemaining = billingState:GetTimeRemaining()
		local resolvedTimeRemaining = if typeof(timeRemaining) == "number" then timeRemaining else 0
		if resolvedTimeRemaining > EARLY_PAYMENT_WINDOW_SECONDS then
			return false,
				string.format(
					"Bill can only be paid within %d in-game hours of the deadline.",
					EARLY_PAYMENT_WINDOW_HOURS
				)
		end
	end

	local availableCash = currencyStateData.Cash
	if availableCash < totalDue then
		local shortfall = totalDue - availableCash
		return false, string.format("Need $%d more cash.", shortfall)
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
			Overdue = breakdown.Overdue,
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
	Overdue: number,
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
			outstandingBreakdown.PlotTax = outstandingBalance
		end
	end

	local outstandingTotal = sumBreakdownAmounts(outstandingBreakdown)
	local currentCharges = computeCurrentCycleCharges(player, plotStateData)

	if typeof(plotStateData) == "table" then
		currentCharges.Electric = sanitizeChargeAmount(BillingCalculator.EstimateCycleElectricCost(plotStateData))
	else
		currentCharges.Electric = 0
	end

	local includeCurrentCycle = outstandingTotal <= 0

	local plotTotal = sanitizeChargeAmount(outstandingBreakdown.PlotTax)
	local electricTotal = sanitizeChargeAmount(outstandingBreakdown.Electric)
	local interestTotal = sanitizeChargeAmount(outstandingBreakdown.Interest)

	if includeCurrentCycle then
		plotTotal += sanitizeChargeAmount(currentCharges.PlotTax)
		electricTotal += sanitizeChargeAmount(currentCharges.Electric)
	end

	local totalDue = plotTotal + electricTotal + interestTotal

	return {
		PlotTax = plotTotal,
		Electric = electricTotal,
		Overdue = interestTotal,
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
	EnergyUsageTracker.RemovePlayer(player)
end

return BillingService
