--!strict
-- StarterPlayerScripts/Client/UserInterface/NeedWarningNotifications.lua

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NeedConfig = require(ReplicatedStorage.Shared.Configurations.NeedConfig)
local PlotFinder = require(ReplicatedStorage.Shared.Utilities.PlotFinder)
local ResidentsStore = require(script.Parent.Parent.ClientStores.ResidentsStore)
local ResidentNeedsUI = require(script.Parent.ResidentNeedsUI)
local NotificationModule = require(script.Parent.Notification)

type NeedSeverity = "Low" | "Critical" | "Satisfied"

type NeedEntry = {
	lastShownSeverity: NeedSeverity?,
	lastShownTime: number,
	pendingSeverity: NeedSeverity?,
	currentValue: number?,
	lastSatisfiedShown: boolean,
}

type NotificationHandle = NotificationModule.NotificationHandle
type NotificationPlacement = NotificationModule.NotificationPlacement

local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")
local ResidentGui = PlayerGui:WaitForChild("ResidentGui")
local ResidentSelectionFrame = ResidentGui:WaitForChild("ResidentSelectionFrame")

local NeedWarningNotifications = {}

local NEED_NAMES = { "Hunger", "Energy", "Fun", "Social", "Hygiene" }
local NEED_FEELING_TEXT = {
	Hunger = "hungry",
	Energy = "tired",
	Fun = "bored",
	Social = "lonely",
	Hygiene = "dirty",
}
local NEED_SATISFIED_TEXT = {
	Hunger = "satisfied",
	Energy = "energized",
	Fun = "entertained",
	Social = "fulfilled",
	Hygiene = "refreshed",
}
local NEED_SEVERITY_COLORS: { [NeedSeverity]: Color3 } = {
	Low = Color3.fromRGB(236, 187, 92),
	Critical = Color3.fromRGB(220, 98, 86),
	Satisfied = Color3.fromRGB(82, 199, 107),
}

local NEED_DEFINITIONS = NeedConfig.Needs
local SOUND_ID = "rbxassetid://109149869070031"
local TOAST_DURATION_SECONDS = 4.5
local REMINDER_INTERVAL_SECONDS = 60

local NEED_PLACEMENT: NotificationPlacement = {
	Parent = ResidentGui,
	AnchorPoint = Vector2.new(0, 0.5),
	Position = UDim2.new(0, 16, 0.5, 0),
	Size = UDim2.fromScale(0.20, 0.35),
	HorizontalAlignment = Enum.HorizontalAlignment.Left,
	VerticalAlignment = Enum.VerticalAlignment.Top,
	Padding = 6,
	MaxVisible = 3,
	ZIndex = 100,
	Name = "NeedWarningToasts",
}

local needStateByResident: { [string]: { [string]: NeedEntry } } = {}
local residentConnections: { [string]: { RBXScriptConnection } } = {}
local folderConnections: { RBXScriptConnection } = {}
local currentResidentsFolder: Folder? = nil
local activeToastHandles: { [NotificationHandle]: boolean } = {}

local function trackToastHandle(handle: NotificationHandle)
	activeToastHandles[handle] = true
	task.delay(TOAST_DURATION_SECONDS + 1, function()
		if activeToastHandles[handle] then
			activeToastHandles[handle] = nil
		end
	end)
end

local function clearTrackedHandles()
	for handle in pairs(activeToastHandles) do
		handle.Dismiss()
	end
	table.clear(activeToastHandles)
end

local function showNeedToast(residentName: string, needName: string, severity: NeedSeverity)
	local feelingText: string
	if severity == "Satisfied" then
		feelingText = NEED_SATISFIED_TEXT[needName] or "satisfied"
	else
		feelingText = NEED_FEELING_TEXT[needName] or string.lower(needName)
	end
	local message = string.format("%s is feeling %s.", residentName, feelingText)
	local backgroundColor = NEED_SEVERITY_COLORS[severity]
	local priority = if severity == "Critical" then 2 elseif severity == "Satisfied" then 0 else 1

	local handle = NotificationModule.Show({
		Title = if severity == "Satisfied" then "Need Satisfied" else "Need Warning",
		Text = message,
		BackgroundColor = backgroundColor,
		TextColor = Color3.new(1, 1, 1),
		Duration = TOAST_DURATION_SECONDS,
		SoundId = SOUND_ID,
		Priority = priority,
		Placement = NEED_PLACEMENT,
	})

	trackToastHandle(handle)
end

local function ensureNeedEntry(residentName: string, needName: string): NeedEntry
	local residentEntry = needStateByResident[residentName]
	if not residentEntry then
		residentEntry = {}
		needStateByResident[residentName] = residentEntry
	end
	local entry = residentEntry[needName]
	if not entry then
		entry = {
			lastShownSeverity = nil,
			lastShownTime = 0,
			pendingSeverity = nil,
			currentValue = nil,
			lastSatisfiedShown = false,
		}
		residentEntry[needName] = entry
	end
	return entry
