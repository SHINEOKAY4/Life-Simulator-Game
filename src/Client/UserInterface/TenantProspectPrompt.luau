--!strict
-- StarterPlayerScripts/Client/UserInterface/TenantProspectPrompt.luau
-- Immersive modal for showcasing tenant prospects and guiding the escort workflow.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local TenantTraits = require(ReplicatedStorage.Shared.Definitions.TenantTraits)
local TenantDefinitions = require(ReplicatedStorage.Shared.Definitions.TenantDefinitions)
local Formatter = require(ReplicatedStorage.Shared.Utilities.Formatter)

export type ProspectOfferPayload = {
	ProspectId: string,
	Name: string,
	TierId: string,
	RentPerInterval: number,
	RentIntervalSeconds: number,
	LeaseSeconds: number,
	Deposit: number?,
	RentBoostPercent: number?,
	Traits: { string }?,
}

export type PromptCallbacks = {
	OnAccept: (() -> ())?,
	OnDecline: (() -> ())?,
	OnClosed: (() -> ())?,
}

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

local TenantProspectPrompt = {}

local _screenGui: ScreenGui?
local _panel: GuiObject?
local _card: GuiObject?
local _callbacks: PromptCallbacks? = nil
local _statusLabel: TextLabel?
local _instructionLabel: TextLabel?
local _acceptButton: TextButton?
local _declineButton: TextButton?
local _escortBanner: Frame?
local _currentPayload: ProspectOfferPayload?
local _busy = false

local CURRENCY_OPTIONS = {
	currencySymbol = "$",
	thousandSeparator = ",",
	decimalPlaces = 0,
}

local function ensureGui(): ScreenGui
	if _screenGui and _screenGui.Parent then
		return _screenGui
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = "TenantProspectPrompt"
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 9500
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Global
	gui.Parent = PlayerGui
	_screenGui = gui
	return gui
end

local function safeFormatCurrency(amount: number?): string
	if typeof(amount) ~= "number" then
		return "—"
	end
	local ok, formatted = pcall(function()
		return Formatter.formatCurrency(amount :: number, CURRENCY_OPTIONS)
	end)
	if ok then
		return formatted
	end
	return string.format("$%d", math.floor((amount :: number) + 0.5))
end

local function formatInterval(seconds: number): string
	if seconds >= 86400 then
		local days = math.max(1, math.floor(seconds / 86400 + 0.5))
		return string.format("every %d day%s", days, days == 1 and "" or "s")
	elseif seconds >= 3600 then
		local hours = math.max(1, math.floor(seconds / 3600 + 0.5))
		return string.format("every %d hr", hours)
	elseif seconds >= 60 then
		local minutes = math.max(1, math.floor(seconds / 60 + 0.5))
		return string.format("every %d min", minutes)
	end
	return "every few moments"
end

local function formatLease(seconds: number): string
	if seconds <= 0 then
		return "Flexible term"
	end
	local days = math.floor(seconds / 86400 + 0.5)
	if days >= 1 then
		return string.format("%d day lease", days)
	end
	local hours = math.max(1, math.floor(seconds / 3600 + 0.5))
	return string.format("%d hr lease", hours)
end

local function setButtonsEnabled(isEnabled: boolean)
	if _acceptButton then
		_acceptButton.Active = isEnabled
		_acceptButton.AutoButtonColor = isEnabled
		_acceptButton.BackgroundTransparency = isEnabled and 0 or 0.2
	end
	if _declineButton then
		_declineButton.Active = isEnabled
		_declineButton.AutoButtonColor = isEnabled
		_declineButton.BackgroundTransparency = isEnabled and 0 or 0.2
	end
end

local function setStatus(text: string?, isError: boolean?)
	if not _statusLabel then
		return
	end
	local hasText = text ~= nil and text ~= ""
	_statusLabel.Visible = hasText
	if not hasText then
		_statusLabel.Text = ""
		return
	end
	_statusLabel.Text = text or ""
	_statusLabel.TextColor3 = if isError then Color3.fromRGB(255, 145, 145) else Color3.fromRGB(189, 214, 255)
end

