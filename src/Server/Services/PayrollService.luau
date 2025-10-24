--!strict
-- ServerScriptService/Server/Services/PayrollService.lua

local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")

local PayrollPackets = require(ReplicatedStorage.Network.PayrollPackets)
local PlayerSession = require(script.Parent.PlayerSession)
local PlotService = require(script.Parent.PlotService)
local CurrencyService = require(script.Parent.CurrencyService)
local PayrollState = require(ServerScriptService.Server.Classes.PayrollState)
local WorldUpdate = require(ServerScriptService.Server.Utilities.WorldUpdate)
local TimeScale = require(ReplicatedStorage.Shared.Utilities.TimeScale)

local PAYROLL_CYCLE_DURATION_SECONDS = 14400 -- 4 hours
local CHECK_INTERVAL_SECONDS = 5

local PayrollService = {}
local PlayerPayrollStates: { [number]: PayrollState.PayrollState } = {}

local function resolvePayoutClockTime(payrollState: PayrollState.PayrollState): number
	local serverNow = Workspace:GetServerTimeNow()
	local elapsed = payrollState:GetElapsedSeconds()
	local cycleStartSeconds = serverNow - elapsed
	local payoutServerSeconds = cycleStartSeconds + payrollState.CycleDurationSeconds
	return TimeScale.ClockTimeFromServerSeconds(payoutServerSeconds)
end

local function sanitizeAmount(amount: number): number
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

local function getCurrencyState(player: Player): any?
	local currencyData = PlayerSession.GetData(player, "CurrencyState")
	if typeof(currencyData) ~= "table" then
		return nil
	end
	return currencyData
end

local function ensurePayrollState(player: Player)
	local playerIdentifier = player.UserId
	if PlayerPayrollStates[playerIdentifier] then
		return
	end

	local payrollStateData = PlayerSession.GetDataAwait(player, "PayrollState")
	local payrollState = PayrollState.new(PAYROLL_CYCLE_DURATION_SECONDS, payrollStateData)
	PlayerPayrollStates[playerIdentifier] = payrollState
end

function PayrollService.Init()
	PlotService.PlotClaimed:Connect(function(player: Player, _plotState)
		ensurePayrollState(player)
	end)

	PlotService.PlotUnclaimed:Connect(function(player: Player, _plotIndex)
		PayrollService.Remove(player)
	end)

	PayrollPackets.RequestPayrollInfo.OnServerInvoke = function(player: Player)
		local breakdown = PayrollService.GetPayrollBreakdown(player)
		local payrollState = PayrollService.GetPayrollState(player)
		local timeRemaining = 0
		local nextPayoutClockTime = 0

		if payrollState then
			timeRemaining = payrollState:GetTimeRemaining()
			nextPayoutClockTime = resolvePayoutClockTime(payrollState)
		end

		if typeof(timeRemaining) ~= "number" then
			timeRemaining = 0
		end
		if typeof(nextPayoutClockTime) ~= "number" then
			nextPayoutClockTime = 0
		end

		return {
			TotalPending = breakdown.TotalPending,
			NextPayoutClockTime = nextPayoutClockTime,
			TimeRemaining = timeRemaining,
		}
	end

	Players.PlayerRemoving:Connect(function(player: Player)
		PayrollService.Remove(player)
	end)

	for _, player in ipairs(Players:GetPlayers()) do
		if player:GetAttribute("OwnedPlotIndex") ~= nil then
			ensurePayrollState(player)
		end
	end

	PayrollService.Start()
end

function PayrollService.Start()
	if WorldUpdate.IsSubscribed("PayrollService") then
		return
	end
	WorldUpdate.Subscribe("PayrollService", CHECK_INTERVAL_SECONDS, function(deltaSeconds: number)
		PayrollService.UpdatePayroll(deltaSeconds)
	end)
end

function PayrollService.UpdatePayroll(deltaSeconds: number)
	for playerIdentifier, payrollState in pairs(PlayerPayrollStates) do
		local player = Players:GetPlayerByUserId(playerIdentifier)
		if player == nil then
			continue
		end

		payrollState:Update(deltaSeconds)

		if payrollState:IsDue() then
			PayrollService.ProcessPayroll(player, payrollState)
		end
	end
end

function PayrollService.ProcessPayroll(player: Player, payrollState: PayrollState.PayrollState)
	local currencyStateData = getCurrencyState(player)
	if not currencyStateData then
		return
	end

	local allEarnings = payrollState:GetAllEarnings()
	local totalPayout = 0
	local residentBreakdown: { [string]: number } = {}

	for residentName, earningsData in pairs(allEarnings) do
		local minutesWorked = earningsData.SecondsWorked / 60
		local basePay = earningsData.BasePay
		local payout = math.floor(basePay * minutesWorked + 0.5)
		payout = sanitizeAmount(payout)

		if payout > 0 then
			totalPayout += payout
			residentBreakdown[residentName] = payout
		end
	end

	if totalPayout > 0 then
		CurrencyService.Add(player, "Cash", totalPayout, currencyStateData)

		local nextPayoutClockTime = resolvePayoutClockTime(payrollState)
		PayrollPackets.PayrollUpdate:FireClient(player, {
			PayoutAmount = totalPayout,
			NextPayoutClockTime = nextPayoutClockTime,
		})

		local residentCount = 0
		for _ in pairs(residentBreakdown) do
			residentCount += 1
		end

		print(
			string.format(
				"[PayrollService] Processed payroll for %s: $%d across %d residents",
				player.Name,
				totalPayout,
				residentCount
			)
		)
	end

	payrollState:ClearAllEarnings()
	payrollState:ResetCycle()
end

function PayrollService.GetPayrollState(player: Player): PayrollState.PayrollState?
	return PlayerPayrollStates[player.UserId]
end

function PayrollService.GetPayrollBreakdown(player: Player): {
	TotalPending: number,
	ResidentEarnings: { [string]: number },
}
	local payrollState = PayrollService.GetPayrollState(player)
	local totalPending = 0
	local residentEarnings: { [string]: number } = {}

	if payrollState then
		local allEarnings = payrollState:GetAllEarnings()
		for residentName, earningsData in pairs(allEarnings) do
			local minutesWorked = earningsData.SecondsWorked / 60
			local basePay = earningsData.BasePay
			local payout = math.floor(basePay * minutesWorked + 0.5)
			payout = sanitizeAmount(payout)

			if payout > 0 then
				totalPending += payout
				residentEarnings[residentName] = payout
			end
		end
	end

	return {
		TotalPending = totalPending,
		ResidentEarnings = residentEarnings,
	}
end

function PayrollService.RecordWorkTime(
	player: Player,
	residentName: string,
	secondsWorked: number,
	jobId: string,
	basePay: number
)
	local payrollState = PayrollService.GetPayrollState(player)
	if not payrollState then
		warn(string.format("[PayrollService] No payroll state for %s", player.Name))
		return
	end

	payrollState:AddWorkTime(residentName, secondsWorked, jobId, basePay)
end

function PayrollService.Remove(player: Player)
	PlayerPayrollStates[player.UserId] = nil
end

return PayrollService
