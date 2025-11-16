local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")

local BuildPaletteGui = PlayerGui:WaitForChild("BuildPaletteGui")
local MainFrame = BuildPaletteGui:WaitForChild("Main") :: Frame

local LeftFrame = MainFrame:WaitForChild("Left") :: Frame
local RightFrame = MainFrame:WaitForChild("Right") :: Frame
local BottomFrame = LeftFrame:WaitForChild("BottomFrame") :: Frame
local exitButton = BottomFrame:WaitForChild("CancelButton") :: GuiButton
local selectButton = BottomFrame:WaitForChild("SelectButton") :: GuiButton
local ColorPickerButton = MainFrame:WaitForChild("ColorPickerButton") :: GuiButton

local ColorsFrame = RightFrame:WaitForChild("ColorsFrame") :: Frame
local MaterialsFrame = RightFrame:WaitForChild("MaterialsFrame") :: Frame

local ColorsScrollingFrame = ColorsFrame:WaitForChild("ScrollingFrame") :: ScrollingFrame
local MaterialsScrollingFrame = MaterialsFrame:WaitForChild("ScrollingFrame") :: ScrollingFrame

local GoodSignal = require(ReplicatedStorage.Packages.GoodSignal)
local SurfacePalette = require(ReplicatedStorage.Shared.Configurations.Build.SurfacePalette)
local AssetsFolder = ReplicatedStorage:WaitForChild("Assets")
local InterfacesTemplatesFolder = AssetsFolder:WaitForChild("InterfacesTemplates")
local CancelPreviewButtonTemplate = InterfacesTemplatesFolder:WaitForChild("CancelPreviewButton") :: TextButton

local sliderWidthPixels = 20
local sliderHeightPixels = 120
local previewSizePixels = 64

local presetColorDefinitions: { Color3 } = {
	Color3.fromRGB(255, 255, 255),
	Color3.fromRGB(200, 200, 200),
	Color3.fromRGB(120, 120, 120),
	Color3.fromRGB(0, 0, 0),
	Color3.fromRGB(255, 0, 0),
	Color3.fromRGB(255, 128, 0),
	Color3.fromRGB(255, 255, 0),
	Color3.fromRGB(0, 255, 0),
	Color3.fromRGB(0, 255, 255),
	Color3.fromRGB(0, 128, 255),
	Color3.fromRGB(128, 0, 255),
	Color3.fromRGB(255, 0, 255),
}

local PRESET_ATTRIBUTE = "AutoColorPreset"

local BuildPaletteUI = {}
local colorChangedSignal = GoodSignal.new()
local materialChangedSignal = GoodSignal.new()
local selectActivatedSignal = GoodSignal.new()
BuildPaletteUI.ColorChanged = colorChangedSignal
BuildPaletteUI.MaterialChanged = materialChangedSignal
local suggestionSelectedSignal = GoodSignal.new()
BuildPaletteUI.SuggestionSelected = suggestionSelectedSignal

local isInitialized = false
local sliderConnections: { RBXScriptConnection } = {}

type SliderReferences = {
	hueSliderFrame: Frame,
	saturationSliderFrame: Frame,
	valueSliderFrame: Frame,
	saturationGradient: UIGradient,
	valueGradient: UIGradient,
	slidersContainer: Frame,
	sliderElements: { GuiObject },
	selectedColorPreviewImage: ImageLabel,
	selectedColorLabel: TextLabel,
	materialNameLabel: TextLabel,
}

export type PaintSuggestion = {
	Id: string?,
	Label: string?,
	SurfaceId: string?,
	PaintColor: Color3?,
	Source: string?,
}

local sliderRefs: SliderReferences? = nil
local currentHue = 0.0
local currentSaturation = 1.0
local currentValue = 1.0
local selectedPresetButton: TextButton? = nil
local selectedMaterialButton: GuiButton? = nil
local slidersVisible = false
local currentMaterialImage: string? = nil
local currentMaterialRectOffset: Vector2? = nil
local currentMaterialRectSize: Vector2? = nil
local currentMaterialName = "Material"
local currentSurfaceId: string? = nil
local currentMaterialId: string? = nil
local hasCustomColor = false
local paletteCancelButton: TextButton? = nil
local paletteCancelSource: string? = nil
local paletteCancelHandler: (() -> ())? = nil
local currentSuggestions: { PaintSuggestion } = {}
local suggestionButtonConnections: { RBXScriptConnection } = {}

