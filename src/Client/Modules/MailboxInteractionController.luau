--!strict
-- Handles proximity prompt for collecting mailbox rent and keeps prompt text in sync with balance.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlotFinder = require(ReplicatedStorage.Shared.Utilities.PlotFinder)
local Formatter = require(ReplicatedStorage.Shared.Utilities.Formatter)
local MailboxPackets = require(ReplicatedStorage.Network.MailboxPackets)
local PromptWidgetBinder = require(script.Parent.PromptWidgetBinder)
local MailboxCashEffect = require(script.Parent.Parent.UserInterface.MailboxCashEffect)

local LocalPlayer = Players.LocalPlayer

local MailboxInteractionController = {}

local RESIDENTS_FOLDER_NAME = "Residents"
local MAILBOX_ATTRIBUTE_NAME = "MailboxBalance"
local MAILBOX_NAME = "Mailbox"
local PROMPT_NAME = "MailboxCollectPrompt"
local PROMPT_OBJECT_TEXT = "Mailbox"
local COLLECTION_TEMPLATE = "Collect: %s"
local EMPTY_ACTION_TEXT = "Mailbox Empty"
local BUSY_ACTION_TEXT = "Collecting..."
local MAX_PROMPT_DISTANCE = 7
local MAX_BALANCE = 4294967295

local MAILBOX_BILLBOARD_NAME = "BillboardGui"
local MAILBOX_LABEL_NAME = "TimeTextLabel"

local CURRENCY_DISPLAY_OPTIONS = {
	currencySymbol = "$",
	decimalPlaces = 0,
	useCommas = true,
}

local controllerInitialized = false

local currentPlotIndex: number? = nil
local currentPlotModel: Model? = nil

local plotConnections: { RBXScriptConnection } = {}
local plotAncestryConnection: RBXScriptConnection? = nil

local residentsFolder: Folder? = nil
local residentsConnections: { RBXScriptConnection } = {}

local mailboxPart: BasePart? = nil
local mailboxAncestryConnection: RBXScriptConnection? = nil

local promptInstance: ProximityPrompt? = nil
local promptConnections: { RBXScriptConnection } = {}
local promptCreatedByController = false

local mailboxLabel: TextLabel? = nil
local mailboxLabelConnections: { RBXScriptConnection } = {}

local currentBalance = 0
local isCollecting = false

local function disconnectConnectionList(connectionList: { RBXScriptConnection })
	for _, connection in ipairs(connectionList) do
		connection:Disconnect()
	end
	table.clear(connectionList)
end

local function clampBalance(value: number): number
	local numericValue = math.floor(value + 0.5)

	if numericValue < 0 then
		numericValue = 0
	elseif numericValue > MAX_BALANCE then
		numericValue = MAX_BALANCE
	end

	return numericValue
end

local function getMailboxLabelFromMailboxPart(part: BasePart?): TextLabel?
	if not part then
		return nil
	end

	local billboardGui = part:FindFirstChild(MAILBOX_BILLBOARD_NAME)
	if not billboardGui or not billboardGui:IsA("BillboardGui") then
		return nil
	end

	local label = billboardGui:FindFirstChild(MAILBOX_LABEL_NAME)
	if label and label:IsA("TextLabel") then
		return label
	end

	return nil
end

local function refreshDisplays()
	local formattedAmount = Formatter.formatCurrency(currentBalance, CURRENCY_DISPLAY_OPTIONS)
	local collectText = string.format(COLLECTION_TEMPLATE, formattedAmount)

	local prompt = promptInstance
	if prompt then
		if isCollecting then
			prompt.ActionText = BUSY_ACTION_TEXT
		elseif currentBalance > 0 then
			prompt.ActionText = collectText
		else
			prompt.ActionText = EMPTY_ACTION_TEXT
		end

		prompt.ObjectText = PROMPT_OBJECT_TEXT
		prompt.Enabled = true

		PromptWidgetBinder.Refresh(prompt)
	end

	local label = mailboxLabel
	if label then
		label.Text = collectText
	end
end

local function setBalance(value: number)
	currentBalance = clampBalance(value)
	refreshDisplays()
end

