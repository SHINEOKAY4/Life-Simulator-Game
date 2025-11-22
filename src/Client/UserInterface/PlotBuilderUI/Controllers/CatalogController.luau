--!strict

local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")

local PlotBuilder = require(script.Parent.Parent.Parent.Parent.Modules.PlotBuilder)
local ItemFinder = require(game:GetService("ReplicatedStorage").Shared.Utilities.ItemFinder)
local Tooltip = require(script.Parent.Parent.Parent:WaitForChild("Tooltip"))
local ProgressionController = require(script.Parent.Parent.Parent.Parent.Modules.ProgressionController)

local PLACEHOLDER_THUMBNAIL = "rbxasset://textures/ui/GuiImagePlaceholder.png"
local THUMBNAIL_TEMPLATE = "rbxthumb://type=Asset&id=%d&w=420&h=420"
local CATEGORY_HOVER_OFFSET = Vector2.new(12, 8)
local CATEGORY_HOVER_TWEEN = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local LOCKED_IMAGE_TINT = Color3.fromRGB(188, 192, 206)
local UNLOCKED_IMAGE_TINT = Color3.new(1, 1, 1)

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

type ItemSpec = { [string]: any }
type CatalogItemEntry = { Id: string, Spec: ItemSpec, Path: { string } }
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

type ButtonMetrics = {
	BaseSize: UDim2,
	BasePosition: UDim2,
	HoverSize: UDim2,
	HoverPosition: UDim2,
	Hovered: boolean,
	Initialized: boolean,
}

type CatalogConfig = {
	CategoriesFrame: Frame,
	LeftDockFrame: Frame,
	RightDockFrame: Frame,
	ScrollingFrame: ScrollingFrame,
	TitleLabel: TextLabel,
	CategorySelectionFolder: Instance?,
	PanelsInputContexts: Instance?,
	ItemButtonTemplate: ImageButton,
	Categories: { string },
	connectDebounced: (action: Instance?, name: string, callback: () -> ()) -> (),
}

type SelectionState = {
	ActiveButton: GuiButton?,
}

type SearchCacheState = {
	Key: string?,
}

local CatalogController = {}
CatalogController.__index = CatalogController

function CatalogController.new(config: CatalogConfig)
	local self = setmetatable({}, CatalogController)
	self._categoriesFrame = config.CategoriesFrame
	self._leftDockFrame = config.LeftDockFrame
	self._rightDockFrame = config.RightDockFrame
	self._scrollingFrame = config.ScrollingFrame
	self._titleLabel = config.TitleLabel
	self._categorySelectionFolder = config.CategorySelectionFolder
	self._panelsInputContexts = config.PanelsInputContexts
	self._itemButtonTemplate = config.ItemButtonTemplate
	self._categories = config.Categories
	self._connectDebounced = config.connectDebounced
	self._categoryInfos = {} :: { [string]: CategoryInfo }
	self._categoryButtonMetrics = {} :: { [GuiButton]: ButtonMetrics }
	self._categoryButtonTweens = {} :: { [GuiButton]: Tween }
	self._selectionState = { ActiveButton = nil :: GuiButton? } :: SelectionState
	self._searchQuery = ""
	self._searchQueryRaw = ""
	self._cachedSearchResults = {} :: { SearchResultEntry }
	self._searchCache = { Key = nil :: string? } :: SearchCacheState
	self._emptyStateLabel = nil :: TextLabel?
	self._currentCategory = nil :: string?
	self._currentPanel = nil :: Frame?
	self._itemLayout = self._scrollingFrame:FindFirstChildWhichIsA("UIGridLayout") :: UIGridLayout?
	return self
end

local function trim(text: string): string
	local trimmed = text:gsub("^%s+", "")
	return trimmed:gsub("%s+$", "")
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