local function clearSliderConnections()
	for _, connection in ipairs(sliderConnections) do
		connection:Disconnect()
	end
	table.clear(sliderConnections)
end

local function createRoundCorner(parent: Instance, cornerRadiusScale: number)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(cornerRadiusScale, 0)
	corner.Parent = parent
	return corner
end

local function createVerticalSlider(parent: Instance, name: string, backgroundColor: Color3): Frame
	local sliderFrame = Instance.new("Frame")
	sliderFrame.Name = name
	sliderFrame.BackgroundColor3 = backgroundColor
	sliderFrame.BorderSizePixel = 0
	sliderFrame.Size = UDim2.fromOffset(sliderWidthPixels, sliderHeightPixels)
	sliderFrame.Parent = parent
	createRoundCorner(sliderFrame, 0.25)

	local trackPadding = Instance.new("UIPadding")
	trackPadding.PaddingTop = UDim.new(0, 4)
	trackPadding.PaddingBottom = UDim.new(0, 4)
	trackPadding.Parent = sliderFrame

	local handle = Instance.new("Frame")
	handle.Name = "Handle"
	handle.Size = UDim2.new(1, 0, 0, 4)
	handle.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	handle.BorderSizePixel = 0
	handle.Parent = sliderFrame
	createRoundCorner(handle, 1)

	return sliderFrame
end

local function updateSliderHandlePosition(sliderFrame: Frame, value: number)
	local handle = sliderFrame:FindFirstChild("Handle")
	if handle and handle:IsA("Frame") then
		handle.AnchorPoint = Vector2.new(0, 0.5)
		handle.Position = UDim2.fromScale(0, 1 - value)
	end
end

local function getCurrentColor(): Color3
	return Color3.fromHSV(currentHue, currentSaturation, currentValue)
end

local function refreshSliderVisibility()
	if not sliderRefs then
		return
	end
	for _, slider in ipairs(sliderRefs.sliderElements) do
		slider.Visible = slidersVisible
		slider.Active = slidersVisible
	end
end

local function clearPresetSelection()
	if not selectedPresetButton then
		return
	end
	local stroke = selectedPresetButton:FindFirstChild("SelectionStroke")
	if stroke and stroke:IsA("UIStroke") then
		stroke.Thickness = 0
	end
	selectedPresetButton = nil
end

local function selectPreset(button: TextButton)
	if selectedPresetButton == button then
		return
	end
	clearPresetSelection()
	local stroke = button:FindFirstChild("SelectionStroke")
	if stroke and stroke:IsA("UIStroke") then
		stroke.Thickness = 2
	end
	selectedPresetButton = button
end

local MATERIAL_STROKE_NAME = "MaterialSelectionStroke"
local SUGGESTION_ATTRIBUTE = "PaintSuggestionButton"

local function getOrCreateMaterialStroke(button: GuiButton): UIStroke
	local stroke = button:FindFirstChild(MATERIAL_STROKE_NAME)
	if stroke and stroke:IsA("UIStroke") then
		return stroke
	end
	local newStroke = Instance.new("UIStroke")
	newStroke.Name = MATERIAL_STROKE_NAME
	newStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	newStroke.Thickness = 0
	newStroke.Color = Color3.fromRGB(255, 255, 255)
	newStroke.Parent = button
	return newStroke
end

local function clearMaterialSelection()
	if not selectedMaterialButton then
		return
	end
	local stroke = selectedMaterialButton:FindFirstChild(MATERIAL_STROKE_NAME)
	if stroke and stroke:IsA("UIStroke") then
		stroke.Thickness = 0
	end
	selectedMaterialButton = nil
end

local function selectMaterialButton(button: GuiButton)
	if selectedMaterialButton == button then
		return
	end
	clearMaterialSelection()
	local stroke = getOrCreateMaterialStroke(button)
	stroke.Thickness = 2
	selectedMaterialButton = button
end

