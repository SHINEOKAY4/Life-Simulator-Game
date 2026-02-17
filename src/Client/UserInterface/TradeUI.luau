--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local TradePackets = require(ReplicatedStorage.Network.TradePackets)

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

local TradeUI = {}

local RootGui: ScreenGui
local Panel: Frame
local IncomingList: ScrollingFrame
local OutgoingList: ScrollingFrame
local DetailFrame: Frame
local DetailTitle: TextLabel
local DetailItems: TextLabel
local DetailRequestedItems: TextLabel
local AcceptButton: TextButton
local DeclineButton: TextButton
local CancelButton: TextButton
local StatusLabel: TextLabel
local HintLabel: TextLabel
local TabIncoming: TextButton
local TabOutgoing: TextButton

local CachedPayload: any = nil
local SelectedTradeId: string? = nil
local ActiveTab: string = "Incoming"

local function setStatus(text: string, color: Color3?)
	StatusLabel.Text = text
	StatusLabel.TextColor3 = color or Color3.fromRGB(230, 230, 230)
end

local function clearList(frame: ScrollingFrame)
	for _, child in ipairs(frame:GetChildren()) do
		if child:IsA("UIListLayout") or child:IsA("UIPadding") then
			continue
		end
		child:Destroy()
	end
end

local function findTradeById(list: any, tradeId: string): any
	if typeof(list) ~= "table" then
		return nil
	end
	for _, trade in ipairs(list) do
		if trade.TradeId == tradeId then
			return trade
		end
	end
	return nil
end

local function getActiveList(): any
	if typeof(CachedPayload) ~= "table" then
		return {}
	end
	if ActiveTab == "Incoming" then
		return CachedPayload.Incoming or {}
	else
		return CachedPayload.Outgoing or {}
	end
end

local function formatItemList(items: any): string
	if typeof(items) ~= "table" or #items == 0 then
		return "(none)"
	end
	local parts: { string } = {}
	for _, itemId in ipairs(items) do
		table.insert(parts, tostring(itemId))
	end
	return table.concat(parts, ", ")
end

local function renderDetails()
	local list = getActiveList()
	local trade = if SelectedTradeId then findTradeById(list, SelectedTradeId) else nil

	if not trade then
		DetailTitle.Text = "Select a trade"
		DetailItems.Text = "Offered items: -"
		DetailRequestedItems.Text = "Requested items: -"
		AcceptButton.Visible = false
		DeclineButton.Visible = false
		CancelButton.Visible = false
		return
	end

	local initiatorName = trade.InitiatorName or ("Player " .. tostring(trade.InitiatorUserId or "?"))
	if ActiveTab == "Incoming" then
		DetailTitle.Text = "Trade from " .. initiatorName
		DetailItems.Text = "They offer: " .. formatItemList(trade.InitiatorItems)
		DetailRequestedItems.Text = "They want: " .. formatItemList(trade.RequestedItems)
		AcceptButton.Visible = true
		DeclineButton.Visible = true
		CancelButton.Visible = false
	else
		DetailTitle.Text = "Trade to " .. (trade.RecipientName or ("Player " .. tostring(trade.RecipientUserId or "?")))
		DetailItems.Text = "You offer: " .. formatItemList(trade.InitiatorItems)
		DetailRequestedItems.Text = "You want: " .. formatItemList(trade.RequestedItems)
		AcceptButton.Visible = false
		DeclineButton.Visible = false
		CancelButton.Visible = true
	end
end

