--!strict
-- StarterPlayerScripts/Client/Modules/FoodSourceInteractionController.luau
-- Handles proximity interactions for harvestable food sources on the player's plot.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local FoodPackets = require(ReplicatedStorage.Network.FoodPackets)
local FoodSources = require(ReplicatedStorage.Shared.Definitions.FoodSources)
local PlotFinder = require(ReplicatedStorage.Shared.Utilities.PlotFinder)
local PromptWidgetBinder = require(script.Parent:WaitForChild("PromptWidgetBinder"))
local PlacementCelebration = require(script.Parent.PlacementCelebration)

local LocalPlayer = Players.LocalPlayer

export type FoodSourceSpec = FoodSources.FoodSourceSpec

export type TrackedSource = {
	Model: Model,
	Prompt: ProximityPrompt,
	Connections: { RBXScriptConnection },
	SourceGuid: string,
	Spec: FoodSourceSpec,
	CreatedPrompt: boolean,
	Pending: boolean,
}

local FoodSourceInteractionController = {}

local trackedByModel: { [Model]: TrackedSource } = {}
local trackedByPrompt: { [ProximityPrompt]: TrackedSource } = {}
local trackedByGuid: { [string]: TrackedSource } = {}
local pendingGuidWait: { [Model]: RBXScriptConnection } = {}

local currentPlotIndex: number? = nil
local currentInteractablesFolder: Instance? = nil
local folderConnections: { RBXScriptConnection } = {}
local plotChildAwaiter: RBXScriptConnection? = nil

local HARVEST_PROMPT_NAME = "HarvestPrompt"
local DEFAULT_MAX_DISTANCE = 8
local RESTOCK_LABEL_UPDATE_INTERVAL = 0.5
local FAILURE_NOTICE_THROTTLE = 1.25

local restockAccumulator = 0
local lastFailureNotice: { [string]: number } = {}

local function clearGuidWait(model: Model)
	local connection = pendingGuidWait[model]
	if connection then
		connection:Disconnect()
		pendingGuidWait[model] = nil
	end
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

local function determineSpec(model: Model): FoodSourceSpec?
	local sourceIdAttr = model:GetAttribute("FoodSourceId")
	if typeof(sourceIdAttr) ~= "string" or sourceIdAttr == "" then
		return nil
	end
	local spec = FoodSources.Sources[sourceIdAttr]
	if spec then
		return spec
	end
	local fallbackKey = string.gsub(sourceIdAttr, "%s+", "")
	return FoodSources.Sources[fallbackKey]
end

local function formatTimeRemaining(seconds: number): string
	local clamped = math.max(0, math.ceil(seconds))
	local minutes = math.floor(clamped / 60)
	local secs = clamped % 60
	if minutes > 0 then
		if secs > 0 then
			return string.format("%dm %02ds", minutes, secs)
		end
		return string.format("%dm", minutes)
	end
	return string.format("%ds", math.max(secs, 0))
end

local function humanizeIdentifier(identifier: string): string
	local trimmed = identifier:gsub("^%s+", ""):gsub("%s+$", "")
	if trimmed == "" then
		return "harvest storage"
	end
	local spaced = trimmed:gsub("(%u)", " %1"):gsub("%s+", " ")
	spaced = spaced:gsub("^ ", "")
	if spaced == "" then
		return "harvest storage"
	end
	return spaced
end

local function computeRestockRemaining(model: Model): number
	local readyAtAttr = model:GetAttribute("HarvestRestockAt")
	if typeof(readyAtAttr) ~= "number" or readyAtAttr <= 0 then
		return 0
	end
	local now = Workspace:GetServerTimeNow()
	return math.max(0, readyAtAttr - now)
end

local function buildRestockActionText(remainingSeconds: number): string
	if remainingSeconds > 1 then
		return string.format("Regrowing (%s)", formatTimeRemaining(remainingSeconds))
	end
	return "Regrowing"
end

local function shouldShowNotice(sourceGuid: string): boolean
	local now = os.clock()
	local last = lastFailureNotice[sourceGuid]
	if last and now - last < FAILURE_NOTICE_THROTTLE then
		return false
	end
	lastFailureNotice[sourceGuid] = now
	return true
end

