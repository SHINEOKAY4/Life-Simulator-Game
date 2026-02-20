--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local CraftingPackets = require(ReplicatedStorage.Network.CraftingPackets)

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

local CraftingUI = {}

local RootGui: ScreenGui
local Panel: Frame
local RecipeList: ScrollingFrame
local RecipeDetail: Frame
local RecipeTitle: TextLabel
local RecipeDescription: TextLabel
local StationLabel: TextLabel
local TimeLabel: TextLabel
local SkillLabel: TextLabel
local IngredientsList: ScrollingFrame
local CraftButton: TextButton
local StatusLabel: TextLabel
local HintLabel: TextLabel

local SelectedRecipeId: string? = nil
local CachedPayload: any = nil
local ActiveCraftEndsAt: number? = nil
local CountdownConnection: RBXScriptConnection? = nil

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

local function formatDuration(seconds: number): string
	local clamped = math.max(0, math.floor(seconds + 0.5))
	local mins = math.floor(clamped / 60)
	local secs = clamped % 60
	if mins > 0 then
		return string.format("%dm %02ds", mins, secs)
	end
	return string.format("%ds", secs)
end

local function findRecipeById(payload: any, recipeId: string): any
	if typeof(payload) ~= "table" or typeof(payload.Recipes) ~= "table" then
		return nil
	end
	for _, recipe in ipairs(payload.Recipes) do
		if recipe.Id == recipeId then
			return recipe
		end
	end
	return nil
end

local function resolveStationInfo(stationId: string): (string, boolean)
	if typeof(CachedPayload) ~= "table" or typeof(CachedPayload.Stations) ~= "table" then
		return stationId, false
	end
	for _, station in ipairs(CachedPayload.Stations) do
		if station.Id == stationId then
			return station.Name or stationId, station.Available == true
		end
	end
	return stationId, false
end

local function refreshCountdown()
	if ActiveCraftEndsAt == nil then
		HintLabel.Text = "Press C to close"
		return
	end
	local remaining = math.max(0, ActiveCraftEndsAt - workspace:GetServerTimeNow())
	HintLabel.Text = string.format("Crafting... %s remaining", formatDuration(remaining))
	if remaining <= 0.05 then
		ActiveCraftEndsAt = nil
		HintLabel.Text = "Press C to close"
	end
end

local function updateCountdownConnection()
	if CountdownConnection then
		CountdownConnection:Disconnect()
		CountdownConnection = nil
	end
	CountdownConnection = RunService.Heartbeat:Connect(refreshCountdown)
end

