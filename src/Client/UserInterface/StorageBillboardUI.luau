--!strict
-- StarterPlayerScripts/Client/UserInterface/StorageBillboardUI.luau
-- Shows container inventory and pantry items when the player approaches storage stations.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FoodPackets = require(ReplicatedStorage.Network.FoodPackets)
local IngredientsCatalog = require(ReplicatedStorage.Shared.Definitions.Ingredients)
local KitchenStateStore = require(script.Parent.Parent.ClientStores.KitchenStateStore)
local GoodSignal = require(ReplicatedStorage.Packages.GoodSignal)

local LocalPlayer = Players.LocalPlayer

local AssetsFolder = ReplicatedStorage.Assets
local FoodFrameTemplate = AssetsFolder.InterfacesTemplates.FoodFrameTemplate
--[[
the template has these following children so when cloned we edit this:
local TextButton = FoodFrameTemplate.TextButton -- the button for interacting with the food item and also edit the text to show name
local ImageLabel = FoodFrameTemplate.ImageLabel -- the image showing the food item
local TextLabel = FoodFrameTemplate.TextLabel -- The label to show quantity
]]

local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")
local StorageBillboard = PlayerGui:WaitForChild("StorageBillboard") :: BillboardGui
local RootFrame = StorageBillboard:WaitForChild("Root") :: Frame

local ControlsFrame = RootFrame:WaitForChild("Controls") :: Frame
local CloseButton = ControlsFrame:WaitForChild("Close") :: TextButton
local DepositButton = ControlsFrame:WaitForChild("Deposit") :: TextButton
local WithdrawButton = ControlsFrame:WaitForChild("Withdraw") :: TextButton
local QuantityBox = ControlsFrame:WaitForChild("Quantity") :: TextBox

local Header = RootFrame:WaitForChild("Header") :: Frame
local CapacityLabel = Header:WaitForChild("Capacity") :: TextLabel
local TitleLabel = Header:WaitForChild("Title") :: TextLabel

local ListsFrame = RootFrame:WaitForChild("Lists") :: Frame
local PantryColumn = ListsFrame:WaitForChild("PantryColumn") :: Frame
local PantryList = PantryColumn:WaitForChild("PantryList") :: ScrollingFrame
local ContainerColumn = ListsFrame:WaitForChild("ContainerColumn") :: Frame
local ContainerList = ContainerColumn:WaitForChild("ContainerList") :: ScrollingFrame

export type StorageMeta = {
	Name: string?,
	StationType: string,
	ItemId: string,
	Capacity: number,
}

local StorageBillboardUI = {}
StorageBillboardUI.VisibilityChanged = GoodSignal.new()

local billboard: BillboardGui = StorageBillboard
local titleLabel: TextLabel = TitleLabel
local capacityLabel: TextLabel = CapacityLabel
local pantryFrame: ScrollingFrame = PantryList
local containerFrame: ScrollingFrame = ContainerList
local quantityBox: TextBox = QuantityBox
local depositButton: TextButton = DepositButton
local withdrawButton: TextButton = WithdrawButton
local closeButton: TextButton = CloseButton

local storeConnection: RBXScriptConnection?
local currentContainerId: string? = nil
local currentStationType = "FoodStorage"
local currentMeta: StorageMeta? = nil
type Selection = { Source: "Pantry" | "Container", IngredientId: string }

local pendingSelection: Selection? = nil

local buttonRegistry: {
	Pantry: { [string]: TextButton },
	Container: { [string]: TextButton },
} = {
	Pantry = {},
	Container = {},
}

local mutedTextColor = Color3.fromRGB(166, 172, 191)
local listButtonSelectedColor = Color3.fromRGB(82, 118, 255)
local selectedTextColor = Color3.fromRGB(255, 255, 255)
local disabledActionColor = Color3.fromRGB(72, 78, 98)

type IngredientMap = KitchenStateStore.IngredientMap

local function getIngredientName(ingredientId: string): string
	local spec = IngredientsCatalog[ingredientId]
	if spec and typeof(spec.Name) == "string" then
		return spec.Name
	end
	return ingredientId
end

local function sanitizeQuantityInput(): number
	local box = quantityBox
	local rawText = box.Text
	local parsed = tonumber(rawText)
	local numeric: number
	if parsed == nil then
		numeric = 1
	else
		numeric = math.clamp(math.floor(parsed), 1, 255)
	end
	box.Text = tostring(numeric)
	return numeric
end

