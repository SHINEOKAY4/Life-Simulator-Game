--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local AchievementPackets = require(ReplicatedStorage.Network.AchievementPackets)
local BadgeService = require(ReplicatedStorage.Shared.Services.BadgeService)
local Notification = require(script.Parent.Notification)

local AchievementUI = {}

type AchievementRow = {
	Id: string,
	Name: string,
	Description: string,
	Category: string,
	CurrentValue: number,
	ProgressValue: number,
	TargetValue: number,
	IsUnlocked: boolean,
	IsClaimed: boolean,
	SortOrder: number,
	Rewards: { [string]: any },
}

type Snapshot = {
	Achievements: { AchievementRow },
	UnlockedCount: number,
	ClaimedCount: number,
	TotalCount: number,
}

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

local gui: ScreenGui? = nil
local windowFrame: Frame? = nil
local progressLabel: TextLabel? = nil
local listFrame: ScrollingFrame? = nil
local emptyLabel: TextLabel? = nil
local open = false
local initialized = false
local currentSnapshot: Snapshot? = nil
local rowById: { [string]: AchievementRow } = {}

local function formatRewardText(row: AchievementRow): string
	local rewards = row.Rewards
	if typeof(rewards) ~= "table" then
		return ""
	end
	local cash = rewards.Cash
	local xp = rewards.Experience
	local chunks = {}
	if typeof(cash) == "number" and cash > 0 then
		chunks[#chunks + 1] = string.format("$%d", math.floor(cash + 0.5))
	end
	if typeof(xp) == "number" and xp > 0 then
		chunks[#chunks + 1] = string.format("%d XP", math.floor(xp + 0.5))
	end
	return table.concat(chunks, " + ")
end

local function ensureGui()
	if gui and gui.Parent then
		return
	end

	gui = Instance.new("ScreenGui")
	gui.Name = "AchievementsGui"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 60
	gui.Enabled = false
	gui.Parent = PlayerGui

	local overlay = Instance.new("Frame")
	overlay.Name = "Overlay"
	overlay.Size = UDim2.fromScale(1, 1)
	overlay.BackgroundColor3 = Color3.fromRGB(12, 14, 18)
	overlay.BackgroundTransparency = 0.34
	overlay.BorderSizePixel = 0
	overlay.Parent = gui

	local frame = Instance.new("Frame")
	frame.Name = "Window"
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromScale(0.5, 0.5)
	frame.Size = UDim2.fromOffset(760, 520)
	frame.BackgroundColor3 = Color3.fromRGB(24, 29, 38)
	frame.BorderSizePixel = 0
	frame.Parent = overlay
	windowFrame = frame

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = frame

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(95, 116, 153)
	stroke.Thickness = 1
	stroke.Transparency = 0.35
	stroke.Parent = frame

	local header = Instance.new("Frame")
	header.Name = "Header"
	header.Size = UDim2.new(1, 0, 0, 64)
	header.BackgroundTransparency = 1
	header.Parent = frame

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.Position = UDim2.fromOffset(24, 14)
	title.Size = UDim2.fromOffset(420, 30)
	title.Font = Enum.Font.GothamBold
	title.Text = "Achievements"
	title.TextSize = 26
	title.TextColor3 = Color3.fromRGB(244, 249, 255)
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Parent = header

	local sub = Instance.new("TextLabel")
	sub.Name = "Sub"
	sub.BackgroundTransparency = 1
	sub.Position = UDim2.fromOffset(24, 40)
	sub.Size = UDim2.fromOffset(420, 22)
	sub.Font = Enum.Font.Gotham
	sub.Text = "Track milestones and claim rewards."
	sub.TextSize = 14
	sub.TextColor3 = Color3.fromRGB(176, 188, 205)
	sub.TextXAlignment = Enum.TextXAlignment.Left
	sub.Parent = header

	local close = Instance.new("TextButton")
	close.Name = "Close"
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, -18, 0, 14)
	close.Size = UDim2.fromOffset(36, 36)
	close.Text = "X"
	close.Font = Enum.Font.GothamBold
	close.TextSize = 16
	close.TextColor3 = Color3.fromRGB(223, 231, 246)
	close.BackgroundColor3 = Color3.fromRGB(44, 53, 71)
	close.AutoButtonColor = true
	close.Parent = header
	local closeCorner = Instance.new("UICorner")
	closeCorner.CornerRadius = UDim.new(1, 0)
	closeCorner.Parent = close
	close.Activated:Connect(function()
		AchievementUI.SetVisible(false)
	end)

	local progress = Instance.new("TextLabel")
	progress.Name = "ProgressLabel"
	progress.BackgroundTransparency = 1
	progress.AnchorPoint = Vector2.new(1, 0)
	progress.Position = UDim2.new(1, -66, 0, 42)
	progress.Size = UDim2.fromOffset(280, 20)
	progress.Font = Enum.Font.GothamMedium
	progress.Text = "0 / 0 claimed"
	progress.TextSize = 14
	progress.TextColor3 = Color3.fromRGB(150, 220, 174)
	progress.TextXAlignment = Enum.TextXAlignment.Right
	progress.Parent = header
	progressLabel = progress

	local body = Instance.new("Frame")
	body.Name = "Body"
	body.BackgroundTransparency = 1
	body.Position = UDim2.fromOffset(20, 72)
	body.Size = UDim2.new(1, -40, 1, -88)
	body.Parent = frame

	local list = Instance.new("ScrollingFrame")
	list.Name = "List"
	list.Size = UDim2.fromScale(1, 1)
	list.BackgroundTransparency = 1
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.ScrollBarThickness = 7
	list.CanvasSize = UDim2.fromOffset(0, 0)
	list.Parent = body
	listFrame = list

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 10)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = list

	local empty = Instance.new("TextLabel")
	empty.Name = "EmptyLabel"
	empty.Size = UDim2.new(1, 0, 0, 44)
	empty.BackgroundTransparency = 1
	empty.Text = "No achievements yet."
	empty.Font = Enum.Font.Gotham
	empty.TextSize = 18
	empty.TextColor3 = Color3.fromRGB(179, 191, 208)
	empty.LayoutOrder = 1
	empty.Visible = false
	empty.Parent = list
	emptyLabel = empty
