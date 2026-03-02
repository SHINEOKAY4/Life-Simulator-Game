--!strict
-- StarterPlayerScripts/Client/UserInterface/WorldEventUI.luau
-- Panel UI showing the active world event, its buffs, and the rotation countdown.
-- Subscribes to WorldEventController.StateChanged for live updates.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local WorldEventController = require(script.Parent.Parent.Modules.WorldEventController)

local WorldEventUI = {}

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

local gui: ScreenGui? = nil
local windowFrame: Frame? = nil
local eventNameLabel: TextLabel? = nil
local eventKindLabel: TextLabel? = nil
local eventDescLabel: TextLabel? = nil
local buffListFrame: Frame? = nil
local countdownLabel: TextLabel? = nil
local noEventLabel: TextLabel? = nil
local open = false
local initialized = false

-- Countdown ticker connection
local countdownConnection: RBXScriptConnection? = nil

local PANEL_BG = Color3.fromRGB(18, 22, 30)
local HEADER_BG = Color3.fromRGB(30, 80, 140)
local BUFF_ROW_BG = Color3.fromRGB(28, 34, 44)
local TEXT_PRIMARY = Color3.fromRGB(235, 240, 255)
local TEXT_SECONDARY = Color3.fromRGB(160, 175, 200)
local TEXT_BUFF = Color3.fromRGB(120, 230, 175)
local TEXT_MUTED = Color3.fromRGB(100, 115, 140)
local ACCENT = Color3.fromRGB(60, 160, 255)

local OPEN_TWEEN = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local CLOSE_TWEEN = TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

local function formatCountdown(secondsLeft: number): string
	if secondsLeft <= 0 then
		return "Event ending…"
	end
	local s = math.floor(secondsLeft)
	local hours = math.floor(s / 3600)
	local minutes = math.floor((s % 3600) / 60)
	local secs = s % 60
	if hours > 0 then
		return string.format("Ends in %dh %02dm", hours, minutes)
	elseif minutes > 0 then
		return string.format("Ends in %dm %02ds", minutes, secs)
	else
		return string.format("Ends in %ds", secs)
	end
end

local function formatBuffValue(value: number): string
	-- Convert multiplier (e.g. 1.25) to a "+25%" display
	local pct = math.round((value - 1.0) * 100)
	return string.format("+%d%%", pct)
end

local function clearBuffList()
	if not buffListFrame then
		return
	end
	for _, child in ipairs(buffListFrame:GetChildren()) do
		if child:IsA("Frame") or child:IsA("TextLabel") then
			child:Destroy()
		end
	end
end

local function buildBuffRow(label: string, value: number, index: number)
	if not buffListFrame then
		return
	end

	local row = Instance.new("Frame")
	row.Name = "BuffRow_" .. index
	row.Size = UDim2.new(1, 0, 0, 32)
	row.BackgroundColor3 = BUFF_ROW_BG
	row.BorderSizePixel = 0
	row.LayoutOrder = index
	row.Parent = buffListFrame

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 4)
	corner.Parent = row

	local labelText = Instance.new("TextLabel")
	labelText.Name = "BuffLabel"
	labelText.AnchorPoint = Vector2.new(0, 0.5)
	labelText.Position = UDim2.new(0, 10, 0.5, 0)
	labelText.Size = UDim2.new(0.7, -14, 1, 0)
	labelText.BackgroundTransparency = 1
	labelText.Font = Enum.Font.Gotham
	labelText.Text = label
	labelText.TextColor3 = TEXT_SECONDARY
	labelText.TextSize = 13
	labelText.TextXAlignment = Enum.TextXAlignment.Left
	labelText.TextTruncate = Enum.TextTruncate.AtEnd
	labelText.Parent = row

	local valueText = Instance.new("TextLabel")
	valueText.Name = "BuffValue"
	valueText.AnchorPoint = Vector2.new(1, 0.5)
	valueText.Position = UDim2.new(1, -10, 0.5, 0)
	valueText.Size = UDim2.new(0.3, -4, 1, 0)
	valueText.BackgroundTransparency = 1
	valueText.Font = Enum.Font.GothamBold
	valueText.Text = formatBuffValue(value)
	valueText.TextColor3 = TEXT_BUFF
	valueText.TextSize = 14
	valueText.TextXAlignment = Enum.TextXAlignment.Right
	valueText.Parent = row