local function setButtonEnabled(button: TextButton?, enabled: boolean)
	if not button then
		return
	end
	button.AutoButtonColor = enabled
	button.Active = enabled
	button.Selectable = enabled
	button.TextTransparency = if enabled then 0 else 0.35

	local baseColorAttr = button:GetAttribute("BaseColor")
	local baseColor = if typeof(baseColorAttr) == "Color3" then baseColorAttr else button.BackgroundColor3
	local stroke = button:FindFirstChildWhichIsA("UIStroke")

	if enabled then
		button.BackgroundColor3 = baseColor
		if stroke then
			stroke.Transparency = 0.25
		end
	else
		button.BackgroundColor3 = disabledActionColor
		if stroke then
			stroke.Transparency = 0.55
		end
	end
end

local function refreshSelectionVisuals()
	local selection = pendingSelection
	for source, registry in pairs(buttonRegistry) do
		for ingredientId, button in pairs(registry) do
			local isSelected = selection ~= nil
				and selection.Source == source
				and selection.IngredientId == ingredientId
			local baseColorAttr = button:GetAttribute("BaseColor")
			local baseColor = if typeof(baseColorAttr) == "Color3" then baseColorAttr else button.BackgroundColor3
			button.BackgroundColor3 = if isSelected then listButtonSelectedColor else baseColor

			local baseTextAttr = button:GetAttribute("BaseTextColor")
			local baseTextColor = if typeof(baseTextAttr) == "Color3" then baseTextAttr else button.TextColor3
			button.TextColor3 = if isSelected then selectedTextColor else baseTextColor

			local parent = button.Parent
			if parent then
				local quantityLabel = parent:FindFirstChild("TextLabel")
				if quantityLabel and quantityLabel:IsA("TextLabel") then
					local qtyBaseAttr = quantityLabel:GetAttribute("BaseTextColor")
					local qtyBaseColor = if typeof(qtyBaseAttr) == "Color3"
						then qtyBaseAttr
						else quantityLabel.TextColor3
					quantityLabel.TextColor3 = if isSelected then selectedTextColor else qtyBaseColor
				end
			end
		end
	end

	local canDeposit = selection ~= nil and selection.Source == "Pantry"
	local canWithdraw = selection ~= nil and selection.Source == "Container"
	setButtonEnabled(depositButton, canDeposit)
	setButtonEnabled(withdrawButton, canWithdraw)
end

local function showEmptyState(frame: ScrollingFrame, text: string)
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, 0, 0, 22)
	label.Font = Enum.Font.Gotham
	label.TextSize = 14
	label.TextColor3 = mutedTextColor
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Text = text
	label:SetAttribute("StorageListEntry", true)
	label.Parent = frame
end

local function buildList(frame: ScrollingFrame, entries: IngredientMap, source: "Pantry" | "Container")
	local previousCanvas = frame.CanvasPosition
	for _, child in ipairs(frame:GetChildren()) do
		if child:GetAttribute("StorageListEntry") == true then
			child:Destroy()
		end
	end
	buttonRegistry[source] = {}

	local ordered: { { Id: string, Quantity: number } } = {}
	for ingredientId, quantity in pairs(entries) do
		if typeof(ingredientId) == "string" and typeof(quantity) == "number" then
			ordered[#ordered + 1] = {
				Id = ingredientId,
				Quantity = quantity,
			}
		end
	end
	table.sort(ordered, function(a, b)
		return a.Id < b.Id
	end)

	if #ordered == 0 then
		local emptyText = if source == "Pantry" then "No pantry items" else "Empty"
		frame.CanvasPosition = Vector2.new(0, 0)
		showEmptyState(frame, emptyText)
		return
	end

	for index, entry in ipairs(ordered) do
		local row = FoodFrameTemplate:Clone()
		row.Name = entry.Id
		row.LayoutOrder = index
		row:SetAttribute("StorageListEntry", true)
		row.Parent = frame

		local button = row:FindFirstChild("TextButton")
		if button and button:IsA("TextButton") then
			button.AutoButtonColor = false
			if button:GetAttribute("BaseColor") == nil then
				button:SetAttribute("BaseColor", button.BackgroundColor3)
			end
			if button:GetAttribute("BaseTextColor") == nil then
				button:SetAttribute("BaseTextColor", button.TextColor3)
			end
			button.Text = getIngredientName(entry.Id)
			button.MouseButton1Click:Connect(function()
				pendingSelection = {
					Source = source,
					IngredientId = entry.Id,
				}
				refreshSelectionVisuals()
			end)
			buttonRegistry[source][entry.Id] = button
		end

		local imageLabel = row:FindFirstChild("ImageLabel")
		if imageLabel and imageLabel:IsA("ImageLabel") then
			local ingredientSpec = IngredientsCatalog[entry.Id]
			local assetId = ingredientSpec and ingredientSpec.ImageAssetId
			if typeof(assetId) == "string" and assetId ~= "" then
				imageLabel.Image = assetId
			else
				imageLabel.Image = ""
			end
		end

		local quantityLabel = row:FindFirstChild("TextLabel")
		if quantityLabel and quantityLabel:IsA("TextLabel") then
			quantityLabel.Text = string.format("x%d", entry.Quantity)
			if quantityLabel:GetAttribute("BaseTextColor") == nil then
				quantityLabel:SetAttribute("BaseTextColor", quantityLabel.TextColor3)
			end
		end
	end

	-- Ensure scroll position survives list refresh in case the list updates while scrolled.
	task.defer(function()
		local maxY = math.max(0, frame.AbsoluteCanvasSize.Y - frame.AbsoluteSize.Y)
		frame.CanvasPosition = Vector2.new(0, math.clamp(previousCanvas.Y, 0, maxY))
	end)