end

local function makeCard(row: AchievementRow, layoutOrder: number): Frame
	local card = Instance.new("Frame")
	card.Name = row.Id
	card.LayoutOrder = layoutOrder
	card.Size = UDim2.new(1, -8, 0, 112)
	card.BackgroundColor3 = Color3.fromRGB(31, 38, 50)
	card.BorderSizePixel = 0

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = card

	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 1
	stroke.Transparency = 0.5
	stroke.Color = if row.IsClaimed
		then Color3.fromRGB(68, 158, 112)
		elseif row.IsUnlocked then Color3.fromRGB(110, 166, 255) else Color3.fromRGB(95, 109, 131)
	stroke.Parent = card

	-- Badge icon for the achievement category
	local badge = BadgeService.GetBadgeForCategory(row.Category)
	local BADGE_SIZE = 28
	local CONTENT_LEFT = 14 + BADGE_SIZE + 8 -- left pad + badge + gap

	local badgeFrame = Instance.new("Frame")
	badgeFrame.Name = "BadgeFrame"
	badgeFrame.Position = UDim2.fromOffset(14, 10)
	badgeFrame.Size = UDim2.fromOffset(BADGE_SIZE, BADGE_SIZE)
	badgeFrame.BackgroundColor3 = Color3.fromRGB(badge.Color.R, badge.Color.G, badge.Color.B)
	badgeFrame.BackgroundTransparency = 0.75
	badgeFrame.BorderSizePixel = 0
	badgeFrame.Parent = card

	local badgeCorner = Instance.new("UICorner")
	badgeCorner.CornerRadius = UDim.new(0, 6)
	badgeCorner.Parent = badgeFrame

	local badgeIcon = Instance.new("TextLabel")
	badgeIcon.Name = "BadgeIcon"
	badgeIcon.Size = UDim2.fromScale(1, 1)
	badgeIcon.BackgroundTransparency = 1
	badgeIcon.Font = Enum.Font.Gotham
	badgeIcon.TextSize = 16
	badgeIcon.Text = badge.Icon
	badgeIcon.TextColor3 = Color3.fromRGB(badge.Color.R, badge.Color.G, badge.Color.B)
	badgeIcon.Parent = badgeFrame

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.Position = UDim2.fromOffset(CONTENT_LEFT, 8)
	title.Size = UDim2.new(1, -CONTENT_LEFT - 140, 0, 22)
	title.Font = Enum.Font.GothamBold
	title.TextSize = 18
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextColor3 = Color3.fromRGB(240, 247, 255)
	title.Text = row.Name
	title.Parent = card

	local desc = Instance.new("TextLabel")
	desc.Name = "Desc"
	desc.BackgroundTransparency = 1
	desc.Position = UDim2.fromOffset(CONTENT_LEFT, 31)
	desc.Size = UDim2.new(1, -CONTENT_LEFT - 150, 0, 19)
	desc.Font = Enum.Font.Gotham
	desc.TextSize = 13
	desc.TextXAlignment = Enum.TextXAlignment.Left
	desc.TextColor3 = Color3.fromRGB(166, 181, 202)
	desc.Text = row.Description
	desc.Parent = card

	local progressBack = Instance.new("Frame")
	progressBack.Name = "ProgressBack"
	progressBack.Position = UDim2.fromOffset(CONTENT_LEFT, 60)
	progressBack.Size = UDim2.new(1, -CONTENT_LEFT - 165, 0, 14)
	progressBack.BackgroundColor3 = Color3.fromRGB(16, 20, 29)
	progressBack.BorderSizePixel = 0
	progressBack.Parent = card
	local progressBackCorner = Instance.new("UICorner")
	progressBackCorner.CornerRadius = UDim.new(0, 7)
	progressBackCorner.Parent = progressBack

	local progressFill = Instance.new("Frame")
	progressFill.Name = "ProgressFill"
	progressFill.Size = UDim2.fromScale(0, 1)
	progressFill.BackgroundColor3 = if row.IsClaimed
		then Color3.fromRGB(70, 178, 121)
		elseif row.IsUnlocked then Color3.fromRGB(94, 169, 255) else Color3.fromRGB(120, 135, 161)
	progressFill.BorderSizePixel = 0
	progressFill.Parent = progressBack
	local progressFillCorner = Instance.new("UICorner")
	progressFillCorner.CornerRadius = UDim.new(0, 7)
	progressFillCorner.Parent = progressFill

	local targetRatio = math.clamp(row.ProgressValue / math.max(row.TargetValue, 1), 0, 1)
	TweenService:Create(progressFill, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = UDim2.fromScale(targetRatio, 1),
	}):Play()

	local progressText = Instance.new("TextLabel")
	progressText.Name = "ProgressText"
	progressText.BackgroundTransparency = 1
	progressText.Position = UDim2.fromOffset(CONTENT_LEFT, 76)
	progressText.Size = UDim2.new(1, -CONTENT_LEFT - 170, 0, 20)
	progressText.Font = Enum.Font.GothamMedium
	progressText.TextSize = 13
	progressText.TextXAlignment = Enum.TextXAlignment.Left
	progressText.TextColor3 = Color3.fromRGB(189, 203, 223)
	progressText.Text = string.format("%d / %d", row.ProgressValue, row.TargetValue)
	progressText.Parent = card

	local rewardText = formatRewardText(row)
	if rewardText ~= "" then
		local rewards = Instance.new("TextLabel")
		rewards.Name = "Rewards"
		rewards.BackgroundTransparency = 1
		rewards.Position = UDim2.fromOffset(CONTENT_LEFT, 93)
		rewards.Size = UDim2.new(1, -CONTENT_LEFT - 175, 0, 16)
		rewards.Font = Enum.Font.Gotham
		rewards.TextSize = 12
		rewards.TextXAlignment = Enum.TextXAlignment.Left
		rewards.TextColor3 = Color3.fromRGB(241, 213, 140)
		rewards.Text = "Reward: " .. rewardText
		rewards.Parent = card
	end

	local claimButton = Instance.new("TextButton")
	claimButton.Name = "ClaimButton"
	claimButton.AnchorPoint = Vector2.new(1, 0)
	claimButton.Position = UDim2.new(1, -12, 0, 12)
	claimButton.Size = UDim2.fromOffset(120, 32)
	claimButton.Font = Enum.Font.GothamBold
	claimButton.TextSize = 13
	claimButton.AutoButtonColor = true
	claimButton.Parent = card

	local claimCorner = Instance.new("UICorner")
	claimCorner.CornerRadius = UDim.new(0, 8)
	claimCorner.Parent = claimButton

	if row.IsClaimed then
		claimButton.BackgroundColor3 = Color3.fromRGB(57, 120, 85)
		claimButton.Text = "Claimed"
		claimButton.TextColor3 = Color3.fromRGB(224, 255, 229)
		claimButton.Active = false
	elseif row.IsUnlocked then
		claimButton.BackgroundColor3 = Color3.fromRGB(52, 124, 203)
		claimButton.Text = "Claim Reward"
		claimButton.TextColor3 = Color3.fromRGB(230, 243, 255)
		claimButton.Activated:Connect(function()
			claimButton.Active = false
			local success, message = AchievementPackets.ClaimAchievement:InvokeServer(row.Id)
			if not success then
				claimButton.Active = true
				Notification.Show({
					Title = "Claim Failed",
					Text = if typeof(message) == "string" then message else "Could not claim this achievement.",
					Duration = 3,
					BackgroundColor = Color3.fromRGB(132, 64, 64),
				})
			end
		end)
	else
		claimButton.BackgroundColor3 = Color3.fromRGB(73, 79, 94)
		claimButton.Text = "Locked"
		claimButton.TextColor3 = Color3.fromRGB(192, 198, 211)
		claimButton.Active = false
	end

	return card