local function setBalanceFromAttribute(value: any)
	if typeof(value) == "number" then
		setBalance(value)
	else
		setBalance(0)
	end
end

local function disconnectPrompt()
	disconnectConnectionList(promptConnections)

	if promptInstance then
		PromptWidgetBinder.Detach(promptInstance)

		if promptCreatedByController then
			promptInstance:Destroy()
		end
	end

	promptInstance = nil
	promptCreatedByController = false
end

local function disconnectMailboxLabel()
	disconnectConnectionList(mailboxLabelConnections)
	mailboxLabel = nil
end

local function bindMailboxLabelFromPart(part: BasePart?)
	disconnectMailboxLabel()

	if not part then
		refreshDisplays()
		return
	end

	local label = getMailboxLabelFromMailboxPart(part)
	if not label then
		refreshDisplays()
		return
	end

	mailboxLabel = label

	mailboxLabelConnections[#mailboxLabelConnections + 1] = label.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			disconnectMailboxLabel()
			refreshDisplays()
		end
	end)

	refreshDisplays()
end

local function configurePrompt(prompt: ProximityPrompt)
	prompt.Name = PROMPT_NAME
	prompt.ActionText = EMPTY_ACTION_TEXT
	prompt.ObjectText = PROMPT_OBJECT_TEXT
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.RequiresLineOfSight = false
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = MAX_PROMPT_DISTANCE
	prompt.Style = Enum.ProximityPromptStyle.Custom
end

local function attachPromptToPart(part: BasePart)
	if promptInstance and promptInstance.Parent == part then
		refreshDisplays()
		return
	end

	disconnectPrompt()

	local prompt: ProximityPrompt
	local createdByController = false

	local existingPrompt = part:FindFirstChild(PROMPT_NAME)
	if existingPrompt and existingPrompt:IsA("ProximityPrompt") then
		prompt = existingPrompt
	else
		prompt = Instance.new("ProximityPrompt")
		prompt.Parent = part
		createdByController = true
	end

	configurePrompt(prompt)

	promptInstance = prompt
	promptCreatedByController = createdByController

	PromptWidgetBinder.Attach(prompt)
	refreshDisplays()

	promptConnections[#promptConnections + 1] = prompt.Destroying:Connect(function()
		if promptInstance == prompt then
			disconnectPrompt()
		end
	end)

	promptConnections[#promptConnections + 1] = prompt.Triggered:Connect(function(player)
		if player ~= LocalPlayer then
			return
		end

		if isCollecting then
			return
		end

		isCollecting = true
		refreshDisplays()

		task.spawn(function()
			local wasCallSuccessful, wasRequestAccepted, _, rejectionMessage = pcall(function()
				return MailboxPackets.CollectRequest:Fire()
			end)

			if not wasCallSuccessful then
				warn("Mailbox collect request failed:", wasRequestAccepted)
			elseif not wasRequestAccepted then
				if typeof(rejectionMessage) == "string" and rejectionMessage ~= "" then
					warn("Mailbox collect rejected:", rejectionMessage)
				end
			end

			isCollecting = false
			refreshDisplays()
		end)
	end)
end

local function findMailboxBasePart(instance: Instance?): BasePart?
	if not instance then
		return nil
	end

	if instance:IsA("BasePart") then
		return instance
	end

	if instance:IsA("Model") then
		local model = instance :: Model
		if model.PrimaryPart then
			return model.PrimaryPart
		end
	end

	return instance:FindFirstChildWhichIsA("BasePart", true)
end

local function locateMailboxPart(plotModel: Model?): BasePart?
	if not plotModel then
		return nil
	end

	local directMailboxInstance = plotModel:FindFirstChild(MAILBOX_NAME)
	if directMailboxInstance then
		local part = findMailboxBasePart(directMailboxInstance)
		if part then
			return part
		end
	end

	local recursiveMailboxInstance = plotModel:FindFirstChild(MAILBOX_NAME, true)
	if recursiveMailboxInstance then
		local part = findMailboxBasePart(recursiveMailboxInstance)
		if part then
			return part
		end
	end

	return nil
end