local function destroyPanel()
	if _panel then
		_panel:Destroy()
	end
	_panel = nil
	_card = nil
	_statusLabel = nil
	_instructionLabel = nil
	_acceptButton = nil
	_declineButton = nil
	setStatus(nil, false)
end

local function buildStatColumn(parent: Instance, labelText: string, valueText: string)
	local column = Instance.new("Frame")
	column.BackgroundTransparency = 1
	column.Size = UDim2.new(1 / 3, -6, 1, 0)
	column.Parent = parent

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamMedium
	label.TextColor3 = Color3.fromRGB(160, 175, 205)
	label.TextSize = 14
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Text = labelText
	label.Size = UDim2.new(1, 0, 0, 18)
	label.Parent = column

	local value = Instance.new("TextLabel")
	value.BackgroundTransparency = 1
	value.Font = Enum.Font.GothamBold
	value.TextColor3 = Color3.fromRGB(255, 255, 255)
	value.TextSize = 20
	value.TextXAlignment = Enum.TextXAlignment.Left
	value.Text = valueText
	value.Position = UDim2.fromOffset(0, 20)
	value.Size = UDim2.new(1, 0, 0, 24)
	value.Parent = column
end

local function populateTraits(container: Frame, traitIds: { string }?)
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	layout.Padding = UDim.new(0, 8)
	layout.Parent = container

	local anyTrait = false
	if traitIds then
		for _, traitId in ipairs(traitIds) do
			local traitDef = TenantTraits.GetTrait(traitId)
			if traitDef then
				anyTrait = true
				local entry = Instance.new("Frame")
				entry.BackgroundTransparency = 1
				entry.Size = UDim2.fromScale(1, 0)
				entry.AutomaticSize = Enum.AutomaticSize.Y
				entry.Parent = container

				local nameLabel = Instance.new("TextLabel")
				nameLabel.BackgroundTransparency = 1
				nameLabel.Font = Enum.Font.GothamBold
				nameLabel.TextSize = 15
				nameLabel.TextColor3 = traitDef.DisplayColor or Color3.fromRGB(230, 230, 230)
				nameLabel.TextXAlignment = Enum.TextXAlignment.Left
				nameLabel.Text = traitDef.Name
				nameLabel.Size = UDim2.new(1, 0, 0, 18)
				nameLabel.Parent = entry

				local descLabel = Instance.new("TextLabel")
				descLabel.BackgroundTransparency = 1
				descLabel.Font = Enum.Font.Gotham
				descLabel.TextSize = 14
				descLabel.TextColor3 = Color3.fromRGB(185, 193, 209)
				descLabel.TextXAlignment = Enum.TextXAlignment.Left
				descLabel.TextWrapped = true
				descLabel.Size = UDim2.fromScale(1, 0)
				descLabel.AutomaticSize = Enum.AutomaticSize.Y
				descLabel.Position = UDim2.fromOffset(0, 20)
				descLabel.Text = traitDef.Description
				descLabel.Parent = entry
			end
		end
	end

	if not anyTrait then
		local placeholder = Instance.new("TextLabel")
		placeholder.BackgroundTransparency = 1
		placeholder.Font = Enum.Font.Gotham
		placeholder.TextSize = 14
		placeholder.TextColor3 = Color3.fromRGB(180, 185, 205)
		placeholder.TextXAlignment = Enum.TextXAlignment.Left
		placeholder.Text = "No notable traits listed."
		placeholder.Size = UDim2.new(1, 0, 0, 20)
		placeholder.Parent = container
	end
end