end

local function renderSnapshot(snapshot: Snapshot?)
	if not gui or not listFrame or not progressLabel or not emptyLabel then
		return
	end

	currentSnapshot = snapshot
	rowById = {}

	for _, child in ipairs(listFrame:GetChildren()) do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end

	if not snapshot then
		progressLabel.Text = "0 / 0 claimed"
		emptyLabel.Visible = true
		return
	end

	progressLabel.Text = string.format("%d / %d claimed", snapshot.ClaimedCount or 0, snapshot.TotalCount or 0)

	local rows = snapshot.Achievements
	if typeof(rows) ~= "table" or #rows == 0 then
		emptyLabel.Visible = true
		return
	end

	table.sort(rows, function(a: AchievementRow, b: AchievementRow)
		if a.IsClaimed ~= b.IsClaimed then
			return not a.IsClaimed
		end
		if a.IsUnlocked ~= b.IsUnlocked then
			return a.IsUnlocked
		end
		if a.SortOrder == b.SortOrder then
			return a.Id < b.Id
		end
		return a.SortOrder < b.SortOrder
	end)

	emptyLabel.Visible = false
	for index, row in ipairs(rows) do
		rowById[row.Id] = row
		local card = makeCard(row, index)
		card.Parent = listFrame
	end
end

local function onSnapshotUpdated(payload: any)
	if typeof(payload) ~= "table" then
		return
	end
	renderSnapshot(payload :: Snapshot)
