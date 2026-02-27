--!strict
-- DailyRewardUI: Client-side daily reward interface with streak calendar,
-- claim button, countdown timer, and milestone display.
-- Follows established UI patterns (AchievementUI, SeasonalEventUI).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local DailyRewardPackets = require(ReplicatedStorage.Network.DailyRewardPackets)
local DailyRewardDefinitions = require(ReplicatedStorage.Shared.Definitions.DailyRewardDefinitions)
local Notification = require(script.Parent.Notification)

local DailyRewardUI = {}

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

local gui: ScreenGui? = nil
local windowFrame: Frame? = nil
local headerLabel: TextLabel? = nil
local streakLabel: TextLabel? = nil
local claimButton: TextButton? = nil
local countdownLabel: TextLabel? = nil
local calendarFrame: Frame? = nil
local milestoneFrame: Frame? = nil
local statsLabel: TextLabel? = nil

local open = false
local initialized = false
local countdownActive = false

-- Cached status from server
local cachedStatus: { [string]: any }? = nil

-- Day cell colors
local DAY_COLORS = {
	Claimed = Color3.fromRGB(56, 140, 88),
	Current = Color3.fromRGB(52, 124, 203),
	Upcoming = Color3.fromRGB(40, 48, 64),
}

local MILESTONE_COLOR = Color3.fromRGB(181, 134, 52)
local MILESTONE_CLAIMED_COLOR = Color3.fromRGB(56, 102, 76)

local function formatTime(seconds: number): string
	if seconds <= 0 then
		return "Ready!"
	end
	local hours = math.floor(seconds / 3600)
	local mins = math.floor((seconds % 3600) / 60)
	local secs = math.floor(seconds % 60)
	if hours > 0 then
		return string.format("%dh %02dm %02ds", hours, mins, secs)
	elseif mins > 0 then
		return string.format("%dm %02ds", mins, secs)
	else
		return string.format("%ds", secs)
	end
end

local function clearChildren(container: Frame)
	for _, child in ipairs(container:GetChildren()) do
		if child:IsA("Frame") or child:IsA("TextLabel") then
			child:Destroy()
		end
	end
end

