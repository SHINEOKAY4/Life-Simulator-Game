--!strict
-- StarterPlayerScripts/Client/UserInterface/MainHUD.lua

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Formatter = require(ReplicatedStorage.Shared.Utilities.Formatter)
local TimeScale = require(ReplicatedStorage.Shared.Utilities.TimeScale)
local VisualFX = require(ReplicatedStorage.Shared.Utilities.VisualFX)
local Debounce = require(ReplicatedStorage.Shared.Utilities.Debounce)
local ResidentNeedsUI = require(script.Parent:WaitForChild("ResidentNeedsUI"))
local CurrencyPackets = require(ReplicatedStorage.Network.CurrencyPackets)
local BillingPackets = require(ReplicatedStorage.Network.BillingPackets)

local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")

local InputContextsFolder = PlayerGui:WaitForChild("InputContexts")
local BillContext = InputContextsFolder:WaitForChild("BillContext")

local ActiveQueryFolder = PlayerGui:FindFirstChild("ActiveQuery")
local HUDBottomRightEnabled = ActiveQueryFolder:FindFirstChild("HUDBottomRightEnabled") :: BoolValue

local MainHUDGui = PlayerGui:WaitForChild("MainHUD") :: ScreenGui
local BillFrame = MainHUDGui:WaitForChild("BillFrame") :: Frame
local PlotTaxLabel = BillFrame:WaitForChild("PlotTaxLabel") :: TextLabel
local ElectricLabel = BillFrame:WaitForChild("ElectricLabel") :: TextLabel
local FoodLabel = BillFrame:WaitForChild("FoodLabel") :: TextLabel
local TotalLabel = BillFrame:WaitForChild("TotalLabel") :: TextLabel

local BottomRight = MainHUDGui:WaitForChild("BottomRight") :: Frame
local TopRight = MainHUDGui:WaitForChild("TopRight")
local TextFrame = TopRight:WaitForChild("TextFrame") :: Frame
local CashLabel = TextFrame:WaitForChild("CashLabel") :: TextLabel
local CashLabelStroke = TextFrame:WaitForChild("CashLabelStroke") :: TextLabel
local BuildButton = BottomRight:WaitForChild("BuildButton") :: TextButton
local BillsButton = BottomRight:WaitForChild("BillsButton") :: TextButton
local ExpandButton = BottomRight:WaitForChild("ExpandButton") :: TextButton
local SettingsButton = BottomRight:WaitForChild("SettingsButton") :: TextButton
local BillImageFrame = BillsButton:WaitForChild("Image") :: Frame
local TimeTextFrame = BillImageFrame:WaitForChild("TimeTextFrame") :: Frame
local TimeTextLabel = TimeTextFrame:WaitForChild("TimeTextLabel") :: TextLabel
local ResidentGui = PlayerGui:WaitForChild("ResidentGui") :: ScreenGui
local ResidentSelectionFrame = ResidentGui:WaitForChild("ResidentSelectionFrame") :: Frame
local ResidentRosterBackground = ResidentSelectionFrame:WaitForChild("Background") :: Frame
local Roster = ResidentRosterBackground:WaitForChild("Roster") :: Frame

local rng = Random.new()
local CASH_ATTRIBUTE_NAME = "Cash"
local CASH_FORMAT_OPTIONS = {
	currencySymbol = "$",
}
local lastCash: number? = nil
local pendingCashIncrease = 0
local hasProcessedInitialAttribute = false

type PopupStyle = {
	Duration: number,
	RiseDistance: number,
	InitialScale: number,
	Color: Color3,
	StrokeColor: Color3,
	StrokeTransparency: number,
	Size: Vector2,
	Rotation: number,
	PulseScale: number,
	PulseDuration: number,
	ScaleTweenRatio: number,
	FadeTweenRatio: number,
	FadeDelayRatio: number,
	CleanupExtraDelay: number,
}

local CASH_GAIN_STYLE: PopupStyle = {
	Duration = 1,
	RiseDistance = 54,
	InitialScale = 0.68,
	Color = Color3.fromRGB(120, 255, 180),
	StrokeColor = Color3.fromRGB(10, 35, 20),
	StrokeTransparency = 0.15,
	Size = Vector2.new(148, 42),
	Rotation = 6,
	PulseScale = 1.08,
	PulseDuration = 0.3,
	ScaleTweenRatio = 0.45,
	FadeTweenRatio = 0.55,
	FadeDelayRatio = 0.5,
	CleanupExtraDelay = 0.35,
}

