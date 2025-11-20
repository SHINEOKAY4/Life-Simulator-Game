--!strict
-- Client/UserInterface/ReviewsUI.luau
-- Displays a scrollable list of all tenant reviews.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local ReviewPackets = require(ReplicatedStorage.Network.ReviewPackets)
local SoundtrackManager = require(script.Parent.Parent.Modules.SoundtrackManager)

local ReviewsUI = {}

local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")

local ScreenGui: ScreenGui?
local MainFrame: Frame?
local Container: ScrollingFrame?
local EmptyLabel: TextLabel?
local OverallRatingLabel: TextLabel?

local isVisible = false
local isFetching = false
local cachedReviews = {}

local function createStarRating(rating: number): Frame
	local frame = Instance.new("Frame")
	frame.BackgroundTransparency = 1
	frame.Size = UDim2.fromOffset(80, 16)

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 2)
	layout.Parent = frame

	for i = 1, 5 do
		local star = Instance.new("TextLabel")
		star.BackgroundTransparency = 1
		star.Size = UDim2.fromOffset(14, 14)
		star.Text = "★"
		star.Font = Enum.Font.GothamBold
		star.TextSize = 14
		star.TextColor3 = if i <= rating then Color3.fromRGB(255, 180, 0) else Color3.fromRGB(200, 200, 200)
		star.Parent = frame
	end

	return frame
end