end

local function refreshCountdown(endsAt: number)
	if not countdownLabel then
		return
	end
	if countdownConnection then
		countdownConnection:Disconnect()
		countdownConnection = nil
	end
	if endsAt <= 0 then
		countdownLabel.Text = ""
		return
	end

	local function tick()
		if not countdownLabel then
			return
		end
		local now = os.time()
		local left = endsAt - now
		countdownLabel.Text = formatCountdown(left)
	end

	tick()
	countdownConnection = game:GetService("RunService").Heartbeat:Connect(function()
		tick()
	end)
end

local function refreshUI()
	if not windowFrame then
		return
	end

	local event = WorldEventController.GetActiveEvent()

	local hasEvent = event ~= nil
	if noEventLabel then
		noEventLabel.Visible = not hasEvent
	end
	if eventNameLabel then
		eventNameLabel.Visible = hasEvent
	end
	if eventKindLabel then
		eventKindLabel.Visible = hasEvent
	end
	if eventDescLabel then
		eventDescLabel.Visible = hasEvent
	end
	if buffListFrame then
		buffListFrame.Visible = hasEvent
	end
	if countdownLabel then
		countdownLabel.Visible = hasEvent
	end

	clearBuffList()

	if not hasEvent then
		refreshCountdown(0)
		return
	end

	local ev = event :: WorldEventController.RotationEvent

	if eventNameLabel then
		eventNameLabel.Text = ev.Name
	end
	if eventKindLabel then
		eventKindLabel.Text = ev.Kind
	end
	if eventDescLabel then
		eventDescLabel.Text = ev.Description
	end

	local buffs = ev.Buffs or {}
	for i, buff in ipairs(buffs) do
		buildBuffRow(buff.Label, buff.Value, i)
	end

	refreshCountdown(ev.EndsAt)
end

