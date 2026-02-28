--!strict
-- StarterPlayerScripts/Client/UserInterface/MainHUD.lua

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Formatter = require(ReplicatedStorage.Shared.Utilities.Formatter)
local VisualFX = require(ReplicatedStorage.Shared.Utilities.VisualFX)
local CurrencyPackets = require(ReplicatedStorage.Network.CurrencyPackets)
local BillingConstants = require(ReplicatedStorage.Shared.Definitions.BillingConstants)
local SoundtrackManager = require(script.Parent.Parent.Modules.SoundtrackManager)
local ReviewsUI = require(script.Parent.ReviewsUI)
local ReputationUI = require(script.Parent.ReputationUI)
local ProfileUI = require(script.Parent.ProfileUI)
local BillUI = require(script.Parent.BillUI)
local AchievementUI = require(script.Parent.AchievementUI)
local DailyRewardUI = require(script.Parent.DailyRewardUI)
local SeasonalEventUI = require(script.Parent.SeasonalEventUI)
local PlotExpansion = require(script.Parent.Parent.Modules.PlotExpansion)

local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")

local AssetsFolder = ReplicatedStorage:WaitForChild("Assets")
local InterfacesTemplatesFolder = AssetsFolder:WaitForChild("InterfacesTemplates")
local CancelButtonTemplate = InterfacesTemplatesFolder:WaitForChild("CancelButton") :: TextButton

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

local HUDBottomRightEnabled = ensureQueryBool("HUDBottomRightEnabled", true)
local PlotBuilderEnabled = ensureQueryBool("PlotBuilderEnabled", false)
local PlotExpansionEnabled = ensureQueryBool("PlotExpansionEnabled", false)
local LevelUpOverlayActive = ensureQueryBool("LevelUpOverlayActive", false)

local MainHUDGui = PlayerGui:WaitForChild("MainHUD") :: ScreenGui
local BottomRight = MainHUDGui:WaitForChild("BottomRight") :: Frame
local TopRight = MainHUDGui:WaitForChild("TopRight")
local TextFrame = TopRight:WaitForChild("TextFrame") :: Frame
local CashLabel = TextFrame:WaitForChild("CashLabel") :: TextLabel
local IncomePerSecondLabel = TopRight:WaitForChild("IncomePerSecondLabel") :: TextLabel
local function setButtonText(button: GuiButton, text: string)
	if button:IsA("TextButton") then
		button.Text = text
		return
	end

	local textLabel = button:FindFirstChild("Text")
	if textLabel and textLabel:IsA("TextLabel") then
		textLabel.Text = text
	end
end

local BuildButton = BottomRight:WaitForChild("BuildButton") :: GuiButton
-- ExpandButton moved into PlotBuilder menu; this slot now hosts ProfileButton
local ProfileButton = BottomRight:WaitForChild("ProfileButton") :: GuiButton
local ReviewsButton = BottomRight:WaitForChild("ReviewsButton") :: GuiButton
local BillsButton = BottomRight:WaitForChild("BillsButton") :: GuiButton
local ReputationButton = (function(): GuiButton
	local existing = BottomRight:FindFirstChild("ReputationButton")
	if existing and existing:IsA("GuiButton") then
		return existing
	end
	local button = ReviewsButton:Clone()
	button.Name = "ReputationButton"
	setButtonText(button, "Reputation")
	button.LayoutOrder = ReviewsButton.LayoutOrder + 1
	button.Parent = BottomRight
	return button
end)()
local AchievementsButton = (function(): GuiButton
	local existing = BottomRight:FindFirstChild("AchievementsButton")
	if existing and existing:IsA("GuiButton") then
		return existing
	end
	local button = ReviewsButton:Clone()
	button.Name = "AchievementsButton"
	setButtonText(button, "Achievements")
	button.LayoutOrder = math.max(BillsButton.LayoutOrder, ReputationButton.LayoutOrder) + 1
	button.Parent = BottomRight
	return button
end)()
local DailyRewardsButton = (function(): GuiButton
	local existing = BottomRight:FindFirstChild("DailyRewardsButton")
	if existing and existing:IsA("GuiButton") then
		return existing
	end
	local button = ReviewsButton:Clone()
	button.Name = "DailyRewardsButton"
	setButtonText(button, "Daily Rewards")
	button.LayoutOrder = AchievementsButton.LayoutOrder + 1
	button.Parent = BottomRight
	return button
end)()
local SeasonsButton = (function(): GuiButton
	local existing = BottomRight:FindFirstChild("SeasonsButton")
	if existing and existing:IsA("GuiButton") then
		return existing
	end
	local button = ReviewsButton:Clone()
	button.Name = "SeasonsButton"
	setButtonText(button, "Seasons")
	button.LayoutOrder = DailyRewardsButton.LayoutOrder + 1
	button.Parent = BottomRight
	return button
end)()
local NotifierSymbol = BillsButton:FindFirstChild("NotifierSymbol") :: ImageLabel? -- Notifier for bill due
local ProgressionBar = MainHUDGui:WaitForChild("ProgressionBar") :: Frame
local ProgressionForeground = ProgressionBar:WaitForChild("Foreground") :: Frame
local ProgressionBarFill = ProgressionForeground:WaitForChild("Bar") :: Frame
local XPLabel = ProgressionBar:WaitForChild("XPLabel") :: TextLabel
local LevelLabel = ProgressionBar:WaitForChild("LevelLabel") :: TextLabel

