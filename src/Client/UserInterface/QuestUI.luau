--!strict
-- QuestUI.luau
-- Client-side quest panel: lists quests grouped by state, shows objective progress,
-- and lets players start available quests or claim completed ones.
-- Follows established UI patterns (DailyRewardUI, SeasonalEventUI, AchievementUI).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local QuestPackets = require(ReplicatedStorage.Network.QuestPackets)
local Notification = require(script.Parent.Notification)

local QuestUI = {}

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

-- GUI references
local gui: ScreenGui? = nil
local windowFrame: Frame? = nil
local questListFrame: ScrollingFrame? = nil
local headerLabel: TextLabel? = nil
local filterBar: Frame? = nil
local emptyLabel: TextLabel? = nil

local open = false
local initialized = false
local renderToken = 0

-- Cached snapshot from server: { [questId]: { State, Progress } }
local cachedSnapshot: { [string]: any } = {}

-- Active filter: "all" | "active" | "available" | "done"
local activeFilter = "all"

-- Quest state display config
local STATE_COLORS = {
	in_progress = Color3.fromRGB(52, 124, 203),
	available   = Color3.fromRGB(56, 140, 88),
	completed   = Color3.fromRGB(181, 134, 52),
	claimed     = Color3.fromRGB(60, 68, 86),
	locked      = Color3.fromRGB(45, 52, 68),
}

local STATE_LABELS = {
	in_progress = "In Progress",
	available   = "Available",
	completed   = "Completed!",
	claimed     = "Claimed",
	locked      = "Locked",
}

local FILTER_STATES: { [string]: { string } } = {
	all       = { "in_progress", "available", "completed", "claimed", "locked" },
	active    = { "in_progress" },
	available = { "available" },
	done      = { "completed", "claimed" },
}

local FILTER_LABELS = {
	all       = "All",
	active    = "Active",
	available = "Available",
	done      = "Done",
}

-- ── Helpers ────────────────────────────────────────────────────────────────────

local function stateInFilter(state: string): boolean
	local allowed = FILTER_STATES[activeFilter]
	if not allowed then return true end
	for _, s in ipairs(allowed) do
		if s == state then return true end
	end
	return false
end

-- Build a compact description of objective progress for display.
local function describeObjectives(objectives: { any }, progress: { [string]: number }): string
	if not objectives or #objectives == 0 then
		return "No objectives"
	end
	local parts = {}
	for _, obj in ipairs(objectives) do
		local p = progress and (progress[obj.id] or 0) or 0
		local target = obj.target
		local targetStr
		if type(target) == "number" then
			targetStr = tostring(target)
		else
			targetStr = tostring(target)
			-- For string/table targets the completion is 0 or 1
			p = math.min(p, 1)
			targetStr = "1"
		end
		table.insert(parts, string.format("%s: %d/%s", obj.id, p, targetStr))
	end
	return table.concat(parts, "  ·  ")
end

-- Compute overall completion ratio [0,1] across all objectives.
local function computeCompletionRatio(objectives: { any }, progress: { [string]: number }): number
	if not objectives or #objectives == 0 then return 1 end
	local total = 0
	local done = 0
	for _, obj in ipairs(objectives) do
		local p = progress and (progress[obj.id] or 0) or 0
		local target = obj.target
		if type(target) == "number" then
			total += target
			done += math.min(p, target)
		else
			total += 1
			done += math.min(p, 1)
		end
	end
	if total <= 0 then return 1 end
	return math.clamp(done / total, 0, 1)
end

-- Format reward summary string.
local function describeRewards(rewards: any): string
	if type(rewards) ~= "table" then return "" end
	local parts = {}
	if type(rewards.XP) == "number" and rewards.XP > 0 then
		table.insert(parts, string.format("+%d XP", rewards.XP))
	end
	if type(rewards.Currency) == "table" then
		for _, entry in ipairs(rewards.Currency) do
			if type(entry.Name) == "string" and type(entry.Amount) == "number" and entry.Amount > 0 then
				table.insert(parts, string.format("+%d %s", entry.Amount, entry.Name))
			end
		end
	end
	return table.concat(parts, "  ")
