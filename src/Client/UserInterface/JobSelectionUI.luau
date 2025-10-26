--!strict
-- StarterPlayerScripts/Client/UserInterface/JobSelectionUI.lua

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ResidentNeedsUI = require(script.Parent.ResidentNeedsUI)
local GigManager = require(script.Parent.Parent.Modules.GigManager)
local JobPackets = require(ReplicatedStorage.Network.JobPackets)
local JobCatalog = require(ReplicatedStorage.Shared.Configurations.JobCatalog)
local CareerShiftConfig = require(ReplicatedStorage.Shared.Configurations.CareerShiftConfig)
local Timer = require(ReplicatedStorage.Shared.Utilities.Timer)
local Debounce = require(ReplicatedStorage.Shared.Utilities.Debounce)

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")
local JobSelectionGui = PlayerGui:WaitForChild("JobSelectionGui")

local ActiveQueryFolder = PlayerGui:FindFirstChild("ActiveQuery")
local JobSelectionUIEnabled = ActiveQueryFolder:FindFirstChild("JobSelectionUIEnabled") :: BoolValue
local PlotBuilderEnabled = ActiveQueryFolder:FindFirstChild("PlotBuilderEnabled") :: BoolValue
local PlotExpansionEnabled = ActiveQueryFolder:FindFirstChild("PlotExpansionEnabled") :: BoolValue
local PlotGridOverlayEnabled = ActiveQueryFolder:FindFirstChild("PlotGridOverlayEnabled") :: BoolValue
local ResidualUIEnabled = ActiveQueryFolder:FindFirstChild("ResidentUIEnabled") :: BoolValue

local JobListingsFolder = Workspace:WaitForChild("JobListings") :: Folder
local AssetFolder = ReplicatedStorage:WaitForChild("Assets") :: Folder
local InterfacesTemplateFolder = AssetFolder:WaitForChild("InterfacesTemplates") :: Folder
local Container = JobSelectionGui.Container
local Header = Container:FindFirstChild("Header")
local DetailPanel = Container.Body.DetailPanel
local ListContainer = Container.Body.ListContainer

local CareerTemplate = InterfacesTemplateFolder:FindFirstChild("CareerTemplate") :: TextButton
local GigTemplate = InterfacesTemplateFolder:FindFirstChild("GigTemplate") :: TextButton
local JobListScrollingFrame = ListContainer.JobList

local JobSelectionContext = JobSelectionGui:WaitForChild("JobSelectionContext")

local BlurEffect = Lighting:FindFirstChild("Blur")

local InputContext = Instance.new("InputContext")
InputContext.Name = "JobSelectionContext"
InputContext.Parent = PlayerGui

local JobSelectionUI = {}
local INPUT_DEBOUNCE_SECONDS = 0.25

local function runDebounced(actionName: string, callback: () -> ()): ()
	local key = string.format("JobSelectionUI/%s", actionName)
	Debounce.RunIfAvailable(key, INPUT_DEBOUNCE_SECONDS, callback, LocalPlayer.UserId)
end

type JobFolder = Folder & {
	GetAttribute: (JobFolder, string) -> any,
}

type JobInfo = JobCatalog.JobEntry
type ShiftTemplate = CareerShiftConfig.ShiftTemplate
type TimerInstance = Timer.TimerInstance

type CardMetadata = {
	Button: TextButton,
	Action: InputAction,
	Connections: { RBXScriptConnection },
	Folder: JobFolder,
}

local activeCards: { [JobFolder]: CardMetadata } = {}
local selectedCard: TextButton? = nil

local catalogJobs = JobCatalog.Jobs :: { JobInfo }
local jobsById: { [string]: JobInfo } = {}
for _, job in ipairs(catalogJobs) do
	jobsById[job.Id] = job
end

local DAY_NAMES = {
	"Sun",
	"Mon",
	"Tue",
	"Wed",
	"Thu",
	"Fri",
	"Sat",
}

local function formatClockTime(clockTime: number?): string?
	if typeof(clockTime) ~= "number" then
		return nil
	end
	local totalMinutes = math.floor(clockTime * 60 + 0.5)
	local hours24 = math.floor(totalMinutes / 60) % 24
	local minutes = totalMinutes % 60
	local period = if hours24 >= 12 then "PM" else "AM"
	local hour12 = hours24 % 12
	if hour12 == 0 then
		hour12 = 12
	end
	return string.format("%d:%02d %s", hour12, minutes, period)