local function renderList()
	local listFrame = if ActiveTab == "Incoming" then IncomingList else OutgoingList
	IncomingList.Visible = ActiveTab == "Incoming"
	OutgoingList.Visible = ActiveTab == "Outgoing"

	TabIncoming.BackgroundColor3 = if ActiveTab == "Incoming"
		then Color3.fromRGB(58, 87, 130)
		else Color3.fromRGB(36, 39, 48)
	TabOutgoing.BackgroundColor3 = if ActiveTab == "Outgoing"
		then Color3.fromRGB(58, 87, 130)
		else Color3.fromRGB(36, 39, 48)

	clearList(listFrame)

	local list = getActiveList()
	if typeof(list) ~= "table" or #list == 0 then
		local emptyLabel = Instance.new("TextLabel")
		emptyLabel.BackgroundTransparency = 1
		emptyLabel.Size = UDim2.new(1, -8, 0, 34)
		emptyLabel.Font = Enum.Font.Gotham
		emptyLabel.TextSize = 13
		emptyLabel.TextColor3 = Color3.fromRGB(160, 160, 160)
		emptyLabel.Text = if ActiveTab == "Incoming" then "  No incoming trades" else "  No outgoing trades"
		emptyLabel.TextXAlignment = Enum.TextXAlignment.Left
		emptyLabel.Parent = listFrame
		return
	end

	if not SelectedTradeId and #list > 0 then
		SelectedTradeId = list[1].TradeId
	end

	for _, trade in ipairs(list) do
		local label: string
		if ActiveTab == "Incoming" then
			local name = trade.InitiatorName or ("Player " .. tostring(trade.InitiatorUserId or "?"))
			label = "  From: " .. name
		else
			local name = trade.RecipientName or ("Player " .. tostring(trade.RecipientUserId or "?"))
			label = "  To: " .. name
		end

		local button = Instance.new("TextButton")
		button.Name = trade.TradeId
		button.Size = UDim2.new(1, -8, 0, 34)
		button.BackgroundColor3 = if trade.TradeId == SelectedTradeId
			then Color3.fromRGB(58, 87, 130)
			else Color3.fromRGB(36, 39, 48)
		button.BorderSizePixel = 0
		button.Font = Enum.Font.GothamMedium
		button.TextSize = 13
		button.TextXAlignment = Enum.TextXAlignment.Left
		button.TextColor3 = Color3.fromRGB(242, 242, 242)
		button.Text = label
		button.Parent = listFrame

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 5)
		corner.Parent = button

		button.Activated:Connect(function()
			SelectedTradeId = trade.TradeId
			renderList()
			renderDetails()
		end)
	end

	renderDetails()
end

local function requestData()
	local ok, success, message, payload = pcall(function()
		return TradePackets.GetTradeData:Fire()
	end)
	if not ok then
		setStatus("Trade service unavailable.", Color3.fromRGB(255, 145, 145))
		return
	end
	if not success then
		setStatus(message or "Unable to load trade data.", Color3.fromRGB(255, 145, 145))
		return
	end

	CachedPayload = payload
	SelectedTradeId = nil
	renderList()
	setStatus("", Color3.fromRGB(230, 230, 230))
end

local function onAcceptPressed()
	if not SelectedTradeId then
		return
	end
	local ok, success, message = pcall(function()
		return TradePackets.AcceptTrade:Fire(SelectedTradeId :: string)
	end)
	if not ok then
		setStatus("Failed to accept trade.", Color3.fromRGB(255, 145, 145))
		return
	end
	if not success then
		setStatus(message or "Accept failed.", Color3.fromRGB(255, 145, 145))
	else
		setStatus("Trade accepted!", Color3.fromRGB(177, 240, 184))
	end
	requestData()
end

local function onDeclinePressed()
	if not SelectedTradeId then
		return
	end
	local ok, success, message = pcall(function()
		return TradePackets.DeclineTrade:Fire(SelectedTradeId :: string)
	end)
	if not ok then
		setStatus("Failed to decline trade.", Color3.fromRGB(255, 145, 145))
		return
	end
	if not success then
		setStatus(message or "Decline failed.", Color3.fromRGB(255, 145, 145))
	else
		setStatus("Trade declined.", Color3.fromRGB(200, 200, 200))
	end
	requestData()
end