end

-- ── UI construction helpers ────────────────────────────────────────────────────

local function createProgressBar(parent: Frame, ratio: number): Frame
	local bg = Instance.new("Frame")
	bg.Name = "ProgressBg"
	bg.Size = UDim2.new(1, 0, 0, 6)
	bg.Position = UDim2.fromOffset(0, 0)
	bg.BackgroundColor3 = Color3.fromRGB(30, 36, 48)
	bg.BorderSizePixel = 0
	bg.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = bg

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(math.clamp(ratio, 0, 1), 1)
	fill.BackgroundColor3 = Color3.fromRGB(52, 124, 203)
	fill.BorderSizePixel = 0
	fill.Parent = bg

	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(1, 0)
	fillCorner.Parent = fill

	return bg
end

-- Build one quest card frame. questInfo: { id, name, objectives, rewards, state, progress }
local function createQuestCard(questInfo: { [string]: any }): Frame
	local questId = tostring(questInfo.id or "")
	local questName = tostring(questInfo.name or questId)
	local state = tostring(questInfo.state or "locked")
	local objectives = questInfo.objectives or {}
	local progress = questInfo.progress or {}
	local rewards = questInfo.rewards

	local stateColor = STATE_COLORS[state] or STATE_COLORS.locked
	local stateLabel = STATE_LABELS[state] or state

	local cardHeight = 110
	local showAction = (state == "available" or state == "completed")
	if showAction then cardHeight = 140 end
	local showProgress = (state == "in_progress")
	if showProgress then cardHeight = 130 end

	local card = Instance.new("Frame")
	card.Name = "Quest_" .. questId
	card.Size = UDim2.new(1, -8, 0, cardHeight)
	card.BackgroundColor3 = Color3.fromRGB(24, 30, 40)
	card.BorderSizePixel = 0
	card.LayoutOrder = (
		if state == "in_progress" then 1
		elseif state == "available" then 2
		elseif state == "completed" then 3
		elseif state == "claimed" then 4
		else 5
	)

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = card

	-- Left accent bar coloured by state
	local accent = Instance.new("Frame")
	accent.Name = "Accent"
	accent.Size = UDim2.new(0, 4, 1, 0)
	accent.Position = UDim2.fromOffset(0, 0)
	accent.BackgroundColor3 = stateColor
	accent.BorderSizePixel = 0
	accent.ZIndex = 2
	accent.Parent = card

	local accentCorner = Instance.new("UICorner")
	accentCorner.CornerRadius = UDim.new(0, 10)
	accentCorner.Parent = accent

	-- Quest name
	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "QuestName"
	nameLabel.BackgroundTransparency = 1
	nameLabel.Position = UDim2.fromOffset(16, 10)
	nameLabel.Size = UDim2.new(1, -100, 0, 20)
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextSize = 15
	nameLabel.TextColor3 = Color3.fromRGB(235, 244, 255)
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.Text = questName
	nameLabel.Parent = card

	-- State badge
	local badge = Instance.new("TextLabel")
	badge.Name = "StateBadge"
	badge.BackgroundTransparency = 1
	badge.AnchorPoint = Vector2.new(1, 0)
	badge.Position = UDim2.new(1, -10, 0, 10)
	badge.Size = UDim2.fromOffset(90, 18)
	badge.Font = Enum.Font.GothamMedium
	badge.TextSize = 11
	badge.TextColor3 = stateColor
	badge.TextXAlignment = Enum.TextXAlignment.Right
	badge.Text = stateLabel
	badge.Parent = card

	-- Objective summary
	local objLabel = Instance.new("TextLabel")
	objLabel.Name = "Objectives"
	objLabel.BackgroundTransparency = 1
	objLabel.Position = UDim2.fromOffset(16, 34)
	objLabel.Size = UDim2.new(1, -24, 0, 16)
	objLabel.Font = Enum.Font.Gotham
	objLabel.TextSize = 11
	objLabel.TextColor3 = Color3.fromRGB(160, 174, 195)
	objLabel.TextXAlignment = Enum.TextXAlignment.Left
	objLabel.TextTruncate = Enum.TextTruncate.AtEnd
	objLabel.Text = describeObjectives(objectives, progress)
	objLabel.Parent = card

	-- Reward summary
	local rewardLabel = Instance.new("TextLabel")
	rewardLabel.Name = "Rewards"
	rewardLabel.BackgroundTransparency = 1
	rewardLabel.Position = UDim2.fromOffset(16, 54)
	rewardLabel.Size = UDim2.new(1, -24, 0, 14)
	rewardLabel.Font = Enum.Font.Gotham
	rewardLabel.TextSize = 11
	rewardLabel.TextColor3 = Color3.fromRGB(241, 213, 140)
	rewardLabel.TextXAlignment = Enum.TextXAlignment.Left
	rewardLabel.Text = describeRewards(rewards)
	rewardLabel.Parent = card

	-- Progress bar for in_progress quests
	if showProgress then
		local ratio = computeCompletionRatio(objectives, progress)
		local pbContainer = Instance.new("Frame")
		pbContainer.Name = "ProgressBarContainer"
		pbContainer.BackgroundTransparency = 1
		pbContainer.Position = UDim2.fromOffset(16, 74)
		pbContainer.Size = UDim2.new(1, -32, 0, 8)
		pbContainer.Parent = card
		createProgressBar(pbContainer, ratio)

		local pctLabel = Instance.new("TextLabel")
		pctLabel.Name = "Pct"
		pctLabel.BackgroundTransparency = 1
		pctLabel.Position = UDim2.fromOffset(16, 84)
		pctLabel.Size = UDim2.new(1, -24, 0, 14)
		pctLabel.Font = Enum.Font.Gotham
		pctLabel.TextSize = 10
		pctLabel.TextColor3 = Color3.fromRGB(120, 140, 170)
		pctLabel.TextXAlignment = Enum.TextXAlignment.Left
		pctLabel.Text = string.format("%.0f%% complete", math.clamp(ratio * 100, 0, 100))
		pctLabel.Parent = card
	end

	-- Action button: Start (available) or Claim (completed)
	if showAction then
		local actionLabel = if state == "available" then "Start Quest" else "Claim Reward"
		local actionColor = if state == "available"
			then Color3.fromRGB(56, 140, 88)
			else Color3.fromRGB(181, 134, 52)

    local actionBtn = Instance.new("TextButton")
		actionBtn.Name = "ActionButton"
		actionBtn.AnchorPoint = Vector2.new(0.5, 0)
		actionBtn.Position = UDim2.new(0.5, 0, 0, 98)
		actionBtn.Size = UDim2.fromOffset(200, 32)
		actionBtn.Font = Enum.Font.GothamBold
		actionBtn.TextSize = 13
		actionBtn.Text = actionLabel
		actionBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
		actionBtn.BackgroundColor3 = actionColor
		actionBtn.AutoButtonColor = true
		actionBtn.Parent = card

		local btnCorner = Instance.new("UICorner")
		btnCorner.CornerRadius = UDim.new(0, 8)
		btnCorner.Parent = actionBtn

    actionBtn.Activated:Connect(function()
        actionBtn.Active = false
        actionBtn.Text = if state == "available" then "Starting..." else "Claiming..."
        if state == "available" then
            QuestUI._StartQuest(questId, actionBtn)
        else
            QuestUI._ClaimQuest(questId, actionBtn)
        end
    end)
	end

	return card
