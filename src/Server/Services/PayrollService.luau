--!strict
-- ServerScriptService/Server/Services/PayrollService.lua

local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")

local PayrollPackets = require(ReplicatedStorage.Network.PayrollPackets)
local PlayerSession = require(script.Parent.PlayerSession)
local PlotService = require(script.Parent.PlotService)
local PlotFinder = require(ReplicatedStorage.Shared.Utilities.PlotFinder)
local CurrencyService = require(script.Parent.CurrencyService)
local PayrollState = require(ServerScriptService.Server.Classes.PayrollState)
local WorldUpdate = require(ServerScriptService.Server.Utilities.WorldUpdate)
local TimeScale = require(ReplicatedStorage.Shared.Utilities.TimeScale)

local CHECK_INTERVAL_SECONDS = 1
local MAILBOX_TEXT_DEFAULT = "Next Payout: --"

local function computeCycleDurationSeconds(): number
	local secondsPerFullDay = TimeScale.GetSecondsPerFullDay()
	local secondsPerGameHour = secondsPerFullDay / 24
	local cycleSeconds = secondsPerGameHour * 8
	if cycleSeconds <= 0 then
		cycleSeconds = 60
	end
	return cycleSeconds
end

local function applyCycleDuration(payrollState: PayrollState.PayrollState)
	local targetDuration = computeCycleDurationSeconds()
	if math.abs(payrollState.CycleDurationSeconds - targetDuration) > 1e-03 then
		payrollState.CycleDurationSeconds = targetDuration
	end
end

local PayrollService = {}
local PlayerPayrollStates: { [number]: PayrollState.PayrollState } = {}

type MailboxController = {
	PlotModel: Model,
	Label: TextLabel?,
	ClickConnection: RBXScriptConnection?,
	LastText: string,
}

local PlayerMailboxes: { [number]: MailboxController } = {}

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

local function formatCountdown(seconds: number): string
	local clamped = math.max(0, math.floor(seconds + 0.5))
	local minutes = math.floor(clamped / 60)
	local sec = clamped % 60
	return string.format("%d:%02d", minutes, sec)
end

local function getMailboxController(player: Player): MailboxController?
	return PlayerMailboxes[player.UserId]
end

local function setMailboxText(controller: MailboxController, newText: string)
	if newText == controller.LastText then
		return
	end
	controller.LastText = newText
	local label = controller.Label
	if label then
		label.Text = newText
	end
end

local function updateMailboxDisplay(player: Player, payrollState: PayrollState.PayrollState?)
	local controller = getMailboxController(player)
	if not controller then
		return
	end

	local displayText = MAILBOX_TEXT_DEFAULT
	if payrollState then
		local pending = payrollState:GetPendingCash()
		if pending > 0 then
			displayText = string.format("Collect Cash: $%d", pending)
		else
			displayText = string.format("Next Payout: %s", formatCountdown(payrollState:GetTimeRemaining()))
		end
	end

	setMailboxText(controller, displayText)
end

local function detachMailbox(player: Player)
	local controller = getMailboxController(player)
	if not controller then
		return
	end

	if controller.ClickConnection then
		controller.ClickConnection:Disconnect()
		controller.ClickConnection = nil
	end

	setMailboxText(controller, MAILBOX_TEXT_DEFAULT)
	PlayerMailboxes[player.UserId] = nil
end

local collectPendingPayroll: (Player) -> number

local function attachMailbox(player: Player)
	detachMailbox(player)

	local plotIndex = player:GetAttribute("OwnedPlotIndex")
	if typeof(plotIndex) ~= "number" then
		return
	end

	local plotModel = PlotFinder.FindPlot(plotIndex)
	if not plotModel then
		return
	end

	local mailboxInstance = plotModel:FindFirstChild("Mailbox")
	if not mailboxInstance then
		warn(string.format("[PayrollService] Missing mailbox for plot %d", plotIndex))
		return
	end

	local clickDetector = mailboxInstance:FindFirstChildWhichIsA("ClickDetector")
	if not clickDetector then
		warn(string.format("[PayrollService] Missing ClickDetector on mailbox for plot %d", plotIndex))
		return
	end

	local billboardGui = mailboxInstance:FindFirstChildWhichIsA("BillboardGui")
	local timeLabel = billboardGui and billboardGui:FindFirstChild("TimeTextLabel")
	local castLabel: TextLabel? = if timeLabel and timeLabel:IsA("TextLabel") then timeLabel else nil

	local controller: MailboxController = {
		PlotModel = plotModel,
		Label = castLabel,
		ClickConnection = nil,
		LastText = "",
	}

	controller.ClickConnection = clickDetector.MouseClick:Connect(function(clickingPlayer: Player)
		if clickingPlayer ~= player then
			return
		end
		local ownerId = plotModel:GetAttribute("Owner")
		if ownerId ~= player.UserId then
			return
		end
		collectPendingPayroll(player)
	end)

	PlayerMailboxes[player.UserId] = controller
	setMailboxText(controller, MAILBOX_TEXT_DEFAULT)
	updateMailboxDisplay(player, PayrollService.GetPayrollState(player))
end

