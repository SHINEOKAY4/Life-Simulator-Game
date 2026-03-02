--!strict
-- StarterPlayerScripts/Client/UserInterface/EmoteUI.luau
-- Panel showing the player's available emotes. Click a card to perform it.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local EmotePackets = require(ReplicatedStorage.Network.EmotePackets)

local EmoteUI = {}

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

local gui: ScreenGui? = nil
local windowFrame: Frame? = nil
local emoteListFrame: ScrollingFrame? = nil
local open = false
local initialized = false

local PANEL_BG = Color3.fromRGB(18, 22, 30)
local HEADER_BG = Color3.fromRGB(100, 50, 150)
local CARD_BG = Color3.fromRGB(28, 34, 44)
local CARD_HOVER_BG = Color3.fromRGB(40, 48, 62)
local TEXT_PRIMARY = Color3.fromRGB(235, 240, 255)
local TEXT_SECONDARY = Color3.fromRGB(160, 175, 200)
local TEXT_MUTED = Color3.fromRGB(100, 115, 140)
local ACCENT = Color3.fromRGB(190, 120, 255)
local BUTTON_BG = Color3.fromRGB(120, 60, 180)
local BUTTON_TEXT = Color3.fromRGB(255, 255, 255)

local OPEN_TWEEN = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local CLOSE_TWEEN = TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

local EMOTE_ICONS: { [string]: string } = {
	wave = "👋",
	dance = "💃",
	laugh = "😂",
	cry = "😢",
	clap = "👏",
}

local function getEmoteIcon(emoteId: string): string
	return EMOTE_ICONS[emoteId] or "🎭"
end

local function performEmote(emoteId: string)
	EmotePackets.PerformEmote.InvokeServer(emoteId)
end

local function clearEmoteList()
	if not emoteListFrame then
		return
	end
	for _, child in ipairs(emoteListFrame:GetChildren()) do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
end

local function buildEmoteCard(emoteInfo: { id: string, name: string, description: string }, index: number)
	if not emoteListFrame then
		return
	end

	local card = Instance.new("Frame")
	card.Name = "EmoteCard_" .. emoteInfo.id
	card.Size = UDim2.new(1, 0, 0, 72)
	card.BackgroundColor3 = CARD_BG
	card.BorderSizePixel = 0
	card.LayoutOrder = index
	card.Parent = emoteListFrame

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = card

	-- Emoji icon
	local iconLabel = Instance.new("TextLabel")
	iconLabel.Name = "Icon"
	iconLabel.AnchorPoint = Vector2.new(0, 0.5)
	iconLabel.Position = UDim2.new(0, 12, 0.5, 0)
	iconLabel.Size = UDim2.fromOffset(40, 40)
	iconLabel.BackgroundTransparency = 1
	iconLabel.Font = Enum.Font.Gotham
	iconLabel.Text = getEmoteIcon(emoteInfo.id)
	iconLabel.TextColor3 = TEXT_PRIMARY
	iconLabel.TextSize = 28
	iconLabel.TextXAlignment = Enum.TextXAlignment.Center
	iconLabel.Parent = card

	-- Emote name
	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "EmoteName"
	nameLabel.AnchorPoint = Vector2.new(0, 0)
	nameLabel.Position = UDim2.new(0, 62, 0, 10)
	nameLabel.Size = UDim2.new(1, -150, 0, 22)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.Text = emoteInfo.name
	nameLabel.TextColor3 = TEXT_PRIMARY
	nameLabel.TextSize = 15
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
	nameLabel.Parent = card

	-- Description
	local descLabel = Instance.new("TextLabel")
	descLabel.Name = "EmoteDesc"
	descLabel.AnchorPoint = Vector2.new(0, 0)
	descLabel.Position = UDim2.new(0, 62, 0, 34)
	descLabel.Size = UDim2.new(1, -150, 0, 28)
	descLabel.BackgroundTransparency = 1
	descLabel.Font = Enum.Font.Gotham
	descLabel.Text = emoteInfo.description
	descLabel.TextColor3 = TEXT_SECONDARY
	descLabel.TextSize = 12
	descLabel.TextWrapped = true
	descLabel.TextXAlignment = Enum.TextXAlignment.Left
	descLabel.Parent = card

	-- Perform button
	local btn = Instance.new("TextButton")
	btn.Name = "PerformButton"
	btn.AnchorPoint = Vector2.new(1, 0.5)
	btn.Position = UDim2.new(1, -12, 0.5, 0)
	btn.Size = UDim2.fromOffset(72, 34)
	btn.BackgroundColor3 = BUTTON_BG
	btn.BorderSizePixel = 0
	btn.Font = Enum.Font.GothamBold
	btn.Text = "Do it!"
	btn.TextColor3 = BUTTON_TEXT
	btn.TextSize = 13
	btn.AutoButtonColor = false
	btn.Parent = card

	local btnCorner = Instance.new("UICorner")
	btnCorner.CornerRadius = UDim.new(0, 6)
	btnCorner.Parent = btn

	-- Hover highlight on card
	card.MouseEnter:Connect(function()
		card.BackgroundColor3 = CARD_HOVER_BG
	end)
	card.MouseLeave:Connect(function()
		card.BackgroundColor3 = CARD_BG
	end)

	btn.MouseButton1Down:Connect(function()
		btn.BackgroundColor3 = Color3.fromRGB(80, 30, 130)
	end)
	btn.MouseButton1Up:Connect(function()
		btn.BackgroundColor3 = BUTTON_BG
	end)

	btn.Activated:Connect(function()
		performEmote(emoteInfo.id)
		EmoteUI.SetVisible(false)
	end)