local function renderDetails()
	local recipeId = SelectedRecipeId
	if not recipeId or typeof(CachedPayload) ~= "table" then
		RecipeTitle.Text = "Select a recipe"
		RecipeDescription.Text = ""
		StationLabel.Text = "Station: -"
		TimeLabel.Text = "Time: -"
		SkillLabel.Text = "Skills: -"
		CraftButton.Active = false
		CraftButton.AutoButtonColor = false
		CraftButton.Text = "Craft"
		clearList(IngredientsList)
		return
	end

	local recipe = findRecipeById(CachedPayload, recipeId)
	if not recipe then
		return
	end

	RecipeTitle.Text = string.format("%s  ->  %dx %s", recipe.Name, recipe.Output.Quantity, recipe.Output.Name)
	RecipeDescription.Text = recipe.Description

	local stationText = "Station: None"
	if typeof(recipe.RequiredStations) == "table" and #recipe.RequiredStations > 0 then
		local labels: { string } = {}
		for _, stationId in ipairs(recipe.RequiredStations) do
			local stationName, available = resolveStationInfo(stationId)
			labels[#labels + 1] = string.format("%s%s", stationName, available and "" or " (Missing)")
		end
		stationText = "Station: " .. table.concat(labels, " or ")
	end
	StationLabel.Text = stationText
	TimeLabel.Text = string.format("Time: %s", formatDuration(recipe.CraftingTimeSeconds or 0))

	local skillSegments: { string } = {}
	if typeof(recipe.SkillRequirements) == "table" and #recipe.SkillRequirements > 0 then
		for _, requirement in ipairs(recipe.SkillRequirements) do
			local segment = string.format(
				"%s %d/%d",
				requirement.SkillId,
				requirement.CurrentLevel,
				requirement.RequiredLevel
			)
			skillSegments[#skillSegments + 1] = segment
		end
	else
		skillSegments[1] = "None"
	end
	SkillLabel.Text = "Skills: " .. table.concat(skillSegments, "  |  ")

	clearList(IngredientsList)
	if typeof(recipe.Ingredients) == "table" then
		for _, ingredient in ipairs(recipe.Ingredients) do
			local row = Instance.new("TextLabel")
			row.Name = ingredient.ItemId .. "Row"
			row.BackgroundColor3 = Color3.fromRGB(42, 45, 58)
			row.BorderSizePixel = 0
			row.Size = UDim2.new(1, -8, 0, 26)
			row.Font = Enum.Font.Gotham
			row.TextSize = 13
			row.TextXAlignment = Enum.TextXAlignment.Left
			row.TextColor3 = if ingredient.Missing > 0 then Color3.fromRGB(255, 145, 145) else Color3.fromRGB(177, 240, 184)
			row.Text = string.format(
				"  %s: %d / %d",
				ingredient.Name,
				ingredient.Available,
				ingredient.Required
			)
			row.Parent = IngredientsList

			local corner = Instance.new("UICorner")
			corner.CornerRadius = UDim.new(0, 4)
			corner.Parent = row
		end
	end

	CraftButton.Active = recipe.CanCraft == true and ActiveCraftEndsAt == nil
	CraftButton.AutoButtonColor = CraftButton.Active
	if ActiveCraftEndsAt ~= nil then
		CraftButton.Text = "Crafting..."
	elseif recipe.CanCraft == true then
		CraftButton.Text = "Craft"
	else
		CraftButton.Text = "Missing Requirements"
	end
end

local function renderRecipes()
	clearList(RecipeList)

	if typeof(CachedPayload) ~= "table" or typeof(CachedPayload.Recipes) ~= "table" then
		return
	end

	if not SelectedRecipeId and #CachedPayload.Recipes > 0 then
		SelectedRecipeId = CachedPayload.Recipes[1].Id
	end

	table.sort(CachedPayload.Recipes, function(a, b)
		if a.Category == b.Category then
			return a.Name < b.Name
		end
		return a.Category < b.Category
	end)

	for _, recipe in ipairs(CachedPayload.Recipes) do
		local button = Instance.new("TextButton")
		button.Name = recipe.Id
		button.Size = UDim2.new(1, -8, 0, 34)
		button.BackgroundColor3 = if recipe.Id == SelectedRecipeId
			then Color3.fromRGB(58, 87, 130)
			else Color3.fromRGB(36, 39, 48)
		button.BorderSizePixel = 0
		button.Font = Enum.Font.GothamMedium
		button.TextSize = 13
		button.TextXAlignment = Enum.TextXAlignment.Left
		button.TextColor3 = if recipe.CanCraft then Color3.fromRGB(242, 242, 242) else Color3.fromRGB(190, 190, 190)
		button.Text = string.format("  [%s] %s", recipe.Category, recipe.Name)
		button.Parent = RecipeList

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 5)
		corner.Parent = button

		button.Activated:Connect(function()
			SelectedRecipeId = recipe.Id
			renderRecipes()
			renderDetails()
		end)
	end

	renderDetails()
end

local function requestData()
	local ok, success, message, payload = pcall(function()
		return CraftingPackets.GetCraftingData:Fire()
	end)
	if not ok then
		setStatus("Crafting service unavailable.", Color3.fromRGB(255, 145, 145))
		return
	end
	if not success then
		setStatus(message or "Unable to load crafting data.", Color3.fromRGB(255, 145, 145))
		return
	end

	CachedPayload = payload
	if typeof(payload) == "table" and typeof(payload.ActiveJob) == "table" then
		ActiveCraftEndsAt = payload.ActiveJob.EndsAt
	else
		ActiveCraftEndsAt = nil
	end

	renderRecipes()
	refreshCountdown()
	setStatus("", Color3.fromRGB(230, 230, 230))
end

local function chooseStation(recipe: any): string
	if typeof(recipe.RequiredStations) ~= "table" or #recipe.RequiredStations == 0 then
		return ""
	end

	if typeof(CachedPayload) ~= "table" or typeof(CachedPayload.Stations) ~= "table" then
		return recipe.RequiredStations[1]
	end

	for _, stationId in ipairs(recipe.RequiredStations) do
		for _, station in ipairs(CachedPayload.Stations) do
			if station.Id == stationId and station.Available == true then
				return stationId
			end
		end
	end

	return recipe.RequiredStations[1]
end

local function onCraftPressed()
	if not SelectedRecipeId or ActiveCraftEndsAt ~= nil then
		return
	end
	if typeof(CachedPayload) ~= "table" then
		return
	end

	local recipe = findRecipeById(CachedPayload, SelectedRecipeId)
	if not recipe then
		return
	end

	local stationId = chooseStation(recipe)
	local ok, success, message, result = pcall(function()
		return CraftingPackets.StartCrafting:Fire(SelectedRecipeId :: string, stationId)
	end)
	if not ok then
		setStatus("Failed to submit craft request.", Color3.fromRGB(255, 145, 145))
		return
	end
	if not success then
		setStatus(message or "Craft request rejected.", Color3.fromRGB(255, 145, 145))
		requestData()
		return
	end

	if typeof(result) == "table" and typeof(result.EndsAt) == "number" then
		ActiveCraftEndsAt = result.EndsAt
	end
	setStatus(message or "Crafting started.", Color3.fromRGB(177, 240, 184))
	renderDetails()
	refreshCountdown()
end

local function buildUi()
	RootGui = Instance.new("ScreenGui")
	RootGui.Name = "CraftingMenu"
	RootGui.ResetOnSpawn = false
	RootGui.Enabled = false
	RootGui.DisplayOrder = 35
	RootGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	RootGui.Parent = PlayerGui

	Panel = Instance.new("Frame")
	Panel.Name = "Panel"
	Panel.AnchorPoint = Vector2.new(0.5, 0.5)
	Panel.Position = UDim2.fromScale(0.5, 0.52)
	Panel.Size = UDim2.fromOffset(980, 560)
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

	local header = Instance.new("TextLabel")
	header.BackgroundTransparency = 1
	header.Position = UDim2.fromOffset(20, 14)
	header.Size = UDim2.fromOffset(320, 30)
	header.Font = Enum.Font.GothamBold
	header.Text = "Crafting"
	header.TextSize = 24
	header.TextXAlignment = Enum.TextXAlignment.Left
	header.TextColor3 = Color3.fromRGB(242, 242, 242)
	header.Parent = Panel

	HintLabel = Instance.new("TextLabel")
	HintLabel.BackgroundTransparency = 1
	HintLabel.AnchorPoint = Vector2.new(1, 0)
	HintLabel.Position = UDim2.new(1, -16, 0, 16)
	HintLabel.Size = UDim2.fromOffset(280, 24)
	HintLabel.Font = Enum.Font.Gotham
	HintLabel.Text = "Press C to close"
	HintLabel.TextSize = 13
	HintLabel.TextXAlignment = Enum.TextXAlignment.Right
	HintLabel.TextColor3 = Color3.fromRGB(195, 205, 224)
	HintLabel.Parent = Panel

	RecipeList = Instance.new("ScrollingFrame")
	RecipeList.Name = "RecipeList"
	RecipeList.Position = UDim2.fromOffset(16, 56)
	RecipeList.Size = UDim2.new(0, 340, 1, -118)
	RecipeList.BackgroundColor3 = Color3.fromRGB(29, 32, 42)
	RecipeList.BorderSizePixel = 0
	RecipeList.AutomaticCanvasSize = Enum.AutomaticSize.Y
	RecipeList.ScrollBarThickness = 6
	RecipeList.CanvasSize = UDim2.fromOffset(0, 0)
	RecipeList.Parent = Panel

	local listCorner = Instance.new("UICorner")
	listCorner.CornerRadius = UDim.new(0, 8)
	listCorner.Parent = RecipeList

	local listLayout = Instance.new("UIListLayout")
	listLayout.Padding = UDim.new(0, 6)
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Parent = RecipeList

	local listPadding = Instance.new("UIPadding")
	listPadding.PaddingTop = UDim.new(0, 8)
	listPadding.PaddingLeft = UDim.new(0, 4)
	listPadding.PaddingRight = UDim.new(0, 4)
	listPadding.PaddingBottom = UDim.new(0, 8)
	listPadding.Parent = RecipeList

	RecipeDetail = Instance.new("Frame")
	RecipeDetail.Name = "Detail"
	RecipeDetail.Position = UDim2.fromOffset(370, 56)
	RecipeDetail.Size = UDim2.new(1, -386, 1, -118)
	RecipeDetail.BackgroundColor3 = Color3.fromRGB(30, 34, 45)
	RecipeDetail.BorderSizePixel = 0
	RecipeDetail.Parent = Panel

	local detailCorner = Instance.new("UICorner")
	detailCorner.CornerRadius = UDim.new(0, 8)
	detailCorner.Parent = RecipeDetail

	RecipeTitle = Instance.new("TextLabel")
	RecipeTitle.BackgroundTransparency = 1
	RecipeTitle.Position = UDim2.fromOffset(16, 14)
	RecipeTitle.Size = UDim2.new(1, -24, 0, 34)
	RecipeTitle.Font = Enum.Font.GothamBold
	RecipeTitle.Text = "Select a recipe"
	RecipeTitle.TextSize = 20
	RecipeTitle.TextXAlignment = Enum.TextXAlignment.Left
	RecipeTitle.TextColor3 = Color3.fromRGB(244, 244, 244)
	RecipeTitle.Parent = RecipeDetail

	RecipeDescription = Instance.new("TextLabel")
	RecipeDescription.BackgroundTransparency = 1
	RecipeDescription.Position = UDim2.fromOffset(16, 50)
	RecipeDescription.Size = UDim2.new(1, -24, 0, 42)
	RecipeDescription.Font = Enum.Font.Gotham
	RecipeDescription.TextWrapped = true
	RecipeDescription.Text = ""
	RecipeDescription.TextSize = 14
	RecipeDescription.TextXAlignment = Enum.TextXAlignment.Left
	RecipeDescription.TextYAlignment = Enum.TextYAlignment.Top
	RecipeDescription.TextColor3 = Color3.fromRGB(198, 206, 220)
	RecipeDescription.Parent = RecipeDetail

	StationLabel = Instance.new("TextLabel")
	StationLabel.BackgroundTransparency = 1
	StationLabel.Position = UDim2.fromOffset(16, 96)
	StationLabel.Size = UDim2.new(1, -24, 0, 22)
	StationLabel.Font = Enum.Font.Gotham
	StationLabel.Text = "Station: -"
	StationLabel.TextSize = 14
	StationLabel.TextXAlignment = Enum.TextXAlignment.Left
	StationLabel.TextColor3 = Color3.fromRGB(220, 220, 220)
	StationLabel.Parent = RecipeDetail

	TimeLabel = Instance.new("TextLabel")
	TimeLabel.BackgroundTransparency = 1
	TimeLabel.Position = UDim2.fromOffset(16, 120)
	TimeLabel.Size = UDim2.new(1, -24, 0, 22)
	TimeLabel.Font = Enum.Font.Gotham
	TimeLabel.Text = "Time: -"
	TimeLabel.TextSize = 14
	TimeLabel.TextXAlignment = Enum.TextXAlignment.Left
	TimeLabel.TextColor3 = Color3.fromRGB(220, 220, 220)
	TimeLabel.Parent = RecipeDetail

	SkillLabel = Instance.new("TextLabel")
	SkillLabel.BackgroundTransparency = 1
	SkillLabel.Position = UDim2.fromOffset(16, 144)
	SkillLabel.Size = UDim2.new(1, -24, 0, 36)
	SkillLabel.Font = Enum.Font.Gotham
	SkillLabel.Text = "Skills: -"
	SkillLabel.TextWrapped = true
	SkillLabel.TextYAlignment = Enum.TextYAlignment.Top
	SkillLabel.TextSize = 13
	SkillLabel.TextXAlignment = Enum.TextXAlignment.Left
	SkillLabel.TextColor3 = Color3.fromRGB(220, 220, 220)
	SkillLabel.Parent = RecipeDetail

	local ingredientHeader = Instance.new("TextLabel")
	ingredientHeader.BackgroundTransparency = 1
	ingredientHeader.Position = UDim2.fromOffset(16, 186)
	ingredientHeader.Size = UDim2.new(1, -24, 0, 20)
	ingredientHeader.Font = Enum.Font.GothamBold
	ingredientHeader.Text = "Ingredients"
	ingredientHeader.TextSize = 14
	ingredientHeader.TextXAlignment = Enum.TextXAlignment.Left
	ingredientHeader.TextColor3 = Color3.fromRGB(240, 240, 240)
	ingredientHeader.Parent = RecipeDetail

	IngredientsList = Instance.new("ScrollingFrame")
	IngredientsList.Name = "Ingredients"
	IngredientsList.Position = UDim2.fromOffset(16, 210)
	IngredientsList.Size = UDim2.new(1, -32, 1, -278)
	IngredientsList.BackgroundColor3 = Color3.fromRGB(24, 26, 35)
	IngredientsList.BorderSizePixel = 0
	IngredientsList.AutomaticCanvasSize = Enum.AutomaticSize.Y
	IngredientsList.ScrollBarThickness = 6
	IngredientsList.CanvasSize = UDim2.fromOffset(0, 0)
	IngredientsList.Parent = RecipeDetail

	local ingredientCorner = Instance.new("UICorner")
	ingredientCorner.CornerRadius = UDim.new(0, 8)
	ingredientCorner.Parent = IngredientsList

	local ingredientLayout = Instance.new("UIListLayout")
	ingredientLayout.Padding = UDim.new(0, 4)
	ingredientLayout.SortOrder = Enum.SortOrder.LayoutOrder
	ingredientLayout.Parent = IngredientsList

	local ingredientPadding = Instance.new("UIPadding")
	ingredientPadding.PaddingTop = UDim.new(0, 6)
	ingredientPadding.PaddingBottom = UDim.new(0, 6)
	ingredientPadding.PaddingLeft = UDim.new(0, 4)
	ingredientPadding.PaddingRight = UDim.new(0, 4)
	ingredientPadding.Parent = IngredientsList

	CraftButton = Instance.new("TextButton")
	CraftButton.Name = "CraftButton"
	CraftButton.AnchorPoint = Vector2.new(0, 1)
	CraftButton.Position = UDim2.new(0, 16, 1, -16)
	CraftButton.Size = UDim2.fromOffset(170, 42)
	CraftButton.BackgroundColor3 = Color3.fromRGB(66, 132, 94)
	CraftButton.BorderSizePixel = 0
	CraftButton.Font = Enum.Font.GothamBold
	CraftButton.Text = "Craft"
	CraftButton.TextSize = 16
	CraftButton.TextColor3 = Color3.fromRGB(250, 250, 250)
	CraftButton.Parent = RecipeDetail

	local craftCorner = Instance.new("UICorner")
	craftCorner.CornerRadius = UDim.new(0, 8)
	craftCorner.Parent = CraftButton

	StatusLabel = Instance.new("TextLabel")
	StatusLabel.Name = "StatusLabel"
	StatusLabel.BackgroundTransparency = 1
	StatusLabel.AnchorPoint = Vector2.new(1, 1)
	StatusLabel.Position = UDim2.new(1, -16, 1, -16)
	StatusLabel.Size = UDim2.new(1, -208, 0, 40)
	StatusLabel.Font = Enum.Font.Gotham
	StatusLabel.Text = ""
	StatusLabel.TextSize = 14
	StatusLabel.TextXAlignment = Enum.TextXAlignment.Right
	StatusLabel.TextYAlignment = Enum.TextYAlignment.Center
	StatusLabel.TextColor3 = Color3.fromRGB(230, 230, 230)
	StatusLabel.Parent = RecipeDetail

	CraftButton.Activated:Connect(onCraftPressed)
end

local function setVisible(visible: boolean)
	RootGui.Enabled = visible
	if visible then
		requestData()
		refreshCountdown()
	else
		setStatus("")
	end
	renderDetails()
end

function CraftingUI.Init()
	buildUi()
	updateCountdownConnection()

	UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		if gameProcessed or UserInputService:GetFocusedTextBox() ~= nil then
			return
		end
		if input.KeyCode == Enum.KeyCode.C then
			setVisible(not RootGui.Enabled)
		elseif input.KeyCode == Enum.KeyCode.Escape and RootGui.Enabled then
			setVisible(false)
		end
	end)

	CraftingPackets.CraftStarted.OnClientEvent:Connect(function(payload: any)
		if typeof(payload) ~= "table" then
			return
		end
		ActiveCraftEndsAt = payload.EndsAt
		setStatus("Crafting started.", Color3.fromRGB(177, 240, 184))
		renderDetails()
		refreshCountdown()
	end)

	CraftingPackets.CraftCompleted.OnClientEvent:Connect(function(payload: any)
		if typeof(payload) ~= "table" then
			return
		end
		ActiveCraftEndsAt = nil
		setStatus(
			string.format("Craft complete: %dx %s", payload.OutputQuantity or 0, payload.OutputItemId or "Item"),
			Color3.fromRGB(177, 240, 184)
		)
		requestData()
	end)

	CraftingPackets.CraftFailed.OnClientEvent:Connect(function(payload: any)
		if typeof(payload) ~= "table" then
			return
		end
		ActiveCraftEndsAt = nil
		setStatus(payload.Reason or "Crafting failed.", Color3.fromRGB(255, 145, 145))
		requestData()
	end)
end

return CraftingUI
