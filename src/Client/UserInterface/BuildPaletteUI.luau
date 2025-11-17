local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")

local BuildPaletteGui = PlayerGui:WaitForChild("BuildPaletteGui")
local MainFrame = BuildPaletteGui:WaitForChild("Main") :: Frame

local LeftFrame = MainFrame:WaitForChild("Left") :: Frame
local RightFrame = MainFrame:WaitForChild("Right") :: Frame
local BottomFrame = LeftFrame:WaitForChild("BottomFrame") :: Frame
local exitButton = BottomFrame:WaitForChild("CancelButton") :: GuiButton
local selectButton = BottomFrame:WaitForChild("SelectButton") :: GuiButton

local ColorsFrame = RightFrame:WaitForChild("ColorsFrame") :: Frame
local MaterialsFrame = RightFrame:WaitForChild("MaterialsFrame") :: Frame

local ColorsScrollingFrame = ColorsFrame:WaitForChild("ScrollingFrame") :: ScrollingFrame
local MaterialsScrollingFrame = MaterialsFrame:WaitForChild("ScrollingFrame") :: ScrollingFrame

local GoodSignal = require(ReplicatedStorage.Packages.GoodSignal)
local SurfacePalette = require(ReplicatedStorage.Shared.Configurations.Build.SurfacePalette)
local AssetsFolder = ReplicatedStorage:WaitForChild("Assets")
local InterfacesTemplatesFolder = AssetsFolder:WaitForChild("InterfacesTemplates")
local CancelPreviewButtonTemplate = InterfacesTemplatesFolder:WaitForChild("CancelPreviewButton") :: TextButton

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
local selectModeChangedSignal = GoodSignal.new()
BuildPaletteUI.SelectModeChanged = selectModeChangedSignal

local CURSOR_ICON_ASSET_ID = "rbxassetid://79483268729599"
local POPUP_HIDDEN_SCALE = 0.9
local POPUP_SHOW_TWEEN = TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local POPUP_HIDE_TWEEN = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local POPUP_SCALE_NAME = "PalettePopScale"

local isInitialized = false
local sliderConnections: { RBXScriptConnection } = {}