end

local function summarizeShift(template: ShiftTemplate?): (string?, string?)
	if not template then
		return nil, nil
	end
	local label = template.Label ~= "" and template.Label or template.Id
	local startText = formatClockTime(template.StartClockTime)
	local endText = formatClockTime(template.EndClockTime)
	local shortSummary = nil
	if startText and endText then
		shortSummary = string.format("%s · %s–%s", label, startText, endText)
	elseif startText then
		shortSummary = string.format("%s · Starts %s", label, startText)
	else
		shortSummary = label
	end
	local detailSummary = shortSummary
	local days = template.Days
	if type(days) == "table" and #days > 0 then
		local sortedDays = table.create(#days)
		for index, dayNumber in ipairs(days) do
			sortedDays[index] = dayNumber
		end
		table.sort(sortedDays)
		local names = table.create(#sortedDays)
		for index, dayNumber in ipairs(sortedDays) do
			local dayName = DAY_NAMES[(dayNumber % 7) + 1] or tostring(dayNumber)
			names[index] = dayName
		end
		local dayText = table.concat(names, ", ")
		if startText and endText then
			detailSummary = string.format("%s • %s–%s (%s)", label, startText, endText, dayText)
		else
			detailSummary = string.format("%s (%s)", shortSummary or label, dayText)
		end
	end
	return shortSummary, detailSummary
end

local function getShiftTemplateFromFolder(jobFolder: JobFolder): ShiftTemplate?
	local shiftIdAttr = jobFolder:GetAttribute("ShiftId")
	if type(shiftIdAttr) ~= "string" or shiftIdAttr == "" then
		return nil
	end
	return CareerShiftConfig.GetShift(shiftIdAttr)
end

local function getShiftSummaries(jobFolder: JobFolder): (string?, string?)
	local template = getShiftTemplateFromFolder(jobFolder)
	return summarizeShift(template)
end

local function getJobInfo(jobId: string): JobInfo?
	return jobsById[jobId]
end

local function getJobDisplayType(jobInfo: JobInfo): string
	if jobInfo.Type == "Profession" then
		return "Career"
	end
	return jobInfo.Type
end

local CooldownLabel = if Header then Header:FindFirstChild("CooldownTitle") :: TextLabel? else nil

local restockTimer: TimerInstance? = nil
local restockSecondConnection: RBXScriptConnection? = nil
local restockEndedConnection: RBXScriptConnection? = nil

local function setCooldownText(text: string)
	if CooldownLabel then
		CooldownLabel.Text = text
	end
end

local function cleanupRestockTimer()
	if restockSecondConnection then
		restockSecondConnection:Disconnect()
		restockSecondConnection = nil
	end
	if restockEndedConnection then
		restockEndedConnection:Disconnect()
		restockEndedConnection = nil
	end
	if restockTimer then
		restockTimer:Cancel()
		restockTimer = nil
	end
end

local function formatCountdown(seconds: number): string
	local wholeSeconds = math.max(0, math.floor(seconds + 0.5))
	local hours = math.floor(wholeSeconds / 3600)
	local minutes = math.floor((wholeSeconds % 3600) / 60)
	local secs = wholeSeconds % 60
	if hours > 0 then
		return string.format("%d:%02d:%02d", hours, minutes, secs)
	end
	if minutes > 0 then
		return string.format("%d:%02d", minutes, secs)
	end
	return string.format("%ds", secs)
end

local function startCooldownTimer(nextRestock: number?)
	cleanupRestockTimer()
	if typeof(nextRestock) ~= "number" or nextRestock <= 0 then
		setCooldownText("Next Restock: Unknown")
		return
	end
	local remaining = math.max(0, nextRestock - os.time())
	if remaining <= 0 then
		setCooldownText("Restocking…")
		return
	end
	local timer = Timer.new()
	restockTimer = timer
	setCooldownText(string.format("Next Openings In: %s", formatCountdown(remaining)))
	restockSecondConnection = timer:OnSecond(function(seconds: number)
		setCooldownText(string.format("Next Openings In: %s", formatCountdown(seconds)))
	end)
	restockEndedConnection = timer:OnEnded(function()
		setCooldownText("Restocking…")
		cleanupRestockTimer()
	end)
	timer:Start(remaining)
end

local function syncCooldownFromAttributes()
	local nextRestockAttr = JobListingsFolder:GetAttribute("NextRestock")
	if typeof(nextRestockAttr) == "number" then
		startCooldownTimer(nextRestockAttr)
	else
		startCooldownTimer(nil)
	end
end

local function destroyCard(metadata: CardMetadata)
	for _, connection in metadata.Connections do
		connection:Disconnect()
	end
	metadata.Action:Destroy()
	metadata.Button:Destroy()
end

local function clearCards()
	for _, metadata in activeCards do
		destroyCard(metadata)
	end
	table.clear(activeCards)
	selectedCard = nil
end

local function getRequirementsLabel()
	local requirementsFrame = DetailPanel:FindFirstChild("Requirements")
	if not requirementsFrame then
		return nil
	end
	return requirementsFrame:FindFirstChildWhichIsA("TextLabel")
end

local function describeRequirements(requirements: { { Stat: string, Level: number } }): string
	if #requirements == 0 then
		return "No stat requirements. All residents welcome!"
	end
	local parts = table.create(#requirements)
	for index, requirement in requirements do
		parts[index] = string.format("%s ≥ %d", requirement.Stat, requirement.Level)
	end
	return table.concat(parts, " • ")
end

local function updateDetailPanel(jobInfo: JobInfo, jobFolder: JobFolder)
	DetailPanel.Title.Text = jobInfo.Name
	DetailPanel.Description.Text = jobInfo.Description or ""

	local shiftShort, shiftDetail = getShiftSummaries(jobFolder)
	local highlightText = jobInfo.Highlight or ""
	if shiftDetail then
		if highlightText ~= "" then
			highlightText = string.format("%s\nShift: %s", highlightText, shiftDetail)
		else
			highlightText = string.format("Shift: %s", shiftDetail)
		end
	end
	DetailPanel.Highlight.Text = highlightText
	local jobTypeAttr = jobFolder:GetAttribute("Type")
	local rawJobType = if type(jobTypeAttr) == "string" then jobTypeAttr else getJobDisplayType(jobInfo)
	local displayJobType = if rawJobType == "Profession" then "Career" else tostring(rawJobType)
	local basePay = tostring(jobInfo.BasePay)
	local payUnit = tostring(jobInfo.PayUnit)
	local subtitle = string.format("%s • %s per %s", displayJobType, basePay, payUnit)
	if shiftShort then
		subtitle = string.format("%s • %s", subtitle, shiftShort)
	end
	DetailPanel.Subtitle.Text = subtitle
	DetailPanel.ApplyButton.Text = if jobTypeAttr == "Profession" then "Apply Now" else "Start Gig"
	local requirementsLabel = getRequirementsLabel()
	if requirementsLabel then
		requirementsLabel.Text = describeRequirements(jobInfo.Requirements)
	end
end

local function markSelection(button: TextButton)
	if selectedCard == button then
		return
	end
	if selectedCard then
		selectedCard:SetAttribute("Selected", false)
	end
	selectedCard = button
	button:SetAttribute("Selected", true)
end

local function updateCardText(jobFolder: JobFolder, jobCard: TextButton, jobInfo: JobInfo)
	local blurb = jobCard:FindFirstChild("Blurb") :: TextLabel
	local pay = jobCard:FindFirstChild("Pay") :: TextLabel
	local title = jobCard:FindFirstChild("Title") :: TextLabel
	local availableSlots = jobCard:FindFirstChild("AvailableSlots") :: TextLabel
	local basePay = tostring(jobInfo.BasePay)
	local payUnit = tostring(jobInfo.PayUnit)
	local maxSlots = jobFolder:GetAttribute("MaxSlots")
	local slotsRemaining = jobFolder:GetAttribute("SlotsRemaining")
	local shiftShort, _ = getShiftSummaries(jobFolder)
	local highlightText = jobInfo.Highlight or ""
	if shiftShort then
		if highlightText ~= "" then
			blurb.Text = string.format("%s\nShift: %s", highlightText, shiftShort)
		else
			blurb.Text = string.format("Shift: %s", shiftShort)
		end
	else
		blurb.Text = highlightText
	end
	pay.Text = string.format("$ %s per %s", tostring(basePay), payUnit)
	title.Text = jobInfo.Name
	if availableSlots then
		if jobInfo.Type == "Gig" then
			availableSlots.Text = "Available: Unlimited"
		else
			availableSlots.Text = string.format("Available: %s/%s", tostring(slotsRemaining), tostring(maxSlots))
		end
	end
end

local function createCard(jobFolder: JobFolder): TextButton?
	local jobId = jobFolder:GetAttribute("JobId")
	if type(jobId) ~= "string" then
		warn("JobSelectionUI: Missing JobId attribute for", jobFolder)
		return nil
	end
	local jobInfo = getJobInfo(jobId)
	if not jobInfo then
		warn("JobSelectionUI: No catalog entry for", jobId)
		return nil
	end
	local jobTypeAttr = jobFolder:GetAttribute("Type")
	local rawJobType = if type(jobTypeAttr) == "string" then jobTypeAttr else jobInfo.Type
	local isCareer = rawJobType == "Career" or rawJobType == "Profession"
	local template = if isCareer then CareerTemplate else GigTemplate
	if not template then
		warn("JobSelectionUI: Missing template for job type", rawJobType)
		return nil
	end
	local jobCard = template:Clone()
	jobCard.Name = jobId
	jobCard.Visible = true
	jobCard.Parent = JobListScrollingFrame
	updateCardText(jobFolder, jobCard, jobInfo)

	local inputAction = Instance.new("InputAction")
	inputAction.Name = string.format("Select_%s", jobId)
	inputAction.Parent = InputContext
	inputAction.Enabled = true

	local inputBinding = Instance.new("InputBinding")
	inputBinding.Name = string.format("%sBinding", jobId)
	inputBinding.UIButton = jobCard
	inputBinding.Parent = inputAction

	local connections: { RBXScriptConnection } = {}

	local function focusCard()
		markSelection(jobCard)
		updateDetailPanel(jobInfo, jobFolder)
		return true
	end

	table.insert(
		connections,
		inputAction.Pressed:Connect(function()
			Debounce.RunIfAvailable(string.format("JobSelectionUI/Card/%s", jobId), INPUT_DEBOUNCE_SECONDS, function()
				focusCard()
			end, LocalPlayer.UserId)
		end)
	)

	table.insert(
		connections,
		jobFolder:GetAttributeChangedSignal("SlotsRemaining"):Connect(function()
			updateCardText(jobFolder, jobCard, jobInfo)
		end)
	)

	table.insert(
		connections,
		jobFolder:GetAttributeChangedSignal("MaxSlots"):Connect(function()
			updateCardText(jobFolder, jobCard, jobInfo)
		end)
	)

	table.insert(
		connections,
		jobFolder:GetAttributeChangedSignal("Type"):Connect(function()
			updateCardText(jobFolder, jobCard, jobInfo)
		end)
	)

	table.insert(
		connections,
		jobFolder:GetAttributeChangedSignal("ShiftId"):Connect(function()
			updateCardText(jobFolder, jobCard, jobInfo)
			if selectedCard == jobCard then
				updateDetailPanel(jobInfo, jobFolder)
			end
		end)
	)

	activeCards[jobFolder] = {
		Button = jobCard,
		Action = inputAction,
		Connections = connections,
		Folder = jobFolder,
	}

	return jobCard
end

local function populateCards()
	clearCards()
	local jobFolders = JobListingsFolder:GetChildren()
	table.sort(jobFolders, function(left: Instance, right: Instance)
		local leftId = left:GetAttribute("JobId")
		local rightId = right:GetAttribute("JobId")
		local leftInfo = if type(leftId) == "string" then getJobInfo(leftId) else nil
		local rightInfo = if type(rightId) == "string" then getJobInfo(rightId) else nil
		local leftName = if leftInfo then leftInfo.Name else tostring(leftId)
		local rightName = if rightInfo then rightInfo.Name else tostring(rightId)
		return leftName < rightName
	end)
	for _, jobFolder in ipairs(jobFolders) do
		local button = createCard(jobFolder :: JobFolder)
		if button and not selectedCard then
			markSelection(button)
			local jobId = jobFolder:GetAttribute("JobId")
			if type(jobId) == "string" then
				local jobInfo = getJobInfo(jobId)
				if jobInfo then
					updateDetailPanel(jobInfo, jobFolder :: JobFolder)
				end
			end
		end
	end
end

function JobSelectionUI.Init()
	-- Initialization code for the Job Selection UI goes here

	PlotBuilderEnabled.Changed:Connect(function()
		if PlotBuilderEnabled.Value and JobSelectionUIEnabled.Value then
			JobSelectionUI.Hide()
		end
	end)
	PlotExpansionEnabled.Changed:Connect(function()
		if PlotExpansionEnabled.Value and JobSelectionUIEnabled.Value then
			JobSelectionUI.Hide()
		end
	end)
	PlotGridOverlayEnabled.Changed:Connect(function()
		if PlotGridOverlayEnabled.Value and JobSelectionUIEnabled.Value then
			JobSelectionUI.Hide()
		end
	end)
	ResidualUIEnabled.Changed:Connect(function()
		if ResidualUIEnabled.Value and JobSelectionUIEnabled.Value then
			JobSelectionUI.Hide()
		end
	end)

	JobSelectionContext.CloseButtonAction.Pressed:Connect(function()
		runDebounced("Close", function()
			JobSelectionUI.Hide()
		end)
	end)
	JobSelectionContext.ApplyButtonAction.Pressed:Connect(function()
		runDebounced("Apply", function()
			if selectedCard then
				local jobId = selectedCard.Name
				local jobInfo = getJobInfo(jobId)
				if jobInfo then
					print("Applying for job:", jobInfo.Name)
					if jobInfo.Type == "Gig" then
						local success, message, runId = GigManager.StartGig(jobId)
						print("Gig start result:", success, message, runId)
						if not success then
							warn(message)
							return
						end
						JobSelectionUI.Hide()
						return
					end
					local residentModel = ResidentNeedsUI.GetCurrentSelectedResident()
					local residentName = if residentModel then residentModel.Name else nil
					if not residentName then
						warn("No resident selected to apply for job.")
						return
					end

					local success, message = JobPackets.RequestJob:Fire(jobId, residentName)
					print("Career application result:", success, message)
					if not success then
						warn(message)
						return
					end
					JobSelectionUI.Hide()
					ResidentNeedsUI.Hide(false) -- false to clear selection
				else
					warn("No job info found for selected job ID:", jobId)
				end
			else
				warn("No job selected to apply for.")
			end
		end)
	end)
	JobSelectionContext.Toggle.Pressed:Connect(function()
		runDebounced("Toggle", function()
			if JobSelectionGui.Enabled then
				JobSelectionUI.Hide()
			else
				JobSelectionUI.Show()
			end
		end)
	end)

	JobListingsFolder:GetAttributeChangedSignal("LastListings"):Connect(function()
		populateCards()
		syncCooldownFromAttributes()
	end)

	JobListingsFolder:GetAttributeChangedSignal("NextRestock"):Connect(function()
		syncCooldownFromAttributes()
	end)

	JobListingsFolder.ChildAdded:Connect(function()
		populateCards()
		syncCooldownFromAttributes()
	end)

	JobListingsFolder.ChildRemoved:Connect(function(child)
		local metadata = activeCards[child :: JobFolder]
		if metadata then
			activeCards[child :: JobFolder] = nil
			destroyCard(metadata)
		end
		populateCards()
		syncCooldownFromAttributes()
	end)

	populateCards()
	syncCooldownFromAttributes()
end

function JobSelectionUI.Show()
	if JobSelectionUIEnabled.Value then
		return
	end
	JobSelectionUIEnabled.Value = true
	JobSelectionGui.Enabled = true
	InputContext.Enabled = true
	if BlurEffect then
		BlurEffect.Enabled = true
	end
end

function JobSelectionUI.Hide()
	if not JobSelectionUIEnabled.Value then
		return
	end
	JobSelectionUIEnabled.Value = false
	JobSelectionGui.Enabled = false
	InputContext.Enabled = false
	if BlurEffect then
		BlurEffect.Enabled = false
	end
end

return JobSelectionUI
