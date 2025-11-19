--!strict
-- StarterPlayerScripts/Client/Modules/TenantInteractionController.luau
-- Detects active renters on the player's plot, attaches eviction prompts, and drives the radial confirmation UI.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlotFinder = require(ReplicatedStorage.Shared.Utilities.PlotFinder)
local TenantPackets = require(ReplicatedStorage.Network.TenantPackets)
local ResidentsStore = require(script.Parent.Parent.ClientStores.ResidentsStore)
local MinimalPromptUI = require(script.Parent.MinimalPromptUI)
local TenantEvictionBillboard = require(script.Parent.Parent.UserInterface.TenantEvictionBillboard)

local LocalPlayer = Players.LocalPlayer
local LOCAL_USER_ID = LocalPlayer.UserId

local PROMPT_ACTION_TEXT = "Evict"
local PROMPT_NAME = "TenantEvictionPrompt"
local MAX_PROMPT_DISTANCE = 15
local PROMPT_OFFSET = Vector3.new(0, 0, 0)

export type ResidentDatum = {
	Name: string,
	TenantId: string?,
}

type TenantEntry = {
	TenantId: string,
	Resident: ResidentDatum,
}

type ModelRecord = {
	Model: Model,
	ResidentName: string,
	Prompt: ProximityPrompt?,
	Connections: { RBXScriptConnection },
	PromptConnections: { RBXScriptConnection },
	PromptSuppressed: boolean,
}

local TenantInteractionController = {}

local isInitialized = false
local residentsFolderConnections: { RBXScriptConnection } = {}
local modelRecordsByModel: { [Model]: ModelRecord } = {}
local modelByResidentName: { [string]: Model } = {}
local tenantEntries: { [string]: TenantEntry } = {}

local function disconnectConnections(connections: { RBXScriptConnection })
	for _, connection in ipairs(connections) do
		if connection.Connected then
			connection:Disconnect()
		end
	end
	table.clear(connections)
end

local function disposePrompt(record: ModelRecord)
	local prompt = record.Prompt
	if not prompt then
		return
	end
	record.Prompt = nil
	record.PromptSuppressed = false
	disconnectConnections(record.PromptConnections)
	MinimalPromptUI.Detach(prompt)
	prompt:Destroy()
end

local function cleanupRecord(record: ModelRecord)
	disposePrompt(record)
	disconnectConnections(record.Connections)
	modelRecordsByModel[record.Model] = nil
	if modelByResidentName[record.ResidentName] == record.Model then
		modelByResidentName[record.ResidentName] = nil
	end
	if TenantEvictionBillboard.IsVisibleFor(record.Model) then
		task.defer(TenantEvictionBillboard.Hide)
	end
end

local function findPromptParent(model: Model): Instance?
	local root = model:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		local attachment = root:FindFirstChild("TenantPrompt")
		if attachment and attachment:IsA("Attachment") then
			return attachment
		end
		local newAttachment = Instance.new("Attachment")
		newAttachment.Name = "TenantPrompt"
		newAttachment.Parent = root
		return newAttachment
	end
	local primary = model.PrimaryPart
	if primary then
		return primary
	end
	return model:FindFirstChildWhichIsA("BasePart")
end

local function showEvictionUi(record: ModelRecord, entry: TenantEntry)
	local model = record.Model
	if TenantEvictionBillboard.IsVisibleFor(model) then
		return
	end
	local tenantId = entry.TenantId
	if tenantId == "" then
		return
	end
	record.PromptSuppressed = true

	TenantEvictionBillboard.Show(model, {
		ResidentName = record.ResidentName,
		TenantLabel = entry.Resident.Name,
		OnCancel = function()
			record.PromptSuppressed = false
		end,
		OnConfirm = function()
			TenantEvictionBillboard.SetBusy(true, "Evicting tenant...")
			task.spawn(function()
				local ok, success, message = pcall(function()
					return TenantPackets.EvictTenantRequest:Fire(tenantId)
				end)
				TenantEvictionBillboard.SetBusy(false)
				if not ok then
					TenantEvictionBillboard.SetStatus("Connection lost, try again.", true)
					record.PromptSuppressed = false
					return
				end
				if not success then
					TenantEvictionBillboard.SetStatus(message or "Could not evict tenant.", true)
					record.PromptSuppressed = false
					return
				end
				TenantEvictionBillboard.SetStatus("Tenant eviction processed.")
				task.delay(1, function()
					record.PromptSuppressed = false
					if TenantEvictionBillboard.IsVisibleFor(model) then
						TenantEvictionBillboard.Hide()
					end
				end)
			end)
		end,
	})

	task.defer(function()
		record.PromptSuppressed = false
	end)