end

local function handleNeedValue(residentName: string, needName: string, needValue: number)
	if typeof(needValue) ~= "number" then
		return
	end
	local needDefinition = NEED_DEFINITIONS[needName]
	if not needDefinition then
		return
	end
	local entry = ensureNeedEntry(residentName, needName)
	entry.currentValue = needValue
	local anyResidentSelected = ResidentNeedsUI.GetCurrentSelectedResident() ~= nil

	local releaseThreshold = math.min(needDefinition.Max, needDefinition.Low + needDefinition.Hysteresis)

	-- Check for satisfied state (need is full)
	if needValue >= needDefinition.Max then
		if not ResidentSelectionFrame.Visible or anyResidentSelected then
			entry.pendingSeverity = "Satisfied"
			return
		end
		if not entry.lastSatisfiedShown then
			showNeedToast(residentName, needName, "Satisfied")
			entry.lastSatisfiedShown = true
		end
		entry.lastShownSeverity = nil
		entry.pendingSeverity = nil
		return
	end

	-- Reset satisfied flag if need drops below max
	if needValue < needDefinition.Max then
		entry.lastSatisfiedShown = false
	end

	-- Clear warnings if need is above low threshold
	if needValue > needDefinition.Low then
		if needValue >= releaseThreshold then
			entry.lastShownSeverity = nil
			entry.pendingSeverity = nil
		end
		return
	end

	local severity: NeedSeverity = if needValue <= needDefinition.Critical then "Critical" else "Low"

	if not ResidentSelectionFrame.Visible or anyResidentSelected then
		entry.pendingSeverity = severity
		return
	end

	local now = os.clock()
	local shouldShow = entry.lastShownSeverity == nil
		or entry.lastShownSeverity ~= severity
		or now - entry.lastShownTime >= REMINDER_INTERVAL_SECONDS

	if shouldShow then
		showNeedToast(residentName, needName, severity)
		entry.lastShownSeverity = severity
		entry.lastShownTime = now
		entry.pendingSeverity = nil
	else
		entry.pendingSeverity = nil
	end
end

local function processPendingWarnings()
	if not ResidentSelectionFrame.Visible then
		return
	end
	-- Skip processing if ANY resident is selected
	local anySelected = ResidentNeedsUI.GetCurrentSelectedResident() ~= nil
	if anySelected then
		return
	end

	for residentName, needsMap in pairs(needStateByResident) do
		for needName, entry in pairs(needsMap) do
			local pendingSeverity = entry.pendingSeverity
			if not pendingSeverity then
				continue
			end
			if pendingSeverity ~= "Critical" and pendingSeverity ~= "Low" and pendingSeverity ~= "Satisfied" then
				entry.pendingSeverity = nil
				continue
			end
			local severityToShow: NeedSeverity = pendingSeverity
			local needDefinition = NEED_DEFINITIONS[needName]
			if not needDefinition then
				entry.pendingSeverity = nil
				continue
			end
			local needValue = entry.currentValue
			local stillValid = false
			if severityToShow == "Critical" then
				stillValid = typeof(needValue) == "number" and needValue <= needDefinition.Critical
			elseif severityToShow == "Satisfied" then
				stillValid = typeof(needValue) == "number" and needValue >= needDefinition.Max
			else
				stillValid = typeof(needValue) == "number" and needValue <= needDefinition.Low
			end
			if stillValid then
				local now = os.clock()
				if severityToShow == "Satisfied" then
					if not entry.lastSatisfiedShown then
						showNeedToast(residentName, needName, severityToShow)
						entry.lastSatisfiedShown = true
					end
				elseif
					entry.lastShownSeverity ~= severityToShow
					or now - entry.lastShownTime >= REMINDER_INTERVAL_SECONDS
				then
					showNeedToast(residentName, needName, severityToShow)
					entry.lastShownSeverity = severityToShow
					entry.lastShownTime = now
				end
			else
				if severityToShow ~= "Satisfied" then
					entry.lastShownSeverity = nil
				end
			end
			entry.pendingSeverity = nil
		end
	end
end

local function disconnectResidentConnections(residentName: string)
	local connections = residentConnections[residentName]
	if not connections then
		return
	end
	for _, connection in ipairs(connections) do
		if connection.Connected then
			connection:Disconnect()
		end
	end
	residentConnections[residentName] = nil
end

local function cleanupResident(residentName: string)
	disconnectResidentConnections(residentName)
	needStateByResident[residentName] = nil
end

