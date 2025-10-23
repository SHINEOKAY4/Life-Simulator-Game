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
	delay = 0.0, -- Seconds before tooltip shows
	offset = Vector2.new(16, 24), -- Pixel offset from mouse position
	padding = Vector2.new(12, 6), -- Padding (x, y) in pixels
	maxWidth = nil, -- Maximum pixel width; nil uses 30% of viewport width
	backgroundColor3 = Color3.fromRGB(32, 32, 32),
	backgroundTransparency = 0.1,
	textColor3 = Color3.fromRGB(255, 255, 255),
	textSize = 14,
	font = Enum.Font.Gotham,
	cornerRadius = UDim.new(0, 4),
	strokeColor3 = Color3.fromRGB(0, 0, 0),
	strokeTransparency = 0.4,
	strokeThickness = 1,
	fadeInDuration = 0.12,
	fadeOutDuration = 0.12,
	zIndex = 10,
	allowMultiple = false,
	parent = nil, -- Optional ScreenGui parent; defaults to PlayerGui
}

-- Merge user options with defaults.
local function mergeOptions(options)
	local result = {}
	for k, v in pairs(DEFAULT_OPTIONS) do
		result[k] = v
	end
	if options then
		for k, v in pairs(options) do
			if v ~= nil then
				result[k] = v
			end
		end
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

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, options.padding.X)
	padding.PaddingRight = UDim.new(0, options.padding.X)
	padding.PaddingTop = UDim.new(0, options.padding.Y)
	padding.PaddingBottom = UDim.new(0, options.padding.Y)
	padding.Parent = frame

	local textLabel = Instance.new("TextLabel")
	textLabel.Name = "TooltipText"
	textLabel.BackgroundTransparency = 1
	textLabel.TextColor3 = options.textColor3
	textLabel.TextSize = options.textSize
	textLabel.Font = options.font
	textLabel.Text = options.text
	textLabel.TextWrapped = true
	textLabel.TextXAlignment = Enum.TextXAlignment.Left
	textLabel.TextYAlignment = Enum.TextYAlignment.Center
	textLabel.Size = UDim2.fromScale(1, 1)
	textLabel.AutomaticSize = Enum.AutomaticSize.None
	textLabel.ZIndex = options.zIndex + 1
	textLabel.Parent = frame

	frame.Parent = gui
	return gui, frame, textLabel
end

-- Compute tooltip size based on its text and configuration.
function TooltipModule:_calculateSize()
	local cam = workspace.CurrentCamera
	if not cam then
		return 200, 50
	end
	local viewport = cam.ViewportSize
	local padX = self._options.padding.X
	local padY = self._options.padding.Y
	local maxWidth = self._options.maxWidth or math.floor(viewport.X * 0.3)
	local availWidth = math.max(maxWidth - padX * 2, 10)
	local textSize = TextService:GetTextSize(
		self._text,
		self._options.textSize,
		self._options.font,
		Vector2.new(availWidth, math.huge)
	)
	local width = math.clamp(textSize.X + padX * 2, 0, maxWidth)
	local height = textSize.Y + padY * 2
	return width, height
end

-- Update the tooltip’s position to follow the mouse while staying on-screen.
function TooltipModule:_updatePosition(mouseX, mouseY)
	local width, height = self:_calculateSize()
	local cam = workspace.CurrentCamera
	if not cam then
		return
	end
	local viewport = cam.ViewportSize
	local offsetX = self._options.offset.X
	local offsetY = self._options.offset.Y
	local targetX = mouseX + offsetX
	local targetY = mouseY + offsetY
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
	self._text = self._options.text
	self._gui, self._frame, self._label = createGui(self._options)
	self._isVisible = false
	self._pendingShow = nil
	self._fadeTween = nil
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
	self._label.Text = self._text
	local mousePos = UserInputService:GetMouseLocation()
	self:_updatePosition(mousePos.X, mousePos.Y)
	self._frame.Visible = true
	if self._fadeTween then
		self._fadeTween:Cancel()
	end
	-- Set initial transparency for fade-in
	self._frame.BackgroundTransparency = 1
	self._label.TextTransparency = 1
	if self._frame:FindFirstChildOfClass("UIStroke") then
		self._frame.UIStroke.Transparency = 1
	end
	local tweenInfo = TweenInfo.new(self._options.fadeInDuration, Enum.EasingStyle.Linear, Enum.EasingDirection.Out)
	self._fadeTween = TweenService:Create(self._frame, tweenInfo, {
		BackgroundTransparency = self._options.backgroundTransparency,
	})
	local textTween = TweenService:Create(self._label, tweenInfo, {
		TextTransparency = 0,
	})
	local strokeTween
	if self._frame:FindFirstChildOfClass("UIStroke") then
		strokeTween = TweenService:Create(self._frame.UIStroke, tweenInfo, {
			Transparency = self._options.strokeTransparency,
		})
	end
	self._fadeTween:Play()
	textTween:Play()
	if strokeTween then
		strokeTween:Play()
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
		local tweenInfo =
			TweenInfo.new(self._options.fadeOutDuration, Enum.EasingStyle.Linear, Enum.EasingDirection.Out)
		local fadeOut = TweenService:Create(self._frame, tweenInfo, {
			BackgroundTransparency = 1,
		})
		local textFade = TweenService:Create(self._label, tweenInfo, {
			TextTransparency = 1,
		})
		local strokeFade
		if self._frame:FindFirstChildOfClass("UIStroke") then
			strokeFade = TweenService:Create(self._frame.UIStroke, tweenInfo, {
				Transparency = 1,
			})
		end
		fadeOut.Completed:Connect(function()
			self._frame.Visible = false
			self._gui.Parent = nil
		end)
		fadeOut:Play()
		textFade:Play()
		if strokeFade then
			strokeFade:Play()
		end
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
	if self._isVisible then
		self._label.Text = newText
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
	end
	self._frame.BackgroundColor3 = self._options.backgroundColor3
	if not self._isVisible then
		self._frame.BackgroundTransparency = 1
		self._label.TextTransparency = 1
		if self._frame:FindFirstChildOfClass("UIStroke") then
			self._frame.UIStroke.Transparency = 1
		end
	end
	self._label.TextColor3 = self._options.textColor3
	self._label.Font = self._options.font
	self._label.TextSize = self._options.textSize
	if self._frame:FindFirstChildOfClass("UICorner") then
		self._frame.UICorner.CornerRadius = self._options.cornerRadius
	end
	if self._frame:FindFirstChildOfClass("UIStroke") then
		local stroke = self._frame.UIStroke
		stroke.Color = self._options.strokeColor3
		stroke.Transparency = self._options.strokeTransparency
		stroke.Thickness = self._options.strokeThickness
	end
	local pad = self._frame:FindFirstChildOfClass("UIPadding")
	if pad then
		pad.PaddingLeft = UDim.new(0, self._options.padding.X)
		pad.PaddingRight = UDim.new(0, self._options.padding.X)
		pad.PaddingTop = UDim.new(0, self._options.padding.Y)
		pad.PaddingBottom = UDim.new(0, self._options.padding.Y)
	end
end

-- Return whether the tooltip is currently visible.
function TooltipModule:IsVisible()
	return self._isVisible
end

return TooltipModule
