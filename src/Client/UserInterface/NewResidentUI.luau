--!strict

-- StarterPlayerScripts/Client/UserInterface/NewResident.lua

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Debounce = require(ReplicatedStorage.Shared.Utilities.Debounce)
local ResidentAppearanceConfig = require(ReplicatedStorage.Shared.Configurations.ResidentAppearanceConfig)
local ResidentAppearanceUtils = require(ReplicatedStorage.Shared.Utilities.ResidentAppearanceUtils)
local ResidentStore = require(script.Parent.Parent.ClientStores.ResidentsStore)
local ResidentsPackets = require(ReplicatedStorage.Network.ResidentsPackets)

local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")
local ActiveQueryFolder = PlayerGui:WaitForChild("ActiveQuery")
local CustomizationUIEnabled = ActiveQueryFolder:WaitForChild("CustomizationUIEnabled") :: BoolValue
local ResidentGui = PlayerGui:WaitForChild("ResidentGui")
local InputContextsFolder = PlayerGui:WaitForChild("InputContexts")
local AddResidentContext = InputContextsFolder:WaitForChild("AddResidentContext")

local AddResidentButton = ResidentGui.ResidentSelectionFrame.Background.Roster:FindFirstChild("AddResidentButton")

local AssetsFolder = ReplicatedStorage:FindFirstChild("Assets")
local ResidentTemplateFolder = AssetsFolder and AssetsFolder:FindFirstChild("Residents")

type AppearanceSelectionIds = {
	SkinToneId: string,
	HairId: string,
	FaceId: string,
	TopId: string,
	PantsId: string,
}

type CreationState = {
	Name: string,
	GenderId: string,
	AgeId: string,
	Appearance: AppearanceSelectionIds,
}

type OptionContainers = { [string]: Frame }
type ButtonsByCategory = { [string]: { [string]: GuiButton } }
type SelectedButtons = { [string]: GuiButton? }
type ButtonStyle = {
	Background: Color3,
	Text: Color3?,
}

type UIRefs = {
	Overlay: Frame?,
	NameInput: TextBox?,
	StatusLabel: TextLabel?,
	CreateButton: TextButton?,
	Viewport: ViewportFrame?,
	World: WorldModel?,
}

type PreviewState = {
	Model: Model?,
	GenderId: string?,
}

local STATUS_DEFAULT_COLOR = Color3.fromRGB(124, 106, 43)
local STATUS_ERROR_COLOR = Color3.fromRGB(198, 84, 72)
local STATUS_SUCCESS_COLOR = Color3.fromRGB(92, 153, 99)
local PRIMARY_BUTTON_COLOR = Color3.fromRGB(79, 163, 255)
local PRIMARY_BUTTON_DISABLED_COLOR = Color3.fromRGB(146, 190, 255)
local PRIMARY_BUTTON_TEXT_COLOR = Color3.fromRGB(255, 255, 255)
local SELECTED_BUTTON_COLOR = Color3.fromRGB(147, 118, 70)
local SELECTED_TEXT_COLOR = Color3.fromRGB(255, 255, 255)

local FALLBACK_PREVIEW_PIVOT = CFrame.new(0, -2.579, -8) * CFrame.Angles(0, math.rad(180), 0)

local optionContainers: OptionContainers = {}
local buttonsByCategory: ButtonsByCategory = {}
local selectedButtons: SelectedButtons = {}
local buttonOriginalStyles: { [GuiButton]: ButtonStyle? } = {}

local uiRefs: UIRefs = {
	Overlay = nil,
	NameInput = nil,
	StatusLabel = nil,
	CreateButton = nil,
	Viewport = nil,
	World = nil,
}

local previewState: PreviewState = {
	Model = nil,
	GenderId = nil,
}

local function trim(text: string): string
	return text:gsub("^%s+", ""):gsub("%s+$", "")
end

local function getPreviewPivot(): CFrame
	local world = uiRefs.World
	if not world then
		return FALLBACK_PREVIEW_PIVOT
	end
	local attributePivot = world:GetAttribute("PreviewPivot")
	if attributePivot and typeof(attributePivot) == "CFrame" then
		return attributePivot
	end
	local pivotContainer = world:FindFirstChild("PreviewPivot")
	if pivotContainer then
		if pivotContainer:IsA("BasePart") then
			return pivotContainer.CFrame
		end
		if pivotContainer:IsA("CFrameValue") then
			return pivotContainer.Value
		end
	end
	return FALLBACK_PREVIEW_PIVOT
