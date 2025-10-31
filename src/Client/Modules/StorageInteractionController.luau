--!strict
-- StarterPlayerScripts/Client/Modules/StorageInteractionController.luau
-- Adds proximity prompts to storage-capable stations and opens the storage billboard UI when nearby.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlotFinder = require(ReplicatedStorage.Shared.Utilities.PlotFinder)
local ItemFinder = require(ReplicatedStorage.Shared.Utilities.ItemFinder)
local PromptWidgetBinder = require(script.Parent.PromptWidgetBinder)
local StorageBillboardUI = require(script.Parent.Parent.UserInterface.StorageBillboardUI)

local LocalPlayer = Players.LocalPlayer
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
	PromptWidgetBinder.Detach(tracked.Prompt)
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
	PromptWidgetBinder.Attach(prompt)
	PromptWidgetBinder.Refresh(prompt)
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
	StorageBillboardUI.VisibilityChanged:Connect(function(containerId: string, isVisible: boolean)
		local prompt = promptByContainerId[containerId]
		local tracked = trackedByContainerId[containerId]
		if not prompt or not tracked then
			return
		end
		if isVisible then
			PromptWidgetBinder.SetSuppressed(prompt, true)
		else
			PromptWidgetBinder.SetSuppressed(prompt, false)
		end
	end)
	rebindPlot(LocalPlayer:GetAttribute("OwnedPlotIndex") :: number?)

	LocalPlayer:GetAttributeChangedSignal("OwnedPlotIndex"):Connect(function()
		rebindPlot(LocalPlayer:GetAttribute("OwnedPlotIndex") :: number?)
	end)
end

return StorageInteractionController
