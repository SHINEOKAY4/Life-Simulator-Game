--!strict
-- StarterPlayerScripts/Client/Modules/StorageInteractionController.luau
-- Adds proximity prompts to storage-capable stations and opens the storage billboard UI when nearby.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ProximityPromptService = game:GetService("ProximityPromptService")

local PlotFinder = require(ReplicatedStorage.Shared.Utilities.PlotFinder)
local ItemFinder = require(ReplicatedStorage.Shared.Utilities.ItemFinder)
local StorageBillboardUI = require(script.Parent.Parent.UserInterface.StorageBillboardUI)

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

local StorageInteractionController = {}

export type TrackedModel = {
	Prompt: ProximityPrompt,
	Connections: { RBXScriptConnection },
	ContainerId: string,
	Meta: StorageBillboardUI.StorageMeta,
	CreatedPrompt: boolean,
	DefaultStyle: Enum.ProximityPromptStyle,
}

local trackedModels: { [Model]: TrackedModel } = {}
local promptByContainerId: { [string]: ProximityPrompt } = {}
local trackedByContainerId: { [string]: TrackedModel } = {}
local trackedByPrompt: { [ProximityPrompt]: TrackedModel } = {}
local containerFolderConnections: { RBXScriptConnection } = {}
local plotChildAwaiter: RBXScriptConnection? = nil
local currentContainerFolder: Instance? = nil
local currentPlotIndex: number? = nil

local promptWidgets: { [ProximityPrompt]: BillboardGui } = {}
local promptWidgetSuppressed: { [ProximityPrompt]: boolean } = {}
local promptEventsBound = false

local function applyCircleStyling(frame: Frame)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = frame

	local stroke = Instance.new("UIStroke")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	stroke.Thickness = 2
	stroke.Color = Color3.fromRGB(255, 255, 255)
	stroke.Transparency = 0.15
	stroke.Parent = frame
end

local function createPromptWidget(prompt: ProximityPrompt): BillboardGui?
	local adornee = prompt.Parent
	if not adornee or not adornee:IsA("BasePart") then
		return nil
	end

	local existing = promptWidgets[prompt]
	if existing then
		existing.Adornee = adornee
		return existing
	end

	local gui = Instance.new("BillboardGui")
	gui.Name = "StoragePromptRing"
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.MaxDistance = math.max(prompt.MaxActivationDistance + 20, 25)
	gui.Size = UDim2.fromOffset(120, 120)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 3.25, 0)
	gui.Enabled = false
	gui.Adornee = adornee
	gui.Parent = PlayerGui

	local root = Instance.new("Frame")
	root.Name = "Root"
	root.BackgroundTransparency = 1
	root.Size = UDim2.fromScale(1, 1)
	root.Parent = gui

	local keyRing = Instance.new("Frame")
	keyRing.Name = "KeyRing"
	keyRing.AnchorPoint = Vector2.new(0.5, 0)
	keyRing.Position = UDim2.fromScale(0.5, 0)
	keyRing.Size = UDim2.fromOffset(40, 40)
	keyRing.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	keyRing.BackgroundTransparency = 0.1
	keyRing.Parent = root
	applyCircleStyling(keyRing)

	local keyText = Instance.new("TextLabel")
	keyText.Name = "KeyText"
	keyText.AnchorPoint = Vector2.new(0.5, 0.5)
	keyText.Position = UDim2.fromScale(0.5, 0.5)
	keyText.BackgroundTransparency = 1
	keyText.Font = Enum.Font.GothamBold
	keyText.TextSize = 18
	keyText.TextColor3 = Color3.fromRGB(28, 32, 44)
	keyText.Text = ""
	keyText.Parent = keyRing

	local actionLabel = Instance.new("TextLabel")
	actionLabel.Name = "ActionLabel"
	actionLabel.AnchorPoint = Vector2.new(0.5, 0)
	actionLabel.Position = UDim2.new(0.5, 0, 0, 48)
	actionLabel.Size = UDim2.fromOffset(0, 0)
	actionLabel.AutomaticSize = Enum.AutomaticSize.XY
	actionLabel.BackgroundTransparency = 1
	actionLabel.Font = Enum.Font.GothamBold
	actionLabel.TextSize = 16
	actionLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	actionLabel.Text = prompt.ActionText ~= "" and prompt.ActionText or "Open"
	actionLabel.TextXAlignment = Enum.TextXAlignment.Center
	actionLabel.TextYAlignment = Enum.TextYAlignment.Top
	actionLabel.Parent = root

	promptWidgets[prompt] = gui
	return gui
end