-- Create a single day cell for the 7-day calendar strip
local function createDayCell(dayIndex: number, reward: any, currentStreak: number, canClaim: boolean): Frame
	local isClaimed = dayIndex <= currentStreak
	local isCurrent = dayIndex == currentStreak + 1
	local isNext = dayIndex > currentStreak + 1

	local cell = Instance.new("Frame")
	cell.Name = "Day_" .. tostring(dayIndex)
	cell.LayoutOrder = dayIndex
	cell.Size = UDim2.new(1 / 7, -6, 1, 0)
	cell.BorderSizePixel = 0

	if isClaimed then
		cell.BackgroundColor3 = DAY_COLORS.Claimed
	elseif isCurrent then
		cell.BackgroundColor3 = DAY_COLORS.Current
	else
		cell.BackgroundColor3 = DAY_COLORS.Upcoming
	end

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = cell

	-- Day number label
	local dayLabel = Instance.new("TextLabel")
	dayLabel.Name = "DayNumber"
	dayLabel.BackgroundTransparency = 1
	dayLabel.Position = UDim2.fromOffset(0, 4)
	dayLabel.Size = UDim2.new(1, 0, 0, 16)
	dayLabel.Font = Enum.Font.GothamBold
	dayLabel.TextSize = 12
	dayLabel.TextColor3 = Color3.fromRGB(235, 243, 255)
	dayLabel.Text = "Day " .. tostring(dayIndex)
	dayLabel.Parent = cell

	-- Reward label
	local rewardLabel = Instance.new("TextLabel")
	rewardLabel.Name = "Reward"
	rewardLabel.BackgroundTransparency = 1
	rewardLabel.Position = UDim2.fromOffset(0, 22)
	rewardLabel.Size = UDim2.new(1, 0, 0, 14)
	rewardLabel.Font = Enum.Font.GothamMedium
	rewardLabel.TextSize = 10
	rewardLabel.TextColor3 = Color3.fromRGB(241, 213, 140)
	rewardLabel.Text = string.format("$%d", reward.Cash)
	rewardLabel.Parent = cell

	-- XP label
	local xpLabel = Instance.new("TextLabel")
	xpLabel.Name = "XP"
	xpLabel.BackgroundTransparency = 1
	xpLabel.Position = UDim2.fromOffset(0, 36)
	xpLabel.Size = UDim2.new(1, 0, 0, 14)
	xpLabel.Font = Enum.Font.Gotham
	xpLabel.TextSize = 10
	xpLabel.TextColor3 = Color3.fromRGB(178, 194, 220)
	xpLabel.Text = string.format("+%d XP", reward.Experience)
	xpLabel.Parent = cell

	-- Reward name label
	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "Label"
	nameLabel.BackgroundTransparency = 1
	nameLabel.Position = UDim2.fromOffset(0, 52)
	nameLabel.Size = UDim2.new(1, 0, 0, 14)
	nameLabel.Font = Enum.Font.Gotham
	nameLabel.TextSize = 9
	nameLabel.TextColor3 = Color3.fromRGB(160, 174, 195)
	nameLabel.Text = reward.Label
	nameLabel.Parent = cell

	-- Check mark for claimed days
	if isClaimed then
		local checkLabel = Instance.new("TextLabel")
		checkLabel.Name = "Check"
		checkLabel.BackgroundTransparency = 1
		checkLabel.Position = UDim2.fromOffset(0, 68)
		checkLabel.Size = UDim2.new(1, 0, 0, 16)
		checkLabel.Font = Enum.Font.GothamBold
		checkLabel.TextSize = 14
		checkLabel.TextColor3 = Color3.fromRGB(180, 255, 200)
		checkLabel.Text = "Claimed"
		checkLabel.Parent = cell
	elseif isCurrent and canClaim then
		-- Pulsing highlight for claimable day
		local highlight = Instance.new("UIStroke")
		highlight.Color = Color3.fromRGB(110, 190, 255)
		highlight.Thickness = 2
		highlight.Transparency = 0
		highlight.Parent = cell

		local pulseInfo = TweenInfo.new(0.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
		TweenService:Create(highlight, pulseInfo, { Transparency = 0.6 }):Play()
	end

	return cell
end

-- Create a milestone row
local function createMilestoneRow(milestone: any, index: number, longestStreak: number, claimedMilestones: { [string]: any }?): Frame
	local isReached = longestStreak >= milestone.StreakRequired
	local isClaimed = claimedMilestones and claimedMilestones[tostring(milestone.StreakRequired)] == true

	local row = Instance.new("Frame")
	row.Name = "Milestone_" .. tostring(milestone.StreakRequired)
	row.LayoutOrder = index
	row.Size = UDim2.new(1, -4, 0, 42)
	row.BackgroundColor3 = if isClaimed then MILESTONE_CLAIMED_COLOR elseif isReached then MILESTONE_COLOR else Color3.fromRGB(30, 36, 48)
	row.BorderSizePixel = 0

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = row

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Position = UDim2.fromOffset(10, 4)
	label.Size = UDim2.new(0.6, -10, 0, 18)
	label.Font = Enum.Font.GothamBold
	label.TextSize = 13
	label.TextColor3 = Color3.fromRGB(235, 243, 255)
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Text = string.format("%s (%d-day streak)", milestone.Label, milestone.StreakRequired)
	label.Parent = row

	local rewardInfo = Instance.new("TextLabel")
	rewardInfo.BackgroundTransparency = 1
	rewardInfo.Position = UDim2.fromOffset(10, 22)
	rewardInfo.Size = UDim2.new(0.6, -10, 0, 16)
	rewardInfo.Font = Enum.Font.Gotham
	rewardInfo.TextSize = 11
	rewardInfo.TextColor3 = Color3.fromRGB(241, 213, 140)
	rewardInfo.TextXAlignment = Enum.TextXAlignment.Left
	rewardInfo.Text = string.format("+$%d, +%d XP", milestone.BonusCash, milestone.BonusExperience)
	rewardInfo.Parent = row

	local statusLabel = Instance.new("TextLabel")
	statusLabel.BackgroundTransparency = 1
	statusLabel.AnchorPoint = Vector2.new(1, 0.5)
	statusLabel.Position = UDim2.new(1, -10, 0.5, 0)
	statusLabel.Size = UDim2.fromOffset(80, 20)
	statusLabel.Font = Enum.Font.GothamMedium
	statusLabel.TextSize = 12
	statusLabel.TextXAlignment = Enum.TextXAlignment.Right
	if isClaimed then
		statusLabel.Text = "Claimed"
		statusLabel.TextColor3 = Color3.fromRGB(180, 255, 200)
	elseif isReached then
		statusLabel.Text = "Earned!"
		statusLabel.TextColor3 = Color3.fromRGB(255, 220, 120)
	else
		statusLabel.Text = string.format("%d/%d", math.min(longestStreak, milestone.StreakRequired), milestone.StreakRequired)
		statusLabel.TextColor3 = Color3.fromRGB(160, 174, 195)
	end
	statusLabel.Parent = row

	return row
end

local function ensureGui()
	if gui and gui.Parent then
		return
	end

	gui = Instance.new("ScreenGui")
	gui.Name = "DailyRewardUI"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 55
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
	window.Size = UDim2.fromOffset(640, 480)
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

	-- Header section
	local header = Instance.new("Frame")
	header.Name = "Header"
	header.Size = UDim2.new(1, 0, 0, 60)
	header.BackgroundTransparency = 1
	header.Parent = window

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.Position = UDim2.fromOffset(24, 12)
	title.Size = UDim2.fromOffset(320, 26)
	title.Font = Enum.Font.GothamBold
	title.TextSize = 22
	title.TextColor3 = Color3.fromRGB(244, 249, 255)
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Text = "Daily Rewards"
	title.Parent = header
	headerLabel = title

	local subtitle = Instance.new("TextLabel")
	subtitle.Name = "Subtitle"
	subtitle.BackgroundTransparency = 1
	subtitle.Position = UDim2.fromOffset(24, 38)
	subtitle.Size = UDim2.fromOffset(320, 18)
	subtitle.Font = Enum.Font.Gotham
	subtitle.TextSize = 13
	subtitle.TextColor3 = Color3.fromRGB(176, 188, 205)
	subtitle.TextXAlignment = Enum.TextXAlignment.Left
	subtitle.Text = "Login daily to earn escalating rewards!"
	subtitle.Parent = header

	-- Streak counter
	local streak = Instance.new("TextLabel")
	streak.Name = "StreakLabel"
	streak.BackgroundTransparency = 1
	streak.AnchorPoint = Vector2.new(1, 0)
	streak.Position = UDim2.new(1, -70, 0, 10)
	streak.Size = UDim2.fromOffset(200, 22)
	streak.Font = Enum.Font.GothamBold
	streak.TextSize = 18
	streak.TextColor3 = Color3.fromRGB(255, 200, 80)
	streak.TextXAlignment = Enum.TextXAlignment.Right
	streak.Text = "Streak: 0"
	streak.Parent = header
	streakLabel = streak

	-- Stats label (total claimed, total earned)
	local stats = Instance.new("TextLabel")
	stats.Name = "StatsLabel"
	stats.BackgroundTransparency = 1
	stats.AnchorPoint = Vector2.new(1, 0)
	stats.Position = UDim2.new(1, -70, 0, 34)
	stats.Size = UDim2.fromOffset(200, 16)
	stats.Font = Enum.Font.Gotham
	stats.TextSize = 11
	stats.TextColor3 = Color3.fromRGB(160, 174, 195)
	stats.TextXAlignment = Enum.TextXAlignment.Right
	stats.Text = ""
	stats.Parent = header
	statsLabel = stats

	-- Close button
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
		DailyRewardUI.SetVisible(false)
	end)

	-- 7-day calendar strip
	local calendar = Instance.new("Frame")
	calendar.Name = "Calendar"
	calendar.Position = UDim2.fromOffset(20, 68)
	calendar.Size = UDim2.new(1, -40, 0, 90)
	calendar.BackgroundColor3 = Color3.fromRGB(18, 22, 30)
	calendar.BackgroundTransparency = 0.08
	calendar.BorderSizePixel = 0
	calendar.Parent = window
	calendarFrame = calendar

	local calendarCorner = Instance.new("UICorner")
	calendarCorner.CornerRadius = UDim.new(0, 10)
	calendarCorner.Parent = calendar

	local calendarLayout = Instance.new("UIListLayout")
	calendarLayout.FillDirection = Enum.FillDirection.Horizontal
	calendarLayout.SortOrder = Enum.SortOrder.LayoutOrder
	calendarLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	calendarLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	calendarLayout.Padding = UDim.new(0, 4)
	calendarLayout.Parent = calendar

	local calendarPadding = Instance.new("UIPadding")
	calendarPadding.PaddingLeft = UDim.new(0, 6)
	calendarPadding.PaddingRight = UDim.new(0, 6)
	calendarPadding.PaddingTop = UDim.new(0, 6)
	calendarPadding.PaddingBottom = UDim.new(0, 6)
	calendarPadding.Parent = calendar

	-- Claim section
	local claimSection = Instance.new("Frame")
	claimSection.Name = "ClaimSection"
	claimSection.Position = UDim2.fromOffset(20, 170)
	claimSection.Size = UDim2.new(1, -40, 0, 60)
	claimSection.BackgroundTransparency = 1
	claimSection.Parent = window

	-- Claim button
	local claim = Instance.new("TextButton")
	claim.Name = "ClaimButton"
	claim.AnchorPoint = Vector2.new(0.5, 0)
	claim.Position = UDim2.new(0.5, 0, 0, 0)
	claim.Size = UDim2.fromOffset(240, 44)
	claim.Font = Enum.Font.GothamBold
	claim.TextSize = 18
	claim.Text = "Claim Reward"
	claim.TextColor3 = Color3.fromRGB(255, 255, 255)
	claim.BackgroundColor3 = Color3.fromRGB(52, 124, 203)
	claim.AutoButtonColor = true
	claim.Parent = claimSection
	claimButton = claim

	local claimCorner = Instance.new("UICorner")
	claimCorner.CornerRadius = UDim.new(0, 10)
	claimCorner.Parent = claim

	-- Countdown timer label (below claim button)
	local countdown = Instance.new("TextLabel")
	countdown.Name = "Countdown"
	countdown.BackgroundTransparency = 1
	countdown.AnchorPoint = Vector2.new(0.5, 0)
	countdown.Position = UDim2.new(0.5, 0, 0, 48)
	countdown.Size = UDim2.fromOffset(300, 16)
	countdown.Font = Enum.Font.GothamMedium
	countdown.TextSize = 12
	countdown.TextColor3 = Color3.fromRGB(160, 174, 195)
	countdown.Text = ""
	countdown.Parent = claimSection
	countdownLabel = countdown

	-- Milestones section
	local milestonesTitle = Instance.new("TextLabel")
	milestonesTitle.Name = "MilestonesTitle"
	milestonesTitle.BackgroundTransparency = 1
	milestonesTitle.Position = UDim2.fromOffset(24, 242)
	milestonesTitle.Size = UDim2.new(1, -48, 0, 22)
	milestonesTitle.Font = Enum.Font.GothamBold
	milestonesTitle.TextSize = 16
	milestonesTitle.TextColor3 = Color3.fromRGB(233, 240, 255)
	milestonesTitle.TextXAlignment = Enum.TextXAlignment.Left
	milestonesTitle.Text = "Streak Milestones"
	milestonesTitle.Parent = window

	local milestones = Instance.new("Frame")
	milestones.Name = "Milestones"
	milestones.Position = UDim2.fromOffset(20, 268)
	milestones.Size = UDim2.new(1, -40, 0, 190)
	milestones.BackgroundColor3 = Color3.fromRGB(18, 22, 30)
	milestones.BackgroundTransparency = 0.08
	milestones.BorderSizePixel = 0
	milestones.Parent = window
	milestoneFrame = milestones

	local milestoneCorner = Instance.new("UICorner")
	milestoneCorner.CornerRadius = UDim.new(0, 10)
	milestoneCorner.Parent = milestones

	local milestoneLayout = Instance.new("UIListLayout")
	milestoneLayout.SortOrder = Enum.SortOrder.LayoutOrder
	milestoneLayout.Padding = UDim.new(0, 6)
	milestoneLayout.Parent = milestones

	local milestonePadding = Instance.new("UIPadding")
	milestonePadding.PaddingLeft = UDim.new(0, 8)
	milestonePadding.PaddingRight = UDim.new(0, 8)
	milestonePadding.PaddingTop = UDim.new(0, 8)
	milestonePadding.PaddingBottom = UDim.new(0, 8)
	milestonePadding.Parent = milestones

	-- Mobile constraint
	local mobileConstraint = Instance.new("UISizeConstraint")
	mobileConstraint.MinSize = Vector2.new(420, 460)
	mobileConstraint.MaxSize = Vector2.new(720, 520)
	mobileConstraint.Parent = window

	-- Wire claim button
	claim.Activated:Connect(function()
		DailyRewardUI.ClaimReward()
	end)