local function refreshColorPreview(suppressSignal: boolean?)
	if not sliderRefs then
		return
	end

	local refs = sliderRefs
	local selectedColor = getCurrentColor()
	refs.selectedColorPreviewImage.BackgroundColor3 = selectedColor
	refs.selectedColorPreviewImage.ImageColor3 = selectedColor
	if currentMaterialImage and currentMaterialImage ~= "" then
		refs.selectedColorPreviewImage.ImageTransparency = 0
		refs.selectedColorPreviewImage.Image = currentMaterialImage
		refs.selectedColorPreviewImage.ImageRectOffset = currentMaterialRectOffset or Vector2.new(0, 0)
		refs.selectedColorPreviewImage.ImageRectSize = currentMaterialRectSize or Vector2.new(0, 0)
	else
		refs.selectedColorPreviewImage.Image = ""
		refs.selectedColorPreviewImage.ImageTransparency = 1
	end
	refs.selectedColorLabel.Text = string.format(
		"%d, %d, %d",
		math.floor(selectedColor.R * 255 + 0.5),
		math.floor(selectedColor.G * 255 + 0.5),
		math.floor(selectedColor.B * 255 + 0.5)
	)

	local pureHueColor = Color3.fromHSV(currentHue, 1, 1)
	refs.saturationGradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
		ColorSequenceKeypoint.new(1, pureHueColor),
	})

	local saturatedColor = Color3.fromHSV(currentHue, currentSaturation, 1)
	refs.valueGradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.new(0, 0, 0)),
		ColorSequenceKeypoint.new(1, saturatedColor),
	})

	updateSliderHandlePosition(refs.hueSliderFrame, currentHue)
	updateSliderHandlePosition(refs.saturationSliderFrame, currentSaturation)
	updateSliderHandlePosition(refs.valueSliderFrame, currentValue)
	if not suppressSignal then
		colorChangedSignal:Fire(selectedColor)
	end
end

local function resolveSurfaceId(attributeValue: any): string?
	if typeof(attributeValue) ~= "string" then
		return nil
	end
	if attributeValue == "" then
		return nil
	end
	return attributeValue
end

local function setPreviewMaterial(
	imageId: string?,
	rectOffset: Vector2?,
	rectSize: Vector2?,
	materialName: string?,
	surfaceId: string?,
	materialId: string?
)
	currentMaterialImage = imageId
	currentMaterialRectOffset = rectOffset
	currentMaterialRectSize = rectSize
	if materialName and materialName ~= "" then
		currentMaterialName = materialName
	elseif not currentMaterialName or currentMaterialName == "" then
		currentMaterialName = "Material"
	end
	if typeof(materialId) == "string" and materialId ~= "" then
		currentMaterialId = materialId
	end
	currentSurfaceId = resolveSurfaceId(surfaceId)
	if not currentSurfaceId and typeof(materialId) == "string" and materialId ~= "" then
		currentSurfaceId = materialId
	end
	if sliderRefs then
		local preview = sliderRefs.selectedColorPreviewImage
		if imageId and imageId ~= "" then
			preview.Image = imageId
			preview.ImageTransparency = 0
			preview.ImageRectOffset = rectOffset or Vector2.new(0, 0)
			preview.ImageRectSize = rectSize or Vector2.new(0, 0)
		else
			preview.Image = ""
			preview.ImageTransparency = 1
		end
		sliderRefs.materialNameLabel.Text = currentMaterialName or "Material"
	end
	refreshColorPreview(true)
	materialChangedSignal:Fire(currentSurfaceId, currentMaterialName, currentMaterialId)
end

local function connectVerticalSliderInput(sliderFrame: Frame, onValueChanged: (number) -> ())
	local isDragging = false

	local function updateFromInputPosition(inputPositionY: number)
		local top = sliderFrame.AbsolutePosition.Y
		local height = sliderFrame.AbsoluteSize.Y
		if height <= 0 then
			return
		end
		local relative = math.clamp((inputPositionY - top) / height, 0, 1)
		local value = 1 - relative
		onValueChanged(value)
	end

	table.insert(
		sliderConnections,
		sliderFrame.InputBegan:Connect(function(input: InputObject)
			if
				input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch
			then
				isDragging = true
				updateFromInputPosition(input.Position.Y)
			end
		end)
	)

	table.insert(
		sliderConnections,
		sliderFrame.InputEnded:Connect(function(input: InputObject)
			if
				input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch
			then
				isDragging = false
			end
		end)
	)

	table.insert(
		sliderConnections,
		UserInputService.InputEnded:Connect(function(input: InputObject)
			if
				input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch
			then
				isDragging = false
			end
		end)
	)

	table.insert(
		sliderConnections,
		UserInputService.InputChanged:Connect(function(input: InputObject)
			if not isDragging then
				return
			end
			if
				input.UserInputType == Enum.UserInputType.MouseMovement
				or input.UserInputType == Enum.UserInputType.Touch
			then
				updateFromInputPosition(input.Position.Y)
			end
		end)
	)
end

