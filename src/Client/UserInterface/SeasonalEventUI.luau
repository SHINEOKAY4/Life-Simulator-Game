--!strict
-- SeasonalEventUI: Full-screen overlay with season banner, challenge tracker
-- with per-challenge reward claiming, active buffs panel, milestone rewards,
-- and MainHUD button integration.
-- Follows established patterns (DailyRewardUI, AchievementUI).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local SeasonalEventPackets = require(ReplicatedStorage.Network.SeasonalEventPackets)
local SeasonalEventDefinitions = require(ReplicatedStorage.Shared.Definitions.SeasonalEventDefinitions)
local Notification = require(script.Parent.Notification)

local SeasonalEventUI = {}

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

local gui: ScreenGui? = nil
local bannerFrame: Frame? = nil
local seasonTitleLabel: TextLabel? = nil
local seasonDescriptionLabel: TextLabel? = nil
local seasonStatsLabel: TextLabel? = nil
local challengeList: ScrollingFrame? = nil
local buffsList: ScrollingFrame? = nil
local milestoneList: ScrollingFrame? = nil

local open = false
local initialized = false

local seasonColors: { [string]: Color3 } = {
	Spring = Color3.fromRGB(76, 161, 93),
	Summer = Color3.fromRGB(224, 153, 59),
	Autumn = Color3.fromRGB(181, 96, 54),
	Winter = Color3.fromRGB(76, 132, 191),
}

local MILESTONE_COLOR = Color3.fromRGB(181, 134, 52)
local MILESTONE_CLAIMED_COLOR = Color3.fromRGB(56, 102, 76)

local function clearRows(container: ScrollingFrame)
	for _, child in ipairs(container:GetChildren()) do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
end

