--!strict
-- StarterPlayerScripts/Client/Modules/TenantProspectController.luau
-- Renders roaming tenant prospects and wires up accept/decline UI.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local TenantPackets = require(ReplicatedStorage.Network.TenantPackets)
local PlotFinder = require(ReplicatedStorage.Shared.Utilities.PlotFinder)
local TenantProspectPrompt = require(script.Parent.Parent.UserInterface.TenantProspectPrompt)
local MinimalPromptUI = require(script.Parent.MinimalPromptUI)
local PlotStateStore = require(script.Parent.Parent.ClientStores.PlotStateStore)
local RoomQuery = require(script.Parent.RoomQuery)

local LocalPlayer = Players.LocalPlayer
local AssetsFolder = ReplicatedStorage:FindFirstChild("Assets")
local ResidentTemplatesFolder = AssetsFolder and AssetsFolder:FindFirstChild("Residents")

local SLOT_PART_PREFIX = "TenantProspectSlot"
local PROMPT_ACTION = "Meet"
local MAX_PROMPT_DISTANCE = 18
local TARGET_ATTRIBUTE_PREFIX = "TenantProspectTarget"
local DEFAULT_TEMPLATE_NAME = "Male"
local DISABLE_RESIDENT_BILLBOARD_ATTR = "DisableResidentBillboard"
local ESCORT_CHECK_INTERVAL = 0.2
local ESCORT_SUBMIT_COOLDOWN = 1

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
local ModelPool: { Model } = {}
local ActiveEscortState: {
	ProspectId: string,
	Payload: ProspectSpawnPayload,
	LastRoomId: number?,
	LastRoomKey: string?,
	LastSubmitTime: number,
	Submitting: boolean,
}?
local EscortHeartbeat: RBXScriptConnection?
local LastEscortCheck = 0

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

local function stopEscortHeartbeat()
	if EscortHeartbeat then
		EscortHeartbeat:Disconnect()
		EscortHeartbeat = nil
	end
end

local function hideEscortBannerLater(delaySeconds: number)
	if delaySeconds <= 0 then
		TenantProspectPrompt.HideEscortBanner()
		return
	end
	task.delay(delaySeconds, function()
		TenantProspectPrompt.HideEscortBanner()
	end)
end

local function submitEscortRoom(roomKey: string)
	local state = ActiveEscortState
	if not state or state.Submitting then
		return
	end
	state.Submitting = true
	TenantProspectPrompt.ShowEscortBanner("Reviewing that room...", false)
	task.spawn(function()
		local ok, success, message = pcall(function()
			return TenantPackets.ProspectDecision:Fire(state.ProspectId, "Accept", roomKey)
		end)
		local current = ActiveEscortState
		if not current or current.ProspectId ~= state.ProspectId then
			return
		end
		state.Submitting = false
		if not ok then
			TenantProspectPrompt.ShowEscortBanner("Connection lost, step inside again.", true)
			state.LastRoomKey = nil
			return
		end
		if success then
			TenantProspectPrompt.ShowEscortBanner(message or "Tenant moved in!", false)
			emitDecisionEmoji(state.ProspectId, "Accept")
			ActiveEscortState = nil
			stopEscortHeartbeat()
			hideEscortBannerLater(2.4)
		else
			local rejectionMessage = message or "That room isn't tenant-ready yet."
			TenantProspectPrompt.ShowEscortBanner(rejectionMessage, true)
			state.LastRoomKey = nil
		end
	end)
end

local function updateEscortTracking()
	local state = ActiveEscortState
	if not state then
		stopEscortHeartbeat()
		return
	end
	local now = os.clock()
	if now - LastEscortCheck < ESCORT_CHECK_INTERVAL then
		return
	end
	LastEscortCheck = now

	local character = LocalPlayer.Character
	local root = character and character.PrimaryPart
	if not root then
		return
	end

	local grid = PlotStateStore.GetGrid()
	if not grid then
		return
	end

	local pos = root.Position
	local inBounds, cellX, cellZ = grid:WorldPointToCell(pos)
	if not inBounds then
		return
	end

	local floorHeight = PlotStateStore.GetFloorHeightStuds()
	local originY = grid.OriginTopCFrame.Position.Y
	local level = math.max(0, math.floor(((pos.Y - originY) / floorHeight) + 0.5))

	-- Use simple room query - single source of truth from server
	local currentRoom = RoomQuery.FindRoomAtPosition(level, cellX, cellZ, false)
	if not currentRoom or not currentRoom.RoomKey then
		return
	end

	local roomKey = currentRoom.RoomKey
	if roomKey == state.LastRoomKey then
		return
	end
	if now - state.LastSubmitTime < ESCORT_SUBMIT_COOLDOWN then
		return
	end

	print(string.format("[Client] Escort: Room %s at (%d,%d)", roomKey, cellX, cellZ))
	state.LastRoomKey = roomKey
	state.LastSubmitTime = now
	submitEscortRoom(roomKey)
