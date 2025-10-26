--!strict
-- StarterPlayerScripts/Client/UserInterface/ShiftStatusPanel.luau
-- Displays a compact career status summary for the selected resident.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ResidentNeedsUI = require(script.Parent.ResidentNeedsUI)
local ShiftStatusFormatter = require(script.Parent.Parent.Modules.ShiftStatusFormatter)
local ResidentsStore = require(script.Parent.Parent.ClientStores.ResidentsStore)

local Network = ReplicatedStorage:WaitForChild("Network")
local JobPackets = require(Network:WaitForChild("JobPackets"))

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")
local ResidentGui = PlayerGui:WaitForChild("ResidentGui")
local ResidentSelectionFrame = ResidentGui:WaitForChild("ResidentSelectionFrame")

local STATUS_COLORS = ShiftStatusFormatter.GetStatusColors()
local STATUS_DEFAULT_COLOR = STATUS_COLORS.Idle
local GO_TO_WORK_COLOR = Color3.fromRGB(82, 199, 107)
local GO_HOME_COLOR = Color3.fromRGB(220, 98, 86)
local SHIFT_ACTION_ATTRIBUTE = "ShiftAction"
local SHIFT_ACTION_GO_TO_WORK = "GoToWork"
local SHIFT_ACTION_GO_HOME = "GoHome"

local ShiftStatusPanel = {}

local panelFrame: Frame?
local nameLabel: TextLabel?
local jobLabel: TextLabel?
local statusLabel: TextLabel?
local toggleButton: TextButton?
local wantPanelVisible = false
local currentModel: Model? = nil
local currentResidentName: string? = nil
local modelConnections: { RBXScriptConnection } = {}
local residentSnapshots: { [string]: any } = {}
local shiftActionInFlight = false
local lastStatus: ShiftStatusFormatter.StatusResult? = nil
local handleShiftToggle: () -> () = function() end

local function disconnectModelConnections()
	for _, connection in ipairs(modelConnections) do
		if connection.Connected then
			connection:Disconnect()
		end
	end
	modelConnections = {}
end

local function getOffsiteFolder(): Folder?
	local container = ReplicatedStorage:FindFirstChild("ResidentOffsite")
	if container and container:IsA("Folder") then
		return container
	end
	return nil
end

local function isResidentOffsite(model: Model?): boolean
	local container = getOffsiteFolder()
	return model ~= nil and container ~= nil and model.Parent == container
end

local function showShiftToast(_residentName: string, _message: string, _color: Color3)
	-- Shift notifications disabled (no-op).
end

local function showShiftFailure(_residentName: string, _message: string)
	-- Shift notifications disabled (no-op).
end

local function resolveMessage(message: string?, fallback: string): string
	if type(message) == "string" then
		local trimmed = message:match("^%s*(.-)%s*$")
		if trimmed and trimmed ~= "" then
			return trimmed
		end
	end
	return fallback
end

local function refreshShiftToggle(status: ShiftStatusFormatter.StatusResult?)
	if not toggleButton then
		return
	end
	if not currentModel or not status then
		toggleButton.Visible = false
		toggleButton.Active = false
		toggleButton:SetAttribute(SHIFT_ACTION_ATTRIBUTE, nil)
		toggleButton.Text = ""
		toggleButton.BackgroundTransparency = 0
		toggleButton.TextTransparency = 0
		return
	end

	local action: string? = nil
	local label = ""
	local background = GO_TO_WORK_COLOR
	if status.state == "OnShift" then
		action = SHIFT_ACTION_GO_HOME
		label = "Go Home"
		background = GO_HOME_COLOR
	elseif status.state == "WindowOpen" then
		action = SHIFT_ACTION_GO_TO_WORK
		label = "Go To Work"
		background = GO_TO_WORK_COLOR
	end

	if not action then
		toggleButton.Visible = false
		toggleButton.Active = false
		toggleButton:SetAttribute(SHIFT_ACTION_ATTRIBUTE, nil)
		toggleButton.Text = ""
		toggleButton.BackgroundTransparency = 0
		toggleButton.TextTransparency = 0
		return
	end

	toggleButton.Visible = true
	toggleButton.Text = label
	toggleButton.BackgroundColor3 = background
	toggleButton.TextColor3 = Color3.new(1, 1, 1)
	toggleButton:SetAttribute(SHIFT_ACTION_ATTRIBUTE, action)
	toggleButton.AutoButtonColor = false

	local canTrigger = not shiftActionInFlight
	if action == SHIFT_ACTION_GO_HOME then
		canTrigger = canTrigger and isResidentOffsite(currentModel)
	end

	toggleButton.Active = canTrigger
	toggleButton.BackgroundTransparency = if canTrigger then 0 else 0.35
	toggleButton.TextTransparency = if canTrigger then 0 else 0.35