local function createChallengeRow(challenge: { [string]: any }, index: number): Frame
	local completed = challenge.Completed == true
	local rewardClaimed = challenge.RewardClaimed == true

	local row = Instance.new("Frame")
	row.Name = "Challenge_" .. tostring(challenge.Id or index)
	row.LayoutOrder = index
	row.Size = UDim2.new(1, -4, 0, 90)
	row.BorderSizePixel = 0

	if rewardClaimed then
		row.BackgroundColor3 = Color3.fromRGB(36, 56, 44)
	elseif completed then
		row.BackgroundColor3 = Color3.fromRGB(40, 60, 52)
	else
		row.BackgroundColor3 = Color3.fromRGB(30, 36, 48)
	end

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = row

	-- Challenge name
	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Position = UDim2.fromOffset(12, 6)
	title.Size = UDim2.new(0.6, -12, 0, 18)
	title.Font = Enum.Font.GothamBold
	title.TextSize = 14
	title.TextColor3 = Color3.fromRGB(235, 243, 255)
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Text = tostring(challenge.Name or "Challenge")
	title.Parent = row

	-- Description
	local desc = Instance.new("TextLabel")
	desc.BackgroundTransparency = 1
	desc.Position = UDim2.fromOffset(12, 24)
	desc.Size = UDim2.new(0.6, -12, 0, 14)
	desc.Font = Enum.Font.Gotham
	desc.TextSize = 11
	desc.TextColor3 = Color3.fromRGB(160, 174, 195)
	desc.TextXAlignment = Enum.TextXAlignment.Left
	desc.Text = tostring(challenge.Description or "")
	desc.Parent = row

	-- Progress bar
	local progressValue = tonumber(challenge.CurrentValue) or 0
	local targetValue = math.max(1, tonumber(challenge.TargetValue) or 1)
	local ratio = math.clamp(progressValue / targetValue, 0, 1)

	local progressTrack = Instance.new("Frame")
	progressTrack.BackgroundColor3 = Color3.fromRGB(14, 17, 25)
	progressTrack.BorderSizePixel = 0
	progressTrack.Position = UDim2.fromOffset(12, 44)
	progressTrack.Size = UDim2.new(0.6, -24, 0, 12)
	progressTrack.Parent = row
	local trackCorner = Instance.new("UICorner")
	trackCorner.CornerRadius = UDim.new(0, 6)
	trackCorner.Parent = progressTrack

	local progressFill = Instance.new("Frame")
	progressFill.BackgroundColor3 = if completed then Color3.fromRGB(122, 220, 142) else Color3.fromRGB(104, 166, 255)
	progressFill.BorderSizePixel = 0
	progressFill.Size = UDim2.new(ratio, 0, 1, 0)
	progressFill.Parent = progressTrack
	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0, 6)
	fillCorner.Parent = progressFill

	-- Progress text
	local progressLabel = Instance.new("TextLabel")
	progressLabel.BackgroundTransparency = 1
	progressLabel.Position = UDim2.fromOffset(12, 60)
	progressLabel.Size = UDim2.new(0.6, -24, 0, 14)
	progressLabel.Font = Enum.Font.Gotham
	progressLabel.TextSize = 11
	progressLabel.TextColor3 = Color3.fromRGB(178, 194, 220)
	progressLabel.TextXAlignment = Enum.TextXAlignment.Left
	progressLabel.Text = string.format("%d / %d", math.floor(progressValue + 0.5), targetValue)
	progressLabel.Parent = row

	-- Reward info (right side)
	local rewardCash = math.floor(tonumber(challenge.RewardCash) or 0)
	local rewardXP = math.floor(tonumber(challenge.RewardExperience) or 0)

	local rewardLabel = Instance.new("TextLabel")
	rewardLabel.BackgroundTransparency = 1
	rewardLabel.AnchorPoint = Vector2.new(1, 0)
	rewardLabel.Position = UDim2.new(1, -12, 0, 8)
	rewardLabel.Size = UDim2.fromOffset(120, 14)
	rewardLabel.Font = Enum.Font.GothamMedium
	rewardLabel.TextSize = 12
	rewardLabel.TextColor3 = Color3.fromRGB(241, 213, 140)
	rewardLabel.TextXAlignment = Enum.TextXAlignment.Right
	rewardLabel.Text = string.format("+$%d, +%d XP", rewardCash, rewardXP)
	rewardLabel.Parent = row

	-- Claim button / status (right side)
	if rewardClaimed then
		local claimedLabel = Instance.new("TextLabel")
		claimedLabel.BackgroundTransparency = 1
		claimedLabel.AnchorPoint = Vector2.new(1, 1)
		claimedLabel.Position = UDim2.new(1, -12, 1, -10)
		claimedLabel.Size = UDim2.fromOffset(100, 20)
		claimedLabel.Font = Enum.Font.GothamBold
		claimedLabel.TextSize = 13
		claimedLabel.TextColor3 = Color3.fromRGB(180, 255, 200)
		claimedLabel.TextXAlignment = Enum.TextXAlignment.Right
		claimedLabel.Text = "Claimed"
		claimedLabel.Parent = row
	elseif completed then
		local claimBtn = Instance.new("TextButton")
		claimBtn.Name = "ClaimBtn"
		claimBtn.AnchorPoint = Vector2.new(1, 1)
		claimBtn.Position = UDim2.new(1, -12, 1, -8)
		claimBtn.Size = UDim2.fromOffset(100, 30)
		claimBtn.Font = Enum.Font.GothamBold
		claimBtn.TextSize = 13
		claimBtn.Text = "Claim"
		claimBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
		claimBtn.BackgroundColor3 = Color3.fromRGB(52, 124, 203)
		claimBtn.AutoButtonColor = true
		claimBtn.Parent = row

		local btnCorner = Instance.new("UICorner")
		btnCorner.CornerRadius = UDim.new(0, 8)
		btnCorner.Parent = claimBtn

		-- Pulse to draw attention
		local pulse = Instance.new("UIStroke")
		pulse.Color = Color3.fromRGB(110, 190, 255)
		pulse.Thickness = 2
		pulse.Transparency = 0
		pulse.Parent = claimBtn
		local pulseInfo = TweenInfo.new(0.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
		TweenService:Create(pulse, pulseInfo, { Transparency = 0.6 }):Play()

		local challengeId = tostring(challenge.Id or "")
		claimBtn.Activated:Connect(function()
			claimBtn.Active = false
			claimBtn.Text = "..."
			task.spawn(function()
				local ok, result = pcall(function()
					return SeasonalEventPackets.ClaimChallengeReward:Fire({ ChallengeId = challengeId })
				end)
				if ok and typeof(result) == "table" and result.Success then
					Notification.Show({
						Title = "Challenge Reward Claimed",
						Text = string.format("+$%d, +%d XP", result.CashDistributed or 0, result.ExperienceDistributed or 0),
						Duration = 3,
						BackgroundColor = Color3.fromRGB(52, 130, 90),
					})
					SeasonalEventUI.RefreshStatus()
				else
					local errMsg = "Could not claim reward."
					if typeof(result) == "table" and typeof(result.ErrorMessage) == "string" and result.ErrorMessage ~= "" then
						errMsg = result.ErrorMessage
					end
					Notification.Show({
						Title = "Claim Failed",
						Text = errMsg,
						Duration = 3,
						BackgroundColor = Color3.fromRGB(132, 64, 64),
					})
					claimBtn.Active = true
					claimBtn.Text = "Claim"
				end
			end)
		end)
	else
		-- In progress
		local statusLabel = Instance.new("TextLabel")
		statusLabel.BackgroundTransparency = 1
		statusLabel.AnchorPoint = Vector2.new(1, 1)
		statusLabel.Position = UDim2.new(1, -12, 1, -10)
		statusLabel.Size = UDim2.fromOffset(100, 20)
		statusLabel.Font = Enum.Font.GothamMedium
		statusLabel.TextSize = 12
		statusLabel.TextColor3 = Color3.fromRGB(160, 174, 195)
		statusLabel.TextXAlignment = Enum.TextXAlignment.Right
		statusLabel.Text = "In Progress"
		statusLabel.Parent = row
	end

	return row
end

local function createBuffRow(buff: { [string]: any }, index: number): Frame
	local row = Instance.new("Frame")
	row.Name = "Buff_" .. tostring(index)
	row.LayoutOrder = index
	row.Size = UDim2.new(1, -4, 0, 34)
	row.BackgroundColor3 = Color3.fromRGB(25, 45, 63)
	row.BorderSizePixel = 0

	local cornerInst = Instance.new("UICorner")
	cornerInst.CornerRadius = UDim.new(0, 8)
	cornerInst.Parent = row

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Position = UDim2.fromOffset(10, 0)
	label.Size = UDim2.new(1, -20, 1, 0)
	label.Font = Enum.Font.GothamMedium
	label.TextSize = 13
	label.TextColor3 = Color3.fromRGB(212, 233, 255)
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Text = tostring(buff.Label or buff.Type or "Buff")
	label.Parent = row

	return row
end

local function createMilestoneRow(milestone: any, index: number, seasonsCompleted: number, claimedCount: number): Frame
	local isReached = seasonsCompleted >= milestone.SeasonsCompleted
	-- Milestones are ordered; assume first N are claimed if claimedCount == N
	local isClaimed = index <= claimedCount

	local row = Instance.new("Frame")
	row.Name = "Milestone_" .. tostring(milestone.SeasonsCompleted)
	row.LayoutOrder = index
	row.Size = UDim2.new(1, -4, 0, 52)
	row.BorderSizePixel = 0

	if isClaimed then
		row.BackgroundColor3 = MILESTONE_CLAIMED_COLOR
	elseif isReached then
		row.BackgroundColor3 = MILESTONE_COLOR
	else
		row.BackgroundColor3 = Color3.fromRGB(30, 36, 48)
	end

	local cornerInst = Instance.new("UICorner")
	cornerInst.CornerRadius = UDim.new(0, 8)
	cornerInst.Parent = row

	-- Label
	local nameLabel = Instance.new("TextLabel")
	nameLabel.BackgroundTransparency = 1
	nameLabel.Position = UDim2.fromOffset(10, 4)
	nameLabel.Size = UDim2.new(0.6, -10, 0, 18)
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextSize = 13
	nameLabel.TextColor3 = Color3.fromRGB(235, 243, 255)
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.Text = string.format("%s (%d seasons)", milestone.Label, milestone.SeasonsCompleted)
	nameLabel.Parent = row

	-- Reward info
	local rewardInfo = Instance.new("TextLabel")
	rewardInfo.BackgroundTransparency = 1
	rewardInfo.Position = UDim2.fromOffset(10, 24)
	rewardInfo.Size = UDim2.new(0.6, -10, 0, 14)
	rewardInfo.Font = Enum.Font.Gotham
	rewardInfo.TextSize = 11
	rewardInfo.TextColor3 = Color3.fromRGB(241, 213, 140)
	rewardInfo.TextXAlignment = Enum.TextXAlignment.Left
	rewardInfo.Text = string.format("+$%d, +%d XP", milestone.BonusCash, milestone.BonusExperience)
	rewardInfo.Parent = row

	-- Status / claim button (right side)
	if isClaimed then
		local claimedLabel = Instance.new("TextLabel")
		claimedLabel.BackgroundTransparency = 1
		claimedLabel.AnchorPoint = Vector2.new(1, 0.5)
		claimedLabel.Position = UDim2.new(1, -10, 0.5, 0)
		claimedLabel.Size = UDim2.fromOffset(80, 20)
		claimedLabel.Font = Enum.Font.GothamBold
		claimedLabel.TextSize = 13
		claimedLabel.TextColor3 = Color3.fromRGB(180, 255, 200)
		claimedLabel.TextXAlignment = Enum.TextXAlignment.Right
		claimedLabel.Text = "Claimed"
		claimedLabel.Parent = row
	elseif isReached then
		local claimBtn = Instance.new("TextButton")
		claimBtn.Name = "ClaimMilestoneBtn"
		claimBtn.AnchorPoint = Vector2.new(1, 0.5)
		claimBtn.Position = UDim2.new(1, -10, 0.5, 0)
		claimBtn.Size = UDim2.fromOffset(90, 28)
		claimBtn.Font = Enum.Font.GothamBold
		claimBtn.TextSize = 13
		claimBtn.Text = "Claim"
		claimBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
		claimBtn.BackgroundColor3 = Color3.fromRGB(181, 134, 52)
		claimBtn.AutoButtonColor = true
		claimBtn.Parent = row

		local btnCorner = Instance.new("UICorner")
		btnCorner.CornerRadius = UDim.new(0, 8)
		btnCorner.Parent = claimBtn

		local milestoneSeasonsCompleted = milestone.SeasonsCompleted
		claimBtn.Activated:Connect(function()
			claimBtn.Active = false
			claimBtn.Text = "..."
			task.spawn(function()
				local ok, result = pcall(function()
					return SeasonalEventPackets.ClaimMilestoneReward:Fire({ SeasonsCompleted = milestoneSeasonsCompleted })
				end)
				if ok and typeof(result) == "table" and result.Success then
					Notification.Show({
						Title = "Milestone Reward Claimed",
						Text = string.format("%s: +$%d, +%d XP", tostring(result.RewardName or milestone.Label), result.CashDistributed or 0, result.ExperienceDistributed or 0),
						Duration = 3,
						BackgroundColor = Color3.fromRGB(140, 120, 50),
					})
					SeasonalEventUI.RefreshStatus()
				else
					local errMsg = "Could not claim milestone."
					if typeof(result) == "table" and typeof(result.ErrorMessage) == "string" and result.ErrorMessage ~= "" then
						errMsg = result.ErrorMessage
					end
					Notification.Show({
						Title = "Claim Failed",
						Text = errMsg,
						Duration = 3,
						BackgroundColor = Color3.fromRGB(132, 64, 64),
					})
					claimBtn.Active = true
					claimBtn.Text = "Claim"
				end
			end)
		end)
	else
		-- Not reached yet
		local progressLabel = Instance.new("TextLabel")
		progressLabel.BackgroundTransparency = 1
		progressLabel.AnchorPoint = Vector2.new(1, 0.5)
		progressLabel.Position = UDim2.new(1, -10, 0.5, 0)
		progressLabel.Size = UDim2.fromOffset(80, 20)
		progressLabel.Font = Enum.Font.GothamMedium
		progressLabel.TextSize = 12
		progressLabel.TextColor3 = Color3.fromRGB(160, 174, 195)
		progressLabel.TextXAlignment = Enum.TextXAlignment.Right
		progressLabel.Text = string.format("%d/%d", math.min(seasonsCompleted, milestone.SeasonsCompleted), milestone.SeasonsCompleted)
		progressLabel.Parent = row
	end

	return row
end

local function applySeasonColor(seasonId: string)
	if not bannerFrame then
		return
	end
	local target = seasonColors[seasonId] or Color3.fromRGB(76, 132, 191)
	TweenService:Create(bannerFrame, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		BackgroundColor3 = target,
	}):Play()
