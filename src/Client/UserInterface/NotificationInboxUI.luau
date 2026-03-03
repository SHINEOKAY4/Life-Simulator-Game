--!strict
-- StarterPlayerScripts/Client/UserInterface/NotificationInboxUI.luau
-- Inbox panel showing the player's latest notifications from NotificationPackets.
-- Subscribes to StateSnapshot (full sync on join) and NotificationDelta (incremental).
-- Unread/read state can be toggled locally per notification row.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NotificationPackets = require(ReplicatedStorage.Network.NotificationPackets)

local NotificationInboxUI = {}

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

local gui: ScreenGui? = nil
local windowFrame: CanvasGroup? = nil
local notifListFrame: ScrollingFrame? = nil
local unreadCountLabel: TextLabel? = nil
local open = false
local initialized = false

-- Local notification store: most recent first, capped at 20
local MAX_DISPLAY = 20
local notifications: { [number]: {
	Id: number,
	Category: string,
	Title: string,
	Body: string,
	Icon: string,
	Priority: number,
	Duration: number,
	Timestamp: number,
	Read: boolean,
	Metadata: any,
} } = {}

local PANEL_BG       = Color3.fromRGB(15, 18, 26)
local HEADER_BG      = Color3.fromRGB(30, 80, 140)
local CARD_BG        = Color3.fromRGB(24, 30, 42)
local CARD_READ_BG   = Color3.fromRGB(20, 24, 34)
local TEXT_PRIMARY   = Color3.fromRGB(230, 238, 255)
local TEXT_SECONDARY = Color3.fromRGB(160, 178, 210)
local TEXT_MUTED     = Color3.fromRGB(100, 118, 148)
local UNREAD_DOT     = Color3.fromRGB(80, 180, 255)
local READ_DOT       = Color3.fromRGB(60, 75, 100)
local CLOSE_BG       = Color3.fromRGB(60, 30, 30)

local OPEN_TWEEN  = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local CLOSE_TWEEN = TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

local CATEGORY_ICONS: { [string]: string } = {
	Achievement = "🏆",
	Quest       = "📋",
	Trade       = "🤝",
	Reputation  = "⭐",
	Billing     = "💰",
	Social      = "💬",
	System      = "🔔",
	Reward      = "🎁",
}

local function getCategoryIcon(category: string): string
	return CATEGORY_ICONS[category] or "🔔"
end

local function countUnread(): number
	local count = 0
	for _, n in ipairs(notifications) do
		if not n.Read then
			count += 1
		end
	end
	return count
end

local function updateUnreadBadge()
	if not unreadCountLabel then
		return
	end
	local count = countUnread()
	if count > 0 then
		unreadCountLabel.Text = tostring(count)
		unreadCountLabel.Visible = true
	else
		unreadCountLabel.Visible = false
	end
end

