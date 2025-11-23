--!strict
-- StarterPlayerScripts/Client/UserInterface/MainHUD.lua

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local Formatter = require(ReplicatedStorage.Shared.Utilities.Formatter)
local TimeScale = require(ReplicatedStorage.Shared.Utilities.TimeScale)
local VisualFX = require(ReplicatedStorage.Shared.Utilities.VisualFX)
local Debounce = require(ReplicatedStorage.Shared.Utilities.Debounce)
local CurrencyPackets = require(ReplicatedStorage.Network.CurrencyPackets)
local BillingPackets = require(ReplicatedStorage.Network.BillingPackets)
local SoundtrackManager = require(script.Parent.Parent.Modules.SoundtrackManager)
local ReviewsUI = require(script.Parent.ReviewsUI)
local PlotExpansion = require(script.Parent.Parent.Modules.PlotExpansion)
local ProfilePanel = require(script.Parent.ProfilePanel)

local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")

local AssetsFolder = ReplicatedStorage:WaitForChild("Assets")
local InterfacesTemplatesFolder = AssetsFolder:WaitForChild("InterfacesTemplates")
local CancelButtonTemplate = InterfacesTemplatesFolder:WaitForChild("CancelButton") :: TextButton

local InputContextsFolder = PlayerGui:WaitForChild("InputContexts")
local BillContext = InputContextsFolder:WaitForChild("BillContext")

local ActiveQueryFolder = PlayerGui:FindFirstChild("ActiveQuery")
if not ActiveQueryFolder then
	ActiveQueryFolder = Instance.new("Folder")
	ActiveQueryFolder.Name = "ActiveQuery"
	ActiveQueryFolder.Parent = PlayerGui
end

local function ensureQueryBool(name: string, defaultValue: boolean): BoolValue
	local existing = ActiveQueryFolder:FindFirstChild(name)
	if existing and existing:IsA("BoolValue") then
		return existing
	end
	local value = Instance.new("BoolValue")
	value.Name = name
	value.Value = defaultValue
	value.Parent = ActiveQueryFolder
	return value
end

local HUDBottomRightEnabled = ActiveQueryFolder:FindFirstChild("HUDBottomRightEnabled") :: BoolValue
local PlotBuilderEnabled = ActiveQueryFolder:FindFirstChild("PlotBuilderEnabled") :: BoolValue
local PlotExpansionEnabled = ActiveQueryFolder:FindFirstChild("PlotExpansionEnabled") :: BoolValue?
local LevelUpOverlayActive = ensureQueryBool("LevelUpOverlayActive", false)

local MainHUDGui = PlayerGui:WaitForChild("MainHUD") :: ScreenGui
local BillFrame = MainHUDGui:WaitForChild("BillFrame") :: Frame
local BillPanel = BillFrame:WaitForChild("BillPanel")
local ItemsContainer = BillPanel:WaitForChild("ItemsContainer")
local PlotTaxFrame = ItemsContainer:WaitForChild("PlotTaxFrame")
local ElectricityFrame = ItemsContainer:WaitForChild("ElectricityFrame")
local OverdueFrame = ItemsContainer:WaitForChild("OverdueFrame")
local TotalFrame = BillPanel:WaitForChild("TotalFrame")
local PlotTaxAmountLabel = PlotTaxFrame:WaitForChild("TextLabel") :: TextLabel
local ElectricAmountLabel = ElectricityFrame:WaitForChild("TextLabel") :: TextLabel
local OverdueAmountLabel = OverdueFrame:WaitForChild("TextLabel") :: TextLabel

-- Dynamic Frame Creation for Water and Internet
local WaterFrame = ItemsContainer:FindFirstChild("WaterFrame") :: Frame?
if not WaterFrame then
	local clone = ElectricityFrame:Clone() :: Frame
	clone.Name = "WaterFrame"
	clone.LayoutOrder = (ElectricityFrame :: Frame).LayoutOrder + 1
	local titleLabel = clone:FindFirstChild("TitleLabel")
		or clone:FindFirstChild("Label")
		or clone:FindFirstChild("Title")
	if titleLabel and titleLabel:IsA("TextLabel") then
		titleLabel.Text = "Water"
	end
	clone.Parent = ItemsContainer
	WaterFrame = clone
