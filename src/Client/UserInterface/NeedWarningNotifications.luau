--!strict
-- StarterPlayerScripts/Client/UserInterface/NeedWarningNotifications.lua

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NeedConfig = require(ReplicatedStorage.Shared.Configurations.NeedConfig)
local PlotFinder = require(ReplicatedStorage.Shared.Utilities.PlotFinder)
local ResidentsStore = require(script.Parent.Parent.ClientStores.ResidentsStore)
local NotificationModule = require(script.Parent.Notification)

local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")
local ResidentGui = PlayerGui:WaitForChild("ResidentGui")

local NeedWarningNotifications = {}

local NEED_DEFINITIONS = NeedConfig.Needs
local NEED_NAMES: { string } = {}
for needName in pairs(NEED_DEFINITIONS) do
	table.insert(NEED_NAMES, needName)
end
table.sort(NEED_NAMES)

local NEED_LABEL_OVERRIDES: { [string]: string } = {
	Hunger = "hunger",
	Energy = "energy",
	Hygiene = "hygiene",
	Social = "social needs",
	Fun = "fun",
}

local SOUND_ID = "rbxassetid://109149869070031"
local TOAST_DURATION_SECONDS = 4.5
local NEED_PLACEMENT: NotificationModule.NotificationPlacement = {
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

type ResidentAlertState = {
	NeedZeroShown: { [string]: boolean },
	CollapseShown: boolean,
}

local residentStates: { [string]: ResidentAlertState } = {}
local residentConnections: { [string]: { RBXScriptConnection } } = {}
local folderConnections: { RBXScriptConnection } = {}
local currentResidentsFolder: Folder? = nil

local function getResidentState(residentName: string): ResidentAlertState
	local state = residentStates[residentName]
	if state then
		return state
	end
	local newState: ResidentAlertState = {
		NeedZeroShown = {},
		CollapseShown = false,
	}
	residentStates[residentName] = newState
	return newState
end

local function formatNeedLabel(needName: string): string
	local override = NEED_LABEL_OVERRIDES[needName]
	if override then
		return override
	end
	return string.lower(needName)
end

local function showToast(title: string, text: string, priority: number)
	NotificationModule.Show({
		Title = title,
		Text = text,
		BackgroundTransparency = 1,
		StrokeTransparency = 1,
		Duration = TOAST_DURATION_SECONDS,
		SoundId = SOUND_ID,
		Priority = priority,
		Placement = NEED_PLACEMENT,
	})
end

local function handleNeedValue(residentName: string, needName: string, value: any)
	if typeof(value) ~= "number" then
		return
	end
	local needDefinition = NEED_DEFINITIONS[needName]
	if not needDefinition then
		return
	end
	local state = getResidentState(residentName)
	local alreadyShown = state.NeedZeroShown[needName] == true
	local depleted = value <= needDefinition.Min
	if depleted then
		if not alreadyShown then
			local label = formatNeedLabel(needName)
			local message = string.format("%s has run out of %s.", residentName, label)
			showToast("Need Depleted", message, 1)
			state.NeedZeroShown[needName] = true
		end
	else
		state.NeedZeroShown[needName] = false
	end
end

local function handleCollapseChanged(residentName: string, isCollapsed: any)
	local active = isCollapsed == true
	local state = getResidentState(residentName)
	if active then
		if not state.CollapseShown then
			local message = string.format("%s collapsed from exhaustion.", residentName)
			showToast("Resident Collapsed", message, 2)
			state.CollapseShown = true
		end
	else
		state.CollapseShown = false
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
	residentStates[residentName] = nil
end

local function registerResidentModel(residentModel: Model)
	local residentName = residentModel.Name
	disconnectResidentConnections(residentName)

	local connections: { RBXScriptConnection } = {}

	local collapseConnection = residentModel:GetAttributeChangedSignal("EnergyCollapseActive"):Connect(function()
		local current = residentModel:GetAttribute("EnergyCollapseActive")
		handleCollapseChanged(residentName, current)
	end)
	table.insert(connections, collapseConnection)
	handleCollapseChanged(residentName, residentModel:GetAttribute("EnergyCollapseActive"))

	for _, needName in ipairs(NEED_NAMES) do
		local connection = residentModel:GetAttributeChangedSignal(needName):Connect(function()
			handleNeedValue(residentName, needName, residentModel:GetAttribute(needName))
		end)
		table.insert(connections, connection)
		handleNeedValue(residentName, needName, residentModel:GetAttribute(needName))
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
	if typeof(needsTable) == "table" then
		for _, needName in ipairs(NEED_NAMES) do
			local needValue = needsTable[needName]
			if typeof(needValue) == "number" then
				handleNeedValue(residentName, needName, needValue)
			end
		end
	end
	local collapseFlag = residentData.EnergyCollapseActive
	if collapseFlag ~= nil then
		handleCollapseChanged(residentName, collapseFlag)
	end
end

function NeedWarningNotifications.Init()
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
		local residentName = typeof(residentData) == "table" and residentData.Name or nil
		if type(residentName) ~= "string" then
			return
		end
		handleResidentSnapshot(residentName, residentData)
	end)

	ResidentsStore.ResidentsUpdated:Connect(function(userId: number, updatedResidentData: any)
		if userId ~= Player.UserId then
			return
		end
		local residentName = typeof(updatedResidentData) == "table" and updatedResidentData.Name or nil
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
