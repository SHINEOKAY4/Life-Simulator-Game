--!strict
-- ServerScriptService/Client/UserInterface/StationRadialUI.lua

local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ResidentNeedsUI = require(script.Parent.ResidentNeedsUI)
local ResidentController = require(script.Parent.Parent.Modules.ResidentController)
local KitchenStateStore = require(script.Parent.Parent.ClientStores.KitchenStateStore)
local Debounce = require(ReplicatedStorage.Shared.Utilities.Debounce)
local IngredientsCatalog = require(ReplicatedStorage.Shared.Definitions.Ingredients)
local MealRecipesModule = require(ReplicatedStorage.Shared.Definitions.MealRecipes)
local FoodUtils = require(ReplicatedStorage.Shared.Utilities.FoodUtils)

local MealRecipes = MealRecipesModule.Recipes

type KitchenSnapshot = KitchenStateStore.KitchenSnapshot
type ContainerSnapshot = KitchenStateStore.ContainerSnapshot

local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")

local InputContextsFolder = PlayerGui:WaitForChild("InputContexts")
local StationSelectorContext = InputContextsFolder:WaitForChild("StationSelectorContext")

local _ActiveQueryFolder = PlayerGui:FindFirstChild("ActiveQuery")
local StationRadial = PlayerGui:WaitForChild("StationRadial") :: BillboardGui
local HubFrame = StationRadial:WaitForChild("Root"):FindFirstChild("Hub") :: Frame
local Root = StationRadial:FindFirstChild("Root") :: Frame
local AssignButton = Root:FindFirstChild("AssignButton") :: TextButton
local statusLabelCandidate = Root:FindFirstChild("StatusLabel")
local StatusLabel = if statusLabelCandidate and statusLabelCandidate:IsA("TextLabel") then statusLabelCandidate else nil

local AssignStroke = AssignButton:FindFirstChildWhichIsA("UIStroke")
local AssignBaseColor = AssignButton.BackgroundColor3
local AssignBaseTextColor = AssignButton.TextColor3
local AssignStrokeBaseTransparency = AssignStroke and AssignStroke.Transparency or 0

local StationRadialUI = {}
local OriginalButtonPositions: { [TextButton]: UDim2 } = {}
local CurrentSelectedStation: Model? = nil
local CurrentStationType: string? = nil
local CurrentContainerId: string? = nil

local INPUT_DEBOUNCE_SECONDS = 0.2
local DISABLED_BUTTON_COLOR = Color3.fromRGB(72, 78, 98)
local DISABLED_TEXT_TRANSPARENCY = 0.35
local KITCHEN_REFRESH_COOLDOWN = 2

local kitchenStoreConnected = false
local kitchenSnapshotReady = false
local lastKitchenRefresh = 0

local function trySetStatus(text: string?, visible: boolean?)
	if not StatusLabel then
		return
	end
	if text then
		StatusLabel.Text = text
	end
	if visible ~= nil then
		StatusLabel.Visible = visible
	end
end

local function setAssignButtonState(text: string, enabled: boolean, detail: string?)
	AssignButton.Text = text
	AssignButton.Active = enabled
	AssignButton.AutoButtonColor = enabled
	AssignButton.Selectable = enabled
	AssignButton.TextTransparency = if enabled then 0 else DISABLED_TEXT_TRANSPARENCY
	if enabled then
		AssignButton.BackgroundColor3 = AssignBaseColor
		AssignButton.TextColor3 = AssignBaseTextColor
		if AssignStroke then
			AssignStroke.Transparency = AssignStrokeBaseTransparency
		end
	else
		AssignButton.BackgroundColor3 = DISABLED_BUTTON_COLOR
		AssignButton.TextColor3 = AssignBaseTextColor
		if AssignStroke then
			AssignStroke.Transparency = 0.55
		end
	end
	if detail and detail ~= "" then
		trySetStatus(detail, true)
	else
		trySetStatus("", false)
	end
end

local function pluralSuffix(value: number): string
	return if value == 1 then "" else "s"