local function bindMailboxPart(part: BasePart?)
	if mailboxAncestryConnection then
		mailboxAncestryConnection:Disconnect()
		mailboxAncestryConnection = nil
	end

	if not part then
		mailboxPart = nil
		disconnectPrompt()
		disconnectMailboxLabel()
		refreshDisplays()
		return
	end

	if mailboxPart ~= part then
		disconnectPrompt()
	end

	mailboxPart = part

	bindMailboxLabelFromPart(part)

	mailboxAncestryConnection = part.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			bindMailboxPart(nil)
		end
	end)

	attachPromptToPart(part)
end

local function setResidentsFolder(folder: Folder?)
	if residentsFolder == folder then
		if folder then
			setBalanceFromAttribute(folder:GetAttribute(MAILBOX_ATTRIBUTE_NAME))
		end
		return
	end

	disconnectConnectionList(residentsConnections)
	residentsFolder = folder

	if not folder then
		setBalance(0)
		return
	end

	residentsConnections[#residentsConnections + 1] = folder
		:GetAttributeChangedSignal(MAILBOX_ATTRIBUTE_NAME)
		:Connect(function()
			setBalanceFromAttribute(folder:GetAttribute(MAILBOX_ATTRIBUTE_NAME))
		end)

	residentsConnections[#residentsConnections + 1] = folder.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			setResidentsFolder(nil)
		end
	end)

	setBalanceFromAttribute(folder:GetAttribute(MAILBOX_ATTRIBUTE_NAME))
end

local function disconnectPlotConnections()
	disconnectConnectionList(plotConnections)

	if plotAncestryConnection then
		plotAncestryConnection:Disconnect()
		plotAncestryConnection = nil
	end

	if mailboxAncestryConnection then
		mailboxAncestryConnection:Disconnect()
		mailboxAncestryConnection = nil
	end

	disconnectMailboxLabel()
	currentPlotModel = nil
end

local function bindPlot(plotIndex: number?)
	if currentPlotIndex == plotIndex and currentPlotModel ~= nil then
		return
	end

	currentPlotIndex = plotIndex

	disconnectPlotConnections()
	setResidentsFolder(nil)
	bindMailboxPart(nil)

	if typeof(plotIndex) ~= "number" then
		return
	end

	local plotModel = PlotFinder.FindPlot(plotIndex)
	if not plotModel then
		task.defer(function()
			if currentPlotIndex == plotIndex then
				bindPlot(plotIndex)
			end
		end)
		return
	end

	currentPlotModel = plotModel

	plotAncestryConnection = plotModel.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			bindPlot(nil)
		end
	end)

	plotConnections[#plotConnections + 1] = plotModel.ChildAdded:Connect(function(child)
		if child:IsA("Folder") and child.Name == RESIDENTS_FOLDER_NAME then
			setResidentsFolder(child)
		elseif child.Name == MAILBOX_NAME then
			bindMailboxPart(locateMailboxPart(plotModel))
		end
	end)

	plotConnections[#plotConnections + 1] = plotModel.ChildRemoved:Connect(function(child)
		if child == residentsFolder then
			setResidentsFolder(nil)
		end

		if child.Name == MAILBOX_NAME then
			bindMailboxPart(locateMailboxPart(plotModel))
		end
	end)

	local residents = plotModel:FindFirstChild(RESIDENTS_FOLDER_NAME)
	if residents and residents:IsA("Folder") then
		setResidentsFolder(residents)
	end

	bindMailboxPart(locateMailboxPart(plotModel))
end

function MailboxInteractionController.Init()
	if controllerInitialized then
		return
	end

	controllerInitialized = true

	MailboxCashEffect.Init()

	bindPlot(LocalPlayer:GetAttribute("OwnedPlotIndex") :: number?)

	LocalPlayer:GetAttributeChangedSignal("OwnedPlotIndex"):Connect(function()
		bindPlot(LocalPlayer:GetAttribute("OwnedPlotIndex") :: number?)
	end)

	MailboxPackets.BalanceUpdate.OnClientEvent:Connect(function(payload)
		if typeof(payload) ~= "table" then
			return
		end

		local balance = payload.Balance
		if typeof(balance) == "number" then
			setBalance(balance)
		end
	end)
end

return MailboxInteractionController
