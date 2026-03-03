--!strict
-- Client/UserInterface/MailboxHUD.luau
-- HUD widget showing mailbox balance, tenant income rate, and next payout countdown.
-- Receives data from MailboxPackets.IncomeSummary fired by TenantService.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MailboxPackets = require(ReplicatedStorage.Network.MailboxPackets)
local Formatter = require(ReplicatedStorage.Shared.Utilities.Formatter)

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

local MailboxHUD = {}

local CURRENCY_FORMAT = {
	currencySymbol = "$",
	decimalPlaces = 0,
	useCommas = true,
}
local RATE_FORMAT = {
	currencySymbol = "$",
	decimalPlaces = 2,
}

local currentBalance = 0
local currentRate = 0
local currentNextTick = 0

local balanceLabel: TextLabel? = nil
local rateLabel: TextLabel? = nil
local nextTickLabel: TextLabel? = nil

local function formatNextTick(seconds: number): string
	if seconds <= 0 then
		return ""
	end
	if seconds < 60 then
		return string.format("Next: %ds", seconds)
	end
	local minutes = math.floor(seconds / 60)
	local secs = seconds % 60
	return string.format("Next: %dm %ds", minutes, secs)
end

local function refreshDisplay()
	if balanceLabel then
		balanceLabel.Text = string.format("Mailbox: %s", Formatter.formatCurrency(currentBalance, CURRENCY_FORMAT))
	end

	if rateLabel then
		if currentRate > 0 then
			rateLabel.Text = string.format("+%s/sec", Formatter.formatCurrency(currentRate, RATE_FORMAT))
		else
			rateLabel.Text = "$0/sec"
		end
	end

	if nextTickLabel then
		local tickText = formatNextTick(currentNextTick)
		nextTickLabel.Text = tickText
		nextTickLabel.Visible = tickText ~= ""
	end
end

local function makeLabel(parent: Frame, name: string, order: number): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.LayoutOrder = order
	label.Size = UDim2.new(1, 0, 0, 18)
	label.BackgroundTransparency = 1
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeColor3 = Color3.new(0, 0, 0)
	label.TextStrokeTransparency = 0.4
	label.Font = Enum.Font.GothamMedium
	label.TextSize = 13
	label.TextXAlignment = Enum.TextXAlignment.Right
	label.Text = ""
	label.Parent = parent
	return label
end

function MailboxHUD.Init()
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "MailboxHUDGui"
	screenGui.IgnoreGuiInset = true
	screenGui.ResetOnSpawn = false
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.Parent = PlayerGui

	local container = Instance.new("Frame")
	container.Name = "MailboxContainer"
	container.AnchorPoint = Vector2.new(1, 0)
	-- Positioned top-right, below the TopRight cash/income area
	container.Position = UDim2.new(1, -12, 0, 92)
	container.Size = UDim2.fromOffset(220, 60)
	container.BackgroundTransparency = 1
	container.Parent = screenGui

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 2)
	layout.Parent = container

	balanceLabel = makeLabel(container, "BalanceLabel", 1)
	rateLabel = makeLabel(container, "RateLabel", 2)
	nextTickLabel = makeLabel(container, "NextTickLabel", 3)

	refreshDisplay()

	MailboxPackets.IncomeSummary.OnClientEvent:Connect(function(payload)
		if typeof(payload) ~= "table" then
			return
		end
		if typeof(payload.Balance) == "number" then
			currentBalance = payload.Balance
		end
		if typeof(payload.IncomePerSecond) == "number" then
			currentRate = payload.IncomePerSecond
		end
		if typeof(payload.NextRentTick) == "number" then
			currentNextTick = payload.NextRentTick
		end
		refreshDisplay()
	end)
end

return MailboxHUD