local function ensureSliderUi(): SliderReferences
	if sliderRefs then
		return sliderRefs
	end

	LeftFrame.Visible = true

	local container = LeftFrame:FindFirstChild("ColorPickerContainer")
	if not container or not container:IsA("Frame") then
		container = Instance.new("Frame")
		container.Name = "ColorPickerContainer"
		container.BackgroundTransparency = 1
		container.Size = UDim2.new(1, -12, 1, -12)
		container.Position = UDim2.fromOffset(6, 6)
		container.Parent = LeftFrame

		local padding = Instance.new("UIPadding")
		padding.PaddingTop = UDim.new(0, 6)
		padding.PaddingBottom = UDim.new(0, 6)
		padding.PaddingLeft = UDim.new(0, 6)
		padding.PaddingRight = UDim.new(0, 6)
		padding.Parent = container

		local layout = Instance.new("UIListLayout")
		layout.FillDirection = Enum.FillDirection.Vertical
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Padding = UDim.new(0, 8)
		layout.Parent = container
	end

	local headerLabel = container:FindFirstChild("ColorPickerLabel")
	if not headerLabel then
		headerLabel = Instance.new("TextLabel")
		headerLabel.Name = "ColorPickerLabel"
		headerLabel.BackgroundTransparency = 1
		headerLabel.Size = UDim2.new(1, 0, 0, 20)
		headerLabel.Font = Enum.Font.GothamBold
		headerLabel.Text = "Color Picker"
		headerLabel.TextSize = 16
		headerLabel.TextColor3 = Color3.fromRGB(240, 240, 240)
		headerLabel.TextXAlignment = Enum.TextXAlignment.Left
		headerLabel.Parent = container
	end

	local pickerRow = container:FindFirstChild("PickerRow")
	if not pickerRow then
		pickerRow = Instance.new("Frame")
		pickerRow.Name = "PickerRow"
		pickerRow.BackgroundTransparency = 1
		pickerRow.Size = UDim2.new(1, 0, 0, 150)
		pickerRow.Parent = container

		local rowLayout = Instance.new("UIListLayout")
		rowLayout.FillDirection = Enum.FillDirection.Horizontal
		rowLayout.SortOrder = Enum.SortOrder.LayoutOrder
		rowLayout.Padding = UDim.new(0, 10)
		rowLayout.Parent = pickerRow
	end

	local slidersContainer = pickerRow:FindFirstChild("SlidersContainer")
	if not slidersContainer then
		slidersContainer = Instance.new("Frame")
		slidersContainer.Name = "SlidersContainer"
		slidersContainer.BackgroundTransparency = 1
		slidersContainer.Size = UDim2.new(0, 140, 1, 0)
		slidersContainer.Parent = pickerRow

		local slidersLayout = Instance.new("UIListLayout")
		slidersLayout.FillDirection = Enum.FillDirection.Horizontal
		slidersLayout.SortOrder = Enum.SortOrder.LayoutOrder
		slidersLayout.Padding = UDim.new(0, 8)
		slidersLayout.Parent = slidersContainer
	end

	local previewFrame = pickerRow:FindFirstChild("SelectedColorPreview")
	if not previewFrame or not previewFrame:IsA("ImageLabel") then
		if previewFrame then
			previewFrame:Destroy()
		end
		local newPreview = Instance.new("ImageLabel")
		newPreview.Name = "SelectedColorPreview"
		newPreview.BackgroundColor3 = Color3.fromRGB(255, 0, 0)
		newPreview.BorderSizePixel = 0
		newPreview.Size = UDim2.fromOffset(previewSizePixels, previewSizePixels)
		newPreview.ScaleType = Enum.ScaleType.Stretch
		newPreview.Image = ""
		newPreview.ImageTransparency = 1
		newPreview.Parent = pickerRow
		createRoundCorner(newPreview, 0.35)
		previewFrame = newPreview
	else
		previewFrame = previewFrame :: ImageLabel
	end
	previewFrame.BackgroundTransparency = 0
	previewFrame.ClipsDescendants = false

	local previewLabel = previewFrame:FindFirstChild("SelectedColorLabel")
	if not previewLabel then
		previewLabel = Instance.new("TextLabel")
		previewLabel.Name = "SelectedColorLabel"
	else
		previewLabel = previewLabel :: TextLabel
	end

	previewLabel.AnchorPoint = Vector2.new(0.5, 0)
	previewLabel.Position = UDim2.new(0.5, 0, 1, 6)
	previewLabel.Size = UDim2.new(1, 16, 0, 26)
	previewLabel.BackgroundTransparency = 1
	previewLabel.Font = Enum.Font.GothamBold
	previewLabel.TextSize = 16
	previewLabel.TextColor3 = Color3.fromRGB(245, 245, 245)
	previewLabel.TextXAlignment = Enum.TextXAlignment.Center
	previewLabel.Text = "255, 0, 0"
	previewLabel.Parent = previewFrame
	previewLabel.ZIndex = 3

	local materialNameLabel = previewFrame:FindFirstChild("MaterialNameLabel")
	if not materialNameLabel then
		materialNameLabel = Instance.new("TextLabel")
		materialNameLabel.Name = "MaterialNameLabel"
	else
		materialNameLabel = materialNameLabel :: TextLabel
	end

	materialNameLabel.AnchorPoint = Vector2.new(0.5, 0)
	materialNameLabel.Position = UDim2.new(0.5, 0, 1, 32)
	materialNameLabel.Size = UDim2.new(1, 20, 0, 22)
	materialNameLabel.BackgroundTransparency = 1
	materialNameLabel.Font = Enum.Font.Gotham
	materialNameLabel.TextSize = 14
	materialNameLabel.TextColor3 = Color3.fromRGB(235, 235, 235)
	materialNameLabel.TextXAlignment = Enum.TextXAlignment.Center
	materialNameLabel.Text = currentMaterialName or "Material"
	materialNameLabel.Parent = previewFrame
	materialNameLabel.ZIndex = 3

	local hueSlider = slidersContainer:FindFirstChild("HueSlider")
	if not hueSlider then
		hueSlider = createVerticalSlider(slidersContainer, "HueSlider", Color3.fromRGB(128, 128, 128))
		local gradient = Instance.new("UIGradient")
		gradient.Rotation = 90
		gradient.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0.00, Color3.fromRGB(255, 0, 0)),
			ColorSequenceKeypoint.new(0.17, Color3.fromRGB(255, 255, 0)),
			ColorSequenceKeypoint.new(0.33, Color3.fromRGB(0, 255, 0)),
			ColorSequenceKeypoint.new(0.50, Color3.fromRGB(0, 255, 255)),
			ColorSequenceKeypoint.new(0.67, Color3.fromRGB(0, 0, 255)),
			ColorSequenceKeypoint.new(0.83, Color3.fromRGB(255, 0, 255)),
			ColorSequenceKeypoint.new(1.00, Color3.fromRGB(255, 0, 0)),
		})
		gradient.Parent = hueSlider
	end

	local saturationSlider = slidersContainer:FindFirstChild("SaturationSlider")
	local saturationGradient = saturationSlider and saturationSlider:FindFirstChildWhichIsA("UIGradient")
	if not saturationSlider then
		saturationSlider = createVerticalSlider(slidersContainer, "SaturationSlider", Color3.fromRGB(255, 255, 255))
		saturationGradient = Instance.new("UIGradient")
		saturationGradient.Rotation = 90
		saturationGradient.Parent = saturationSlider
	elseif not saturationGradient then
		saturationGradient = Instance.new("UIGradient")
		saturationGradient.Rotation = 90
		saturationGradient.Parent = saturationSlider
	end

	local valueSlider = slidersContainer:FindFirstChild("ValueSlider")
	local valueGradient = valueSlider and valueSlider:FindFirstChildWhichIsA("UIGradient")
	if not valueSlider then
		valueSlider = createVerticalSlider(slidersContainer, "ValueSlider", Color3.fromRGB(0, 0, 0))
		valueGradient = Instance.new("UIGradient")
		valueGradient.Rotation = 90
		valueGradient.Parent = valueSlider
	elseif not valueGradient then
		valueGradient = Instance.new("UIGradient")
		valueGradient.Rotation = 90
		valueGradient.Parent = valueSlider
	end

	sliderRefs = {
		hueSliderFrame = hueSlider,
		saturationSliderFrame = saturationSlider,
		valueSliderFrame = valueSlider,
		saturationGradient = saturationGradient :: UIGradient,
		valueGradient = valueGradient :: UIGradient,
		slidersContainer = slidersContainer,
		sliderElements = {
			headerLabel,
			hueSlider,
			saturationSlider,
			valueSlider,
		},
		selectedColorPreviewImage = previewFrame :: ImageLabel,
		selectedColorLabel = previewLabel :: TextLabel,
		materialNameLabel = materialNameLabel :: TextLabel,
	}
	local refs = sliderRefs
	if not refs then
		error("BuildPaletteUI: failed to capture slider references")
	end
	local typedRefs: SliderReferences = refs
	clearSliderConnections()
	connectVerticalSliderInput(typedRefs.hueSliderFrame, function(value)
		clearPresetSelection()
		currentHue = value
		hasCustomColor = true
		refreshColorPreview()
	end)
	connectVerticalSliderInput(typedRefs.saturationSliderFrame, function(value)
		clearPresetSelection()
		currentSaturation = value
		hasCustomColor = true
		refreshColorPreview()
	end)
	connectVerticalSliderInput(typedRefs.valueSliderFrame, function(value)
		clearPresetSelection()
		currentValue = value
		hasCustomColor = true
		refreshColorPreview()
	end)

	refreshColorPreview(true)
	refreshSliderVisibility()
	return typedRefs