collectPendingPayroll = function(player: Player): number
	local payrollState = PayrollService.GetPayrollState(player)
	if not payrollState then
		return 0
	end

	local pendingAmount = payrollState:GetPendingCash()
	if pendingAmount <= 0 then
		local nextPayoutClockTime = resolvePayoutClockTime(payrollState)
		local timeRemaining = payrollState:GetTimeRemaining()

		PayrollPackets.PayrollUpdate:FireClient(player, {
			PendingAmount = pendingAmount,
			CycleAmount = 0,
			CollectedAmount = 0,
			NextPayoutClockTime = nextPayoutClockTime,
			TimeRemaining = timeRemaining,
			MailboxEmpty = true,
		})

		updateMailboxDisplay(player, payrollState)
		return 0
	end

	local currencyStateData = PlayerSession.GetDataAwait(player, "CurrencyState")
	if typeof(currencyStateData) ~= "table" then
		warn(string.format("[PayrollService] Currency state unavailable for %s", player.Name))
		return 0
	end

	CurrencyService.Add(player, "Cash", pendingAmount, currencyStateData, {
		Source = "Career",
	})
	payrollState:ClearPendingCash()

	local nextPayoutClockTime = resolvePayoutClockTime(payrollState)
	local timeRemaining = payrollState:GetTimeRemaining()

	PayrollPackets.PayrollUpdate:FireClient(player, {
		PendingAmount = 0,
		CycleAmount = 0,
		CollectedAmount = pendingAmount,
		NextPayoutClockTime = nextPayoutClockTime,
		TimeRemaining = timeRemaining,
		MailboxEmpty = false,
	})

	updateMailboxDisplay(player, payrollState)
	return pendingAmount
end

local function ensurePayrollState(player: Player)
	local playerIdentifier = player.UserId
	if PlayerPayrollStates[playerIdentifier] then
		return
	end

	local payrollStateData = PlayerSession.GetDataAwait(player, "PayrollState")
	local payrollState = PayrollState.new(computeCycleDurationSeconds(), payrollStateData)
	PlayerPayrollStates[playerIdentifier] = payrollState
	updateMailboxDisplay(player, payrollState)
end

function PayrollService.Init()
	PlotService.PlotClaimed:Connect(function(player: Player, _plotState)
		ensurePayrollState(player)
		attachMailbox(player)
	end)

	PlotService.PlotUnclaimed:Connect(function(player: Player, _plotIndex)
		detachMailbox(player)
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
			PendingAmount = if payrollState then payrollState:GetPendingCash() else 0,
			NextPayoutClockTime = nextPayoutClockTime,
			TimeRemaining = timeRemaining,
		}
	end

	Players.PlayerRemoving:Connect(function(player: Player)
		detachMailbox(player)
		PayrollService.Remove(player)
	end)

	for _, player in ipairs(Players:GetPlayers()) do
		if player:GetAttribute("OwnedPlotIndex") ~= nil then
			ensurePayrollState(player)
			attachMailbox(player)
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

		applyCycleDuration(payrollState)

		payrollState:Update(deltaSeconds)

		if payrollState:IsDue() then
			PayrollService.ProcessPayroll(player, payrollState)
		else
			updateMailboxDisplay(player, payrollState)
		end
	end
end

function PayrollService.ProcessPayroll(player: Player, payrollState: PayrollState.PayrollState)
	local allEarnings = payrollState:GetAllEarnings()
	local cycleAmount = 0
	local residentBreakdown: { [string]: number } = {}

	for residentName, earningsData in pairs(allEarnings) do
		local minutesWorked = if typeof(earningsData.WorkMinutes) == "number" then earningsData.WorkMinutes else 0
		local basePayPerMinute = if typeof(earningsData.BasePayPerMinute) == "number"
			then earningsData.BasePayPerMinute
			else 0
		local payout = math.floor(basePayPerMinute * minutesWorked + 0.5)
		payout = sanitizeAmount(payout)

		if payout > 0 then
			cycleAmount += payout
			residentBreakdown[residentName] = payout
		end
	end

	local pendingAfter = payrollState:GetPendingCash()
	if cycleAmount > 0 then
		pendingAfter = payrollState:AddPendingCash(cycleAmount)

		local residentCount = 0
		for _ in pairs(residentBreakdown) do
			residentCount += 1
		end

		print(
			string.format(
				"[PayrollService] Added $%d to %s mailbox (residents: %d, pending: $%d)",
				cycleAmount,
				player.Name,
				residentCount,
				pendingAfter
			)
		)
	else
		pendingAfter = payrollState:GetPendingCash()
	end

	payrollState:ClearAllEarnings()
	payrollState:ResetCycle()

	local nextPayoutClockTime = resolvePayoutClockTime(payrollState)
	local timeRemaining = payrollState:GetTimeRemaining()

	PayrollPackets.PayrollUpdate:FireClient(player, {
		PendingAmount = pendingAfter,
		CycleAmount = cycleAmount,
		CollectedAmount = 0,
		NextPayoutClockTime = nextPayoutClockTime,
		TimeRemaining = timeRemaining,
		MailboxEmpty = false,
	})

	updateMailboxDisplay(player, payrollState)
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
			local minutesWorked = if typeof(earningsData.WorkMinutes) == "number" then earningsData.WorkMinutes else 0
			local basePayPerMinute = if typeof(earningsData.BasePayPerMinute) == "number"
				then earningsData.BasePayPerMinute
				else 0
			local payout = math.floor(basePayPerMinute * minutesWorked + 0.5)
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
	minutesWorked: number,
	jobId: string,
	basePayPerMinute: number
)
	local payrollState = PayrollService.GetPayrollState(player)
	if not payrollState then
		warn(string.format("[PayrollService] No payroll state for %s", player.Name))
		return
	end

	if minutesWorked <= 0 then
		return
	end
	if basePayPerMinute <= 0 then
		return
	end

	payrollState:AddWorkTime(residentName, minutesWorked, jobId, basePayPerMinute)
end

function PayrollService.CollectPending(player: Player): number
	return collectPendingPayroll(player)
end

function PayrollService.Remove(player: Player)
	detachMailbox(player)
	PlayerPayrollStates[player.UserId] = nil
end

return PayrollService