end

local function renderStatus(status: { [string]: any })
	if not seasonTitleLabel or not seasonDescriptionLabel or not seasonStatsLabel or not challengeList or not buffsList or not milestoneList then
		return
	end

	local seasonName = tostring(status.SeasonName or status.CurrentSeason or "Season")
	local seasonId = tostring(status.CurrentSeason or "Spring")
	seasonTitleLabel.Text = seasonName
	seasonDescriptionLabel.Text = tostring(status.SeasonDescription or "")

	local seasonsCompleted = math.max(0, math.floor(tonumber(status.SeasonsCompleted) or 0))
	local totalChallenges = math.max(0, math.floor(tonumber(status.TotalChallengesCompleted) or 0))
	local claimedMilestones = math.max(0, math.floor(tonumber(status.ClaimedMilestonesCount) or 0))
	local totalMilestones = #SeasonalEventDefinitions.Milestones

	seasonStatsLabel.Text = string.format(
		"Seasons: %d | Challenges: %d | Milestones: %d/%d",
		seasonsCompleted, totalChallenges, claimedMilestones, totalMilestones
	)
	applySeasonColor(seasonId)

	-- Render challenges
	clearRows(challengeList)
	local challenges = status.Challenges
	if typeof(challenges) == "table" and #challenges > 0 then
		for index, challenge in ipairs(challenges) do
			local row = createChallengeRow(challenge, index)
			row.Parent = challengeList
		end
	end

	-- Render buffs
	clearRows(buffsList)
	local buffs = status.Buffs
	if typeof(buffs) == "table" and #buffs > 0 then
		for index, buff in ipairs(buffs) do
			local row = createBuffRow(buff, index)
			row.Parent = buffsList
		end
	end

	-- Render milestones
	clearRows(milestoneList)
	local milestones = SeasonalEventDefinitions.Milestones
	for index, milestone in ipairs(milestones) do
		local row = createMilestoneRow(milestone, index, seasonsCompleted, claimedMilestones)
		row.Parent = milestoneList
	end