end
local WaterAmountLabel = (WaterFrame :: Frame):WaitForChild("TextLabel") :: TextLabel

local InternetFrame = ItemsContainer:FindFirstChild("InternetFrame") :: Frame?
if not InternetFrame then
	local clone = ElectricityFrame:Clone() :: Frame
	clone.Name = "InternetFrame"
	clone.LayoutOrder = (ElectricityFrame :: Frame).LayoutOrder + 2
	local titleLabel = clone:FindFirstChild("TitleLabel")
		or clone:FindFirstChild("Label")
		or clone:FindFirstChild("Title")
	if titleLabel and titleLabel:IsA("TextLabel") then
		titleLabel.Text = "Internet"
	end
	clone.Parent = ItemsContainer
	InternetFrame = clone
end
local InternetAmountLabel = (InternetFrame :: Frame):WaitForChild("TextLabel") :: TextLabel

local TotalRow = TotalFrame:WaitForChild("TotalRow")
local TotalAmountLabel = TotalRow:WaitForChild("TotalLabel") :: TextLabel

local BottomRight = MainHUDGui:WaitForChild("BottomRight") :: Frame
local TopRight = MainHUDGui:WaitForChild("TopRight")
local TextFrame = TopRight:WaitForChild("TextFrame") :: Frame
local CashLabel = TextFrame:WaitForChild("CashLabel") :: TextLabel
local IncomePerSecondLabel = TopRight:WaitForChild("IncomePerSecondLabel") :: TextLabel
local BuildButton = BottomRight:WaitForChild("BuildButton") :: TextButton
local BillsButton = BottomRight:WaitForChild("BillsButton") :: TextButton
-- ExpandButton moved into PlotBuilder menu; this slot now hosts ProfileButton
local ProfileButton = BottomRight:WaitForChild("ProfileButton") :: TextButton
local ReviewsButton = BottomRight:WaitForChild("ReviewsButton") :: TextButton
local BillImageFrame = BillsButton:WaitForChild("Image") :: Frame
local TimeTextFrame = BillImageFrame:WaitForChild("TimeTextFrame") :: Frame
local TimeTextLabel = TimeTextFrame:WaitForChild("TimeTextLabel") :: TextLabel
local ProgressionBar = MainHUDGui:WaitForChild("ProgressionBar") :: Frame
local ProgressionForeground = ProgressionBar:WaitForChild("Foreground") :: Frame
local ProgressionBarFill = ProgressionForeground:WaitForChild("Bar") :: Frame
local XPLabel = ProgressionBar:WaitForChild("XPLabel") :: TextLabel
local LevelLabel = ProgressionBar:WaitForChild("LevelLabel") :: TextLabel

local function ensureProfilePanelFrame(): Frame
	local existing = MainHUDGui:FindFirstChild("ProfilePanelFrame")
	if existing and existing:IsA("Frame") then
		existing.BackgroundTransparency = 0
		existing.BackgroundColor3 = Color3.fromRGB(20, 26, 46)
		existing.BorderSizePixel = 0
		existing.Visible = false
		existing.Active = false
		existing.Size = UDim2.fromScale(1, 1)
		existing.ZIndex = math.max(existing.ZIndex, 10)
		return existing
	end

	local frame = Instance.new("Frame")
	frame.Name = "ProfilePanelFrame"
	frame.BackgroundTransparency = 0
	frame.BackgroundColor3 = Color3.fromRGB(20, 26, 46)
	frame.BorderSizePixel = 0
	frame.Visible = false
	frame.Active = false
	frame.Size = UDim2.fromScale(1, 1)
	frame.ZIndex = 10
	frame.Parent = MainHUDGui
	return frame