end

-- ── ensureGui ──────────────────────────────────────────────────────────────────

local function ensureGui()
	if gui and gui.Parent then
		return
	end

	gui = Instance.new("ScreenGui")
	gui.Name = "QuestUI"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 54
	gui.Enabled = false
	gui.Parent = PlayerGui

	-- Semi-transparent overlay
	local overlay = Instance.new("Frame")
	overlay.Name = "Overlay"
	overlay.Size = UDim2.fromScale(1, 1)
	overlay.BackgroundColor3 = Color3.fromRGB(12, 14, 18)
	overlay.BackgroundTransparency = 0.34
	overlay.BorderSizePixel = 0
	overlay.Parent = gui

	-- Main window
	local window = Instance.new("Frame")
	window.Name = "Window"
	window.AnchorPoint = Vector2.new(0.5, 0.5)
	window.Position = UDim2.fromScale(0.5, 0.5)
	window.Size = UDim2.fromOffset(540, 520)
	window.BackgroundColor3 = Color3.fromRGB(24, 29, 38)
	window.BorderSizePixel = 0
	window.Parent = overlay
	windowFrame = window

	local windowCorner = Instance.new("UICorner")
	windowCorner.CornerRadius = UDim.new(0, 12)
	windowCorner.Parent = window

	local windowStroke = Instance.new("UIStroke")
	windowStroke.Color = Color3.fromRGB(95, 116, 153)
	windowStroke.Thickness = 1
	windowStroke.Transparency = 0.35
	windowStroke.Parent = window

	-- Size constraint
	local sizeConstraint = Instance.new("UISizeConstraint")
	sizeConstraint.MinSize = Vector2.new(380, 460)
	sizeConstraint.MaxSize = Vector2.new(660, 600)
	sizeConstraint.Parent = window

	-- Header
	local header = Instance.new("Frame")
	header.Name = "Header"
	header.Size = UDim2.new(1, 0, 0, 56)
	header.BackgroundTransparency = 1
	header.Parent = window

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.Position = UDim2.fromOffset(20, 10)
	title.Size = UDim2.fromOffset(320, 26)
	title.Font = Enum.Font.GothamBold
	title.TextSize = 22
	title.TextColor3 = Color3.fromRGB(244, 249, 255)
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Text = "Quests"
	title.Parent = header
	headerLabel = title

	local subtitle = Instance.new("TextLabel")
	subtitle.Name = "Subtitle"
	subtitle.BackgroundTransparency = 1
	subtitle.Position = UDim2.fromOffset(20, 36)
	subtitle.Size = UDim2.fromOffset(320, 16)
	subtitle.Font = Enum.Font.Gotham
	subtitle.TextSize = 12
	subtitle.TextColor3 = Color3.fromRGB(176, 188, 205)
	subtitle.TextXAlignment = Enum.TextXAlignment.Left
	subtitle.Text = "Complete quests to earn XP and cash rewards"
	subtitle.Parent = header

	-- Close button
	local closeBtn = Instance.new("TextButton")
	closeBtn.Name = "Close"
	closeBtn.AnchorPoint = Vector2.new(1, 0)
	closeBtn.Position = UDim2.new(1, -14, 0, 12)
	closeBtn.Size = UDim2.fromOffset(36, 36)
	closeBtn.Text = "X"
	closeBtn.Font = Enum.Font.GothamBold
	closeBtn.TextSize = 16
	closeBtn.TextColor3 = Color3.fromRGB(223, 231, 246)
	closeBtn.BackgroundColor3 = Color3.fromRGB(44, 53, 71)
	closeBtn.AutoButtonColor = true
	closeBtn.Parent = header
	local closeBtnCorner = Instance.new("UICorner")
	closeBtnCorner.CornerRadius = UDim.new(1, 0)
	closeBtnCorner.Parent = closeBtn
	closeBtn.Activated:Connect(function()
		QuestUI.SetVisible(false)
	end)

	-- Filter bar
	local filterBarFrame = Instance.new("Frame")
	filterBarFrame.Name = "FilterBar"
	filterBarFrame.Position = UDim2.fromOffset(16, 58)
	filterBarFrame.Size = UDim2.new(1, -32, 0, 32)
	filterBarFrame.BackgroundTransparency = 1
	filterBarFrame.Parent = window
	filterBar = filterBarFrame

	local filterLayout = Instance.new("UIListLayout")
	filterLayout.FillDirection = Enum.FillDirection.Horizontal
	filterLayout.Padding = UDim.new(0, 6)
	filterLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	filterLayout.Parent = filterBarFrame

	local FILTER_KEYS = { "all", "active", "available", "done" }
	for _, key in ipairs(FILTER_KEYS) do
		local fb = Instance.new("TextButton")
		fb.Name = "Filter_" .. key
		fb.Size = UDim2.fromOffset(82, 28)
		fb.Font = Enum.Font.GothamMedium
		fb.TextSize = 12
		fb.Text = FILTER_LABELS[key]
		fb.TextColor3 = Color3.fromRGB(200, 212, 228)
		fb.BackgroundColor3 = Color3.fromRGB(36, 44, 58)
		fb.AutoButtonColor = true
		fb.Parent = filterBarFrame

		local fbCorner = Instance.new("UICorner")
		fbCorner.CornerRadius = UDim.new(0, 8)
		fbCorner.Parent = fb

		fb.Activated:Connect(function()
			activeFilter = key
			QuestUI._RenderList()
		end)
	end

	-- Divider
	local divider = Instance.new("Frame")
	divider.Name = "Divider"
	divider.Position = UDim2.fromOffset(16, 94)
	divider.Size = UDim2.new(1, -32, 0, 1)
	divider.BackgroundColor3 = Color3.fromRGB(60, 70, 90)
	divider.BackgroundTransparency = 0.4
	divider.BorderSizePixel = 0
	divider.Parent = window

	-- Scrollable quest list
	local scrollFrame = Instance.new("ScrollingFrame")
	scrollFrame.Name = "QuestList"
	scrollFrame.Position = UDim2.fromOffset(16, 100)
	scrollFrame.Size = UDim2.new(1, -32, 1, -108)
	scrollFrame.BackgroundTransparency = 1
	scrollFrame.BorderSizePixel = 0
	scrollFrame.ScrollBarThickness = 4
	scrollFrame.ScrollBarImageColor3 = Color3.fromRGB(90, 110, 145)
	scrollFrame.CanvasSize = UDim2.fromScale(1, 0)
	scrollFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scrollFrame.Parent = window
	questListFrame = scrollFrame

	local listLayout = Instance.new("UIListLayout")
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Padding = UDim.new(0, 8)
	listLayout.Parent = scrollFrame

	local listPadding = Instance.new("UIPadding")
	listPadding.PaddingRight = UDim.new(0, 4)
	listPadding.PaddingBottom = UDim.new(0, 8)
	listPadding.Parent = scrollFrame

	-- Empty state label
	local empty = Instance.new("TextLabel")
	empty.Name = "EmptyLabel"
	empty.BackgroundTransparency = 1
	empty.AnchorPoint = Vector2.new(0.5, 0.5)
	empty.Position = UDim2.fromScale(0.5, 0.5)
	empty.Size = UDim2.fromOffset(300, 40)
	empty.Font = Enum.Font.Gotham
	empty.TextSize = 14
	empty.TextColor3 = Color3.fromRGB(130, 148, 172)
	empty.Text = "No quests in this category."
	empty.Visible = false
	empty.Parent = scrollFrame
	emptyLabel = empty