end

local function createPresetButtons()
	local layout = ColorsScrollingFrame:FindFirstChildOfClass("UIListLayout")
	if not layout then
		layout = Instance.new("UIListLayout")
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Padding = UDim.new(0, 6)
		layout.Parent = ColorsScrollingFrame
	end
	for _, child in ipairs(ColorsScrollingFrame:GetChildren()) do
		if child:IsA("GuiObject") and child:GetAttribute(PRESET_ATTRIBUTE) == true then
			child:Destroy()
		end
	end

	for index, presetColor in ipairs(presetColorDefinitions) do
		local button = Instance.new("TextButton")
		button.Name = string.format("ColorPreset_%d", index)
		button.AutoButtonColor = true
		button.BackgroundColor3 = presetColor
		button.BorderSizePixel = 0
		button.Size = UDim2.new(1, -8, 0, 32)
		button.Text = ""
		button:SetAttribute(PRESET_ATTRIBUTE, true)
		button.LayoutOrder = 100 + index
		button.Parent = ColorsScrollingFrame
		createRoundCorner(button, 0.25)

		local stroke = Instance.new("UIStroke")
		stroke.Name = "SelectionStroke"
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Thickness = 0
		stroke.Color = Color3.fromRGB(255, 255, 255)
		stroke.Parent = button

		button.Activated:Connect(function()
			selectPreset(button)
			hasCustomColor = true
			local hue, saturation, value = presetColor:ToHSV()
			currentHue = hue
			currentSaturation = saturation
			currentValue = value
			refreshColorPreview()
		end)
	end
