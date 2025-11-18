--!strict
-- StarterPlayerScripts/Client/Modules/TenantProspectController.luau
-- Renders roaming tenant prospects and wires up accept/decline UI.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TenantPackets = require(ReplicatedStorage.Network.TenantPackets)
local PlotFinder = require(ReplicatedStorage.Shared.Utilities.PlotFinder)
local Formatter = require(ReplicatedStorage.Shared.Utilities.Formatter)
local TenantProspectPrompt = require(script.Parent.Parent.UserInterface.TenantProspectPrompt)
local PromptWidgetBinder = require(script.Parent.PromptWidgetBinder)

local LocalPlayer = Players.LocalPlayer
local AssetsFolder = ReplicatedStorage:FindFirstChild("Assets")
local ResidentTemplatesFolder = AssetsFolder and AssetsFolder:FindFirstChild("Residents")

local SLOT_PART_PREFIX = "TenantProspectSlot"
local PROMPT_ACTION = "Meet Prospect"
local MAX_PROMPT_DISTANCE = 18
local TARGET_ATTRIBUTE_PREFIX = "TenantProspectTarget"
local DEFAULT_TEMPLATE_NAME = "Male"

export type ProspectSpawnPayload = {
	ProspectId: string,
	Slot: number,
	Name: string,
	TierId: string,
	RentPerInterval: number,
	RentIntervalSeconds: number,
	Deposit: number?,
	LeaseSeconds: number,
}

local TenantProspectController = {}

local ResidentsFolder: Folder?
local ResidentsFolderConn: RBXScriptConnection?
local ActivePromptId: string?
local IsInitialized = false

local ProspectVisualsById: { [string]: any } = {}
local ProspectVisualsBySlot: { [number]: any } = {}

local function cloneProspectRig(): Model?
	if not ResidentTemplatesFolder then
		return nil
	end
	local template = ResidentTemplatesFolder:FindFirstChild(DEFAULT_TEMPLATE_NAME)
	if not (template and template:IsA("Model")) then
		template = ResidentTemplatesFolder:FindFirstChildWhichIsA("Model")
	end
	if not template then
		warn("TenantProspectController: missing resident template model")
		return nil
	end
	return template:Clone()
end

local function destroyProspect(id: string)
	local record = ProspectVisualsById[id]
	if not record then
		return
	end

	ProspectVisualsById[id] = nil
	if ProspectVisualsBySlot[record.Slot] == record then
		ProspectVisualsBySlot[record.Slot] = nil
	end

	if record.Connections then
		for _, connection in ipairs(record.Connections) do
			connection:Disconnect()
		end
	end

	if record.Prompt then
		PromptWidgetBinder.Detach(record.Prompt)
		record.Prompt:Destroy()
	end

	if record.Model then
		record.Model:Destroy()
	end

	if ActivePromptId == id and TenantProspectPrompt.IsVisible() then
		TenantProspectPrompt.Hide()
	end
end

local function destroyAllProspects()
	for id in pairs(ProspectVisualsById) do
		destroyProspect(id)
	end
	ProspectVisualsById = {}
	ProspectVisualsBySlot = {}
end

local function getResidentsFolder(): Folder?
	if ResidentsFolder and ResidentsFolder.Parent then
		return ResidentsFolder
	end

	local plotIndex = LocalPlayer:GetAttribute("OwnedPlotIndex")
	if typeof(plotIndex) ~= "number" then
		ResidentsFolder = nil
		return nil
	end

	local plotModel = PlotFinder.FindPlot(plotIndex)
	if not plotModel then
		ResidentsFolder = nil
		return nil
	end

	local folder = plotModel:FindFirstChild("Residents")
	if not folder then
		folder = plotModel:WaitForChild("Residents", 5)
	end

	if folder and folder:IsA("Folder") then
		ResidentsFolder = folder
		if ResidentsFolderConn then
			ResidentsFolderConn:Disconnect()
		end
		ResidentsFolderConn = folder.AncestryChanged:Connect(function(_, parent)
			if parent ~= nil then
				return
			end
			ResidentsFolder = nil
			destroyAllProspects()
		end)
		return folder
	end

	return nil
end