end

local ProfilePanelFrame = ensureProfilePanelFrame()

local function isPlotExpansionActive(): boolean
	return PlotExpansionEnabled ~= nil and PlotExpansionEnabled.Value == true
end

local function shouldMainHudBeEnabled(): boolean
	if LevelUpOverlayActive.Value then
		return false
	end
	if isPlotExpansionActive() then
		return false
	end
	return true
end

local function syncMainHudEnabledState()
	MainHUDGui.Enabled = shouldMainHudBeEnabled()
end

local function syncLevelUpSuppression()
	syncMainHudEnabledState()
end

local PlotExpansionCancelGui: ScreenGui? = nil
local PlotExpansionCancelButton: TextButton? = nil

local function ensurePlotExpansionCancelGui(): ScreenGui
	if PlotExpansionCancelGui and PlotExpansionCancelGui.Parent then
		return PlotExpansionCancelGui
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = "PlotExpansionControls"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = MainHUDGui.DisplayOrder + 1
	gui.Enabled = false
	gui.Parent = PlayerGui

	local container = Instance.new("Frame")
	container.Name = "CancelContainer"
	container.AnchorPoint = Vector2.new(1, 1)
	container.Position = UDim2.new(1, -40, 1, -20)
	container.Size = UDim2.fromOffset(260, 64)
	container.BackgroundTransparency = 1
	container.BorderSizePixel = 0
	container.Visible = true
	container.Parent = gui

	local button = CancelButtonTemplate:Clone()
	button.Name = "PlotExpansionCancelButton"
	button.Parent = container
	button.Position = UDim2.fromScale(0.5, 0)
	button.Activated:Connect(function()
		if isPlotExpansionActive() then
			PlotExpansion.Hide()
		end
	end)

	local keyHint = button:FindFirstChild("KeyHint")
	if keyHint and keyHint:IsA("TextLabel") then
		keyHint.Visible = true
	end

	PlotExpansionCancelGui = gui
	PlotExpansionCancelButton = button
	return gui
end

local function syncPlotExpansionCancelState()
	local gui = ensurePlotExpansionCancelGui()
	local isActive = isPlotExpansionActive()
	gui.Enabled = isActive
	if PlotExpansionCancelButton then
		PlotExpansionCancelButton.Active = isActive
		PlotExpansionCancelButton.AutoButtonColor = isActive
		PlotExpansionCancelButton.Visible = isActive
	end
end

local INCOME_RATE_ATTRIBUTE_NAME = "TenantIncomePerSecond"

local FoodFrame = ItemsContainer:FindFirstChild("FoodFrame")
if FoodFrame and FoodFrame:IsA("Frame") then
	FoodFrame.Visible = false
end

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

local MIN_INCOME_DISPLAY = 0.01
local XP_TWEEN_INFO = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local XP_NUMBER_FORMAT = {
	decimalPlaces = 0,
	useCommas = true,
}
local xpTween: Tween? = nil

local function formatIncomePerSecond(amount: number): string
	if typeof(amount) ~= "number" or amount ~= amount then
		return "$0/sec"
	end
	local sanitized = math.max(amount, 0)
	if sanitized == 0 then
		return "$0/sec"
	end
	if sanitized < MIN_INCOME_DISPLAY then
		return "+<$0.01/sec"
	end
	local formatted = Formatter.formatCurrency(sanitized, {
		currencySymbol = "$",
		decimalPlaces = 2,
	})
	return string.format("+%s/sec", formatted)
end

local function formatXpValue(value: number): string
	return Formatter.formatNumber(value, XP_NUMBER_FORMAT)
end