local function buildViewportColumn(parent: Instance, prospectModel: Model?)
	local portrait = Instance.new("Frame")
	portrait.Size = UDim2.fromOffset(180, 220)
	portrait.BackgroundColor3 = Color3.fromRGB(22, 26, 40)
	portrait.BackgroundTransparency = 0.1
	portrait.Parent = parent
	portrait.Name = "PortraitColumn"

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 18)
	corner.Parent = portrait

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(255, 255, 255)
	stroke.Transparency = 0.85
	stroke.Thickness = 1
	stroke.Parent = portrait

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(1, 0, 0, 20)
	title.Position = UDim2.fromOffset(0, 6)
	title.Font = Enum.Font.GothamMedium
	title.TextSize = 13
	title.TextColor3 = Color3.fromRGB(190, 205, 235)
	title.Text = "Meet your prospect"
	title.Parent = portrait

	if not prospectModel then
		local placeholder = Instance.new("TextLabel")
		placeholder.BackgroundTransparency = 1
		placeholder.Size = UDim2.new(1, -20, 0, 120)
		placeholder.Position = UDim2.fromOffset(10, 60)
		placeholder.TextWrapped = true
		placeholder.Font = Enum.Font.Gotham
		placeholder.TextColor3 = Color3.fromRGB(200, 200, 210)
		placeholder.TextSize = 14
		placeholder.Text = "This tenant is shy today, but they promise to bring great vibes."
		placeholder.Parent = portrait
		return
	end

	local viewport = Instance.new("ViewportFrame")
	viewport.BackgroundTransparency = 1
	viewport.Size = UDim2.fromScale(1, 0.8)
	viewport.Position = UDim2.fromScale(0, 0.2)
	viewport.Parent = portrait

	local worldModel = Instance.new("WorldModel")
	worldModel.Parent = viewport

	local clone = prospectModel:Clone()
	clone.Parent = worldModel

	local camera = Instance.new("Camera")
	camera.Parent = viewport
	viewport.CurrentCamera = camera

	local head = clone:FindFirstChild("Head") or clone.PrimaryPart
	if head and head:IsA("BasePart") then
		local forward = (clone.PrimaryPart and clone.PrimaryPart.CFrame.LookVector) or Vector3.new(0, 0, -1)
		local camPos = head.Position + (forward * 4) + Vector3.new(0, 1.25, 0)
		camera.CFrame = CFrame.lookAt(camPos, head.Position)
	end
end