end

local function setShiftActionInFlight(inFlight: boolean)
	if shiftActionInFlight == inFlight then
		return
	end
	shiftActionInFlight = inFlight
	refreshShiftToggle(lastStatus)
end

local function ensurePanel()
	if panelFrame then
		return
	end

	local panel = Instance.new("Frame")
	panel.Name = "ShiftStatusPanel"
	panel.BackgroundTransparency = 1
	panel.BorderSizePixel = 0
	panel.Size = UDim2.fromScale(0.2, 0.207)
	panel.Position = UDim2.fromScale(0, 0.105)
	panel.Visible = false
	panel.ZIndex = 5
	panel.Parent = ResidentGui

	local content = Instance.new("Frame")
	content.Name = "Content"
	content.AnchorPoint = Vector2.new(0, 0)
	content.Position = UDim2.new(0, 0, 0, 0)
	content.Size = UDim2.fromScale(1, 1)
	content.BackgroundTransparency = 1
	content.Parent = panel

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 12)
	padding.PaddingRight = UDim.new(0, 12)
	padding.PaddingTop = UDim.new(0, 4)
	padding.PaddingBottom = UDim.new(0, 4)
	padding.Parent = content

	local layout = Instance.new("UIListLayout")
	layout.Name = "Layout"
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	layout.VerticalAlignment = Enum.VerticalAlignment.Top
	layout.Padding = UDim.new(0, 6)
	layout.Parent = content

	local residentNameLabel = Instance.new("TextLabel")
	residentNameLabel.Name = "ResidentName"
	residentNameLabel.LayoutOrder = 1
	residentNameLabel.AutomaticSize = Enum.AutomaticSize.Y
	residentNameLabel.BackgroundTransparency = 1
	residentNameLabel.Size = UDim2.fromScale(1, 0)
	residentNameLabel.Font = Enum.Font.GothamBold
	residentNameLabel.TextSize = 20
	residentNameLabel.TextColor3 = Color3.new(1, 1, 1)
	residentNameLabel.TextXAlignment = Enum.TextXAlignment.Left
	residentNameLabel.TextYAlignment = Enum.TextYAlignment.Center
	residentNameLabel.TextWrapped = true
	residentNameLabel.Text = ""
	residentNameLabel.Parent = content

	local careerLabel = Instance.new("TextLabel")
	careerLabel.Name = "CareerName"
	careerLabel.LayoutOrder = 2
	careerLabel.AutomaticSize = Enum.AutomaticSize.Y
	careerLabel.BackgroundTransparency = 1
	careerLabel.Size = UDim2.fromScale(1, 0)
	careerLabel.Font = Enum.Font.GothamMedium
	careerLabel.TextSize = 16
	careerLabel.TextColor3 = Color3.fromRGB(235, 240, 255)
	careerLabel.TextXAlignment = Enum.TextXAlignment.Left
	careerLabel.TextYAlignment = Enum.TextYAlignment.Center
	careerLabel.TextWrapped = true
	careerLabel.Text = ""
	careerLabel.Parent = content

	local shiftLabel = Instance.new("TextLabel")
	shiftLabel.Name = "ShiftSummary"
	shiftLabel.LayoutOrder = 3
	shiftLabel.AutomaticSize = Enum.AutomaticSize.Y
	shiftLabel.BackgroundTransparency = 1
	shiftLabel.Size = UDim2.fromScale(1, 0)
	shiftLabel.Font = Enum.Font.Gotham
	shiftLabel.TextSize = 15
	shiftLabel.TextColor3 = Color3.new(1, 1, 1)
	shiftLabel.TextXAlignment = Enum.TextXAlignment.Left
	shiftLabel.TextYAlignment = Enum.TextYAlignment.Center
	shiftLabel.TextWrapped = true
	shiftLabel.Text = ""
	shiftLabel.Parent = content

	local shiftToggle = Instance.new("TextButton")
	shiftToggle.Name = "ShiftToggleButton"
	shiftToggle.LayoutOrder = 4
	shiftToggle.Size = UDim2.new(1, 0, 0, 32)
	shiftToggle.AutoButtonColor = false
	shiftToggle.BackgroundColor3 = GO_TO_WORK_COLOR
	shiftToggle.BackgroundTransparency = 0
	shiftToggle.Text = ""
	shiftToggle.TextColor3 = Color3.new(1, 1, 1)
	shiftToggle.Font = Enum.Font.GothamBold
	shiftToggle.TextSize = 16
	shiftToggle.Visible = false
	shiftToggle.Parent = content

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = shiftToggle

	shiftToggle.Activated:Connect(function()
		handleShiftToggle()
	end)

	panelFrame = panel
	nameLabel = residentNameLabel
	jobLabel = careerLabel
	statusLabel = shiftLabel
	toggleButton = shiftToggle
	refreshShiftToggle(lastStatus)