end

local function ensureGui()
	if gui and gui.Parent then
		return
	end

	gui = Instance.new("ScreenGui")
	gui.Name = "SeasonalEventUI"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 35
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
	window.Size = UDim2.fromOffset(660, 560)
	window.BackgroundColor3 = Color3.fromRGB(24, 29, 38)
	window.BorderSizePixel = 0
	window.Parent = overlay

	local windowCorner = Instance.new("UICorner")
	windowCorner.CornerRadius = UDim.new(0, 12)
	windowCorner.Parent = window

	local windowStroke = Instance.new("UIStroke")
	windowStroke.Color = Color3.fromRGB(95, 116, 153)
	windowStroke.Thickness = 1
	windowStroke.Transparency = 0.35
	windowStroke.Parent = window

	-- Season banner header (colored)
	local banner = Instance.new("Frame")
	banner.Name = "SeasonBanner"
	banner.Size = UDim2.new(1, 0, 0, 74)
	banner.BackgroundColor3 = Color3.fromRGB(76, 132, 191)
	banner.BorderSizePixel = 0
	banner.Parent = window
	bannerFrame = banner

	local bannerCorner = Instance.new("UICorner")
	bannerCorner.CornerRadius = UDim.new(0, 12)
	bannerCorner.Parent = banner

	-- Mask the bottom corners of the banner so it blends with the window
	local bannerMask = Instance.new("Frame")
	bannerMask.Name = "BottomMask"
	bannerMask.AnchorPoint = Vector2.new(0, 1)
	bannerMask.Position = UDim2.new(0, 0, 1, 0)
	bannerMask.Size = UDim2.new(1, 0, 0, 14)
	bannerMask.BackgroundColor3 = banner.BackgroundColor3
	bannerMask.BorderSizePixel = 0
	bannerMask.Parent = banner

	-- Keep the mask color in sync when season changes
	banner:GetPropertyChangedSignal("BackgroundColor3"):Connect(function()
		bannerMask.BackgroundColor3 = banner.BackgroundColor3
	end)

	local seasonTitle = Instance.new("TextLabel")
	seasonTitle.BackgroundTransparency = 1
	seasonTitle.Position = UDim2.fromOffset(20, 10)
	seasonTitle.Size = UDim2.new(0.7, -20, 0, 26)
	seasonTitle.Font = Enum.Font.GothamBold
	seasonTitle.TextSize = 22
	seasonTitle.TextColor3 = Color3.fromRGB(243, 248, 255)
	seasonTitle.TextXAlignment = Enum.TextXAlignment.Left
	seasonTitle.Text = "Season"
	seasonTitle.Parent = banner
	seasonTitleLabel = seasonTitle

	local seasonDescription = Instance.new("TextLabel")
	seasonDescription.BackgroundTransparency = 1
	seasonDescription.Position = UDim2.fromOffset(20, 36)
	seasonDescription.Size = UDim2.new(0.7, -20, 0, 16)
	seasonDescription.Font = Enum.Font.Gotham
	seasonDescription.TextSize = 12
	seasonDescription.TextColor3 = Color3.fromRGB(224, 236, 252)
	seasonDescription.TextXAlignment = Enum.TextXAlignment.Left
	seasonDescription.Text = ""
	seasonDescription.Parent = banner
	seasonDescriptionLabel = seasonDescription

	local seasonStats = Instance.new("TextLabel")
	seasonStats.BackgroundTransparency = 1
	seasonStats.Position = UDim2.fromOffset(20, 54)
	seasonStats.Size = UDim2.new(0.7, -20, 0, 14)
	seasonStats.Font = Enum.Font.GothamMedium
	seasonStats.TextSize = 11
	seasonStats.TextColor3 = Color3.fromRGB(212, 228, 250)
	seasonStats.TextXAlignment = Enum.TextXAlignment.Left
	seasonStats.Text = ""
	seasonStats.Parent = banner
	seasonStatsLabel = seasonStats

	-- Close button
	local close = Instance.new("TextButton")
	close.Name = "Close"
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, -14, 0, 14)
	close.Size = UDim2.fromOffset(36, 36)
	close.Text = "X"
	close.Font = Enum.Font.GothamBold
	close.TextSize = 16
	close.TextColor3 = Color3.fromRGB(223, 231, 246)
	close.BackgroundColor3 = Color3.fromRGB(44, 53, 71)
	close.BackgroundTransparency = 0.3
	close.AutoButtonColor = true
	close.Parent = banner
	local closeCorner = Instance.new("UICorner")
	closeCorner.CornerRadius = UDim.new(1, 0)
	closeCorner.Parent = close
	close.Activated:Connect(function()
		SeasonalEventUI.SetVisible(false)
	end)

	-- Content area below banner
	local contentY = 82

	-- Challenges section
	local challengesTitle = Instance.new("TextLabel")
	challengesTitle.BackgroundTransparency = 1
	challengesTitle.Position = UDim2.fromOffset(22, contentY)
	challengesTitle.Size = UDim2.new(0.5, -22, 0, 20)
	challengesTitle.Font = Enum.Font.GothamBold
	challengesTitle.TextSize = 16
	challengesTitle.TextColor3 = Color3.fromRGB(233, 240, 255)
	challengesTitle.TextXAlignment = Enum.TextXAlignment.Left
	challengesTitle.Text = "Season Challenges"
	challengesTitle.Parent = window

	local challengeScroll = Instance.new("ScrollingFrame")
	challengeScroll.Name = "ChallengeList"
	challengeScroll.Position = UDim2.fromOffset(16, contentY + 24)
	challengeScroll.Size = UDim2.new(0.5, -24, 0, 210)
	challengeScroll.BackgroundColor3 = Color3.fromRGB(18, 22, 30)
	challengeScroll.BackgroundTransparency = 0.08
	challengeScroll.BorderSizePixel = 0
	challengeScroll.ScrollBarThickness = 5
	challengeScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	challengeScroll.CanvasSize = UDim2.fromOffset(0, 0)
	challengeScroll.Parent = window
	challengeList = challengeScroll

	local challengeScrollCorner = Instance.new("UICorner")
	challengeScrollCorner.CornerRadius = UDim.new(0, 10)
	challengeScrollCorner.Parent = challengeScroll

	local challengeLayout = Instance.new("UIListLayout")
	challengeLayout.Padding = UDim.new(0, 6)
	challengeLayout.SortOrder = Enum.SortOrder.LayoutOrder
	challengeLayout.Parent = challengeScroll

	local challengePadding = Instance.new("UIPadding")
	challengePadding.PaddingLeft = UDim.new(0, 6)
	challengePadding.PaddingRight = UDim.new(0, 6)
	challengePadding.PaddingTop = UDim.new(0, 6)
	challengePadding.PaddingBottom = UDim.new(0, 6)
	challengePadding.Parent = challengeScroll

	-- Active Buffs section (right column, top)
	local buffsTitle = Instance.new("TextLabel")
	buffsTitle.BackgroundTransparency = 1
	buffsTitle.Position = UDim2.new(0.5, 8, 0, contentY)
	buffsTitle.Size = UDim2.new(0.5, -30, 0, 20)
	buffsTitle.Font = Enum.Font.GothamBold
	buffsTitle.TextSize = 16
	buffsTitle.TextColor3 = Color3.fromRGB(233, 240, 255)
	buffsTitle.TextXAlignment = Enum.TextXAlignment.Left
	buffsTitle.Text = "Active Buffs"
	buffsTitle.Parent = window

	local buffScroll = Instance.new("ScrollingFrame")
	buffScroll.Name = "BuffsList"
	buffScroll.Position = UDim2.new(0.5, 8, 0, contentY + 24)
	buffScroll.Size = UDim2.new(0.5, -24, 0, 80)
	buffScroll.BackgroundColor3 = Color3.fromRGB(18, 22, 30)
	buffScroll.BackgroundTransparency = 0.08
	buffScroll.BorderSizePixel = 0
	buffScroll.ScrollBarThickness = 4
	buffScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	buffScroll.CanvasSize = UDim2.fromOffset(0, 0)
	buffScroll.Parent = window
	buffsList = buffScroll

	local buffScrollCorner = Instance.new("UICorner")
	buffScrollCorner.CornerRadius = UDim.new(0, 10)
	buffScrollCorner.Parent = buffScroll

	local buffLayout = Instance.new("UIListLayout")
	buffLayout.Padding = UDim.new(0, 6)
	buffLayout.SortOrder = Enum.SortOrder.LayoutOrder
	buffLayout.Parent = buffScroll

	local buffPadding = Instance.new("UIPadding")
	buffPadding.PaddingLeft = UDim.new(0, 6)
	buffPadding.PaddingRight = UDim.new(0, 6)
	buffPadding.PaddingTop = UDim.new(0, 6)
	buffPadding.PaddingBottom = UDim.new(0, 6)
	buffPadding.Parent = buffScroll

	-- Milestones section (right column, below buffs)
	local milestonesY = contentY + 114
	local milestonesTitle = Instance.new("TextLabel")
	milestonesTitle.BackgroundTransparency = 1
	milestonesTitle.Position = UDim2.new(0.5, 8, 0, milestonesY)
	milestonesTitle.Size = UDim2.new(0.5, -30, 0, 20)
	milestonesTitle.Font = Enum.Font.GothamBold
	milestonesTitle.TextSize = 16
	milestonesTitle.TextColor3 = Color3.fromRGB(233, 240, 255)
	milestonesTitle.TextXAlignment = Enum.TextXAlignment.Left
	milestonesTitle.Text = "Season Milestones"
	milestonesTitle.Parent = window

	local milestoneScroll = Instance.new("ScrollingFrame")
	milestoneScroll.Name = "MilestoneList"
	milestoneScroll.Position = UDim2.new(0.5, 8, 0, milestonesY + 24)
	milestoneScroll.Size = UDim2.new(0.5, -24, 0, 120)
	milestoneScroll.BackgroundColor3 = Color3.fromRGB(18, 22, 30)
	milestoneScroll.BackgroundTransparency = 0.08
	milestoneScroll.BorderSizePixel = 0
	milestoneScroll.ScrollBarThickness = 4
	milestoneScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	milestoneScroll.CanvasSize = UDim2.fromOffset(0, 0)
	milestoneScroll.Parent = window
	milestoneList = milestoneScroll

	local milestoneScrollCorner = Instance.new("UICorner")
	milestoneScrollCorner.CornerRadius = UDim.new(0, 10)
	milestoneScrollCorner.Parent = milestoneScroll

	local milestoneLayout = Instance.new("UIListLayout")
	milestoneLayout.Padding = UDim.new(0, 6)
	milestoneLayout.SortOrder = Enum.SortOrder.LayoutOrder
	milestoneLayout.Parent = milestoneScroll

	local milestonePadding = Instance.new("UIPadding")
	milestonePadding.PaddingLeft = UDim.new(0, 6)
	milestonePadding.PaddingRight = UDim.new(0, 6)
	milestonePadding.PaddingTop = UDim.new(0, 6)
	milestonePadding.PaddingBottom = UDim.new(0, 6)
	milestonePadding.Parent = milestoneScroll

	-- Distribute All Rewards button (bottom bar)
	local distributeBtn = Instance.new("TextButton")
	distributeBtn.Name = "DistributeAll"
	distributeBtn.AnchorPoint = Vector2.new(0.5, 1)
	distributeBtn.Position = UDim2.new(0.5, 0, 1, -16)
	distributeBtn.Size = UDim2.fromOffset(220, 40)
	distributeBtn.Font = Enum.Font.GothamBold
	distributeBtn.TextSize = 15
	distributeBtn.Text = "Claim All Rewards"
	distributeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	distributeBtn.BackgroundColor3 = Color3.fromRGB(56, 108, 174)
	distributeBtn.AutoButtonColor = true
	distributeBtn.Parent = window

	local distributeBtnCorner = Instance.new("UICorner")
	distributeBtnCorner.CornerRadius = UDim.new(0, 10)
	distributeBtnCorner.Parent = distributeBtn

	distributeBtn.Activated:Connect(function()
		distributeBtn.Active = false
		distributeBtn.Text = "Claiming..."
		task.spawn(function()
			local ok, result = pcall(function()
				return SeasonalEventPackets.DistributeAllRewards:Fire()
			end)
			if ok and typeof(result) == "table" and result.Success then
				local cash = result.CashDistributed or 0
				local xp = result.ExperienceDistributed or 0
				if cash > 0 or xp > 0 then
					Notification.Show({
						Title = "All Rewards Claimed",
						Text = string.format("+$%d, +%d XP", cash, xp),
						Duration = 4,
						BackgroundColor = Color3.fromRGB(52, 130, 90),
					})
				else
					Notification.Show({
						Title = "No Rewards",
						Text = "No pending rewards to claim.",
						Duration = 3,
						BackgroundColor = Color3.fromRGB(80, 90, 100),
					})
				end
				SeasonalEventUI.RefreshStatus()
			else
				local errMsg = "Could not claim rewards."
				if typeof(result) == "table" and typeof(result.ErrorMessage) == "string" and result.ErrorMessage ~= "" then
					errMsg = result.ErrorMessage
				end
				Notification.Show({
					Title = "Claim Failed",
					Text = errMsg,
					Duration = 3,
					BackgroundColor = Color3.fromRGB(132, 64, 64),
				})
				distributeBtn.Active = true
				distributeBtn.Text = "Claim All Rewards"
			end
		end)
	end)

	-- Mobile constraint
	local mobileConstraint = Instance.new("UISizeConstraint")
	mobileConstraint.MinSize = Vector2.new(460, 480)
	mobileConstraint.MaxSize = Vector2.new(740, 600)
	mobileConstraint.Parent = window