local function onCancelPressed()
	if not SelectedTradeId then
		return
	end
	local ok, success, message = pcall(function()
		return TradePackets.CancelTrade:Fire(SelectedTradeId :: string)
	end)
	if not ok then
		setStatus("Failed to cancel trade.", Color3.fromRGB(255, 145, 145))
		return
	end
	if not success then
		setStatus(message or "Cancel failed.", Color3.fromRGB(255, 145, 145))
	else
		setStatus("Trade cancelled.", Color3.fromRGB(200, 200, 200))
	end
	requestData()
end

local function buildUi()
	RootGui = Instance.new("ScreenGui")
	RootGui.Name = "TradeMenu"
	RootGui.ResetOnSpawn = false
	RootGui.Enabled = false
	RootGui.DisplayOrder = 36
	RootGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	RootGui.Parent = PlayerGui

	Panel = Instance.new("Frame")
	Panel.Name = "Panel"
	Panel.AnchorPoint = Vector2.new(0.5, 0.5)
	Panel.Position = UDim2.fromScale(0.5, 0.52)
	Panel.Size = UDim2.fromOffset(860, 500)
	Panel.BackgroundColor3 = Color3.fromRGB(25, 28, 35)
	Panel.BorderSizePixel = 0
	Panel.Parent = RootGui

	local panelCorner = Instance.new("UICorner")
	panelCorner.CornerRadius = UDim.new(0, 10)
	panelCorner.Parent = Panel

	local panelStroke = Instance.new("UIStroke")
	panelStroke.Color = Color3.fromRGB(71, 91, 125)
	panelStroke.Thickness = 1
	panelStroke.Parent = Panel

	-- Header
	local header = Instance.new("TextLabel")
	header.BackgroundTransparency = 1
	header.Position = UDim2.fromOffset(20, 14)
	header.Size = UDim2.fromOffset(200, 30)
	header.Font = Enum.Font.GothamBold
	header.Text = "Trading"
	header.TextSize = 24
	header.TextXAlignment = Enum.TextXAlignment.Left
	header.TextColor3 = Color3.fromRGB(242, 242, 242)
	header.Parent = Panel

	HintLabel = Instance.new("TextLabel")
	HintLabel.BackgroundTransparency = 1
	HintLabel.AnchorPoint = Vector2.new(1, 0)
	HintLabel.Position = UDim2.new(1, -16, 0, 16)
	HintLabel.Size = UDim2.fromOffset(200, 24)
	HintLabel.Font = Enum.Font.Gotham
	HintLabel.Text = "Press T to close"
	HintLabel.TextSize = 13
	HintLabel.TextXAlignment = Enum.TextXAlignment.Right
	HintLabel.TextColor3 = Color3.fromRGB(195, 205, 224)
	HintLabel.Parent = Panel

	-- Tabs
	TabIncoming = Instance.new("TextButton")
	TabIncoming.Name = "TabIncoming"
	TabIncoming.Position = UDim2.fromOffset(16, 52)
	TabIncoming.Size = UDim2.fromOffset(160, 32)
	TabIncoming.BackgroundColor3 = Color3.fromRGB(58, 87, 130)
	TabIncoming.BorderSizePixel = 0
	TabIncoming.Font = Enum.Font.GothamMedium
	TabIncoming.TextSize = 13
	TabIncoming.TextColor3 = Color3.fromRGB(242, 242, 242)
	TabIncoming.Text = "Incoming"
	TabIncoming.Parent = Panel

	local tabInCorner = Instance.new("UICorner")
	tabInCorner.CornerRadius = UDim.new(0, 6)
	tabInCorner.Parent = TabIncoming

	TabOutgoing = Instance.new("TextButton")
	TabOutgoing.Name = "TabOutgoing"
	TabOutgoing.Position = UDim2.fromOffset(184, 52)
	TabOutgoing.Size = UDim2.fromOffset(160, 32)
	TabOutgoing.BackgroundColor3 = Color3.fromRGB(36, 39, 48)
	TabOutgoing.BorderSizePixel = 0
	TabOutgoing.Font = Enum.Font.GothamMedium
	TabOutgoing.TextSize = 13
	TabOutgoing.TextColor3 = Color3.fromRGB(242, 242, 242)
	TabOutgoing.Text = "Outgoing"
	TabOutgoing.Parent = Panel

	local tabOutCorner = Instance.new("UICorner")
	tabOutCorner.CornerRadius = UDim.new(0, 6)
	tabOutCorner.Parent = TabOutgoing

	-- Incoming list
	IncomingList = Instance.new("ScrollingFrame")
	IncomingList.Name = "IncomingList"
	IncomingList.Position = UDim2.fromOffset(16, 96)
	IncomingList.Size = UDim2.new(0, 330, 1, -158)
	IncomingList.BackgroundColor3 = Color3.fromRGB(29, 32, 42)
	IncomingList.BorderSizePixel = 0
	IncomingList.AutomaticCanvasSize = Enum.AutomaticSize.Y
	IncomingList.ScrollBarThickness = 6
	IncomingList.CanvasSize = UDim2.fromOffset(0, 0)
	IncomingList.Parent = Panel

	local inCorner = Instance.new("UICorner")
	inCorner.CornerRadius = UDim.new(0, 8)
	inCorner.Parent = IncomingList

	local inLayout = Instance.new("UIListLayout")
	inLayout.Padding = UDim.new(0, 6)
	inLayout.SortOrder = Enum.SortOrder.LayoutOrder
	inLayout.Parent = IncomingList

	local inPad = Instance.new("UIPadding")
	inPad.PaddingTop = UDim.new(0, 8)
	inPad.PaddingLeft = UDim.new(0, 4)
	inPad.PaddingRight = UDim.new(0, 4)
	inPad.PaddingBottom = UDim.new(0, 8)
	inPad.Parent = IncomingList

	-- Outgoing list (same position, toggled)
	OutgoingList = Instance.new("ScrollingFrame")
	OutgoingList.Name = "OutgoingList"
	OutgoingList.Position = UDim2.fromOffset(16, 96)
	OutgoingList.Size = UDim2.new(0, 330, 1, -158)
	OutgoingList.BackgroundColor3 = Color3.fromRGB(29, 32, 42)
	OutgoingList.BorderSizePixel = 0
	OutgoingList.AutomaticCanvasSize = Enum.AutomaticSize.Y
	OutgoingList.ScrollBarThickness = 6
	OutgoingList.CanvasSize = UDim2.fromOffset(0, 0)
	OutgoingList.Visible = false
	OutgoingList.Parent = Panel

	local outCorner = Instance.new("UICorner")
	outCorner.CornerRadius = UDim.new(0, 8)
	outCorner.Parent = OutgoingList

	local outLayout = Instance.new("UIListLayout")
	outLayout.Padding = UDim.new(0, 6)
	outLayout.SortOrder = Enum.SortOrder.LayoutOrder
	outLayout.Parent = OutgoingList

	local outPad = Instance.new("UIPadding")
	outPad.PaddingTop = UDim.new(0, 8)
	outPad.PaddingLeft = UDim.new(0, 4)
	outPad.PaddingRight = UDim.new(0, 4)
	outPad.PaddingBottom = UDim.new(0, 8)
	outPad.Parent = OutgoingList

	-- Detail panel
	DetailFrame = Instance.new("Frame")
	DetailFrame.Name = "Detail"
	DetailFrame.Position = UDim2.fromOffset(360, 96)
	DetailFrame.Size = UDim2.new(1, -376, 1, -158)
	DetailFrame.BackgroundColor3 = Color3.fromRGB(30, 34, 45)
	DetailFrame.BorderSizePixel = 0
	DetailFrame.Parent = Panel

	local detailCorner = Instance.new("UICorner")
	detailCorner.CornerRadius = UDim.new(0, 8)
	detailCorner.Parent = DetailFrame

	DetailTitle = Instance.new("TextLabel")
	DetailTitle.BackgroundTransparency = 1
	DetailTitle.Position = UDim2.fromOffset(16, 14)
	DetailTitle.Size = UDim2.new(1, -24, 0, 34)
	DetailTitle.Font = Enum.Font.GothamBold
	DetailTitle.Text = "Select a trade"
	DetailTitle.TextSize = 18
	DetailTitle.TextXAlignment = Enum.TextXAlignment.Left
	DetailTitle.TextColor3 = Color3.fromRGB(244, 244, 244)
	DetailTitle.Parent = DetailFrame

	DetailItems = Instance.new("TextLabel")
	DetailItems.BackgroundTransparency = 1
	DetailItems.Position = UDim2.fromOffset(16, 56)
	DetailItems.Size = UDim2.new(1, -24, 0, 48)
	DetailItems.Font = Enum.Font.Gotham
	DetailItems.TextWrapped = true
	DetailItems.Text = "Offered items: -"
	DetailItems.TextSize = 14
	DetailItems.TextXAlignment = Enum.TextXAlignment.Left
	DetailItems.TextYAlignment = Enum.TextYAlignment.Top
	DetailItems.TextColor3 = Color3.fromRGB(198, 206, 220)
	DetailItems.Parent = DetailFrame

	DetailRequestedItems = Instance.new("TextLabel")
	DetailRequestedItems.BackgroundTransparency = 1
	DetailRequestedItems.Position = UDim2.fromOffset(16, 110)
	DetailRequestedItems.Size = UDim2.new(1, -24, 0, 48)
	DetailRequestedItems.Font = Enum.Font.Gotham
	DetailRequestedItems.TextWrapped = true
	DetailRequestedItems.Text = "Requested items: -"
	DetailRequestedItems.TextSize = 14
	DetailRequestedItems.TextXAlignment = Enum.TextXAlignment.Left
	DetailRequestedItems.TextYAlignment = Enum.TextYAlignment.Top
	DetailRequestedItems.TextColor3 = Color3.fromRGB(198, 206, 220)
	DetailRequestedItems.Parent = DetailFrame

	-- Accept button (for incoming trades)
	AcceptButton = Instance.new("TextButton")
	AcceptButton.Name = "AcceptButton"
	AcceptButton.AnchorPoint = Vector2.new(0, 1)
	AcceptButton.Position = UDim2.new(0, 16, 1, -16)
	AcceptButton.Size = UDim2.fromOffset(130, 40)
	AcceptButton.BackgroundColor3 = Color3.fromRGB(66, 132, 94)
	AcceptButton.BorderSizePixel = 0
	AcceptButton.Font = Enum.Font.GothamBold
	AcceptButton.Text = "Accept"
	AcceptButton.TextSize = 15
	AcceptButton.TextColor3 = Color3.fromRGB(250, 250, 250)
	AcceptButton.Visible = false
	AcceptButton.Parent = DetailFrame

	local acceptCorner = Instance.new("UICorner")
	acceptCorner.CornerRadius = UDim.new(0, 8)
	acceptCorner.Parent = AcceptButton

	-- Decline button (for incoming trades)
	DeclineButton = Instance.new("TextButton")
	DeclineButton.Name = "DeclineButton"
	DeclineButton.AnchorPoint = Vector2.new(0, 1)
	DeclineButton.Position = UDim2.new(0, 156, 1, -16)
	DeclineButton.Size = UDim2.fromOffset(130, 40)
	DeclineButton.BackgroundColor3 = Color3.fromRGB(145, 60, 60)
	DeclineButton.BorderSizePixel = 0
	DeclineButton.Font = Enum.Font.GothamBold
	DeclineButton.Text = "Decline"
	DeclineButton.TextSize = 15
	DeclineButton.TextColor3 = Color3.fromRGB(250, 250, 250)
	DeclineButton.Visible = false
	DeclineButton.Parent = DetailFrame

	local declineCorner = Instance.new("UICorner")
	declineCorner.CornerRadius = UDim.new(0, 8)
	declineCorner.Parent = DeclineButton

	-- Cancel button (for outgoing trades)
	CancelButton = Instance.new("TextButton")
	CancelButton.Name = "CancelButton"
	CancelButton.AnchorPoint = Vector2.new(0, 1)
	CancelButton.Position = UDim2.new(0, 16, 1, -16)
	CancelButton.Size = UDim2.fromOffset(130, 40)
	CancelButton.BackgroundColor3 = Color3.fromRGB(145, 100, 50)
	CancelButton.BorderSizePixel = 0
	CancelButton.Font = Enum.Font.GothamBold
	CancelButton.Text = "Cancel Trade"
	CancelButton.TextSize = 15
	CancelButton.TextColor3 = Color3.fromRGB(250, 250, 250)
	CancelButton.Visible = false
	CancelButton.Parent = DetailFrame

	local cancelCorner = Instance.new("UICorner")
	cancelCorner.CornerRadius = UDim.new(0, 8)
	cancelCorner.Parent = CancelButton

	-- Status label
	StatusLabel = Instance.new("TextLabel")
	StatusLabel.Name = "StatusLabel"
	StatusLabel.BackgroundTransparency = 1
	StatusLabel.AnchorPoint = Vector2.new(1, 1)
	StatusLabel.Position = UDim2.new(1, -16, 1, -16)
	StatusLabel.Size = UDim2.new(1, -180, 0, 36)
	StatusLabel.Font = Enum.Font.Gotham
	StatusLabel.Text = ""
	StatusLabel.TextSize = 14
	StatusLabel.TextXAlignment = Enum.TextXAlignment.Right
	StatusLabel.TextYAlignment = Enum.TextYAlignment.Center
	StatusLabel.TextColor3 = Color3.fromRGB(230, 230, 230)
	StatusLabel.Parent = DetailFrame

	-- Wire up buttons
	AcceptButton.Activated:Connect(onAcceptPressed)
	DeclineButton.Activated:Connect(onDeclinePressed)
	CancelButton.Activated:Connect(onCancelPressed)

	TabIncoming.Activated:Connect(function()
		ActiveTab = "Incoming"
		SelectedTradeId = nil
		renderList()
	end)

	TabOutgoing.Activated:Connect(function()
		ActiveTab = "Outgoing"
		SelectedTradeId = nil
		renderList()
	end)