end

local function ensureEscortHeartbeat()
	if EscortHeartbeat then
		return
	end
	LastEscortCheck = 0
	EscortHeartbeat = RunService.Heartbeat:Connect(updateEscortTracking)
end

local function beginEscort(payload: ProspectSpawnPayload)
	ActiveEscortState = nil
	stopEscortHeartbeat()
	ActiveEscortState = {
		ProspectId = payload.ProspectId,
		Payload = payload,
		LastRoomId = nil,
		LastRoomKey = nil,
		LastSubmitTime = 0,
		Submitting = false,
	}
	TenantProspectPrompt.Hide()
	TenantProspectPrompt.ShowEscortBanner(
		string.format("%s is following you. Step into any furnished room to assign it.", payload.Name),
		false
	)
	ensureEscortHeartbeat()
end

local function getPooledRig(): Model?
	local pooled = table.remove(ModelPool)
	if pooled then
		return pooled
	end

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

local function returnPooledRig(model: Model)
	model.Parent = nil

	-- Cleanup added instances
	local highlight = model:FindFirstChild("TenantProspectHighlight")
	if highlight then
		highlight:Destroy()
	end

	local emoji = model:FindFirstChild("TenantDecisionEmoji")
	if emoji then
		emoji:Destroy()
	end

	local rootPart = model:FindFirstChild("HumanoidRootPart")
	if rootPart then
		local attachment = rootPart:FindFirstChild("TenantPromptAttachment")
		if attachment then
			attachment:Destroy()
		end
		rootPart.Anchored = false
	end

	table.insert(ModelPool, model)
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
		returnPooledRig(record.Model)
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
					return TenantPackets.ProspectDecision:Fire(payload.ProspectId, "Accept", "")
				end)
				TenantProspectPrompt.SetBusy(false)
				if not ok then
					TenantProspectPrompt.SetStatus("Connection lost, try again.", true)
					return
				end
				if not success then
					local statusMessage = message or "Could not invite tenant."
					TenantProspectPrompt.SetStatus(statusMessage, true)
					return
				end
				local lowerMessage = string.lower(message or "")
				if lowerMessage == "escortstart" then
					beginEscort(payload)
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
					return TenantPackets.ProspectDecision:Fire(payload.ProspectId, "Decline", "")
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
	local rig = getPooledRig()
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

local function describeRemovalReason(reason: string?): string
	local lower = string.lower(reason or "")
	if lower == "expired" then
		return "They got impatient and wandered off."
	elseif lower == "declined" then
		return "You declined the offer."
	elseif lower == "escorttimeout" then
		return "They left because it took too long to pick a room."
	elseif lower == "escortcancelled" then
		return "Escort cancelled."
	elseif lower == "cleanup" then
		return "They left with the plot."
	end
	return "The tenant decided to leave."
end

local function onProspectRemoved(payload)
	local reason = payload.Reason or ""
	if ActiveEscortState and ActiveEscortState.ProspectId == payload.ProspectId then
		if string.lower(reason) == "accepted" then
			TenantProspectPrompt.ShowEscortBanner("Tenant settled in!", false)
			hideEscortBannerLater(2.2)
		else
			TenantProspectPrompt.ShowEscortBanner(describeRemovalReason(reason), true)
			hideEscortBannerLater(2.2)
		end
		ActiveEscortState = nil
		stopEscortHeartbeat()
	end
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

	-- Clear RoomQuery cache when rooms change to ensure accurate detection
	PlotStateStore.OnRoomSnapshotChanged(function()
		RoomQuery.ClearCache()
	end)

	TenantPackets.ProspectSpawn.OnClientEvent:Connect(function(payload)
		spawnProspect(payload :: ProspectSpawnPayload)
	end)

	TenantPackets.ProspectRemoved.OnClientEvent:Connect(onProspectRemoved)
	TenantPackets.ProspectPrompt.OnClientEvent:Connect(function(payload)
		showPrompt(payload :: ProspectSpawnPayload)
	end)
end

-- Get prospect position for seamless tenant handoff
function TenantProspectController.GetProspectPosition(prospectId: string): CFrame?
	local record = ProspectVisualsById[prospectId]
	if not record or not record.Model then
		return nil
	end
	return record.Model:GetPivot()
end

-- Remove prospect model (called by ResidentController for seamless handoff)
function TenantProspectController.RemoveProspect(prospectId: string)
	destroyProspect(prospectId)
end

return TenantProspectController