local function formatInterval(seconds: number): string
	if seconds < 60 then
		return string.format("%ds", math.floor(seconds + 0.5))
	end
	if seconds % 60 == 0 then
		local minutes = math.floor(seconds / 60)
		if minutes < 60 then
			return string.format("%d min", minutes)
		end
	end
	return Formatter.formatDuration(seconds, {
		units = { "hour", "minute" },
		shortUnits = true,
		maxUnits = 2,
	})
end

local function showPrompt(payload: ProspectSpawnPayload)
	ActivePromptId = payload.ProspectId

	TenantProspectPrompt.Show(payload, {
		OnAccept = function()
			ActivePromptId = payload.ProspectId
			TenantProspectPrompt.SetBusy(true, "Inviting tenant...")
			task.spawn(function()
				local ok, success, message = pcall(function()
					return TenantPackets.ProspectDecision:Fire(payload.ProspectId, "Accept")
				end)
				TenantProspectPrompt.SetBusy(false)
				if not ok then
					TenantProspectPrompt.SetStatus("Connection lost, try again.", true)
					return
				end
				if not success then
					TenantProspectPrompt.SetStatus(message or "Could not invite tenant.", true)
					return
				end
				TenantProspectPrompt.Hide()
			end)
		end,
		OnDecline = function()
			ActivePromptId = payload.ProspectId
			TenantProspectPrompt.SetBusy(true, "Letting them know...")
			task.spawn(function()
				local ok, success, message = pcall(function()
					return TenantPackets.ProspectDecision:Fire(payload.ProspectId, "Decline")
				end)
				TenantProspectPrompt.SetBusy(false)
				if not ok then
					TenantProspectPrompt.SetStatus("Could not reach server.", true)
					return
				end
				if not success then
					TenantProspectPrompt.SetStatus(message or "Decline failed.", true)
					return
				end
				TenantProspectPrompt.Hide()
			end)
		end,
		OnClosed = function()
			if ActivePromptId == payload.ProspectId then
				ActivePromptId = nil
			end
		end,
	})
end

local function attachPrompt(record, payload)
	local slotPart = record.SlotPart
	if not slotPart then
		return
	end

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "TenantProspectInteraction"
	prompt.ActionText = PROMPT_ACTION
	prompt.ObjectText = payload.Name
	prompt.MaxActivationDistance = MAX_PROMPT_DISTANCE
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.RequiresLineOfSight = false
	prompt.HoldDuration = 0
	prompt.Parent = slotPart
	PromptWidgetBinder.Attach(prompt)

	record.Prompt = prompt
	record.Connections[#record.Connections + 1] = prompt.Triggered:Connect(function(player)
		if player ~= LocalPlayer then
			return
		end
		showPrompt(payload)
	end)
end

local function createBillboard(root: BasePart, payload: ProspectSpawnPayload)
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "TenantProspectBillboard"
	billboard.AlwaysOnTop = true
	billboard.LightInfluence = 0
	billboard.Size = UDim2.fromOffset(200, 60)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, 4.25, 0)
	billboard.MaxDistance = 60
	billboard.Parent = root

	local container = Instance.new("Frame")
	container.BackgroundColor3 = Color3.fromRGB(28, 32, 44)
	container.BackgroundTransparency = 0.2
	container.AutomaticSize = Enum.AutomaticSize.XY
	container.Size = UDim2.fromOffset(0, 0)
	container.Parent = billboard

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = container

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 10)
	padding.PaddingRight = UDim.new(0, 10)
	padding.PaddingTop = UDim.new(0, 6)
	padding.PaddingBottom = UDim.new(0, 6)
	padding.Parent = container

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "Name"
	nameLabel.BackgroundTransparency = 1
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	nameLabel.TextSize = 16
	nameLabel.AutomaticSize = Enum.AutomaticSize.XY
	nameLabel.Text = payload.Name
	nameLabel.Parent = container

	local rentLabel = Instance.new("TextLabel")
	rentLabel.Name = "Rent"
	rentLabel.BackgroundTransparency = 1
	rentLabel.Font = Enum.Font.Gotham
	rentLabel.TextColor3 = Color3.fromRGB(200, 210, 244)
	rentLabel.TextSize = 14
	rentLabel.AutomaticSize = Enum.AutomaticSize.XY
	rentLabel.TextYAlignment = Enum.TextYAlignment.Top
	rentLabel.Text = string.format(
		"%s / %s",
		Formatter.formatCurrency(payload.RentPerInterval, {
			currencySymbol = "$",
		}),
		formatInterval(payload.RentIntervalSeconds)
	)
	rentLabel.Parent = container

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.VerticalAlignment = Enum.VerticalAlignment.Top
	layout.Parent = container