end
local OPEN_DEBOUNCE_ID = "ResidentCreation/Open"
local OPEN_DEBOUNCE_SECONDS = 0.25

local interfaceInitialized = false

local SUPPRESSED_CHILD_NAMES: { string } = {
	"ResidentSelectionFrame",
	"ResidentNeedsFrame",
	"ResidentButtons",
	"Profile",
	"ShiftStatusPanel",
}

local suppressedGuiVisibility: { [GuiObject]: boolean } = {}

local OPTION_FIELDS: { [string]: string? } = {
	Hair = "HairId",
	Face = "FaceId",
	Top = "TopId",
	Pants = "PantsId",
	SkinTone = "SkinToneId",
}

local function suppressResidentInterface()
	table.clear(suppressedGuiVisibility)
	if not ResidentGui then
		return
	end
	for _, childName in ipairs(SUPPRESSED_CHILD_NAMES) do
		local descendant = ResidentGui:FindFirstChild(childName)
		if descendant and descendant:IsA("GuiObject") then
			suppressedGuiVisibility[descendant] = descendant.Visible
			descendant.Visible = false
		end
	end
end

local function restoreResidentInterface()
	for guiObject, wasVisible in pairs(suppressedGuiVisibility) do
		if guiObject.Parent then
			guiObject.Visible = wasVisible
		end
	end
	table.clear(suppressedGuiVisibility)
end

local function cloneAppearanceSelection(selection: AppearanceSelectionIds): AppearanceSelectionIds
	return {
		SkinToneId = selection.SkinToneId,
		HairId = selection.HairId,
		FaceId = selection.FaceId,
		TopId = selection.TopId,
		PantsId = selection.PantsId,
	}
end

local function buildDefaultState(): CreationState
	local defaults = ResidentAppearanceConfig.GetDefaultSelection()
	return {
		Name = "",
		GenderId = defaults.GenderId,
		AgeId = defaults.AgeId,
		Appearance = cloneAppearanceSelection(defaults),
	}
end

local currentState: CreationState = buildDefaultState()
local isVisible = false
local isSubmitting = false

local function setButtonSelected(category: string, optionId: string)
	local categoryButtons = buttonsByCategory[category]
	if not categoryButtons then
		return
	end
	local targetButton = categoryButtons[optionId]
	if not targetButton then
		return
	end
	local previous = selectedButtons[category]
	if previous and previous ~= targetButton then
		previous:SetAttribute("Selected", false)
		local previousStyle = buttonOriginalStyles[previous]
		if previousStyle then
			previous.BackgroundColor3 = previousStyle.Background
			if previous:IsA("TextButton") and previousStyle.Text then
				previous.TextColor3 = previousStyle.Text
			end
		end
	end
	local existingStyle = buttonOriginalStyles[targetButton]
	if existingStyle == nil then
		local textColor = nil
		if targetButton:IsA("TextButton") then
			textColor = targetButton.TextColor3
		end
		buttonOriginalStyles[targetButton] = {
			Background = targetButton.BackgroundColor3,
			Text = textColor,
		}
	end
	targetButton:SetAttribute("Selected", true)
	targetButton.BackgroundColor3 = SELECTED_BUTTON_COLOR
	if targetButton:IsA("TextButton") then
		targetButton.TextColor3 = SELECTED_TEXT_COLOR
	end
	selectedButtons[category] = targetButton
end

local function destroyPreviewModel()
	local model = previewState.Model
	if not model then
		previewState.GenderId = nil
		return
	end
	model:Destroy()
	previewState.Model = nil
	previewState.GenderId = nil
end

local function findTemplateForGender(genderId: string?): Model?
	if not ResidentTemplateFolder then
		return nil
	end
	local template = if genderId then ResidentTemplateFolder:FindFirstChild(genderId) else nil
	if template and template:IsA("Model") then
		return template
	end
	local fallback = ResidentTemplateFolder:FindFirstChildOfClass("Model")
	if fallback and fallback:IsA("Model") then
		return fallback
	end
	return nil
