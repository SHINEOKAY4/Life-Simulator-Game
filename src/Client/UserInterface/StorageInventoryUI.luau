--!strict
-- Storage Inventory panel: shows stashed items and lets the player place them back for free.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local StashPackets = require(ReplicatedStorage.Network.StashPackets)
local ItemFinder = require(ReplicatedStorage.Shared.Utilities.ItemFinder)
local Notification = require(script.Parent.Notification)

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

-- Lazy-require PlotBuilder to avoid circular requires at module load time.
local PlotBuilder: any = nil
local function getPlotBuilder(): any
	if not PlotBuilder then
		PlotBuilder = require(script.Parent.Parent.Modules.PlotBuilder)
	end
	return PlotBuilder
end

local StorageInventoryUI = {}

local RootGui: ScreenGui?
local Panel: Frame?
local ItemList: ScrollingFrame?
local EmptyLabel: TextLabel?
local CloseButton: TextButton?
local isOpen = false

-- Current stash snapshot: { [itemId]: count }
local currentStash: { [string]: number } = {}

local function findOrCreateGui(): ScreenGui
	local existing = PlayerGui:FindFirstChild("StorageInventoryGui")
	if existing and existing:IsA("ScreenGui") then
		return existing :: ScreenGui
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = "StorageInventoryGui"
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.IgnoreGuiInset = false
	gui.Parent = PlayerGui
	return gui
end

local function buildUI(gui: ScreenGui)
	-- Backdrop / panel
	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.Size = UDim2.new(0, 340, 0, 480)
	panel.Position = UDim2.new(0.5, -170, 0.5, -240)
	panel.BackgroundColor3 = Color3.fromRGB(28, 30, 40)
	panel.BorderSizePixel = 0
	panel.Visible = false
	panel.Parent = gui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = panel

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(80, 90, 130)
	stroke.Thickness = 1.5
	stroke.Parent = panel

	-- Title bar
	local titleBar = Instance.new("Frame")
	titleBar.Size = UDim2.new(1, 0, 0, 44)
	titleBar.BackgroundColor3 = Color3.fromRGB(38, 42, 60)
	titleBar.BorderSizePixel = 0
	titleBar.Parent = panel

	local titleCorner = Instance.new("UICorner")
	titleCorner.CornerRadius = UDim.new(0, 10)
	titleCorner.Parent = titleBar

	-- Cover bottom-rounded corners of title bar
	local titleCoverBottom = Instance.new("Frame")
	titleCoverBottom.Size = UDim2.new(1, 0, 0, 10)
	titleCoverBottom.Position = UDim2.new(0, 0, 1, -10)
	titleCoverBottom.BackgroundColor3 = Color3.fromRGB(38, 42, 60)
	titleCoverBottom.BorderSizePixel = 0
	titleCoverBottom.Parent = titleBar

	local titleLabel = Instance.new("TextLabel")
	titleLabel.Size = UDim2.new(1, -50, 1, 0)
	titleLabel.Position = UDim2.new(0, 14, 0, 0)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Font = Enum.Font.GothamBold
	titleLabel.TextSize = 16
	titleLabel.TextColor3 = Color3.fromRGB(230, 230, 255)
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.Text = "Storage"
	titleLabel.Parent = titleBar

	local closeBtn = Instance.new("TextButton")
	closeBtn.Name = "CloseButton"
	closeBtn.Size = UDim2.new(0, 32, 0, 32)
	closeBtn.Position = UDim2.new(1, -40, 0.5, -16)
	closeBtn.BackgroundTransparency = 1
	closeBtn.Font = Enum.Font.GothamBold
	closeBtn.TextSize = 20
	closeBtn.TextColor3 = Color3.fromRGB(200, 200, 220)
	closeBtn.Text = "×"
	closeBtn.Parent = titleBar

	-- Subtitle hint
	local hint = Instance.new("TextLabel")
	hint.Size = UDim2.new(1, -20, 0, 18)
	hint.Position = UDim2.new(0, 10, 0, 48)
	hint.BackgroundTransparency = 1
	hint.Font = Enum.Font.Gotham
	hint.TextSize = 12
	hint.TextColor3 = Color3.fromRGB(140, 150, 180)
	hint.TextXAlignment = Enum.TextXAlignment.Left
	hint.Text = "Items you've picked up — place them back for free."
	hint.Parent = panel

	-- Item list
	local list = Instance.new("ScrollingFrame")
	list.Name = "ItemList"
	list.Size = UDim2.new(1, -20, 1, -84)
	list.Position = UDim2.new(0, 10, 0, 72)
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.ScrollBarThickness = 4
	list.ScrollBarImageColor3 = Color3.fromRGB(80, 90, 130)
	list.CanvasSize = UDim2.new(0, 0, 0, 0)
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.Parent = panel

	local listLayout = Instance.new("UIListLayout")
	listLayout.Padding = UDim.new(0, 6)
	listLayout.SortOrder = Enum.SortOrder.Name
	listLayout.Parent = list

	local listPad = Instance.new("UIPadding")
	listPad.PaddingTop = UDim.new(0, 4)
	listPad.PaddingBottom = UDim.new(0, 4)
	listPad.Parent = list

	-- Empty state label
	local emptyLabel = Instance.new("TextLabel")
	emptyLabel.Name = "EmptyLabel"
	emptyLabel.Size = UDim2.new(1, 0, 0, 40)
	emptyLabel.BackgroundTransparency = 1
	emptyLabel.Font = Enum.Font.Gotham
	emptyLabel.TextSize = 14
	emptyLabel.TextColor3 = Color3.fromRGB(140, 150, 170)
	emptyLabel.Text = "Your stash is empty.\nPick up items from your plot to store them here."
	emptyLabel.TextWrapped = true
	emptyLabel.Visible = false
	emptyLabel.Parent = panel

	Panel = panel
	ItemList = list
	EmptyLabel = emptyLabel
	CloseButton = closeBtn

	closeBtn.Activated:Connect(function()
		StorageInventoryUI.Hide()
	end)