end

local function setPanelVisible(isVisible: boolean)
	ensurePanel()
	wantPanelVisible = isVisible
	if panelFrame then
		panelFrame.Visible = isVisible and ResidentSelectionFrame.Visible
	end
end

local function getSnapshot(residentName: string): any?
	local snapshot = residentSnapshots[residentName]
	if snapshot then
		return snapshot
	end
	local fetched = ResidentsStore.GetResident(nil, residentName)
	if fetched then
		residentSnapshots[residentName] = fetched
	end
	return fetched
end

local function updatePanel()
	ensurePanel()
	if not panelFrame or not nameLabel or not jobLabel or not statusLabel then
		return
	end
	if not currentModel or not currentModel.Parent then
		refreshShiftToggle(nil)
		setPanelVisible(false)
		return
	end

	local residentName = currentResidentName or currentModel.Name
	if type(residentName) ~= "string" or residentName == "" then
		refreshShiftToggle(nil)
		setPanelVisible(false)
		return
	end

	local snapshot = getSnapshot(residentName)
	local status = ShiftStatusFormatter.Compute(snapshot, currentModel)
	local statusColor = status and status.color or STATUS_DEFAULT_COLOR
	local emoji = nil
	if status and status.jobId then
		emoji = ShiftStatusFormatter.GetCareerEmoji(status.jobId)
	end
	if not emoji and snapshot then
		emoji = ShiftStatusFormatter.GetCareerEmoji(snapshot.CurrentCareerId)
	end

	nameLabel.Text = if emoji and emoji ~= "" then string.format("%s %s", emoji, residentName) else residentName

	local resolvedJobName = status and status.jobName
	local jobName: string
	if resolvedJobName and resolvedJobName ~= "" then
		jobName = resolvedJobName
	else
		local snapshotJobId = snapshot and snapshot.CurrentCareerId
		jobName = ShiftStatusFormatter.GetJobName(snapshotJobId) or "No career selected"
	end
	jobLabel.Text = jobName

	local statusText = status and status.text
	if not statusText or statusText == "" then
		statusText = "No upcoming shift."
	end
	statusLabel.Text = statusText
	statusLabel.TextColor3 = statusColor
	lastStatus = status
	refreshShiftToggle(status)

	setPanelVisible(true)
end