local function updatePromptWidget(prompt: ProximityPrompt, inputType: Enum.ProximityPromptInputType?)
	local widget = promptWidgets[prompt]
	if not widget then
		return
	end
	local root = widget:FindFirstChild("Root")
	if not root or not root:IsA("Frame") then
		return
	end

	local keyRing = root:FindFirstChild("KeyRing")
	local keyText = keyRing and keyRing:FindFirstChild("KeyText")
	local actionLabel = root:FindFirstChild("ActionLabel")

	if keyRing and keyRing:IsA("Frame") and keyText and keyText:IsA("TextLabel") then
		local displayText = ""
		if inputType == Enum.ProximityPromptInputType.Touch then
			displayText = "Tap"
		elseif inputType == Enum.ProximityPromptInputType.Gamepad then
			displayText = prompt.GamepadKeyCode.Name
		else
			displayText = prompt.KeyboardKeyCode.Name
		end
		displayText = displayText ~= "" and displayText or ""
		keyText.Text = displayText
	end

	if actionLabel and actionLabel:IsA("TextLabel") then
		actionLabel.Text = prompt.ActionText ~= "" and prompt.ActionText or "Open"
	end

	local adornee = prompt.Parent
	if adornee and adornee:IsA("BasePart") then
		widget.Adornee = adornee
	end
end

local function setPromptWidgetVisible(prompt: ProximityPrompt, shouldShow: boolean)
	local widget = promptWidgets[prompt]
	if not widget then
		return
	end
	if promptWidgetSuppressed[prompt] then
		widget.Enabled = false
		return
	end
	widget.Enabled = shouldShow
end

local function bindPromptServiceEvents()
	if promptEventsBound then
		return
	end
	promptEventsBound = true

	ProximityPromptService.PromptShown:Connect(
		function(prompt: ProximityPrompt, inputType: Enum.ProximityPromptInputType)
			local tracked = trackedByPrompt[prompt]
			if not tracked then
				return
			end
			createPromptWidget(prompt)
			updatePromptWidget(prompt, inputType)
			setPromptWidgetVisible(prompt, true)
		end
	)

	ProximityPromptService.PromptHidden:Connect(function(prompt: ProximityPrompt)
		setPromptWidgetVisible(prompt, false)
	end)

	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt)
		setPromptWidgetVisible(prompt, false)
	end)
end
local function findInteractPart(model: Model): BasePart?
	if model.PrimaryPart and model.PrimaryPart:IsA("BasePart") then
		return model.PrimaryPart
	end
	local part = model:FindFirstChildWhichIsA("BasePart", true)
	if part then
		return part
	end
	return nil
end

local function isStorageSpec(spec: any): boolean
	if typeof(spec) ~= "table" then
		return false
	end
	local storageConfig = spec.StorageConfig
	return typeof(storageConfig) == "table"
		and typeof(storageConfig.Capacity) == "number"
		and storageConfig.Capacity > 0
end

local function cleanupModel(model: Model)
	local tracked = trackedModels[model]
	if not tracked then
		return
	end
	promptByContainerId[tracked.ContainerId] = nil
	trackedModels[model] = nil
	trackedByContainerId[tracked.ContainerId] = nil
	trackedByPrompt[tracked.Prompt] = nil
	for _, connection in ipairs(tracked.Connections) do
		connection:Disconnect()
	end
	tracked.Prompt.Style = tracked.DefaultStyle
	local widget = promptWidgets[tracked.Prompt]
	if widget then
		widget:Destroy()
		promptWidgets[tracked.Prompt] = nil
	end
	promptWidgetSuppressed[tracked.Prompt] = nil
	if tracked.CreatedPrompt then
		tracked.Prompt:Destroy()
	else
		tracked.Prompt.Enabled = true
	end
	StorageBillboardUI.HideIfTarget(tracked.ContainerId)
end

