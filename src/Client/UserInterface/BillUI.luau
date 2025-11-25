--!strict
-- StarterPlayerScripts/UserInterface/BillUI.luau

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")
local BillGui = PlayerGui:WaitForChild("BillGui")

local BillingConstants = require(ReplicatedStorage.Shared.Definitions.BillingConstants)
local BillingPackets = require(ReplicatedStorage.Network.BillingPackets)
local Debounce = require(ReplicatedStorage.Shared.Utilities.Debounce)
local Formatter = require(ReplicatedStorage.Shared.Utilities.Formatter)
local VisualFX = require(ReplicatedStorage.Shared.Utilities.VisualFX)

local ActiveQueryFolder = PlayerGui:WaitForChild("ActiveQuery") :: Folder
local HudBottomRightFlag = ActiveQueryFolder:FindFirstChild("HUDBottomRightEnabled") :: BoolValue?

local MainFrame = BillGui:WaitForChild("Main") :: Frame
local WindowFrame = MainFrame:WaitForChild("Window") :: Frame
local BodyFrame = WindowFrame:WaitForChild("Body") :: Frame
local BillsFrame = BodyFrame:WaitForChild("Bills") :: Frame
local TotalFrame = BodyFrame:WaitForChild("Total") :: Frame
local PayButton = MainFrame:WaitForChild("PayButton") :: TextButton

local PropertyTaxFrame = BillsFrame:WaitForChild("PropertyTax") :: Frame
local ElectricityFrame = BillsFrame:WaitForChild("Electricity") :: Frame
local WaterFrame = BillsFrame:WaitForChild("Water") :: Frame
local InternetFrame = BillsFrame:WaitForChild("Internet") :: Frame

local PropertyTaxAmountLabel = PropertyTaxFrame:WaitForChild("Amount") :: TextLabel
local ElectricityAmountLabel = ElectricityFrame:WaitForChild("Amount") :: TextLabel
local WaterAmountLabel = WaterFrame:WaitForChild("Amount") :: TextLabel
local InternetAmountLabel = InternetFrame:WaitForChild("Amount") :: TextLabel
local TotalAmountLabel = TotalFrame:WaitForChild("Amount") :: TextLabel
local ImageLabelBackground = BodyFrame:FindFirstChild("ImageLabel") :: ImageLabel
local CloseButton = ImageLabelBackground:FindFirstChild("CloseButton") :: TextButton

local BillUI = {}

local CURRENCY_OPTIONS = {
	currencySymbol = "$",
	decimalPlaces = 2,
	useCommas = true,
}

local POPUP_OPTIONS = {
	hiddenScale = 0.92,
}

local CASH_ATTRIBUTE = "Cash"

local isVisible = false
local hudSuppressed = false
local hudRestoreValue: boolean? = nil

local function updateAmountLabel(label: TextLabel, value: number)
	label.Text = Formatter.formatCurrency(value, CURRENCY_OPTIONS)
end

local function suppressHud()
	if hudSuppressed or not HudBottomRightFlag then
		return
	end
	hudSuppressed = true
	hudRestoreValue = HudBottomRightFlag.Value
	HudBottomRightFlag.Value = false
end

local function restoreHud()
	if not hudSuppressed or not HudBottomRightFlag then
		return
	end
	hudSuppressed = false
	HudBottomRightFlag.Value = if hudRestoreValue ~= nil then hudRestoreValue else true
	hudRestoreValue = nil
end

local function hideConflictingInterfaces()
	-- Hide ProfileUI
	local profileGui = PlayerGui:FindFirstChild("Profile")
	if profileGui and profileGui:IsA("ScreenGui") then
		local mainFrame = profileGui:FindFirstChild("Main")
		if mainFrame and mainFrame.Visible then
			local ok, module = pcall(require, script.Parent.ProfileUI)
			if ok and module and typeof(module.Hide) == "function" then
				module.Hide()
			end
		end
	end

	-- Hide ReviewsUI
	local reviewsGui = PlayerGui:FindFirstChild("Reviews")
	if reviewsGui and reviewsGui:IsA("ScreenGui") and reviewsGui.Enabled then
		local ok, module = pcall(require, script.Parent.ReviewsUI)
		if ok and module and typeof(module.SetVisible) == "function" then
			module.SetVisible(false)
		end
	end
end

