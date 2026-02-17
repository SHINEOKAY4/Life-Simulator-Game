--!strict
-- Client/UserInterface/ReputationUI.luau
-- Displays player trust level, reputation score, and social rankings.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local ReputationPackets = require(ReplicatedStorage.Network.ReputationPackets)
local SoundtrackManager = require(script.Parent.Parent.Modules.SoundtrackManager)

local ReputationUI = {}

local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")

local ScreenGui: ScreenGui?
local MainFrame: Frame?
local RankingsContainer: ScrollingFrame?
local EmptyLabel: TextLabel?
local ScoreLabel: TextLabel?
local TrustLabel: TextLabel?
local RankLabel: TextLabel?
local RewardLabel: TextLabel?

local isVisible = false
local isFetching = false
local cachedData: { [string]: any }? = nil

local function clearRankings()
	if not RankingsContainer then
		return
	end
	for _, child in ipairs(RankingsContainer:GetChildren()) do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
end

local function createRankingRow(entry: { [string]: any }): Frame
	local row = Instance.new("Frame")
	row.Name = "RankingRow"
	row.Size = UDim2.new(1, 0, 0, 34)
	row.BackgroundColor3 = if entry.IsLocalPlayer then Color3.fromRGB(235, 245, 255) else Color3.fromRGB(248, 250, 252)
	row.BorderSizePixel = 0

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = row

	local rank = Instance.new("TextLabel")
	rank.BackgroundTransparency = 1
	rank.Size = UDim2.new(0, 44, 1, 0)
	rank.Position = UDim2.fromOffset(10, 0)
	rank.Font = Enum.Font.GothamBold
	rank.Text = "#" .. tostring(entry.Rank or 0)
	rank.TextColor3 = Color3.fromRGB(50, 60, 80)
	rank.TextSize = 14
	rank.TextXAlignment = Enum.TextXAlignment.Left
	rank.Parent = row

	local name = Instance.new("TextLabel")
	name.BackgroundTransparency = 1
	name.Size = UDim2.new(1, -200, 1, 0)
	name.Position = UDim2.fromOffset(54, 0)
	name.Font = Enum.Font.GothamSemibold
	name.Text = tostring(entry.PlayerName or "Unknown")
	name.TextColor3 = Color3.fromRGB(50, 60, 80)
	name.TextSize = 14
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.TextTruncate = Enum.TextTruncate.AtEnd
	name.Parent = row

	local score = Instance.new("TextLabel")
	score.BackgroundTransparency = 1
	score.Size = UDim2.new(0, 66, 1, 0)
	score.AnchorPoint = Vector2.new(1, 0)
	score.Position = UDim2.new(1, -70, 0, 0)
	score.Font = Enum.Font.GothamBold
	score.Text = tostring(entry.ReputationScore or 0)
	score.TextColor3 = Color3.fromRGB(30, 130, 95)
	score.TextSize = 14
	score.TextXAlignment = Enum.TextXAlignment.Right
	score.Parent = row

	local trust = Instance.new("TextLabel")
	trust.BackgroundTransparency = 1
	trust.Size = UDim2.new(0, 88, 1, 0)
	trust.AnchorPoint = Vector2.new(1, 0)
	trust.Position = UDim2.new(1, -140, 0, 0)
	trust.Font = Enum.Font.Gotham
	trust.Text = tostring(entry.TrustLevel or "Unknown")
	trust.TextColor3 = Color3.fromRGB(95, 105, 130)
	trust.TextSize = 13
	trust.TextXAlignment = Enum.TextXAlignment.Right
	trust.Parent = row

	return row
end

local function populateRankings(rankings: { [any]: any })
	if not RankingsContainer or not EmptyLabel then
		return
	end

	clearRankings()

	if #rankings == 0 then
		EmptyLabel.Visible = true
		return
	end
	EmptyLabel.Visible = false

	for _, entry in ipairs(rankings) do
		local row = createRankingRow(entry)
		row.Parent = RankingsContainer
	end
end

local function applySnapshot(data: { [string]: any })
	if not ScoreLabel or not TrustLabel or not RankLabel or not RewardLabel then
		return
	end

	local snapshot = data.Snapshot or {}
	local score = snapshot.ReputationScore or 0
	local trust = snapshot.TrustLevel or "Unknown"
	local multiplier = snapshot.RewardMultiplier or 1
	local nextLevel = snapshot.NextTrustLevel or "MAX"
	local pointsToNext = snapshot.PointsToNextLevel or 0

	ScoreLabel.Text = string.format("Reputation: %d", score)
	TrustLabel.Text = string.format("Trust: %s", trust)
	RankLabel.Text = string.format("Your Rank: #%d", data.PlayerRank or 0)
	RewardLabel.Text = string.format("Reward Bonus: x%.2f (%d to %s)", multiplier, pointsToNext, nextLevel)