end

local function resolveItemDisplayName(itemId: string): string
	local data = ItemFinder.FindItemById(itemId)
	if data and typeof(data.Name) == "string" and data.Name ~= "" then
		return data.Name
	end
	return itemId
end

local function clearItemList()
	if not ItemList then
		return
	end
	for _, child in ipairs(ItemList:GetChildren()) do
		if child:IsA("UIListLayout") or child:IsA("UIPadding") then
			continue
		end
		child:Destroy()
	end
end

local function buildItemRow(itemId: string, count: number): Frame
	local row = Instance.new("Frame")
	row.Name = itemId
	row.Size = UDim2.new(1, 0, 0, 52)
	row.BackgroundColor3 = Color3.fromRGB(40, 44, 60)
	row.BorderSizePixel = 0

	local rowCorner = Instance.new("UICorner")
	rowCorner.CornerRadius = UDim.new(0, 6)
	rowCorner.Parent = row

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Size = UDim2.new(1, -110, 0.5, 0)
	nameLabel.Position = UDim2.new(0, 10, 0, 4)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextSize = 14
	nameLabel.TextColor3 = Color3.fromRGB(220, 225, 255)
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
	nameLabel.Text = resolveItemDisplayName(itemId)
	nameLabel.Parent = row

	local countLabel = Instance.new("TextLabel")
	countLabel.Size = UDim2.new(1, -110, 0.5, -4)
	countLabel.Position = UDim2.new(0, 10, 0.5, 0)
	countLabel.BackgroundTransparency = 1
	countLabel.Font = Enum.Font.Gotham
	countLabel.TextSize = 12
	countLabel.TextColor3 = Color3.fromRGB(160, 170, 200)
	countLabel.TextXAlignment = Enum.TextXAlignment.Left
	countLabel.Text = "Qty: " .. tostring(count)
	countLabel.Parent = row

	local placeBtn = Instance.new("TextButton")
	placeBtn.Size = UDim2.new(0, 80, 0, 32)
	placeBtn.Position = UDim2.new(1, -90, 0.5, -16)
	placeBtn.BackgroundColor3 = Color3.fromRGB(70, 140, 240)
	placeBtn.Font = Enum.Font.GothamBold
	placeBtn.TextSize = 13
	placeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	placeBtn.Text = "Place"
	placeBtn.BorderSizePixel = 0
	placeBtn.Parent = row

	local btnCorner = Instance.new("UICorner")
	btnCorner.CornerRadius = UDim.new(0, 6)
	btnCorner.Parent = placeBtn

	placeBtn.Activated:Connect(function()
		-- Close storage panel and start the preview flow in stash mode.
		StorageInventoryUI.Hide()
		local pb = getPlotBuilder()
		pb.SetStashMode(itemId)
		pb.PreviewSelected(itemId)
	end)

	return row
end

local function refreshItemList()
	clearItemList()
	if not ItemList or not EmptyLabel or not Panel then
		return
	end

	-- Count non-zero entries
	local hasItems = false
	for itemId, count in pairs(currentStash) do
		if typeof(count) == "number" and count > 0 then
			hasItems = true
			local row = buildItemRow(itemId, count)
			row.Parent = ItemList
		end
	end

	EmptyLabel.Visible = not hasItems
	if not hasItems then
		EmptyLabel.Position = UDim2.new(0, 10, 0, 72)
		EmptyLabel.Parent = Panel
	end
end

-- Called when the server pushes a stash update.
local function onStashUpdated(items: any)
	if typeof(items) ~= "table" then
		currentStash = {}
	else
		currentStash = items :: { [string]: number }
	end
	if isOpen then
		refreshItemList()
	end
end

function StorageInventoryUI.Show()
	if isOpen then
		return
	end
	if not Panel then
		return
	end

	-- Fetch latest stash from server before showing.
	task.spawn(function()
		local success, _, items = StashPackets.GetStash:Fire()
		if success and typeof(items) == "table" then
			currentStash = items :: { [string]: number }
		end
		refreshItemList()
	end)

	isOpen = true
	Panel.Visible = true
	local uiScale = Panel:FindFirstChild("UIPopupScale")
	if uiScale and uiScale:IsA("UIScale") then
		uiScale.Scale = 0.9
		TweenService:Create(uiScale, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	end
end

function StorageInventoryUI.Hide()
	if not isOpen then
		return
	end
	isOpen = false
	if Panel then
		Panel.Visible = false
	end
end

function StorageInventoryUI.IsOpen(): boolean
	return isOpen
end

function StorageInventoryUI.Init()
	local gui = findOrCreateGui()
	RootGui = gui
	buildUI(gui)

	-- Add a popup UIScale for animation (same pattern as other panels).
	if Panel then
		local scaleInst = Instance.new("UIScale")
		scaleInst.Name = "UIPopupScale"
		scaleInst.Scale = 1
		scaleInst.Parent = Panel
	end

	-- Subscribe to server stash updates.
	StashPackets.StashUpdated.OnClientEvent:Connect(onStashUpdated)
end

return StorageInventoryUI
