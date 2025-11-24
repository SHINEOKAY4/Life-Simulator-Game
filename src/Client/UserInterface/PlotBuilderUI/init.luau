--!strict
-- StarterPlayerScripts/Client/UserInterface/PlotBuilderUI.luau

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local UserInterfaceFolder = script.Parent
local ClientFolder = UserInterfaceFolder.Parent
local ModulesFolder = ClientFolder.Modules
local ClientStoresFolder = ClientFolder.ClientStores

local PlotBuilder = require(ModulesFolder.PlotBuilder)
local PlotExpansion = require(ModulesFolder.PlotExpansion)
local GoodSignal = require(ReplicatedStorage.Packages.GoodSignal)
local SurfacePaintController = require(ModulesFolder.SurfacePaintController)
local BuildPaletteUI = require(UserInterfaceFolder.BuildPaletteUI)
-- Removed ObjectSelector require (binding no longer triggered from menu; state value still observed)
local CutawayViewController = require(ModulesFolder.CutawayViewController)
local Debounce = require(ReplicatedStorage.Shared.Utilities.Debounce)
local PlotStateStore = require(ClientStoresFolder.PlotStateStore)
local MenuController = require(script.Controllers.MenuController)
local CatalogController = require(script.Controllers.CatalogController)
local PreviewController = require(script.Controllers.PreviewController)

local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")

local plotBuilderGuiInstance = PlayerGui:FindFirstChild("PlotBuilderUI") or PlayerGui:FindFirstChild("PlotBuilderGui")
assert(
	plotBuilderGuiInstance and plotBuilderGuiInstance:IsA("ScreenGui"),
	"PlotBuilderUI expected PlotBuilderUI or PlotBuilderGui ScreenGui"
)
local PlotBuilderGui = plotBuilderGuiInstance :: ScreenGui
local BuildPaletteGui = PlayerGui:FindFirstChild("BuildPaletteGui")
local BuildPaletteMainFrame = BuildPaletteGui and BuildPaletteGui:FindFirstChild("Main")
local BuildPaletteVisibilityConnection: RBXScriptConnection? = nil

local function resolveBuildPaletteMainFrame(): Frame?
	if BuildPaletteMainFrame and BuildPaletteMainFrame.Parent then
		return BuildPaletteMainFrame
	end
	if not BuildPaletteGui or not BuildPaletteGui.Parent then
		BuildPaletteGui = PlayerGui:FindFirstChild("BuildPaletteGui")
	end
	if BuildPaletteGui then
		BuildPaletteMainFrame = BuildPaletteGui:FindFirstChild("Main")
	end
	return BuildPaletteMainFrame
end

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
local MenuFrame = MainFrame:WaitForChild("Menu") :: Frame
local RightFrame = MainFrame:WaitForChild("Right") :: Frame
local LeftFrame = MainFrame:WaitForChild("Left") :: Frame
local UpFrame = LeftFrame:WaitForChild("UpFrame") :: Frame
local UpButton = UpFrame:WaitForChild("UpButton") :: GuiButton
local UpTextLabel = UpFrame:FindFirstChildWhichIsA("TextLabel")
local DownFrame = LeftFrame:WaitForChild("DownFrame") :: Frame
local DownButton = DownFrame:WaitForChild("DownButton") :: GuiButton
local DownTextLabel = DownFrame:FindFirstChildWhichIsA("TextLabel")
local Header = RightFrame:FindFirstChild("Header") :: Frame
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
local UPGRADE_CUTAWAY_SOURCE = "PlotBuilderUpgrade"
local CUTAWAY_PRIORITY = 20

local PlotBuilderUI = {}
local upgradeViewChangedSignal = GoodSignal.new()
PlotBuilderUI.UpgradeViewChanged = upgradeViewChangedSignal
local isUpgradeViewActive = false
local storageMenuActive = false
local menuController: any = nil
local catalogController: any = nil
local previewController: any = nil
local ActiveLevelChangedConnection: RBXScriptConnection? = nil
local EXIT_BUTTON_BOUND_ATTRIBUTE = "PlotBuilderExitBound"
local paletteHiddenDuringPreview = false

local function resolveGuiButton(container: Instance?): GuiButton?
	if not container then
		return nil
	end
	if container:IsA("GuiButton") then
		return container
	end
	return container:FindFirstChildWhichIsA("GuiButton")
end