local function showHarvestNotice(record: TrackedSource, reason: string?)
	if not shouldShowNotice(record.SourceGuid) then
		return
	end
	local spec = record.Spec
	local message: string
	local color: Color3
	local normalized = reason or ""
	if normalized == "Restocking" then
		local remaining = computeRestockRemaining(record.Model)
		if remaining > 1 then
			message = string.format("%s ready in %s", spec.Name, formatTimeRemaining(remaining))
		else
			message = string.format("%s is still regrowing", spec.Name)
		end
		color = Color3.fromRGB(255, 226, 124)
	elseif normalized == "StorageFull" then
		local containerIdAttr = record.Model:GetAttribute("HarvestContainerId")
		local containerId = if typeof(containerIdAttr) == "string"
			then containerIdAttr
			else spec.TargetStorage and spec.TargetStorage.ContainerId or "Harvest storage"
		message = string.format("%s is full", humanizeIdentifier(containerId))
		color = Color3.fromRGB(255, 118, 118)
	elseif normalized == "NotYourPlot" then
		message = "Only your own plot sources"
		color = Color3.fromRGB(255, 118, 118)
	elseif normalized == "HarvestBusy" then
		message = "Harvest already in progress"
		color = Color3.fromRGB(180, 210, 255)
	elseif normalized == "NoYield" then
		message = "Nothing ready to collect"
		color = Color3.fromRGB(255, 190, 128)
	else
		message = "Unable to harvest right now"
		color = Color3.fromRGB(255, 118, 118)
	end

	local adornee = record.Prompt.Parent
	local position: Vector3? = nil
	if adornee and adornee:IsA("BasePart") then
		position = adornee.Position
	else
		local model = record.Model
		local ok, pivot = pcall(function()
			return model:GetPivot()
		end)
		if ok then
			position = pivot.Position
		end
	end

	PlacementCelebration.ShowMessage(position, message, color)
end

local function updatePromptAvailability(record: TrackedSource)
	local model = record.Model
	local prompt = record.Prompt
	local spec = record.Spec
	local readyAttr = model:GetAttribute("HarvestReady")
	local isReady = if typeof(readyAttr) == "boolean" then readyAttr else true
	if record.Pending then
		prompt.Enabled = false
		PromptWidgetBinder.SetSuppressed(prompt, true)
		if prompt.ActionText ~= "Collecting..." then
			prompt.ActionText = "Collecting..."
			PromptWidgetBinder.Refresh(prompt)
		end
		return
	end

	prompt.Enabled = true
	PromptWidgetBinder.SetSuppressed(prompt, false)

	if isReady then
		local desiredText = "Harvest " .. spec.Name
		if prompt.ActionText ~= desiredText then
			prompt.ActionText = desiredText
			PromptWidgetBinder.Refresh(prompt)
		end
		return
	end

	local remaining = computeRestockRemaining(model)
	local restockText = buildRestockActionText(remaining)
	if prompt.ActionText ~= restockText then
		prompt.ActionText = restockText
		PromptWidgetBinder.Refresh(prompt)
	end
end

local function cleanupModel(model: Model)
	clearGuidWait(model)
	local tracked = trackedByModel[model]
	if not tracked then
		return
	end
	trackedByModel[model] = nil
	trackedByPrompt[tracked.Prompt] = nil
	trackedByGuid[tracked.SourceGuid] = nil
	lastFailureNotice[tracked.SourceGuid] = nil
	for _, connection in ipairs(tracked.Connections) do
		connection:Disconnect()
	end
	PromptWidgetBinder.Detach(tracked.Prompt)
	if tracked.CreatedPrompt then
		tracked.Prompt:Destroy()
	else
		tracked.Prompt.Enabled = true
	end
end

local function onPromptTriggered(record: TrackedSource)
	if record.Pending then
		return
	end
	local sourceGuid = record.SourceGuid
	if not sourceGuid or sourceGuid == "" then
		return
	end
	local readyAttr = record.Model:GetAttribute("HarvestReady")
	local isReady = if typeof(readyAttr) == "boolean" then readyAttr else true
	if not isReady then
		showHarvestNotice(record, "Restocking")
		updatePromptAvailability(record)
		return
	end
	record.Pending = true
	updatePromptAvailability(record)

	task.defer(function()
		local ok, success, message = pcall(function()
			return FoodPackets.HarvestFoodSourceRequest:Fire(sourceGuid)
		end)
		record.Pending = false
		if not ok then
			warn("Harvest request failed", success)
			showHarvestNotice(record, "Error")
			updatePromptAvailability(record)
			return
		end
		if not success then
			warn("Harvest rejected", message)
			showHarvestNotice(record, typeof(message) == "string" and message or nil)
		end
		updatePromptAvailability(record)
	end)
end