end

local function updatePanel()
	if not currentContainerId then
		return
	end

	local title = titleLabel
	local capacityText = capacityLabel
	local containerColumn = containerFrame
	local pantryColumn = pantryFrame

	local fallback = currentMeta
	local container = KitchenStateStore.ResolveContainer(currentContainerId, fallback)
	local pantry = KitchenStateStore.GetPantry()

	local capacity = 0
	local used = 0
	if container then
		capacity = container.Capacity
		for _, quantity in pairs(container.Ingredients) do
			if typeof(quantity) == "number" then
				used += quantity
			end
		end
	end

	local displayName = fallback and fallback.Name or "Storage"
	title.Text = displayName or "Storage"
	if capacity > 0 then
		capacityText.Text = string.format("%d / %d stored", used, capacity)
	else
		capacityText.Text = string.format("%d stored", used)
	end

	local containerIngredients = if container then container.Ingredients else {}
	buildList(containerColumn, containerIngredients, "Container")
	buildList(pantryColumn, pantry, "Pantry")
	refreshSelectionVisuals()
end

local function hideBillboard()
	local previousContainerId = currentContainerId
	local gui = billboard
	if gui then
		gui.Enabled = false
		gui.Adornee = nil :: any
		gui.StudsOffsetWorldSpace = Vector3.zero
	end
	if storeConnection then
		storeConnection:Disconnect()
		storeConnection = nil
	end
	currentContainerId = nil
	currentMeta = nil
	currentStationType = "FoodStorage"
	pendingSelection = nil
	refreshSelectionVisuals()

	if previousContainerId and StorageBillboardUI.VisibilityChanged then
		StorageBillboardUI.VisibilityChanged:Fire(previousContainerId, false)
	end
end

local function onDeposit()
	if not currentContainerId or not pendingSelection or pendingSelection.Source ~= "Pantry" then
		return
	end

	local quantity = sanitizeQuantityInput()
	local ingredientId = pendingSelection.IngredientId
	local stationType = currentStationType

	local success, message =
		FoodPackets.ContainerTransferRequest:Fire(stationType, currentContainerId, ingredientId, quantity, "Deposit")
	if not success and message then
		warn("Storage deposit failed:", message)
	end
end

local function onWithdraw()
	if not currentContainerId or not pendingSelection or pendingSelection.Source ~= "Container" then
		return
	end

	local quantity = sanitizeQuantityInput()
	local ingredientId = pendingSelection.IngredientId
	local stationType = currentStationType

	local success, message =
		FoodPackets.ContainerTransferRequest:Fire(stationType, currentContainerId, ingredientId, quantity, "Withdraw")
	if not success and message then
		warn("Storage withdrawal failed:", message)
	end
end

local initialized = false

function StorageBillboardUI.Init()
	if initialized then
		return
	end
	initialized = true

	billboard.Enabled = false
	billboard.Adornee = nil :: any

	if depositButton:GetAttribute("BaseColor") == nil then
		depositButton:SetAttribute("BaseColor", depositButton.BackgroundColor3)
	end
	if withdrawButton:GetAttribute("BaseColor") == nil then
		withdrawButton:SetAttribute("BaseColor", withdrawButton.BackgroundColor3)
	end

	quantityBox.FocusLost:Connect(function()
		sanitizeQuantityInput()
	end)
	depositButton.MouseButton1Click:Connect(onDeposit)
	withdrawButton.MouseButton1Click:Connect(onWithdraw)
	closeButton.MouseButton1Click:Connect(function()
		StorageBillboardUI.Hide()
	end)

	sanitizeQuantityInput()
	setButtonEnabled(depositButton, false)
	setButtonEnabled(withdrawButton, false)