local function findMenuButton(name: string, aliases: { string }?): GuiButton?
	local candidates = { name }
	if aliases then
		for _, alias in ipairs(aliases) do
			candidates[#candidates + 1] = alias
		end
	end
	for _, candidate in ipairs(candidates) do
		local button = resolveGuiButton(MenuFrame:FindFirstChild(candidate))
		if button then
			return button
		end
	end
	return nil
end

local MenuButtons = {
	Paint = findMenuButton("Paint"),
	Storage = findMenuButton("Storage"),
	Select = findMenuButton("Select", { "Expand", "ExpandButton" }),
	Upgrade = findMenuButton("Upgrade"),
	Back = findMenuButton("Back"),
}

local POPUP_HIDDEN_SCALE = 0.9
local POPUP_SHOW_TWEEN = TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local POPUP_HIDE_TWEEN = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local POPUP_SCALE_NAME = "UIPopupScale"

local framePopTweens: { [GuiObject]: Tween? } = {}
local framePopTargets: { [GuiObject]: boolean } = {}
local function ensureUIScale(target: GuiObject, scaleName: string): UIScale
	local existing = target:FindFirstChild(scaleName)
	if existing and existing:IsA("UIScale") then
		return existing
	end
	local scale = Instance.new("UIScale")
	scale.Name = scaleName
	scale.Scale = 1
	scale.Parent = target
	return scale
end

local function setPopupVisible(frame: GuiObject, shouldShow: boolean)
	if framePopTargets[frame] == shouldShow then
		if shouldShow and not frame.Visible then
			frame.Visible = true
		end
		return
	end
	framePopTargets[frame] = shouldShow

	local scale = ensureUIScale(frame, POPUP_SCALE_NAME)
	local activeTween = framePopTweens[frame]
	if activeTween then
		activeTween:Cancel()
		framePopTweens[frame] = nil
	end

	if shouldShow then
		frame.Visible = true
		scale.Scale = POPUP_HIDDEN_SCALE
		local tween = TweenService:Create(scale, POPUP_SHOW_TWEEN, {
			Scale = 1,
		})
		framePopTweens[frame] = tween
		tween.Completed:Connect(function()
			if framePopTweens[frame] == tween then
				framePopTweens[frame] = nil
			end
		end)
		tween:Play()
		return
	end

	if not frame.Visible then
		framePopTargets[frame] = false
		scale.Scale = 1
		return
	end

	local tween = TweenService:Create(scale, POPUP_HIDE_TWEEN, {
		Scale = POPUP_HIDDEN_SCALE,
	})
	framePopTweens[frame] = tween
	tween.Completed:Connect(function()
		if framePopTweens[frame] ~= tween then
			return
		end
		framePopTweens[frame] = nil
		if framePopTargets[frame] == false then
			frame.Visible = false
			scale.Scale = 1
		end
	end)
	tween:Play()
end

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

local function ensureCatalogController()
	if catalogController then
		return catalogController
	end

	local controller = CatalogController.new({
		CategoriesFrame = CategoriesFrame,
		LeftDockFrame = LeftDockFrame,
		RightDockFrame = RightDockFrame,
		ScrollingFrame = ScrollingFrame,
		TitleLabel = TitleLabel,
		CategorySelectionFolder = CategorySelectionFolder,
		PanelsInputContexts = PanelsInputContexts,
		ItemButtonTemplate = ItemButtonTemplate,
		Categories = Categories,
		connectDebounced = connectDebounced,
	})
	controller:Init()
	catalogController = controller
	return controller
end

local function bindFloorLevelActions()
	connectDebounced(FloorUpAction, "FloorLevelUp", function()
		changeActiveLevel(1)
	end)

	connectDebounced(FloorDownAction, "FloorLevelDown", function()
		changeActiveLevel(-1)
	end)
end

local function boolValueTrue(value: BoolValue?): boolean
	return value ~= nil and value.Value == true
end

local function isPreviewActive(): boolean
	local controller = previewController
	if controller and controller.IsPreviewActive then
		return controller:IsPreviewActive()
	end
	if not boolValueTrue(PlotBuilderEnabledValue) then
		return false
	end
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

local function refreshUpgradeCutaway()
	if not isUpgradeViewActive or not shouldShowMainFrame() then
		CutawayViewController.Release(UPGRADE_CUTAWAY_SOURCE)
		return
	end

	CutawayViewController.Request(UPGRADE_CUTAWAY_SOURCE, {
		Priority = CUTAWAY_PRIORITY,
		TargetLevel = PlotStateStore.GetActiveLevel(),
	})
end

local function isMenuBlocked(): boolean
	if storageMenuActive then
		return true
	end
	if isPreviewActive() then
		return true
	end
	if BuildPaletteUI.IsSelectModeActive() then
		return true
	end
	local paletteFrame = resolveBuildPaletteMainFrame()
	if paletteFrame and paletteFrame.Visible then
		return true
	end
	return false
end

local function syncPalettePreviewState()
	local builderActive = PlotBuilderEnabledValue and boolValueTrue(PlotBuilderEnabledValue)
	local previewActive = builderActive and isPreviewActive()
	if previewActive then
		if BuildPaletteUI.IsVisible() then
			BuildPaletteUI.Hide()
			paletteHiddenDuringPreview = true
		end
		return
	end

	if paletteHiddenDuringPreview and builderActive then
		BuildPaletteUI.Show()
	end
	paletteHiddenDuringPreview = false
end

local function ensurePreviewController()
	if previewController then
		return previewController
	end

	local controller = PreviewController.new({
		PlotBuilderGui = PlotBuilderGui,
		CancelButtonTemplate = CancelButtonTemplate,
		PlotBuilderEnabledValue = PlotBuilderEnabledValue,
		ObjectPreviewEnabledValue = ObjectPreviewEnabledValue,
		CancelPreviewAction = CancelPreviewAction,
	}, {
		onPreviewCancelled = function()
			SurfacePaintController.Stop()
			syncPalettePreviewState()
		end,
		onHideRequested = function()
			PlotBuilder.Hide()
		end,
	})
	controller:Init()
	previewController = controller
	return controller
end

local function syncVisibility()
	local builderVisible = shouldShowMainFrame()
	local previewActive = isPreviewActive()
	PlotBuilderGui.Enabled = builderVisible
	MainFrame.Visible = builderVisible

	local showMenuFrame = false
	local showRightFrame = false

	if not builderVisible then
		LeftFrame.Visible = false
	elseif isUpgradeViewActive then
		LeftFrame.Visible = true
		showRightFrame = not previewActive
	else
		LeftFrame.Visible = false
		showMenuFrame = not isMenuBlocked()
	end

	setPopupVisible(MenuFrame, builderVisible and showMenuFrame)
	setPopupVisible(RightFrame, builderVisible and showRightFrame)

	refreshUpgradeCutaway()
end

local function setUpgradeViewActive(active: boolean)
	if isUpgradeViewActive == active then
		return
	end
	isUpgradeViewActive = active
	if active then
		BuildPaletteUI.Hide()
	else
		PlotBuilder.RemovePreview()
	end
	upgradeViewChangedSignal:Fire(isUpgradeViewActive)
	syncVisibility()
end

local function returnToMenuView()
	setUpgradeViewActive(false)
end

local function ensureBuildPaletteVisibilityObserver()
	if BuildPaletteVisibilityConnection then
		return
	end
	local paletteFrame = resolveBuildPaletteMainFrame()
	if not paletteFrame then
		return
	end
	BuildPaletteVisibilityConnection = paletteFrame:GetPropertyChangedSignal("Visible"):Connect(function()
		syncVisibility()
	end)
end

local function toggleBuildPalette()
	local paletteFrame = resolveBuildPaletteMainFrame()
	if paletteFrame and paletteFrame.Visible then
		BuildPaletteUI.Hide()
		syncVisibility()
		return
	end
	returnToMenuView()
	BuildPaletteUI.Show()
	syncPalettePreviewState()
	ensureBuildPaletteVisibilityObserver()
	syncVisibility()
end

local function toggleStorageInventory()
	warn("[PlotBuilderUI] Storage inventory UI is not implemented yet.")
end

local function togglePlotExpansionMode()
	if not PlotExpansionEnabledValue then
		warn("[PlotBuilderUI] PlotExpansionEnabled missing for menu binding.")
		return
	end
	if boolValueTrue(PlotExpansionEnabledValue) then
		PlotExpansion.Hide()
	else
		PlotExpansion.Show()
	end
end

local function toggleUpgradePanel()
	setUpgradeViewActive(not isUpgradeViewActive)
end

local function exitBuilder()
	returnToMenuView()
	BuildPaletteUI.Hide()
	PlotBuilder.Hide()
end

local function ensureMenuController()
	if menuController then
		return menuController
	end

	local controller = MenuController.new(MenuButtons, {
		onPaint = toggleBuildPalette,
		onStorage = toggleStorageInventory,
		onSelect = togglePlotExpansionMode,
		onUpgrade = toggleUpgradePanel,
		onBack = exitBuilder,
	})
	controller:Init()
	menuController = controller
	return controller
end

local function bindExitButton(button: GuiButton)
	if button:GetAttribute(EXIT_BUTTON_BOUND_ATTRIBUTE) == true then
		return
	end
	button:SetAttribute(EXIT_BUTTON_BOUND_ATTRIBUTE, true)
	button.Activated:Connect(function()
		returnToMenuView()
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
				returnToMenuView()
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
			if not boolValueTrue(PlotBuilderEnabledValue) then
				SurfacePaintController.Stop()
				local controller = ensureCatalogController()
				controller:ClearActiveSelection()
				BuildPaletteUI.Hide()
				paletteHiddenDuringPreview = false
			end
			setUpgradeViewActive(false)
			syncVisibility()
			ensurePreviewController():UpdateCancelButtonState()
			syncPalettePreviewState()
		end)
	end
	if ObjectPreviewEnabledValue then
		ObjectPreviewEnabledValue.Changed:Connect(function()
			syncVisibility()
			ensurePreviewController():UpdateCancelButtonState()
			syncPalettePreviewState()
		end)
	end
	if PlotExpansionEnabledValue then
		PlotExpansionEnabledValue.Changed:Connect(syncVisibility)
	end
	if ObjectSelectorEnabledValue then
		ObjectSelectorEnabledValue.Changed:Connect(function()
			if boolValueTrue(ObjectSelectorEnabledValue) then
				returnToMenuView()
			end
			syncVisibility()
		end)
	end
end

function PlotBuilderUI:Init()
	local catalog = ensureCatalogController()
	local preview = ensurePreviewController()
	ensureMenuController()
	bindExitControls()
	initializeVisibilityObservers()
	bindFloorLevelActions()
	if ActiveLevelChangedConnection then
		ActiveLevelChangedConnection:Disconnect()
	end
	ActiveLevelChangedConnection = PlotStateStore.OnActiveLevelChanged(function()
		refreshLevelControls()
		refreshUpgradeCutaway()
	end)
	refreshLevelControls()
	catalog:SelectInitialCategory()
	ensureBuildPaletteVisibilityObserver()
	PlayerGui.ChildAdded:Connect(function(child)
		if child.Name ~= "BuildPaletteGui" then
			return
		end
		if not child:IsA("ScreenGui") then
			return
		end
		BuildPaletteGui = child
		BuildPaletteMainFrame = BuildPaletteGui:FindFirstChild("Main")
		ensureBuildPaletteVisibilityObserver()
		syncVisibility()
	end)
	BuildPaletteUI.OnSelectModeChanged(function()
		syncVisibility()
	end)
	syncVisibility()
	preview:UpdateCancelButtonState()
	syncPalettePreviewState()
end

function PlotBuilderUI.Show()
	syncVisibility()
end

function PlotBuilderUI.Hide()
	returnToMenuView()
	setPopupVisible(MenuFrame, false)
	LeftFrame.Visible = false
	setPopupVisible(RightFrame, false)
	MainFrame.Visible = false
	CutawayViewController.Release(UPGRADE_CUTAWAY_SOURCE)
	local controller = previewController
	if controller then
		controller:UpdateCancelButtonState()
	end
end

function PlotBuilderUI.AcquireCancelButton(sourceId: string, handler: (() -> ())?)
	if typeof(sourceId) ~= "string" or sourceId == "" then
		error("PlotBuilderUI.AcquireCancelButton requires a non-empty source identifier")
	end
	if handler ~= nil and typeof(handler) ~= "function" then
		error("PlotBuilderUI.AcquireCancelButton handler must be a function or nil")
	end
	ensurePreviewController():AcquireCancelButton(sourceId, handler)
end

function PlotBuilderUI.ReleaseCancelButton(sourceId: string)
	if typeof(sourceId) ~= "string" or sourceId == "" then
		return
	end
	local controller = previewController
	if controller then
		controller:ReleaseCancelButton(sourceId)
	end
end

function PlotBuilderUI.OnUpgradeViewChanged(handler: (boolean) -> ())
	if typeof(handler) ~= "function" then
		error("PlotBuilderUI.OnUpgradeViewChanged requires a handler function")
	end
	return upgradeViewChangedSignal:Connect(handler)
end

function PlotBuilderUI.IsUpgradeViewActive(): boolean
	return isUpgradeViewActive
end

return PlotBuilderUI