function CatalogController:_ensureItemLayout()
	if self._itemLayout then
		return
	end

	local layout = Instance.new("UIGridLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.CellPadding = UDim2.fromOffset(8, 8)
	layout.CellSize = UDim2.fromOffset(180, 180)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	layout.VerticalAlignment = Enum.VerticalAlignment.Top
	layout.Parent = self._scrollingFrame
	self._itemLayout = layout
end

function CatalogController:_ensureEmptyStateLabel(message: string?)
	if not self._emptyStateLabel then
		local label = Instance.new("TextLabel")
		label.Name = "EmptyState"
		label.BackgroundTransparency = 1
		label.Size = UDim2.new(1, 0, 0, 48)
		label.Font = Enum.Font.Gotham
		label.TextSize = 18
		label.TextColor3 = Color3.fromRGB(210, 210, 210)
		label.TextWrapped = true
		label.RichText = true
		self._emptyStateLabel = label
	end

	local label = self._emptyStateLabel :: TextLabel
	label.Text = message or "<i>No items available yet.</i>"
	label.Visible = true
	label.Parent = self._scrollingFrame
end

function CatalogController:_hideEmptyStateLabel()
	if self._emptyStateLabel then
		self._emptyStateLabel.Visible = false
		self._emptyStateLabel.Parent = nil
	end
end

function CatalogController:_clearActiveSelection()
	local selectionState: SelectionState = self._selectionState
	local activeButton = selectionState.ActiveButton
	if activeButton then
		activeButton:SetAttribute("Selected", false)
		selectionState.ActiveButton = nil
	end
end

function CatalogController:ClearActiveSelection()
	self:_clearActiveSelection()
end

function CatalogController:_clearItemButtons()
	self:_clearActiveSelection()
	for _, child in ipairs(self._scrollingFrame:GetChildren()) do
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

local function resolveItemDescription(entry: CatalogItemEntry, categoryName: string?): string
	local spec = entry.Spec
	local description = spec.Description
	local finalDescription = description
	if typeof(finalDescription) ~= "string" or finalDescription == "" then
		local categoryPath = formatCategoryPath(categoryName, entry.Path)
		if categoryPath then
			finalDescription = string.format("Available under %s.", categoryPath)
		else
			local tagsLine = formatTags(spec)
			if tagsLine then
				finalDescription = tagsLine
			else
				finalDescription = "Preview this item to see how it reshapes your plot."
			end
		end
	end
	return finalDescription
end

local function formatNeedLabel(needName: string): string
	if needName == "" then
		return "Need"
	end
	return needName
end

local function getNeedColor(needName: string): string
	if needName == "Hunger" then
		return "#e67e22"
	end
	if needName == "Energy" then
		return "#f1c40f"
	end
	if needName == "Hygiene" then
		return "#3498db"
	end
	if needName == "Social" then
		return "#e74c3c"
	end
	if needName == "Fun" then
		return "#9b59b6"
	end
	if needName == "Bladder" then
		return "#95a5a6"
	end
	return "#7f8c8d"
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

function CatalogController:_collectDetailSegments(entry: CatalogItemEntry)
	local spec = entry.Spec
	local segments = {}
	local cost = spec.Cost
	if typeof(cost) == "number" then
		table.insert(segments, {
			Label = "Cost",
			Value = string.format("$%d", math.floor(cost + 0.5)),
			Color = Color3.fromHex("#2ecc71"),
			Icon = "💰",
		})
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
			table.insert(segments, {
				Label = "Duration",
				Value = string.format("%ds", math.floor(duration + 0.5)),
				Color = Color3.fromHex("#3498db"),
				Icon = DURATION_EMOJI,
			})
		end

		local effectsList = stationEffects.Effects
		local addedEffectLine = false
		if typeof(effectsList) == "table" then
			for _, effect in ipairs(effectsList) do
				local needName = effect.Need
				if typeof(needName) == "string" and needName ~= "" then
					local label = formatNeedLabel(needName)
					local color = Color3.fromHex(getNeedColor(needName))
					local valueLabel = formatEffectValue(effect.Rate, effect.Amount)
					if valueLabel then
						table.insert(segments, {
							Label = label,
							Value = valueLabel,
							Color = color,
							Icon = NEED_EMOJI[needName] or "✨",
						})
						addedEffectLine = true
					end
				end
			end
		end

		if not addedEffectLine and restDefaults and typeof(restDefaults.RatePerHour) == "number" then
			local restValue = formatEffectValue(restDefaults.RatePerHour, nil)
			if restValue then
				table.insert(segments, {
					Label = "Energy",
					Value = restValue,
					Color = Color3.fromHex(getNeedColor("Energy")),
					Icon = NEED_EMOJI["Energy"],
				})
			end
		end
	end

	local energyUse = spec.EnergyConsumptionPerHour
	if typeof(energyUse) == "number" and energyUse > 0 then
		table.insert(segments, {
			Label = "Power",
			Value = string.format("-%d/hr", math.floor(energyUse + 0.5)),
			Color = Color3.fromHex("#f39c12"),
			Icon = POWER_EMOJI,
		})
	end

	local storage = spec.StorageConfig
	if typeof(storage) == "table" then
		local capacity = storage.Capacity
		if typeof(capacity) == "number" and capacity > 0 then
			table.insert(segments, {
				Label = "Storage",
				Value = string.format("%d slots", math.floor(capacity + 0.5)),
				Color = Color3.fromHex("#95a5a6"),
				Icon = STORAGE_EMOJI,
			})
		end
	end
	return segments
end

function CatalogController:_attachItemTooltip(button: GuiButton, entry: CatalogItemEntry, categoryName: string?)
	local spec = entry.Spec
	local itemName = typeof(spec.Name) == "string" and spec.Name or entry.Id
	local description = resolveItemDescription(entry, categoryName)
	local stats = self:_collectDetailSegments(entry)
	local thumbnail = buildThumbnail(spec)

	local tooltip = Tooltip.new(button, {
		title = itemName,
		description = description,
		thumbnail = thumbnail,
		delay = 0.05,
		maxWidth = 280,
	})

	local function updateContent()
		local locked = button:GetAttribute("Locked") == true
		if locked then
			local requiredLevelAttr = button:GetAttribute("RequiredLevel")
			local requiredLevel = if typeof(requiredLevelAttr) == "number" then requiredLevelAttr else 1
			tooltip:SetItemContent({
				Title = "Locked Item",
				Description = string.format("Reach level %d to unlock %s.", requiredLevel, itemName),
				Thumbnail = thumbnail,
				Stats = {}, -- Hide stats when locked
			})
		else
			tooltip:SetItemContent({
				Title = itemName,
				Description = description,
				Thumbnail = thumbnail,
				Stats = stats,
			})
		end
	end

	updateContent()
	button:GetAttributeChangedSignal("Locked"):Connect(updateContent)

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

local function getCurrentLevel(): number
	local player = Players.LocalPlayer
	local attr = player:GetAttribute("PlayerLevel")
	if typeof(attr) == "number" then
		return attr
	end
	return ProgressionController.GetLevel()
end

local function resolveRequiredLevel(spec: ItemSpec): number
	local required = spec.RequiredLevel
	if typeof(required) ~= "number" then
		return 1
	end
	if required < 1 then
		return 1
	end
	return math.floor(required + 0.5)
end

local function isEntryLocked(entry: CatalogItemEntry): (boolean, number)
	local requiredLevel = resolveRequiredLevel(entry.Spec)
	if requiredLevel <= 1 then
		return false, requiredLevel
	end
	local level = getCurrentLevel()
	return level < requiredLevel, requiredLevel
end

local function formatSearchTitle(searchQuery: string, searchQueryRaw: string, resultCount: number): string
	local display = searchQueryRaw ~= "" and searchQueryRaw or searchQuery
	if display ~= "" then
		local escapedDisplay = display:gsub("%%", "%%%%")
		return string.format("Results for '%s' (%d)", escapedDisplay, resultCount)
	end
	return string.format("Search Results (%d)", resultCount)
end

function CatalogController:_applyLockVisual(button: ImageButton, locked: boolean, requiredLevel: number)
	local lockIcon = button:FindFirstChild("Lock")
	if lockIcon and lockIcon:IsA("GuiObject") then
		lockIcon.Visible = locked
	end

	local infoFrame = button:FindFirstChild("Info")
	if infoFrame and infoFrame:IsA("Frame") then
		local costLabel = infoFrame:FindFirstChild("ItemCost")
		if costLabel and costLabel:IsA("GuiObject") then
			costLabel.Visible = not locked
		end
	end

	button.AutoButtonColor = not locked
	button:SetAttribute("Locked", locked)
	button:SetAttribute("RequiredLevel", requiredLevel)
	button.ImageColor3 = locked and LOCKED_IMAGE_TINT or UNLOCKED_IMAGE_TINT
end

function CatalogController:_configureItemButton(button: ImageButton, entry: CatalogItemEntry, layoutOrder: number)
	button.Name = entry.Id
	button.LayoutOrder = layoutOrder
	button.Visible = true
	button.Image = buildThumbnail(entry.Spec)
	button:SetAttribute("Selected", false)

	local fallbackInstance = button:FindFirstChild("FallbackLabel")
	local fallbackLabel = if fallbackInstance and fallbackInstance:IsA("TextLabel") then fallbackInstance else nil
	if button.Image == PLACEHOLDER_THUMBNAIL then
		if not fallbackLabel then
			local label = Instance.new("TextLabel")
			label.Name = "FallbackLabel"
			label.Size = UDim2.fromScale(0.8, 0.8)
			label.Position = UDim2.fromScale(0.1, 0.1)
			label.BackgroundTransparency = 1
			label.TextColor3 = Color3.new(1, 1, 1)
			label.TextStrokeTransparency = 0
			label.TextScaled = true
			label.Font = Enum.Font.GothamBold
			label.Parent = button
			fallbackLabel = label
		end
		if fallbackLabel then
			fallbackLabel.Text = entry.Spec.Name or entry.Id
			fallbackLabel.Visible = true
		end
		button.ImageTransparency = 0.8
	else
		if fallbackLabel then
			fallbackLabel.Visible = false
		end
		button.ImageTransparency = 0
	end

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

	local locked, requiredLevel = isEntryLocked(entry)
	self:_applyLockVisual(button, locked, requiredLevel)
end

function CatalogController:_selectItemButton(button: GuiButton, entry: CatalogItemEntry)
	local locked = isEntryLocked(entry)
	if locked then
		return
	end

	local selectionState: SelectionState = self._selectionState
	local activeButton = selectionState.ActiveButton
	if activeButton and activeButton ~= button then
		activeButton:SetAttribute("Selected", false)
	end

	selectionState.ActiveButton = button
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

function CatalogController:_createItemButton(
	entry: CatalogItemEntry,
	layoutOrder: number,
	categoryName: string?
): GuiButton
	local button = self._itemButtonTemplate:Clone()
	self:_configureItemButton(button, entry, layoutOrder)
	button.Activated:Connect(function()
		self:_selectItemButton(button, entry)
	end)
	self:_attachItemTooltip(button, entry, categoryName)
	return button
end

local function matchesFilter(entry: CatalogItemEntry, normalizedFilter: string?): boolean
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

local function matchesSearch(entry: CatalogItemEntry, normalizedQuery: string): boolean
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

local function getSlotKey(normalizedKey: string?): string
	return normalizedKey or "__all"
end

function CatalogController:_updateTitle(categoryName: string, normalizedFilter: string?)
	local info = self._categoryInfos[categoryName]
	if not info then
		self._titleLabel.Text = categoryName
		return
	end

	local titleText = categoryName
	local filterInfo = info.Filters[getSlotKey(normalizedFilter)]
	if filterInfo then
		local displayText: string? = nil
		local button = filterInfo.Button
		if button then
			if button:IsA("TextButton") and button.Text ~= "" then
				displayText = button.Text
			else
				local textLabel = button:FindFirstChildWhichIsA("TextLabel")
				if textLabel and textLabel.Text ~= "" then
					displayText = textLabel.Text
				end
			end
		end
		if (not displayText or displayText == "") and filterInfo.RawKey ~= "" then
			displayText = filterInfo.RawKey
		end
		if displayText and displayText ~= "" then
			titleText = displayText
		end
	end

	self._titleLabel.Text = titleText
end

function CatalogController:_ensureFilterInfo(categoryName: string, rawKey: string, normalizedKey: string?): FilterInfo
	local info = self._categoryInfos[categoryName]
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

function CatalogController:_resolveActionButton(action: Instance): GuiButton?
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

function CatalogController:_registerFilterAction(categoryName: string, action: Instance)
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

	local filterInfo = self:_ensureFilterInfo(categoryName, rawKey or "", normalized)
	filterInfo.Action = action

	local button = self:_resolveActionButton(action)
	if button then
		filterInfo.Button = button
		button:SetAttribute("Selected", false)
	end

	local eventLabel = rawKey or "All"
	self._connectDebounced(action, "Filter:" .. categoryName .. ":" .. eventLabel, function()
		self:HandleFilterInput(categoryName, normalized)
	end)
end

function CatalogController:_updateFilterHighlight(info: CategoryInfo, normalizedKey: string?)
	local activeSlot = getSlotKey(normalizedKey)
	for slotKey, filterInfo in info.Filters do
		local button = filterInfo.Button
		if button then
			button:SetAttribute("Selected", slotKey == activeSlot)
		end
	end
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

function CatalogController:_applyFilter(categoryName: string, normalizedKey: string?)
	local info = self._categoryInfos[categoryName]
	if not info then
		return
	end
	info.ActiveFilterKey = normalizedKey
	self:_updateFilterHighlight(info, normalizedKey)
	self:RefreshItems()
end

function CatalogController:_setCurrentCategory(categoryName: string): CategoryInfo?
	local info = self._categoryInfos[categoryName]
	if not info then
		warn(("PlotBuilderUI missing category info for %s"):format(categoryName))
		return nil
	end

	if self._currentCategory == categoryName then
		if info.Label then
			info.Label.Visible = true
		end
		if info.Panel then
			info.Panel.Visible = true
			self._currentPanel = info.Panel :: Frame?
		end
		return info
	end

	if self._currentCategory then
		local previousInfo = self._categoryInfos[self._currentCategory]
		if previousInfo then
			if previousInfo.Button then
				previousInfo.Button:SetAttribute("Selected", false)
				self:_refreshCategoryButtonVisual(previousInfo.Button)
			end
			if previousInfo.Panel then
				previousInfo.Panel.Visible = false
			end
			if previousInfo.Label then
				previousInfo.Label.Visible = false
			end
		end
	end

	self._currentCategory = categoryName
	if info.Button then
		info.Button:SetAttribute("Selected", true)
		self:_refreshCategoryButtonVisual(info.Button)
	end
	if info.Label then
		info.Label.Visible = true
	end
	if self._currentPanel and self._currentPanel ~= info.Panel then
		self._currentPanel.Visible = false
	end
	self._currentPanel = info.Panel :: Frame?
	if self._currentPanel then
		self._currentPanel.Visible = true
	end
	return info
end

function CatalogController:SelectCategory(categoryName: string)
	local info = self:_setCurrentCategory(categoryName)
	if not info then
		return
	end
	local defaultFilter = determineDefaultFilterKey(info)
	self:_applyFilter(categoryName, defaultFilter)
end

function CatalogController:HandleFilterInput(categoryName: string, normalizedKey: string?)
	local info = self:_setCurrentCategory(categoryName)
	if not info then
		return
	end
	self:_applyFilter(categoryName, normalizedKey)
end

function CatalogController:_animateCategoryButton(
	button: GuiButton,
	metrics: ButtonMetrics,
	targetState: string,
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
		local activeInstantTween = self._categoryButtonTweens[button]
		if activeInstantTween then
			activeInstantTween:Cancel()
			self._categoryButtonTweens[button] = nil
		end
		return
	end

	local activeTween = self._categoryButtonTweens[button]
	if activeTween then
		activeTween:Cancel()
	end
	if button.Size == targetSize and button.Position == targetPosition then
		self._categoryButtonTweens[button] = nil
		return
	end

	local tween = TweenService:Create(button, CATEGORY_HOVER_TWEEN, {
		Size = targetSize,
		Position = targetPosition,
	})
	self._categoryButtonTweens[button] = tween
	tween.Completed:Connect(function()
		if self._categoryButtonTweens[button] == tween then
			self._categoryButtonTweens[button] = nil
		end
	end)
	tween:Play()
end

function CatalogController:_refreshCategoryButtonVisual(button: GuiButton)
	local metrics = self._categoryButtonMetrics[button]
	if not metrics then
		return
	end
	local shouldHover = metrics.Hovered or button:GetAttribute("Selected") == true
	local targetState = if shouldHover then "hover" else "base"
	local useInstant = not metrics.Initialized
	self:_animateCategoryButton(button, metrics, targetState, useInstant)
	metrics.Initialized = true
end

function CatalogController:_bindCategoryHoverEffect(button: GuiButton)
	if self._categoryButtonMetrics[button] then
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
		Initialized = false,
	}

	self._categoryButtonMetrics[button] = metrics

	button.MouseEnter:Connect(function()
		local stored = self._categoryButtonMetrics[button]
		if not stored then
			return
		end
		stored.Hovered = true
		self:_refreshCategoryButtonVisual(button)
		local categoryNameAttr = button:GetAttribute("PlotBuilderCategoryName")
		if typeof(categoryNameAttr) == "string" then
			local info = self._categoryInfos[categoryNameAttr]
			if info and info.Label then
				info.Label.Visible = true
			end
		end
	end)

	button.MouseLeave:Connect(function()
		local stored = self._categoryButtonMetrics[button]
		if not stored then
			return
		end
		stored.Hovered = false
		self:_refreshCategoryButtonVisual(button)
		local categoryNameAttr = button:GetAttribute("PlotBuilderCategoryName")
		if typeof(categoryNameAttr) == "string" and self._currentCategory ~= categoryNameAttr then
			local info = self._categoryInfos[categoryNameAttr]
			if info and info.Label then
				info.Label.Visible = false
			end
		end
	end)

	button.AncestryChanged:Connect(function(_, parent)
		if parent ~= nil then
			return
		end
		local activeTween = self._categoryButtonTweens[button]
		if activeTween then
			activeTween:Cancel()
		end
		self._categoryButtonTweens[button] = nil
		self._categoryButtonMetrics[button] = nil
		local categoryNameAttr = button:GetAttribute("PlotBuilderCategoryName")
		if typeof(categoryNameAttr) == "string" and self._currentCategory ~= categoryNameAttr then
			local info = self._categoryInfos[categoryNameAttr]
			if info and info.Label then
				info.Label.Visible = false
			end
		end
	end)

	self:_refreshCategoryButtonVisual(button)
end

function CatalogController:_registerCategory(categoryName: string)
	local categoryFrame = self._categoriesFrame:FindFirstChild(categoryName)
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
	local panelCandidate = self._leftDockFrame:FindFirstChild(categoryName)
	if not panelCandidate then
		panelCandidate = self._leftDockFrame:FindFirstChild(categoryName .. "Panel")
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

	self._categoryInfos[categoryName] = info

	if button then
		button:SetAttribute("Selected", false)
		button:SetAttribute("PlotBuilderCategoryName", categoryName)
		button.Activated:Connect(function()
			self:SelectCategory(categoryName)
		end)
		self:_bindCategoryHoverEffect(button)
	end

	local actionInstance = self._categorySelectionFolder and self._categorySelectionFolder:FindFirstChild(categoryName)
	self._connectDebounced(actionInstance, "Category:" .. categoryName, function()
		self:SelectCategory(categoryName)
	end)
end

local function resolveCategoryAlias(categoryInfos: { [string]: CategoryInfo }, name: string): string?
	if categoryInfos[name] then
		return name
	end
	if #name > 9 and string.sub(name, -9) == "Selection" then
		local trimmed = string.sub(name, 1, #name - 9)
		if categoryInfos[trimmed] then
			return trimmed
		end
	end
	return nil
end

function CatalogController:_resolveActionCategory(action: Instance): string?
	local attributeCategory = action:GetAttribute("Category")
	if typeof(attributeCategory) == "string" then
		local mapped = resolveCategoryAlias(self._categoryInfos, attributeCategory)
		if mapped then
			return mapped
		end
	end

	local panelsContext = self._panelsInputContexts :: Instance?
	local ancestor = action.Parent
	while ancestor do
		if panelsContext and ancestor == panelsContext then
			break
		end
		local mapped = resolveCategoryAlias(self._categoryInfos, ancestor.Name)
		if mapped then
			return mapped
		end
		ancestor = ancestor.Parent
	end

	if panelsContext and ancestor == panelsContext then
		local mapped = resolveCategoryAlias(self._categoryInfos, action.Name)
		if mapped then
			return mapped
		end
	end

	return nil
end

function CatalogController:_bindPanelInputActions()
	if not self._panelsInputContexts then
		return
	end

	for _, descendant in ipairs(self._panelsInputContexts:GetDescendants()) do
		if descendant:IsA("InputAction") then
			local categoryName = self:_resolveActionCategory(descendant)
			if categoryName then
				self:_registerFilterAction(categoryName, descendant)
			end
		end
	end

	for categoryName in pairs(self._categoryInfos) do
		self:_ensureFilterInfo(categoryName, "", nil)
	end
end

function CatalogController:_populateCategoryItems(categoryName: string, normalizedFilter: string?)
	self:_ensureItemLayout()
	local entries = ItemFinder.GetCategoryEntries(categoryName)
	local filtered = table.create(#entries)
	for _, entry in ipairs(entries) do
		if matchesFilter(entry, normalizedFilter) and matchesSearch(entry, self._searchQuery) then
			filtered[#filtered + 1] = entry
		end
	end

	self:_clearItemButtons()
	if #filtered == 0 then
		self:_ensureEmptyStateLabel("<i>No items available yet.</i>")
		return
	end

	self:_hideEmptyStateLabel()
	for index, entry in ipairs(filtered) do
		local button = self:_createItemButton(entry, index, categoryName)
		button.Parent = self._scrollingFrame
	end
	self._scrollingFrame.CanvasPosition = Vector2.new(0, 0)
end

function CatalogController:_escapeRichText(text: string): string
	local escaped = text:gsub("&", "&amp;")
	escaped = escaped:gsub("<", "&lt;")
	return escaped:gsub(">", "&gt;")
end

function CatalogController:_populateSearchResults(normalizedFilter: string?)
	self:_ensureItemLayout()
	self:_clearItemButtons()

	local cacheState: SearchCacheState = self._searchCache
	if cacheState.Key ~= self._searchQuery then
		if self._searchQuery == "" then
			self._cachedSearchResults = {} :: { SearchResultEntry }
			cacheState.Key = nil
		else
			self._cachedSearchResults = ItemFinder.SearchCatalog(self._searchQuery)
			cacheState.Key = self._searchQuery
		end
	end

	local candidates: { SearchResultEntry } = self._cachedSearchResults
	local filtered: { SearchResultEntry } = table.create(#candidates)
	local effectiveFilter = (self._searchQuery == "" and normalizedFilter) or nil
	for _, entry in ipairs(candidates) do
		if matchesFilter(entry, effectiveFilter) then
			filtered[#filtered + 1] = entry
		end
	end

	self._titleLabel.Text = formatSearchTitle(self._searchQuery, self._searchQueryRaw, #filtered)
	if #filtered == 0 then
		local safeQuery = self._searchQueryRaw ~= "" and self._searchQueryRaw or self._searchQuery
		if safeQuery ~= "" then
			local escaped = self:_escapeRichText(safeQuery)
			self:_ensureEmptyStateLabel(string.format("<i>No matches for '%s'.</i>", escaped))
		else
			self:_ensureEmptyStateLabel("<i>No matches found.</i>")
		end
		return
	end

	self:_hideEmptyStateLabel()
	for index, entry in ipairs(filtered) do
		local button = self:_createItemButton(entry, index, entry.Category)
		button:SetAttribute("Category", entry.Category)
		button.Parent = self._scrollingFrame
	end
	self._scrollingFrame.CanvasPosition = Vector2.new(0, 0)
end

function CatalogController:RefreshItems()
	local info = self._currentCategory and self._categoryInfos[self._currentCategory] or nil
	local filterKey = info and info.ActiveFilterKey or nil
	if self._searchQuery ~= "" then
		self:_populateSearchResults(nil)
		return
	end
	if not self._currentCategory then
		self:_clearItemButtons()
		self._titleLabel.Text = "Catalog"
		self:_ensureEmptyStateLabel("<i>Select a category to get started.</i>")
		return
	end
	self:_updateTitle(self._currentCategory, filterKey)
	self:_populateCategoryItems(self._currentCategory, filterKey)
end

function CatalogController:_bindSearchBox()
	local header = self._rightDockFrame:FindFirstChild("Header")
	local searchFrame = header and header:FindFirstChild("SearchFrame")
	if not searchFrame then
		return
	end

	local searchBox = searchFrame:FindFirstChildWhichIsA("TextBox", true)
	if not searchBox then
		return
	end

	local clearButton = searchFrame:FindFirstChild("ClearButton", true)
	local function updateSearch()
		local rawTrimmed = trim(searchBox.Text)
		local normalized = normalizeSearch(searchBox.Text)
		if normalized == self._searchQuery and rawTrimmed == self._searchQueryRaw then
			return
		end
		self._searchQuery = normalized
		self._searchQueryRaw = rawTrimmed
		self._searchCache.Key = nil
		self._cachedSearchResults = {} :: { SearchResultEntry }
		self:RefreshItems()
	end

	searchBox:GetPropertyChangedSignal("Text"):Connect(updateSearch)
	searchBox.FocusLost:Connect(updateSearch)

	if clearButton and clearButton:IsA("GuiButton") then
		clearButton.Activated:Connect(function()
			if searchBox.Text ~= "" then
				searchBox.Text = ""
			elseif self._searchQuery ~= "" or self._searchQueryRaw ~= "" then
				self._searchQuery = ""
				self._searchQueryRaw = ""
				self._searchCache.Key = nil
				self._cachedSearchResults = {} :: { SearchResultEntry }
				self:RefreshItems()
			end
		end)
	end
end

function CatalogController:Init()
	for _, categoryName in ipairs(self._categories) do
		self:_registerCategory(categoryName)
	end
	self:_bindPanelInputActions()
	self:_bindSearchBox()
end

function CatalogController:SelectInitialCategory()
	local candidate: string? = nil
	for _, categoryName in ipairs(self._categories :: { string }) do
		if self._categoryInfos[categoryName] then
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
		self:SelectCategory(candidate)
	end
end

return CatalogController
