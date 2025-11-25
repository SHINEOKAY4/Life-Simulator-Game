--!strict
-- Billing service - manages billing cycles and calculations

local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local BillingState = require(ServerScriptService.Server.Classes.BillingState)
local BillingCalculator = require(ServerScriptService.Server.Utilities.BillingCalculator)
local BillingConstants = require(ReplicatedStorage.Shared.Definitions.BillingConstants)
local BillingPackets = require(ReplicatedStorage.Network.BillingPackets)
local PlayerSession = require(script.Parent.PlayerSession)
local PlotService = require(script.Parent.PlotService)
local CurrencyService = require(script.Parent.CurrencyService)
local ResidentService = require(script.Parent.ResidentService)
local EnergyUsageTracker = require(ServerScriptService.Server.Utilities.EnergyUsageTracker)
local WorldUpdate = require(ServerScriptService.Server.Utilities.WorldUpdate)

local BillingService = {}

-- Active billing states per player
local PlayerStates: { [number]: BillingState.BillingState } = {}

-- Update player attributes with current bill breakdown
local function updatePlayerAttributes(
	player: Player,
	breakdown: {
		PropertyTax: number,
		Electricity: number,
		Water: number,
		Internet: number,
		Total: number,
	}
)
	player:SetAttribute(BillingConstants.PropertyTaxAttribute, breakdown.PropertyTax)
	player:SetAttribute(BillingConstants.ElectricityAttribute, breakdown.Electricity)
	player:SetAttribute(BillingConstants.WaterAttribute, breakdown.Water)
	player:SetAttribute(BillingConstants.InternetAttribute, breakdown.Internet)
	player:SetAttribute(BillingConstants.TotalBillAttribute, breakdown.Total)
end

-- Calculate current bill for a player
local function calculateBill(player: Player): {
	PropertyTax: number,
	Electricity: number,
	Water: number,
	Internet: number,
	Total: number,
}
	local billingState = PlayerStates[player.UserId]
	if not billingState then
		return { PropertyTax = 0, Electricity = 0, Water = 0, Internet = 0, Total = 0 }
	end

	-- Get plot data
	local plotState = PlotService.GetState(player)
	if not plotState then
		return { PropertyTax = 0, Electricity = 0, Water = 0, Internet = 0, Total = 0 }
	end

	-- Count occupied cells for property tax
	local occupiedCells = 0
	for _ in pairs(plotState.Save.PlacedObjects) do
		occupiedCells += 1
	end

	-- Calculate property tax
	local propertyTax = BillingCalculator.CalculatePropertyTax(occupiedCells)

	-- Calculate electricity from energy tracker
	local energyConsumedKWh = EnergyUsageTracker.CollectUsage(player)
	local electricity = BillingCalculator.CalculateElectricity(energyConsumedKWh)

	-- Calculate water based on resident count
	local residents = ResidentService.GetResidents(player)
	local residentCount = residents and #residents or 0
	local water = BillingCalculator.CalculateWater(residentCount)

	-- Calculate internet
	local internet = BillingCalculator.CalculateInternet(billingState.Save.InternetTier)

	local total = propertyTax + electricity + water + internet

	return {
		PropertyTax = propertyTax,
		Electricity = electricity,
		Water = water,
		Internet = internet,
		Total = total,
	}
end

-- Process billing cycle for a player
local function processBillingCycle(player: Player)
	local billingState = PlayerStates[player.UserId]
	if not billingState then
		return
	end

	local elapsed = billingState:GetElapsedSeconds()
	if elapsed < BillingConstants.CycleDurationSeconds then
		return
	end

	-- Calculate final bill
	local breakdown = calculateBill(player)

	-- Update current cycle data
	billingState.Save.CurrentCycle = {
		PropertyTax = breakdown.PropertyTax,
		Electricity = breakdown.Electricity,
		Water = breakdown.Water,
		Internet = breakdown.Internet,
	}

	-- Mark bill as due and track unpaid time
	billingState:MarkUnpaid()
	player:SetAttribute(BillingConstants.BillDueAttribute, true)
	updatePlayerAttributes(player, breakdown)

	print(string.format("[BillingService] Bill due for %s: $%.2f", player.Name, breakdown.Total))
end

-- Check if grace period has expired and enforce consequences
local function enforceConsequences(player: Player)
	local billingState = PlayerStates[player.UserId]
	if not billingState then
		return
	end

	-- Only enforce if bill is due
	if player:GetAttribute(BillingConstants.BillDueAttribute) ~= true then
		-- Bill is paid, ensure outage is cleared
		if player:GetAttribute(BillingConstants.PowerOutageAttribute) == true then
			player:SetAttribute(BillingConstants.PowerOutageAttribute, false)
			print(string.format("[BillingService] Power restored for %s", player.Name))
		end
		return
	end

	-- Check if grace period has expired
	if billingState:IsGracePeriodExpired(BillingConstants.GracePeriodSeconds) then
		-- Activate power outage
		if player:GetAttribute(BillingConstants.PowerOutageAttribute) ~= true then
			player:SetAttribute(BillingConstants.PowerOutageAttribute, true)
			local unpaidDuration = billingState:GetUnpaidDuration()
			print(
				string.format(
					"[BillingService] Power outage activated for %s (unpaid for %d seconds)",
					player.Name,
					unpaidDuration
				)
			)
		end
	else
		-- Still in grace period, ensure outage is not active
		if player:GetAttribute(BillingConstants.PowerOutageAttribute) == true then
			player:SetAttribute(BillingConstants.PowerOutageAttribute, false)
		end
	end