local function registerModel(model: Model)
	if trackedModels[model] then
		return
	end
	if not model:IsA("Model") then
		return
	end

	local itemIdAttr = model:GetAttribute("ItemId")
	if typeof(itemIdAttr) ~= "string" or itemIdAttr == "" then
		return
	end

	local spec = ItemFinder.FindItemById(itemIdAttr)
	if not isStorageSpec(spec) then
		return
	end

	local interactPart = findInteractPart(model)
	if not interactPart then
		return
	end

	local existing = interactPart:FindFirstChild("StoragePrompt")
	local prompt: ProximityPrompt
	local createdPrompt = false
	if not existing or not existing:IsA("ProximityPrompt") then
		prompt = Instance.new("ProximityPrompt")
		prompt.Name = "StoragePrompt"
		local itemDisplayName = typeof(spec.Name) == "string" and spec.Name or "Storage"
		prompt.ActionText = "Open " .. itemDisplayName
		prompt.ObjectText = itemDisplayName
		prompt.KeyboardKeyCode = Enum.KeyCode.E
		prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = 7
		prompt.RequiresLineOfSight = false
		prompt.Parent = interactPart
		createdPrompt = true
	else
		prompt = existing
		local itemDisplayName = typeof(spec.Name) == "string" and spec.Name or prompt.ObjectText
		if itemDisplayName == nil or itemDisplayName == "" then
			itemDisplayName = "Storage"
		end
		prompt.ObjectText = itemDisplayName
		prompt.ActionText = "Open " .. itemDisplayName
	end

	local storageConfig = spec.StorageConfig
	local capacity = if storageConfig and typeof(storageConfig.Capacity) == "number" then storageConfig.Capacity else 0
	local meta: StorageBillboardUI.StorageMeta = {
		Name = typeof(spec.Name) == "string" and spec.Name or nil,
		StationType = typeof(spec.StationType) == "string" and spec.StationType or "CookStation",
		ItemId = itemIdAttr,
		Capacity = capacity,
	}

	local containerId = model.Name

	local connections: { RBXScriptConnection } = {}

	prompt.Style = Enum.ProximityPromptStyle.Custom

	local function bindPromptSignals()
		local triggeredConn = prompt.Triggered:Connect(function(player)
			if player ~= LocalPlayer then
				return
			end
			if StorageBillboardUI.IsVisible() and StorageBillboardUI.GetCurrentContainerId() == containerId then
				StorageBillboardUI.Hide()
			else
				StorageBillboardUI.Show(model, containerId, meta)
			end
		end)
		local hiddenConn = prompt.PromptHidden:Connect(function()
			StorageBillboardUI.HandlePromptHidden(containerId)
		end)
		connections[#connections + 1] = triggeredConn
		connections[#connections + 1] = hiddenConn
	end

	bindPromptSignals()

	connections[#connections + 1] = model.Destroying:Connect(function()
		cleanupModel(model)
	end)
	connections[#connections + 1] = model.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			cleanupModel(model)
		end
	end)

	local record: TrackedModel = {
		Prompt = prompt,
		Connections = connections,
		ContainerId = containerId,
		Meta = meta,
		CreatedPrompt = createdPrompt,
		DefaultStyle = prompt.Style,
	}
	trackedModels[model] = record
	trackedByContainerId[containerId] = record
	trackedByPrompt[prompt] = record
	promptByContainerId[containerId] = prompt
	createPromptWidget(prompt)
	updatePromptWidget(prompt, nil)
end

local function unbindContainerFolder()
	for _, connection in ipairs(containerFolderConnections) do
		connection:Disconnect()
	end
	containerFolderConnections = {}
	currentContainerFolder = nil
	for model in pairs(trackedModels) do
		cleanupModel(model)
	end
end

local function bindContainerFolder(folder: Instance)
	if currentContainerFolder == folder then
		return
	end

	unbindContainerFolder()
	currentContainerFolder = folder

	for _, child in ipairs(folder:GetChildren()) do
		if child:IsA("Model") then
			registerModel(child)
		end
	end

	containerFolderConnections[#containerFolderConnections + 1] = folder.ChildAdded:Connect(function(child)
		if child:IsA("Model") then
			registerModel(child)
		end
	end)

	containerFolderConnections[#containerFolderConnections + 1] = folder.ChildRemoved:Connect(function(child)
		if child:IsA("Model") then
			cleanupModel(child)
		end
	end)
end

local function rebindPlot(plotIndex: number?)
	if plotIndex == currentPlotIndex then
		return
	end
	currentPlotIndex = plotIndex

	unbindContainerFolder()
	if plotChildAwaiter then
		plotChildAwaiter:Disconnect()
		plotChildAwaiter = nil
	end
	if not plotIndex then
		return
	end

	local plotModel = PlotFinder.FindPlot(plotIndex)
	if plotModel then
		local containerFolder = plotModel:FindFirstChild("Container")
		if containerFolder then
			bindContainerFolder(containerFolder)
			return
		end
	end

	if plotChildAwaiter then
		plotChildAwaiter:Disconnect()
		plotChildAwaiter = nil
	end

	if not plotModel then
		task.defer(function()
			if currentPlotIndex == plotIndex then
				rebindPlot(plotIndex)
			end
		end)
		return
	end

	plotChildAwaiter = plotModel.ChildAdded:Connect(function(child)
		if child.Name == "Container" then
			bindContainerFolder(child)
			if plotChildAwaiter then
				plotChildAwaiter:Disconnect()
				plotChildAwaiter = nil
			end
		end
	end)
end

function StorageInteractionController.Init()
	bindPromptServiceEvents()
	StorageBillboardUI.VisibilityChanged:Connect(function(containerId: string, isVisible: boolean)
		local prompt = promptByContainerId[containerId]
		local tracked = trackedByContainerId[containerId]
		if not prompt or not tracked then
			return
		end
		if isVisible then
			promptWidgetSuppressed[prompt] = true
			setPromptWidgetVisible(prompt, false)
		else
			promptWidgetSuppressed[prompt] = nil
			setPromptWidgetVisible(prompt, false)
		end
	end)
	rebindPlot(LocalPlayer:GetAttribute("OwnedPlotIndex") :: number?)

	LocalPlayer:GetAttributeChangedSignal("OwnedPlotIndex"):Connect(function()
		rebindPlot(LocalPlayer:GetAttribute("OwnedPlotIndex") :: number?)
	end)
end

return StorageInteractionController
