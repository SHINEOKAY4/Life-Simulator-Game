--!strict
--[[
    NotificationModule.lua

    A lightweight, modular, and stateless toast/notification utility for Roblox experiences.

    ## Overview

    This module exposes a single function, `Show`, for creating toast‑style notifications
    for players. Each notification is represented by a self‑contained GUI tree and is
    independently managed – there is no persistent state between calls beyond the
    internal registry of active toasts. Notifications appear anchored to the top‑right
    of the player’s `PlayerGui` and gracefully fade in and out using TweenService.

    Notifications may include an optional icon, configurable background and text
    colors, an arbitrary number of buttons (each with its own callback), custom
    duration (or be indefinite), a sound that plays on show, and priority for
    stacking. Higher priority notifications automatically appear above lower priority
    ones.  The module uses typed definitions throughout and runs under `--!strict`
    Luau mode, ensuring API correctness and clarity.

    ## Usage

        local NotificationModule = require(path.to.NotificationModule)

        NotificationModule.Show({
            Title = "Quest Complete!",
            Text  = "You have earned 100 coins.",
            Icon  = "rbxassetid://123456", -- optional
            Duration = 4, -- optional, defaults to 5 seconds
            BackgroundColor = Color3.fromRGB(30, 144, 255),
            Buttons = {
                {
                    Text = "Collect",
                    Callback = function(handle)
                        print("Player collected reward!")
                        -- handle.Dismiss() -- optional manual dismissal
                    end,
                },
            },
            SoundId = "rbxassetid://6026984225", -- optional sound to play on show
            Priority = 2, -- larger values appear above lower values
        })

    ## Notes

    * Notifications are client‑side only; they must be required from a LocalScript.
    * Duration values of `nil` or `<= 0` will cause a notification to persist until
      explicitly dismissed via its button callbacks or by calling the returned
      handle’s `Dismiss` method.
    * This module intentionally avoids any dependencies besides core Roblox
      services and does not rely on external libraries.
]]

-- Type definitions
export type NotificationButton = {
	-- Text displayed on the button.
	Text: string,
	-- Optional callback invoked when the button is clicked.  The callback
	-- receives a NotificationHandle allowing manual dismissal.
	Callback: ((NotificationHandle) -> ())?,
}

export type NotificationOptions = {
	-- The title text displayed at the top of the notification. Required.
	Title: string,
	-- The body text describing the notification. Required.
	Text: string,
	-- An optional image to display on the left side of the notification.
	-- Should be a Roblox asset URI (e.g. "rbxassetid://...").
	Icon: string?,
	-- How long (in seconds) the notification should stay on screen. A value
	-- of `nil` or `<= 0` makes the notification persistent until dismissed.
	Duration: number?,
	-- Zero or more buttons to display beneath the body text.
	Buttons: { NotificationButton }?,
	-- A non‑negative integer indicating the notification’s priority. Higher
	-- priority notifications appear above lower priority ones. Default 0.
	Priority: number?,
	-- Background color for the notification panel.  If omitted a dark gray theme is used.
	BackgroundColor: Color3?,
	-- Color used for the title and message text. Defaults to white for the
	-- title and light gray for the body.
	TextColor: Color3?,
	-- Font used by the title and message labels. Defaults to Gotham fonts.
	Font: Enum.Font?,
	-- Optional sound asset to play when the notification appears.
	SoundId: string?,
}

export type NotificationHandle = {
	-- Dismisses the notification immediately.  The handle becomes invalid after dismissal.
	Dismiss: () -> (),
}

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")

-- Internal module table
local NotificationModule = {}

-- Container for all active notifications.  Lazily created on the first call to Show().
local _containerGui: ScreenGui? = nil
-- Panel within the container that holds individual toast CanvasGroups.
local stackFrame: Frame? = nil
-- Counter for assigning unique LayoutOrder values.  Incremented for each notification.
local nextOrder: number = 0
-- Registry of active notification handles.  Used to track and dismiss toasts.
local activeToasts: { [CanvasGroup]: boolean } = {}

-- Constants controlling layout and appearance.
local PADDING: number = 8
local MAX_WIDTH: number = 320
local CORNER_RADIUS: number = 8
local TEXT_PADDING: number = 6
local BUTTON_HEIGHT: number = 28
local BUTTON_MIN_WIDTH: number = 80

-- Ensure the container ScreenGui and stack frame exist; create them lazily.
local function ensureContainer(): Frame
	if stackFrame then
		return stackFrame
	end

	local localPlayer = Players.LocalPlayer
	assert(localPlayer, "NotificationModule must be used from a LocalScript")
	local playerGui = localPlayer:WaitForChild("PlayerGui")

	local gui = Instance.new("ScreenGui")
	gui.Name = "_NotificationModuleGui"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 10000
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Global
	gui.Parent = playerGui
	_containerGui = gui

	local frame = Instance.new("Frame")
	frame.Name = "StackFrame"
	frame.BackgroundTransparency = 1
	frame.ClipsDescendants = false
	frame.AutomaticSize = Enum.AutomaticSize.Y
	frame.Size = UDim2.fromOffset(MAX_WIDTH, 0)
	frame.AnchorPoint = Vector2.new(1, 0)
	frame.Position = UDim2.new(1, -PADDING, 0, PADDING)
	frame.Parent = gui
	stackFrame = frame

	local listLayout = Instance.new("UIListLayout")
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Padding = UDim.new(0, PADDING)
	listLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	listLayout.VerticalAlignment = Enum.VerticalAlignment.Top
	listLayout.Parent = frame

	return frame