end

function SeasonalEventUI.RefreshStatus()
	task.spawn(function()
		local ok, payload = pcall(function()
			return SeasonalEventPackets.GetSeasonStatus:Fire()
		end)
		if ok and typeof(payload) == "table" then
			renderStatus(payload)
		end
	end)
end

function SeasonalEventUI.SetVisible(visible: boolean)
	ensureGui()
	open = visible
	if gui then
		gui.Enabled = visible
	end
	if visible then
		SeasonalEventUI.RefreshStatus()
	end
end

function SeasonalEventUI.Toggle()
	SeasonalEventUI.SetVisible(not open)
end

function SeasonalEventUI.Init()
	if initialized then
		return
	end
	initialized = true

	ensureGui()

	-- Listen for server-pushed season transitions
	SeasonalEventPackets.SeasonTransitioned.OnClientEvent:Connect(function(payload)
		if typeof(payload) == "table" then
			local seasonName = tostring(payload.SeasonName or payload.NewSeason or "Season")
			Notification.Show({
				Title = "Season Updated",
				Text = string.format("%s has begun.", seasonName),
				Duration = 3,
				BackgroundColor = Color3.fromRGB(56, 108, 174),
			})
		end
		SeasonalEventUI.RefreshStatus()
	end)

	-- Listen for server-pushed challenge completions
	SeasonalEventPackets.ChallengeCompleted.OnClientEvent:Connect(function(payload)
		if typeof(payload) == "table" then
			Notification.Show({
				Title = "Seasonal Challenge Complete",
				Text = tostring(payload.Name or "Challenge complete") .. " - open Seasons to claim!",
				Duration = 4,
				BackgroundColor = Color3.fromRGB(64, 134, 92),
			})
		end
		SeasonalEventUI.RefreshStatus()
	end)

	-- Fetch initial status
	SeasonalEventUI.RefreshStatus()
end

return SeasonalEventUI
