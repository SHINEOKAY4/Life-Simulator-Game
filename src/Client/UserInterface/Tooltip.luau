-- TooltipModule.lua

--[[
    TooltipModule.lua

    A lightweight, reusable tooltip system for Roblox GUI elements.

    ## Overview

    This module provides a simple way to attach tooltips to any `GuiObject`. A tooltip
    is a small popup that appears near the mouse pointer when the player hovers over
    a UI element. Each tooltip instance maintains its own state and connections so
    that multiple tooltips can coexist without interfering with one another.

    ### Features

    * **Stateless and modular** – each tooltip returned by the constructor manages
      its own events and can be disposed of independently.
    * **Customisable appearance** – colours, padding, fonts, corner radii and
      optional borders can all be overridden via an options table.
    * **Automatic sizing** – uses `TextService:GetTextSize` to calculate width and height,
      avoiding one‑frame size jumps:contentReference[oaicite:4]{index=4}.
    * **Position clamping** – the tooltip stays on screen by clamping its position
      within the current camera’s viewport.
    * **Delayed display** – specify a delay before the tooltip appears after hovering.
    * **Smooth transitions** – fade‑in and fade‑out animations via `TweenService`.
    * **Safe top bar handling** – sets `IgnoreGuiInset` on the internal `ScreenGui`
      to ignore the Roblox top bar:contentReference[oaicite:5]{index=5}.
    * **Robust hover logic** – tracks the currently hovered element to avoid
      premature hiding:contentReference[oaicite:6]{index=6}.

    See the comments in the module for usage examples and configuration details.
--]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local TextService = game:GetService("TextService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local TooltipModule = {}
TooltipModule.__index = TooltipModule

-- Tracks the currently hovered tooltip instance.
local currentHoverInstance = nil

-- Default configuration values.
local DEFAULT_OPTIONS = {
	text = "Tooltip",
	title = nil,
	description = nil,
	detailText = nil,
	thumbnail = nil,
	delay = 0.0, -- Seconds before tooltip shows
	offset = Vector2.new(28, 0), -- Pixels to offset from the mouse; positive X keeps spacing when placing to the left
	padding = Vector2.new(16, 14), -- Padding (x, y) in pixels
	maxWidth = nil, -- Maximum pixel width; nil uses 32% of viewport width
	backgroundColor3 = Color3.fromRGB(255, 255, 255),
	backgroundTransparency = 0,
	cornerRadius = UDim.new(0, 10),
	strokeColor3 = Color3.fromRGB(220, 226, 233),
	strokeTransparency = 0.2,
	strokeThickness = 1,
	accentColor3 = Color3.fromRGB(45, 170, 255),
	fadeInDuration = 0.14,
	fadeOutDuration = 0.12,
	zIndex = 10,
	allowMultiple = false,
	parent = nil, -- Optional ScreenGui parent; defaults to PlayerGui
	imageSize = Vector2.new(108, 108),
	contentSpacing = 14,
	textSpacing = 6,
	detailSpacing = 4,
	titleFont = Enum.Font.GothamBold,
	titleTextSize = 18,
	titleColor3 = Color3.fromRGB(23, 28, 43),
	descriptionFont = Enum.Font.Gotham,
	descriptionTextSize = 14,
	descriptionColor3 = Color3.fromRGB(72, 82, 96),
	detailFont = Enum.Font.GothamMedium,
	detailTextSize = 13,
	detailColor3 = Color3.fromRGB(135, 145, 160),
}

-- Merge user options with defaults.
local function mergeOptions(options)
	local result = table.clone(DEFAULT_OPTIONS)
	if options then
		for k, v in pairs(options) do
			if v ~= nil then
				result[k] = v
			end
		end
	end
	if result.title == nil then
		result.title = ""
	end
	if result.description == nil then
		result.description = typeof(result.text) == "string" and result.text or ""
	end
	if result.detailText == nil then
		result.detailText = ""
	end
	return result
end

-- Create a ScreenGui containing the tooltip frame and label.
local function createGui(options)
	local gui = Instance.new("ScreenGui")
	gui.Name = "TooltipGui"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 2147483647
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Global

	local frame = Instance.new("Frame")
	frame.Name = "TooltipFrame"
	frame.AnchorPoint = Vector2.new(0, 0)
	frame.BackgroundColor3 = options.backgroundColor3
	frame.BackgroundTransparency = options.backgroundTransparency
	frame.BorderSizePixel = 0
	frame.ClipsDescendants = true
	frame.Size = UDim2.fromOffset(0, 0)
	frame.Visible = false
	frame.ZIndex = options.zIndex

	local corner = Instance.new("UICorner")
	corner.CornerRadius = options.cornerRadius
	corner.Parent = frame

	local stroke = Instance.new("UIStroke")
	stroke.Color = options.strokeColor3
	stroke.Thickness = options.strokeThickness
	stroke.Transparency = options.strokeTransparency
	stroke.Parent = frame

	local content = Instance.new("Frame")
	content.Name = "Content"
	content.BackgroundTransparency = 1
	content.Position = UDim2.fromOffset(options.padding.X, options.padding.Y)
	content.Size = UDim2.new(1, -options.padding.X * 2, 1, -options.padding.Y * 2)
	content.ZIndex = options.zIndex + 1
	content.Parent = frame

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0, options.contentSpacing)
	layout.Parent = content

	local imageHolder = Instance.new("Frame")
	imageHolder.Name = "ThumbnailHolder"
	imageHolder.BackgroundTransparency = 1
	imageHolder.Size = UDim2.fromOffset(options.imageSize.X, options.imageSize.Y)
	imageHolder.Visible = false
	imageHolder.Parent = content

	local imageCorner = Instance.new("UICorner")
	imageCorner.CornerRadius = UDim.new(0, math.floor(math.min(options.imageSize.X, options.imageSize.Y) / 6))
	imageCorner.Parent = imageHolder

	local imageStroke = Instance.new("UIStroke")
	imageStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	imageStroke.Color = options.strokeColor3
	imageStroke.Thickness = 1
	imageStroke.Transparency = 0.2
	imageStroke.Parent = imageHolder

	local imageLabel = Instance.new("ImageLabel")
	imageLabel.Name = "Thumbnail"
	imageLabel.BackgroundTransparency = 1
	imageLabel.ImageTransparency = 1
	imageLabel.ScaleType = Enum.ScaleType.Fit
	imageLabel.Size = UDim2.fromScale(1, 1)
	imageLabel.ZIndex = options.zIndex + 1
	imageLabel.Parent = imageHolder

	local textContainer = Instance.new("Frame")
	textContainer.Name = "TextContainer"
	textContainer.BackgroundTransparency = 1
	textContainer.Size = UDim2.fromScale(1, 1)
	textContainer.Parent = content

	local textLayout = Instance.new("UIListLayout")
	textLayout.FillDirection = Enum.FillDirection.Vertical
	textLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	textLayout.VerticalAlignment = Enum.VerticalAlignment.Top
	textLayout.SortOrder = Enum.SortOrder.LayoutOrder
	textLayout.Padding = UDim.new(0, options.textSpacing)
	textLayout.Parent = textContainer

	local titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "Title"
	titleLabel.BackgroundTransparency = 1
	titleLabel.LayoutOrder = 1
	titleLabel.RichText = false
	titleLabel.TextColor3 = options.titleColor3
	titleLabel.TextSize = options.titleTextSize
	titleLabel.Font = options.titleFont
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.TextYAlignment = Enum.TextYAlignment.Top
	titleLabel.TextWrapped = true
	titleLabel.AutomaticSize = Enum.AutomaticSize.None
	titleLabel.ZIndex = options.zIndex + 1
	titleLabel.Parent = textContainer

	local descriptionLabel = Instance.new("TextLabel")
	descriptionLabel.Name = "Description"
	descriptionLabel.BackgroundTransparency = 1
	descriptionLabel.LayoutOrder = 2
	descriptionLabel.RichText = true
	descriptionLabel.TextColor3 = options.descriptionColor3
	descriptionLabel.TextSize = options.descriptionTextSize
	descriptionLabel.Font = options.descriptionFont
	descriptionLabel.TextXAlignment = Enum.TextXAlignment.Left
	descriptionLabel.TextYAlignment = Enum.TextYAlignment.Top
	descriptionLabel.TextWrapped = true
	descriptionLabel.AutomaticSize = Enum.AutomaticSize.None
	descriptionLabel.ZIndex = options.zIndex + 1
	descriptionLabel.Parent = textContainer

	local detailLabel = Instance.new("TextLabel")
	detailLabel.Name = "Detail"
	detailLabel.BackgroundTransparency = 1
	detailLabel.LayoutOrder = 3
	detailLabel.RichText = true
	detailLabel.TextColor3 = options.detailColor3
	detailLabel.TextSize = options.detailTextSize
	detailLabel.Font = options.detailFont
	detailLabel.TextXAlignment = Enum.TextXAlignment.Left
	detailLabel.TextYAlignment = Enum.TextYAlignment.Top
	detailLabel.TextWrapped = true
	detailLabel.AutomaticSize = Enum.AutomaticSize.None
	detailLabel.ZIndex = options.zIndex + 1
	detailLabel.Parent = textContainer

	frame.Parent = gui
	return gui, frame, titleLabel, descriptionLabel, detailLabel, imageHolder, imageLabel, textContainer
end

-- Compute tooltip size based on its text and configuration.

function TooltipModule:_syncContent()
	if self._titleLabel then
		self._titleLabel.Text = self._titleText
		self._titleLabel.Visible = self._titleText ~= ""
	end

	if self._descriptionLabel then
		self._descriptionLabel.Text = self._descriptionText
		self._descriptionLabel.Visible = self._descriptionText ~= ""
	end

	if self._detailLabel then
		self._detailLabel.Text = self._detailText
		self._detailLabel.Visible = self._detailText ~= ""
	end

	local thumbnail = self._thumbnailAsset
	local hasThumbnail = typeof(thumbnail) == "string" and thumbnail ~= ""
	self._hasThumbnail = hasThumbnail
	if hasThumbnail then
		self._thumbnailHolder.Visible = true
		self._thumbnailImage.Image = thumbnail
	else
		self._thumbnailHolder.Visible = false
		self._thumbnailImage.Image = ""
	end
end

function TooltipModule:_calculateLayout(): {
	width: number,
	height: number,
	textWidth: number,
	textHeight: number,
	titleHeight: number,
	descriptionHeight: number,
	detailHeight: number,
	hasTitle: boolean,
	hasDescription: boolean,
	hasDetail: boolean,
	hasThumbnail: boolean,
}
	local cam = workspace.CurrentCamera
	if not cam then
		return {
			width = 240,
			height = 120,
			textWidth = 160,
			textHeight = 80,
			titleHeight = 0,
			descriptionHeight = 80,
			detailHeight = 0,
			hasTitle = self._titleText ~= "",
			hasDescription = self._descriptionText ~= "",
			hasDetail = self._detailText ~= "",
			hasThumbnail = self._hasThumbnail == true,
		}
	end

	local viewport = cam.ViewportSize
	local padX = self._options.padding.X
	local padY = self._options.padding.Y
	local maxWidth = self._options.maxWidth or math.floor(viewport.X * 0.32)
	local hasTitle = self._titleText ~= ""
	local hasDescription = self._descriptionText ~= ""
	local hasDetail = self._detailText ~= ""
	local hasThumbnail = self._hasThumbnail == true

	local thumbnailWidth = hasThumbnail and self._options.imageSize.X or 0
	local thumbnailHeight = hasThumbnail and self._options.imageSize.Y or 0
	local reservedWidth = hasThumbnail and (thumbnailWidth + self._options.contentSpacing) or 0

	local maxContentWidth = math.max(maxWidth - padX * 2, 120)
	local tentativeTextWidth = math.max(maxContentWidth - reservedWidth, 120)
	local totalWidth = padX * 2 + reservedWidth + tentativeTextWidth
	if totalWidth > maxWidth then
		totalWidth = maxWidth
		tentativeTextWidth = math.max(totalWidth - padX * 2 - reservedWidth, 100)
	end

	local textWidth = tentativeTextWidth
	local textSpace = Vector2.new(textWidth, math.huge)

	local titleHeight = 0
	if hasTitle then
		titleHeight =
			TextService:GetTextSize(self._titleText, self._options.titleTextSize, self._options.titleFont, textSpace).Y
	end

	local descriptionHeight = 0
	if hasDescription then
		descriptionHeight = TextService:GetTextSize(
			self._descriptionText,
			self._options.descriptionTextSize,
			self._options.descriptionFont,
			textSpace
		).Y
	end

	local detailHeight = 0
	if hasDetail then
		detailHeight = TextService:GetTextSize(
			self._detailText,
			self._options.detailTextSize,
			self._options.detailFont,
			textSpace
		).Y
	end

	local textHeight = 0
	local spacingAccumulator = 0
	if hasTitle then
		textHeight += titleHeight
	end
	if hasDescription then
		if textHeight > 0 then
			spacingAccumulator += self._options.textSpacing
		end
		textHeight += descriptionHeight
	end
	if hasDetail then
		if textHeight > 0 then
			spacingAccumulator += self._options.detailSpacing
		end
		textHeight += detailHeight
	end
	textHeight += spacingAccumulator

	local contentHeight = math.max(textHeight, thumbnailHeight)
	if contentHeight == 0 then
		contentHeight = math.floor(self._options.imageSize.Y * 0.75)
	end

	local totalHeight = padY * 2 + contentHeight
	return {
		width = totalWidth,
		height = totalHeight,
		textWidth = textWidth,
		textHeight = textHeight,
		titleHeight = titleHeight,
		descriptionHeight = descriptionHeight,
		detailHeight = detailHeight,
		hasTitle = hasTitle,
		hasDescription = hasDescription,
		hasDetail = hasDetail,
		hasThumbnail = hasThumbnail,
		thumbnailWidth = thumbnailWidth,
		thumbnailHeight = thumbnailHeight,
		contentHeight = contentHeight,
	}
end

function TooltipModule:_applyLayout(layoutInfo)
	if self._thumbnailHolder then
		self._thumbnailHolder.Visible = layoutInfo.hasThumbnail
		local width = layoutInfo.hasThumbnail and layoutInfo.thumbnailWidth or 0
		local height = layoutInfo.hasThumbnail and layoutInfo.thumbnailHeight or 0
		self._thumbnailHolder.Size = UDim2.fromOffset(width, height)
	end

	if self._textContainer then
		local height = math.max(layoutInfo.textHeight, 0)
		self._textContainer.Size = UDim2.fromOffset(layoutInfo.textWidth, height)
	end

	if self._titleLabel then
		self._titleLabel.Visible = layoutInfo.hasTitle
		local titleHeight = layoutInfo.hasTitle and layoutInfo.titleHeight or 0
		self._titleLabel.Size = UDim2.fromOffset(layoutInfo.textWidth, titleHeight)
	end

	if self._descriptionLabel then
		self._descriptionLabel.Visible = layoutInfo.hasDescription
		local descHeight = layoutInfo.hasDescription and layoutInfo.descriptionHeight or 0
		self._descriptionLabel.Size = UDim2.fromOffset(layoutInfo.textWidth, descHeight)
	end

	if self._detailLabel then
		self._detailLabel.Visible = layoutInfo.hasDetail
		local detailHeight = layoutInfo.hasDetail and layoutInfo.detailHeight or 0
		self._detailLabel.Size = UDim2.fromOffset(layoutInfo.textWidth, detailHeight)
	end
end

-- Update the tooltip’s position to follow the mouse while staying on-screen.
function TooltipModule:_updatePosition(mouseX, mouseY)
	local layoutInfo = self:_calculateLayout()
	self:_applyLayout(layoutInfo)
	local width = layoutInfo.width
	local height = layoutInfo.height
	local cam = workspace.CurrentCamera
	if not cam then
		return
	end
	local viewport = cam.ViewportSize
	local offsetX = self._options.offset.X
	local offsetY = self._options.offset.Y
	local targetX = mouseX - offsetX - width
	local targetY = mouseY - (height * 0.5) + offsetY
	targetX = math.clamp(targetX, 0, viewport.X - width)
	targetY = math.clamp(targetY, 0, viewport.Y - height)
	self._frame.Position = UDim2.fromOffset(targetX, targetY)
	self._frame.Size = UDim2.fromOffset(width, height)
end

-- Handle MouseEnter: start a delay timer before showing.
function TooltipModule:_onMouseEnter()
	currentHoverInstance = self
	if self._pendingShow then
		task.cancel(self._pendingShow)
	end
	if self._options.delay > 0 then
		self._pendingShow = task.delay(self._options.delay, function()
			if currentHoverInstance == self then
				self:Show()
			end
		end)
	else
		self:Show()
	end
end

-- Handle MouseLeave: hide if this is the currently hovered tooltip.
function TooltipModule:_onMouseLeave()
	if currentHoverInstance == self then
		currentHoverInstance = nil
		self:Hide()
	end
end

-- Handle MouseMoved: reposition the tooltip.
function TooltipModule:_onMouseMoved(x, y)
	if currentHoverInstance == self then
		self:_updatePosition(x, y)
	end
end

-- Create a new tooltip attached to the given GuiObject.
function TooltipModule.new(object, options)
	assert(
		typeof(object) == "Instance" and object:IsA("GuiObject"),
		"TooltipModule.new requires a GuiObject as the first argument"
	)
	local self = setmetatable({}, TooltipModule)
	self._options = mergeOptions(options)
	self._titleText = typeof(self._options.title) == "string" and self._options.title or ""
	self._descriptionText = typeof(self._options.description) == "string" and self._options.description or ""
	self._detailText = typeof(self._options.detailText) == "string" and self._options.detailText or ""
	self._thumbnailAsset = typeof(self._options.thumbnail) == "string" and self._options.thumbnail or ""
	self._text = self._descriptionText ~= "" and self._descriptionText or self._titleText
	self._gui, self._frame, self._titleLabel, self._descriptionLabel, self._detailLabel, self._thumbnailHolder, self._thumbnailImage, self._textContainer =
		createGui(self._options)
	self._contentFrame = self._frame:FindFirstChild("Content")
	self._contentLayout = self._contentFrame and self._contentFrame:FindFirstChildWhichIsA("UIListLayout")
	self._textLayout = self._textContainer:FindFirstChildWhichIsA("UIListLayout")
	self._frameStroke = self._frame:FindFirstChildWhichIsA("UIStroke")
	self._textLabels = {
		self._titleLabel,
		self._descriptionLabel,
		self._detailLabel,
	}
	self._isVisible = false
	self._pendingShow = nil
	self._fadeTween = nil
	self._activeTextTweens = {}
	self._imageTween = nil
	self._object = object
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

	self:_syncContent()
	return self
end

-- Show the tooltip. Hides any other tooltips if allowMultiple is false.
function TooltipModule:Show()
	if self._isVisible then
		return
	end
	self._isVisible = true
	if not self._options.allowMultiple and currentHoverInstance and currentHoverInstance ~= self then
		currentHoverInstance:Hide()
	end
	local parent = self._options.parent
	if not parent then
		local player = Players.LocalPlayer
		local playerGui = player and player:FindFirstChild("PlayerGui")
		parent = playerGui or game:GetService("CoreGui")
	end
	self._gui.Parent = parent
	self:_syncContent()
	local mousePos = UserInputService:GetMouseLocation()
	self:_updatePosition(mousePos.X, mousePos.Y)
	self._frame.Visible = true
	if self._fadeTween then
		self._fadeTween:Cancel()
	end
	for _, tween in ipairs(self._activeTextTweens) do
		tween:Cancel()
	end
	table.clear(self._activeTextTweens)
	if self._imageTween then
		self._imageTween:Cancel()
		self._imageTween = nil
	end
	-- Set initial transparency for fade-in
	self._frame.BackgroundTransparency = 1
	if self._frameStroke then
		self._frameStroke.Transparency = 1
	end
	for _, label in ipairs(self._textLabels) do
		if label and label.Visible then
			label.TextTransparency = 1
		end
	end
	if self._thumbnailHolder and self._thumbnailHolder.Visible then
		self._thumbnailImage.ImageTransparency = 1
	end
	local tweenInfo = TweenInfo.new(self._options.fadeInDuration, Enum.EasingStyle.Linear, Enum.EasingDirection.Out)
	self._fadeTween = TweenService:Create(self._frame, tweenInfo, {
		BackgroundTransparency = self._options.backgroundTransparency,
	})
	self._fadeTween:Play()
	if self._frameStroke then
		local strokeTween = TweenService:Create(self._frameStroke, tweenInfo, {
			Transparency = self._options.strokeTransparency,
		})
		strokeTween:Play()
		self._activeTextTweens[#self._activeTextTweens + 1] = strokeTween
	end
	for _, label in ipairs(self._textLabels) do
		if label and label.Visible then
			local textTween = TweenService:Create(label, tweenInfo, {
				TextTransparency = 0,
			})
			textTween:Play()
			self._activeTextTweens[#self._activeTextTweens + 1] = textTween
		end
	end
	if self._thumbnailHolder and self._thumbnailHolder.Visible then
		self._imageTween = TweenService:Create(self._thumbnailImage, tweenInfo, {
			ImageTransparency = 0,
		})
		self._imageTween:Play()
	end
end

-- Hide the tooltip with a fade-out.
function TooltipModule:Hide()
	if not self._isVisible and not self._pendingShow then
		return
	end
	if self._pendingShow then
		task.cancel(self._pendingShow)
		self._pendingShow = nil
	end
	if self._isVisible then
		self._isVisible = false
		if self._fadeTween then
			self._fadeTween:Cancel()
		end
		for _, tween in ipairs(self._activeTextTweens) do
			tween:Cancel()
		end
		table.clear(self._activeTextTweens)
		if self._imageTween then
			self._imageTween:Cancel()
			self._imageTween = nil
		end
		local tweenInfo =
			TweenInfo.new(self._options.fadeOutDuration, Enum.EasingStyle.Linear, Enum.EasingDirection.Out)
		local fadeOut = TweenService:Create(self._frame, tweenInfo, {
			BackgroundTransparency = 1,
		})
		local strokeFade
		if self._frameStroke then
			strokeFade = TweenService:Create(self._frameStroke, tweenInfo, {
				Transparency = 1,
			})
			strokeFade:Play()
		end
		for _, label in ipairs(self._textLabels) do
			if label then
				local textFade = TweenService:Create(label, tweenInfo, {
					TextTransparency = 1,
				})
				textFade:Play()
			end
		end
		if self._thumbnailHolder and self._thumbnailHolder.Visible then
			local imageFade = TweenService:Create(self._thumbnailImage, tweenInfo, {
				ImageTransparency = 1,
			})
			imageFade:Play()
		end
		fadeOut.Completed:Connect(function()
			self._frame.Visible = false
			self._gui.Parent = nil
		end)
		fadeOut:Play()
	end
end

-- Destroy the tooltip and disconnect all events.
function TooltipModule:Destroy()
	if self._pendingShow then
		task.cancel(self._pendingShow)
		self._pendingShow = nil
	end
	if self._fadeTween then
		self._fadeTween:Cancel()
	end
	for _, tween in ipairs(self._activeTextTweens) do
		tween:Cancel()
	end
	self._activeTextTweens = {}
	if self._imageTween then
		self._imageTween:Cancel()
		self._imageTween = nil
	end
	self._gui.Parent = nil
	self._gui:Destroy()
	for _, conn in ipairs(self._connections) do
		conn:Disconnect()
	end
	table.clear(self._connections)
	if currentHoverInstance == self then
		currentHoverInstance = nil
	end
end

-- Update the tooltip text and reposition if visible.
function TooltipModule:SetText(newText)
	assert(type(newText) == "string", "SetText expects a string")
	self._text = newText
	self._descriptionText = newText
	self._options.description = newText
	if self._isVisible then
		self:_syncContent()
		local mousePos = UserInputService:GetMouseLocation()
		self:_updatePosition(mousePos.X, mousePos.Y)
	end
end

function TooltipModule:SetItemContent(content)
	assert(type(content) == "table", "SetItemContent expects a table")
	if content.Title ~= nil then
		self._titleText = tostring(content.Title)
		self._options.title = self._titleText
	end
	if content.Description ~= nil then
		self._descriptionText = tostring(content.Description)
		self._text = self._descriptionText
		self._options.description = self._descriptionText
	end
	local detailText = self._detailText
	if content.Detail ~= nil then
		detailText = tostring(content.Detail)
	end
	if typeof(content.Highlights) == "table" then
		local bulletLines = table.create(#content.Highlights)
		for _, entry in ipairs(content.Highlights) do
			if typeof(entry) == "string" and entry ~= "" then
				bulletLines[#bulletLines + 1] = entry
			end
		end
		if #bulletLines > 0 then
			local highlights = table.concat(bulletLines, "\n")
			if detailText ~= nil and detailText ~= "" then
				detailText = detailText .. "\n" .. highlights
			else
				detailText = highlights
			end
		end
	end
	if detailText ~= nil then
		self._detailText = detailText
		self._options.detailText = detailText
	end
	if content.Thumbnail ~= nil then
		if typeof(content.Thumbnail) == "string" then
			self._thumbnailAsset = content.Thumbnail
		else
			self._thumbnailAsset = ""
		end
		self._options.thumbnail = self._thumbnailAsset
	end
	if self._thumbnailHolder then
		local thumbStroke = self._thumbnailHolder:FindFirstChildWhichIsA("UIStroke")
		if thumbStroke then
			thumbStroke.Color = self._options.strokeColor3
		end
	end
	self:_syncContent()
	if self._isVisible then
		local mousePos = UserInputService:GetMouseLocation()
		self:_updatePosition(mousePos.X, mousePos.Y)
	end
end

-- Update one or more options on an existing tooltip.
function TooltipModule:UpdateOptions(options)
	assert(type(options) == "table", "UpdateOptions expects a table")
	for k, v in pairs(options) do
		if DEFAULT_OPTIONS[k] ~= nil then
			self._options[k] = v
		end
		if k == "title" and typeof(v) == "string" then
			self._titleText = v
		elseif k == "description" and typeof(v) == "string" then
			self._descriptionText = v
			self._text = v
		elseif k == "detailText" and typeof(v) == "string" then
			self._detailText = v
		elseif k == "thumbnail" then
			if typeof(v) == "string" then
				self._thumbnailAsset = v
			else
				self._thumbnailAsset = ""
			end
		end
	end

	self._frame.BackgroundColor3 = self._options.backgroundColor3
	if not self._isVisible then
		self._frame.BackgroundTransparency = 1
		if self._frameStroke then
			self._frameStroke.Transparency = 1
		end
		for _, label in ipairs(self._textLabels) do
			if label then
				label.TextTransparency = 1
			end
		end
		if self._thumbnailHolder then
			self._thumbnailImage.ImageTransparency = 1
		end
	end
	if self._frameStroke then
		self._frameStroke.Color = self._options.strokeColor3
		self._frameStroke.Transparency = self._options.strokeTransparency
		self._frameStroke.Thickness = self._options.strokeThickness
	end
	if self._frame:FindFirstChildOfClass("UICorner") then
		self._frame.UICorner.CornerRadius = self._options.cornerRadius
	end
	if self._contentFrame then
		self._contentFrame.Position = UDim2.fromOffset(self._options.padding.X, self._options.padding.Y)
		self._contentFrame.Size = UDim2.new(1, -self._options.padding.X * 2, 1, -self._options.padding.Y * 2)
	end
	if self._contentLayout then
		self._contentLayout.Padding = UDim.new(0, self._options.contentSpacing)
	end
	if self._textLayout then
		self._textLayout.Padding = UDim.new(0, self._options.textSpacing)
	end
	if self._thumbnailHolder then
		self._thumbnailHolder.Size = UDim2.fromOffset(self._options.imageSize.X, self._options.imageSize.Y)
		local corner = self._thumbnailHolder:FindFirstChildWhichIsA("UICorner")
		if corner then
			corner.CornerRadius =
				UDim.new(0, math.floor(math.min(self._options.imageSize.X, self._options.imageSize.Y) / 6))
		end
		local thumbStroke = self._thumbnailHolder:FindFirstChildWhichIsA("UIStroke")
		if thumbStroke then
			thumbStroke.Color = self._options.strokeColor3
		end
	end
	if self._titleLabel then
		self._titleLabel.TextColor3 = self._options.titleColor3
		self._titleLabel.Font = self._options.titleFont
		self._titleLabel.TextSize = self._options.titleTextSize
	end
	if self._descriptionLabel then
		self._descriptionLabel.TextColor3 = self._options.descriptionColor3
		self._descriptionLabel.Font = self._options.descriptionFont
		self._descriptionLabel.TextSize = self._options.descriptionTextSize
	end
	if self._detailLabel then
		self._detailLabel.TextColor3 = self._options.detailColor3
		self._detailLabel.Font = self._options.detailFont
		self._detailLabel.TextSize = self._options.detailTextSize
	end

	self:_syncContent()
	if self._isVisible then
		local mousePos = UserInputService:GetMouseLocation()
		self:_updatePosition(mousePos.X, mousePos.Y)
	end
end

-- Return whether the tooltip is currently visible.
function TooltipModule:IsVisible()
	return self._isVisible
end

return TooltipModule