local function ensureGui()
	if gui and gui.Parent then
		return
	end

	gui = Instance.new("ScreenGui")
	gui.Name = "WorldEventGui"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 65
	gui.Enabled = false
	gui.Parent = PlayerGui

	-- Dim overlay
	local overlay = Instance.new("Frame")
	overlay.Name = "Overlay"
	overlay.Size = UDim2.fromScale(1, 1)
	overlay.BackgroundColor3 = Color3.fromRGB(8, 10, 14)
	overlay.BackgroundTransparency = 0.45
	overlay.BorderSizePixel = 0
	overlay.ZIndex = 1
	overlay.Parent = gui

	overlay.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			WorldEventUI.SetVisible(false)
		end
	end)

	-- Main window
	local win = Instance.new("Frame")
	win.Name = "Window"
	win.AnchorPoint = Vector2.new(0.5, 0.5)
	win.Position = UDim2.fromScale(0.5, 0.5)
	win.Size = UDim2.fromOffset(420, 360)
	win.BackgroundColor3 = PANEL_BG
	win.BorderSizePixel = 0
	win.ZIndex = 2
	win.Parent = gui
	windowFrame = win

	local winCorner = Instance.new("UICorner")
	winCorner.CornerRadius = UDim.new(0, 10)
	winCorner.Parent = win

	-- Header bar
	local header = Instance.new("Frame")
	header.Name = "Header"
	header.Size = UDim2.new(1, 0, 0, 52)
	header.BackgroundColor3 = HEADER_BG
	header.BorderSizePixel = 0
	header.ZIndex = 3
	header.Parent = win

	local headerCorner = Instance.new("UICorner")
	headerCorner.CornerRadius = UDim.new(0, 10)
	headerCorner.Parent = header

	-- Square off bottom corners of header
	local headerSquareBottom = Instance.new("Frame")
	headerSquareBottom.Size = UDim2.new(1, 0, 0.5, 0)
	headerSquareBottom.Position = UDim2.fromScale(0, 0.5)
	headerSquareBottom.BackgroundColor3 = HEADER_BG
	headerSquareBottom.BorderSizePixel = 0
	headerSquareBottom.ZIndex = 3
	headerSquareBottom.Parent = header

	local titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "Title"
	titleLabel.Size = UDim2.new(1, -60, 1, 0)
	titleLabel.Position = UDim2.fromOffset(16, 0)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Font = Enum.Font.GothamBold
	titleLabel.Text = "World Events"
	titleLabel.TextColor3 = TEXT_PRIMARY
	titleLabel.TextSize = 18
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.ZIndex = 4
	titleLabel.Parent = header

	-- Close button
	local closeBtn = Instance.new("TextButton")
	closeBtn.Name = "CloseButton"
	closeBtn.AnchorPoint = Vector2.new(1, 0.5)
	closeBtn.Position = UDim2.new(1, -12, 0.5, 0)
	closeBtn.Size = UDim2.fromOffset(28, 28)
	closeBtn.BackgroundTransparency = 1
	closeBtn.Font = Enum.Font.GothamBold
	closeBtn.Text = "✕"
	closeBtn.TextColor3 = TEXT_PRIMARY
	closeBtn.TextSize = 16
	closeBtn.ZIndex = 5
	closeBtn.Parent = header
	closeBtn.Activated:Connect(function()
		WorldEventUI.SetVisible(false)
	end)

	-- Content area
	local content = Instance.new("Frame")
	content.Name = "Content"
	content.Position = UDim2.fromOffset(0, 52)
	content.Size = UDim2.new(1, 0, 1, -52)
	content.BackgroundTransparency = 1
	content.ZIndex = 3
	content.Parent = win

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 16)
	padding.PaddingRight = UDim.new(0, 16)
	padding.PaddingTop = UDim.new(0, 14)
	padding.PaddingBottom = UDim.new(0, 14)
	padding.Parent = content

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 10)
	layout.Parent = content

	-- No event placeholder
	local noEvt = Instance.new("TextLabel")
	noEvt.Name = "NoEventLabel"
	noEvt.Size = UDim2.new(1, 0, 0, 60)
	noEvt.BackgroundTransparency = 1
	noEvt.Font = Enum.Font.Gotham
	noEvt.Text = "No active world event right now.\nCheck back soon!"
	noEvt.TextColor3 = TEXT_MUTED
	noEvt.TextSize = 14
	noEvt.TextWrapped = true
	noEvt.TextXAlignment = Enum.TextXAlignment.Center
	noEvt.LayoutOrder = 0
	noEvt.Visible = false
	noEvt.ZIndex = 3
	noEvt.Parent = content
	noEventLabel = noEvt

	-- Event name
	local evName = Instance.new("TextLabel")
	evName.Name = "EventName"
	evName.Size = UDim2.new(1, 0, 0, 26)
	evName.BackgroundTransparency = 1
	evName.Font = Enum.Font.GothamBold
	evName.Text = ""
	evName.TextColor3 = TEXT_PRIMARY
	evName.TextSize = 20
	evName.TextXAlignment = Enum.TextXAlignment.Left
	evName.TextTruncate = Enum.TextTruncate.AtEnd
	evName.LayoutOrder = 1
	evName.Visible = false
	evName.ZIndex = 3
	evName.Parent = content
	eventNameLabel = evName

	-- Event kind badge
	local evKind = Instance.new("TextLabel")
	evKind.Name = "EventKind"
	evKind.Size = UDim2.new(1, 0, 0, 18)
	evKind.BackgroundTransparency = 1
	evKind.Font = Enum.Font.GothamMedium
	evKind.Text = ""
	evKind.TextColor3 = ACCENT
	evKind.TextSize = 12
	evKind.TextXAlignment = Enum.TextXAlignment.Left
	evKind.LayoutOrder = 2
	evKind.Visible = false
	evKind.ZIndex = 3
	evKind.Parent = content
	eventKindLabel = evKind

	-- Event description
	local evDesc = Instance.new("TextLabel")
	evDesc.Name = "EventDescription"
	evDesc.Size = UDim2.new(1, 0, 0, 52)
	evDesc.BackgroundTransparency = 1
	evDesc.Font = Enum.Font.Gotham
	evDesc.Text = ""
	evDesc.TextColor3 = TEXT_SECONDARY
	evDesc.TextSize = 13
	evDesc.TextWrapped = true
	evDesc.TextXAlignment = Enum.TextXAlignment.Left
	evDesc.LayoutOrder = 3
	evDesc.Visible = false
	evDesc.ZIndex = 3
	evDesc.Parent = content
	eventDescLabel = evDesc

	-- Buffs section header
	local buffsHeader = Instance.new("TextLabel")
	buffsHeader.Name = "BuffsHeader"
	buffsHeader.Size = UDim2.new(1, 0, 0, 18)
	buffsHeader.BackgroundTransparency = 1
	buffsHeader.Font = Enum.Font.GothamBold
	buffsHeader.Text = "Active Bonuses"
	buffsHeader.TextColor3 = TEXT_MUTED
	buffsHeader.TextSize = 11
	buffsHeader.TextXAlignment = Enum.TextXAlignment.Left
	buffsHeader.LayoutOrder = 4
	buffsHeader.ZIndex = 3
	buffsHeader.Parent = content

	-- Buff list
	local buffList = Instance.new("Frame")
	buffList.Name = "BuffList"
	buffList.Size = UDim2.new(1, 0, 0, 110)
	buffList.BackgroundTransparency = 1
	buffList.LayoutOrder = 5
	buffList.Visible = false
	buffList.ZIndex = 3
	buffList.Parent = content
	buffListFrame = buffList

	local buffLayout = Instance.new("UIListLayout")
	buffLayout.SortOrder = Enum.SortOrder.LayoutOrder
	buffLayout.Padding = UDim.new(0, 5)
	buffLayout.Parent = buffList

	-- Countdown
	local countdown = Instance.new("TextLabel")
	countdown.Name = "CountdownLabel"
	countdown.Size = UDim2.new(1, 0, 0, 20)
	countdown.BackgroundTransparency = 1
	countdown.Font = Enum.Font.GothamMedium
	countdown.Text = ""
	countdown.TextColor3 = TEXT_MUTED
	countdown.TextSize = 12
	countdown.TextXAlignment = Enum.TextXAlignment.Right
	countdown.LayoutOrder = 6
	countdown.Visible = false
	countdown.ZIndex = 3
	countdown.Parent = content
	countdownLabel = countdown