end

local function renderCalendar(currentStreak: number, canClaim: boolean)
	if not calendarFrame then
		return
	end

	-- Clear existing day cells (keep UIListLayout and UIPadding)
	for _, child in ipairs(calendarFrame:GetChildren()) do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end

	-- Use streak modulo cycle to determine which days in the 7-day cycle are claimed
	local cyclePosition = currentStreak % DailyRewardDefinitions.CycleLength
	-- If streak is exactly at a multiple of 7, all 7 are claimed in this cycle
	if currentStreak > 0 and cyclePosition == 0 then
		cyclePosition = DailyRewardDefinitions.CycleLength
	end

	for day = 1, DailyRewardDefinitions.CycleLength do
		local reward = DailyRewardDefinitions.GetRewardForStreak(day)
		local cell = createDayCell(day, reward, cyclePosition, canClaim)
		cell.Parent = calendarFrame
	end
end

local function renderMilestones(longestStreak: number, claimedMilestones: { [string]: any }?)
	if not milestoneFrame then
		return
	end

	-- Clear existing milestone rows (keep UIListLayout and UIPadding)
	for _, child in ipairs(milestoneFrame:GetChildren()) do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end

	local milestones = DailyRewardDefinitions.Milestones
	for index, milestone in ipairs(milestones) do
		local row = createMilestoneRow(milestone, index, longestStreak, claimedMilestones)
		row.Parent = milestoneFrame
	end