type SliderReferences = {
	hueSliderFrame: Frame,
	saturationSliderFrame: Frame,
	valueSliderFrame: Frame,
	saturationGradient: UIGradient,
	valueGradient: UIGradient,
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
local boundMaterialButtons: { [GuiButton]: boolean } = {}
local isSelectModeActive = false
local isPaletteVisible = false
local paletteScale: UIScale? = nil
local paletteTween: Tween? = nil
local cursorGui: ScreenGui? = nil
local cursorImage: ImageLabel? = nil
local cursorConnection: RBXScriptConnection? = nil
local cursorActive = false

local CURSOR_IMAGE_SIZE = Vector2.new(48, 48)
local CURSOR_OFFSET = Vector2.new(-8, -8)

local function clearSliderConnections()
	for _, connection in ipairs(sliderConnections) do
		connection:Disconnect()
	end
	table.clear(sliderConnections)
end

local function ensurePaletteScale(): UIScale
	if paletteScale and paletteScale.Parent == MainFrame then
		return paletteScale
	end
	local existing = MainFrame:FindFirstChild(POPUP_SCALE_NAME)
	if existing and existing:IsA("UIScale") then
		paletteScale = existing
		return paletteScale
	end
	local scale = Instance.new("UIScale")
	scale.Name = POPUP_SCALE_NAME
	scale.Scale = 1
	scale.Parent = MainFrame
	paletteScale = scale
	return scale
end

local function tweenPaletteVisibility(shouldShow: boolean)
	local scale = ensurePaletteScale()
	if paletteTween then
		paletteTween:Cancel()
		paletteTween = nil
	end

	if shouldShow then
		BuildPaletteGui.Enabled = true
		MainFrame.Visible = true
		scale.Scale = POPUP_HIDDEN_SCALE
		local tween = TweenService:Create(scale, POPUP_SHOW_TWEEN, {
			Scale = 1,
		})
		paletteTween = tween
		tween.Completed:Connect(function()
			if paletteTween == tween then
				paletteTween = nil
			end
		end)
		tween:Play()
		return
	end

	if not MainFrame.Visible then
		scale.Scale = 1
		return
	end

	local tween = TweenService:Create(scale, POPUP_HIDE_TWEEN, {
		Scale = POPUP_HIDDEN_SCALE,
	})
	paletteTween = tween
	tween.Completed:Connect(function()
		if paletteTween ~= tween then
			return
		end
		paletteTween = nil
		if not isPaletteVisible then
			MainFrame.Visible = false
			scale.Scale = 1
		end
	end)
	tween:Play()
end

local function ensureCursorGui(): ImageLabel
	if cursorImage and cursorImage.Parent then
		return cursorImage
	end

	local gui = cursorGui
	if not gui or not gui.Parent then
		gui = Instance.new("ScreenGui")
		gui.Name = "BuildPaletteCursorGui"
		gui.ResetOnSpawn = false
		gui.IgnoreGuiInset = true
		gui.DisplayOrder = 1000
		gui.Parent = PlayerGui
		cursorGui = gui
	end

	local image = Instance.new("ImageLabel")
	image.Name = "CursorIcon"
	image.Image = CURSOR_ICON_ASSET_ID
	image.BackgroundTransparency = 1
	image.Size = UDim2.fromOffset(CURSOR_IMAGE_SIZE.X, CURSOR_IMAGE_SIZE.Y)
	image.AnchorPoint = Vector2.new(0, 0)
	image.Visible = false
	image.ZIndex = 10
	image.Parent = gui
	cursorImage = image
	return image
end

local function setCursorActive(isActive: boolean)
	if cursorActive == isActive then
		return
	end
	cursorActive = isActive

	if isActive then
		local image = ensureCursorGui()
		image.Visible = true
		UserInputService.MouseIconEnabled = false
		if cursorConnection then
			cursorConnection:Disconnect()
		end
		cursorConnection = RunService.RenderStepped:Connect(function()
			local mousePosition = UserInputService:GetMouseLocation()
			image.Position = UDim2.fromOffset(mousePosition.X + CURSOR_OFFSET.X, mousePosition.Y + CURSOR_OFFSET.Y)
		end)
		return
	end

	if cursorConnection then
		cursorConnection:Disconnect()
		cursorConnection = nil
	end
	UserInputService.MouseIconEnabled = true
	if cursorImage then
		cursorImage.Visible = false
	end
end

local function createRoundCorner(parent: Instance, cornerRadiusScale: number)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(cornerRadiusScale, 0)
	corner.Parent = parent
	return corner
end

local function updateSliderHandlePosition(sliderFrame: Frame, value: number)
	local handle = sliderFrame:FindFirstChild("Handle")
	if handle and handle:IsA("Frame") then
		handle.AnchorPoint = Vector2.new(0, 0.5)
		handle.Position = UDim2.fromScale(0, value)
	end
end

local function getCurrentColor(): Color3
	return Color3.fromHSV(currentHue, currentSaturation, currentValue)
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
		onValueChanged(relative)
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

	local colorPickerContainer = LeftFrame:WaitForChild("ColorPickerContainer") :: Frame
	local pickerRow = colorPickerContainer:WaitForChild("PickerRow") :: Frame
	local slidersContainer = pickerRow:WaitForChild("SlidersContainer") :: Frame

	local function expectSlider(name: string): Frame
		local slider = slidersContainer:FindFirstChild(name)
		if not slider or not slider:IsA("Frame") then
			error(string.format("BuildPaletteUI missing slider '%s' inside SlidersContainer", name))
		end
		return slider
	end

	local hueSlider = expectSlider("HueSlider")
	local saturationSlider = expectSlider("SaturationSlider")
	local valueSlider = expectSlider("ValueSlider")

	local hueGradient = hueSlider:FindFirstChildWhichIsA("UIGradient")
	if not hueGradient then
		hueGradient = Instance.new("UIGradient")
		hueGradient.Rotation = 90
		hueGradient.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0.00, Color3.fromRGB(255, 0, 0)),
			ColorSequenceKeypoint.new(0.17, Color3.fromRGB(255, 255, 0)),
			ColorSequenceKeypoint.new(0.33, Color3.fromRGB(0, 255, 0)),
			ColorSequenceKeypoint.new(0.50, Color3.fromRGB(0, 255, 255)),
			ColorSequenceKeypoint.new(0.67, Color3.fromRGB(0, 0, 255)),
			ColorSequenceKeypoint.new(0.83, Color3.fromRGB(255, 0, 255)),
			ColorSequenceKeypoint.new(1.00, Color3.fromRGB(255, 0, 0)),
		})
		hueGradient.Parent = hueSlider
	else
		hueGradient.Rotation = 90
	end

	local function ensureGradient(slider: Frame): UIGradient
		local gradient = slider:FindFirstChildWhichIsA("UIGradient")
		if gradient then
			gradient.Rotation = 90
			return gradient
		end
		local newGradient = Instance.new("UIGradient")
		newGradient.Rotation = 90
		newGradient.Parent = slider
		return newGradient
	end

	local saturationGradient = ensureGradient(saturationSlider)
	local valueGradient = ensureGradient(valueSlider)

	local selectedColorPreview = colorPickerContainer:WaitForChild("SelectedColorPreview")
	if not selectedColorPreview:IsA("ImageLabel") then
		error("BuildPaletteUI missing SelectedColorPreview ImageLabel")
	end
	local previewLabel = selectedColorPreview:WaitForChild("SelectedColorLabel")
	if not previewLabel:IsA("TextLabel") then
		error("BuildPaletteUI missing SelectedColorLabel TextLabel")
	end
	local materialNameLabel = selectedColorPreview:WaitForChild("MaterialNameLabel")
	if not materialNameLabel:IsA("TextLabel") then
		error("BuildPaletteUI missing MaterialNameLabel TextLabel")
	end
	local previewImage = selectedColorPreview :: ImageLabel
	local previewTextLabel = previewLabel :: TextLabel
	local materialNameTextLabel = materialNameLabel :: TextLabel
	materialNameTextLabel.Text = currentMaterialName or "Material"

	sliderRefs = {
		hueSliderFrame = hueSlider,
		saturationSliderFrame = saturationSlider,
		valueSliderFrame = valueSlider,
		saturationGradient = saturationGradient,
		valueGradient = valueGradient,
		selectedColorPreviewImage = previewImage,
		selectedColorLabel = previewTextLabel,
		materialNameLabel = materialNameTextLabel,
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
	if boundMaterialButtons[materialButton] then
		return
	end
	boundMaterialButtons[materialButton] = true
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
		boundMaterialButtons[materialButton] = nil
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
	isSelectModeActive = isActive
	selectButton:SetAttribute("Active", isActive)
	selectButton:SetAttribute("SurfacePaintActive", isActive)
	setCursorActive(isActive)
	selectModeChangedSignal:Fire(isActive)
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
	selectButton.Activated:Connect(function()
		selectActivatedSignal:Fire()
	end)
	exitButton.Activated:Connect(BuildPaletteUI.Hide)
	isInitialized = true
end

function BuildPaletteUI.Show()
	if isPaletteVisible then
		return
	end
	isPaletteVisible = true
	BuildPaletteGui.Enabled = true
	tweenPaletteVisibility(true)
end

function BuildPaletteUI.Hide()
	if not isPaletteVisible then
		return
	end
	isPaletteVisible = false
	tweenPaletteVisibility(false)
end

function BuildPaletteUI.IsVisible(): boolean
	return isPaletteVisible
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

function BuildPaletteUI.OnSelectModeChanged(handler: (boolean) -> ())
	if typeof(handler) ~= "function" then
		error("BuildPaletteUI.OnSelectModeChanged requires a handler function")
	end
	return selectModeChangedSignal:Connect(handler)
end

function BuildPaletteUI.IsSelectModeActive(): boolean
	return isSelectModeActive
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