local function registerResidentModel(residentModel: Model)
	local residentName = residentModel.Name
	disconnectResidentConnections(residentName)
	local connections: { RBXScriptConnection } = {}
	for _, needName in ipairs(NEED_NAMES) do
		local attributeConnection = residentModel:GetAttributeChangedSignal(needName):Connect(function()
			local updatedValue = residentModel:GetAttribute(needName)
			if typeof(updatedValue) == "number" then
				handleNeedValue(residentName, needName, updatedValue)
			end
		end)
		table.insert(connections, attributeConnection)
		local initialValue = residentModel:GetAttribute(needName)
		if typeof(initialValue) == "number" then
			handleNeedValue(residentName, needName, initialValue)
		end
	end
	local destroyingConnection = residentModel.Destroying:Connect(function()
		disconnectResidentConnections(residentName)
	end)
	table.insert(connections, destroyingConnection)
	residentConnections[residentName] = connections
end

local function disconnectFolderConnections()
	for _, connection in ipairs(folderConnections) do
		if connection.Connected then
			connection:Disconnect()
		end
	end
	folderConnections = {}
end

local function setResidentsFolder(residentsFolder: Folder?)
	if currentResidentsFolder == residentsFolder then
		return
	end
	disconnectFolderConnections()
	currentResidentsFolder = residentsFolder
	if not residentsFolder then
		return
	end
	for _, child in ipairs(residentsFolder:GetChildren()) do
		if child:IsA("Model") then
			registerResidentModel(child)
		end
	end
	local addedConnection = residentsFolder.ChildAdded:Connect(function(instance)
		if instance:IsA("Model") then
			registerResidentModel(instance)
		end
	end)
	local removedConnection = residentsFolder.ChildRemoved:Connect(function(instance)
		if instance:IsA("Model") then
			cleanupResident(instance.Name)
		end
	end)
	folderConnections = { addedConnection, removedConnection }
end

local function resolveResidentsFolder(): Folder?
	local ownedPlotIndex = Player:GetAttribute("OwnedPlotIndex")
	if typeof(ownedPlotIndex) ~= "number" then
		return nil
	end
	local plotModel = PlotFinder.FindPlot(ownedPlotIndex)
	if not plotModel then
		return nil
	end
	local residentsFolder = plotModel:FindFirstChild("Residents")
	if residentsFolder and residentsFolder:IsA("Folder") then
		return residentsFolder
	end
	return nil
end

local function attemptBindResidentsFolder(): boolean
	local residentsFolder = resolveResidentsFolder()
	if not residentsFolder then
		return false
	end
	setResidentsFolder(residentsFolder)
	return true
end

local function handleResidentSnapshot(residentName: string, residentData: any)
	if typeof(residentData) ~= "table" then
		return
	end
	local needsTable = residentData.Needs
	if typeof(needsTable) ~= "table" then
		return
	end
	for _, needName in ipairs(NEED_NAMES) do
		local needValue = needsTable[needName]
		if typeof(needValue) == "number" then
			handleNeedValue(residentName, needName, needValue)
		end
	end
end

function NeedWarningNotifications.Init()
	local function checkPendingWarnings()
		processPendingWarnings()
	end

	ResidentSelectionFrame:GetPropertyChangedSignal("Visible"):Connect(function()
		if not ResidentSelectionFrame.Visible then
			clearTrackedHandles()
		else
			checkPendingWarnings()
		end
	end)

	ResidentNeedsUI.ResidentSelectionChanged:Connect(function(selectedResident: Model?)
		if selectedResident then
			clearTrackedHandles()
		else
			checkPendingWarnings()
		end
	end)

	if not attemptBindResidentsFolder() then
		local attributeConnection: RBXScriptConnection?
		attributeConnection = Player:GetAttributeChangedSignal("OwnedPlotIndex"):Connect(function()
			if attemptBindResidentsFolder() and attributeConnection then
				attributeConnection:Disconnect()
				attributeConnection = nil
			end
		end)
	end

	ResidentsStore.ResidentAdded:Connect(function(userId: number, residentData: any)
		if userId ~= Player.UserId then
			return
		end
		if typeof(residentData) ~= "table" then
			return
		end
		local residentName = residentData.Name
		if type(residentName) ~= "string" then
			return
		end
		handleResidentSnapshot(residentName, residentData)
	end)

	ResidentsStore.ResidentsUpdated:Connect(function(userId: number, updatedResidentData: any)
		if userId ~= Player.UserId then
			return
		end
		if typeof(updatedResidentData) ~= "table" then
			return
		end
		local residentName = updatedResidentData.Name
		if type(residentName) ~= "string" then
			return
		end
		handleResidentSnapshot(residentName, updatedResidentData)
	end)

	ResidentsStore.ResidentRemoved:Connect(function(userId: number, residentName: string)
		if userId ~= Player.UserId then
			return
		end
		if type(residentName) ~= "string" then
			return
		end
		cleanupResident(residentName)
	end)
end

return NeedWarningNotifications