end

local function updateClaimButton(canClaim: boolean, secondsUntilClaim: number)
	if not claimButton or not countdownLabel then
		return
	end

	if canClaim then
		claimButton.BackgroundColor3 = Color3.fromRGB(52, 124, 203)
		claimButton.Text = "Claim Reward"
		claimButton.TextColor3 = Color3.fromRGB(255, 255, 255)
		claimButton.Active = true
		claimButton.AutoButtonColor = true
		countdownLabel.Text = "Your daily reward is ready!"
		countdownLabel.TextColor3 = Color3.fromRGB(120, 200, 140)
	else
		claimButton.BackgroundColor3 = Color3.fromRGB(55, 62, 78)
		claimButton.Text = "On Cooldown"
		claimButton.TextColor3 = Color3.fromRGB(160, 170, 185)
		claimButton.Active = false
		claimButton.AutoButtonColor = false
		countdownLabel.Text = "Next reward in: " .. formatTime(secondsUntilClaim)
		countdownLabel.TextColor3 = Color3.fromRGB(160, 174, 195)
	end
end

local function renderStatus(status: { [string]: any })
	if not streakLabel or not statsLabel then
		return
	end

	cachedStatus = status

	local currentStreak = math.max(0, math.floor(tonumber(status.CurrentStreak) or 0))
	local longestStreak = math.max(0, math.floor(tonumber(status.LongestStreak) or 0))
	local totalClaimed = math.max(0, math.floor(tonumber(status.TotalClaimed) or 0))
	local totalCash = math.max(0, math.floor(tonumber(status.TotalCashEarned) or 0))
	local canClaim = status.CanClaim == true
	local secondsUntilClaim = math.max(0, tonumber(status.SecondsUntilClaim) or 0)

	streakLabel.Text = string.format("Streak: %d (Best: %d)", currentStreak, longestStreak)
	statsLabel.Text = string.format("Claimed %d times | $%d earned", totalClaimed, totalCash)

	renderCalendar(currentStreak, canClaim)
	renderMilestones(longestStreak, status.MilestonesClaimed)
	updateClaimButton(canClaim, secondsUntilClaim)

	-- Start countdown loop if on cooldown
	if not canClaim and secondsUntilClaim > 0 then
		DailyRewardUI._StartCountdown(secondsUntilClaim)
	end