local function handleShiftToggleImpl()
	if not toggleButton or shiftActionInFlight then
		return
	end
	local actionValue = toggleButton:GetAttribute(SHIFT_ACTION_ATTRIBUTE)
	if type(actionValue) ~= "string" then
		return
	end
	local residentName = currentResidentName
	if type(residentName) ~= "string" or residentName == "" then
		return
	end

	if actionValue == SHIFT_ACTION_GO_HOME and not isResidentOffsite(currentModel) then
		showShiftFailure(residentName, "Resident has not left for work yet.")
		refreshShiftToggle(lastStatus)
		return
	end

	setShiftActionInFlight(true)
	task.spawn(function()
		local success: boolean
		local message: string
		if actionValue == SHIFT_ACTION_GO_TO_WORK then
			success, message = JobPackets.StartResidentShift:Fire(residentName)
			if success then
				local text = resolveMessage(message, "Resident is heading to work.")
				showShiftToast(residentName, text, GO_TO_WORK_COLOR)
			else
				local failure = resolveMessage(message, "Could not start the shift.")
				showShiftFailure(residentName, failure)
			end
		else
			local _penalty
			success, message, _penalty = JobPackets.StopResidentShift:Fire(residentName)
			if success then
				local text = resolveMessage(message, "Calling resident back home.")
				showShiftToast(residentName, text, GO_HOME_COLOR)
			else
				local failure = resolveMessage(message, "Could not recall the resident.")
				showShiftFailure(residentName, failure)
			end
		end
		setShiftActionInFlight(false)
		updatePanel()
	end)
end

handleShiftToggle = handleShiftToggleImpl

local function setCurrentModel(model: Model?)
	if currentModel == model then
		updatePanel()
		return
	end

	disconnectModelConnections()
	currentModel = model
	currentResidentName = if model then model.Name else nil

	if not model then
		lastStatus = nil
		shiftActionInFlight = false
		refreshShiftToggle(nil)
		setPanelVisible(false)
		return
	end

	modelConnections = {
		model:GetAttributeChangedSignal("IsOnShift"):Connect(updatePanel),
		model:GetAttributeChangedSignal("WorkingJobId"):Connect(updatePanel),
		model:GetAttributeChangedSignal("AssignedShiftId"):Connect(updatePanel),
		model.Destroying:Connect(function()
			setCurrentModel(nil)
		end),
		model.AncestryChanged:Connect(function()
			updatePanel()
		end),
	}

	updatePanel()
end

function ShiftStatusPanel.Init()
	ensurePanel()
	ResidentNeedsUI.ResidentSelectionChanged:Connect(function(model)
		if typeof(model) == "Instance" and model:IsA("Model") then
			setCurrentModel(model)
		else
			setCurrentModel(nil)
		end
	end)

	ResidentSelectionFrame:GetPropertyChangedSignal("Visible"):Connect(function()
		if not ResidentSelectionFrame.Visible then
			if panelFrame then
				panelFrame.Visible = false
			end
		elseif wantPanelVisible then
			updatePanel()
		end
	end)

	ResidentsStore.ResidentAdded:Connect(function(userId: number, residentData: any)
		if userId ~= LocalPlayer.UserId then
			return
		end
		if type(residentData.Name) ~= "string" then
			return
		end
		residentSnapshots[residentData.Name] = residentData
		if residentData.Name == currentResidentName then
			updatePanel()
		end
	end)

	ResidentsStore.ResidentsUpdated:Connect(function(userId: number, residentData: any)
		if userId ~= LocalPlayer.UserId then
			return
		end
		if type(residentData.Name) ~= "string" then
			return
		end
		residentSnapshots[residentData.Name] = residentData
		if residentData.Name == currentResidentName then
			updatePanel()
		end
	end)

	ResidentsStore.ResidentRemoved:Connect(function(userId: number, residentName: string)
		if userId ~= LocalPlayer.UserId then
			return
		end
		residentSnapshots[residentName] = nil
		if residentName == currentResidentName then
			setCurrentModel(nil)
		end
	end)
end

return ShiftStatusPanel