end

local function populateEmotes(emotes: { { id: string, name: string, description: string } })
	clearEmoteList()
	if #emotes == 0 then
		-- Show empty state
		if emoteListFrame then
			local noEmotes = Instance.new("TextLabel")
			noEmotes.Name = "NoEmotesLabel"
			noEmotes.Size = UDim2.new(1, 0, 0, 60)
			noEmotes.BackgroundTransparency = 1
			noEmotes.Font = Enum.Font.Gotham
			noEmotes.Text = "No emotes available yet."
			noEmotes.TextColor3 = TEXT_MUTED
			noEmotes.TextSize = 14
			noEmotes.TextXAlignment = Enum.TextXAlignment.Center
			noEmotes.Parent = emoteListFrame
		end
		return
	end
	for i, emoteInfo in ipairs(emotes) do
		buildEmoteCard(emoteInfo, i)
	end
	-- Update canvas height for scrolling
	if emoteListFrame then
		emoteListFrame.CanvasSize = UDim2.new(0, 0, 0, #emotes * 80)
	end
end

local function fetchAndPopulate()
	local ok, emotes = EmotePackets.GetEmotes.InvokeServer()
	if ok and typeof(emotes) == "table" then
		populateEmotes(emotes)
	end
end

local function ensureGui()
	if gui and gui.Parent then
		return
	end

	gui = Instance.new("ScreenGui")
	gui.Name = "EmoteGui"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 66
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
			EmoteUI.SetVisible(false)
		end
	end)

	-- Main window
	local win = Instance.new("Frame")
	win.Name = "Window"
	win.AnchorPoint = Vector2.new(0.5, 0.5)
	win.Position = UDim2.fromScale(0.5, 0.5)
	win.Size = UDim2.fromOffset(380, 420)
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
	titleLabel.Text = "Emotes"
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
		EmoteUI.SetVisible(false)
	end)

	-- Subtitle
	local subtitle = Instance.new("TextLabel")
	subtitle.Name = "Subtitle"
	subtitle.AnchorPoint = Vector2.new(0, 0)
	subtitle.Position = UDim2.fromOffset(16, 60)
	subtitle.Size = UDim2.new(1, -32, 0, 20)
	subtitle.BackgroundTransparency = 1
	subtitle.Font = Enum.Font.GothamMedium
	subtitle.Text = "Express yourself!"
	subtitle.TextColor3 = ACCENT
	subtitle.TextSize = 13
	subtitle.TextXAlignment = Enum.TextXAlignment.Left
	subtitle.ZIndex = 3
	subtitle.Parent = win

	-- Emote scroll list
	local scrollFrame = Instance.new("ScrollingFrame")
	scrollFrame.Name = "EmoteList"
	scrollFrame.AnchorPoint = Vector2.new(0, 0)
	scrollFrame.Position = UDim2.fromOffset(0, 88)
	scrollFrame.Size = UDim2.new(1, 0, 1, -88)
	scrollFrame.BackgroundTransparency = 1
	scrollFrame.BorderSizePixel = 0
	scrollFrame.ScrollBarThickness = 4
	scrollFrame.ScrollBarImageColor3 = ACCENT
	scrollFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
	scrollFrame.ZIndex = 3
	scrollFrame.Parent = win
	emoteListFrame = scrollFrame

	local listPadding = Instance.new("UIPadding")
	listPadding.PaddingLeft = UDim.new(0, 12)
	listPadding.PaddingRight = UDim.new(0, 12)
	listPadding.PaddingTop = UDim.new(0, 8)
	listPadding.PaddingBottom = UDim.new(0, 8)
	listPadding.Parent = scrollFrame

	local listLayout = Instance.new("UIListLayout")
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Padding = UDim.new(0, 8)
	listLayout.Parent = scrollFrame
end

local function animateOpen()
	if not gui or not windowFrame then
		return
	end
	gui.Enabled = true
	windowFrame.Size = UDim2.fromOffset(380, 420)
	local tween = TweenService:Create(windowFrame, OPEN_TWEEN, {
		Size = UDim2.fromOffset(380, 420),
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
		Size = UDim2.fromOffset(380, 0),
	})
	tween.Completed:Connect(function()
		if gui then
			gui.Enabled = false
		end
		if windowFrame then
			windowFrame.Size = UDim2.fromOffset(380, 420)
		end
		if callback then
			callback()
		end
	end)
	tween:Play()
end

function EmoteUI.SetVisible(visible: boolean)
	if not initialized then
		return
	end
	if visible == open then
		return
	end
	open = visible
	if visible then
		ensureGui()
		task.spawn(fetchAndPopulate)
		animateOpen()
	else
		animateClose()
	end
end

function EmoteUI.Toggle()
	EmoteUI.SetVisible(not open)
end

function EmoteUI.Init()
	if initialized then
		return
	end
	initialized = true
	ensureGui()
end

return EmoteUI
