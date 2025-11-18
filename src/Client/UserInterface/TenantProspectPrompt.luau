--!strict
-- StarterPlayerScripts/Client/UserInterface/TenantProspectPrompt.luau
-- Lightweight modal for presenting tenant prospect offers with Accept/Decline actions.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Formatter = require(ReplicatedStorage.Shared.Utilities.Formatter)

export type ProspectOfferPayload = {
	ProspectId: string,
	Name: string,
	TierId: string,
	RentPerInterval: number,
	RentIntervalSeconds: number,
	LeaseSeconds: number,
	Deposit: number?,
}

export type PromptCallbacks = {
	OnAccept: (() -> ())?,
	OnDecline: (() -> ())?,
	OnClosed: (() -> ())?,
}

local CASH_OPTIONS = {
	currencySymbol = "$",
}

local LEASE_DURATION_OPTIONS = {
	units = { "hour", "minute" },
	shortUnits = true,
	maxUnits = 2,
}

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

local TenantProspectPrompt = {}

local _screenGui: ScreenGui?
local _panel: GuiObject?
local _callbacks: PromptCallbacks? = nil
local _statusLabel: TextLabel?
local _acceptButton: TextButton?
local _declineButton: TextButton?
local _currentPayload: ProspectOfferPayload?
local _busy = false

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

local function setButtonsEnabled(isEnabled: boolean)
	if _acceptButton then
		_acceptButton.Active = isEnabled
		_acceptButton.AutoButtonColor = isEnabled
		_acceptButton.BackgroundTransparency = isEnabled and 0 or 0.25
	end
	if _declineButton then
		_declineButton.Active = isEnabled
		_declineButton.AutoButtonColor = isEnabled
		_declineButton.BackgroundTransparency = isEnabled and 0 or 0.25
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
	if isError then
		_statusLabel.TextColor3 = Color3.fromRGB(255, 140, 140)
	else
		_statusLabel.TextColor3 = Color3.fromRGB(199, 214, 255)
	end
end

local function formatInterval(seconds: number): string
	if seconds < 1 then
		return "Instant"
	end
	if seconds < 60 then
		return string.format("%ds", math.floor(seconds + 0.5))
	end
	if seconds % 60 == 0 then
		local minutes = math.floor(seconds / 60)
		if minutes < 60 then
			return string.format("%d min", minutes)
		end
	end
	return Formatter.formatDuration(seconds, LEASE_DURATION_OPTIONS)
end

local function destroyPanel()
	if _panel then
		_panel:Destroy()
	end
	_panel = nil
	_statusLabel = nil
	_acceptButton = nil
	_declineButton = nil
	setStatus(nil, false)
end

local function buildInfoLabel(text: string, layoutOrder: number): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = "Info" .. layoutOrder
	label.LayoutOrder = layoutOrder
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamMedium
	label.TextSize = 16
	label.TextColor3 = Color3.fromRGB(240, 244, 255)
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Text = text
	label.Size = UDim2.fromScale(1, 0)
	label.AutomaticSize = Enum.AutomaticSize.Y
	return label
end

