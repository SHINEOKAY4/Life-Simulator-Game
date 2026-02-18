--!strict

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
local seasonProgressLabel: TextLabel? = nil
local challengeList: ScrollingFrame? = nil
local buffsList: ScrollingFrame? = nil

local initialized = false

local seasonColors: { [string]: Color3 } = {
	Spring = Color3.fromRGB(76, 161, 93),
	Summer = Color3.fromRGB(224, 153, 59),
	Autumn = Color3.fromRGB(181, 96, 54),
	Winter = Color3.fromRGB(76, 132, 191),
}

local function clearRows(container: ScrollingFrame)
	for _, child in ipairs(container:GetChildren()) do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
end

local function createChallengeRow(challenge: { [string]: any }, index: number): Frame
	local row = Instance.new("Frame")
	row.Name = "Challenge_" .. tostring(challenge.Id or index)
	row.LayoutOrder = index
	row.Size = UDim2.new(1, -4, 0, 68)
	row.BackgroundColor3 = if challenge.Completed then Color3.fromRGB(56, 102, 76) else Color3.fromRGB(30, 36, 48)
	row.BorderSizePixel = 0

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = row

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Position = UDim2.fromOffset(10, 6)
	title.Size = UDim2.new(1, -20, 0, 18)
	title.Font = Enum.Font.GothamSemibold
	title.TextSize = 13
	title.TextColor3 = Color3.fromRGB(235, 243, 255)
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Text = tostring(challenge.Name or "Challenge")
	title.Parent = row

	local progressValue = tonumber(challenge.CurrentValue) or 0
	local targetValue = math.max(1, tonumber(challenge.TargetValue) or 1)
	local ratio = math.clamp(progressValue / targetValue, 0, 1)

	local progressTrack = Instance.new("Frame")
	progressTrack.BackgroundColor3 = Color3.fromRGB(14, 17, 25)
	progressTrack.BorderSizePixel = 0
	progressTrack.Position = UDim2.fromOffset(10, 30)
	progressTrack.Size = UDim2.new(1, -20, 0, 12)
	progressTrack.Parent = row
	local trackCorner = Instance.new("UICorner")
	trackCorner.CornerRadius = UDim.new(0, 6)
	trackCorner.Parent = progressTrack

	local progressFill = Instance.new("Frame")
	progressFill.BackgroundColor3 = if challenge.Completed then Color3.fromRGB(122, 220, 142) else Color3.fromRGB(104, 166, 255)
	progressFill.BorderSizePixel = 0
	progressFill.Size = UDim2.new(ratio, 0, 1, 0)
	progressFill.Parent = progressTrack
	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0, 6)
	fillCorner.Parent = progressFill

	local progressLabel = Instance.new("TextLabel")
	progressLabel.BackgroundTransparency = 1
	progressLabel.Position = UDim2.fromOffset(10, 45)
	progressLabel.Size = UDim2.new(1, -20, 0, 16)
	progressLabel.Font = Enum.Font.Gotham
	progressLabel.TextSize = 12
	progressLabel.TextColor3 = Color3.fromRGB(178, 194, 220)
	progressLabel.TextXAlignment = Enum.TextXAlignment.Left
	progressLabel.Text = string.format("%d / %d", math.floor(progressValue + 0.5), targetValue)
	progressLabel.Parent = row

	return row
end

local function createBuffRow(buff: { [string]: any }, index: number): Frame
	local row = Instance.new("Frame")
	row.Name = "Buff_" .. tostring(index)
	row.LayoutOrder = index
	row.Size = UDim2.new(1, -4, 0, 34)
	row.BackgroundColor3 = Color3.fromRGB(25, 45, 63)
	row.BorderSizePixel = 0

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = row

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
	if not seasonTitleLabel or not seasonDescriptionLabel or not seasonProgressLabel or not challengeList or not buffsList then
		return
	end

	local seasonName = tostring(status.SeasonName or status.CurrentSeason or "Season")
	local seasonId = tostring(status.CurrentSeason or "Spring")
	seasonTitleLabel.Text = seasonName
	seasonDescriptionLabel.Text = tostring(status.SeasonDescription or "")
	local claimedMilestones = math.max(0, math.floor(tonumber(status.ClaimedMilestonesCount) or 0))
	local totalMilestones = #SeasonalEventDefinitions.Milestones
	seasonProgressLabel.Text = string.format(
		"Seasons Completed: %d | Challenges Completed: %d | Milestones Claimed: %d / %d",
		math.max(0, math.floor(tonumber(status.SeasonsCompleted) or 0)),
		math.max(0, math.floor(tonumber(status.TotalChallengesCompleted) or 0)),
		claimedMilestones,
		totalMilestones
	)
	applySeasonColor(seasonId)

	clearRows(challengeList)
	local challenges = status.Challenges
	if typeof(challenges) == "table" and #challenges > 0 then
		for index, challenge in ipairs(challenges) do
			local row = createChallengeRow(challenge, index)
			row.Parent = challengeList
		end
	end

	clearRows(buffsList)
	local buffs = status.Buffs
	if typeof(buffs) == "table" and #buffs > 0 then
		for index, buff in ipairs(buffs) do
			local row = createBuffRow(buff, index)
			row.Parent = buffsList
		end
	end