end

local function applyData(data: { [string]: any })
	cachedData = data
	applySnapshot(data)
	populateRankings(data.Rankings or {})
end

local function fetchData()
	if isFetching then
		return
	end
	isFetching = true

	task.spawn(function()
		local success, result = pcall(function()
			return ReputationPackets.GetReputationRequest:Fire()
		end)
		isFetching = false

		if success and typeof(result) == "table" then
			applyData(result)
		else
			warn("Failed to fetch reputation data:", result)
		end
	end)
end

function ReputationUI.Init()
	if ScreenGui then
		return
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = "ReputationUI"
	gui.ResetOnSpawn = false
	gui.Enabled = false
	gui.DisplayOrder = 11
	gui.Parent = PlayerGui
	ScreenGui = gui

	local main = Instance.new("Frame")
	main.Name = "MainFrame"
	main.AnchorPoint = Vector2.new(0.5, 0.5)
	main.Position = UDim2.fromScale(0.5, 0.5)
	main.Size = UDim2.new(0, 460, 0.62, 0)
	main.BackgroundColor3 = Color3.fromRGB(246, 248, 252)
	main.BorderSizePixel = 0
	main.ClipsDescendants = true
	main.Parent = gui
	MainFrame = main

	local sizeConstraint = Instance.new("UISizeConstraint")
	sizeConstraint.MinSize = Vector2.new(320, 320)
	sizeConstraint.MaxSize = Vector2.new(460, 620)
	sizeConstraint.Parent = main

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = main

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(218, 223, 234)
	stroke.Thickness = 1
	stroke.Parent = main

	local titleBar = Instance.new("Frame")
	titleBar.Name = "TitleBar"
	titleBar.BackgroundTransparency = 1
	titleBar.Size = UDim2.new(1, 0, 0, 56)
	titleBar.Parent = main

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Position = UDim2.fromOffset(18, 8)
	title.Size = UDim2.new(1, -66, 0, 24)
	title.Font = Enum.Font.GothamBold
	title.Text = "Social Reputation"
	title.TextSize = 20
	title.TextColor3 = Color3.fromRGB(42, 52, 76)
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Parent = titleBar

	local subtitle = Instance.new("TextLabel")
	subtitle.BackgroundTransparency = 1
	subtitle.Position = UDim2.fromOffset(18, 30)
	subtitle.Size = UDim2.new(1, -66, 0, 18)
	subtitle.Font = Enum.Font.Gotham
	subtitle.Text = "Trust levels, rankings, and reward bonus"
	subtitle.TextSize = 13
	subtitle.TextColor3 = Color3.fromRGB(96, 105, 125)
	subtitle.TextXAlignment = Enum.TextXAlignment.Left
	subtitle.Parent = titleBar

	local closeButton = Instance.new("ImageButton")
	closeButton.Name = "CloseButton"
	closeButton.AnchorPoint = Vector2.new(1, 0.5)
	closeButton.Position = UDim2.new(1, -15, 0.5, 0)
	closeButton.Size = UDim2.fromOffset(24, 24)
	closeButton.BackgroundTransparency = 1
	closeButton.Image = "rbxassetid://3926305904"
	closeButton.ImageRectOffset = Vector2.new(284, 4)
	closeButton.ImageRectSize = Vector2.new(24, 24)
	closeButton.ImageColor3 = Color3.fromRGB(96, 96, 108)
	closeButton.Parent = titleBar
	closeButton.MouseButton1Click:Connect(function()
		SoundtrackManager.PlayButtonClick()
		ReputationUI.SetVisible(false)
	end)

	local separator = Instance.new("Frame")
	separator.BackgroundColor3 = Color3.fromRGB(228, 232, 240)
	separator.BorderSizePixel = 0
	separator.Position = UDim2.new(0, 0, 1, -1)
	separator.Size = UDim2.new(1, 0, 0, 1)
	separator.Parent = titleBar

	local scoreLabel = Instance.new("TextLabel")
	scoreLabel.BackgroundTransparency = 1
	scoreLabel.Position = UDim2.fromOffset(18, 64)
	scoreLabel.Size = UDim2.new(0.5, -24, 0, 20)
	scoreLabel.Font = Enum.Font.GothamBold
	scoreLabel.Text = "Reputation: 0"
	scoreLabel.TextColor3 = Color3.fromRGB(40, 128, 92)
	scoreLabel.TextSize = 16
	scoreLabel.TextXAlignment = Enum.TextXAlignment.Left
	scoreLabel.Parent = main
	ScoreLabel = scoreLabel

	local trustLabel = Instance.new("TextLabel")
	trustLabel.BackgroundTransparency = 1
	trustLabel.Position = UDim2.new(0.5, 4, 0, 64)
	trustLabel.Size = UDim2.new(0.5, -22, 0, 20)
	trustLabel.Font = Enum.Font.GothamBold
	trustLabel.Text = "Trust: Unknown"
	trustLabel.TextColor3 = Color3.fromRGB(54, 63, 84)
	trustLabel.TextSize = 16
	trustLabel.TextXAlignment = Enum.TextXAlignment.Right
	trustLabel.Parent = main
	TrustLabel = trustLabel

	local rankLabel = Instance.new("TextLabel")
	rankLabel.BackgroundTransparency = 1
	rankLabel.Position = UDim2.fromOffset(18, 86)
	rankLabel.Size = UDim2.new(1, -36, 0, 18)
	rankLabel.Font = Enum.Font.Gotham
	rankLabel.Text = "Your Rank: #0"
	rankLabel.TextColor3 = Color3.fromRGB(90, 100, 125)
	rankLabel.TextSize = 14
	rankLabel.TextXAlignment = Enum.TextXAlignment.Left
	rankLabel.Parent = main
	RankLabel = rankLabel

	local rewardLabel = Instance.new("TextLabel")
	rewardLabel.BackgroundTransparency = 1
	rewardLabel.Position = UDim2.fromOffset(18, 104)
	rewardLabel.Size = UDim2.new(1, -36, 0, 18)
	rewardLabel.Font = Enum.Font.Gotham
	rewardLabel.Text = "Reward Bonus: x1.00"
	rewardLabel.TextColor3 = Color3.fromRGB(90, 100, 125)
	rewardLabel.TextSize = 14
	rewardLabel.TextXAlignment = Enum.TextXAlignment.Left
	rewardLabel.Parent = main
	RewardLabel = rewardLabel

	local rankingsTitle = Instance.new("TextLabel")
	rankingsTitle.BackgroundTransparency = 1
	rankingsTitle.Position = UDim2.fromOffset(18, 136)
	rankingsTitle.Size = UDim2.new(1, -36, 0, 20)
	rankingsTitle.Font = Enum.Font.GothamBold
	rankingsTitle.Text = "Player Rankings"
	rankingsTitle.TextColor3 = Color3.fromRGB(52, 63, 86)
	rankingsTitle.TextSize = 15
	rankingsTitle.TextXAlignment = Enum.TextXAlignment.Left
	rankingsTitle.Parent = main

	local rankings = Instance.new("ScrollingFrame")
	rankings.Name = "RankingsContainer"
	rankings.BackgroundTransparency = 1
	rankings.Position = UDim2.fromOffset(0, 160)
	rankings.Size = UDim2.new(1, 0, 1, -160)
	rankings.CanvasSize = UDim2.new(0, 0, 0, 0)
	rankings.AutomaticCanvasSize = Enum.AutomaticSize.Y
	rankings.ScrollBarThickness = 5
	rankings.ScrollBarImageColor3 = Color3.fromRGB(190, 200, 220)
	rankings.Parent = main
	RankingsContainer = rankings

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 8)
	padding.PaddingBottom = UDim.new(0, 12)
	padding.PaddingLeft = UDim.new(0, 18)
	padding.PaddingRight = UDim.new(0, 18)
	padding.Parent = rankings

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 8)
	layout.Parent = rankings

	local emptyLabel = Instance.new("TextLabel")
	emptyLabel.BackgroundTransparency = 1
	emptyLabel.Size = UDim2.new(1, 0, 0, 20)
	emptyLabel.Font = Enum.Font.Gotham
	emptyLabel.Text = "No rankings available yet."
	emptyLabel.TextColor3 = Color3.fromRGB(140, 145, 155)
	emptyLabel.TextSize = 14
	emptyLabel.Visible = false
	emptyLabel.Parent = rankings
	EmptyLabel = emptyLabel
end

function ReputationUI.SetData(data: { [string]: any })
	if not ScreenGui then
		ReputationUI.Init()
	end
	applyData(data)
end

function ReputationUI.SetVisible(visible: boolean)
	if not ScreenGui then
		ReputationUI.Init()
	end
	if not ScreenGui or not MainFrame then
		return
	end

	isVisible = visible
	ScreenGui.Enabled = visible

	if visible then
		MainFrame.Position = UDim2.fromScale(0.5, 0.56)
		TweenService:Create(MainFrame, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Position = UDim2.fromScale(0.5, 0.5),
		}):Play()

		if cachedData then
			applyData(cachedData)
		end
		fetchData()
	end
end

function ReputationUI.Toggle()
	ReputationUI.SetVisible(not isVisible)
end

return ReputationUI
