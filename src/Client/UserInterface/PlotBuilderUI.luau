--!strict
-- StarterPlayerScripts/Client/UserInterface/PlotBuilderUI.lua

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlotBuilder = require(script.Parent.Parent.Modules.PlotBuilder)
local Debounce = require(ReplicatedStorage.Shared.Utilities.Debounce)

local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")
local PlotBuilderGui = PlayerGui:WaitForChild("PlotBuilderGui")

local ActiveQueryFolder = PlayerGui:FindFirstChild("ActiveQuery")
local LeftDock = PlotBuilderGui:WaitForChild("Main").Bottom.LeftDock
local RightDock = PlotBuilderGui:WaitForChild("Main").Bottom.RightDock

local HomeFrame = LeftDock:WaitForChild("Home")
local FurnitureFrame = LeftDock:WaitForChild("Furnitures")
local EnvironmentFrame = LeftDock:WaitForChild("Environment")

local CategorySelection = PlotBuilderGui:WaitForChild("CategorySelection")
local HomeSelection = PlotBuilderGui:WaitForChild("HomeSelection")
local FurnitureSelection = PlotBuilderGui:WaitForChild("FurnitureSelection")
local EnvironmentSelection = PlotBuilderGui:WaitForChild("EnvironmentSelection")

local PlotBuilderUI = {}

local ActiveView: string? = nil
type CategoryPanel = "Home" | "Furnitures" | "Environment"
local ActivePanel: CategoryPanel? = nil
local INPUT_DEBOUNCE_SECONDS = 0.2

local function connectDebounced(action: InputAction, actionName: string, callback: () -> ()): ()
	action.Pressed:Connect(function()
		Debounce.RunIfAvailable(
			string.format("PlotBuilderUI/%s", actionName),
			INPUT_DEBOUNCE_SECONDS,
			callback,
			Player.UserId
		)
	end)
end

local CATEGORY_TAGS = {
	Floors = "Floor",
	Walls = "Wall",
	Roofs = "Roof",
	Decorations = "Decoration",
	Doors = "Door",
	Chairs = "Chair",
	Tables = "Table",
	Beds = "Bed",
	Trees = "Tree",
	Plants = "Plant",
	Rocks = "Rock",
	Outdoors = "Outdoor",
	Appliances = "Appliance",
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
	local isFurniture = ActivePanel == "Furnitures"
	local isEnvironment = ActivePanel == "Environment"
	HomeFrame.Visible = isHome

	FurnitureFrame.Visible = isFurniture
	EnvironmentFrame.Visible = isEnvironment

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
	local objectPreviewEnabled = ActiveQueryFolder:FindFirstChild("ObjectPreviewEnabled")
	objectPreviewEnabled.Changed:Connect(function()
		local enabled = objectPreviewEnabled.Value
		if enabled then
			PlotBuilderGui.Main.Visible = false
		end
	end)

	connectDebounced(CategorySelection.Home, "CategoryHome", function()
		print("CategorySelection Home button pressed")
		switchCategoryPanel("Home")
	end)

	connectDebounced(CategorySelection.Furnitures, "CategoryFurniture", function()
		print("CategorySelection Furniture button pressed")
		switchCategoryPanel("Furnitures")
	end)

	connectDebounced(CategorySelection.Environment, "CategoryEnvironment", function()
		print("CategorySelection Environment button pressed")
		switchCategoryPanel("Environment")
	end)

	connectDebounced(HomeSelection.Floors, "HomeFloors", function()
		print("HomeSelection Floors button pressed")
		setActiveCategory("Floors")
	end)

	connectDebounced(HomeSelection.Walls, "HomeWalls", function()
		print("HomeSelection Walls button pressed")
		setActiveCategory("Walls")
	end)

	connectDebounced(HomeSelection.Roofs, "HomeRoofs", function()
		print("HomeSelection Roofs button pressed")
		setActiveCategory("Roofs")
	end)

	connectDebounced(HomeSelection.Decorations, "HomeDecorations", function()
		print("HomeSelection Decorations button pressed")
		setActiveCategory("Decorations")
	end)

	connectDebounced(HomeSelection.Doors, "HomeDoors", function()
		print("HomeSelection Doors button pressed")
		setActiveCategory("Doors")
	end)

	connectDebounced(HomeSelection.Appliances, "HomeAppliances", function()
		print("HomeSelection Appliances button pressed")
		setActiveCategory("Appliances")
	end)

	connectDebounced(FurnitureSelection.Chairs, "FurnitureChairs", function()
		print("FurnitureSelection Chairs button pressed")
		setActiveCategory("Chairs")
	end)

	connectDebounced(FurnitureSelection.Tables, "FurnitureTables", function()
		print("FurnitureSelection Tables button pressed")
		setActiveCategory("Tables")
	end)

	connectDebounced(FurnitureSelection.Beds, "FurnitureBeds", function()
		print("FurnitureSelection Beds button pressed")
		setActiveCategory("Beds")
	end)

	connectDebounced(EnvironmentSelection.Outdoors, "EnvironmentOutdoors", function()
		print("FurnitureSelection Outdoors button pressed")
		setActiveCategory("Outdoors")
	end)

	connectDebounced(EnvironmentSelection.Trees, "EnvironmentTrees", function()
		print("EnvironmentSelection Trees button pressed")
		setActiveCategory("Trees")
	end)

	connectDebounced(EnvironmentSelection.Plants, "EnvironmentPlants", function()
		print("EnvironmentSelection Plants button pressed")
		setActiveCategory("Plants")
	end)

	connectDebounced(EnvironmentSelection.Rocks, "EnvironmentRocks", function()
		print("EnvironmentSelection Rocks button pressed")
		setActiveCategory("Rocks")
	end)

	switchCategoryPanel("Home")
end

return PlotBuilderUI