local function renderPanel(payload: ProspectOfferPayload, callbacks: PromptCallbacks?)
	destroyPanel()

	local gui = ensureGui()
	local overlay = Instance.new("TextButton")
	overlay.Name = "Darken"
	overlay.AutoButtonColor = false
	overlay.BackgroundColor3 = Color3.fromRGB(6, 8, 14)
	overlay.BackgroundTransparency = 0.35
	overlay.BorderSizePixel = 0
	overlay.Text = ""
	overlay.Modal = true
	overlay.Size = UDim2.fromScale(1, 1)
	overlay.Parent = gui

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromOffset(440, 320)
	panel.BackgroundColor3 = Color3.fromRGB(24, 27, 35)
	panel.Parent = overlay

	local panelCorner = Instance.new("UICorner")
	panelCorner.CornerRadius = UDim.new(0, 12)
	panelCorner.Parent = panel

	local panelStroke = Instance.new("UIStroke")
	panelStroke.Color = Color3.fromRGB(92, 111, 194)
	panelStroke.Transparency = 0.55
	panelStroke.Thickness = 2
	panelStroke.Parent = panel

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 20)
	padding.PaddingBottom = UDim.new(0, 20)
	padding.PaddingLeft = UDim.new(0, 24)
	padding.PaddingRight = UDim.new(0, 24)
	padding.Parent = panel

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.Size = UDim2.fromScale(1, 0)
	title.AutomaticSize = Enum.AutomaticSize.Y
	title.Font = Enum.Font.GothamBold
	title.TextColor3 = Color3.fromRGB(255, 255, 255)
	title.TextSize = 24
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Text = string.format("%s wants to rent your plot", payload.Name)
	title.Parent = panel

	local tierLabel = Instance.new("TextLabel")
	tierLabel.Name = "Tier"
	tierLabel.BackgroundTransparency = 1
	tierLabel.Position = UDim2.fromOffset(0, 40)
	tierLabel.Size = UDim2.fromScale(1, 0)
	tierLabel.AutomaticSize = Enum.AutomaticSize.Y
	tierLabel.Font = Enum.Font.Gotham
	tierLabel.TextColor3 = Color3.fromRGB(186, 196, 216)
	tierLabel.TextSize = 16
	tierLabel.TextXAlignment = Enum.TextXAlignment.Left
	tierLabel.Text = string.format("Prospect tier: %s", payload.TierId)
	tierLabel.Parent = panel

	local infoList = Instance.new("Frame")
	infoList.Name = "OfferStats"
	infoList.BackgroundTransparency = 1
	infoList.Position = UDim2.fromOffset(0, 90)
	infoList.Size = UDim2.new(1, 0, 0, 150)
	infoList.Parent = panel

	local listLayout = Instance.new("UIListLayout")
	listLayout.FillDirection = Enum.FillDirection.Vertical
	listLayout.VerticalAlignment = Enum.VerticalAlignment.Top
	listLayout.Padding = UDim.new(0, 8)
	listLayout.Parent = infoList

	local rentText = Formatter.formatCurrency(payload.RentPerInterval, CASH_OPTIONS)
	local rentIntervalText = formatInterval(payload.RentIntervalSeconds)
	local depositValue = payload.Deposit or 0
	local depositText = Formatter.formatCurrency(depositValue, CASH_OPTIONS)
	local leaseText = "Stays until you evict them"
	if payload.LeaseSeconds and payload.LeaseSeconds > 0 then
		leaseText = Formatter.formatDuration(payload.LeaseSeconds, LEASE_DURATION_OPTIONS)
	end

	local rentLabel = buildInfoLabel(string.format("Rent: %s every %s", rentText, rentIntervalText), 1)
	rentLabel.Parent = infoList

	if depositValue > 0 then
		local depositLabel = buildInfoLabel(string.format("Deposit returned on move-out: %s", depositText), 2)
		depositLabel.Parent = infoList
	end

	local leaseLabel = buildInfoLabel(string.format("Lease length: %s", leaseText), 3)
	leaseLabel.Parent = infoList

	local status = Instance.new("TextLabel")
	status.Name = "Status"
	status.BackgroundTransparency = 1
	status.Size = UDim2.fromScale(1, 0)
	status.AutomaticSize = Enum.AutomaticSize.Y
	status.Font = Enum.Font.Gotham
	status.TextSize = 14
	status.TextColor3 = Color3.fromRGB(199, 214, 255)
	status.Visible = false
	status.Parent = panel
	status.Position = UDim2.new(0, 0, 1, -90)

	local buttons = Instance.new("Frame")
	buttons.Name = "Buttons"
	buttons.BackgroundTransparency = 1
	buttons.AnchorPoint = Vector2.new(0, 1)
	buttons.Position = UDim2.new(0, 0, 1, -20)
	buttons.Size = UDim2.fromScale(1, 0)
	buttons.AutomaticSize = Enum.AutomaticSize.Y
	buttons.Parent = panel

	local buttonLayout = Instance.new("UIListLayout")
	buttonLayout.FillDirection = Enum.FillDirection.Horizontal
	buttonLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	buttonLayout.Padding = UDim.new(0, 12)
	buttonLayout.Parent = buttons

	local declineButton = Instance.new("TextButton")
	declineButton.Name = "Decline"
	declineButton.AutoButtonColor = true
	declineButton.BackgroundColor3 = Color3.fromRGB(49, 53, 65)
	declineButton.Size = UDim2.fromOffset(150, 42)
	declineButton.Font = Enum.Font.Gotham
	declineButton.TextSize = 16
	declineButton.Text = "Decline"
	declineButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	declineButton.Parent = buttons

	local declineCorner = Instance.new("UICorner")
	declineCorner.CornerRadius = UDim.new(0, 10)
	declineCorner.Parent = declineButton

	local acceptButton = Instance.new("TextButton")
	acceptButton.Name = "Accept"
	acceptButton.AutoButtonColor = true
	acceptButton.BackgroundColor3 = Color3.fromRGB(96, 187, 121)
	acceptButton.Size = UDim2.fromOffset(160, 42)
	acceptButton.Font = Enum.Font.GothamBold
	acceptButton.TextSize = 16
	acceptButton.Text = "Invite to Move In"
	acceptButton.TextColor3 = Color3.fromRGB(12, 23, 16)
	acceptButton.Parent = buttons

	local acceptCorner = Instance.new("UICorner")
	acceptCorner.CornerRadius = UDim.new(0, 10)
	acceptCorner.Parent = acceptButton

	local closeButton = Instance.new("TextButton")
	closeButton.Name = "Close"
	closeButton.AnchorPoint = Vector2.new(1, 0)
	closeButton.Position = UDim2.new(1, 0, 0, -8)
	closeButton.Size = UDim2.fromOffset(32, 32)
	closeButton.Text = "✕"
	closeButton.TextSize = 18
	closeButton.Font = Enum.Font.Gotham
	closeButton.TextColor3 = Color3.fromRGB(190, 196, 210)
	closeButton.BackgroundTransparency = 1
	closeButton.Parent = panel

	local appear = TweenService:Create(panel, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = UDim2.fromOffset(460, 332),
	})
	appear:Play()

	_panel = overlay
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

	closeButton.MouseButton1Click:Connect(function()
		TenantProspectPrompt.Hide()
	end)
	overlay.MouseButton1Click:Connect(function()
		TenantProspectPrompt.Hide()
	end)
end

function TenantProspectPrompt.Show(payload: ProspectOfferPayload, callbacks: PromptCallbacks?)
	_currentPayload = payload
	renderPanel(payload, callbacks)
end

function TenantProspectPrompt.Hide()
	_busy = false
	destroyPanel()
	if _screenGui then
		_screenGui:ClearAllChildren()
	end
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
		setStatus(message or "Processing decision...", false)
	else
		setStatus(nil, false)
	end
end

function TenantProspectPrompt.SetStatus(message: string?, isError: boolean?)
	setStatus(message, isError)
end

function TenantProspectPrompt.IsVisible(): boolean
	return _panel ~= nil
end

function TenantProspectPrompt.GetProspectId(): string?
	return _currentPayload and _currentPayload.ProspectId or nil
end

return TenantProspectPrompt
