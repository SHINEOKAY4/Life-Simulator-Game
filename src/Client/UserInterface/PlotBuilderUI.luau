--!strict
-- StarterPlayerScripts/Client/UserInterface/PlotBuilderUI.luau

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local PlotBuilder = require(script.Parent.Parent.Modules.PlotBuilder)
local Debounce = require(ReplicatedStorage.Shared.Utilities.Debounce)
local ItemFinder = require(ReplicatedStorage.Shared.Utilities.ItemFinder)
local Tooltip = require(script.Parent:WaitForChild("Tooltip"))
local PlotStateStore = require(script.Parent.Parent.ClientStores.PlotStateStore)

local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")

local plotBuilderGuiInstance = PlayerGui:FindFirstChild("PlotBuilderUI") or PlayerGui:FindFirstChild("PlotBuilderGui")
assert(
	plotBuilderGuiInstance and plotBuilderGuiInstance:IsA("ScreenGui"),
	"PlotBuilderUI expected PlotBuilderUI or PlotBuilderGui ScreenGui"
)
local PlotBuilderGui = plotBuilderGuiInstance :: ScreenGui

local InputContextsFolder = PlayerGui:WaitForChild("InputContexts")
local PreviewContext = InputContextsFolder:WaitForChild("PreviewContext")
local CancelPreviewAction = PreviewContext:FindFirstChild("CancelPreview")
local FloorContext = InputContextsFolder:WaitForChild("FloorContext")
local FloorUpAction = FloorContext:WaitForChild("UpButton")
local FloorDownAction = FloorContext:WaitForChild("DownButton")

local AssetsFolder = ReplicatedStorage:WaitForChild("Assets")
local InterfacesTemplatesFolder = AssetsFolder:WaitForChild("InterfacesTemplates")
local ItemButtonTemplate = InterfacesTemplatesFolder:WaitForChild("ItemButtonTemplate") :: ImageButton
local CancelButtonTemplate = InterfacesTemplatesFolder:WaitForChild("CancelButton") :: TextButton

local MainFrame = PlotBuilderGui:WaitForChild("Main") :: Frame
local RightFrame = MainFrame:WaitForChild("Right") :: Frame
local LeftFrame = MainFrame:WaitForChild("Left") :: Frame
local UpFrame = LeftFrame:WaitForChild("UpFrame") :: Frame
local UpButton = UpFrame:WaitForChild("UpButton") :: GuiButton
local UpTextLabel = UpFrame:FindFirstChildWhichIsA("TextLabel")
local DownFrame = LeftFrame:WaitForChild("DownFrame") :: Frame
local DownButton = DownFrame:WaitForChild("DownButton") :: GuiButton
local DownTextLabel = DownFrame:FindFirstChildWhichIsA("TextLabel")
local Header = RightFrame:FindFirstChild("Header") :: Frame
local SearchFrame = Header and Header:FindFirstChild("SearchFrame")
local LeftDockFrame = RightFrame:WaitForChild("LeftDock") :: Frame
local CategoriesFrame = LeftDockFrame:WaitForChild("Categories") :: Frame
local RightDockFrame = RightFrame:WaitForChild("RightDock") :: Frame
local ScrollingFrame = RightDockFrame:WaitForChild("ScrollingFrame") :: ScrollingFrame
local TitleLabel = Header:WaitForChild("Title") :: TextLabel
local CategorySelectionFolder = PlotBuilderGui:FindFirstChild("CategorySelection")
local PanelsInputContexts = PlotBuilderGui:FindFirstChild("PanelsInputContexts")
local ExitButtonContextFolder = PlotBuilderGui:FindFirstChild("ExitButtonContext")
local ExitAction = ExitButtonContextFolder and ExitButtonContextFolder:FindFirstChild("ExitButton")

local ActiveQueryFolder = PlayerGui:FindFirstChild("ActiveQuery")
local PlotBuilderEnabledValue = ActiveQueryFolder and ActiveQueryFolder:FindFirstChild("PlotBuilderEnabled")
local ObjectPreviewEnabledValue = ActiveQueryFolder and ActiveQueryFolder:FindFirstChild("ObjectPreviewEnabled")
local PlotExpansionEnabledValue = ActiveQueryFolder and ActiveQueryFolder:FindFirstChild("PlotExpansionEnabled")
local ObjectSelectorEnabledValue = ActiveQueryFolder and ActiveQueryFolder:FindFirstChild("ObjectSelectorEnabled")

local Categories = {
	"Build",
	"Furnitures",
	"Appliances",
	"Decorations",
	"Utilities",
	"Outdoor",
	"Rooms",
}

local INPUT_DEBOUNCE_SECONDS = 0.2
local PLACEHOLDER_THUMBNAIL = "rbxasset://textures/ui/GuiImagePlaceholder.png"
local THUMBNAIL_TEMPLATE = "rbxthumb://type=Asset&id=%d&w=420&h=420"
local CATEGORY_HOVER_OFFSET = Vector2.new(12, 8)
local CATEGORY_HOVER_TWEEN = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

type ItemSpec = { [string]: any }
type ItemEntry = { Id: string, Spec: ItemSpec, Path: { string } }
type SearchResultEntry = { Id: string, Spec: ItemSpec, Path: { string }, Category: string }
type FilterInfo = {
	Key: string?,
	RawKey: string,
	Button: GuiButton?,
	Action: Instance?,
}
type CategoryInfo = {
	Button: GuiButton?,
	Label: TextLabel?,
	Panel: Frame?,
	Filters: { [string]: FilterInfo },
	FilterOrder: { FilterInfo },
	ActiveFilterKey: string?,
}
type ButtonVisualState = "base" | "hover"
type ButtonMetrics = {
	BaseSize: UDim2,
	BasePosition: UDim2,
	HoverSize: UDim2,
	HoverPosition: UDim2,
	Hovered: boolean,
}

local PlotBuilderUI = {}
local CategoryInfos: { [string]: CategoryInfo } = {}
local CurrentCategory: string? = nil
local CurrentPanel: Frame? = nil
local ActiveItemButton: GuiButton? = nil
local SearchQuery = ""
local SearchQueryRaw = ""
local CachedSearchKey: string? = nil
local CachedSearchResults: { SearchResultEntry } = {}