local function updateProgressionDisplay()
	local levelAttr = Player:GetAttribute("PlayerLevel")
	local xpIntoAttr = Player:GetAttribute("PlayerXPIntoLevel")
	local xpForNextAttr = Player:GetAttribute("PlayerXPForNext")

	local level = if typeof(levelAttr) == "number" then math.max(1, math.floor(levelAttr + 0.5)) else 1
	local xpIntoLevel = if typeof(xpIntoAttr) == "number" then math.max(0, xpIntoAttr) else 0
	local xpForNext = if typeof(xpForNextAttr) == "number" then math.max(0, xpForNextAttr) else 0
	local isMaxLevel = xpForNext <= 0

	LevelLabel.Text = string.format("Lvl %d", level)
	if isMaxLevel then
		XPLabel.Text = formatXpValue(xpIntoLevel) .. " XP"
	else
		XPLabel.Text = string.format("%s/%s", formatXpValue(xpIntoLevel), formatXpValue(xpForNext))
	end

	local targetRatio = if isMaxLevel then 1 else math.clamp(xpIntoLevel / math.max(xpForNext, 1), 0, 1)
	local targetSize = UDim2.fromScale(targetRatio, 1)
	if xpTween then
		xpTween:Cancel()
		xpTween = nil
	end
	if ProgressionBarFill.Size == targetSize then
		return
	end
	local tween = TweenService:Create(ProgressionBarFill, XP_TWEEN_INFO, {
		Size = targetSize,
	})
	xpTween = tween
	tween:Play()
end

local function updateIncomePerSecondLabel()
	local rawValue = Player:GetAttribute(INCOME_RATE_ATTRIBUTE_NAME)
	IncomePerSecondLabel.Text = formatIncomePerSecond(if typeof(rawValue) == "number" then rawValue else 0)
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

local function showCashPop(delta: number, _targetResidentName: string?)
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

	button.Activated:Connect(function()
		SoundtrackManager.PlayButtonClick()
	end)
end

local MainHUD = {}