end

-- Play a sound if provided.  The sound is cleaned up automatically.
local function playSound(soundId: string?)
	if soundId == nil or soundId == "" then
		return
	end
	local sound = Instance.new("Sound")
	sound.SoundId = soundId
	sound.Volume = 1
	sound.PlayOnRemove = false
	sound.Parent = SoundService
	sound.Ended:Once(function()
		sound:Destroy()
	end)
	sound:Play()
end

-- Create a single toast CanvasGroup based on options.
local function createToast(options: NotificationOptions): CanvasGroup
	local parentFrame = ensureContainer()

	-- Root CanvasGroup for the toast. Allows tweening group transparency.
	local toast = Instance.new("CanvasGroup")
	toast.Name = "Toast"
	toast.AutomaticSize = Enum.AutomaticSize.Y
	toast.Size = UDim2.fromScale(1, 0)
	toast.GroupTransparency = 1
	toast.Parent = parentFrame

	-- Assign layout order: negative priority ensures higher priority appears above.
	nextOrder += 1
	local priority = options.Priority or 0
	toast.LayoutOrder = -priority * 1000 + nextOrder

	-- Main panel
	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.BackgroundTransparency = 0
	panel.BackgroundColor3 = options.BackgroundColor or Color3.fromRGB(33, 33, 33)
	panel.AutomaticSize = Enum.AutomaticSize.Y
	panel.Size = UDim2.fromScale(1, 0)
	panel.Parent = toast

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, CORNER_RADIUS)
	corner.Parent = panel

	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 1
	stroke.Color = options.BackgroundColor and options.BackgroundColor:Lerp(Color3.new(1, 1, 1), 0.2)
		or Color3.fromRGB(255, 255, 255)
	stroke.Transparency = 0.9
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = panel

	-- Horizontal content container
	local content = Instance.new("Frame")
	content.Name = "Content"
	content.BackgroundTransparency = 1
	content.AutomaticSize = Enum.AutomaticSize.Y
	content.Size = UDim2.new(1, -2 * PADDING, 0, 0)
	content.Position = UDim2.fromOffset(PADDING, PADDING)
	content.Parent = panel

	local horizontalLayout = Instance.new("UIListLayout")
	horizontalLayout.FillDirection = Enum.FillDirection.Horizontal
	horizontalLayout.SortOrder = Enum.SortOrder.LayoutOrder
	horizontalLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	horizontalLayout.VerticalAlignment = Enum.VerticalAlignment.Top
	horizontalLayout.Padding = UDim.new(0, TEXT_PADDING)
	horizontalLayout.Parent = content

	-- Optional icon
	if options.Icon then
		local iconImage = Instance.new("ImageLabel")
		iconImage.Name = "Icon"
		iconImage.BackgroundTransparency = 1
		iconImage.Size = UDim2.fromOffset(32, 32)
		iconImage.Image = options.Icon
		iconImage.ImageColor3 = Color3.new(1, 1, 1)
		iconImage.Parent = content
		local iconAspect = Instance.new("UIAspectRatioConstraint")
		iconAspect.AspectRatio = 1
		iconAspect.Parent = iconImage
	end

	-- Vertical stack for title, body, and buttons
	local textStack = Instance.new("Frame")
	textStack.Name = "TextStack"
	textStack.BackgroundTransparency = 1
	textStack.AutomaticSize = Enum.AutomaticSize.Y
	textStack.Size = UDim2.fromScale(1, 0)
	textStack.Parent = content

	local verticalLayout = Instance.new("UIListLayout")
	verticalLayout.FillDirection = Enum.FillDirection.Vertical
	verticalLayout.SortOrder = Enum.SortOrder.LayoutOrder
	verticalLayout.Padding = UDim.new(0, TEXT_PADDING)
	verticalLayout.Parent = textStack

	-- Title label
	local titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "Title"
	titleLabel.BackgroundTransparency = 1
	titleLabel.Text = options.Title
	titleLabel.TextWrapped = true
	titleLabel.AutomaticSize = Enum.AutomaticSize.Y
	titleLabel.Size = UDim2.fromScale(1, 0)
	titleLabel.Font = options.Font or Enum.Font.GothamMedium
	titleLabel.TextSize = 16
	titleLabel.TextColor3 = options.TextColor or Color3.fromRGB(255, 255, 255)
	titleLabel.Parent = textStack

	-- Body label
	local bodyLabel = Instance.new("TextLabel")
	bodyLabel.Name = "Body"
	bodyLabel.BackgroundTransparency = 1
	bodyLabel.Text = options.Text
	bodyLabel.TextWrapped = true
	bodyLabel.AutomaticSize = Enum.AutomaticSize.Y
	bodyLabel.Size = UDim2.fromScale(1, 0)
	bodyLabel.Font = options.Font or Enum.Font.Gotham
	bodyLabel.TextSize = 14
	if options.TextColor then
		bodyLabel.TextColor3 = options.TextColor:Lerp(Color3.new(1, 1, 1), 0.2)
	else
		bodyLabel.TextColor3 = Color3.fromRGB(220, 220, 220)
	end
	bodyLabel.Parent = textStack

	-- Buttons (optional)
	if options.Buttons and #options.Buttons > 0 then
		local buttonContainer = Instance.new("Frame")
		buttonContainer.Name = "ButtonContainer"
		buttonContainer.BackgroundTransparency = 1
		buttonContainer.AutomaticSize = Enum.AutomaticSize.Y
		buttonContainer.Size = UDim2.fromScale(1, 0)
		buttonContainer.Parent = textStack

		local buttonLayout = Instance.new("UIListLayout")
		buttonLayout.FillDirection = Enum.FillDirection.Horizontal
		buttonLayout.SortOrder = Enum.SortOrder.LayoutOrder
		buttonLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
		buttonLayout.VerticalAlignment = Enum.VerticalAlignment.Top
		buttonLayout.Padding = UDim.new(0, TEXT_PADDING)
		buttonLayout.Parent = buttonContainer

		for _, btn in ipairs(options.Buttons) do
			local b = Instance.new("TextButton")
			b.Name = "Button"
			b.BackgroundTransparency = 0
			b.AutoButtonColor = false
			b.Text = btn.Text
			b.TextWrapped = true
			b.TextSize = 14
			b.Font = options.Font or Enum.Font.GothamMedium
			b.TextColor3 = options.TextColor or Color3.fromRGB(255, 255, 255)
			b.BackgroundColor3 = (options.BackgroundColor or Color3.fromRGB(33, 33, 33)):Lerp(Color3.new(0, 0, 0), 0.2)
			b.Size = UDim2.fromOffset(BUTTON_MIN_WIDTH, BUTTON_HEIGHT)
			b.Parent = buttonContainer

			local bCorner = Instance.new("UICorner")
			bCorner.CornerRadius = UDim.new(0, CORNER_RADIUS / 2)
			bCorner.Parent = b

			b.MouseButton1Click:Connect(function()
				playSound(options.SoundId)
				if btn.Callback then
					btn.Callback({
						Dismiss = function()
							NotificationModule.Dismiss(toast)
						end,
					})
				else
					NotificationModule.Dismiss(toast)
				end
			end)
		end
	end

	return toast