local function getAvatarColor(name: string): Color3
	local sum = 0
	for i = 1, #name do
		sum += string.byte(name, i)
	end
	local colors = {
		Color3.fromRGB(255, 179, 186), -- Pastel Red
		Color3.fromRGB(255, 223, 186), -- Pastel Orange
		Color3.fromRGB(186, 255, 201), -- Pastel Green
		Color3.fromRGB(186, 225, 255), -- Pastel Blue
		Color3.fromRGB(227, 186, 255), -- Pastel Purple
		Color3.fromRGB(255, 200, 160), -- Peach
	}
	return colors[(sum % #colors) + 1]
end

local function createReviewCard(review: { [string]: any }): Frame
	local card = Instance.new("Frame")
	card.Name = "ReviewCard"
	card.Size = UDim2.fromScale(1, 0)
	card.AutomaticSize = Enum.AutomaticSize.Y
	card.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	card.BorderSizePixel = 0
	card.LayoutOrder = -(review.Timestamp or 0) -- Newest first

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = card

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(235, 238, 242)
	stroke.Thickness = 1.5
	stroke.Parent = card

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 16)
	padding.PaddingBottom = UDim.new(0, 16)
	padding.PaddingLeft = UDim.new(0, 16)
	padding.PaddingRight = UDim.new(0, 16)
	padding.Parent = card

	-- Avatar
	local tenantName = review.TenantName or "Unknown"
	local avatar = Instance.new("Frame")
	avatar.Name = "Avatar"
	avatar.Size = UDim2.fromOffset(40, 40)
	avatar.BackgroundColor3 = getAvatarColor(tenantName)
	avatar.Parent = card

	local avatarCorner = Instance.new("UICorner")
	avatarCorner.CornerRadius = UDim.new(1, 0)
	avatarCorner.Parent = avatar

	local initial = Instance.new("TextLabel")
	initial.BackgroundTransparency = 1
	initial.Size = UDim2.fromScale(1, 1)
	initial.Font = Enum.Font.GothamBold
	initial.Text = string.sub(tenantName, 1, 1)
	initial.TextColor3 = Color3.fromRGB(255, 255, 255)
	initial.TextSize = 20
	initial.Parent = avatar

	-- Content Container
	local content = Instance.new("Frame")
	content.Name = "Content"
	content.BackgroundTransparency = 1
	content.Position = UDim2.fromOffset(52, 0)
	content.Size = UDim2.new(1, -52, 0, 0)
	content.AutomaticSize = Enum.AutomaticSize.Y
	content.Parent = card

	-- Name
	local nameLabel = Instance.new("TextLabel")
	nameLabel.BackgroundTransparency = 1
	nameLabel.Size = UDim2.new(1, -90, 0, 20)
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.Text = tenantName
	nameLabel.TextColor3 = Color3.fromRGB(45, 55, 75) -- Dark Slate
	nameLabel.TextSize = 16
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
	nameLabel.Parent = content

	-- Stars
	local stars = createStarRating(review.Rating or 0)
	stars.AnchorPoint = Vector2.new(1, 0)
	stars.Position = UDim2.new(1, 0, 0, 2)
	stars.Parent = content

	-- Comment
	local commentLabel = Instance.new("TextLabel")
	commentLabel.BackgroundTransparency = 1
	commentLabel.Position = UDim2.fromOffset(0, 24)
	commentLabel.Size = UDim2.fromScale(1, 0)
	commentLabel.AutomaticSize = Enum.AutomaticSize.Y
	commentLabel.Font = Enum.Font.GothamMedium
	commentLabel.Text = review.Comment or ""
	commentLabel.TextColor3 = Color3.fromRGB(100, 110, 125) -- Slate Grey
	commentLabel.TextSize = 14
	commentLabel.TextWrapped = true
	commentLabel.TextXAlignment = Enum.TextXAlignment.Left
	commentLabel.LineHeight = 1.2
	commentLabel.Parent = content

	return card
end

local function updateOverallRating(reviews: { [any]: any })
	if not OverallRatingLabel then
		return
	end

	if #reviews == 0 then
		OverallRatingLabel.Text = ""
		return
	end

	local total = 0
	for _, review in ipairs(reviews) do
		total += (review.Rating or 0)
	end
	local average = total / #reviews
	OverallRatingLabel.Text = string.format("%.1f ★", average)
end

local function populateList(reviews: { [any]: any })
	if not Container or not EmptyLabel then
		return
	end

	-- Clear existing
	for _, child in ipairs(Container:GetChildren()) do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end

	updateOverallRating(reviews)

	if #reviews == 0 then
		EmptyLabel.Visible = true
		return
	end
	EmptyLabel.Visible = false

	-- Sort by timestamp descending
	table.sort(reviews, function(a, b)
		return (a.Timestamp or 0) > (b.Timestamp or 0)
	end)

	for _, review in ipairs(reviews) do
		local card = createReviewCard(review)
		card.Parent = Container
	end
end

local function fetchReviews()
	if isFetching then
		return
	end
	isFetching = true

	-- Show loading state if needed?

	task.spawn(function()
		local success, result = pcall(function()
			return ReviewPackets.GetReviewsRequest:Fire()
		end)
		isFetching = false

		if success and result then
			cachedReviews = result
			if isVisible then
				populateList(cachedReviews)
			end
		else
			warn("Failed to fetch reviews:", result)
		end
	end)
end

function ReviewsUI.Init()
	if ScreenGui then
		return
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = "ReviewsUI"
	gui.ResetOnSpawn = false
	gui.Enabled = false
	gui.DisplayOrder = 10 -- Above HUD
	gui.Parent = PlayerGui
	ScreenGui = gui

	-- Main Frame
	local mainFrame = Instance.new("Frame")
	mainFrame.Name = "MainFrame"
	mainFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	mainFrame.Position = UDim2.fromScale(0.5, 0.5)
	mainFrame.Size = UDim2.new(0, 400, 0.65, 0)
	mainFrame.BackgroundColor3 = Color3.fromRGB(248, 250, 252)
	mainFrame.BorderSizePixel = 0
	mainFrame.ClipsDescendants = true
	mainFrame.Parent = gui
	MainFrame = mainFrame

	local sizeConstraint = Instance.new("UISizeConstraint")
	sizeConstraint.MaxSize = Vector2.new(400, 600)
	sizeConstraint.MinSize = Vector2.new(300, 300)
	sizeConstraint.Parent = mainFrame

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = mainFrame

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(220, 220, 220)
	stroke.Thickness = 1
	stroke.Parent = mainFrame

	-- Title Bar
	local titleBar = Instance.new("Frame")
	titleBar.Name = "TitleBar"
	titleBar.BackgroundTransparency = 1
	titleBar.Size = UDim2.new(1, 0, 0, 50)
	titleBar.Parent = mainFrame

	local titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "Title"
	titleLabel.BackgroundTransparency = 1
	titleLabel.Size = UDim2.new(1, -50, 1, 0)
	titleLabel.Position = UDim2.fromOffset(20, 0)
	titleLabel.Font = Enum.Font.GothamBold
	titleLabel.Text = "Tenant Reviews"
	titleLabel.TextColor3 = Color3.fromRGB(45, 55, 75)
	titleLabel.TextSize = 20
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.Parent = titleBar

	local overallRatingLabel = Instance.new("TextLabel")
	overallRatingLabel.Name = "OverallRating"
	overallRatingLabel.AnchorPoint = Vector2.new(1, 0.5)
	overallRatingLabel.BackgroundTransparency = 1
	overallRatingLabel.Size = UDim2.new(0, 100, 1, 0)
	overallRatingLabel.Position = UDim2.new(1, -50, 0.5, 0)
	overallRatingLabel.Font = Enum.Font.GothamBold
	overallRatingLabel.Text = ""
	overallRatingLabel.TextColor3 = Color3.fromRGB(255, 180, 0)
	overallRatingLabel.TextSize = 18
	overallRatingLabel.TextXAlignment = Enum.TextXAlignment.Right
	overallRatingLabel.Parent = titleBar
	OverallRatingLabel = overallRatingLabel

	local closeButton = Instance.new("ImageButton")
	closeButton.Name = "CloseButton"
	closeButton.AnchorPoint = Vector2.new(1, 0.5)
	closeButton.Position = UDim2.new(1, -15, 0.5, 0)
	closeButton.Size = UDim2.fromOffset(24, 24)
	closeButton.BackgroundTransparency = 1
	closeButton.Image = "rbxassetid://3926305904" -- Close icon
	closeButton.ImageRectOffset = Vector2.new(284, 4)
	closeButton.ImageRectSize = Vector2.new(24, 24)
	closeButton.ImageColor3 = Color3.fromRGB(100, 100, 100)
	closeButton.Parent = titleBar

	closeButton.MouseButton1Click:Connect(function()
		SoundtrackManager.PlayButtonClick()
		ReviewsUI.SetVisible(false)
	end)

	local separator = Instance.new("Frame")
	separator.Name = "Separator"
	separator.BackgroundColor3 = Color3.fromRGB(230, 230, 230)
	separator.BorderSizePixel = 0
	separator.Position = UDim2.new(0, 0, 1, -1)
	separator.Size = UDim2.new(1, 0, 0, 1)
	separator.Parent = titleBar

	-- Container
	local container = Instance.new("ScrollingFrame")
	container.Name = "Container"
	container.BackgroundTransparency = 1
	container.Position = UDim2.fromOffset(0, 50)
	container.Size = UDim2.new(1, 0, 1, -50)
	container.CanvasSize = UDim2.new(0, 0, 0, 0)
	container.ScrollBarThickness = 4
	container.ScrollBarImageColor3 = Color3.fromRGB(200, 210, 220)
	container.AutomaticCanvasSize = Enum.AutomaticSize.Y
	container.Parent = mainFrame
	Container = container

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 15)
	padding.PaddingBottom = UDim.new(0, 15)
	padding.PaddingLeft = UDim.new(0, 20)
	padding.PaddingRight = UDim.new(0, 20)
	padding.Parent = container

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 10)
	layout.Parent = container

	local emptyLabel = Instance.new("TextLabel")
	emptyLabel.Name = "EmptyLabel"
	emptyLabel.BackgroundTransparency = 1
	emptyLabel.Size = UDim2.fromScale(1, 1)
	emptyLabel.Font = Enum.Font.Gotham
	emptyLabel.Text = "No reviews yet."
	emptyLabel.TextColor3 = Color3.fromRGB(150, 150, 150)
	emptyLabel.TextSize = 16
	emptyLabel.Visible = false
	emptyLabel.Parent = container
	EmptyLabel = emptyLabel
end

function ReviewsUI.SetVisible(visible: boolean)
	if not ScreenGui then
		ReviewsUI.Init()
	end

	local gui = ScreenGui
	local mainFrame = MainFrame
	if not gui or not mainFrame then
		return
	end

	isVisible = visible
	gui.Enabled = visible

	if visible then
		-- Animate In
		mainFrame.Position = UDim2.fromScale(0.5, 0.55)
		mainFrame.BackgroundTransparency = 0 -- Ensure visible

		TweenService:Create(mainFrame, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Position = UDim2.fromScale(0.5, 0.5),
		}):Play()

		fetchReviews()
	end
end

function ReviewsUI.Toggle()
	ReviewsUI.SetVisible(not isVisible)
end

function ReviewsUI.AddLiveReview(review: { [string]: any })
	if not ScreenGui then
		return
	end
	table.insert(cachedReviews, review)
	if isVisible then
		populateList(cachedReviews)
	end
end

return ReviewsUI