end

local function clearSuggestionButtons()
	for _, connection in ipairs(suggestionButtonConnections) do
		connection:Disconnect()
	end
	table.clear(suggestionButtonConnections)
	for _, child in ipairs(ColorsScrollingFrame:GetChildren()) do
		if child:IsA("GuiObject") and child:GetAttribute(SUGGESTION_ATTRIBUTE) == true then
			child:Destroy()
		end
	end
end

local function createSuggestionButton(index: number, suggestion: PaintSuggestion)
	local button = Instance.new("TextButton")
	button.Name = if suggestion.Id and suggestion.Id ~= ""
		then "Suggestion_" .. suggestion.Id
		else "Suggestion_" .. tostring(index)
	button.AutoButtonColor = true
	button.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
	button.BorderSizePixel = 0
	button.Size = UDim2.new(1, -8, 0, 36)
	button.Text = ""
	button.LayoutOrder = index
	button:SetAttribute(SUGGESTION_ATTRIBUTE, true)
	button.Parent = ColorsScrollingFrame
	createRoundCorner(button, 0.2)

	local swatch = Instance.new("Frame")
	swatch.Name = "Swatch"
	swatch.AnchorPoint = Vector2.new(0, 0.5)
	swatch.Position = UDim2.new(0, 8, 0.5, 0)
	swatch.Size = UDim2.fromOffset(24, 24)
	swatch.BackgroundColor3 = suggestion.PaintColor or Color3.fromRGB(200, 200, 200)
	swatch.BorderSizePixel = 0
	swatch.Parent = button
	createRoundCorner(swatch, 0.3)

	local swatchStroke = Instance.new("UIStroke")
	swatchStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	swatchStroke.Thickness = 1
	swatchStroke.Color = Color3.fromRGB(255, 255, 255)
	swatchStroke.Transparency = 0.5
	swatchStroke.Parent = swatch

	local label = Instance.new("TextLabel")
	label.Name = "SuggestionLabel"
	label.BackgroundTransparency = 1
	label.AnchorPoint = Vector2.new(0, 0)
	label.Position = UDim2.fromOffset(40, 0)
	label.Size = UDim2.new(1, -48, 1, 0)
	label.Font = Enum.Font.Gotham
	label.TextSize = 14
	label.TextColor3 = Color3.fromRGB(235, 235, 235)
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Text = suggestion.Label or "Suggested"
	label.Parent = button

	local connection = button.Activated:Connect(function()
		local record = currentSuggestions[index]
		if record then
			suggestionSelectedSignal:Fire(record)
		end
	end)
	table.insert(suggestionButtonConnections, connection)