end

local function setStatus(text: string, isError: boolean?)
	local statusLabel = uiRefs.StatusLabel
	if not statusLabel then
		return
	end
	statusLabel.Text = text
	if text == "" then
		statusLabel.TextTransparency = 1
	else
		statusLabel.TextTransparency = 0
	end
	if isError == nil then
		statusLabel.TextColor3 = STATUS_DEFAULT_COLOR
	elseif isError then
		statusLabel.TextColor3 = STATUS_ERROR_COLOR
	else
		statusLabel.TextColor3 = STATUS_SUCCESS_COLOR
	end
end

local function updateCreateButtonState()
	local createButton = uiRefs.CreateButton
	if not createButton then
		return
	end
	createButton.AutoButtonColor = not isSubmitting
	createButton.Active = not isSubmitting
	createButton.Text = if isSubmitting then "Saving..." else "Save"
	createButton.BackgroundColor3 = if isSubmitting then PRIMARY_BUTTON_DISABLED_COLOR else PRIMARY_BUTTON_COLOR
	createButton.TextColor3 = PRIMARY_BUTTON_TEXT_COLOR
	createButton.TextTransparency = if isSubmitting then 0.25 else 0
end

local function ensurePreviewAssetsExists(): boolean
	local viewportFrame = uiRefs.Viewport
	if not viewportFrame then
		setStatus("Preview unavailable: viewport missing", true)
		return false
	end
	if not uiRefs.World then
		setStatus("Preview unavailable: preview world missing", true)
		return false
	end
	return true
end

local function ensurePreviewModel(): boolean
	if not ensurePreviewAssetsExists() then
		return false
	end
	if not ResidentTemplateFolder then
		setStatus("Preview unavailable: resident templates missing", true)
		return false
	end
	local genderId = currentState.GenderId
	local world = uiRefs.World
	local model = previewState.Model
	local requiresNewModel = previewState.GenderId ~= genderId or model == nil or model.Parent ~= world
	if requiresNewModel then
		destroyPreviewModel()
		local template = findTemplateForGender(genderId)
		if not template or not template:IsA("Model") then
			setStatus("Preview unavailable: template missing", true)
			return false
		end
		if not world then
			return false
		end
		local cloned = template:Clone()
		local pivotCFrame = getPreviewPivot()
		cloned:PivotTo(pivotCFrame)
		cloned.Parent = world
		cloned:SetAttribute("TemplateGender", genderId)
		local animate = cloned:FindFirstChild("Animate")
		if animate then
			animate:Destroy()
		end
		previewState.Model = cloned
		previewState.GenderId = genderId
	end
	return previewState.Model ~= nil
end
local function refreshPreview()
	if not ensurePreviewModel() then
		return
	end
	local ageDefinition = ResidentAppearanceConfig.ResolveAge(currentState.AgeId)
	local model = previewState.Model
	if not model then
		return
	end
	local resolvedAge = ageDefinition or ResidentAppearanceConfig.AgeOptions[1]
	ResidentAppearanceUtils.ApplyToModel(model, currentState.Appearance, resolvedAge.Numeric, {
		AnchorRootPart = true,
		FreezeHumanoid = true,
	})
	model:PivotTo(getPreviewPivot())
end

local function clearSelections()
	for category, button in pairs(selectedButtons) do
		if button then
			button:SetAttribute("Selected", false)
			local original = buttonOriginalStyles[button]
			if original then
				button.BackgroundColor3 = original.Background
				if button:IsA("TextButton") and original.Text then
					button.TextColor3 = original.Text
				end
			end
		end
		selectedButtons[category] = nil
	end
end

local function applyStateToUI()
	local nameInput = uiRefs.NameInput
	if nameInput then
		nameInput.Text = currentState.Name
	end
	clearSelections()
	setButtonSelected("Gender", currentState.GenderId)
	setButtonSelected("Age", currentState.AgeId)
	setButtonSelected("SkinTone", currentState.Appearance.SkinToneId)
	setButtonSelected("Hair", currentState.Appearance.HairId)
	setButtonSelected("Face", currentState.Appearance.FaceId)
	setButtonSelected("Top", currentState.Appearance.TopId)
	setButtonSelected("Pants", currentState.Appearance.PantsId)
	updateCreateButtonState()
	setStatus("", nil)
	refreshPreview()
	if nameInput then
		nameInput:CaptureFocus()
	end