local CASH_DEDUCTION_STYLE: PopupStyle = {
	Duration = 0.95,
	RiseDistance = 40,
	InitialScale = 0.68,
	Color = Color3.fromRGB(255, 145, 145),
	StrokeColor = Color3.fromRGB(65, 0, 0),
	StrokeTransparency = 0.12,
	Size = Vector2.new(110, 32),
	Rotation = 4,
	PulseScale = 0.96,
	PulseDuration = 0.28,
	ScaleTweenRatio = 0.4,
	FadeTweenRatio = 0.6,
	FadeDelayRatio = 0.45,
	CleanupExtraDelay = 0.3,
}

local function findRosterFrame(targetResidentName: string?): Frame?
	if typeof(targetResidentName) == "string" and targetResidentName ~= "" then
		local specificFrame = Roster:FindFirstChild(targetResidentName)
		if specificFrame and specificFrame:IsA("Frame") then
			return specificFrame
		end
	end

	local selectedModel = ResidentNeedsUI.GetCurrentSelectedResident()
	if selectedModel then
		local namedFrame = Roster:FindFirstChild(selectedModel.Name)
		if namedFrame and namedFrame:IsA("Frame") then
			return namedFrame
		end
	end
	for _, child in ipairs(Roster:GetChildren()) do
		if child:IsA("Frame") then
			return child
		end
	end
	return nil
end

local function ensurePulseScale(): UIScale
	local existing = CashLabel:FindFirstChildWhichIsA("UIScale")
	if existing then
		existing.Scale = 1
		return existing
	end
	local pulseScale = Instance.new("UIScale")
	pulseScale.Scale = 1
	pulseScale.Parent = CashLabel
	return pulseScale
end