end

local function extractMaterialImage(button: GuiButton): (string?, Vector2?, Vector2?)
	if button:IsA("ImageButton") then
		return button.Image, button.ImageRectOffset, button.ImageRectSize
	end
	local imageObject = button:FindFirstChildWhichIsA("ImageLabel", true)
	if not imageObject then
		imageObject = button:FindFirstChildWhichIsA("ImageButton", true)
	end
	if imageObject then
		return imageObject.Image, imageObject.ImageRectOffset, imageObject.ImageRectSize
	end
	return nil, nil, nil
end

local function applyMaterialSelectionFromButton(materialButton: GuiButton)
	local imageId, rectOffset, rectSize = extractMaterialImage(materialButton)
	local surfaceAttribute = materialButton:GetAttribute("SurfaceId")
	local resolvedSurfaceId = if typeof(surfaceAttribute) == "string" then surfaceAttribute else nil
	local displayNameValue = materialButton:GetAttribute("DisplayName")
	local displayName = if typeof(displayNameValue) == "string" and displayNameValue ~= ""
		then displayNameValue
		else materialButton.Name
	setPreviewMaterial(imageId, rectOffset, rectSize, displayName, resolvedSurfaceId, materialButton.Name)
	local paletteLookupId = resolvedSurfaceId or materialButton.Name
	local definition = SurfacePalette.GetSurface(paletteLookupId)
	if definition then
		BuildPaletteUI.SetSelectedColor(definition.Color, true, false)
	end
	selectMaterialButton(materialButton)
end

local function bindMaterialButton(materialButton: GuiButton)
	if materialButton:GetAttribute("MaterialButtonBound") then
		return
	end
	materialButton:SetAttribute("MaterialButtonBound", true)
	materialButton.Activated:Connect(function()
		applyMaterialSelectionFromButton(materialButton)
	end)
	materialButton.AncestryChanged:Connect(function(_, parent)
		if parent then
			return
		end
		if selectedMaterialButton == materialButton then
			selectedMaterialButton = nil
		end
	end)
	getOrCreateMaterialStroke(materialButton)
end

local function bindMaterialButtons()
	local initializedSelection = currentSurfaceId ~= nil
	for _, child in ipairs(MaterialsScrollingFrame:GetChildren()) do
		if child:IsA("GuiButton") then
			bindMaterialButton(child)
			if not initializedSelection then
				applyMaterialSelectionFromButton(child)
				initializedSelection = true
			end
		end
	end

	MaterialsScrollingFrame.ChildAdded:Connect(function(child)
		if child:IsA("GuiButton") then
			bindMaterialButton(child)
			if not currentSurfaceId then
				applyMaterialSelectionFromButton(child)
			end
		end
	end)
end

function BuildPaletteUI.SetSuggestions(suggestions: { PaintSuggestion }?)
	clearSuggestionButtons()
	currentSuggestions = suggestions or {}
	if not suggestions or #suggestions == 0 then
		return
	end
	for index, suggestion in ipairs(currentSuggestions) do
		createSuggestionButton(index, suggestion)
	end
end

function BuildPaletteUI.OnSuggestionSelected(handler: (PaintSuggestion) -> ())
	if typeof(handler) ~= "function" then
		error("BuildPaletteUI.OnSuggestionSelected requires a handler function")
	end
	return suggestionSelectedSignal:Connect(handler)
end

local function setSelectButtonActiveState(isActive: boolean)
	selectButton:SetAttribute("Active", isActive)
	selectButton:SetAttribute("SurfacePaintActive", isActive)
end

local function applySliderVisibility()
	refreshSliderVisibility()
	ColorPickerButton:SetAttribute("PaletteVisible", slidersVisible)
end

local function toggleSliderVisibility()
	slidersVisible = not slidersVisible
	applySliderVisibility()
end