end

local function resolveAdornee(model: Model): BasePart?
	if model.PrimaryPart and model.PrimaryPart:IsA("BasePart") then
		return model.PrimaryPart
	end
	local part = model:FindFirstChildWhichIsA("BasePart", true)
	if part then
		return part
	end
	return nil
end

local function setBillboardPlacement(model: Model, adornee: BasePart)
	local gui = billboard
	if not gui then
		return
	end

	local offset: Vector3
	local success, boundingCFrame, boundingSize = pcall(function()
		return model:GetBoundingBox()
	end)
	local camera = workspace.CurrentCamera
	local cameraPosition = camera and camera.CFrame.Position or nil

	if success and boundingCFrame and boundingSize then
		local upVector = boundingCFrame.UpVector
		local rightVector = boundingCFrame.RightVector
		local lookVector = boundingCFrame.LookVector
		local topMargin = 0.45
		local leftMargin = 0.45
		local frontMargin = 0.15
		local frontDirection = lookVector
		if cameraPosition then
			local directionToCamera = cameraPosition - boundingCFrame.Position
			if directionToCamera.Magnitude > 0 then
				local sign = if directionToCamera.Unit:Dot(lookVector) >= 0 then 1 else -1
				frontDirection = lookVector * sign
			end
		end
		local offsetFromBounds = (-rightVector * (boundingSize.X / 2 + leftMargin))
			+ (upVector * (boundingSize.Y / 2 + topMargin))
			+ (frontDirection * (boundingSize.Z / 2 + frontMargin))
		offset = (boundingCFrame.Position + offsetFromBounds) - adornee.Position
	else
		local adorneeSize = adornee.Size
		local upVector = adornee.CFrame.UpVector
		local rightVector = adornee.CFrame.RightVector
		local lookVector = adornee.CFrame.LookVector
		local topMargin = math.max(adorneeSize.Y * 0.25, 0.45)
		local leftMargin = math.max(adorneeSize.X * 0.25, 0.4)
		local frontMargin = math.max(adorneeSize.Z * 0.25, 0.12)
		local frontDirection = lookVector
		if cameraPosition then
			local directionToCamera = cameraPosition - adornee.Position
			if directionToCamera.Magnitude > 0 then
				local sign = if directionToCamera.Unit:Dot(lookVector) >= 0 then 1 else -1
				frontDirection = lookVector * sign
			end
		end
		offset = (-rightVector * (adorneeSize.X / 2 + leftMargin))
			+ (upVector * (adorneeSize.Y / 2 + topMargin))
			+ (frontDirection * (adorneeSize.Z / 2 + frontMargin))
	end

	gui.StudsOffsetWorldSpace = offset
	gui.ExtentsOffsetWorldSpace = Vector3.zero
end

function StorageBillboardUI.Show(model: Model, containerId: string, meta: StorageMeta)
	StorageBillboardUI.Init()
	local adornee = resolveAdornee(model)
	if not adornee then
		return
	end

	currentContainerId = containerId
	currentStationType = meta.StationType
	currentMeta = meta
	pendingSelection = nil

	local gui = billboard :: BillboardGui
	gui.Adornee = adornee
	setBillboardPlacement(model, adornee)
	gui.Enabled = true

	if storeConnection then
		storeConnection:Disconnect()
	end
	storeConnection = KitchenStateStore.Changed:Connect(function()
		updatePanel()
	end)

	KitchenStateStore.RequestRefresh()
	updatePanel()

	if StorageBillboardUI.VisibilityChanged then
		StorageBillboardUI.VisibilityChanged:Fire(containerId, true)
	end
end

function StorageBillboardUI.Hide()
	hideBillboard()
end

function StorageBillboardUI.HideIfTarget(containerId: string)
	if currentContainerId == containerId then
		hideBillboard()
	end
end

function StorageBillboardUI.HandlePromptHidden(containerId: string): boolean
	if currentContainerId ~= containerId then
		return false
	end

	hideBillboard()
	return true
end

function StorageBillboardUI.IsVisible(): boolean
	return billboard.Enabled
end

function StorageBillboardUI.GetCurrentContainerId(): string?
	return currentContainerId
end

return StorageBillboardUI