end

local function resolvePreparedMealLabel(snapshot: KitchenSnapshot): (string?, string?)
	local bestId: string? = nil
	local bestServings = 0
	local bestHunger = 0
	for mealId, portions in pairs(snapshot.Meals) do
		if typeof(portions) == "number" and portions > 0 then
			local recipe = MealRecipes[mealId]
			if recipe then
				local hunger = FoodUtils.ComputeHungerEffect(recipe.HungerRestore)
				if hunger > 0 then
					local servings = math.max(1, math.floor(portions + 0.5))
					if hunger > bestHunger or (hunger == bestHunger and servings > bestServings) then
						bestId = mealId
						bestHunger = hunger
						bestServings = servings
					end
				end
			end
		end
	end
	if not bestId then
		return nil, nil
	end
	local recipe = MealRecipes[bestId]
	local name = recipe and recipe.Name or bestId
	local servingsText = string.format("%d serving%s ready", bestServings, pluralSuffix(bestServings))
	local hungerText = string.format("+%d hunger each", bestHunger)
	return string.format("Serve %s", name), string.format("%s - %s", servingsText, hungerText)
end

local function resolveSnackLabel(container: ContainerSnapshot): (string?, string?)
	local bestName: string? = nil
	local bestDetail: string? = nil
	local bestScore = 0
	for ingredientId, quantity in pairs(container.Ingredients) do
		if typeof(ingredientId) == "string" and typeof(quantity) == "number" and quantity > 0 then
			local spec = IngredientsCatalog[ingredientId]
			local hunger = 0
			if spec and typeof(spec.RawHungerRestore) == "number" then
				hunger = FoodUtils.ComputeHungerEffect(spec.RawHungerRestore)
			end
			if hunger > 0 then
				local servings = math.max(1, math.floor(quantity + 0.5))
				if hunger > bestScore then
					bestScore = hunger
					local name = spec and spec.Name or ingredientId
					local servingsText = string.format("x%d available", servings)
					local hungerText = string.format("+%d hunger", hunger)
					bestName = string.format("Grab %s", name)
					bestDetail = string.format("%s - %s", servingsText, hungerText)
				end
			end
		end
	end
	return bestName, bestDetail
end

local function updateFoodStorageAssignButton(containerId: string?)
	if not containerId then
		setAssignButtonState("Grab Food", true, nil)
		return
	end
	if not kitchenSnapshotReady then
		setAssignButtonState("Grab Food", true, "Syncing kitchen data...")
		return
	end
	local snapshot = KitchenStateStore.GetSnapshot()
	local mealLabel, mealDetail = resolvePreparedMealLabel(snapshot)
	if mealLabel then
		setAssignButtonState(mealLabel, true, mealDetail)
		return
	end
	local container = snapshot.Containers[containerId]
	if not container then
		setAssignButtonState("Grab Food", true, "Storage syncing...")
		return
	end
	local snackLabel, snackDetail = resolveSnackLabel(container)
	if snackLabel and snackDetail then
		setAssignButtonState(snackLabel, true, snackDetail)
		return
	end
	setAssignButtonState("No Food Available", false, "Restock this storage or cook a meal first.")
end

local function ensureKitchenStoreConnection()
	if kitchenStoreConnected then
		return
	end
	kitchenStoreConnected = true
	KitchenStateStore.Init()
	KitchenStateStore.Changed:Connect(function()
		kitchenSnapshotReady = true
		if CurrentStationType == "FoodStorage" and CurrentContainerId then
			updateFoodStorageAssignButton(CurrentContainerId)
		end
	end)
end

local function refreshKitchenSnapshot()
	if not kitchenStoreConnected then
		return
	end
	local now = os.clock()
	if now - lastKitchenRefresh < KITCHEN_REFRESH_COOLDOWN then
		return
	end
	lastKitchenRefresh = now
	task.spawn(function()
		local success, _ = KitchenStateStore.RequestRefresh()
		if success then
			kitchenSnapshotReady = true
		end
	end)