local function renderPanel(payload: ProspectOfferPayload, callbacks: PromptCallbacks?, prospectModel: Model?)
	destroyPanel()

	local gui = ensureGui()

	local overlay = Instance.new("CanvasGroup")
	overlay.Name = "ProspectOverlay"
	overlay.Size = UDim2.fromScale(1, 1)
	overlay.BackgroundColor3 = Color3.fromRGB(4, 6, 12)
	overlay.BackgroundTransparency = 0.35
	overlay.Parent = gui

	local card = Instance.new("Frame")
	card.Name = "ProspectCard"
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position = UDim2.fromScale(0.5, 0.5)
	card.Size = UDim2.fromOffset(760, 480)
	card.BackgroundColor3 = Color3.fromRGB(16, 20, 30)
	card.Parent = overlay

	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(26, 34, 60)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(13, 16, 25)),
	})
	gradient.Rotation = -20
	gradient.Parent = card

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 22)
	corner.Parent = card

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(255, 255, 255)
	stroke.Transparency = 0.7
	stroke.Thickness = 1
	stroke.Parent = card

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 26)
	padding.PaddingBottom = UDim.new(0, 26)
	padding.PaddingLeft = UDim.new(0, 28)
	padding.PaddingRight = UDim.new(0, 28)
	padding.Parent = card

	local contentRow = Instance.new("Frame")
	contentRow.BackgroundTransparency = 1
	contentRow.Size = UDim2.new(1, 0, 0, 260)
	contentRow.Parent = card

	local rowLayout = Instance.new("UIListLayout")
	rowLayout.FillDirection = Enum.FillDirection.Horizontal
	rowLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	rowLayout.Padding = UDim.new(0, 24)
	rowLayout.Parent = contentRow

	local infoColumn = Instance.new("Frame")
	infoColumn.BackgroundTransparency = 1
	infoColumn.Size = UDim2.new(1, -220, 1, 0)
	infoColumn.Parent = contentRow

	local infoLayout = Instance.new("UIListLayout")
	infoLayout.FillDirection = Enum.FillDirection.Vertical
	infoLayout.SortOrder = Enum.SortOrder.LayoutOrder
	infoLayout.Padding = UDim.new(0, 12)
	infoLayout.Parent = infoColumn

	local header = Instance.new("Frame")
	header.BackgroundTransparency = 1
	header.Size = UDim2.new(1, 0, 0, 80)
	header.LayoutOrder = 1
	header.Parent = infoColumn

	local nameLabel = Instance.new("TextLabel")
	nameLabel.BackgroundTransparency = 1
	nameLabel.Font = Enum.Font.GothamBlack
	nameLabel.TextSize = 32
	nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.Text = payload.Name
	nameLabel.Size = UDim2.new(1, 0, 0, 40)
	nameLabel.Parent = header

	local tierLabel = Instance.new("TextLabel")
	tierLabel.BackgroundTransparency = 1
	tierLabel.Font = Enum.Font.GothamMedium
	tierLabel.TextSize = 16
	tierLabel.TextXAlignment = Enum.TextXAlignment.Left
	local tierDef = TenantDefinitions.GetDefinition(payload.TierId)
	tierLabel.TextColor3 = (tierDef and tierDef.DisplayColor) or Color3.fromRGB(170, 205, 255)
	tierLabel.Text = string.format("%s tier", string.upper(payload.TierId))
	tierLabel.Position = UDim2.fromOffset(0, 38)
	tierLabel.Size = UDim2.new(1, 0, 0, 24)
	tierLabel.Parent = header

	local boostChip = Instance.new("TextLabel")
	boostChip.BackgroundColor3 = Color3.fromRGB(42, 60, 96)
	boostChip.BackgroundTransparency = 0.1
	boostChip.Font = Enum.Font.GothamBold
	boostChip.TextSize = 14
	boostChip.TextColor3 = Color3.fromRGB(144, 215, 255)
	local boostPercent = math.floor(math.max(0, (payload.RentBoostPercent or 0) * 100))
	boostChip.Text = string.format("+%d%% rent boost", boostPercent)
	boostChip.AutomaticSize = Enum.AutomaticSize.X
	boostChip.Size = UDim2.fromOffset(0, 26)
	boostChip.Position = UDim2.fromOffset(0, 64)
	boostChip.Parent = header

	local boostCorner = Instance.new("UICorner")
	boostCorner.CornerRadius = UDim.new(1, 0)
	boostCorner.Parent = boostChip

	local statsFrame = Instance.new("Frame")
	statsFrame.BackgroundTransparency = 1
	statsFrame.Size = UDim2.new(1, 0, 0, 70)
	statsFrame.LayoutOrder = 2
	statsFrame.Parent = infoColumn

	local statsLayout = Instance.new("UIListLayout")
	statsLayout.FillDirection = Enum.FillDirection.Horizontal
	statsLayout.Padding = UDim.new(0, 8)
	statsLayout.Parent = statsFrame

	buildStatColumn(statsFrame, "Rent", safeFormatCurrency(payload.RentPerInterval))
	buildStatColumn(
		statsFrame,
		"Deposit",
		safeFormatCurrency(payload.Deposit or math.floor(payload.RentPerInterval * 1.5))
	)
	buildStatColumn(statsFrame, "Interval", formatInterval(payload.RentIntervalSeconds))

	local contractFrame = Instance.new("Frame")
	contractFrame.BackgroundTransparency = 1
	contractFrame.Size = UDim2.new(1, 0, 0, 60)
	contractFrame.LayoutOrder = 3
	contractFrame.Parent = infoColumn

	local contractLabel = Instance.new("TextLabel")
	contractLabel.BackgroundTransparency = 1
	contractLabel.Font = Enum.Font.Gotham
	contractLabel.TextSize = 15
	contractLabel.TextColor3 = Color3.fromRGB(180, 190, 210)
	contractLabel.TextXAlignment = Enum.TextXAlignment.Left
	contractLabel.Text = string.format("Lease: %s", formatLease(payload.LeaseSeconds))
	contractLabel.Size = UDim2.new(1, 0, 0, 22)
	contractLabel.Parent = contractFrame

	local instruction = Instance.new("TextLabel")
	instruction.BackgroundTransparency = 1
	instruction.Font = Enum.Font.GothamMedium
	instruction.TextSize = 16
	instruction.TextColor3 = Color3.fromRGB(220, 233, 255)
	instruction.TextWrapped = true
	instruction.TextXAlignment = Enum.TextXAlignment.Left
	instruction.Size = UDim2.fromScale(1, 0)
	instruction.AutomaticSize = Enum.AutomaticSize.Y
	instruction.Text = "Guide them inside your favorite room after confirming so they know where to unpack."
	instruction.LayoutOrder = 4
	instruction.Parent = infoColumn
	_instructionLabel = instruction

	buildViewportColumn(contentRow, prospectModel)

	local traitsBlock = Instance.new("Frame")
	traitsBlock.BackgroundTransparency = 0.1
	traitsBlock.BackgroundColor3 = Color3.fromRGB(22, 28, 44)
	traitsBlock.Size = UDim2.new(1, 0, 0, 140)
	traitsBlock.Position = UDim2.fromOffset(0, 280)
	traitsBlock.Parent = card

	local traitsCorner = Instance.new("UICorner")
	traitsCorner.CornerRadius = UDim.new(0, 18)
	traitsCorner.Parent = traitsBlock

	local traitsPad = Instance.new("UIPadding")
	traitsPad.PaddingTop = UDim.new(0, 14)
	traitsPad.PaddingBottom = UDim.new(0, 14)
	traitsPad.PaddingLeft = UDim.new(0, 18)
	traitsPad.PaddingRight = UDim.new(0, 18)
	traitsPad.Parent = traitsBlock

	local traitsTitle = Instance.new("TextLabel")
	traitsTitle.BackgroundTransparency = 1
	traitsTitle.Font = Enum.Font.GothamMedium
	traitsTitle.TextSize = 16
	traitsTitle.TextColor3 = Color3.fromRGB(205, 215, 240)
	traitsTitle.TextXAlignment = Enum.TextXAlignment.Left
	traitsTitle.Text = "Tenant traits"
	traitsTitle.Size = UDim2.new(1, 0, 0, 20)
	traitsTitle.Parent = traitsBlock

	local traitsList = Instance.new("Frame")
	traitsList.BackgroundTransparency = 1
	traitsList.Size = UDim2.fromScale(1, 0)
	traitsList.AutomaticSize = Enum.AutomaticSize.Y
	traitsList.Position = UDim2.fromOffset(0, 26)
	traitsList.Parent = traitsBlock
	populateTraits(traitsList, payload.Traits)

	local buttons = Instance.new("Frame")
	buttons.BackgroundTransparency = 1
	buttons.Size = UDim2.new(1, 0, 0, 52)
	buttons.Position = UDim2.fromScale(0, 1)
	buttons.AnchorPoint = Vector2.new(0, 1)
	buttons.Parent = card

	local buttonLayout = Instance.new("UIListLayout")
	buttonLayout.FillDirection = Enum.FillDirection.Horizontal
	buttonLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	buttonLayout.Padding = UDim.new(0, 12)
	buttonLayout.Parent = buttons

	local declineButton = Instance.new("TextButton")
	declineButton.Name = "Decline"
	declineButton.AutoButtonColor = true
	declineButton.BackgroundColor3 = Color3.fromRGB(34, 37, 48)
	declineButton.Size = UDim2.fromOffset(160, 44)
	declineButton.Font = Enum.Font.Gotham
	declineButton.TextSize = 16
	declineButton.Text = "Pass for now"
	declineButton.TextColor3 = Color3.fromRGB(205, 210, 230)
	declineButton.Parent = buttons

	local declineCorner = Instance.new("UICorner")
	declineCorner.CornerRadius = UDim.new(0, 14)
	declineCorner.Parent = declineButton

	local acceptButton = Instance.new("TextButton")
	acceptButton.Name = "Accept"
	acceptButton.AutoButtonColor = true
	acceptButton.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	acceptButton.Size = UDim2.fromOffset(220, 44)
	acceptButton.Font = Enum.Font.GothamBold
	acceptButton.TextSize = 17
	acceptButton.Text = "Guide to a room"
	acceptButton.TextColor3 = Color3.fromRGB(10, 15, 25)
	acceptButton.Parent = buttons

	local acceptCorner = Instance.new("UICorner")
	acceptCorner.CornerRadius = UDim.new(0, 14)
	acceptCorner.Parent = acceptButton

	local status = Instance.new("TextLabel")
	status.BackgroundTransparency = 1
	status.Font = Enum.Font.Gotham
	status.TextSize = 14
	status.TextColor3 = Color3.fromRGB(189, 214, 255)
	status.TextXAlignment = Enum.TextXAlignment.Left
	status.Text = ""
	status.Visible = false
	status.Size = UDim2.new(1, 0, 0, 20)
	status.Position = UDim2.fromOffset(0, card.Size.Y.Offset - 16)
	status.Parent = card

	local appear = TweenService:Create(
		overlay,
		TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ GroupTransparency = 0 }
	)
	appear:Play()

	_panel = overlay
	_card = card
	_callbacks = callbacks
	_statusLabel = status
	_acceptButton = acceptButton
	_declineButton = declineButton
	_busy = false
	setStatus(nil, false)
	setButtonsEnabled(true)

	acceptButton.MouseButton1Click:Connect(function()
		if _busy then
			return
		end
		if _callbacks and _callbacks.OnAccept then
			_callbacks.OnAccept()
		end
	end)

	declineButton.MouseButton1Click:Connect(function()
		if _busy then
			return
		end
		if _callbacks and _callbacks.OnDecline then
			_callbacks.OnDecline()
		else
			TenantProspectPrompt.Hide()
		end
	end)
