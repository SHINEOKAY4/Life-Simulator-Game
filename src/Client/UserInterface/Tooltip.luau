-- TooltipModule.lua
-- Revamped for modern UI with structured stats support

local UserInputService = game:GetService("UserInputService")

local TooltipModule = {}
TooltipModule.__index = TooltipModule

local currentHoverInstance = nil

local DEFAULT_OPTIONS = {
	text = "Tooltip",
	title = "",
	description = "",
	thumbnail = nil,
	delay = 0.0,
	offset = Vector2.new(20, 20),
	padding = Vector2.new(12, 12),
	maxWidth = 280,
	backgroundColor3 = Color3.fromRGB(30, 33, 36),
	backgroundTransparency = 0.05,
	cornerRadius = UDim.new(0, 8),
	strokeColor3 = Color3.fromRGB(60, 63, 66),
	strokeTransparency = 0,
	strokeThickness = 1,
	fadeInDuration = 0.15,
	fadeOutDuration = 0.1,
	zIndex = 100,
	allowMultiple = false,
	parent = nil,
	imageSize = Vector2.new(48, 48),
	contentSpacing = 8,
	titleFont = Enum.Font.GothamBold,
	titleTextSize = 16,
	titleColor3 = Color3.fromRGB(255, 255, 255),
	descriptionFont = Enum.Font.Gotham,
	descriptionTextSize = 13,
	descriptionColor3 = Color3.fromRGB(200, 200, 200),
}

local function mergeOptions(options)
	local result = table.clone(DEFAULT_OPTIONS)
	if options then
		for k, v in pairs(options) do
			if v ~= nil then
				result[k] = v
			end
		end
	end
	return result
end

local function createGui(options)
	local gui = Instance.new("ScreenGui")
	gui.Name = "TooltipGui"
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 1000
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	local frame = Instance.new("Frame")
	frame.Name = "TooltipFrame"
	frame.BackgroundColor3 = options.backgroundColor3
	frame.BackgroundTransparency = options.backgroundTransparency
	frame.BorderSizePixel = 0
	frame.Size = UDim2.fromOffset(options.maxWidth, 0)
	frame.AutomaticSize = Enum.AutomaticSize.Y
	frame.Visible = false

	local corner = Instance.new("UICorner")
	corner.CornerRadius = options.cornerRadius
	corner.Parent = frame

	local stroke = Instance.new("UIStroke")
	stroke.Color = options.strokeColor3
	stroke.Thickness = options.strokeThickness
	stroke.Transparency = options.strokeTransparency
	stroke.Parent = frame

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, options.padding.Y)
	padding.PaddingBottom = UDim.new(0, options.padding.Y)
	padding.PaddingLeft = UDim.new(0, options.padding.X)
	padding.PaddingRight = UDim.new(0, options.padding.X)
	padding.Parent = frame

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.Padding = UDim.new(0, options.contentSpacing)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = frame

	-- Header (Title)
	local titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "Title"
	titleLabel.BackgroundTransparency = 1
	titleLabel.TextColor3 = options.titleColor3
	titleLabel.Font = options.titleFont
	titleLabel.TextSize = options.titleTextSize
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.TextWrapped = true
	titleLabel.Size = UDim2.fromScale(1, 0)
	titleLabel.AutomaticSize = Enum.AutomaticSize.Y
	titleLabel.LayoutOrder = 1
	titleLabel.Parent = frame

	-- Body (Thumbnail + Description)
	local bodyFrame = Instance.new("Frame")
	bodyFrame.Name = "Body"
	bodyFrame.BackgroundTransparency = 1
	bodyFrame.Size = UDim2.fromScale(1, 0)
	bodyFrame.AutomaticSize = Enum.AutomaticSize.Y
	bodyFrame.LayoutOrder = 2
	bodyFrame.Parent = frame

	local bodyLayout = Instance.new("UIListLayout")
	bodyLayout.FillDirection = Enum.FillDirection.Horizontal
	bodyLayout.VerticalAlignment = Enum.VerticalAlignment.Top
	bodyLayout.Padding = UDim.new(0, 8)
	bodyLayout.Parent = bodyFrame

	local thumbnailHolder = Instance.new("Frame")
	thumbnailHolder.Name = "ThumbnailHolder"
	thumbnailHolder.BackgroundTransparency = 1
	thumbnailHolder.Size = UDim2.fromOffset(options.imageSize.X, options.imageSize.Y)
	thumbnailHolder.Visible = false
	thumbnailHolder.Parent = bodyFrame

	local thumbImage = Instance.new("ImageLabel")
	thumbImage.Name = "Image"
	thumbImage.BackgroundTransparency = 1
	thumbImage.Size = UDim2.fromScale(1, 1)
	thumbImage.ScaleType = Enum.ScaleType.Fit
	thumbImage.Parent = thumbnailHolder

	local descriptionLabel = Instance.new("TextLabel")
	descriptionLabel.Name = "Description"
	descriptionLabel.BackgroundTransparency = 1
	descriptionLabel.TextColor3 = options.descriptionColor3
	descriptionLabel.Font = options.descriptionFont
	descriptionLabel.TextSize = options.descriptionTextSize
	descriptionLabel.TextWrapped = true
	descriptionLabel.TextXAlignment = Enum.TextXAlignment.Left
	descriptionLabel.AutomaticSize = Enum.AutomaticSize.Y
	descriptionLabel.Size = UDim2.fromScale(1, 0)
	descriptionLabel.Parent = bodyFrame

	-- Stats Container
	local statsFrame = Instance.new("Frame")
	statsFrame.Name = "Stats"
	statsFrame.BackgroundTransparency = 1
	statsFrame.Size = UDim2.fromScale(1, 0)
	statsFrame.AutomaticSize = Enum.AutomaticSize.Y
	statsFrame.LayoutOrder = 3
	statsFrame.Parent = frame

	local statsLayout = Instance.new("UIListLayout")
	statsLayout.FillDirection = Enum.FillDirection.Vertical
	statsLayout.Padding = UDim.new(0, 4)
	statsLayout.Parent = statsFrame

	frame.Parent = gui
	return gui, frame, titleLabel, descriptionLabel, thumbnailHolder, thumbImage, statsFrame