local function registerModel(model: Model)
	if trackedByModel[model] then
		return
	end

	local spec = determineSpec(model)
	if not spec then
		return
	end

	local sourceGuidAttr = model:GetAttribute("FoodSourceGuid")
	if typeof(sourceGuidAttr) ~= "string" or sourceGuidAttr == "" then
		if not pendingGuidWait[model] then
			pendingGuidWait[model] = model:GetAttributeChangedSignal("FoodSourceGuid"):Connect(function()
				clearGuidWait(model)
				registerModel(model)
			end)
		end
		return
	end

	local interactPart = findInteractPart(model)
	if not interactPart then
		return
	end

	local existing = interactPart:FindFirstChild(HARVEST_PROMPT_NAME)
	local prompt: ProximityPrompt
	local createdPrompt = false
	if existing and existing:IsA("ProximityPrompt") then
		prompt = existing
	else
		prompt = Instance.new("ProximityPrompt")
		prompt.Name = HARVEST_PROMPT_NAME
		createdPrompt = true
		prompt.KeyboardKeyCode = Enum.KeyCode.E
		prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
		prompt.ObjectText = spec.Name
		prompt.ActionText = "Harvest " .. spec.Name
		prompt.HoldDuration = 0
		prompt.RequiresLineOfSight = false
		prompt.MaxActivationDistance = DEFAULT_MAX_DISTANCE
		prompt.Parent = interactPart
	end

	prompt.Style = Enum.ProximityPromptStyle.Custom

	local record: TrackedSource = {
		Model = model,
		Prompt = prompt,
		Connections = {},
		SourceGuid = sourceGuidAttr,
		Spec = spec,
		CreatedPrompt = createdPrompt,
		Pending = false,
	}

	record.Connections[#record.Connections + 1] = prompt.Triggered:Connect(function(player)
		if player ~= LocalPlayer then
			return
		end
		onPromptTriggered(record)
	end)

	record.Connections[#record.Connections + 1] = model:GetAttributeChangedSignal("HarvestReady"):Connect(function()
		updatePromptAvailability(record)
	end)

	record.Connections[#record.Connections + 1] = model:GetAttributeChangedSignal("FoodSourceGuid"):Connect(function()
		local newGuid = model:GetAttribute("FoodSourceGuid")
		if typeof(newGuid) ~= "string" or newGuid == "" then
			return
		end
		trackedByGuid[record.SourceGuid] = nil
		record.SourceGuid = newGuid
		trackedByGuid[newGuid] = record
	end)

	record.Connections[#record.Connections + 1] = model.Destroying:Connect(function()
		cleanupModel(model)
	end)

	record.Connections[#record.Connections + 1] = model.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			cleanupModel(model)
		end
	end)

	trackedByModel[model] = record
	trackedByPrompt[prompt] = record
	trackedByGuid[sourceGuidAttr] = record

	PromptWidgetBinder.Attach(prompt)
	updatePromptAvailability(record)
end

local function unbindCurrentFolder()
	for _, connection in ipairs(folderConnections) do
		connection:Disconnect()
	end
	folderConnections = {}
	currentInteractablesFolder = nil
	local toCleanup: { Model } = {}
	for model in pairs(trackedByModel) do
		toCleanup[#toCleanup + 1] = model
	end
	for _, model in ipairs(toCleanup) do
		cleanupModel(model)
	end
end

local function bindInteractablesFolder(folder: Instance)
	if currentInteractablesFolder == folder then
		return
	end

	unbindCurrentFolder()
	currentInteractablesFolder = folder

	for _, child in ipairs(folder:GetChildren()) do
		if child:IsA("Model") then
			registerModel(child)
		end
	end

	folderConnections[#folderConnections + 1] = folder.ChildAdded:Connect(function(child)
		if child:IsA("Model") then
			registerModel(child)
		end
	end)

	folderConnections[#folderConnections + 1] = folder.ChildRemoved:Connect(function(child)
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

	unbindCurrentFolder()
	if plotChildAwaiter then
		plotChildAwaiter:Disconnect()
		plotChildAwaiter = nil
	end

	if not plotIndex then
		return
	end

	local plotModel = PlotFinder.FindPlot(plotIndex)
	if plotModel then
		local interactables = plotModel:FindFirstChild("Interactables")
		if interactables then
			bindInteractablesFolder(interactables)
			return
		end
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
		if child.Name == "Interactables" then
			bindInteractablesFolder(child)
			if plotChildAwaiter then
				plotChildAwaiter:Disconnect()
				plotChildAwaiter = nil
			end
		end
	end)
end

RunService.Heartbeat:Connect(function(deltaTime)
	restockAccumulator += deltaTime
	if restockAccumulator < RESTOCK_LABEL_UPDATE_INTERVAL then
		return
	end
	restockAccumulator = 0
	local now = Workspace:GetServerTimeNow()
	for _, record in pairs(trackedByModel) do
		if record.Pending then
			continue
		end
		local readyAttr = record.Model:GetAttribute("HarvestReady")
		local isReady = if typeof(readyAttr) == "boolean" then readyAttr else true
		if isReady then
			continue
		end
		local restockAt = record.Model:GetAttribute("HarvestRestockAt")
		local remaining = 0
		if typeof(restockAt) == "number" and restockAt > 0 then
			remaining = math.max(0, restockAt - now)
		end
		local restockText = buildRestockActionText(remaining)
		if record.Prompt.ActionText ~= restockText then
			record.Prompt.ActionText = restockText
			PromptWidgetBinder.Refresh(record.Prompt)
		end
	end
end)

function FoodSourceInteractionController.Init()
	rebindPlot(LocalPlayer:GetAttribute("OwnedPlotIndex") :: number?)

	LocalPlayer:GetAttributeChangedSignal("OwnedPlotIndex"):Connect(function()
		rebindPlot(LocalPlayer:GetAttribute("OwnedPlotIndex") :: number?)
	end)
end

return FoodSourceInteractionController