end

-- ── Render ─────────────────────────────────────────────────────────────────────

-- A lightweight quest catalog stub for rendering names/objectives on the client.
-- The server is authoritative; we only need display data here.
-- Quest names/objectives are embedded in the snapshot when we receive them,
-- so we fall back to just the id if the server sends a minimal snapshot.
-- (QuestService embeds the full catalog shape in GetPlayerQuests.)

function QuestUI._RenderList()
	local list = questListFrame
	if not list then return end
	renderToken += 1
	local currentToken = renderToken

	-- Clear existing quest cards
	for _, child in ipairs(list:GetChildren()) do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end

	-- Update filter button visual states
	if filterBar then
		for _, child in ipairs(filterBar:GetChildren()) do
			if child:IsA("TextButton") then
				local key = string.sub(child.Name, #"Filter_" + 1)
				if key == activeFilter then
					child.BackgroundColor3 = Color3.fromRGB(52, 124, 203)
					child.TextColor3 = Color3.fromRGB(255, 255, 255)
				else
					child.BackgroundColor3 = Color3.fromRGB(36, 44, 58)
					child.TextColor3 = Color3.fromRGB(200, 212, 228)
				end
			end
		end
	end

	-- Build cards for quests that pass the current filter
	local count = 0
	for questId, qstate in pairs(cachedSnapshot) do
		if currentToken ~= renderToken then
			return
		end
		local state = tostring(qstate.State or "locked")
		if not stateInFilter(state) then
			continue
		end

		-- Pull display info from qstate (server serialises definition data into snapshot)
		local questInfo: { [string]: any } = {
			id         = questId,
			name       = tostring(qstate.Name or questId),
			state      = state,
			objectives = qstate.Objectives or {},
			progress   = qstate.Progress or {},
			rewards    = qstate.Rewards,
		}

		local card = createQuestCard(questInfo)
		card.Parent = list
		count += 1
	end

	if emptyLabel then
		emptyLabel.Visible = (count == 0)
	end
end

-- ── Network actions ────────────────────────────────────────────────────────────

function QuestUI._StartQuest(questId: string, actionButton: TextButton?)
	task.spawn(function()
		local ok, success, errMsg = pcall(function()
			return QuestPackets.StartQuest:Fire(questId)
		end)
		if not ok or success == false then
			local message = "Could not start quest. It may have prerequisites."
			if typeof(errMsg) == "string" and errMsg ~= "" then
				message = errMsg
			end
			Notification.Show({
				Title = "Quest Unavailable",
				Text = message,
				Duration = 3,
				BackgroundColor = Color3.fromRGB(130, 64, 64),
			})
		end
		if actionButton then
			actionButton.Active = true
			actionButton.Text = "Start Quest"
		end
		-- Snapshot update will be pushed by server; re-render on receipt.
	end)
end

function QuestUI._ClaimQuest(questId: string, actionButton: TextButton?)
	task.spawn(function()
		local ok, success, errMsg = pcall(function()
			return QuestPackets.ClaimQuest:Fire(questId)
		end)
		if not ok or success == false then
			local message = "Could not claim quest reward. Try again."
			if typeof(errMsg) == "string" and errMsg ~= "" then
				message = errMsg
			end
			Notification.Show({
				Title = "Claim Failed",
				Text = message,
				Duration = 3,
				BackgroundColor = Color3.fromRGB(130, 64, 64),
			})
		end
		if actionButton then
			actionButton.Active = true
			actionButton.Text = "Claim Reward"
		end
	end)
end

function QuestUI._FetchSnapshot()
	task.spawn(function()
		local ok, success, payload = pcall(function()
			return QuestPackets.GetQuestSnapshot:Fire()
		end)
		if ok and success == true and typeof(payload) == "table" then
			cachedSnapshot = payload
			QuestUI._RenderList()
		elseif ok and success == true and payload == nil then
			cachedSnapshot = {}
			QuestUI._RenderList()
		end
	end)
end

-- ── Public API ─────────────────────────────────────────────────────────────────

function QuestUI.SetVisible(visible: boolean)
	ensureGui()
	open = visible
	if gui then
		gui.Enabled = visible
	end
	if visible then
		QuestUI._FetchSnapshot()
	end
end

function QuestUI.Toggle()
	QuestUI.SetVisible(not open)
end

function QuestUI.Init()
	if initialized then
		return
	end
	initialized = true

	ensureGui()

	-- Receive server-pushed snapshot updates
	QuestPackets.QuestSnapshotUpdated.OnClientEvent:Connect(function(snapshot)
		if typeof(snapshot) == "table" then
			cachedSnapshot = snapshot
			if open then
				QuestUI._RenderList()
			end
		end
	end)

	-- Show a toast when a quest completes
	QuestPackets.QuestCompleted.OnClientEvent:Connect(function(payload)
		if typeof(payload) == "table" then
			local name = tostring(payload.QuestName or payload.QuestId or "Quest")
			Notification.Show({
				Title = "Quest Complete!",
				Text = string.format('"%s" is finished — open Quests to claim your reward.', name),
				Duration = 5,
				BackgroundColor = Color3.fromRGB(56, 130, 80),
			})
		end
	end)
end

return QuestUI