-- Refresh notification list UI
local function rebuildList()
	if not notifListFrame then
		return
	end
	-- Clear existing cards
	for _, child in ipairs(notifListFrame:GetChildren()) do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end

	if #notifications == 0 then
		local emptyLabel = Instance.new("TextLabel")
		emptyLabel.Name = "EmptyLabel"
		emptyLabel.Size = UDim2.new(1, -16, 0, 50)
		emptyLabel.BackgroundTransparency = 1
		emptyLabel.Text = "No notifications yet."
		emptyLabel.TextColor3 = TEXT_MUTED
		emptyLabel.Font = Enum.Font.Gotham
		emptyLabel.TextSize = 14
		emptyLabel.TextXAlignment = Enum.TextXAlignment.Center
		emptyLabel.LayoutOrder = 1
		emptyLabel.Parent = notifListFrame
		return
	end

	local cap = math.min(#notifications, MAX_DISPLAY)
	for i = 1, cap do
		local n = notifications[i]

		local card = Instance.new("Frame")
		card.Name = "NotifCard_" .. tostring(n.Id)
		card.Size = UDim2.new(1, -8, 0, 80)
		card.BackgroundColor3 = if n.Read then CARD_READ_BG else CARD_BG
		card.BorderSizePixel = 0
		card.LayoutOrder = i
		card.Parent = notifListFrame

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 6)
		corner.Parent = card

		-- Unread indicator dot
		local dot = Instance.new("Frame")
		dot.Name = "UnreadDot"
		dot.Size = UDim2.fromOffset(8, 8)
		dot.AnchorPoint = Vector2.new(0, 0.5)
		dot.Position = UDim2.new(0, 8, 0.5, 0)
		dot.BackgroundColor3 = if n.Read then READ_DOT else UNREAD_DOT
		dot.BorderSizePixel = 0
		dot.Parent = card

		local dotCorner = Instance.new("UICorner")
		dotCorner.CornerRadius = UDim.new(1, 0)
		dotCorner.Parent = dot

		-- Icon label
		local iconLabel = Instance.new("TextLabel")
		iconLabel.Name = "IconLabel"
		iconLabel.Size = UDim2.fromOffset(28, 28)
		iconLabel.AnchorPoint = Vector2.new(0, 0.5)
		iconLabel.Position = UDim2.new(0, 22, 0.5, 0)
		iconLabel.BackgroundTransparency = 1
		iconLabel.Text = getCategoryIcon(n.Category)
		iconLabel.Font = Enum.Font.Gotham
		iconLabel.TextSize = 20
		iconLabel.TextXAlignment = Enum.TextXAlignment.Center
		iconLabel.Parent = card

		-- Title
		local titleLabel = Instance.new("TextLabel")
		titleLabel.Name = "TitleLabel"
		titleLabel.Size = UDim2.new(1, -80, 0, 22)
		titleLabel.Position = UDim2.fromOffset(56, 8)
		titleLabel.BackgroundTransparency = 1
		titleLabel.Text = n.Title
		titleLabel.TextColor3 = TEXT_PRIMARY
		titleLabel.Font = Enum.Font.GothamBold
		titleLabel.TextSize = 13
		titleLabel.TextXAlignment = Enum.TextXAlignment.Left
		titleLabel.TextTruncate = Enum.TextTruncate.AtEnd
		titleLabel.Parent = card

		-- Body
		local bodyLabel = Instance.new("TextLabel")
		bodyLabel.Name = "BodyLabel"
		bodyLabel.Size = UDim2.new(1, -80, 0, 30)
		bodyLabel.Position = UDim2.fromOffset(56, 30)
		bodyLabel.BackgroundTransparency = 1
		bodyLabel.Text = n.Body
		bodyLabel.TextColor3 = TEXT_SECONDARY
		bodyLabel.Font = Enum.Font.Gotham
		bodyLabel.TextSize = 11
		bodyLabel.TextXAlignment = Enum.TextXAlignment.Left
		bodyLabel.TextWrapped = true
		bodyLabel.TextTruncate = Enum.TextTruncate.AtEnd
		bodyLabel.Parent = card

		-- Category + timestamp row
		local metaLabel = Instance.new("TextLabel")
		metaLabel.Name = "MetaLabel"
		metaLabel.Size = UDim2.new(1, -80, 0, 16)
		metaLabel.Position = UDim2.fromOffset(56, 60)
		metaLabel.BackgroundTransparency = 1
		local ts = n.Timestamp
		local timeStr = string.format("%02d:%02d", math.floor(ts / 3600) % 24, math.floor(ts / 60) % 60)
		metaLabel.Text = n.Category .. "  ·  " .. timeStr
		metaLabel.TextColor3 = TEXT_MUTED
		metaLabel.Font = Enum.Font.Gotham
		metaLabel.TextSize = 10
		metaLabel.TextXAlignment = Enum.TextXAlignment.Left
		metaLabel.Parent = card

		-- Read toggle button (top-right "✓")
		local toggleButton = Instance.new("TextButton")
		toggleButton.Name = "ReadToggle"
		toggleButton.Size = UDim2.fromOffset(24, 24)
		toggleButton.AnchorPoint = Vector2.new(1, 0)
		toggleButton.Position = UDim2.new(1, -6, 0, 6)
		toggleButton.BackgroundTransparency = 1
		toggleButton.Text = if n.Read then "○" else "✓"
		toggleButton.TextColor3 = if n.Read then TEXT_MUTED else UNREAD_DOT
		toggleButton.Font = Enum.Font.GothamBold
		toggleButton.TextSize = 14
		toggleButton.Parent = card

		-- Local toggle on click (no server round-trip needed per acceptance criteria)
		local notifId = n.Id
		toggleButton.Activated:Connect(function()
			for _, stored in ipairs(notifications) do
				if stored.Id == notifId then
					stored.Read = not stored.Read
					break
				end
			end
			rebuildList()
			updateUnreadBadge()
		end)
	end

	-- Update canvas size
	notifListFrame.CanvasSize = UDim2.fromOffset(0, cap * 88 + 4)
end