end

local function onGenderSelected(optionId: string)
	if currentState.GenderId == optionId then
		return
	end
	currentState.GenderId = optionId
	setButtonSelected("Gender", optionId)
	refreshPreview()
end

local function onAgeSelected(optionId: string)
	if currentState.AgeId == optionId then
		return
	end
	currentState.AgeId = optionId
	setButtonSelected("Age", optionId)
	refreshPreview()
end

local function onAppearanceSelected(category: string, fieldName: string, optionId: string)
	local appearance = currentState.Appearance
	if appearance[fieldName] == optionId then
		return
	end
	appearance[fieldName] = optionId
	setButtonSelected(category, optionId)
	refreshPreview()
end

local function closeModal()
	local overlay = uiRefs.Overlay
	if not overlay then
		return
	end
	local nameInput = uiRefs.NameInput
	if nameInput then
		nameInput:ReleaseFocus()
	end
	destroyPreviewModel()
	restoreResidentInterface()
	overlay.Visible = false
	CustomizationUIEnabled.Value = false
	isVisible = false
	isSubmitting = false
	updateCreateButtonState()
	setStatus("", nil)
end

local function submitCreation()
	local nameInput = uiRefs.NameInput
	if isSubmitting or not nameInput then
		return
	end
	local trimmedName = trim(nameInput.Text)
	if trimmedName == "" then
		setStatus("Please enter a resident name.", true)
		nameInput:CaptureFocus()
		return
	end
	currentState.Name = trimmedName
	isSubmitting = true
	updateCreateButtonState()
	setStatus("Submitting resident...", nil)

	task.spawn(function()
		local success, message = ResidentStore.RequestAddResident({
			Name = currentState.Name,
			GenderId = currentState.GenderId,
			AgeId = currentState.AgeId,
			Appearance = cloneAppearanceSelection(currentState.Appearance),
		})
		if success then
			setStatus("Resident created!", false)
			task.delay(0.25, closeModal)
		else
			setStatus(message or "Unable to create resident.", true)
		end
		isSubmitting = false
		updateCreateButtonState()
	end)
end

local function registerOptionButtons()
	table.clear(buttonsByCategory)
	for category, container in pairs(optionContainers) do
		local categoryButtons: { [string]: GuiButton } = {}
		for _, descendant in ipairs(container:GetDescendants()) do
			if descendant:IsA("GuiButton") then
				local button = descendant :: GuiButton
				local attributeId = button:GetAttribute("OptionId")
				local optionId = if typeof(attributeId) == "string" and attributeId ~= ""
					then attributeId
					else button.Name
				categoryButtons[optionId] = button
				if buttonOriginalStyles[button] == nil then
					local textColor = nil
					if button:IsA("TextButton") then
						textColor = button.TextColor3
					end
					buttonOriginalStyles[button] = {
						Background = button.BackgroundColor3,
						Text = textColor,
					}
				end
				button.Activated:Connect(function()
					if category == "Gender" then
						onGenderSelected(optionId)
						return
					end
					if category == "Age" then
						onAgeSelected(optionId)
						return
					end
					local fieldName = OPTION_FIELDS[category]
					if fieldName then
						onAppearanceSelected(category, fieldName, optionId)
					end
				end)
				button:SetAttribute("Selected", false)
				local style = buttonOriginalStyles[button]
				if style then
					button.BackgroundColor3 = style.Background
					if button:IsA("TextButton") and style.Text then
						button.TextColor3 = style.Text
					end
				end
			end
		end
		buttonsByCategory[category] = categoryButtons
	end
end