local function ensureCancelButton(): TextButton
	if paletteCancelButton and paletteCancelButton.Parent then
		return paletteCancelButton
	end
	local button = CancelPreviewButtonTemplate:Clone()
	button.Name = "PaletteCancelButton"
	button.AnchorPoint = Vector2.new(1, 1)
	button.Size = UDim2.fromOffset(160, 48)
	button.Position = UDim2.new(1, -24, 1, -24)
	button.Visible = false
	button.Active = false
	button.AutoButtonColor = false
	button.Parent = BuildPaletteGui
	local keyHint = button:FindFirstChild("KeyHint")
	if keyHint and keyHint:IsA("TextLabel") then
		keyHint.Visible = false
	end
	button.Activated:Connect(function()
		if paletteCancelHandler then
			paletteCancelHandler()
		end
	end)
	paletteCancelButton = button
	return button
end

local function updateCancelButtonState()
	local button = ensureCancelButton()
	local isActive = paletteCancelHandler ~= nil
	button.Visible = isActive
	button.Active = isActive
	button.AutoButtonColor = isActive
end

local function clearCancelHandler()
	paletteCancelSource = nil
	paletteCancelHandler = nil
	updateCancelButtonState()
end

function BuildPaletteUI.Init()
	if isInitialized then
		return
	end
	ensureSliderUi()
	createPresetButtons()
	BuildPaletteUI.SetSuggestions({})
	bindMaterialButtons()
	applySliderVisibility()
	selectButton.Activated:Connect(function()
		selectActivatedSignal:Fire()
	end)
	exitButton.Activated:Connect(BuildPaletteUI.Hide)
	ColorPickerButton.Activated:Connect(toggleSliderVisibility)
	isInitialized = true
end

function BuildPaletteUI.Show()
	BuildPaletteGui.Enabled = true
	MainFrame.Visible = true
end

function BuildPaletteUI.Hide()
	MainFrame.Visible = false
end

function BuildPaletteUI.IsVisible(): boolean
	return BuildPaletteGui.Enabled
end

function BuildPaletteUI.GetSelectedColor(): Color3
	return getCurrentColor()
end

function BuildPaletteUI.GetSelectedColorOverride(): Color3?
	if hasCustomColor then
		return getCurrentColor()
	end
	return nil
end

function BuildPaletteUI.SetSelectedColor(color: Color3, suppressSignal: boolean?, markAsCustom: boolean?)
	currentHue, currentSaturation, currentValue = color:ToHSV()
	clearPresetSelection()
	if markAsCustom ~= nil then
		hasCustomColor = markAsCustom
	else
		hasCustomColor = true
	end
	if sliderRefs then
		refreshColorPreview(suppressSignal)
	else
		ensureSliderUi()
		refreshColorPreview(suppressSignal)
	end
end

function BuildPaletteUI.GetSelectedSurfaceId(): string?
	return currentSurfaceId
end

function BuildPaletteUI.GetSelectedMaterialName(): string
	return currentMaterialName
end

function BuildPaletteUI.OnSelectActivated(handler: () -> ())
	if typeof(handler) ~= "function" then
		error("BuildPaletteUI.OnSelectActivated requires a handler function")
	end
	return selectActivatedSignal:Connect(handler)
end

function BuildPaletteUI.SetSelectModeActive(isActive: boolean)
	setSelectButtonActiveState(isActive)
end

function BuildPaletteUI.AcquireCancelButton(sourceId: string, handler: (() -> ())?)
	if typeof(sourceId) ~= "string" or sourceId == "" then
		error("BuildPaletteUI.AcquireCancelButton requires a non-empty source identifier")
	end
	if handler ~= nil and typeof(handler) ~= "function" then
		error("BuildPaletteUI.AcquireCancelButton handler must be a function or nil")
	end
	ensureCancelButton()
	if paletteCancelSource and paletteCancelSource ~= sourceId then
		warn(
			string.format(
				"BuildPaletteUI cancel button already claimed by '%s'; overriding with '%s'",
				paletteCancelSource,
				sourceId
			)
		)
	end
	paletteCancelSource = sourceId
	paletteCancelHandler = handler
	updateCancelButtonState()
end

function BuildPaletteUI.ReleaseCancelButton(sourceId: string)
	if typeof(sourceId) ~= "string" or sourceId == "" then
		return
	end
	if paletteCancelSource ~= sourceId then
		return
	end
	clearCancelHandler()
end

return BuildPaletteUI