end

local function setVisible(visible: boolean)
	RootGui.Enabled = visible
	if visible then
		requestData()
	else
		setStatus("")
	end
	renderDetails()
end

function TradeUI.Init()
	buildUi()

	UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		if gameProcessed or UserInputService:GetFocusedTextBox() ~= nil then
			return
		end
		if input.KeyCode == Enum.KeyCode.T then
			setVisible(not RootGui.Enabled)
		elseif input.KeyCode == Enum.KeyCode.Escape and RootGui.Enabled then
			setVisible(false)
		end
	end)

	-- Listen for server-pushed notifications
	TradePackets.TradeIncoming.OnClientEvent:Connect(function(payload: any)
		if typeof(payload) ~= "table" then
			return
		end
		-- Auto-refresh if panel is open
		if RootGui.Enabled then
			requestData()
		end
		setStatus(
			string.format("Trade request from %s!", payload.InitiatorName or "a player"),
			Color3.fromRGB(177, 210, 255)
		)
	end)

	TradePackets.TradeResolved.OnClientEvent:Connect(function(payload: any)
		if typeof(payload) ~= "table" then
			return
		end
		local color = Color3.fromRGB(230, 230, 230)
		if payload.Status == "Completed" then
			color = Color3.fromRGB(177, 240, 184)
		elseif payload.Status == "Declined" or payload.Status == "Cancelled" then
			color = Color3.fromRGB(255, 180, 145)
		end
		setStatus(payload.Message or ("Trade " .. (payload.Status or "resolved")), color)
		if RootGui.Enabled then
			requestData()
		end
	end)
end

return TradeUI
