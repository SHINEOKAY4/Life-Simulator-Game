--!strict
-- StarterPlayerScripts/Client/UserInterface/PlotBuilderUI.lua

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")

local PlotBuilder = require(script.Parent.Parent.Modules.PlotBuilder)

local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")
local PlotBuilderGui = PlayerGui:WaitForChild("PlotBuilderGui")

local ActiveQueryFolder = PlayerGui:FindFirstChild("ActiveQuery")
local LeftDock = PlotBuilderGui:WaitForChild("Main").Bottom.LeftDock
local RightDock = PlotBuilderGui:WaitForChild("Main").Bottom.RightDock

local HomeFrame = LeftDock:WaitForChild("Home")
local FurnitureFrame = LeftDock:WaitForChild("Furnitures")

local CategorySelection = PlotBuilderGui:WaitForChild("CategorySelection")
local HomeSelection = PlotBuilderGui:WaitForChild("HomeSelection")
local FurnitureSelection = PlotBuilderGui:WaitForChild("FurnitureSelection")

local PlotBuilderUI = {}

local ActiveView: string? = nil
type CategoryPanel = "Home" | "Furnitures"
local ActivePanel: CategoryPanel? = nil

local CATEGORY_TAGS = {
	Floors = "Floor",
	Walls = "Wall",
	Roofs = "Roof",
	Decorations = "Decoration",
	Chairs = "Chair",
	Tables = "Table",
	Beds = "Bed",
}

local buttonCache: { [string]: { TextButton } } = {}
local emptyStateLabel: TextLabel? = nil

local function getScrollingFrame(): ScrollingFrame
	local scrollingFrame = RightDock:FindFirstChild("ScrollingFrame")
	assert(
		scrollingFrame and scrollingFrame:IsA("ScrollingFrame"),
		"PlotBuilderUI expects a ScrollingFrame inside RightDock"
	)

	if not scrollingFrame:FindFirstChildWhichIsA("UIListLayout") then
		local layout = Instance.new("UIListLayout")
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Padding = UDim.new(0, 4)
		layout.Parent = scrollingFrame
	end

	return scrollingFrame
end

local function ensureEmptyStateLabel(scrollFrame: ScrollingFrame)
	if emptyStateLabel == nil then
		local label = Instance.new("TextLabel")
		label.Name = "EmptyState"
		label.Size = UDim2.new(1, 0, 0, 32)
		label.BackgroundTransparency = 1
		label.TextColor3 = Color3.fromRGB(200, 200, 200)
		label.Font = Enum.Font.Gotham
		label.TextSize = 18
		label.TextWrapped = true
		label.RichText = true
		emptyStateLabel = label
	end

	local label = emptyStateLabel :: TextLabel
	label.Text = "<i>No items available in this category yet.</i>"
	label.Visible = true
	label.Parent = scrollFrame
end

local function hideEmptyStateLabel()
	local label = emptyStateLabel
	if label ~= nil then
		label.Visible = false
		label.Parent = nil
	end
end

local function createButtonsForCategory(category: string): { TextButton }
	local tag = CATEGORY_TAGS[category]
	if tag == nil then
		warn("PlotBuilderUI received unknown category", category)
		return {}
	end

	local buttons = {}
	for _, itemModel in ipairs(CollectionService:GetTagged(tag)) do
		local button = Instance.new("TextButton")
		button.Name = itemModel.Name
		button.Text = itemModel.Name
		button.Size = UDim2.new(1, -8, 0, 40)
		button.BackgroundColor3 = Color3.fromRGB(45, 45, 45)
		button.TextColor3 = Color3.fromRGB(230, 230, 230)
		button.Font = Enum.Font.Gotham
		button.TextSize = 18
		button.AutoButtonColor = true
		button.LayoutOrder = #buttons

		button.MouseButton1Click:Connect(function()
			print("Selected item: " .. itemModel.Name)
			PlotBuilder.PreviewSelected(itemModel.Name)
		end)

		table.insert(buttons, button)
	end

	buttonCache[category] = buttons
	return buttons
end

local function getButtonsForCategory(category: string): { TextButton }
	local cached = buttonCache[category]
	if cached ~= nil then
		return cached
	end

	return createButtonsForCategory(category)
end

local function detachButtons(buttons: { TextButton })
	for _, button in ipairs(buttons) do
		button.Parent = nil
	end
end

local function attachButtons(scrollFrame: ScrollingFrame, buttons: { TextButton })
	for _, button in ipairs(buttons) do
		button.Parent = scrollFrame
	end
end

local function clearActiveCategory()
	if ActiveView ~= nil then
		local previousButtons = buttonCache[ActiveView]
		if previousButtons ~= nil then
			detachButtons(previousButtons)
		end
		ActiveView = nil
	end

	hideEmptyStateLabel()
end

local function switchCategoryPanel(category: CategoryPanel)
	local scrollFrame = getScrollingFrame()

	ActivePanel = category
	clearActiveCategory()

	local isHome = ActivePanel == "Home"
	HomeFrame.Visible = isHome

	FurnitureFrame.Visible = not isHome

	scrollFrame.Visible = true
end

local function setActiveCategory(category: string)
	if ActiveView == category then
		return
	end

	local scrollFrame = getScrollingFrame()

	if ActiveView ~= nil then
		local previousButtons = buttonCache[ActiveView]
		if previousButtons ~= nil then
			detachButtons(previousButtons)
		end
	end

	ActiveView = category

	local buttons = getButtonsForCategory(category)
	if #buttons == 0 then
		ensureEmptyStateLabel(scrollFrame)
		return
	end

	hideEmptyStateLabel()
	attachButtons(scrollFrame, buttons)
end

function PlotBuilderUI:Init()
	print("PlotBuilderUI initialized")
	local objectPreviewEnabled = ActiveQueryFolder:FindFirstChild("ObjectPreviewEnabled")
	objectPreviewEnabled.Changed:Connect(function()
		local enabled = objectPreviewEnabled.Value
		if enabled then
			PlotBuilderGui.Main.Visible = false
		end
	end)

	CategorySelection.Home.Pressed:Connect(function()
		print("CategorySelection Home button pressed")
		switchCategoryPanel("Home")
	end)

	CategorySelection.Furnitures.Pressed:Connect(function()
		print("CategorySelection Furniture button pressed")
		switchCategoryPanel("Furnitures")
	end)

	HomeSelection.Floors.Pressed:Connect(function()
		print("HomeSelection Floors button pressed")
		setActiveCategory("Floors")
	end)

	HomeSelection.Walls.Pressed:Connect(function()
		print("HomeSelection Walls button pressed")
		setActiveCategory("Walls")
	end)

	HomeSelection.Roofs.Pressed:Connect(function()
		print("HomeSelection Roofs button pressed")
		setActiveCategory("Roofs")
	end)

	HomeSelection.Decorations.Pressed:Connect(function()
		print("HomeSelection Decorations button pressed")
		setActiveCategory("Decorations")
	end)

	FurnitureSelection.Chairs.Pressed:Connect(function()
		print("FurnitureSelection Chairs button pressed")
		setActiveCategory("Chairs")
	end)

	FurnitureSelection.Tables.Pressed:Connect(function()
		print("FurnitureSelection Tables button pressed")
		setActiveCategory("Tables")
	end)

	FurnitureSelection.Beds.Pressed:Connect(function()
		print("FurnitureSelection Beds button pressed")
		setActiveCategory("Beds")
	end)

	switchCategoryPanel("Home")
end

return PlotBuilderUI