local function createCashPopup(
	amount: number,
	style: PopupStyle,
	parentContainer: Frame,
	anchorPosition: UDim2,
	anchorPoint: Vector2,
	zIndexBase: number,
	onPreAnimate: (() -> ())?
)
	local popupLabel = Instance.new("TextLabel")
	popupLabel.Name = "CashPopup"
	popupLabel.AnchorPoint = anchorPoint
	popupLabel.Position = anchorPosition
	popupLabel.Size = UDim2.fromOffset(style.Size.X, style.Size.Y)
	popupLabel.BackgroundTransparency = 1
	popupLabel.Text = if amount > 0
		then string.format("+%s", Formatter.formatCurrency(amount, CASH_FORMAT_OPTIONS))
		else "-" .. Formatter.formatCurrency(math.abs(amount), CASH_FORMAT_OPTIONS)
	popupLabel.TextColor3 = style.Color
	popupLabel.TextStrokeColor3 = style.StrokeColor
	popupLabel.TextStrokeTransparency = style.StrokeTransparency
	popupLabel.Font = Enum.Font.GothamBold
	popupLabel.TextScaled = true
	popupLabel.ZIndex = zIndexBase
	popupLabel.ClipsDescendants = false
	popupLabel.Rotation = rng:NextNumber(-style.Rotation, style.Rotation)
	popupLabel.Parent = parentContainer

	local scale = Instance.new("UIScale")
	scale.Scale = style.InitialScale
	scale.Parent = popupLabel

	if onPreAnimate then
		onPreAnimate()
	end

	local targetPosition =
		UDim2.fromOffset(popupLabel.Position.X.Offset, popupLabel.Position.Y.Offset - style.RiseDistance)

	local riseTween = TweenService:Create(
		popupLabel,
		TweenInfo.new(style.Duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{
			Position = targetPosition,
		}
	)

	local scaleTween = TweenService:Create(
		scale,
		TweenInfo.new(style.Duration * style.ScaleTweenRatio, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{
			Scale = 1,
		}
	)

	local fadeTween = TweenService:Create(
		popupLabel,
		TweenInfo.new(style.Duration * style.FadeTweenRatio, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{
			TextTransparency = 1,
			TextStrokeTransparency = 1,
		}
	)

	riseTween:Play()
	scaleTween:Play()

	task.delay(style.Duration * style.FadeDelayRatio, function()
		if popupLabel.Parent then
			fadeTween:Play()
		end
	end)

	local function cleanup()
		if popupLabel.Parent then
			popupLabel:Destroy()
		end
	end

	fadeTween.Completed:Connect(cleanup)
	task.delay(style.Duration + style.CleanupExtraDelay, cleanup)
end

local function showCashPop(delta: number, targetResidentName: string?)
	if delta <= 0 then
		return
	end

	local pulseScale = ensurePulseScale()
	pulseScale.Scale = 1
	VisualFX.Pulse(CashLabel, CASH_GAIN_STYLE.PulseScale, CASH_GAIN_STYLE.PulseDuration, function()
		if pulseScale.Parent then
			pulseScale.Scale = 1
		end
	end)

	local targetFrame = findRosterFrame(targetResidentName)
	if not targetFrame then
		return
	end

	local frameSize = targetFrame.AbsoluteSize
	local backgroundSize = ResidentRosterBackground.AbsoluteSize
	if (frameSize.X <= 0 or frameSize.Y <= 0) or (backgroundSize.X <= 0 or backgroundSize.Y <= 0) then
		return
	end

	local backgroundPosition = ResidentRosterBackground.AbsolutePosition
	local framePosition = targetFrame.AbsolutePosition
	local frameCenterX = framePosition.X + (frameSize.X * 0.5)
	local topOffsetX = frameCenterX - backgroundPosition.X
	local topOffsetY = framePosition.Y - backgroundPosition.Y

	createCashPopup(
		delta,
		CASH_GAIN_STYLE,
		ResidentRosterBackground,
		UDim2.fromOffset(math.round(topOffsetX), math.round(topOffsetY)),
		Vector2.new(0.5, 1),
		math.max(targetFrame.ZIndex + 5, 10),
		function()
			VisualFX.Pulse(targetFrame, 1.03, 0.32, nil)
		end
	)
end

local function showCashDeductionPop(amount: number)
	if amount <= 0 then
		return
	end

	local pulseScale = ensurePulseScale()
	pulseScale.Scale = 1
	VisualFX.Pulse(CashLabel, CASH_DEDUCTION_STYLE.PulseScale, CASH_DEDUCTION_STYLE.PulseDuration, function()
		if pulseScale.Parent then
			pulseScale.Scale = 1
		end
	end)

	local container = TextFrame
	local containerSize = container.AbsoluteSize
	if containerSize.X <= 0 or containerSize.Y <= 0 then
		return
	end

	local containerPosition = container.AbsolutePosition
	local labelPosition = CashLabel.AbsolutePosition
	local labelSize = CashLabel.AbsoluteSize
	local centerOffsetX = (labelPosition.X + labelSize.X * 0.5) - containerPosition.X
	local bottomOffsetY = (labelPosition.Y + labelSize.Y) - containerPosition.Y

	createCashPopup(
		-amount,
		CASH_DEDUCTION_STYLE,
		container,
		UDim2.fromOffset(math.round(centerOffsetX), math.round(bottomOffsetY)),
		Vector2.new(0.5, 0),
		math.max(CashLabel.ZIndex + 2, 10),
		nil
	)
end

local HOVER_TWEEN_INFO = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local HOVER_SCALE_X = 1.19
local HOVER_SCALE_Y = 1.211

local function scaleUDim2(size: UDim2, scaleX: number, scaleY: number): UDim2
	return UDim2.new(size.X.Scale * scaleX, size.X.Offset * scaleX, size.Y.Scale * scaleY, size.Y.Offset * scaleY)
end

local function formatClockLabel(clockTime: number): string
	local normalized = (clockTime % 24 + 24) % 24
	local hourComponent = math.floor(normalized)
	local minuteFloat = (normalized - hourComponent) * 60
	local minuteComponent = math.floor(minuteFloat + 0.5)

	if minuteComponent >= 60 then
		minuteComponent -= 60
		hourComponent = (hourComponent + 1) % 24
	end

	local suffix = if hourComponent >= 12 then "pm" else "am"
	local displayHour = hourComponent % 12
	if displayHour == 0 then
		displayHour = 12
	end

	if minuteComponent == 0 then
		return string.format("%d %s", displayHour, suffix)
	end

	return string.format("%d:%02d %s", displayHour, minuteComponent, suffix)
end

local function resolveNextBillingLabel(timeRemainingSeconds: number?, outstandingTotal: number?): string
	local resolvedOutstanding = if typeof(outstandingTotal) == "number" then outstandingTotal else 0

	if typeof(timeRemainingSeconds) == "number" and timeRemainingSeconds <= 0 and resolvedOutstanding > 0 then
		return "due"
	end

	if typeof(timeRemainingSeconds) == "number" and timeRemainingSeconds > 0 then
		local currentClock = TimeScale.GetClockTime()
		local additionalHours = TimeScale.GameHoursFromRealDelta(timeRemainingSeconds)
		return formatClockLabel(currentClock + additionalHours)
	end

	return "-"
end

local function configureButtonVisuals(button: TextButton)
	local imageFrame = button:FindFirstChild("Image")
	if not imageFrame or not imageFrame:IsA("Frame") then
		return
	end

	local originalSize = imageFrame.Size
	local hoverSize = scaleUDim2(originalSize, HOVER_SCALE_X, HOVER_SCALE_Y)
	local currentTarget = originalSize
	local activeTween: Tween? = nil
	local isHovering = false
	local isPressing = false

	local function play(targetSize: UDim2)
		if currentTarget == targetSize then
			return
		end

		currentTarget = targetSize
		if activeTween then
			activeTween:Cancel()
		end
		activeTween = VisualFX.TweenSize(imageFrame, HOVER_TWEEN_INFO, targetSize)
	end

	local function updateTarget()
		if isHovering or isPressing then
			play(hoverSize)
		else
			play(originalSize)
		end
	end

	button.MouseEnter:Connect(function()
		isHovering = true
		updateTarget()
	end)

	button.MouseLeave:Connect(function()
		isHovering = false
		updateTarget()
	end)

	button.MouseButton1Down:Connect(function()
		isPressing = true
		updateTarget()
	end)

	button.MouseButton1Up:Connect(function()
		isPressing = false
		updateTarget()
	end)

	button.InputEnded:Connect(function(inputObject)
		local inputType = inputObject.UserInputType
		if inputType ~= Enum.UserInputType.MouseButton1 and inputType ~= Enum.UserInputType.Touch then
			return
		end
		isPressing = false
		updateTarget()
	end)
end

local MainHUD = {}

function MainHUD.Init()
	local currentCash = Player:GetAttribute(CASH_ATTRIBUTE_NAME)
	if typeof(currentCash) ~= "number" then
		currentCash = 0
	end
	lastCash = currentCash
	CashLabel.Text = Formatter.formatCurrency(currentCash, CASH_FORMAT_OPTIONS)
	CashLabelStroke.Text = CashLabel.Text

	CurrencyPackets.PlayerCurrencyDelta.OnClientEvent:Connect(function(payload)
		if typeof(payload) ~= "table" then
			return
		end
		local currencyName = payload.CurrencyName
		if currencyName ~= CASH_ATTRIBUTE_NAME then
			return
		end
		local amount = payload.Amount
		if typeof(amount) ~= "number" or amount <= 0 then
			return
		end
		local residentNameValue = payload.ResidentName
		local resolvedResidentName = if typeof(residentNameValue) == "string" and residentNameValue ~= ""
			then residentNameValue
			else nil
		pendingCashIncrease += amount
		showCashPop(amount, resolvedResidentName)
	end)

	local function updateBillDisplay(plotTax: number, electricityCost: number, foodCost: number, totalCost: number)
		PlotTaxLabel.Text = Formatter.formatCurrency(plotTax, CASH_FORMAT_OPTIONS)
		ElectricLabel.Text = Formatter.formatCurrency(electricityCost, CASH_FORMAT_OPTIONS)
		FoodLabel.Text = Formatter.formatCurrency(foodCost, CASH_FORMAT_OPTIONS)
		local totalText = Formatter.formatCurrency(totalCost, CASH_FORMAT_OPTIONS)
		TotalLabel.Text = totalText
	end

	local function updateDueLabel(_dueClockTime: number?, timeRemaining: number?, outstandingTotal: number?)
		-- Always use timeRemaining for consistency (ignore dueClockTime to avoid calculation drift)
		TimeTextLabel.Text = resolveNextBillingLabel(timeRemaining, outstandingTotal)
	end

	-- Listen for real-time billing updates from server
	BillingPackets.BillingBreakdownUpdate.OnClientEvent:Connect(function(payload)
		if typeof(payload) ~= "table" then
			return
		end

		local plotTax = payload.PlotTax
		local electricityCost = payload.Electric
		local foodCost = payload.Food
		local outstandingTotal = payload.OutstandingTotal
		local totalCost = payload.Total
		local dueClockTime = payload.DueClockTime
		local timeRemaining = payload.TimeRemaining

		updateDueLabel(dueClockTime, timeRemaining, outstandingTotal)

		-- Only update bill breakdown if the bill frame is currently visible
		if BillFrame.Visible then
			updateBillDisplay(plotTax, electricityCost, foodCost, totalCost)
		end
	end)

	BillContext.Toggle.Pressed:Connect(function()
		BillFrame.Visible = not BillFrame.Visible
		if not BillFrame.Visible then
			return
		end

		local payload = BillingPackets.RequestBillingInfo:Fire()
		if typeof(payload) ~= "table" then
			return
		end

		local plotTax = payload.PlotTax
		local electricityCost = payload.Electric
		local foodCost = payload.Food
		local outstandingTotal = payload.OutstandingTotal
		local totalCost = payload.Total
		local dueClockTime = payload.DueClockTime
		local timeRemaining = payload.TimeRemaining

		updateDueLabel(dueClockTime, timeRemaining, outstandingTotal)

		updateBillDisplay(plotTax, electricityCost, foodCost, totalCost)
	end)

	BillContext.PayAction.Pressed:Connect(function()
		local success, message = BillingPackets.PayBillRequest:Fire()
		if success then
			print(message or "Bill paid successfully")
		else
			warn(message or "Unable to process bill payment")
		end
	end)

	-- Debounce settings for billing info requests
	local BILLING_REQUEST_DEBOUNCE = 0.5 -- Prevent requests more often than twice per second

	-- Function to request and update billing info with debouncing
	local function requestAndUpdateBillingInfo()
		Debounce.RunIfAvailable("BillingInfoRequest", BILLING_REQUEST_DEBOUNCE, function()
			local payload = BillingPackets.RequestBillingInfo:Fire()
			if typeof(payload) == "table" then
				updateDueLabel(payload.DueClockTime, payload.TimeRemaining, payload.OutstandingTotal)
			end
		end, Player.UserId)
	end

	-- Initial request on script load
	task.defer(requestAndUpdateBillingInfo)

	-- Listen for when player claims or loses a plot
	Player:GetAttributeChangedSignal("OwnedPlotIndex"):Connect(function()
		local plotIndex = Player:GetAttribute("OwnedPlotIndex")
		if plotIndex ~= nil then
			-- Player claimed a plot, request billing info (debounced)
			requestAndUpdateBillingInfo()
		else
			-- Player lost their plot, reset to default
			TimeTextLabel.Text = resolveNextBillingLabel(nil, nil)
		end
	end)

	Player:GetAttributeChangedSignal(CASH_ATTRIBUTE_NAME):Connect(function()
		local newValue = Player:GetAttribute(CASH_ATTRIBUTE_NAME)
		if typeof(newValue) ~= "number" then
			newValue = 0
		end
		CashLabel.Text = Formatter.formatCurrency(newValue, CASH_FORMAT_OPTIONS)
		CashLabelStroke.Text = CashLabel.Text
		if not hasProcessedInitialAttribute then
			hasProcessedInitialAttribute = true
			if pendingCashIncrease == 0 then
				lastCash = newValue
				return
			end
		end
		if lastCash then
			local difference = newValue - lastCash
			if difference > 0 then
				if pendingCashIncrease > 0 then
					if difference >= pendingCashIncrease then
						difference -= pendingCashIncrease
						pendingCashIncrease = 0
					else
						pendingCashIncrease -= difference
						difference = 0
					end
				end
				if difference > 0 then
					showCashPop(difference, nil)
				end
			elseif difference < 0 then
				showCashDeductionPop(math.abs(difference))
			end
		end
		lastCash = newValue
	end)

	for _, button in ipairs({ BuildButton, BillsButton, ExpandButton, SettingsButton }) do
		configureButtonVisuals(button)
	end

	TimeTextLabel.Text = resolveNextBillingLabel(nil, nil)
end

function MainHUD.Show()
	-- Code to show the MainHUD goes here
	BottomRight.Visible = true
	HUDBottomRightEnabled.Value = true
end

function MainHUD.Hide()
	-- Code to hide the MainHUD goes here
	BottomRight.Visible = false
	HUDBottomRightEnabled.Value = false
end

return MainHUD