local ItemLayout = ScrollingFrame:FindFirstChildWhichIsA("UIGridLayout")
local EmptyStateLabel: TextLabel? = nil
local CategoryButtonMetrics: { [GuiButton]: ButtonMetrics } = {}
local CategoryButtonTweens: { [GuiButton]: Tween? } = {}
local PreviewControlsFrame: Frame? = nil
local CancelPreviewButton: TextButton? = nil
local CancelActionPressedConnection: RBXScriptConnection? = nil
local CancelRKeyConnection: RBXScriptConnection? = nil
local ActiveLevelChangedConnection: RBXScriptConnection? = nil
local ExternalCancelSource: string? = nil
local ExternalCancelHandler: (() -> ())? = nil
local EXIT_BUTTON_BOUND_ATTRIBUTE = "PlotBuilderExitBound"

local function formatLevelDisplay(level: number): string
	local defaultLevel = PlotStateStore.GetDefaultLevel()
	local displayIndex = level - defaultLevel + 1
	if displayIndex < 1 then
		displayIndex = 1
	end
	return string.format("Level %d", displayIndex)
end

local function refreshLevelControls()
	local currentLevel = PlotStateStore.GetActiveLevel()
	local defaultLevel = PlotStateStore.GetDefaultLevel()
	local maxLevel = PlotStateStore.GetMaxLevel()
	local canGoUp = currentLevel < maxLevel
	local canGoDown = currentLevel > defaultLevel

	if UpButton then
		UpButton.Active = canGoUp
		if UpButton:IsA("ImageButton") then
			UpButton.AutoButtonColor = canGoUp
		end
	end
	if DownButton then
		DownButton.Active = canGoDown
		if DownButton:IsA("ImageButton") then
			DownButton.AutoButtonColor = canGoDown
		end
	end

	if UpTextLabel and UpTextLabel:IsA("TextLabel") then
		if canGoUp then
			UpTextLabel.Text = formatLevelDisplay(currentLevel + 1)
		else
			UpTextLabel.Text = "Top Level"
		end
	end

	if DownTextLabel and DownTextLabel:IsA("TextLabel") then
		if canGoDown then
			DownTextLabel.Text = formatLevelDisplay(currentLevel - 1)
		else
			DownTextLabel.Text = "Ground Level"
		end
	end
end

local function changeActiveLevel(delta: number)
	local currentLevel = PlotStateStore.GetActiveLevel()
	PlotBuilder.RegisterFloorInput()
	PlotStateStore.SetActiveLevel(currentLevel + delta)
end

local selectCategory: (string) -> ()
local populateCategoryItems: (string, string?) -> ()
local refreshItems: () -> ()
local refreshCategoryButtonVisual: (GuiButton, boolean?) -> ()
local bindCategoryHoverEffect: (GuiButton) -> ()
local handleFilterInput: (string, string?) -> ()

local function connectDebounced(action: Instance?, actionName: string, callback: () -> ())
	if not action or not action:IsA("InputAction") then
		return
	end

	action.Pressed:Connect(function()
		Debounce.RunIfAvailable(
			string.format("PlotBuilderUI/%s", actionName),
			INPUT_DEBOUNCE_SECONDS,
			callback,
			Player.UserId
		)
	end)
end

local function bindFloorLevelActions()
	connectDebounced(FloorUpAction, "FloorLevelUp", function()
		changeActiveLevel(1)
	end)

	connectDebounced(FloorDownAction, "FloorLevelDown", function()
		changeActiveLevel(-1)
	end)
end

local function trim(text: string): string
	local trimmed = text:gsub("^%s+", "")
	return trimmed:gsub("%s+$", "")
end

local function escapeRichText(text: string): string
	local escaped = text:gsub("&", "&amp;")
	escaped = escaped:gsub("<", "&lt;")
	escaped = escaped:gsub(">", "&gt;")
	return escaped
end

local function normalizeFilterKey(rawValue: string?): string?
	if typeof(rawValue) ~= "string" then
		return nil
	end

	local trimmed = trim(rawValue)
	if trimmed == "" then
		return nil
	end

	return string.lower(trimmed)
end

local function normalizeSearch(term: string?): string
	if typeof(term) ~= "string" then
		return ""
	end

	return string.lower(trim(term))
end

local function normalizedEquals(value: any, normalized: string): boolean
	if typeof(value) ~= "string" then
		return false
	end

	return normalizeFilterKey(value) == normalized
end

local function boolValueTrue(value: BoolValue?): boolean
	return value ~= nil and value.Value == true
end

local function isPreviewActive(): boolean
	return boolValueTrue(ObjectPreviewEnabledValue)
end

local function shouldShowMainFrame(): boolean
	if PlotBuilderEnabledValue and not boolValueTrue(PlotBuilderEnabledValue) then
		return false
	end

	if PlotExpansionEnabledValue and boolValueTrue(PlotExpansionEnabledValue) then
		return false
	end

	if ObjectSelectorEnabledValue and boolValueTrue(ObjectSelectorEnabledValue) then
		return false
	end

	return true
end

local function updateCancelButtonState()
	if not CancelPreviewButton then
		return
	end

	local previewActive = boolValueTrue(ObjectPreviewEnabledValue) and boolValueTrue(PlotBuilderEnabledValue)
	local externalActive = ExternalCancelSource ~= nil
	local buttonVisible = previewActive or externalActive

	if PreviewControlsFrame then
		PreviewControlsFrame.Visible = buttonVisible
	end

	CancelPreviewButton.Active = buttonVisible
	CancelPreviewButton.AutoButtonColor = buttonVisible
	CancelPreviewButton.Selectable = buttonVisible
	CancelPreviewButton.Visible = buttonVisible
	CancelPreviewButton:SetAttribute("PreviewActive", previewActive)

	local keyHint = CancelPreviewButton:FindFirstChild("KeyHint")
	if keyHint and keyHint:IsA("TextLabel") then
		keyHint.Visible = buttonVisible
	end
end

local function syncVisibility()
	local builderVisible = shouldShowMainFrame()
	local previewActive = isPreviewActive()
	MainFrame.Visible = builderVisible
	if LeftFrame then
		LeftFrame.Visible = builderVisible
	end
	if RightFrame then
		RightFrame.Visible = builderVisible and not previewActive
	end
end