end

function TenantProspectPrompt.Show(payload: ProspectOfferPayload, callbacks: PromptCallbacks?, prospectModel: Model?)
	_currentPayload = payload
	renderPanel(payload, callbacks, prospectModel)
end

function TenantProspectPrompt.Hide()
	_busy = false
	destroyPanel()
	local cb = _callbacks
	_callbacks = nil
	_currentPayload = nil
	if cb and cb.OnClosed then
		cb.OnClosed()
	end
end

function TenantProspectPrompt.SetBusy(isBusy: boolean, message: string?)
	_busy = isBusy
	setButtonsEnabled(not isBusy)
	if isBusy then
		setStatus(message or "Working...", false)
	else
		setStatus(nil, false)
	end
end

function TenantProspectPrompt.SetStatus(message: string?, isError: boolean?)
	setStatus(message, isError)
end

function TenantProspectPrompt.UpdateInstruction(text: string)
	if _instructionLabel then
		_instructionLabel.Text = text
	end
end

function TenantProspectPrompt.ShowEscortBanner(message: string, isError: boolean?)
	local gui = ensureGui()
	if _escortBanner then
		_escortBanner:Destroy()
	end

	local banner = Instance.new("Frame")
	banner.Name = "EscortBanner"
	banner.AnchorPoint = Vector2.new(0.5, 0)
	banner.Position = UDim2.fromScale(0.5, 0.08)
	banner.Size = UDim2.fromOffset(420, 60)
	banner.BackgroundColor3 = if isError then Color3.fromRGB(70, 24, 30) else Color3.fromRGB(28, 48, 78)
	banner.BackgroundTransparency = 0.05
	banner.Parent = gui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 16)
	corner.Parent = banner

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(255, 255, 255)
	stroke.Transparency = 0.75
	stroke.Thickness = 1
	stroke.Parent = banner

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamMedium
	label.TextSize = 15
	label.TextWrapped = true
	label.Size = UDim2.new(1, -24, 1, -16)
	label.Position = UDim2.fromOffset(12, 8)
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextColor3 = if isError then Color3.fromRGB(255, 200, 200) else Color3.fromRGB(230, 240, 255)
	label.Text = message
	label.Parent = banner

	_escortBanner = banner
end

function TenantProspectPrompt.HideEscortBanner()
	if _escortBanner then
		_escortBanner:Destroy()
		_escortBanner = nil
	end
end

function TenantProspectPrompt.IsVisible(): boolean
	return _panel ~= nil
end

function TenantProspectPrompt.GetProspectId(): string?
	return _currentPayload and _currentPayload.ProspectId or nil
end

return TenantProspectPrompt