end

function TooltipModule.new(object, options)
	local self = setmetatable({}, TooltipModule)
	self._options = mergeOptions(options)
	self._gui, self._frame, self._titleLabel, self._descriptionLabel, self._thumbnailHolder, self._thumbnailImage, self._statsFrame =
		createGui(self._options)

	self._connections = {}
	table.insert(
		self._connections,
		object.MouseEnter:Connect(function()
			self:_onMouseEnter()
		end)
	)
	table.insert(
		self._connections,
		object.MouseLeave:Connect(function()
			self:_onMouseLeave()
		end)
	)
	table.insert(
		self._connections,
		object.MouseMoved:Connect(function(x, y)
			self:_onMouseMoved(x, y)
		end)
	)

	return self
end

function TooltipModule:_renderStats(stats)
	for _, child in ipairs(self._statsFrame:GetChildren()) do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end

	if not stats or #stats == 0 then
		self._statsFrame.Visible = false
		return
	end
	self._statsFrame.Visible = true

	for _, stat in ipairs(stats) do
		local row = Instance.new("Frame")
		row.Name = "StatRow"
		row.BackgroundColor3 = Color3.fromRGB(45, 48, 52)
		row.BorderSizePixel = 0
		row.Size = UDim2.new(1, 0, 0, 24)
		row.Parent = self._statsFrame

		local rowCorner = Instance.new("UICorner")
		rowCorner.CornerRadius = UDim.new(0, 4)
		rowCorner.Parent = row

		local rowLayout = Instance.new("UIListLayout")
		rowLayout.FillDirection = Enum.FillDirection.Horizontal
		rowLayout.VerticalAlignment = Enum.VerticalAlignment.Center
		rowLayout.Padding = UDim.new(0, 8)
		rowLayout.Parent = row

		local rowPadding = Instance.new("UIPadding")
		rowPadding.PaddingLeft = UDim.new(0, 8)
		rowPadding.PaddingRight = UDim.new(0, 8)
		rowPadding.Parent = row

		-- Icon/Label
		local labelText = (stat.Icon or "") .. " " .. (stat.Label or "")
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Text = labelText
		label.TextColor3 = Color3.fromRGB(180, 180, 180)
		label.Font = Enum.Font.GothamMedium
		label.TextSize = 12
		label.AutomaticSize = Enum.AutomaticSize.X
		label.Size = UDim2.fromScale(0, 1)
		label.Parent = row

		-- Spacer
		local spacer = Instance.new("Frame")
		spacer.BackgroundTransparency = 1
		spacer.Size = UDim2.fromScale(1, 1) -- Will fill remaining space? No, UIListLayout doesn't fill.
		-- We can use a flexible frame if we want right alignment.
		-- Actually, let's just put Value on the right.
		-- Since UIListLayout stacks left-to-right, we can't easily right-align the last item without a wrapper or script.
		-- But we can set the Label size to expand? No.
		-- Let's just put the Value next to it for now, or use a different layout.
		-- Better: Use a Frame for Value with AnchorPoint/Position?
		-- Let's keep it simple: Label [Space] Value.
		-- To push Value to the right, we can make the Label take up available space? No.
		-- We can insert a "Spring" frame.
		spacer.LayoutOrder = 2
		spacer.Parent = row

		-- Value
		local value = Instance.new("TextLabel")
		value.BackgroundTransparency = 1
		value.Text = stat.Value or ""
		value.TextColor3 = stat.Color or Color3.fromRGB(255, 255, 255)
		value.Font = Enum.Font.GothamBold
		value.TextSize = 12
		value.AutomaticSize = Enum.AutomaticSize.X
		value.Size = UDim2.fromScale(0, 1)
		value.LayoutOrder = 3
		value.Parent = row

		-- Make spacer fill space
		-- In UIListLayout, we can't easily fill space.
		-- Hack: Set spacer Size to UDim2.new(1, - (labelWidth + valueWidth), 1, 0) ? Hard to calculate.
		-- Alternative: Don't use UIListLayout for the row. Use direct positioning.
		rowLayout:Destroy()

		label.Position = UDim2.fromScale(0, 0)
		label.Size = UDim2.fromScale(0.6, 1)
		label.TextXAlignment = Enum.TextXAlignment.Left

		value.Position = UDim2.fromScale(0.6, 0)
		value.Size = UDim2.fromScale(0.4, 1)
		value.TextXAlignment = Enum.TextXAlignment.Right
	end