local function syncBottomRightVisibility()
	BottomRight.Visible = HUDBottomRightEnabled.Value
end

syncBottomRightVisibility()

HUDBottomRightEnabled:GetPropertyChangedSignal("Value"):Connect(syncBottomRightVisibility)

local function setBottomRightEnabled(enabled: boolean)
	if HUDBottomRightEnabled.Value == enabled then
		syncBottomRightVisibility()
		return
	end
	HUDBottomRightEnabled.Value = enabled
end

local function isPlotExpansionActive(): boolean
	return PlotExpansionEnabled.Value == true
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

local rng = Random.new()
local CASH_ATTRIBUTE_NAME = "Cash"
local CASH_FORMAT_OPTIONS = {
	currencySymbol = "$",
	useAbbreviation = true,
	decimalPlaces = 2,
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

local function configureButtonVisuals(button: GuiButton)
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
	PlotExpansionEnabled.Changed:Connect(function()
		syncMainHudEnabledState()
		syncPlotExpansionCancelState()
	end)

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

	ReviewsButton.Activated:Connect(function()
		ReputationUI.SetVisible(false)
		ReviewsUI.Toggle()
	end)

	ReputationButton.Activated:Connect(function()
		ReviewsUI.SetVisible(false)
		ReputationUI.Toggle()
	end)

	AchievementsButton.Activated:Connect(function()
		AchievementUI.Toggle()
	end)

	DailyRewardsButton.Activated:Connect(function()
		DailyRewardUI.Toggle()
	end)

	SeasonsButton.Activated:Connect(function()
		SeasonalEventUI.Toggle()
	end)

	PlotBuilderEnabled.Changed:Connect(function()
		if PlotBuilderEnabled.Value then
			MainHUD.Hide()
		else
			MainHUD.Show()
		end
	end)
	local function handleOwnedPlotChanged()
		local plotIndex = Player:GetAttribute("OwnedPlotIndex")
		if plotIndex ~= nil then
			setBottomRightEnabled(true)
			return
		end
		setBottomRightEnabled(false)
	end

	handleOwnedPlotChanged()
	Player:GetAttributeChangedSignal("OwnedPlotIndex"):Connect(handleOwnedPlotChanged)

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

	for _, button in ipairs({ BuildButton, ReviewsButton, ReputationButton, ProfileButton, BillsButton, AchievementsButton, DailyRewardsButton, SeasonsButton }) do
		configureButtonVisuals(button)
	end

	local function handleProfileButtonActivated()
		ReviewsUI.SetVisible(false)
		ReputationUI.SetVisible(false)
		ProfileUI.Toggle()
	end

	ProfileButton.Activated:Connect(handleProfileButtonActivated)

	-- Billing system: Listen to BillDue attribute
	local notifierTween = nil
	local function updateBillNotifier()
		if not NotifierSymbol then
			return
		end
		local billDue = Player:GetAttribute(BillingConstants.BillDueAttribute) == true
		NotifierSymbol.Visible = billDue

		-- Add pulsing tween animation when bill is due
		if billDue then
			if notifierTween then
				notifierTween:Cancel()
			end

			local tweenInfo = TweenInfo.new(
				0.6, -- Duration
				Enum.EasingStyle.Quad,
				Enum.EasingDirection.InOut,
				-1, -- Repeat infinitely
				true -- Reverse
			)

			notifierTween = TweenService:Create(NotifierSymbol, tweenInfo, {
				Size = UDim2.fromScale(NotifierSymbol.Size.X.Scale * 1.2, NotifierSymbol.Size.Y.Scale * 1.2),
				Rotation = 15,
			})
			notifierTween:Play()
		else
			-- Stop tween and reset when bill is paid
			if notifierTween then
				notifierTween:Cancel()
				NotifierSymbol.Size = UDim2.fromScale(1, 1)
				NotifierSymbol.Rotation = 0
			end
		end
	end

	updateBillNotifier()
	Player:GetAttributeChangedSignal(BillingConstants.BillDueAttribute):Connect(updateBillNotifier)

	-- Bills button activated: Toggle BillUI
	BillsButton.Activated:Connect(function()
		BillUI.Toggle()
	end)
end

function MainHUD.Show()
	setBottomRightEnabled(true)
end

function MainHUD.Hide()
	setBottomRightEnabled(false)
end

return MainHUD