end

local function runDebounced(actionName: string, callback: () -> ()): ()
	local key = string.format("StationRadialUI/%s", actionName)
	Debounce.RunIfAvailable(key, INPUT_DEBOUNCE_SECONDS, callback, Player.UserId)
end

local function textForStation(stationType: string): string
	if stationType == "CookStation" then
		return "Cook"
	elseif stationType == "FunStation" then
		return "Play"
	elseif stationType == "RestStation" then
		return "Rest"
	elseif stationType == "HygieneStation" then
		return "Clean Up"
	elseif stationType == "SocialStation" then
		return "Socialize"
	elseif stationType == "MealStation" then
		return "Eat Meal"
	elseif stationType == "FoodStorage" then
		return "Grab Food"
	end

	return "Unknown Station"
end

local function registerButton(button: TextButton)
	if OriginalButtonPositions[button] then
		return
	end

	OriginalButtonPositions[button] = button.Position
end

local function tryRegisterDescendant(descendant: Instance)
	if descendant:IsA("TextButton") then
		registerButton(descendant)
	end
end

for _, descendant in ipairs(StationRadial:GetDescendants()) do
	tryRegisterDescendant(descendant)
end

StationRadial.DescendantAdded:Connect(function(descendant)
	tryRegisterDescendant(descendant)
end)

local function animateButtonsOut()
	if not HubFrame then
		return
	end

	for _, descendant in ipairs(StationRadial:GetDescendants()) do
		if descendant:IsA("TextButton") then
			registerButton(descendant)
			descendant.Position = HubFrame.Position
			local originalPosition = OriginalButtonPositions[descendant]
			if originalPosition then
				local tweenInfo = TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
				local tween = TweenService:Create(descendant, tweenInfo, { Position = originalPosition })
				tween:Play()
			end
		end
	end
end

function StationRadialUI.Init()
	ensureKitchenStoreConnection()
	StationSelectorContext.CloseStation.Pressed:Connect(function()
		runDebounced("Close", function()
			StationRadialUI.Hide()
		end)
	end)

	StationSelectorContext.AssignResident.Pressed:Connect(function()
		runDebounced("Assign", function()
			if not AssignButton.Active then
				return
			end
			local currentStation = StationRadialUI.GetCurrentSelectedStation()
			local residentModel = ResidentNeedsUI.GetCurrentSelectedResident()
			local currentStationName = currentStation and currentStation.Name or "None"
			local residentName = residentModel and residentModel.Name or "None"

			if currentStation and residentModel then
				local success, message = ResidentController.RequestResidentToStation(residentName, currentStationName)
				if not success then
					warn(message or "Failed to assign resident to station")
				end
			end
			StationRadialUI.Hide()
		end)
	end)
end

function StationRadialUI.Show(adorneeModel: Model, stationType: string)
	if CurrentSelectedStation == adorneeModel then
		return
	end
	ensureKitchenStoreConnection()
	StationRadial.Enabled = true
	StationRadial.Adornee = adorneeModel
	CurrentSelectedStation = adorneeModel
	CurrentStationType = stationType
	CurrentContainerId = nil
	local defaultText = textForStation(stationType)
	if stationType == "FoodStorage" then
		CurrentContainerId = adorneeModel.Name
		setAssignButtonState(defaultText, true, nil)
		refreshKitchenSnapshot()
		updateFoodStorageAssignButton(CurrentContainerId)
	else
		setAssignButtonState(defaultText, true, nil)
	end
	animateButtonsOut()
end

function StationRadialUI.Hide()
	--StationRadial.Enabled = false -- Commented out because we want to keep it enabled for input to finish processing
	StationRadial.Adornee = nil :: any
	CurrentSelectedStation = nil
	CurrentStationType = nil
	CurrentContainerId = nil
	trySetStatus("", false)
end

function StationRadialUI.GetCurrentSelectedStation(): Model?
	return CurrentSelectedStation
end
return StationRadialUI