end

local function createProspectModel(payload: ProspectSpawnPayload, slotPart: BasePart): any
	local rig = cloneProspectRig()
	if not rig then
		return nil
	end
	local humanoid = rig:FindFirstChildOfClass("Humanoid")
	local rootPart = rig:FindFirstChild("HumanoidRootPart")
	if not (humanoid and rootPart and rootPart:IsA("BasePart")) then
		rig:Destroy()
		warn("TenantProspectController: template missing humanoid or HumanoidRootPart")
		return nil
	end
	rootPart.Anchored = false
	rig.Name = string.format("TenantProspect_%s", payload.ProspectId)
	rig.PrimaryPart = rootPart

	createBillboard(rootPart, payload)

	local highlight = Instance.new("Highlight")
	highlight.Name = "TenantProspectHighlight"
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.FillColor = Color3.fromRGB(140, 190, 255)
	highlight.FillTransparency = 0.85
	highlight.OutlineTransparency = 1
	highlight.Adornee = rig
	highlight.Parent = rig

	local record = {
		Id = payload.ProspectId,
		Slot = payload.Slot,
		Payload = payload,
		Model = rig,
		Humanoid = humanoid,
		RootPart = rootPart,
		SlotPart = slotPart,
		TargetAttribute = string.format("%s%d", TARGET_ATTRIBUTE_PREFIX, payload.Slot),
		Connections = {} :: { RBXScriptConnection },
		Prompt = nil :: ProximityPrompt?,
	}

	record.Connections[#record.Connections + 1] = slotPart.Destroying:Connect(function()
		destroyProspect(payload.ProspectId)
	end)

	return record
end

local function applyTarget(record)
	local folder = ResidentsFolder
	if not folder then
		return
	end
	local target = folder:GetAttribute(record.TargetAttribute)
	if typeof(target) ~= "Vector3" then
		return
	end
	record.Humanoid:MoveTo(target)
end

local function bindTargetUpdates(record)
	local folder = ResidentsFolder
	if not folder then
		return
	end
	record.Connections[#record.Connections + 1] = folder
		:GetAttributeChangedSignal(record.TargetAttribute)
		:Connect(function()
			applyTarget(record)
		end)
	applyTarget(record)
end

local function spawnProspect(payload: ProspectSpawnPayload)
	local folder = getResidentsFolder()
	if not folder then
		return
	end

	local slotName = string.format("%s%d", SLOT_PART_PREFIX, payload.Slot)
	local slotPart = folder:FindFirstChild(slotName)
	if not slotPart then
		slotPart = folder:WaitForChild(slotName, 5)
	end
	if not slotPart or not slotPart:IsA("BasePart") then
		return
	end

	destroyProspect(payload.ProspectId)

	local record = createProspectModel(payload, slotPart)
	if not record then
		return
	end
	record.Model.Parent = folder
	record.Model:PivotTo(slotPart.CFrame)
	record.Humanoid.AutoRotate = true
	record.Humanoid:MoveTo(slotPart.Position)
	ProspectVisualsById[payload.ProspectId] = record
	ProspectVisualsBySlot[payload.Slot] = record

	attachPrompt(record, payload)
	bindTargetUpdates(record)
end

local function onProspectRemoved(payload)
	destroyProspect(payload.ProspectId)
end

local function onOwnedPlotChanged()
	destroyAllProspects()
	ResidentsFolder = nil
	getResidentsFolder()
end

function TenantProspectController.Init()
	if IsInitialized then
		return
	end
	IsInitialized = true

	getResidentsFolder()

	LocalPlayer:GetAttributeChangedSignal("OwnedPlotIndex"):Connect(onOwnedPlotChanged)

	TenantPackets.ProspectSpawn.OnClientEvent:Connect(function(payload)
		spawnProspect(payload :: ProspectSpawnPayload)
	end)

	TenantPackets.ProspectRemoved.OnClientEvent:Connect(onProspectRemoved)
	TenantPackets.ProspectPrompt.OnClientEvent:Connect(function(payload)
		showPrompt(payload :: ProspectSpawnPayload)
	end)
end

return TenantProspectController