end

local function onPromptTriggered(record: ModelRecord)
	if TenantEvictionBillboard.IsVisibleFor(record.Model) then
		return
	end
	local entry = tenantEntries[record.ResidentName]
	if not entry then
		return
	end
	showEvictionUi(record, entry)
end

local function ensurePromptForRecord(record: ModelRecord)
	disposePrompt(record)
	local entry = tenantEntries[record.ResidentName]
	if not entry then
		if TenantEvictionBillboard.IsVisibleFor(record.Model) then
			TenantEvictionBillboard.Hide()
		end
		return
	end
	local parentInstance = findPromptParent(record.Model)
	if not parentInstance then
		return
	end

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = PROMPT_NAME
	prompt.ActionText = PROMPT_ACTION_TEXT
	prompt.ObjectText = record.ResidentName
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.RequiresLineOfSight = false
	prompt.MaxActivationDistance = MAX_PROMPT_DISTANCE
	prompt.Style = Enum.ProximityPromptStyle.Custom
	prompt.HoldDuration = 0
	prompt:SetAttribute("MinimalPromptOffset", PROMPT_OFFSET)
	prompt.Parent = parentInstance

	record.Prompt = prompt
	MinimalPromptUI.Attach(prompt)
	local promptConnection = prompt.Triggered:Connect(function(player: Player)
		if player ~= LocalPlayer then
			return
		end
		onPromptTriggered(record)
	end)
	record.PromptConnections[#record.PromptConnections + 1] = promptConnection
	record.PromptConnections[#record.PromptConnections + 1] = prompt.PromptHidden:Connect(function()
		if record.PromptSuppressed then
			return
		end
		if TenantEvictionBillboard.IsVisibleFor(record.Model) then
			task.defer(TenantEvictionBillboard.Hide)
		end
	end)
end

local function refreshResidentRecord(residentName: string)
	local model = modelByResidentName[residentName]
	if not model then
		return
	end
	local record = modelRecordsByModel[model]
	if not record then
		return
	end
	ensurePromptForRecord(record)
end

local function updateResidentMapping(record: ModelRecord, newName: string)
	if record.ResidentName == newName then
		return
	end
	if modelByResidentName[record.ResidentName] == record.Model then
		modelByResidentName[record.ResidentName] = nil
	end
	record.ResidentName = newName
	modelByResidentName[newName] = record.Model
	refreshResidentRecord(newName)
end

local function trackModel(model: Model)
	local residentNameValue = model:GetAttribute("ResidentName")
	local residentName = if type(residentNameValue) == "string" and residentNameValue ~= ""
		then residentNameValue
		else model.Name

	local record: ModelRecord = {
		Model = model,
		ResidentName = residentName,
		Prompt = nil,
		Connections = {},
		PromptConnections = {},
		PromptSuppressed = false,
	}

	modelRecordsByModel[model] = record
	modelByResidentName[residentName] = model

	record.Connections[#record.Connections + 1] = model.Destroying:Connect(function()
		cleanupRecord(record)
	end)

	record.Connections[#record.Connections + 1] = model.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			cleanupRecord(record)
		end
	end)

	record.Connections[#record.Connections + 1] = model:GetAttributeChangedSignal("ResidentName"):Connect(function()
		local updatedNameValue = model:GetAttribute("ResidentName")
		local updatedName = if type(updatedNameValue) == "string" and updatedNameValue ~= ""
			then updatedNameValue
			else model.Name
		updateResidentMapping(record, updatedName)
	end)

	ensurePromptForRecord(record)
end

local function untrackAllModels()
	for _, record in pairs(modelRecordsByModel) do
		cleanupRecord(record)
	end
	modelRecordsByModel = {}
	modelByResidentName = {}
end

local function bindResidentsFolder(folder: Instance?)
	disconnectConnections(residentsFolderConnections)
	untrackAllModels()
	TenantEvictionBillboard.Hide()

	if not folder then
		return
	end

	for _, child in ipairs(folder:GetChildren()) do
		if child:IsA("Model") then
			trackModel(child)
		end
	end

	residentsFolderConnections[#residentsFolderConnections + 1] = folder.ChildAdded:Connect(function(child)
		if child:IsA("Model") then
			trackModel(child)
		end
	end)

	residentsFolderConnections[#residentsFolderConnections + 1] = folder.ChildRemoved:Connect(function(child)
		if not child:IsA("Model") then
			return
		end
		local record = modelRecordsByModel[child]
		if record then
			cleanupRecord(record)
		end
	end)

	residentsFolderConnections[#residentsFolderConnections + 1] = folder.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			bindResidentsFolder(nil)
		end
	end)
end

local function rebindPlotResidents()
	local plotIndex = LocalPlayer:GetAttribute("OwnedPlotIndex")
	if typeof(plotIndex) ~= "number" then
		bindResidentsFolder(nil)
		return
	end

	local plotModel = PlotFinder.FindPlot(plotIndex)
	if not plotModel then
		bindResidentsFolder(nil)
		return
	end

	local residentsFolder = plotModel:FindFirstChild("Residents")
	if residentsFolder and residentsFolder:IsA("Folder") then
		bindResidentsFolder(residentsFolder)
		return
	end

	local awaiting: RBXScriptConnection?
	awaiting = plotModel.ChildAdded:Connect(function(child)
		if child.Name == "Residents" and child:IsA("Folder") then
			if awaiting and awaiting.Connected then
				awaiting:Disconnect()
			end
			bindResidentsFolder(child)
		end
	end)

	if awaiting then
		residentsFolderConnections[#residentsFolderConnections + 1] = awaiting
	end
end

local function applyResidentEntry(residentData: ResidentDatum)
	local residentName = residentData.Name
	if type(residentName) ~= "string" or residentName == "" then
		return
	end
	local tenantIdValue = residentData.TenantId
	local tenantId = if type(tenantIdValue) == "string" and tenantIdValue ~= "" then tenantIdValue else nil
	if tenantId then
		tenantEntries[residentName] = {
			TenantId = tenantId,
			Resident = residentData,
		}
	else
		tenantEntries[residentName] = nil
	end
	refreshResidentRecord(residentName)
end

local function onResidentAdded(_userId: number, residentData: any)
	if type(residentData) ~= "table" then
		return
	end
	applyResidentEntry(residentData :: ResidentDatum)
end

local function onResidentRemoved(_userId: number, residentName: string)
	tenantEntries[residentName] = nil
	refreshResidentRecord(residentName)
end

local function primeTenantEntries()
	local currentResidents = ResidentsStore.GetResidents(LocalPlayer.UserId)
	if not currentResidents then
		return
	end
	for _, residentData in pairs(currentResidents) do
		applyResidentEntry(residentData :: ResidentDatum)
	end
end

function TenantInteractionController.Init()
	if isInitialized then
		return
	end
	isInitialized = true

	TenantEvictionBillboard.Init()
	primeTenantEntries()
	rebindPlotResidents()

	LocalPlayer:GetAttributeChangedSignal("OwnedPlotIndex"):Connect(rebindPlotResidents)

	ResidentsStore.ResidentAdded:Connect(function(userId: number, residentData: any)
		if userId ~= LOCAL_USER_ID then
			return
		end
		onResidentAdded(userId, residentData)
	end)

	ResidentsStore.ResidentsUpdated:Connect(function(userId: number, residentData: any)
		if userId ~= LOCAL_USER_ID then
			return
		end
		onResidentAdded(userId, residentData)
	end)

	ResidentsStore.ResidentRemoved:Connect(function(userId: number, residentName: string)
		if userId ~= LOCAL_USER_ID then
			return
		end
		onResidentRemoved(userId, residentName)
	end)
end

return TenantInteractionController