end

local function onAchievementUnlocked(payload: any)
	if typeof(payload) ~= "table" then
		return
	end
	local achievementId = payload.AchievementId
	if typeof(achievementId) ~= "string" or achievementId == "" then
		return
	end

	local row = rowById[achievementId]
	local name = if row then row.Name else "Achievement"
	local category = if row then row.Category else ""
	local badge = BadgeService.GetBadgeForCategory(category)
	Notification.Show({
		Title = badge.Icon .. " Achievement Unlocked",
		Text = string.format("%s is now ready to claim.", name),
		Duration = 4,
		BackgroundColor = Color3.fromRGB(43, 88, 141),
	})
end

function AchievementUI.SetVisible(visible: boolean)
	ensureGui()
	open = visible
	if gui then
		gui.Enabled = visible
	end
end

function AchievementUI.Toggle()
	AchievementUI.SetVisible(not open)
end

function AchievementUI.Init()
	if initialized then
		return
	end
	initialized = true

	ensureGui()
	AchievementPackets.SnapshotUpdated.OnClientEvent:Connect(onSnapshotUpdated)
	AchievementPackets.AchievementUnlocked.OnClientEvent:Connect(onAchievementUnlocked)

	local ok, _, payload = AchievementPackets.GetSnapshot:InvokeServer()
	if ok and typeof(payload) == "table" then
		renderSnapshot(payload :: Snapshot)
	else
		renderSnapshot(nil)
	end
end

return AchievementUI