local function updatePayButtonVisibility()
	local cash = Player:GetAttribute(CASH_ATTRIBUTE) or 0
	local totalBill = Player:GetAttribute(BillingConstants.TotalBillAttribute) or 0
	local billDue = Player:GetAttribute(BillingConstants.BillDueAttribute) == true
	PayButton.Visible = billDue and cash >= totalBill and totalBill > 0
end

function BillUI.Init()
	-- Initially hide the UI
	MainFrame.Visible = false

	-- Listen to PropertyTax attribute changes
	Player:GetAttributeChangedSignal(BillingConstants.PropertyTaxAttribute):Connect(function()
		local value = Player:GetAttribute(BillingConstants.PropertyTaxAttribute) or 0
		updateAmountLabel(PropertyTaxAmountLabel, value)
	end)
	updateAmountLabel(PropertyTaxAmountLabel, Player:GetAttribute(BillingConstants.PropertyTaxAttribute) or 0)

	-- Listen to Electricity attribute changes
	Player:GetAttributeChangedSignal(BillingConstants.ElectricityAttribute):Connect(function()
		local value = Player:GetAttribute(BillingConstants.ElectricityAttribute) or 0
		updateAmountLabel(ElectricityAmountLabel, value)
	end)
	updateAmountLabel(ElectricityAmountLabel, Player:GetAttribute(BillingConstants.ElectricityAttribute) or 0)

	-- Listen to Water attribute changes
	Player:GetAttributeChangedSignal(BillingConstants.WaterAttribute):Connect(function()
		local value = Player:GetAttribute(BillingConstants.WaterAttribute) or 0
		updateAmountLabel(WaterAmountLabel, value)
	end)
	updateAmountLabel(WaterAmountLabel, Player:GetAttribute(BillingConstants.WaterAttribute) or 0)

	-- Listen to Internet attribute changes
	Player:GetAttributeChangedSignal(BillingConstants.InternetAttribute):Connect(function()
		local value = Player:GetAttribute(BillingConstants.InternetAttribute) or 0
		updateAmountLabel(InternetAmountLabel, value)
	end)
	updateAmountLabel(InternetAmountLabel, Player:GetAttribute(BillingConstants.InternetAttribute) or 0)

	-- Listen to TotalBill attribute changes
	Player:GetAttributeChangedSignal(BillingConstants.TotalBillAttribute):Connect(function()
		local value = Player:GetAttribute(BillingConstants.TotalBillAttribute) or 0
		updateAmountLabel(TotalAmountLabel, value)
	end)
	updateAmountLabel(TotalAmountLabel, Player:GetAttribute(BillingConstants.TotalBillAttribute) or 0)

	-- Update PayButton visibility when cash or bill changes
	Player:GetAttributeChangedSignal(CASH_ATTRIBUTE):Connect(updatePayButtonVisibility)
	Player:GetAttributeChangedSignal(BillingConstants.TotalBillAttribute):Connect(updatePayButtonVisibility)
	Player:GetAttributeChangedSignal(BillingConstants.BillDueAttribute):Connect(updatePayButtonVisibility)
	updatePayButtonVisibility()

	-- PayButton logic
	PayButton.Activated:Connect(function()
		Debounce.RunIfAvailable("PayBill", 0.5, function()
			local success, message = BillingPackets.PayBill:Fire()
			if success then
				print("[BillUI] Bill paid successfully:", message)
			else
				warn("[BillUI] Failed to pay bill:", message)
			end
		end, Player.UserId)
	end)

	-- CloseButton logic
	CloseButton.Activated:Connect(function()
		BillUI.Hide()
	end)
end

function BillUI.Show()
	if isVisible then
		hideConflictingInterfaces()
		return
	end
	isVisible = true
	suppressHud()
	hideConflictingInterfaces()
	MainFrame.Visible = true
	VisualFX.SetPopupVisible(WindowFrame, true, POPUP_OPTIONS)
end

function BillUI.Hide()
	if not isVisible then
		return
	end
	isVisible = false
	restoreHud()
	VisualFX.SetPopupVisible(WindowFrame, false, {
		hiddenScale = POPUP_OPTIONS.hiddenScale,
		onHidden = function()
			if not isVisible then
				MainFrame.Visible = false
			end
		end,
	})
end

function BillUI.Toggle()
	if isVisible then
		BillUI.Hide()
	else
		BillUI.Show()
	end
end

return BillUI