local function initInterface()
	if interfaceInitialized then
		return
	end

	interfaceInitialized = true
	currentState = buildDefaultState()
	table.clear(optionContainers)
	table.clear(buttonsByCategory)
	table.clear(selectedButtons)

	local overlay = ResidentGui:WaitForChild("ResidentCreationOverlay") :: Frame
	local modal = overlay:WaitForChild("Modal") :: Frame
	local contentContainer = modal:WaitForChild("ContentContainer") :: Frame
	local nameRow = contentContainer:WaitForChild("NameRow") :: Frame
	local inputColumn = nameRow:WaitForChild("InputColumn") :: GuiObject
	local nameBox = inputColumn:WaitForChild("NameInput") :: TextBox
	local create = nameRow:WaitForChild("CreateButton") :: TextButton
	local mainContent = contentContainer:WaitForChild("MainContent") :: Frame
	local leftColumn = mainContent:WaitForChild("LeftColumn") :: GuiObject
	local rightColumn = mainContent:WaitForChild("RightColumn") :: GuiObject
	local previewColumn = mainContent:WaitForChild("PreviewColumn") :: Frame
	local viewportContainer = previewColumn:WaitForChild("ViewportContainer") :: GuiObject
	local viewport = viewportContainer:WaitForChild("ResidentPreview") :: ViewportFrame
	local closeButton = modal:WaitForChild("CloseButton") :: TextButton

	uiRefs.Overlay = overlay
	overlay.Visible = false
	uiRefs.NameInput = nameBox
	uiRefs.CreateButton = create
	uiRefs.StatusLabel = previewColumn:WaitForChild("Status") :: TextLabel
	uiRefs.Viewport = viewport
	uiRefs.World = viewport:WaitForChild("WorldModel") :: WorldModel

	closeButton.Activated:Connect(function()
		if isSubmitting then
			return
		end
		closeModal()
	end)

	nameBox.FocusLost:Connect(function()
		local sanitized = trim(nameBox.Text)
		currentState.Name = sanitized
		nameBox.Text = sanitized
	end)

	create.Activated:Connect(submitCreation)

	optionContainers.Hair = (leftColumn:WaitForChild("HairSection") :: Frame):WaitForChild("Options") :: Frame
	optionContainers.Face = (leftColumn:WaitForChild("FaceSection") :: Frame):WaitForChild("Options") :: Frame
	optionContainers.Top = (leftColumn:WaitForChild("TopSection") :: Frame):WaitForChild("Options") :: Frame
	optionContainers.Pants = (rightColumn:WaitForChild("PantsSection") :: Frame):WaitForChild("Options") :: Frame
	optionContainers.SkinTone = (rightColumn:WaitForChild("SkinToneSection") :: Frame):WaitForChild("Options") :: Frame
	optionContainers.Age = (rightColumn:WaitForChild("AgeSection") :: Frame):WaitForChild("Options") :: Frame
	optionContainers.Gender = (rightColumn:WaitForChild("GenderSection") :: Frame):WaitForChild("Options") :: Frame

	registerOptionButtons()

	UserInputService.InputBegan:Connect(function(inputObject, processed)
		if processed or not isVisible then
			return
		end
		if inputObject.KeyCode == Enum.KeyCode.Escape then
			closeModal()
		end
	end)

	updateCreateButtonState()
end

local function openModal()
	initInterface()
	local overlay = uiRefs.Overlay
	if not overlay then
		return
	end
	currentState = buildDefaultState()
	destroyPreviewModel()
	suppressResidentInterface()
	overlay.Visible = true
	CustomizationUIEnabled.Value = true
	isVisible = true
	applyStateToUI()
end

local function requestOpenModal()
	Debounce.RunIfAvailable(OPEN_DEBOUNCE_ID, OPEN_DEBOUNCE_SECONDS, openModal, Player.UserId)
end

local function connectTriggers()
	AddResidentContext.AddResidentButton.Pressed:Connect(function()
		requestOpenModal()
	end)
	if AddResidentButton and AddResidentButton:IsA("TextButton") then
		AddResidentButton.Activated:Connect(function()
			requestOpenModal()
		end)
	end
end

local NewResidentUI = {}

function NewResidentUI.Init()
	initInterface()
	connectTriggers()
	ResidentsPackets.PromptResidentCreation.OnClientEvent:Connect(function()
		requestOpenModal()
	end)
end

return NewResidentUI