-- Merge a single delta notification into the local store (most-recent-first)
local function applyDelta(notif: {
	Id: number,
	Category: string,
	Title: string,
	Body: string,
	Icon: string,
	Priority: number,
	Duration: number,
	Timestamp: number,
	Read: boolean,
	Metadata: any,
})
	-- Remove duplicate by Id if present
	for i = #notifications, 1, -1 do
		if notifications[i].Id == notif.Id then
			table.remove(notifications, i)
		end
	end
	-- Insert at front (most recent)
	table.insert(notifications, 1, notif)
	-- Cap
	while #notifications > MAX_DISPLAY do
		table.remove(notifications, #notifications)
	end
end

-- Apply a full StateSnapshot (Queue is already ordered by priority)
local function applySnapshot(queue: { {
	Id: number,
	Category: string,
	Title: string,
	Body: string,
	Icon: string,
	Priority: number,
	Duration: number,
	Timestamp: number,
	Read: boolean,
	Metadata: any,
} })
	notifications = {}
	for i = 1, math.min(#queue, MAX_DISPLAY) do
		table.insert(notifications, queue[i])
	end
end

local function buildGui()
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "NotificationInboxUI"
	screenGui.IgnoreGuiInset = true
	screenGui.ResetOnSpawn = false
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.DisplayOrder = 12
	screenGui.Enabled = false
	screenGui.Parent = PlayerGui
	gui = screenGui

	-- Overlay close region
	local overlay = Instance.new("TextButton")
	overlay.Name = "Overlay"
	overlay.Size = UDim2.fromScale(1, 1)
	overlay.BackgroundTransparency = 0.5
	overlay.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	overlay.BorderSizePixel = 0
	overlay.Text = ""
	overlay.ZIndex = 1
	overlay.Parent = screenGui
	overlay.Activated:Connect(function()
		NotificationInboxUI.SetVisible(false)
	end)

	-- Window
	local window = Instance.new("CanvasGroup")
	window.Name = "NotificationInboxWindow"
	window.Size = UDim2.fromOffset(360, 500)
	window.AnchorPoint = Vector2.new(0.5, 0.5)
	window.Position = UDim2.fromScale(0.5, 0.5)
	window.BackgroundColor3 = PANEL_BG
	window.BorderSizePixel = 0
	window.ZIndex = 2
	window.Parent = screenGui
	windowFrame = window

	local windowCorner = Instance.new("UICorner")
	windowCorner.CornerRadius = UDim.new(0, 10)
	windowCorner.Parent = window

	-- Header
	local header = Instance.new("Frame")
	header.Name = "Header"
	header.Size = UDim2.new(1, 0, 0, 48)
	header.BackgroundColor3 = HEADER_BG
	header.BorderSizePixel = 0
	header.ZIndex = 3
	header.Parent = window

	local headerCorner = Instance.new("UICorner")
	headerCorner.CornerRadius = UDim.new(0, 10)
	headerCorner.Parent = header

	local headerFill = Instance.new("Frame")
	headerFill.Size = UDim2.new(1, 0, 0.5, 0)
	headerFill.Position = UDim2.fromScale(0, 0.5)
	headerFill.BackgroundColor3 = HEADER_BG
	headerFill.BorderSizePixel = 0
	headerFill.ZIndex = 3
	headerFill.Parent = header

	local titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "TitleLabel"
	titleLabel.Size = UDim2.new(1, -80, 1, 0)
	titleLabel.Position = UDim2.fromOffset(16, 0)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Text = "🔔 Notifications"
	titleLabel.TextColor3 = TEXT_PRIMARY
	titleLabel.Font = Enum.Font.GothamBold
	titleLabel.TextSize = 16
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.ZIndex = 4
	titleLabel.Parent = header

	-- Unread count badge in header
	local badge = Instance.new("TextLabel")
	badge.Name = "UnreadCount"
	badge.Size = UDim2.fromOffset(26, 20)
	badge.AnchorPoint = Vector2.new(1, 0.5)
	badge.Position = UDim2.new(1, -56, 0.5, 0)
	badge.BackgroundColor3 = UNREAD_DOT
	badge.BorderSizePixel = 0
	badge.Text = "0"
	badge.TextColor3 = Color3.fromRGB(255, 255, 255)
	badge.Font = Enum.Font.GothamBold
	badge.TextSize = 12
	badge.Visible = false
	badge.ZIndex = 4
	badge.Parent = header
	unreadCountLabel = badge

	local badgeCorner = Instance.new("UICorner")
	badgeCorner.CornerRadius = UDim.new(0, 4)
	badgeCorner.Parent = badge

	-- Close button
	local closeBtn = Instance.new("TextButton")
	closeBtn.Name = "CloseButton"
	closeBtn.Size = UDim2.fromOffset(32, 32)
	closeBtn.AnchorPoint = Vector2.new(1, 0.5)
	closeBtn.Position = UDim2.new(1, -8, 0.5, 0)
	closeBtn.BackgroundColor3 = CLOSE_BG
	closeBtn.BorderSizePixel = 0
	closeBtn.Text = "✕"
	closeBtn.TextColor3 = TEXT_PRIMARY
	closeBtn.Font = Enum.Font.GothamBold
	closeBtn.TextSize = 14
	closeBtn.ZIndex = 5
	closeBtn.Parent = header
	closeBtn.Activated:Connect(function()
		NotificationInboxUI.SetVisible(false)
	end)

	local closeBtnCorner = Instance.new("UICorner")
	closeBtnCorner.CornerRadius = UDim.new(0, 6)
	closeBtnCorner.Parent = closeBtn

	-- Mark-all-read button
	local markAllBtn = Instance.new("TextButton")
	markAllBtn.Name = "MarkAllRead"
	markAllBtn.Size = UDim2.new(1, -16, 0, 30)
	markAllBtn.Position = UDim2.fromOffset(8, 52)
	markAllBtn.BackgroundColor3 = Color3.fromRGB(30, 60, 100)
	markAllBtn.BorderSizePixel = 0
	markAllBtn.Text = "Mark all as read"
	markAllBtn.TextColor3 = TEXT_SECONDARY
	markAllBtn.Font = Enum.Font.Gotham
	markAllBtn.TextSize = 12
	markAllBtn.ZIndex = 3
	markAllBtn.Parent = window
	markAllBtn.Activated:Connect(function()
		for _, n in ipairs(notifications) do
			n.Read = true
		end
		rebuildList()
		updateUnreadBadge()
	end)

	local markAllCorner = Instance.new("UICorner")
	markAllCorner.CornerRadius = UDim.new(0, 6)
	markAllCorner.Parent = markAllBtn

	-- Notification list
	local listFrame = Instance.new("ScrollingFrame")
	listFrame.Name = "NotificationList"
	listFrame.Size = UDim2.new(1, -8, 1, -92)
	listFrame.Position = UDim2.fromOffset(4, 90)
	listFrame.BackgroundTransparency = 1
	listFrame.BorderSizePixel = 0
	listFrame.ScrollBarThickness = 4
	listFrame.ScrollBarImageColor3 = HEADER_BG
	listFrame.CanvasSize = UDim2.fromOffset(0, 0)
	listFrame.ZIndex = 3
	listFrame.Parent = window
	notifListFrame = listFrame

	local listLayout = Instance.new("UIListLayout")
	listLayout.Padding = UDim.new(0, 6)
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Parent = listFrame

	local listPadding = Instance.new("UIPadding")
	listPadding.PaddingTop = UDim.new(0, 4)
	listPadding.PaddingBottom = UDim.new(0, 4)
	listPadding.Parent = listFrame
end

local function animateOpen()
	if not windowFrame or not gui then
		return
	end
	gui.Enabled = true
	windowFrame.Position = UDim2.new(0.5, 0, 0.55, 0)
	windowFrame.GroupTransparency = 0.4
	TweenService:Create(windowFrame, OPEN_TWEEN, {
		Position = UDim2.fromScale(0.5, 0.5),
		GroupTransparency = 0,
	}):Play()
end

local function animateClose(onDone: () -> ())
	if not windowFrame or not gui then
		onDone()
		return
	end
	local tween = TweenService:Create(windowFrame, CLOSE_TWEEN, {
		Position = UDim2.new(0.5, 0, 0.55, 0),
		GroupTransparency = 0.4,
	})
	tween.Completed:Connect(function()
		if gui then
			gui.Enabled = false
		end
		onDone()
	end)
	tween:Play()
end

function NotificationInboxUI.SetVisible(visible: boolean)
	if not initialized then
		return
	end
	if visible == open then
		return
	end
	open = visible
	if visible then
		rebuildList()
		updateUnreadBadge()
		animateOpen()
	else
		animateClose(function() end)
	end
end

function NotificationInboxUI.Toggle()
	NotificationInboxUI.SetVisible(not open)
end

function NotificationInboxUI.Init()
	if initialized then
		return
	end
	initialized = true

	buildGui()
	rebuildList()

	-- Subscribe to full state snapshot (sent on join and on request)
	NotificationPackets.StateSnapshot.OnClientEvent:Connect(function(payload)
		if type(payload) ~= "table" or type(payload.Queue) ~= "table" then
			return
		end
		applySnapshot(payload.Queue)
		if open then
			rebuildList()
		end
		updateUnreadBadge()
	end)

	-- Subscribe to incremental delta (new notification added)
	NotificationPackets.NotificationDelta.OnClientEvent:Connect(function(payload)
		if type(payload) ~= "table" then
			return
		end
		applyDelta(payload)
		if open then
			rebuildList()
		end
		updateUnreadBadge()
	end)
end

return NotificationInboxUI