end

local function animateOpen()
	if not gui or not windowFrame then
		return
	end
	gui.Enabled = true
	windowFrame.Size = UDim2.fromOffset(420, 360)
	local tween = TweenService:Create(windowFrame, OPEN_TWEEN, {
		Size = UDim2.fromOffset(420, 360),
	})
	tween:Play()
end

local function animateClose(callback: (() -> ())?)
	if not windowFrame then
		if callback then
			callback()
		end
		return
	end
	local tween = TweenService:Create(windowFrame, CLOSE_TWEEN, {
		Size = UDim2.fromOffset(420, 0),
	})
	tween.Completed:Connect(function()
		if gui then
			gui.Enabled = false
		end
		if windowFrame then
			windowFrame.Size = UDim2.fromOffset(420, 360)
		end
		if callback then
			callback()
		end
	end)
	tween:Play()
end

function WorldEventUI.SetVisible(visible: boolean)
	if not initialized then
		return
	end
	if visible == open then
		return
	end
	open = visible
	if visible then
		ensureGui()
		refreshUI()
		animateOpen()
	else
		animateClose()
	end
end

function WorldEventUI.Toggle()
	WorldEventUI.SetVisible(not open)
end

function WorldEventUI.Init()
	if initialized then
		return
	end
	initialized = true
	ensureGui()

	WorldEventController.StateChanged:Connect(function()
		if open then
			refreshUI()
		end
	end)
end

return WorldEventUI