end

-- Animate a toast into view, schedule dismissal if needed, and return a handle.
local function showToast(options: NotificationOptions): NotificationHandle
	local toast = createToast(options)
	activeToasts[toast] = true

	playSound(options.SoundId)

	local fadeIn = TweenService:Create(
		toast,
		TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ GroupTransparency = 0 }
	)
	fadeIn:Play()

	local isDismissed = false
	local function dismiss()
		if isDismissed then
			return
		end
		isDismissed = true
		activeToasts[toast] = nil
		local fadeOut = TweenService:Create(
			toast,
			TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ GroupTransparency = 1 }
		)
		fadeOut:Play()
		fadeOut.Completed:Once(function()
			toast:Destroy()
		end)
	end

	if options.Duration and options.Duration > 0 then
		task.delay(options.Duration, function()
			if not isDismissed then
				dismiss()
			end
		end)
	end

	return {
		Dismiss = dismiss,
	} :: NotificationHandle
end

-- Public API: Show a notification.  Returns a handle for manual dismissal.
function NotificationModule.Show(options: NotificationOptions): NotificationHandle
	assert(options ~= nil, "Notification options must be provided")
	assert(type(options.Title) == "string" and options.Title ~= "", "Notification Title must be a non‑empty string")
	assert(type(options.Text) == "string" and options.Text ~= "", "Notification Text must be a non‑empty string")
	return showToast(options)
end

-- Public API: Dismiss a specific toast if it is still active.
function NotificationModule.Dismiss(handle: any)
	if typeof(handle) == "table" and typeof(handle.Dismiss) == "function" then
		handle.Dismiss()
	elseif typeof(handle) == "Instance" and handle:IsA("CanvasGroup") then
		local toast = handle :: CanvasGroup
		if not activeToasts[toast] then
			return
		end
		local fadeOut = TweenService:Create(
			toast,
			TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ GroupTransparency = 1 }
		)
		fadeOut:Play()
		fadeOut.Completed:Once(function()
			toast:Destroy()
		end)
		activeToasts[toast] = nil
	end
end

-- Public API: Immediately dismiss all active notifications.
function NotificationModule.ClearAll()
	for toast, _ in pairs(activeToasts) do
		NotificationModule.Dismiss(toast)
	end
end

return NotificationModule