end

local function refreshStatus()
	task.spawn(function()
		local ok, payload = pcall(function()
			return SeasonalEventPackets.GetSeasonStatus:Fire()
		end)
		if ok and typeof(payload) == "table" then
			renderStatus(payload)
		end
	end)
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
	gui.Parent = PlayerGui

	local banner = Instance.new("Frame")
	banner.Name = "SeasonBanner"
	banner.AnchorPoint = Vector2.new(0.5, 0)
	banner.Position = UDim2.fromScale(0.5, 0.02)
	banner.Size = UDim2.new(0, 460, 0, 74)
	banner.BackgroundColor3 = Color3.fromRGB(76, 132, 191)
	banner.BorderSizePixel = 0
	banner.Parent = gui
	bannerFrame = banner

	local bannerCorner = Instance.new("UICorner")
	bannerCorner.CornerRadius = UDim.new(0, 10)
	bannerCorner.Parent = banner

	local seasonTitle = Instance.new("TextLabel")
	seasonTitle.BackgroundTransparency = 1
	seasonTitle.Position = UDim2.fromOffset(14, 7)
	seasonTitle.Size = UDim2.new(1, -28, 0, 26)
	seasonTitle.Font = Enum.Font.GothamBold
	seasonTitle.TextSize = 22
	seasonTitle.TextColor3 = Color3.fromRGB(243, 248, 255)
	seasonTitle.TextXAlignment = Enum.TextXAlignment.Left
	seasonTitle.Text = "Season"
	seasonTitle.Parent = banner
	seasonTitleLabel = seasonTitle

	local seasonDescription = Instance.new("TextLabel")
	seasonDescription.BackgroundTransparency = 1
	seasonDescription.Position = UDim2.fromOffset(14, 33)
	seasonDescription.Size = UDim2.new(1, -28, 0, 16)
	seasonDescription.Font = Enum.Font.Gotham
	seasonDescription.TextSize = 12
	seasonDescription.TextColor3 = Color3.fromRGB(224, 236, 252)
	seasonDescription.TextXAlignment = Enum.TextXAlignment.Left
	seasonDescription.Text = ""
	seasonDescription.Parent = banner
	seasonDescriptionLabel = seasonDescription

	local progress = Instance.new("TextLabel")
	progress.BackgroundTransparency = 1
	progress.Position = UDim2.fromOffset(14, 51)
	progress.Size = UDim2.new(1, -28, 0, 16)
	progress.Font = Enum.Font.GothamMedium
	progress.TextSize = 11
	progress.TextColor3 = Color3.fromRGB(212, 228, 250)
	progress.TextXAlignment = Enum.TextXAlignment.Left
	progress.Text = ""
	progress.Parent = banner
	seasonProgressLabel = progress

	local challengesPanel = Instance.new("Frame")
	challengesPanel.Name = "ChallengesPanel"
	challengesPanel.AnchorPoint = Vector2.new(1, 0)
	challengesPanel.Position = UDim2.new(1, -16, 0, 102)
	challengesPanel.Size = UDim2.new(0, 340, 0, 260)
	challengesPanel.BackgroundColor3 = Color3.fromRGB(18, 22, 30)
	challengesPanel.BackgroundTransparency = 0.08
	challengesPanel.BorderSizePixel = 0
	challengesPanel.Parent = gui
	local challengesCorner = Instance.new("UICorner")
	challengesCorner.CornerRadius = UDim.new(0, 10)
	challengesCorner.Parent = challengesPanel

	local challengesTitle = Instance.new("TextLabel")
	challengesTitle.BackgroundTransparency = 1
	challengesTitle.Position = UDim2.fromOffset(12, 8)
	challengesTitle.Size = UDim2.new(1, -24, 0, 20)
	challengesTitle.Font = Enum.Font.GothamBold
	challengesTitle.TextSize = 16
	challengesTitle.TextColor3 = Color3.fromRGB(233, 240, 255)
	challengesTitle.TextXAlignment = Enum.TextXAlignment.Left
	challengesTitle.Text = "Season Challenges"
	challengesTitle.Parent = challengesPanel

	local challengeScroll = Instance.new("ScrollingFrame")
	challengeScroll.Name = "ChallengeList"
	challengeScroll.Position = UDim2.fromOffset(8, 34)
	challengeScroll.Size = UDim2.new(1, -16, 1, -42)
	challengeScroll.BackgroundTransparency = 1
	challengeScroll.BorderSizePixel = 0
	challengeScroll.ScrollBarThickness = 5
	challengeScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	challengeScroll.CanvasSize = UDim2.fromOffset(0, 0)
	challengeScroll.Parent = challengesPanel
	challengeList = challengeScroll

	local challengeLayout = Instance.new("UIListLayout")
	challengeLayout.Padding = UDim.new(0, 6)
	challengeLayout.Parent = challengeScroll

	local buffsPanel = Instance.new("Frame")
	buffsPanel.Name = "BuffsPanel"
	buffsPanel.AnchorPoint = Vector2.new(1, 0)
	buffsPanel.Position = UDim2.new(1, -16, 0, 370)
	buffsPanel.Size = UDim2.new(0, 340, 0, 140)
	buffsPanel.BackgroundColor3 = Color3.fromRGB(18, 22, 30)
	buffsPanel.BackgroundTransparency = 0.08
	buffsPanel.BorderSizePixel = 0
	buffsPanel.Parent = gui
	local buffsCorner = Instance.new("UICorner")
	buffsCorner.CornerRadius = UDim.new(0, 10)
	buffsCorner.Parent = buffsPanel

	local buffsTitle = Instance.new("TextLabel")
	buffsTitle.BackgroundTransparency = 1
	buffsTitle.Position = UDim2.fromOffset(12, 8)
	buffsTitle.Size = UDim2.new(1, -24, 0, 20)
	buffsTitle.Font = Enum.Font.GothamBold
	buffsTitle.TextSize = 16
	buffsTitle.TextColor3 = Color3.fromRGB(233, 240, 255)
	buffsTitle.TextXAlignment = Enum.TextXAlignment.Left
	buffsTitle.Text = "Active Buffs"
	buffsTitle.Parent = buffsPanel

	local buffScroll = Instance.new("ScrollingFrame")
	buffScroll.Name = "BuffsList"
	buffScroll.Position = UDim2.fromOffset(8, 34)
	buffScroll.Size = UDim2.new(1, -16, 1, -42)
	buffScroll.BackgroundTransparency = 1
	buffScroll.BorderSizePixel = 0
	buffScroll.ScrollBarThickness = 4
	buffScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	buffScroll.CanvasSize = UDim2.fromOffset(0, 0)
	buffScroll.Parent = buffsPanel
	buffsList = buffScroll

	local buffLayout = Instance.new("UIListLayout")
	buffLayout.Padding = UDim.new(0, 6)
	buffLayout.Parent = buffScroll

	local mobileConstraint = Instance.new("UISizeConstraint")
	mobileConstraint.MinSize = Vector2.new(300, 70)
	mobileConstraint.MaxSize = Vector2.new(520, 90)
	mobileConstraint.Parent = banner
end

function SeasonalEventUI.Init()
	if initialized then
		return
	end
	initialized = true

	ensureGui()
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
		refreshStatus()
	end)

	SeasonalEventPackets.ChallengeCompleted.OnClientEvent:Connect(function(payload)
		if typeof(payload) == "table" then
			Notification.Show({
				Title = "Seasonal Challenge Complete",
				Text = tostring(payload.Name or "Challenge complete"),
				Duration = 3,
				BackgroundColor = Color3.fromRGB(64, 134, 92),
			})
		end
		refreshStatus()
	end)

	refreshStatus()
end

return SeasonalEventUI
