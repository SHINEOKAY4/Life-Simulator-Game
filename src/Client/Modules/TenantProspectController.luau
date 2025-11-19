--!strict
-- StarterPlayerScripts/Client/Modules/TenantProspectController.luau
-- Renders roaming tenant prospects and wires up accept/decline UI.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local TenantPackets = require(ReplicatedStorage.Network.TenantPackets)
local PlotFinder = require(ReplicatedStorage.Shared.Utilities.PlotFinder)
local TenantProspectPrompt = require(script.Parent.Parent.UserInterface.TenantProspectPrompt)
local MinimalPromptUI = require(script.Parent.MinimalPromptUI)

local LocalPlayer = Players.LocalPlayer
local AssetsFolder = ReplicatedStorage:FindFirstChild("Assets")
local ResidentTemplatesFolder = AssetsFolder and AssetsFolder:FindFirstChild("Residents")

local SLOT_PART_PREFIX = "TenantProspectSlot"
local PROMPT_ACTION = "Meet"
local MAX_PROMPT_DISTANCE = 18
local TARGET_ATTRIBUTE_PREFIX = "TenantProspectTarget"
local DEFAULT_TEMPLATE_NAME = "Male"
local DISABLE_RESIDENT_BILLBOARD_ATTR = "DisableResidentBillboard"

export type ProspectSpawnPayload = {
	ProspectId: string,
	Slot: number,
	Name: string,
	TierId: string,
	RentPerInterval: number,
	RentIntervalSeconds: number,
	Deposit: number?,
	LeaseSeconds: number,
	RentBoostPercent: number?,
	Traits: { string }?,
}

local TenantProspectController = {}

local ResidentsFolder: Folder?
local ResidentsFolderConn: RBXScriptConnection?
local ActivePromptId: string?
local IsInitialized = false

local ProspectVisualsById: { [string]: any } = {}
local ProspectVisualsBySlot: { [number]: any } = {}

local DECISION_EMOJIS = {
	Accept = {
		Text = "🎉",
		Color = Color3.fromRGB(90, 200, 120),
	},
	Decline = {
		Text = "💤",
		Color = Color3.fromRGB(200, 120, 120),
	},
}

local function emitDecisionEmoji(prospectId: string, decision: "Accept" | "Decline")
	local record = ProspectVisualsById[prospectId]
	if not record then
		return
	end
	local rootPart = record.RootPart :: BasePart?
	if not rootPart then
		return
	end
	local config = DECISION_EMOJIS[decision]
	if not config then
		return
	end

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "TenantDecisionEmoji"
	billboard.AlwaysOnTop = true
	billboard.Size = UDim2.fromOffset(48, 48)
	billboard.MaxDistance = 60
	billboard.StudsOffsetWorldSpace = Vector3.new(0, 4, 0)
	billboard.Adornee = rootPart
	billboard.Parent = record.Model

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.Text = config.Text
	label.TextColor3 = config.Color
	label.Size = UDim2.fromScale(1, 1)
	label.Parent = billboard

	local fadeInfo = TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local tween = TweenService:Create(label, fadeInfo, { TextTransparency = 1 })

	task.delay(1.2, function()
		if not billboard.Parent then
			return
		end
		tween:Play()
		task.delay(fadeInfo.Time + 0.05, function()
			if billboard.Parent then
				billboard:Destroy()
			end
		end)
	end)
end

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
		MinimalPromptUI.Detach(record.Prompt)
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

local function showPrompt(payload: ProspectSpawnPayload)
	ActivePromptId = payload.ProspectId

	local record = ProspectVisualsById[payload.ProspectId]
	local model = record and record.Model

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
				emitDecisionEmoji(payload.ProspectId, "Accept")
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
				emitDecisionEmoji(payload.ProspectId, "Decline")
				TenantProspectPrompt.Hide()
			end)
		end,
		OnClosed = function()
			if ActivePromptId == payload.ProspectId then
				ActivePromptId = nil
			end
		end,
	}, model)
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
	prompt.Style = Enum.ProximityPromptStyle.Custom

	local promptParent: Instance = slotPart
	local rootPart = record.RootPart :: BasePart?
	if rootPart then
		local attachment = rootPart:FindFirstChild("TenantPromptAttachment")
		local promptAttachment: Attachment
		if attachment and attachment:IsA("Attachment") then
			promptAttachment = attachment
		else
			promptAttachment = Instance.new("Attachment")
			promptAttachment.Name = "TenantPromptAttachment"
			promptAttachment.CFrame = CFrame.new()
			promptAttachment.Parent = rootPart
		end
		promptParent = promptAttachment
	end

	prompt.Parent = promptParent

	-- Center prompt at model origin
	prompt:SetAttribute("MinimalPromptOffset", Vector3.new(0, 0, 0))

	MinimalPromptUI.Attach(prompt)

	record.Prompt = prompt
	record.Connections[#record.Connections + 1] = prompt.Triggered:Connect(function(player)
		if player ~= LocalPlayer then
			return
		end
		showPrompt(payload)
	end)

	record.Connections[#record.Connections + 1] = prompt.PromptHidden:Connect(function()
		if ActivePromptId == payload.ProspectId and TenantProspectPrompt.IsVisible() then
			TenantProspectPrompt.Hide()
		end
	end)
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
	rig:SetAttribute(DISABLE_RESIDENT_BILLBOARD_ATTR, true)
	humanoid.WalkSpeed = 8
	humanoid.JumpPower = 0
	humanoid.UseJumpPower = true

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