end

-- Countdown timer loop
function DailyRewardUI._StartCountdown(seconds: number)
	if countdownActive then
		return
	end
	countdownActive = true

	task.spawn(function()
		local remaining = seconds
		while remaining > 0 and countdownActive do
			task.wait(1)
			remaining -= 1
			if countdownLabel then
				if remaining > 0 then
					countdownLabel.Text = "Next reward in: " .. formatTime(remaining)
				else
					countdownLabel.Text = "Your daily reward is ready!"
					countdownLabel.TextColor3 = Color3.fromRGB(120, 200, 140)
				end
			end
		end
		countdownActive = false

		-- Auto-refresh when countdown completes
		if remaining <= 0 then
			DailyRewardUI.RefreshStatus()
		end
	end)
end

function DailyRewardUI.RefreshStatus()
	countdownActive = false
	task.spawn(function()
		local ok, payload = pcall(function()
			return DailyRewardPackets.GetDailyRewardStatus:Fire()
		end)
		if ok and typeof(payload) == "table" then
			renderStatus(payload)
		end
	end)
end

function DailyRewardUI.ClaimReward()
	if not claimButton then
		return
	end

	-- Prevent double-clicks
	claimButton.Active = false
	claimButton.Text = "Claiming..."

	task.spawn(function()
		local ok, result = pcall(function()
			return DailyRewardPackets.ClaimDailyReward:Fire()
		end)

		if ok and typeof(result) == "table" then
			local streak = math.max(1, math.floor(tonumber(result.Streak) or 1))
			local cashEarned = math.floor(tonumber(result.CashEarned) or 0)
			local xpEarned = math.floor(tonumber(result.ExperienceEarned) or 0)
			local dayLabel = tostring(result.DayLabel or "")
			local milestoneLabel = result.MilestoneUnlocked

			-- Show claim notification
			local notifText = string.format("Day %d: +$%d, +%d XP", streak, cashEarned, xpEarned)
			if typeof(milestoneLabel) == "string" and milestoneLabel ~= "" then
				notifText = notifText .. string.format("\nMilestone: %s!", milestoneLabel)
			end

			Notification.Show({
				Title = dayLabel ~= "" and dayLabel or string.format("Day %d Reward!", streak),
				Text = notifText,
				Duration = 4,
				BackgroundColor = Color3.fromRGB(52, 130, 90),
			})

			-- Refresh UI to reflect new state
			DailyRewardUI.RefreshStatus()
		else
			Notification.Show({
				Title = "Claim Failed",
				Text = "Could not claim your daily reward. Try again later.",
				Duration = 3,
				BackgroundColor = Color3.fromRGB(132, 64, 64),
			})
			-- Re-enable button on failure
			if claimButton then
				claimButton.Active = true
				claimButton.Text = "Claim Reward"
			end
		end
	end)
end

function DailyRewardUI.SetVisible(visible: boolean)
	ensureGui()
	open = visible
	if gui then
		gui.Enabled = visible
	end
	if visible then
		DailyRewardUI.RefreshStatus()
	else
		countdownActive = false
	end
end

function DailyRewardUI.Toggle()
	DailyRewardUI.SetVisible(not open)
end

function DailyRewardUI.Init()
	if initialized then
		return
	end
	initialized = true

	ensureGui()

	-- Listen for server-pushed status updates
	DailyRewardPackets.DailyRewardUpdated.OnClientEvent:Connect(function(payload)
		if typeof(payload) == "table" then
			renderStatus(payload)
		end
	end)

	-- Auto-prompt on join if reward is available
	task.spawn(function()
		local ok, payload = pcall(function()
			return DailyRewardPackets.GetDailyRewardStatus:Fire()
		end)
		if ok and typeof(payload) == "table" then
			renderStatus(payload)
			if payload.CanClaim == true then
				-- Auto-open the UI when a reward is available
				task.delay(1.5, function()
					if not open then
						DailyRewardUI.SetVisible(true)
					end
				end)
			end
		end
	end)
end

return DailyRewardUI