end

function BillingService.Init()
	-- Listen for payment requests
	BillingPackets.PayBill.OnServerInvoke = function(player: Player)
		return BillingService.PayBill(player)
	end

	-- Subscribe to world update for periodic checks
	WorldUpdate.Subscribe("BillingCycle", BillingConstants.CycleDurationSeconds / 4, function()
		for _, player in Players:GetPlayers() do
			if PlayerStates[player.UserId] then
				processBillingCycle(player)
			end
		end
	end)

	-- Periodic enforcement checks
	WorldUpdate.Subscribe("BillingEnforcement", 10, function()
		for _, player in Players:GetPlayers() do
			if PlayerStates[player.UserId] then
				enforceConsequences(player)
			end
		end
	end)

	print("[BillingService] Initialized")
end

function BillingService.LoadPlayer(player: Player)
	local billingData = PlayerSession.GetDataAwait(player, "BillingState")
	if not billingData then
		warn("[BillingService] No billing data for player:", player.Name)
		return
	end

	local state = BillingState.new(billingData)
	PlayerStates[player.UserId] = state

	-- Reconcile UnpaidTime for existing saves
	if billingData.UnpaidTime == nil then
		billingData.UnpaidTime = nil
	end

	-- Check if player has an unpaid bill
	local hasBillDue = billingData.UnpaidTime ~= nil

	if hasBillDue then
		-- Restore unpaid bill state
		local breakdown = billingData.CurrentCycle
		local total = math.round(breakdown.PropertyTax + breakdown.Electricity + breakdown.Water + breakdown.Internet)

		player:SetAttribute(BillingConstants.BillDueAttribute, true)
		updatePlayerAttributes(player, {
			PropertyTax = breakdown.PropertyTax,
			Electricity = breakdown.Electricity,
			Water = breakdown.Water,
			Internet = breakdown.Internet,
			Total = total,
		})

		-- Check if power outage should be active
		if state:IsGracePeriodExpired(BillingConstants.GracePeriodSeconds) then
			player:SetAttribute(BillingConstants.PowerOutageAttribute, true)
			print(
				string.format(
					"[BillingService] Restored power outage for %s (unpaid for %d seconds)",
					player.Name,
					state:GetUnpaidDuration()
				)
			)
		else
			player:SetAttribute(BillingConstants.PowerOutageAttribute, false)
		end

		print(string.format("[BillingService] Restored unpaid bill for %s: $%.2f", player.Name, total))
	else
		-- No unpaid bill, initialize clean state
		player:SetAttribute(BillingConstants.BillDueAttribute, false)
		player:SetAttribute(BillingConstants.PowerOutageAttribute, false)
		updatePlayerAttributes(player, { PropertyTax = 0, Electricity = 0, Water = 0, Internet = 0, Total = 0 })
	end

	print("[BillingService] Loaded player:", player.Name)
end

function BillingService.UnloadPlayer(player: Player)
	PlayerStates[player.UserId] = nil
	print("[BillingService] Unloaded player:", player.Name)
end

function BillingService.PayBill(player: Player): (boolean, string)
	local billingState = PlayerStates[player.UserId]
	if not billingState then
		return false, "No billing state found"
	end

	-- Check if bill is due
	if player:GetAttribute(BillingConstants.BillDueAttribute) ~= true then
		return false, "No bill due"
	end

	local breakdown = billingState.Save.CurrentCycle
	local total = math.round(breakdown.PropertyTax + breakdown.Electricity + breakdown.Water + breakdown.Internet)

	-- Check if player has enough cash
	local currencyData = PlayerSession.GetDataAwait(player, "CurrencyState")
	if not currencyData then
		return false, "Currency data not found"
	end

	local currentCash = currencyData.Cash or 0
	if currentCash < total then
		return false, "Insufficient funds"
	end

	-- Deduct from player currency (amount must be integer)
	CurrencyService.Remove(player, "Cash", total, currencyData)

	-- Reset billing cycle
	billingState:ResetCycle()
	EnergyUsageTracker.ResetAccumulated(player)

	-- Clear bill due flag and power outage
	player:SetAttribute(BillingConstants.BillDueAttribute, false)
	player:SetAttribute(BillingConstants.PowerOutageAttribute, false)
	updatePlayerAttributes(player, { PropertyTax = 0, Electricity = 0, Water = 0, Internet = 0, Total = 0 })

	print(string.format("[BillingService] %s paid bill: $%.2f", player.Name, total))
	return true, string.format("Bill paid: $%.2f", total)
end

function BillingService.GetState(player: Player): BillingState.BillingState?
	return PlayerStates[player.UserId]
end

function BillingService.SetInternetTier(player: Player, tier: string): boolean
	local state = PlayerStates[player.UserId]
	if not state then
		return false
	end

	state:SetInternetTier(tier)
	return true
end

return BillingService
