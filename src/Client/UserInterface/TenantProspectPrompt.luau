--!strict
-- StarterPlayerScripts/Client/UserInterface/TenantProspectPrompt.luau
-- Lightweight modal for presenting tenant prospect offers with Accept/Decline actions.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local TenantTraits = require(ReplicatedStorage.Shared.Definitions.TenantTraits)
local TenantDefinitions = require(ReplicatedStorage.Shared.Definitions.TenantDefinitions)

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

local function renderPanel(payload: ProspectOfferPayload, callbacks: PromptCallbacks?, prospectModel: Model?)
	destroyPanel()

	local gui = ensureGui()

	-- Minimal Card Design
	local panel = Instance.new("CanvasGroup")
	panel.Name = "ProspectCard"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	-- Initial size will be set by animation
	panel.BackgroundColor3 = Color3.fromRGB(15, 15, 20)
	panel.BackgroundTransparency = 0.05
	panel.Parent = gui

	local panelCorner = Instance.new("UICorner")
	panelCorner.CornerRadius = UDim.new(0, 20)
	panelCorner.Parent = panel

	local panelStroke = Instance.new("UIStroke")
	panelStroke.Color = Color3.fromRGB(255, 255, 255)
	panelStroke.Transparency = 0.9
	panelStroke.Thickness = 1
	panelStroke.Parent = panel

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 24)
	padding.PaddingBottom = UDim.new(0, 24)
	padding.PaddingLeft = UDim.new(0, 24)
	padding.PaddingRight = UDim.new(0, 24)
	padding.Parent = panel

	local contentOffsetY = 0

	-- Portrait
	if prospectModel then
		local portraitContainer = Instance.new("Frame")
		portraitContainer.Name = "PortraitContainer"
		portraitContainer.BackgroundColor3 = Color3.fromRGB(30, 30, 35)
		portraitContainer.Size = UDim2.fromOffset(100, 100)
		portraitContainer.Position = UDim2.fromScale(0.5, 0)
		portraitContainer.AnchorPoint = Vector2.new(0.5, 0)
		portraitContainer.Parent = panel

		local portraitCorner = Instance.new("UICorner")
		portraitCorner.CornerRadius = UDim.new(1, 0)
		portraitCorner.Parent = portraitContainer

		local viewport = Instance.new("ViewportFrame")
		viewport.BackgroundTransparency = 1
		viewport.Size = UDim2.fromScale(1, 1)
		viewport.Parent = portraitContainer

		local worldModel = Instance.new("WorldModel")
		worldModel.Parent = viewport

		local clone = prospectModel:Clone()
		clone.Parent = worldModel

		local camera = Instance.new("Camera")
		camera.Parent = viewport
		viewport.CurrentCamera = camera

		local head = clone:FindFirstChild("Head") or clone.PrimaryPart
		if head and head:IsA("BasePart") then
			local lookAt = head.Position
			local forward = (clone.PrimaryPart and clone.PrimaryPart.CFrame.LookVector) or Vector3.new(0, 0, -1)
			local camPos = lookAt + (forward * 3) + Vector3.new(0, 0.2, 0)
			camera.CFrame = CFrame.lookAt(camPos, lookAt)
		end

		contentOffsetY = 110
	end

	-- Header: Name & Tier
	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "Name"
	nameLabel.BackgroundTransparency = 1
	nameLabel.Position = UDim2.fromOffset(0, contentOffsetY)
	nameLabel.Size = UDim2.fromScale(1, 0)
	nameLabel.AutomaticSize = Enum.AutomaticSize.Y
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	nameLabel.TextSize = 22
	nameLabel.TextXAlignment = Enum.TextXAlignment.Center
	nameLabel.Text = payload.Name
	nameLabel.Parent = panel

	local tierLabel = Instance.new("TextLabel")
	tierLabel.Name = "Tier"
	tierLabel.BackgroundTransparency = 1
	tierLabel.Position = UDim2.fromOffset(0, contentOffsetY + 28)
	tierLabel.Size = UDim2.fromScale(1, 0)
	tierLabel.AutomaticSize = Enum.AutomaticSize.Y
	tierLabel.Font = Enum.Font.GothamMedium

	local tierDef = TenantDefinitions.GetDefinition(payload.TierId)
	tierLabel.TextColor3 = tierDef and tierDef.DisplayColor or Color3.fromRGB(150, 150, 160)

	tierLabel.TextSize = 14
	tierLabel.TextXAlignment = Enum.TextXAlignment.Center
	tierLabel.Text = string.upper(payload.TierId)
	tierLabel.Parent = panel

	-- Hero Stat: Boost
	local boostContainer = Instance.new("Frame")
	boostContainer.Name = "BoostContainer"
	boostContainer.BackgroundTransparency = 1
	boostContainer.Position = UDim2.fromOffset(0, contentOffsetY + 60)
	boostContainer.Size = UDim2.new(1, 0, 0, 80)
	boostContainer.Parent = panel

	local boostValue = payload.RentBoostPercent or 0
	local boostText = string.format("+%.0f%%", boostValue * 100)

	local boostLabel = Instance.new("TextLabel")
	boostLabel.Name = "BoostValue"
	boostLabel.BackgroundTransparency = 1
	boostLabel.Size = UDim2.fromScale(1, 0.7)
	boostLabel.Font = Enum.Font.GothamBlack
	boostLabel.TextColor3 = Color3.fromRGB(100, 255, 140) -- Green
	boostLabel.TextSize = 48
	boostLabel.Text = boostText
	boostLabel.Parent = boostContainer

	local boostDesc = Instance.new("TextLabel")
	boostDesc.Name = "BoostDesc"
	boostDesc.BackgroundTransparency = 1
	boostDesc.Position = UDim2.fromScale(0, 0.65)
	boostDesc.Size = UDim2.fromScale(1, 0.35)
	boostDesc.Font = Enum.Font.GothamMedium
	boostDesc.TextColor3 = Color3.fromRGB(180, 180, 190)
	boostDesc.TextSize = 14
	boostDesc.Text = "RENT BOOST"
	boostDesc.Parent = boostContainer

	-- Traits List
	local traitsContainer = Instance.new("Frame")
	traitsContainer.Name = "TraitsContainer"
	traitsContainer.BackgroundTransparency = 1
	traitsContainer.Position = UDim2.fromOffset(0, contentOffsetY + 150)
	traitsContainer.Size = UDim2.fromScale(1, 0)
	traitsContainer.AutomaticSize = Enum.AutomaticSize.Y
	traitsContainer.Parent = panel

	local traitsLayout = Instance.new("UIListLayout")
	traitsLayout.FillDirection = Enum.FillDirection.Vertical
	traitsLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	traitsLayout.Padding = UDim.new(0, 6)
	traitsLayout.Parent = traitsContainer

	local traitCount = 0
	if payload.Traits then
		for _, traitId in ipairs(payload.Traits) do
			local traitDef = TenantTraits.GetTrait(traitId)
			if traitDef then
				traitCount += 1
				local traitLabel = Instance.new("TextLabel")
				traitLabel.Name = "Trait_" .. traitId
				traitLabel.BackgroundTransparency = 1
				traitLabel.Size = UDim2.fromScale(1, 0)
				traitLabel.AutomaticSize = Enum.AutomaticSize.Y
				traitLabel.Font = Enum.Font.GothamBold
				traitLabel.TextSize = 15
				traitLabel.Text = traitDef.Name
				traitLabel.TextColor3 = traitDef.DisplayColor or Color3.fromRGB(200, 200, 200)
				traitLabel.Parent = traitsContainer
			end
		end
	end

	-- Buttons
	local buttons = Instance.new("Frame")
	buttons.Name = "Buttons"
	buttons.BackgroundTransparency = 1
	buttons.AnchorPoint = Vector2.new(0, 1)
	buttons.Position = UDim2.fromScale(0, 1)
	buttons.Size = UDim2.new(1, 0, 0, 44)
	buttons.Parent = panel

	local buttonLayout = Instance.new("UIListLayout")
	buttonLayout.FillDirection = Enum.FillDirection.Horizontal
	buttonLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	buttonLayout.Padding = UDim.new(0, 12)
	buttonLayout.Parent = buttons

	local declineButton = Instance.new("TextButton")
	declineButton.Name = "Decline"
	declineButton.AutoButtonColor = true
	declineButton.BackgroundColor3 = Color3.fromRGB(35, 35, 40)
	declineButton.Size = UDim2.fromScale(0.4, 1)
	declineButton.Font = Enum.Font.GothamMedium
	declineButton.TextSize = 14
	declineButton.Text = "Pass"
	declineButton.TextColor3 = Color3.fromRGB(200, 200, 210)
	declineButton.Parent = buttons

	local declineCorner = Instance.new("UICorner")
	declineCorner.CornerRadius = UDim.new(0, 12)
	declineCorner.Parent = declineButton

	local acceptButton = Instance.new("TextButton")
	acceptButton.Name = "Accept"
	acceptButton.AutoButtonColor = true
	acceptButton.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	acceptButton.Size = UDim2.fromScale(0.55, 1)
	acceptButton.Font = Enum.Font.GothamBold
	acceptButton.TextSize = 14
	acceptButton.Text = "Accept"
	acceptButton.TextColor3 = Color3.fromRGB(10, 10, 15)
	acceptButton.Parent = buttons

	local acceptCorner = Instance.new("UICorner")
	acceptCorner.CornerRadius = UDim.new(0, 12)
	acceptCorner.Parent = acceptButton

	-- Status Overlay (for busy state)
	local status = Instance.new("TextLabel")
	status.Name = "Status"
	status.BackgroundTransparency = 1
	status.Size = UDim2.fromScale(1, 0)
	status.AutomaticSize = Enum.AutomaticSize.Y
	status.Font = Enum.Font.GothamMedium
	status.TextSize = 14
	status.TextColor3 = Color3.fromRGB(255, 255, 255)
	status.Visible = false
	status.Parent = panel
	status.Position = UDim2.new(0, 0, 1, -70)

	-- Animation
	local baseHeight = 260 + contentOffsetY
	local traitsHeight = traitCount * 22
	local targetHeight = baseHeight + traitsHeight
	panel.Size = UDim2.fromOffset(300, targetHeight - 20)
	panel.GroupTransparency = 1

	local appear = TweenService:Create(panel, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Size = UDim2.fromOffset(320, targetHeight),
		GroupTransparency = 0,
	})
	appear:Play()

	_panel = panel -- Note: _panel is now the frame itself, not an overlay
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