end

function TooltipModule:SetItemContent(content)
	self._titleLabel.Text = content.Title or ""
	self._titleLabel.Visible = (content.Title ~= nil and content.Title ~= "")

	self._descriptionLabel.Text = content.Description or ""
	self._descriptionLabel.Visible = (content.Description ~= nil and content.Description ~= "")

	if content.Thumbnail then
		self._thumbnailHolder.Visible = true
		self._thumbnailImage.Image = content.Thumbnail
		self._descriptionLabel.Size = UDim2.new(1, -(self._options.imageSize.X + 8), 0, 0)
	else
		self._thumbnailHolder.Visible = false
		self._descriptionLabel.Size = UDim2.fromScale(1, 0)
	end

	self:_renderStats(content.Stats)

	self:_updatePosition(UserInputService:GetMouseLocation().X, UserInputService:GetMouseLocation().Y)
end

function TooltipModule:_updatePosition(mouseX, mouseY)
	local viewport = workspace.CurrentCamera.ViewportSize
	local size = self._frame.AbsoluteSize
	local offset = self._options.offset

	local targetX = mouseX + offset.X
	local targetY = mouseY + offset.Y

	if targetX + size.X > viewport.X then
		targetX = mouseX - size.X - offset.X
	end
	if targetY + size.Y > viewport.Y then
		targetY = viewport.Y - size.Y - offset.Y -- Clamp bottom
	end

	self._frame.Position = UDim2.fromOffset(targetX, targetY)
end

function TooltipModule:_onMouseEnter()
	currentHoverInstance = self
	if self._options.delay > 0 then
		task.delay(self._options.delay, function()
			if currentHoverInstance == self then
				self:Show()
			end
		end)
	else
		self:Show()
	end
end

function TooltipModule:_onMouseLeave()
	if currentHoverInstance == self then
		currentHoverInstance = nil
		self:Hide()
	end
end

function TooltipModule:_onMouseMoved(x, y)
	if currentHoverInstance == self then
		self:_updatePosition(x, y)
	end
end

function TooltipModule:Show()
	if self._frame.Visible then
		return
	end
	local parent = self._options.parent or game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui")
	self._gui.Parent = parent
	self._frame.Visible = true
	self:_updatePosition(UserInputService:GetMouseLocation().X, UserInputService:GetMouseLocation().Y)
end

function TooltipModule:Hide()
	self._frame.Visible = false
	self._gui.Parent = nil
end

function TooltipModule:Destroy()
	self:Hide()
	self._gui:Destroy()
	for _, conn in ipairs(self._connections) do
		conn:Disconnect()
	end
end

return TooltipModule