function MainHUD.Init()
	syncLevelUpSuppression()
	LevelUpOverlayActive.Changed:Connect(syncLevelUpSuppression)

	syncPlotExpansionCancelState()
	if PlotExpansionEnabled then
		PlotExpansionEnabled.Changed:Connect(function()
			syncMainHudEnabledState()
			syncPlotExpansionCancelState()
		end)
	else
		warn("[MainHUD] PlotExpansionEnabled BoolValue missing; HUD suppression may be incorrect.")
	end

	local currentCash = Player:GetAttribute(CASH_ATTRIBUTE_NAME)
	if typeof(currentCash) ~= "number" then
		currentCash = 0
	end
	lastCash = currentCash
	CashLabel.Text = Formatter.formatCurrency(currentCash, CASH_FORMAT_OPTIONS)
	updateIncomePerSecondLabel()
	Player:GetAttributeChangedSignal(INCOME_RATE_ATTRIBUTE_NAME):Connect(updateIncomePerSecondLabel)

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

	local BILLING_TOGGLE_DEBOUNCE = 0.3
	local BILLING_PAY_DEBOUNCE = 0.5
	local lastFormattedClockTime: string? = nil
	local needsClockUpdate = false
	local graceCountdownDeadline: number? = nil
	local graceCountdownConnection: RBXScriptConnection? = nil
	local lastOutstandingTotal: number? = nil
	local lastTimeRemainingSeconds: number? = nil
	local lastDueClockTime: number? = nil

	local function stopGraceCountdown()
		if graceCountdownConnection then
			graceCountdownConnection:Disconnect()
			graceCountdownConnection = nil
		end
		graceCountdownDeadline = nil
	end

	local function formatGraceCountdownLabel(timeRemainingSeconds: number): string
		local remaining = math.max(math.ceil(timeRemainingSeconds), 0)
		local minutes = math.floor(remaining / 60)
		local seconds = remaining % 60
		return string.format("grace %d:%02d", minutes, seconds)
	end

	local function resolveNextBillingLabel(
		timeRemainingSeconds: number?,
		outstandingTotal: number?,
		isGraceActive: boolean,
		isOverdueActive: boolean
	): string
		local resolvedOutstanding = if typeof(outstandingTotal) == "number" then outstandingTotal else 0

		if isOverdueActive then
			return "overdue"
		end

		if isGraceActive then
			if typeof(timeRemainingSeconds) == "number" and timeRemainingSeconds > 0 then
				return formatGraceCountdownLabel(timeRemainingSeconds)
			end
			if resolvedOutstanding > 0 then
				return "due"
			end
			return "grace 0:00"
		end

		if typeof(timeRemainingSeconds) == "number" and timeRemainingSeconds <= 0 and resolvedOutstanding > 0 then
			return "due"
		end

		if typeof(timeRemainingSeconds) == "number" and timeRemainingSeconds > 0 then
			local currentClock = TimeScale.GetClockTime()
			local additionalHours = TimeScale.GameHoursFromRealDelta(timeRemainingSeconds)
			local formattedTime = formatClockLabel(currentClock + additionalHours)

			if not lastFormattedClockTime then
				lastFormattedClockTime = formattedTime
			end
			if needsClockUpdate then
				lastFormattedClockTime = formattedTime
			end
			return lastFormattedClockTime or formattedTime
		end

		return "-"
	end

	local function syncGraceCountdown(timeRemainingSeconds: number?, isGraceActive: boolean, isOverdueActive: boolean)
		if isOverdueActive or not isGraceActive then
			stopGraceCountdown()
			return
		end
		if typeof(timeRemainingSeconds) ~= "number" or timeRemainingSeconds <= 0 then
			stopGraceCountdown()
			return
		end

		graceCountdownDeadline = os.clock() + timeRemainingSeconds

		if graceCountdownConnection then
			return
		end

		graceCountdownConnection = RunService.Heartbeat:Connect(function()
			local deadline = graceCountdownDeadline
			if not deadline then
				stopGraceCountdown()
				return
			end

			local remaining = deadline - os.clock()
			if remaining <= 0 then
				stopGraceCountdown()
				local overdueActive = Player:GetAttribute("BillingOverdueActive") == true
				if overdueActive then
					TimeTextLabel.Text = "overdue"
					return
				end
				local outstanding = if typeof(lastOutstandingTotal) == "number" then lastOutstandingTotal else 0
				if outstanding > 0 then
					TimeTextLabel.Text = "due"
				else
					TimeTextLabel.Text = "grace 0:00"
				end
				return
			end

			TimeTextLabel.Text = formatGraceCountdownLabel(remaining)
		end)
	end

	local function clampAmount(value: any): number
		if typeof(value) ~= "number" or not value then
			return 0
		end
		return value
	end

	local function resolveOverdueInterest(
		plotTax: number?,
		electricityCost: number?,
		waterCost: number?,
		internetCost: number?,
		totalCost: number?,
		providedOverdue: number?
	): number
		if typeof(providedOverdue) == "number" then
			return providedOverdue
		end

		local total = if typeof(totalCost) == "number" then totalCost else 0
		if total <= 0 then
			return 0
		end

		local baseSum = 0
		if typeof(plotTax) == "number" then
			baseSum += plotTax
		end
		if typeof(electricityCost) == "number" then
			baseSum += electricityCost
		end
		if typeof(waterCost) == "number" then
			baseSum += waterCost
		end
		if typeof(internetCost) == "number" then
			baseSum += internetCost
		end

		local interest = total - baseSum
		if interest <= 0 then
			return 0
		end

		return interest
	end

	local function updateBillDisplay(
		plotTax: number?,
		electricityCost: number?,
		waterCost: number?,
		internetCost: number?,
		overdueInterest: number?,
		totalCost: number?
	)
		local sanitizedPlotTax = clampAmount(plotTax)
		local sanitizedElectric = clampAmount(electricityCost)
		local sanitizedWater = clampAmount(waterCost)
		local sanitizedInternet = clampAmount(internetCost)
		local sanitizedOverdue = clampAmount(overdueInterest)
		local sanitizedTotal = clampAmount(totalCost)

		PlotTaxAmountLabel.Text = Formatter.formatCurrency(sanitizedPlotTax, CASH_FORMAT_OPTIONS)
		ElectricAmountLabel.Text = Formatter.formatCurrency(sanitizedElectric, CASH_FORMAT_OPTIONS)
		WaterAmountLabel.Text = Formatter.formatCurrency(sanitizedWater, CASH_FORMAT_OPTIONS)
		InternetAmountLabel.Text = Formatter.formatCurrency(sanitizedInternet, CASH_FORMAT_OPTIONS)
		OverdueAmountLabel.Text = Formatter.formatCurrency(sanitizedOverdue, CASH_FORMAT_OPTIONS)
		TotalAmountLabel.Text = Formatter.formatCurrency(sanitizedTotal, CASH_FORMAT_OPTIONS)
	end

	local function updateDueLabel(
		dueClockTime: number?,
		timeRemaining: number?,
		outstandingTotal: number?,
		isNeedClockUpdate: boolean
	)
		lastDueClockTime = dueClockTime
		if typeof(timeRemaining) == "number" then
			lastTimeRemainingSeconds = timeRemaining
		else
			lastTimeRemainingSeconds = nil
		end
		if typeof(outstandingTotal) == "number" then
			lastOutstandingTotal = outstandingTotal
		else
			lastOutstandingTotal = nil
		end

		local graceActive = Player:GetAttribute("BillingGraceActive") == true
		local overdueActive = Player:GetAttribute("BillingOverdueActive") == true
		if overdueActive then
			graceActive = false
		end

		needsClockUpdate = if graceActive then false else isNeedClockUpdate

		TimeTextLabel.Text = resolveNextBillingLabel(timeRemaining, outstandingTotal, graceActive, overdueActive)
		syncGraceCountdown(timeRemaining, graceActive, overdueActive)
	end

	-- Listen for real-time billing updates from server
	BillingPackets.BillingBreakdownUpdate.OnClientEvent:Connect(function(payload)
		if typeof(payload) ~= "table" then
			return
		end

		local plotTax = payload.PlotTax
		local electricityCost = payload.Electric
		local waterCost = payload.Water
		local internetCost = payload.Internet
		local outstandingTotal = payload.OutstandingTotal
		local totalCost = payload.Total
		local overdueInterest = resolveOverdueInterest(
			plotTax,
			electricityCost,
			waterCost,
			internetCost,
			totalCost,
			rawget(payload, "Overdue")
		)
		local dueClockTime = payload.DueClockTime
		local timeRemaining = payload.TimeRemaining

		updateDueLabel(dueClockTime, timeRemaining, outstandingTotal, true)

		-- Only update bill breakdown if the bill frame is currently visible
		if BillFrame.Visible then
			updateBillDisplay(plotTax, electricityCost, waterCost, internetCost, overdueInterest, totalCost)
		end
	end)

	local function requestAndUpdateBillingInfo()
		local payload = BillingPackets.RequestBillingInfo:Fire()
		if typeof(payload) ~= "table" then
			return
		end

		local plotTax = payload.PlotTax
		local electricityCost = payload.Electric
		local waterCost = payload.Water
		local internetCost = payload.Internet
		local outstandingTotal = payload.OutstandingTotal
		local totalCost = payload.Total
		local overdueInterest = resolveOverdueInterest(
			plotTax,
			electricityCost,
			waterCost,
			internetCost,
			totalCost,
			rawget(payload, "Overdue")
		)
		local dueClockTime = payload.DueClockTime
		local timeRemaining = payload.TimeRemaining

		updateDueLabel(dueClockTime, timeRemaining, outstandingTotal, false)

		if BillFrame.Visible then
			updateBillDisplay(plotTax, electricityCost, waterCost, internetCost, overdueInterest, totalCost)
		end
	end

	BillContext.Toggle.Pressed:Connect(function()
		Debounce.RunIfAvailable("BillTogglePress", BILLING_TOGGLE_DEBOUNCE, function()
			SoundtrackManager.PlayBillToggle()
			BillFrame.Visible = not BillFrame.Visible
			if BillFrame.Visible then
				ProfilePanel.Hide()
				ReviewsUI.SetVisible(false)
				requestAndUpdateBillingInfo()
			end
		end, Player.UserId)
	end)

	BillContext.PayAction.Pressed:Connect(function()
		Debounce.RunIfAvailable("BillPayPress", BILLING_PAY_DEBOUNCE, function()
			local success, message = BillingPackets.PayBillRequest:Fire()
			if success then
				SoundtrackManager.PlayBillPaid()
				print(message or "Bill paid successfully")
			else
				warn(message or "Unable to process bill payment")
			end
		end, Player.UserId)
	end)

	ReviewsButton.Activated:Connect(function()
		BillFrame.Visible = false
		ProfilePanel.Hide()
		ReviewsUI.Toggle()
	end)

	PlotBuilderEnabled.Changed:Connect(function()
		if PlotBuilderEnabled.Value then
			MainHUD.Hide()
		else
			MainHUD.Show()
		end
	end)
	-- Initial request on script load
	task.defer(requestAndUpdateBillingInfo)

	-- Listen for when player claims or loses a plot
	Player:GetAttributeChangedSignal("OwnedPlotIndex"):Connect(function()
		local plotIndex = Player:GetAttribute("OwnedPlotIndex")
		if plotIndex ~= nil then
			-- Player claimed a plot, request billing info
			requestAndUpdateBillingInfo()
		else
			-- Player lost their plot, reset to default
			stopGraceCountdown()
			TimeTextLabel.Text = resolveNextBillingLabel(
				nil,
				nil,
				Player:GetAttribute("BillingGraceActive") == true,
				Player:GetAttribute("BillingOverdueActive") == true
			)
		end
	end)

	local function onBillingAttributeChanged()
		updateDueLabel(lastDueClockTime, lastTimeRemainingSeconds, lastOutstandingTotal, false)
	end

	Player:GetAttributeChangedSignal("BillingGraceActive"):Connect(onBillingAttributeChanged)
	Player:GetAttributeChangedSignal("BillingOverdueActive"):Connect(onBillingAttributeChanged)

	Player:GetAttributeChangedSignal(CASH_ATTRIBUTE_NAME):Connect(function()
		local newValue = Player:GetAttribute(CASH_ATTRIBUTE_NAME)
		if typeof(newValue) ~= "number" then
			newValue = 0
		end
		CashLabel.Text = Formatter.formatCurrency(newValue, CASH_FORMAT_OPTIONS)
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

	updateProgressionDisplay()
	local progressionAttributes = {
		"PlayerXPIntoLevel",
		"PlayerXPForNext",
		"PlayerLevel",
	}
	for _, attributeName in ipairs(progressionAttributes) do
		Player:GetAttributeChangedSignal(attributeName):Connect(updateProgressionDisplay)
	end

	for _, button in ipairs({ BuildButton, BillsButton, ReviewsButton, ProfileButton }) do
		configureButtonVisuals(button)
	end

	local function handleProfileButtonActivated()
		if BillFrame.Visible then
			BillFrame.Visible = false
		end
		ReviewsUI.SetVisible(false)
		ProfilePanel.Toggle()
	end

	ProfileButton.Activated:Connect(handleProfileButtonActivated)
	ProfilePanel.Init(ProfilePanelFrame)

	ProfilePanel.VisibilityChanged:Connect(function(isVisible: boolean)
		if not isVisible then
			return
		end
		if BillFrame.Visible then
			BillFrame.Visible = false
		end
		ReviewsUI.SetVisible(false)
	end)

	TimeTextLabel.Text = resolveNextBillingLabel(
		nil,
		nil,
		Player:GetAttribute("BillingGraceActive") == true,
		Player:GetAttribute("BillingOverdueActive") == true
	)
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
	ProfilePanel.Hide()
end

return MainHUD