local function ensureItemLayout()
	if ItemLayout then
		return
	end

	local layout = Instance.new("UIGridLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.CellPadding = UDim2.fromOffset(8, 8)
	layout.CellSize = UDim2.fromOffset(180, 180)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	layout.VerticalAlignment = Enum.VerticalAlignment.Top
	layout.Parent = ScrollingFrame

	ItemLayout = layout
end

local function ensureEmptyStateLabel(message: string?)
	if not EmptyStateLabel then
		local label = Instance.new("TextLabel")
		label.Name = "EmptyState"
		label.BackgroundTransparency = 1
		label.Size = UDim2.new(1, 0, 0, 48)
		label.Font = Enum.Font.Gotham
		label.TextSize = 18
		label.TextColor3 = Color3.fromRGB(210, 210, 210)
		label.TextWrapped = true
		label.RichText = true
		EmptyStateLabel = label
	end

	local label = EmptyStateLabel :: TextLabel
	label.Text = message or "<i>No items available yet.</i>"
	label.Visible = true
	label.Parent = ScrollingFrame
end

local function hideEmptyStateLabel()
	if EmptyStateLabel then
		EmptyStateLabel.Visible = false
		EmptyStateLabel.Parent = nil
	end
end

local function animateCategoryButton(
	button: GuiButton,
	metrics: ButtonMetrics,
	targetState: ButtonVisualState,
	instant: boolean?
)
	local targetSize: UDim2
	local targetPosition: UDim2

	if targetState == "hover" then
		targetSize = metrics.HoverSize
		targetPosition = metrics.HoverPosition
	else
		targetSize = metrics.BaseSize
		targetPosition = metrics.BasePosition
	end

	if instant then
		button.Size = targetSize
		button.Position = targetPosition
		local activeInstantTween = CategoryButtonTweens[button]
		if activeInstantTween then
			activeInstantTween:Cancel()
			CategoryButtonTweens[button] = nil
		end
		return
	end

	local activeTween = CategoryButtonTweens[button]
	if activeTween then
		activeTween:Cancel()
	end

	if button.Size == targetSize and button.Position == targetPosition then
		CategoryButtonTweens[button] = nil
		return
	end

	local tween = TweenService:Create(button, CATEGORY_HOVER_TWEEN, {
		Size = targetSize,
		Position = targetPosition,
	})
	CategoryButtonTweens[button] = tween

	tween.Completed:Connect(function()
		if CategoryButtonTweens[button] == tween then
			CategoryButtonTweens[button] = nil
		end
	end)

	tween:Play()
end

refreshCategoryButtonVisual = function(button: GuiButton, instant: boolean?)
	local metrics = CategoryButtonMetrics[button]
	if not metrics then
		return
	end

	local shouldHover = metrics.Hovered or button:GetAttribute("Selected") == true
	local targetState: ButtonVisualState = "base"
	if shouldHover then
		targetState = "hover"
	end
	animateCategoryButton(button, metrics, targetState, instant)
end

bindCategoryHoverEffect = function(button: GuiButton)
	if CategoryButtonMetrics[button] then
		return
	end

	local baseSize = button.Size
	local basePosition = button.Position
	local hoverSize = UDim2.new(
		baseSize.X.Scale,
		baseSize.X.Offset + CATEGORY_HOVER_OFFSET.X,
		baseSize.Y.Scale,
		baseSize.Y.Offset + CATEGORY_HOVER_OFFSET.Y
	)
	local hoverPosition = UDim2.new(
		basePosition.X.Scale,
		basePosition.X.Offset - math.floor(CATEGORY_HOVER_OFFSET.X / 2),
		basePosition.Y.Scale,
		basePosition.Y.Offset - math.floor(CATEGORY_HOVER_OFFSET.Y / 2)
	)

	local metrics: ButtonMetrics = {
		BaseSize = baseSize,
		BasePosition = basePosition,
		HoverSize = hoverSize,
		HoverPosition = hoverPosition,
		Hovered = false,
	}

	CategoryButtonMetrics[button] = metrics

	button.MouseEnter:Connect(function()
		local stored = CategoryButtonMetrics[button]
		if not stored then
			return
		end
		stored.Hovered = true
		refreshCategoryButtonVisual(button)
		local categoryNameAttr = button:GetAttribute("PlotBuilderCategoryName")
		if typeof(categoryNameAttr) == "string" then
			local info = CategoryInfos[categoryNameAttr]
			if info and info.Label then
				info.Label.Visible = true
			end
		end
	end)

	button.MouseLeave:Connect(function()
		local stored = CategoryButtonMetrics[button]
		if not stored then
			return
		end
		stored.Hovered = false
		refreshCategoryButtonVisual(button)
		local categoryNameAttr = button:GetAttribute("PlotBuilderCategoryName")
		if typeof(categoryNameAttr) == "string" and CurrentCategory ~= categoryNameAttr then
			local info = CategoryInfos[categoryNameAttr]
			if info and info.Label then
				info.Label.Visible = false
			end
		end
	end)

	button.AncestryChanged:Connect(function(_, parent)
		if parent ~= nil then
			return
		end

		local activeTween = CategoryButtonTweens[button]
		if activeTween then
			activeTween:Cancel()
		end

		CategoryButtonTweens[button] = nil
		CategoryButtonMetrics[button] = nil
		local categoryNameAttr = button:GetAttribute("PlotBuilderCategoryName")
		if typeof(categoryNameAttr) == "string" and CurrentCategory ~= categoryNameAttr then
			local info = CategoryInfos[categoryNameAttr]
			if info and info.Label then
				info.Label.Visible = false
			end
		end
	end)

	refreshCategoryButtonVisual(button, true)
end

local function clearActiveSelection()
	if ActiveItemButton then
		ActiveItemButton:SetAttribute("Selected", false)
		ActiveItemButton = nil
	end
end

local function clearItemButtons()
	clearActiveSelection()
	for _, child in ipairs(ScrollingFrame:GetChildren()) do
		if child:IsA("GuiButton") then
			child:Destroy()
		end
	end
end

local function buildThumbnail(spec: ItemSpec): string
	local assetId = spec.AssetId
	if typeof(assetId) == "number" and assetId > 0 then
		return string.format(THUMBNAIL_TEMPLATE, assetId)
	end

	return PLACEHOLDER_THUMBNAIL
end

local function formatCategoryPath(categoryName: string?, path: { string }): string?
	local segments = table.create(#path + 1)
	if categoryName and categoryName ~= "" then
		segments[#segments + 1] = categoryName
	end
	for _, segment in ipairs(path) do
		segments[#segments + 1] = segment
	end
	if #segments == 0 then
		return nil
	end
	return table.concat(segments, " > ")
end

local function formatTags(spec: ItemSpec): string?
	local tags = spec.Tags
	if typeof(tags) == "table" and #tags > 0 then
		return "Tags: " .. table.concat(tags, " / ")
	end
	return nil
end

local function resolveItemDescription(entry: ItemEntry, categoryName: string?): string
	local spec = entry.Spec
	local description = spec.Description
	if typeof(description) == "string" and description ~= "" then
		return description
	end
	local categoryPath = formatCategoryPath(categoryName, entry.Path)
	if categoryPath then
		return string.format("Available under %s.", categoryPath)
	end
	local tagsLine = formatTags(spec)
	if tagsLine then
		return tagsLine
	end
	return "Preview this item to see how it reshapes your plot."
end

local NEED_EMOJI: { [string]: string } = {
	Hunger = "🍽",
	Energy = "😴",
	Hygiene = "🧼",
	Social = "🗨",
	Fun = "🎮",
	Bladder = "🚽",
}

local DURATION_EMOJI = "⏱"
local POWER_EMOJI = "⚡"
local STORAGE_EMOJI = "📦"

local REST_MODE_SUMMARY: { [string]: { DurationSeconds: number?, RatePerHour: number? } } = {
	Sleep = { DurationSeconds = 420, RatePerHour = 12 },
	Nap = { DurationSeconds = 180, RatePerHour = 10 },
	Relax = { DurationSeconds = 210, RatePerHour = 9 },
	DaySleep = { DurationSeconds = 240, RatePerHour = 10 },
	Ground = { DurationSeconds = 420, RatePerHour = 6 },
}

type DetailSegment = {
	label: string,
	value: string,
}

local function formatNeedLabel(needName: string): string
	if needName == "" then
		return "Need"
	end
	local emoji = NEED_EMOJI[needName]
	if emoji then
		return string.format("%s %s", emoji, needName)
	end
	return needName
end

local function formatEffectValue(rateValue: number?, amountValue: number?): string?
	if typeof(rateValue) == "number" then
		local rounded = math.floor(math.abs(rateValue) + 0.5)
		local sign = if rateValue >= 0 then "+" else "-"
		return string.format("%s%d/hr", sign, rounded)
	end
	if typeof(amountValue) == "number" then
		local rounded = math.floor(math.abs(amountValue) + 0.5)
		local sign = if amountValue >= 0 then "+" else "-"
		return string.format("%s%d", sign, rounded)
	end
	return nil
end

local function collectDetailSegments(entry: ItemEntry): { DetailSegment }
	local spec = entry.Spec
	local segments: { DetailSegment } = {}

	local cost = spec.Cost
	if typeof(cost) == "number" then
		segments[#segments + 1] = {
			label = "Cost",
			value = string.format("$%d", math.floor(cost + 0.5)),
		}
	end

	local stationEffects = spec.StationEffects
	if typeof(stationEffects) == "table" then
		local restDefaults = nil
		local restMode = stationEffects.RestMode
		if typeof(restMode) == "string" then
			restDefaults = REST_MODE_SUMMARY[restMode]
		end

		local duration = stationEffects.DurationSeconds
		if typeof(duration) ~= "number" and restDefaults and typeof(restDefaults.DurationSeconds) == "number" then
			duration = restDefaults.DurationSeconds
		end
		if typeof(duration) == "number" then
			segments[#segments + 1] = {
				label = string.format("%s Duration", DURATION_EMOJI),
				value = string.format("%ds", math.floor(duration + 0.5)),
			}
		end

		local effectsList = stationEffects.Effects
		local addedEffectLine = false
		if typeof(effectsList) == "table" then
			for _, effect in ipairs(effectsList) do
				local needName = effect.Need
				if typeof(needName) == "string" and needName ~= "" then
					local displayValue = formatEffectValue(effect.RatePerHour, effect.Amount or effect.Instant)
					if displayValue then
						segments[#segments + 1] = {
							label = formatNeedLabel(needName),
							value = displayValue,
						}
						addedEffectLine = true
					end
				end
			end
		end

		if not addedEffectLine and restDefaults and typeof(restDefaults.RatePerHour) == "number" then
			local restValue = formatEffectValue(restDefaults.RatePerHour, nil)
			if restValue then
				segments[#segments + 1] = {
					label = formatNeedLabel("Energy"),
					value = restValue,
				}
			end
		end
	end

	local energyUse = spec.EnergyConsumptionPerHour
	if typeof(energyUse) == "number" and energyUse > 0 then
		segments[#segments + 1] = {
			label = string.format("%s Power", POWER_EMOJI),
			value = string.format("-%d/hr", math.floor(energyUse + 0.5)),
		}
	end

	local storage = spec.StorageConfig
	if typeof(storage) == "table" then
		local capacity = storage.Capacity
		if typeof(capacity) == "number" and capacity > 0 then
			segments[#segments + 1] = {
				label = string.format("%s Storage", STORAGE_EMOJI),
				value = string.format("%d slots", math.floor(capacity + 0.5)),
			}
		end
	end

	return segments
end

local function buildDetailLine(entry: ItemEntry): string
	local segments = collectDetailSegments(entry)
	if #segments == 0 then
		return ""
	end

	local parts = table.create(#segments)
	for index, segment in ipairs(segments) do
		parts[index] = string.format("%s %s", segment.label, segment.value)
	end

	return table.concat(parts, "    ")
end

local function attachItemTooltip(button: GuiButton, entry: ItemEntry, categoryName: string?)
	local spec = entry.Spec
	local itemName = typeof(spec.Name) == "string" and spec.Name or entry.Id
	local description = resolveItemDescription(entry, categoryName)
	local detailText = buildDetailLine(entry)
	local thumbnail = buildThumbnail(spec)

	local tooltip = Tooltip.new(button, {
		title = itemName,
		description = description,
		detailText = detailText,
		thumbnail = thumbnail,
		delay = 0.1,
		maxWidth = 360,
		detailTextSize = 16,
	})

	tooltip:SetItemContent({
		Title = itemName,
		Description = description,
		Detail = detailText,
		Thumbnail = thumbnail,
	})

	button.Destroying:Connect(function()
		tooltip:Destroy()
	end)
end

local function formatCost(costValue: any): string
	if typeof(costValue) ~= "number" then
		return "—"
	end

	return string.format("$%d", math.floor(costValue + 0.5))
end

local function configureItemButton(button: ImageButton, entry: ItemEntry, layoutOrder: number)
	button.Name = entry.Id
	button.LayoutOrder = layoutOrder
	button.Visible = true
	button.Image = buildThumbnail(entry.Spec)
	button:SetAttribute("Selected", false)

	local infoFrame = button:FindFirstChild("Info")
	if infoFrame and infoFrame:IsA("Frame") then
		local costLabel = infoFrame:FindFirstChild("ItemCost")
		if costLabel and costLabel:IsA("TextLabel") then
			costLabel.Text = formatCost(entry.Spec.Cost)
		end

		local nameLabel = infoFrame:FindFirstChild("ItemName")
		if nameLabel and nameLabel:IsA("TextLabel") then
			local displayName = entry.Spec.Name
			nameLabel.Text = typeof(displayName) == "string" and displayName or entry.Id
		end
	end
end

local function selectItemButton(button: GuiButton, entry: ItemEntry)
	if ActiveItemButton and ActiveItemButton ~= button then
		ActiveItemButton:SetAttribute("Selected", false)
	end

	ActiveItemButton = button
	button:SetAttribute("Selected", true)

	local spec = entry.Spec
	local facing = spec.Facing
	local initialFacing: string? = nil
	if typeof(facing) == "table" and #facing > 0 then
		local firstFacing = facing[1]
		if typeof(firstFacing) == "string" then
			initialFacing = firstFacing
		end
	end

	PlotBuilder.PreviewSelected(entry.Id, initialFacing)
end

local function ensurePreviewControlsFrame(): Frame
	if PreviewControlsFrame and PreviewControlsFrame.Parent then
		return PreviewControlsFrame
	end

	local existing = PlotBuilderGui:FindFirstChild("PreviewControls")
	if existing and existing:IsA("Frame") then
		PreviewControlsFrame = existing
		return existing
	end

	local legacy = MainFrame:FindFirstChild("PreviewControls")
	if legacy and legacy:IsA("Frame") then
		legacy.Parent = PlotBuilderGui
		legacy.ZIndex = 100
		legacy.Visible = false
		PreviewControlsFrame = legacy
		return legacy
	end

	local container = Instance.new("Frame")
	container.Name = "PreviewControls"
	container.AnchorPoint = Vector2.new(1, 1)
	container.Position = UDim2.new(1, -24, 1, -24)
	container.Size = UDim2.fromOffset(260, 64)
	container.BackgroundTransparency = 1
	container.BorderSizePixel = 0
	container.ZIndex = 100
	container.Visible = false
	container.Parent = PlotBuilderGui

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0, 12)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = container

	PreviewControlsFrame = container
	return container
end

local function ensureCancelPreviewButton(): TextButton
	local frame = ensurePreviewControlsFrame()
	local existing = frame:FindFirstChild("CancelPreviewButton")
	if existing and existing:IsA("TextButton") then
		CancelPreviewButton = existing
		return existing
	end

	local clonedButton = CancelButtonTemplate:Clone()
	clonedButton.Name = "CancelPreviewButton"
	clonedButton.LayoutOrder = 100
	clonedButton.ZIndex = frame.ZIndex + 1
	clonedButton.Parent = frame

	local keyHint = clonedButton:FindFirstChild("KeyHint")
	if keyHint and keyHint:IsA("TextLabel") then
		keyHint.ZIndex = clonedButton.ZIndex + 1
	end

	CancelPreviewButton = clonedButton
	return clonedButton
end

local function handlePreviewCancelled()
	clearActiveSelection()
	updateCancelButtonState()
end

local function bindCancelPreviewButton()
	local button = ensureCancelPreviewButton()
	if button:GetAttribute("CancelHandlerBound") ~= true then
		button:SetAttribute("CancelHandlerBound", true)
		button.Activated:Connect(function()
			local previewActive = boolValueTrue(ObjectPreviewEnabledValue) and boolValueTrue(PlotBuilderEnabledValue)
			if previewActive then
				handlePreviewCancelled()
				PlotBuilder.RemovePreview()
				return
			end
			if ExternalCancelHandler then
				ExternalCancelHandler()
			end
		end)
	end

	updateCancelButtonState()

	if CancelPreviewAction and CancelPreviewAction:IsA("InputAction") then
		local binding = (CancelPreviewAction :: any).InputBinding
		if binding then
			(binding :: any).UIButton = button
		end

		local keyHint = button:FindFirstChild("KeyHint")
		if keyHint and keyHint:IsA("TextLabel") then
			local resolvedHint = keyHint.Text ~= "" and keyHint.Text or "Esc"
			local attributeCandidates = { "KeyboardHint", "KeyHint", "DisplayLabel" }
			for _, attributeName in ipairs(attributeCandidates) do
				local hintValue = CancelPreviewAction:GetAttribute(attributeName)
				if typeof(hintValue) == "string" and hintValue ~= "" then
					resolvedHint = hintValue
					break
				end
			end
			keyHint.Text = resolvedHint
		end

		if not CancelActionPressedConnection then
			CancelActionPressedConnection = CancelPreviewAction.Pressed:Connect(function()
				handlePreviewCancelled()
			end)
		end
	end

	if not CancelRKeyConnection then
		CancelRKeyConnection = UserInputService.InputBegan:Connect(function(input, gameProcessed)
			if gameProcessed then
				return
			end
			if input.KeyCode ~= Enum.KeyCode.R then
				return
			end
			if UserInputService:GetFocusedTextBox() then
				return
			end
			if not (boolValueTrue(ObjectPreviewEnabledValue) and boolValueTrue(PlotBuilderEnabledValue)) then
				return
			end
			handlePreviewCancelled()
			PlotBuilder.RemovePreview()
		end)
	end
end

local function createItemButton(entry: ItemEntry, layoutOrder: number, categoryName: string?): GuiButton
	local button = ItemButtonTemplate:Clone()
	configureItemButton(button, entry, layoutOrder)

	button.Activated:Connect(function()
		selectItemButton(button, entry)
	end)

	attachItemTooltip(button, entry, categoryName)

	return button
end

local function matchesFilter(entry: ItemEntry, normalizedFilter: string?): boolean
	if normalizedFilter == nil or normalizedFilter == "" or normalizedFilter == "all" then
		return true
	end

	for _, segment in ipairs(entry.Path) do
		if normalizedEquals(segment, normalizedFilter) then
			return true
		end
	end

	local spec = entry.Spec
	if normalizedEquals(spec.PlacementType, normalizedFilter) then
		return true
	end

	if normalizedEquals(spec.StationType, normalizedFilter) then
		return true
	end

	local tags = spec.Tags
	if typeof(tags) == "table" then
		for _, tag in ipairs(tags) do
			if normalizedEquals(tag, normalizedFilter) then
				return true
			end
		end
	end

	return false
end

local function matchesSearch(entry: ItemEntry, normalizedQuery: string): boolean
	if normalizedQuery == "" then
		return true
	end

	local spec = entry.Spec
	local displayName = spec.Name
	if typeof(displayName) == "string" and string.find(string.lower(displayName), normalizedQuery, 1, true) then
		return true
	end

	if string.find(string.lower(entry.Id), normalizedQuery, 1, true) then
		return true
	end

	local tags = spec.Tags
	if typeof(tags) == "table" then
		for _, tag in ipairs(tags) do
			if typeof(tag) == "string" and string.find(string.lower(tag), normalizedQuery, 1, true) then
				return true
			end
		end
	end

	for _, segment in ipairs(entry.Path) do
		if string.find(string.lower(segment), normalizedQuery, 1, true) then
			return true
		end
	end

	return false
end

populateCategoryItems = function(categoryName: string, normalizedFilter: string?)
	ensureItemLayout()

	local entries = ItemFinder.GetCategoryEntries(categoryName)
	local filtered = table.create(#entries)

	for _, entry in ipairs(entries) do
		if matchesFilter(entry, normalizedFilter) and matchesSearch(entry, SearchQuery) then
			filtered[#filtered + 1] = entry
		end
	end

	clearItemButtons()

	if #filtered == 0 then
		ensureEmptyStateLabel("<i>No items available yet.</i>")
		return
	end

	hideEmptyStateLabel()

	for index, entry in ipairs(filtered) do
		local button = createItemButton(entry, index, categoryName)
		button.Parent = ScrollingFrame
	end

	ScrollingFrame.CanvasPosition = Vector2.new(0, 0)
end

local function getSearchDisplayText(): string
	return SearchQueryRaw ~= "" and SearchQueryRaw or SearchQuery
end

local function formatSearchTitle(resultCount: number): string
	local display = getSearchDisplayText()
	if display ~= "" then
		local escapedDisplay = display:gsub("%%", "%%%%")
		return string.format("Results for '%s' (%d)", escapedDisplay, resultCount)
	end

	return string.format("Search Results (%d)", resultCount)
end

local function populateSearchResults(normalizedFilter: string?)
	ensureItemLayout()
	clearItemButtons()

	if CachedSearchKey ~= SearchQuery then
		if SearchQuery == "" then
			CachedSearchResults = {}
			CachedSearchKey = nil
		else
			CachedSearchResults = ItemFinder.SearchCatalog(SearchQuery)
			CachedSearchKey = SearchQuery
		end
	end

	local candidates = CachedSearchResults
	local filtered = table.create(#candidates)
	local effectiveFilter = (SearchQuery == "" and normalizedFilter) or nil
	for _, entry in ipairs(candidates) do
		if matchesFilter(entry, effectiveFilter) then
			filtered[#filtered + 1] = entry
		end
	end

	TitleLabel.Text = formatSearchTitle(#filtered)

	if #filtered == 0 then
		local safeQuery = getSearchDisplayText()
		if safeQuery ~= "" then
			local escaped = escapeRichText(safeQuery)
			ensureEmptyStateLabel(string.format("<i>No matches for '%s'.</i>", escaped))
		else
			ensureEmptyStateLabel("<i>No matches found.</i>")
		end
		return
	end

	hideEmptyStateLabel()

	for index, entry in ipairs(filtered) do
		local button = createItemButton(entry, index, entry.Category)
		button:SetAttribute("Category", entry.Category)
		button.Parent = ScrollingFrame
	end

	ScrollingFrame.CanvasPosition = Vector2.new(0, 0)
end

local function getSlotKey(normalizedKey: string?): string
	return normalizedKey or "__all"
end

local function resolveCategoryAlias(name: string): string?
	if CategoryInfos[name] then
		return name
	end

	if #name > 9 and string.sub(name, -9) == "Selection" then
		local trimmed = string.sub(name, 1, #name - 9)
		if CategoryInfos[trimmed] then
			return trimmed
		end
	end

	return nil
end

local function resolveActionButton(action: Instance): GuiButton?
	local binding = (action :: any).InputBinding
	if not binding then
		return nil
	end

	local candidate = (binding :: any).UIButton
	if typeof(candidate) ~= "Instance" then
		return nil
	end

	if candidate:IsA("GuiButton") then
		return candidate
	end

	return nil
end

local function ensureFilterInfo(categoryName: string, rawKey: string, normalizedKey: string?): FilterInfo
	local info = CategoryInfos[categoryName]
	if not info then
		error(("PlotBuilderUI missing category info for %s"):format(categoryName))
	end

	local slotKey = getSlotKey(normalizedKey)
	local filterInfo: FilterInfo? = info.Filters[slotKey]
	if not filterInfo then
		local newFilterInfo: FilterInfo = {
			Key = normalizedKey,
			RawKey = rawKey,
			Button = nil,
			Action = nil,
		}
		info.Filters[slotKey] = newFilterInfo
		table.insert(info.FilterOrder, newFilterInfo)
		filterInfo = newFilterInfo
	elseif rawKey ~= "" then
		filterInfo.RawKey = rawKey
	end

	return filterInfo :: FilterInfo
end

local function registerFilterAction(categoryName: string, action: Instance)
	local attributeValue = action:GetAttribute("FilterKey")
	local rawKey: string? = nil
	if typeof(attributeValue) == "string" then
		rawKey = attributeValue
	end
	if not rawKey or rawKey == "" then
		rawKey = action.Name
	end

	local normalized = normalizeFilterKey(rawKey)
	if normalized == "all" then
		normalized = nil
	end

	local filterInfo = ensureFilterInfo(categoryName, rawKey or "", normalized)
	filterInfo.Action = action

	local button = resolveActionButton(action)
	if button then
		filterInfo.Button = button
		button:SetAttribute("Selected", false)
	end

	local eventLabel = rawKey or "All"
	connectDebounced(action, "Filter:" .. categoryName .. ":" .. eventLabel, function()
		handleFilterInput(categoryName, normalized)
	end)
end

local function updateFilterHighlight(info: CategoryInfo, normalizedKey: string?)
	local activeSlot = getSlotKey(normalizedKey)

	for slotKey, filterInfo in info.Filters do
		local button = filterInfo.Button
		if button then
			button:SetAttribute("Selected", slotKey == activeSlot)
		end
	end
end

local function getButtonDisplayText(button: GuiButton): string?
	if button:IsA("TextButton") then
		local text = button.Text
		if text ~= "" then
			return text
		end
	end

	local textLabel = button:FindFirstChildWhichIsA("TextLabel")
	if textLabel then
		local labelText = textLabel.Text
		if labelText ~= "" then
			return labelText
		end
	end

	return nil
end

local function updateTitle(categoryName: string, normalizedFilter: string?)
	local info = CategoryInfos[categoryName]
	if not info then
		TitleLabel.Text = categoryName
		return
	end

	local titleText = categoryName
	local filterInfo = info.Filters[getSlotKey(normalizedFilter)]
	if filterInfo then
		local displayText: string? = nil
		local button = filterInfo.Button
		if button then
			displayText = getButtonDisplayText(button)
		end
		if (not displayText or displayText == "") and filterInfo.RawKey ~= "" then
			displayText = filterInfo.RawKey
		end
		if displayText and displayText ~= "" then
			titleText = displayText
		end
	end

	TitleLabel.Text = titleText
end

local function determineDefaultFilterKey(info: CategoryInfo): string?
	if #info.FilterOrder == 0 then
		return nil
	end

	for _, filterInfo in ipairs(info.FilterOrder) do
		if filterInfo.Key == nil then
			return nil
		end
	end

	local first = info.FilterOrder[1]
	return first and first.Key or nil
end

local function applyFilter(categoryName: string, normalizedKey: string?)
	local info = CategoryInfos[categoryName]
	if not info then
		return
	end

	info.ActiveFilterKey = normalizedKey
	updateFilterHighlight(info, normalizedKey)
	refreshItems()
end

local function setCurrentCategory(categoryName: string): CategoryInfo?
	local info = CategoryInfos[categoryName]
	if not info then
		warn(("PlotBuilderUI missing category info for %s"):format(categoryName))
		return nil
	end

	if CurrentCategory == categoryName then
		if info.Label then
			info.Label.Visible = true
		end
		if info.Panel then
			info.Panel.Visible = true
			CurrentPanel = info.Panel
		end
		return info
	end

	if CurrentCategory then
		local previousInfo = CategoryInfos[CurrentCategory]
		if previousInfo then
			if previousInfo.Button then
				previousInfo.Button:SetAttribute("Selected", false)
				refreshCategoryButtonVisual(previousInfo.Button)
			end
			if previousInfo.Panel then
				previousInfo.Panel.Visible = false
			end
			if previousInfo.Label then
				previousInfo.Label.Visible = false
			end
		end
	end

	CurrentCategory = categoryName

	if info.Button then
		info.Button:SetAttribute("Selected", true)
		refreshCategoryButtonVisual(info.Button)
	end

	if info.Label then
		info.Label.Visible = true
	end

	if CurrentPanel and CurrentPanel ~= info.Panel then
		CurrentPanel.Visible = false
	end

	CurrentPanel = info.Panel
	if CurrentPanel then
		CurrentPanel.Visible = true
	end

	return info
end

selectCategory = function(categoryName: string)
	local info = setCurrentCategory(categoryName)
	if not info then
		return
	end

	local defaultFilter = determineDefaultFilterKey(info)
	applyFilter(categoryName, defaultFilter)
end

handleFilterInput = function(categoryName: string, normalizedKey: string?)
	local info = setCurrentCategory(categoryName)
	if not info then
		return
	end

	applyFilter(categoryName, normalizedKey)
end

refreshItems = function()
	local info = CurrentCategory and CategoryInfos[CurrentCategory] or nil
	local filterKey = info and info.ActiveFilterKey or nil

	if SearchQuery ~= "" then
		populateSearchResults(nil)
		return
	end

	if not CurrentCategory then
		clearItemButtons()
		TitleLabel.Text = "Catalog"
		ensureEmptyStateLabel("<i>Select a category to get started.</i>")
		return
	end

	updateTitle(CurrentCategory, filterKey)
	populateCategoryItems(CurrentCategory, filterKey)
end

local function registerCategory(categoryName: string)
	local categoryFrame = CategoriesFrame:FindFirstChild(categoryName)
	local button: GuiButton? = nil
	local label: TextLabel? = nil

	if categoryFrame then
		if categoryFrame:IsA("GuiButton") then
			button = categoryFrame
		else
			local buttonCandidate = categoryFrame:FindFirstChildWhichIsA("GuiButton")
			if buttonCandidate and buttonCandidate:IsA("GuiButton") then
				button = buttonCandidate
			end
			local labelCandidate = categoryFrame:FindFirstChildWhichIsA("TextLabel")
			if labelCandidate and labelCandidate:IsA("TextLabel") then
				label = labelCandidate
			end
		end
	end

	if label then
		label.Text = categoryName
		label.Visible = false
	end

	local panel: Frame? = nil
	local panelCandidate = LeftDockFrame:FindFirstChild(categoryName)
	if not panelCandidate then
		panelCandidate = LeftDockFrame:FindFirstChild(categoryName .. "Panel")
	end
	if panelCandidate and panelCandidate:IsA("Frame") then
		local framePanel = panelCandidate :: Frame
		framePanel.Visible = false
		panel = framePanel
	end

	local info: CategoryInfo = {
		Button = button,
		Label = label,
		Panel = panel,
		Filters = {} :: { [string]: FilterInfo },
		FilterOrder = {} :: { FilterInfo },
		ActiveFilterKey = nil,
	}

	CategoryInfos[categoryName] = info

	if button then
		button:SetAttribute("Selected", false)
		button:SetAttribute("PlotBuilderCategoryName", categoryName)
		button.Activated:Connect(function()
			selectCategory(categoryName)
		end)

		bindCategoryHoverEffect(button)
	end

	local actionInstance = CategorySelectionFolder and CategorySelectionFolder:FindFirstChild(categoryName)
	connectDebounced(actionInstance, "Category:" .. categoryName, function()
		selectCategory(categoryName)
	end)
end

local function resolveActionCategory(action: Instance): string?
	local attributeCategory = action:GetAttribute("Category")
	if typeof(attributeCategory) == "string" then
		local mapped = resolveCategoryAlias(attributeCategory)
		if mapped then
			return mapped
		end
	end

	local ancestor = action.Parent
	while ancestor and ancestor ~= PanelsInputContexts do
		local mapped = resolveCategoryAlias(ancestor.Name)
		if mapped then
			return mapped
		end
		ancestor = ancestor.Parent
	end

	if ancestor == PanelsInputContexts then
		local mapped = resolveCategoryAlias(action.Name)
		if mapped then
			return mapped
		end
	end

	return nil
end

local function bindPanelInputActions()
	if not PanelsInputContexts then
		return
	end

	for _, descendant in ipairs(PanelsInputContexts:GetDescendants()) do
		if descendant:IsA("InputAction") then
			local categoryName = resolveActionCategory(descendant)
			if categoryName then
				registerFilterAction(categoryName, descendant)
			end
		end
	end

	for categoryName in pairs(CategoryInfos) do
		ensureFilterInfo(categoryName, "", nil)
	end
end

local function bindSearchBox()
	if not SearchFrame then
		return
	end

	local searchBox = SearchFrame:FindFirstChildWhichIsA("TextBox", true)
	if not searchBox then
		return
	end

	local clearButton = SearchFrame:FindFirstChild("ClearButton", true)

	local function updateSearch()
		local rawTrimmed = trim(searchBox.Text)
		local normalized = normalizeSearch(searchBox.Text)
		if normalized == SearchQuery and rawTrimmed == SearchQueryRaw then
			return
		end

		SearchQuery = normalized
		SearchQueryRaw = rawTrimmed
		CachedSearchKey = nil
		CachedSearchResults = {}
		refreshItems()
	end

	searchBox:GetPropertyChangedSignal("Text"):Connect(updateSearch)
	searchBox.FocusLost:Connect(function()
		updateSearch()
	end)

	if clearButton and clearButton:IsA("GuiButton") then
		clearButton.Activated:Connect(function()
			if searchBox.Text ~= "" then
				searchBox.Text = ""
			elseif SearchQuery ~= "" or SearchQueryRaw ~= "" then
				SearchQuery = ""
				SearchQueryRaw = ""
				CachedSearchKey = nil
				CachedSearchResults = {}
				refreshItems()
			end
		end)
	end
end

local function bindExitButton(button: GuiButton)
	if button:GetAttribute(EXIT_BUTTON_BOUND_ATTRIBUTE) == true then
		return
	end
	button:SetAttribute(EXIT_BUTTON_BOUND_ATTRIBUTE, true)
	button.Activated:Connect(function()
		PlotBuilder.Hide()
	end)
end

local function bindExitButtonsInFolder(folder: Instance)
	for _, descendant in ipairs(folder:GetDescendants()) do
		if descendant:IsA("GuiButton") then
			bindExitButton(descendant)
		end
	end
	folder.DescendantAdded:Connect(function(descendant)
		if descendant:IsA("GuiButton") then
			bindExitButton(descendant)
		end
	end)
end

local function bindExitControls()
	if ExitAction then
		if ExitAction:IsA("InputAction") then
			connectDebounced(ExitAction, "Exit", function()
				PlotBuilder.Hide()
			end)
		elseif ExitAction:IsA("GuiButton") then
			bindExitButton(ExitAction)
		end
	end

	if ExitButtonContextFolder then
		bindExitButtonsInFolder(ExitButtonContextFolder)
	end

	local headerClose = Header and Header:FindFirstChild("CloseButton")
	if headerClose and headerClose:IsA("GuiButton") then
		bindExitButton(headerClose)
	end
end

local function initializeVisibilityObservers()
	if PlotBuilderEnabledValue then
		PlotBuilderEnabledValue.Changed:Connect(function()
			syncVisibility()
			updateCancelButtonState()
			if not boolValueTrue(PlotBuilderEnabledValue) then
				clearActiveSelection()
			end
		end)
	end
	if ObjectPreviewEnabledValue then
		ObjectPreviewEnabledValue.Changed:Connect(function()
			syncVisibility()
			updateCancelButtonState()
		end)
	end
	if PlotExpansionEnabledValue then
		PlotExpansionEnabledValue.Changed:Connect(syncVisibility)
	end
	if ObjectSelectorEnabledValue then
		ObjectSelectorEnabledValue.Changed:Connect(syncVisibility)
	end
end

local function registerCategories()
	for _, categoryName in ipairs(Categories) do
		registerCategory(categoryName)
	end
end

local function selectInitialCategory()
	local candidate: string? = nil

	for _, categoryName in ipairs(Categories) do
		if CategoryInfos[categoryName] then
			if not candidate then
				candidate = categoryName
			end
			local entries = ItemFinder.GetCategoryEntries(categoryName)
			if #entries > 0 then
				candidate = categoryName
				break
			end
		end
	end

	if candidate then
		selectCategory(candidate)
	end
end

function PlotBuilderUI:Init()
	ensureItemLayout()
	registerCategories()
	bindPanelInputActions()
	bindSearchBox()
	bindExitControls()
	initializeVisibilityObservers()
	bindCancelPreviewButton()
	bindFloorLevelActions()
	if ActiveLevelChangedConnection then
		ActiveLevelChangedConnection:Disconnect()
	end
	ActiveLevelChangedConnection = PlotStateStore.OnActiveLevelChanged(function()
		refreshLevelControls()
	end)
	refreshLevelControls()
	selectInitialCategory()
	syncVisibility()
	updateCancelButtonState()
end

function PlotBuilderUI.Show()
	syncVisibility()
end

function PlotBuilderUI.Hide()
	MainFrame.Visible = false
end

function PlotBuilderUI.AcquireCancelButton(sourceId: string, handler: (() -> ())?)
	if typeof(sourceId) ~= "string" or sourceId == "" then
		error("PlotBuilderUI.AcquireCancelButton requires a non-empty source identifier")
	end
	if handler ~= nil and typeof(handler) ~= "function" then
		error("PlotBuilderUI.AcquireCancelButton handler must be a function or nil")
	end
	if ExternalCancelSource and ExternalCancelSource ~= sourceId then
		warn(
			string.format(
				"PlotBuilderUI cancel button already claimed by '%s'; overriding with '%s'",
				ExternalCancelSource,
				sourceId
			)
		)
	end
	ExternalCancelSource = sourceId
	ExternalCancelHandler = handler
	updateCancelButtonState()
end

function PlotBuilderUI.ReleaseCancelButton(sourceId: string)
	if typeof(sourceId) ~= "string" or sourceId == "" then
		return
	end
	if ExternalCancelSource ~= sourceId then
		return
	end
	ExternalCancelSource = nil
	ExternalCancelHandler = nil
	updateCancelButtonState()
end

return PlotBuilderUI
